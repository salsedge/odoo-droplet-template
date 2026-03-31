#!/usr/bin/env bash
# =============================================================================
# set-domain.sh — Change Primary Domain (Operational)
# =============================================================================
# Changes the primary domain for the Odoo instance. Optionally keeps an alias
# domain that 301-redirects to the new primary.
#
# This is a day-2 operational script, not part of the initial deploy sequence.
# It lives in scripts/ops/ to distinguish it from the numbered deploy scripts.
#
# What it does:
#   1. Verifies DNS resolution for the primary domain
#   2. Expands (or issues) SSL certificate via certbot webroot
#   3. Detects the actual certificate path from certbot
#   4. Deploys the appropriate Nginx config (multi-domain or single-domain)
#   5. Tests and reloads Nginx (with rollback on failure)
#   6. Updates Odoo web.base.url (skips if already correct)
#   7. Restarts Odoo only if web.base.url changed
#
# Prerequisites:
#   - DNS A record(s) pointing to this server's public IP
#   - Nginx and certbot already installed (via 04-setup-nginx.sh)
#   - Odoo stack running (via 03-deploy-stack.sh)
#   - /opt/odoo/.env with POSTGRES_USER, POSTGRES_DB
#
# Usage:
#   sudo bash scripts/ops/set-domain.sh <primary-domain> <cert-email> [alias-domain]
#
# Examples:
#   sudo bash scripts/ops/set-domain.sh portal.loodon.com admin@loodon.com odoo.loodon.com
#   sudo bash scripts/ops/set-domain.sh portal.loodon.com admin@loodon.com
#
# Idempotent: safe to re-run. Skips Odoo restart if web.base.url already correct.
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")/config}"
CERTBOT_WEBROOT="/var/www/certbot"
NGINX_CONF="/etc/nginx/sites-available/odoo.conf"
NGINX_BACKUP=""
ODOO_ENV="/opt/odoo/.env"
TOTAL_STEPS=7

# =============================================================================
# Cleanup / rollback trap
# =============================================================================
cleanup() {
  local exit_code=$?
  if [[ -n "$NGINX_BACKUP" && -f "$NGINX_BACKUP" ]]; then
    echo ""
    echo "ERROR: Script failed — restoring previous Nginx config"
    mv "$NGINX_BACKUP" "$NGINX_CONF"
    if nginx -t 2>/dev/null; then
      systemctl reload nginx 2>/dev/null
      echo "  Previous Nginx config restored and reloaded."
    else
      echo "  WARNING: Could not restore Nginx config. Manual intervention required."
      echo "  Check: /etc/nginx/sites-available/odoo.conf"
    fi
  fi
  exit "$exit_code"
}
trap cleanup ERR

# =============================================================================
# Argument parsing
# =============================================================================
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <primary-domain> <cert-email> [alias-domain]" >&2
  echo "" >&2
  echo "  primary-domain  FQDN for the Odoo instance (e.g., portal.loodon.com)" >&2
  echo "  cert-email      Email for Let's Encrypt notifications" >&2
  echo "  alias-domain    Optional old domain that 301-redirects to primary" >&2
  exit 1
fi

PRIMARY_DOMAIN="$1"
CERT_EMAIL="$2"
ALIAS_DOMAIN="${3:-}"

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (or via sudo)" >&2
  exit 1
fi

echo "=== Domain Change: set-domain.sh ==="
echo "  Primary: ${PRIMARY_DOMAIN}"
echo "  Email:   ${CERT_EMAIL}"
echo "  Alias:   ${ALIAS_DOMAIN:-'(none)'}"
echo ""

# Verify required config files exist
if [[ -n "$ALIAS_DOMAIN" ]]; then
  if [[ ! -f "${CONFIG_DIR}/nginx/odoo-multidomain.conf" ]]; then
    echo "ERROR: Missing config file: ${CONFIG_DIR}/nginx/odoo-multidomain.conf" >&2
    exit 1
  fi
else
  if [[ ! -f "${CONFIG_DIR}/nginx/odoo.conf" ]]; then
    echo "ERROR: Missing config file: ${CONFIG_DIR}/nginx/odoo.conf" >&2
    exit 1
  fi
fi

# Verify .env exists for Postgres credentials
if [[ ! -f "$ODOO_ENV" ]]; then
  echo "ERROR: ${ODOO_ENV} not found — cannot update Odoo web.base.url" >&2
  exit 1
fi

# =============================================================================
# Step 1: Verify DNS resolution
# =============================================================================
echo "[1/${TOTAL_STEPS}] Checking DNS for ${PRIMARY_DOMAIN}..."

RESOLVED_IP=$(dig +short "${PRIMARY_DOMAIN}" A 2>/dev/null | tail -1)
SERVER_IP=$(curl -s -4 --connect-timeout 5 ifconfig.me 2>/dev/null \
  || curl -s -4 --connect-timeout 5 icanhazip.com 2>/dev/null)

if [[ -z "$RESOLVED_IP" ]]; then
  echo "  ERROR: DNS lookup for ${PRIMARY_DOMAIN} returned no results." >&2
  echo "  Ensure the A record is set and DNS has propagated." >&2
  echo "  Verify with: dig ${PRIMARY_DOMAIN}" >&2
  exit 1
fi

if [[ "$RESOLVED_IP" != "$SERVER_IP" ]]; then
  echo "  WARNING: ${PRIMARY_DOMAIN} resolves to ${RESOLVED_IP}" >&2
  echo "           This server's public IP is ${SERVER_IP}" >&2
  echo "  Certbot HTTP-01 challenge will fail if DNS doesn't point here." >&2
  echo "  Continuing — certbot will produce a clear error if mismatched." >&2
else
  echo "  OK (${RESOLVED_IP})"
fi

# =============================================================================
# Step 2: Expand/issue SSL certificate (webroot method)
# =============================================================================
echo "[2/${TOTAL_STEPS}] Expanding SSL certificate..."

CERTBOT_ARGS=(
  certonly
  --webroot
  --webroot-path "${CERTBOT_WEBROOT}"
  -d "${PRIMARY_DOMAIN}"
  --non-interactive
  --agree-tos
  --email "${CERT_EMAIL}"
)

if [[ -n "$ALIAS_DOMAIN" ]]; then
  CERTBOT_ARGS+=(-d "${ALIAS_DOMAIN}" --expand)
fi

# --keep-until-expiring: if cert already covers these domains, skip issuance
CERTBOT_ARGS+=(--keep-until-expiring)

certbot "${CERTBOT_ARGS[@]}"
echo "  OK"

# =============================================================================
# Step 3: Detect certificate path
# =============================================================================
echo "[3/${TOTAL_STEPS}] Detecting certificate path..."

# Parse certbot certificates output to find the cert that covers our primary domain
CERT_NAME=""
while IFS= read -r line; do
  if [[ "$line" =~ Certificate\ Name:\ (.+) ]]; then
    current_name="${BASH_REMATCH[1]}"
  fi
  if [[ "$line" =~ Domains:\ (.+) ]]; then
    domains="${BASH_REMATCH[1]}"
    if echo "$domains" | grep -qw "${PRIMARY_DOMAIN}"; then
      CERT_NAME="$current_name"
      break
    fi
  fi
done < <(certbot certificates 2>/dev/null)

if [[ -z "$CERT_NAME" ]]; then
  echo "  ERROR: Could not detect certificate path for ${PRIMARY_DOMAIN}" >&2
  echo "  The SSL certificate was issued but the path could not be parsed." >&2
  echo "  Run 'sudo certbot certificates' and update Nginx config manually." >&2
  exit 1
fi

CERT_PATH="/etc/letsencrypt/live/${CERT_NAME}"
echo "  ${CERT_PATH}"

# Verify the cert files actually exist
if [[ ! -f "${CERT_PATH}/fullchain.pem" || ! -f "${CERT_PATH}/privkey.pem" ]]; then
  echo "  ERROR: Certificate files not found at ${CERT_PATH}" >&2
  echo "  Expected: ${CERT_PATH}/fullchain.pem and ${CERT_PATH}/privkey.pem" >&2
  exit 1
fi

# =============================================================================
# Step 4: Back up current Nginx config
# =============================================================================
echo "[4/${TOTAL_STEPS}] Backing up Nginx config..."

if [[ -f "$NGINX_CONF" ]]; then
  NGINX_BACKUP="${NGINX_CONF}.bak.$(date +%s)"
  cp "$NGINX_CONF" "$NGINX_BACKUP"
  echo "  ${NGINX_BACKUP}"
else
  echo "  No existing config to back up"
fi

# =============================================================================
# Step 5: Deploy Nginx config
# =============================================================================
echo "[5/${TOTAL_STEPS}] Deploying Nginx config..."

if [[ -n "$ALIAS_DOMAIN" ]]; then
  # Multi-domain: primary + alias redirect
  sed -e "s/PRIMARY_DOMAIN/${PRIMARY_DOMAIN}/g" \
      -e "s/ALIAS_DOMAIN/${ALIAS_DOMAIN}/g" \
      -e "s|CERT_NAME|${CERT_NAME}|g" \
      "${CONFIG_DIR}/nginx/odoo-multidomain.conf" \
      > "$NGINX_CONF"
  echo "  Multi-domain config: ${PRIMARY_DOMAIN} + ${ALIAS_DOMAIN} (redirect)"
else
  # Single-domain: use existing template
  sed "s/DOMAIN_PLACEHOLDER/${PRIMARY_DOMAIN}/g" \
      "${CONFIG_DIR}/nginx/odoo.conf" \
      > "$NGINX_CONF"
  echo "  Single-domain config: ${PRIMARY_DOMAIN}"
fi

# Fix cert paths to use detected CERT_NAME (for single-domain template too)
sed -i "s|/etc/letsencrypt/live/DOMAIN_PLACEHOLDER|/etc/letsencrypt/live/${CERT_NAME}|g" \
    "$NGINX_CONF" 2>/dev/null || true

chmod 644 "$NGINX_CONF"

# =============================================================================
# Step 6: Test and reload Nginx
# =============================================================================
echo "[6/${TOTAL_STEPS}] Testing Nginx config..."

if ! nginx -t 2>&1; then
  echo ""
  echo "  ERROR: Nginx config test failed — restoring previous config" >&2
  if [[ -n "$NGINX_BACKUP" && -f "$NGINX_BACKUP" ]]; then
    mv "$NGINX_BACKUP" "$NGINX_CONF"
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
    echo "  Previous config restored and reloaded." >&2
    NGINX_BACKUP=""  # Prevent trap from double-restoring
  fi
  echo "" >&2
  echo "  The SSL certificate was expanded but Nginx was NOT updated." >&2
  echo "  Fix the config template and re-run this script." >&2
  exit 1
fi

systemctl reload nginx
echo "  OK — reloaded"

# Nginx is good — remove backup, clear trap target
rm -f "$NGINX_BACKUP"
NGINX_BACKUP=""

# =============================================================================
# Step 7: Update Odoo web.base.url
# =============================================================================
echo "[7/${TOTAL_STEPS}] Updating Odoo web.base.url..."

# Read Postgres credentials from .env (grep, not source — passwords may contain
# characters that bash interprets as commands when sourced)
POSTGRES_USER=$(grep -E '^POSTGRES_USER=' "$ODOO_ENV" | head -1 | cut -d= -f2-)
POSTGRES_DB=$(grep -E '^POSTGRES_DB=' "$ODOO_ENV" | head -1 | cut -d= -f2-)

if [[ -z "$POSTGRES_USER" || -z "$POSTGRES_DB" ]]; then
  echo "  ERROR: Could not read POSTGRES_USER or POSTGRES_DB from ${ODOO_ENV}" >&2
  exit 1
fi

EXPECTED_URL="https://${PRIMARY_DOMAIN}"

CURRENT_URL=$(docker exec odoo-db psql -t -A \
  -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  -c "SELECT value FROM ir_config_parameter WHERE key = 'web.base.url';" 2>/dev/null || echo "")

if [[ "$CURRENT_URL" == "$EXPECTED_URL" ]]; then
  echo "  Already set to ${EXPECTED_URL} — skipping Odoo restart"
else
  docker exec odoo-db psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
    "UPDATE ir_config_parameter SET value = '${EXPECTED_URL}' WHERE key = 'web.base.url';" \
    > /dev/null

  echo "  Updated: ${CURRENT_URL:-'(empty)'} -> ${EXPECTED_URL}"
  echo "  Restarting Odoo..."
  docker restart odoo-app > /dev/null
  echo "  Odoo restarted"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Domain change complete ==="
echo "  Primary: https://${PRIMARY_DOMAIN}"
if [[ -n "$ALIAS_DOMAIN" ]]; then
  echo "  Alias:   https://${ALIAS_DOMAIN} -> 301 redirect"
fi
echo ""
echo "Verify:"
echo "  curl -sI https://${PRIMARY_DOMAIN} | head -5"
if [[ -n "$ALIAS_DOMAIN" ]]; then
  echo "  curl -sI https://${ALIAS_DOMAIN} | head -5  # Should show 301"
fi
echo "  curl -sI https://${PRIMARY_DOMAIN} | grep -i strict  # HSTS header"
echo "  sudo certbot certificates  # Both domains on one cert"
