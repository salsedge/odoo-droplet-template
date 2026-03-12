#!/usr/bin/env bash
# =============================================================================
# 04-setup-nginx.sh — Nginx Reverse Proxy & Let's Encrypt SSL
# =============================================================================
# Requirements: PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05
#
# Installs Nginx, obtains SSL certificate via certbot HTTP-01 challenge,
# and configures the full reverse proxy with security headers.
#
# Prerequisites:
#   - DNS A record pointing domain to droplet public IP
#   - 01-harden-host.sh completed (UFW allows 80/443)
#   - 03-deploy-stack.sh completed (Odoo running on 127.0.0.1:8069)
#
# Usage:
#   sudo bash scripts/04-setup-nginx.sh <domain> [email]
#   Example: sudo bash scripts/04-setup-nginx.sh odoo.example.com admin@example.com
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/config}"
CERTBOT_WEBROOT="/var/www/certbot"

# =============================================================================
# Argument parsing
# =============================================================================
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <domain> [email]" >&2
  echo "  domain  — FQDN for the Odoo instance (e.g., odoo.example.com)" >&2
  echo "  email   — Email for Let's Encrypt notifications (optional)" >&2
  exit 1
fi

DOMAIN="$1"
EMAIL="${2:-}"

echo "=== Phase 2 / Plan 02-03: Nginx + SSL Setup ==="
echo "Domain: ${DOMAIN}"
echo "Email:  ${EMAIL:-'(not provided, using --register-unsafely-without-email)'}"

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Verify config files exist
for f in nginx/odoo-pre-ssl.conf nginx/odoo.conf; do
  if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
    echo "ERROR: Missing config file: ${CONFIG_DIR}/${f}" >&2
    exit 1
  fi
done

# Verify DNS resolves to this server (prevents wasted certbot rate-limited attempts)
echo "--- Verifying DNS resolution for ${DOMAIN} ---"
RESOLVED_IP=$(dig +short "${DOMAIN}" A 2>/dev/null | tail -1)
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)

if [[ -z "${RESOLVED_IP}" ]]; then
  echo "ERROR: DNS lookup for ${DOMAIN} returned no results." >&2
  echo "  Ensure the A record is set and DNS has propagated." >&2
  echo "  Verify with: dig ${DOMAIN}" >&2
  exit 1
fi

if [[ "${RESOLVED_IP}" != "${SERVER_IP}" ]]; then
  echo "WARNING: ${DOMAIN} resolves to ${RESOLVED_IP}, but this server's public IP is ${SERVER_IP}" >&2
  echo "  Certbot HTTP-01 challenge will fail if DNS doesn't point here." >&2
  echo "  Continuing anyway -- certbot will fail with a clear error if mismatched." >&2
fi

# =============================================================================
# Step 1: Install Nginx and Certbot
# =============================================================================
echo "--- Installing Nginx and Certbot (PROXY-01, PROXY-02) ---"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q nginx certbot python3-certbot-nginx

# Stop Nginx during initial config
systemctl stop nginx

# =============================================================================
# Step 2: Deploy pre-SSL config for HTTP-01 challenge
# =============================================================================
echo "--- Deploying pre-SSL Nginx config ---"

# Create certbot webroot
mkdir -p "${CERTBOT_WEBROOT}"

# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Deploy pre-SSL config with domain substituted
sed "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" "${CONFIG_DIR}/nginx/odoo-pre-ssl.conf" \
  > /etc/nginx/sites-available/odoo.conf

ln -sf /etc/nginx/sites-available/odoo.conf /etc/nginx/sites-enabled/odoo.conf

# Set permissions (HARD-06)
chmod 644 /etc/nginx/sites-available/odoo.conf

# Test and start Nginx
nginx -t
systemctl start nginx
echo "Nginx started with pre-SSL config on port 80"

# =============================================================================
# Step 3: Obtain SSL certificate via HTTP-01 challenge
# =============================================================================
echo "--- Obtaining Let's Encrypt SSL certificate (PROXY-02) ---"

CERTBOT_ARGS=(
  certonly
  --webroot
  --webroot-path "${CERTBOT_WEBROOT}"
  -d "${DOMAIN}"
  --non-interactive
  --agree-tos
)

if [[ -n "${EMAIL}" ]]; then
  CERTBOT_ARGS+=(--email "${EMAIL}")
else
  CERTBOT_ARGS+=(--register-unsafely-without-email)
fi

certbot "${CERTBOT_ARGS[@]}"

echo "SSL certificate obtained for ${DOMAIN}"

# =============================================================================
# Step 4: Deploy full SSL Nginx config
# =============================================================================
echo "--- Deploying full SSL Nginx config (PROXY-01, PROXY-03, PROXY-04) ---"

# Substitute domain placeholder in the full SSL config
sed "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" "${CONFIG_DIR}/nginx/odoo.conf" \
  > /etc/nginx/sites-available/odoo.conf

# Set permissions (HARD-06)
chmod 644 /etc/nginx/sites-available/odoo.conf

# Test and reload Nginx
nginx -t
systemctl reload nginx
echo "Nginx reloaded with full SSL configuration"

# =============================================================================
# Step 5: Configure certbot auto-renewal via systemd timer (PROXY-05)
# =============================================================================
echo "--- Configuring certbot auto-renewal timer (PROXY-05) ---"

# Create systemd service for certbot renewal
cat > /etc/systemd/system/certbot-renewal.service << 'UNIT'
[Unit]
Description=Certbot Let's Encrypt certificate renewal
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx"
UNIT

# Create systemd timer (runs twice daily as recommended by Let's Encrypt)
cat > /etc/systemd/system/certbot-renewal.timer << 'UNIT'
[Unit]
Description=Run certbot renewal twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Enable and start the timer
systemctl daemon-reload
systemctl enable certbot-renewal.timer
systemctl start certbot-renewal.timer

echo "Certbot auto-renewal timer configured (runs twice daily)"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Nginx + SSL Setup Complete ==="
echo "  PROXY-01: Nginx reverse proxy to 127.0.0.1:8069"
echo "  PROXY-02: Let's Encrypt SSL via HTTP-01 challenge"
echo "  PROXY-03: HTTPS redirect + HSTS headers"
echo "  PROXY-04: /web/database/* blocked (403)"
echo "  PROXY-05: Certbot auto-renewal via systemd timer"
echo ""
echo "Odoo is now accessible at: https://${DOMAIN}"
echo ""
echo "Verify:"
echo "  curl -I https://${DOMAIN}  # Should show 200/302 with HSTS header"
echo "  curl -I https://${DOMAIN}/web/database  # Should show 403"
echo "  systemctl list-timers | grep certbot  # Should show next renewal"
