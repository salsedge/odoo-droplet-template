#!/usr/bin/env bash
# =============================================================================
# 04-setup-nginx.sh — Nginx Reverse Proxy & Let's Encrypt SSL
# =============================================================================
# Requirements: PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05
#
# Installs Nginx (nginx.org stable repo), obtains SSL certificate via certbot HTTP-01 challenge,
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

# nginx.org package layout: no sites-available/sites-enabled; nginx.conf only
# includes conf.d/*.conf, so the site config must live there to be loaded.
NGINX_SITE_CONF="/etc/nginx/conf.d/odoo.conf"
NGINX_MIN_VERSION="1.30.7"
NGINX_KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
# Published at https://nginx.org/en/linux_packages.html
NGINX_KEY_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"

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
for f in nginx/odoo-pre-ssl.conf nginx/odoo.conf nginx/nginx-restart-if-upgraded \
  apt/52unattended-upgrades-nginx-org apt/99nginx-restart-if-upgraded; do
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

# Refuse before any apt change: swapping to the nginx.org package removes Ubuntu's
# libnginx-mod-* dynamic modules, and anything that loads them would break with
# the old service already stopped. Migrate them deliberately first.
INSTALLED_NGINX_MODS="$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'libnginx-mod-*' 2>/dev/null \
  | awk '$1 == "ii" { print $2 }' || true)"
if [[ -n "${INSTALLED_NGINX_MODS}" ]]; then
  echo "ERROR: Ubuntu nginx dynamic modules are installed; the nginx.org swap would remove them:" >&2
  while IFS= read -r mod; do echo "  ${mod}" >&2; done <<< "${INSTALLED_NGINX_MODS}"
  echo "  No apt changes made. Migrate or remove these modules deliberately, then re-run." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl gnupg2 ca-certificates lsb-release ubuntu-keyring

# nginx comes from the nginx.org stable repo, not the Ubuntu archive: the distro
# package lags upstream security fixes (CVE-2026-123007, HTTP/2, fixed in 1.30.7).
# Steps follow https://nginx.org/en/linux_packages.html (Ubuntu section).
echo "--- Configuring nginx.org stable apt repository ---"

KEY_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${KEY_TMP_DIR}"' EXIT

curl -fsSL https://nginx.org/keys/nginx_signing.key \
  | gpg --dearmor > "${KEY_TMP_DIR}/nginx-archive-keyring.gpg"

# Fail closed: only install the keyring if it carries the fingerprint published
# on nginx.org. The file may hold other nginx signing keys too (expected).
if ! GNUPGHOME="${KEY_TMP_DIR}" gpg --dry-run --quiet --no-keyring --import \
    --import-options import-show --with-colons "${KEY_TMP_DIR}/nginx-archive-keyring.gpg" \
    | awk -F: '$1 == "fpr" { print $10 }' | grep -x "${NGINX_KEY_FINGERPRINT}" >/dev/null; then
  echo "ERROR: nginx signing key fingerprint mismatch (expected ${NGINX_KEY_FINGERPRINT})" >&2
  exit 1
fi
install -m 0644 "${KEY_TMP_DIR}/nginx-archive-keyring.gpg" "${NGINX_KEYRING}"

echo "deb [signed-by=${NGINX_KEYRING}] https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
  > /etc/apt/sources.list.d/nginx.list

# Pin so the Ubuntu nginx package can never win over nginx.org's
printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n' \
  > /etc/apt/preferences.d/99nginx

apt-get update -q
# --force-confnew: on a box that already had Ubuntu's nginx, take nginx.org's
# nginx.conf so the layout matches a fresh install (conf.d only, user nginx).
apt-get install -y -q -o Dpkg::Options::=--force-confnew \
  nginx certbot python3-certbot-nginx

# Assert the version floor: the CVE fix is the whole point of this step
NGINX_VERSION="$(nginx -v 2>&1 | sed -n 's|^nginx version: nginx/\([0-9.]*\).*|\1|p')"
if [[ -z "${NGINX_VERSION}" ]] \
  || [[ "$(printf '%s\n%s\n' "${NGINX_MIN_VERSION}" "${NGINX_VERSION}" | sort -V | head -1)" != "${NGINX_MIN_VERSION}" ]]; then
  echo "ERROR: nginx ${NGINX_VERSION:-unknown} is below required ${NGINX_MIN_VERSION}" >&2
  exit 1
fi
echo "nginx ${NGINX_VERSION} installed (>= ${NGINX_MIN_VERSION})"

# Keep it patched: unattended-upgrades only trusts Ubuntu origins by default. The
# hook restarts nginx when an upgrade replaced the binary but the package's own
# live swap failed (old vulnerable master still serving). Installed after the
# package swap so the hook cannot fire mid-migration from Ubuntu's nginx.
echo "--- Enabling nginx.org unattended upgrades + restart-on-upgrade hook ---"
install -m 0644 "${CONFIG_DIR}/apt/52unattended-upgrades-nginx-org" \
  /etc/apt/apt.conf.d/52unattended-upgrades-nginx-org
install -m 0755 "${CONFIG_DIR}/nginx/nginx-restart-if-upgraded" \
  /usr/local/sbin/nginx-restart-if-upgraded
install -m 0644 "${CONFIG_DIR}/apt/99nginx-restart-if-upgraded" \
  /etc/apt/apt.conf.d/99nginx-restart-if-upgraded

# Stop Nginx during initial config
systemctl stop nginx

# =============================================================================
# Step 2: Deploy pre-SSL config for HTTP-01 challenge
# =============================================================================
echo "--- Deploying pre-SSL Nginx config ---"

# Create certbot webroot
mkdir -p "${CERTBOT_WEBROOT}"

# Remove the stock default site so it cannot compete for default_server
rm -f /etc/nginx/conf.d/default.conf

# Boxes first built with Ubuntu's nginx: drop the old sites-enabled links so the
# site is not loaded twice (duplicate upstream) if an old nginx.conf survived.
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/odoo.conf

# Deploy pre-SSL config with domain substituted
sed "s/DOMAIN_PLACEHOLDER/${DOMAIN}/g" "${CONFIG_DIR}/nginx/odoo-pre-ssl.conf" \
  > "${NGINX_SITE_CONF}"

# Set permissions (HARD-06)
chmod 644 "${NGINX_SITE_CONF}"

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
  > "${NGINX_SITE_CONF}"

# Set permissions (HARD-06)
chmod 644 "${NGINX_SITE_CONF}"

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
