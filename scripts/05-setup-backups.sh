#!/usr/bin/env bash
# =============================================================================
# 05-setup-backups.sh — Install & Configure Backup Infrastructure
# =============================================================================
# Requirements: BACK-01, BACK-02, BACK-03, BACK-04
#
# Installs rclone and msmtp, deploys configuration templates with credential
# substitution from .env, copies backup/restore scripts, installs cron entries,
# and creates backup directories on Block Storage.
#
# Prerequisites:
#   - 03-deploy-stack.sh completed (Docker stack running)
#   - .env at /opt/odoo/.env with Spaces + SMTP credentials filled in
#   - Config files available in the same directory or specified via CONFIG_DIR
#
# Usage:
#   sudo bash scripts/05-setup-backups.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/config}"
DEPLOY_DIR="/opt/odoo"
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
RCLONE_REMOTE="${RCLONE_REMOTE:-spaces:odoo-prod-backups}"
ENV_FILE="${DEPLOY_DIR}/.env"

echo "=== Phase 3 / Plan 03-01: Backup Infrastructure Setup ==="

# =============================================================================
# Pre-flight checks
# =============================================================================

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Verify .env exists with required backup credentials
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found. Run 03-deploy-stack.sh first." >&2
  exit 1
fi

# Check for required backup credentials
MISSING_KEYS=()
for key in SPACES_ACCESS_KEY SPACES_SECRET_KEY SPACES_REGION SMTP_HOST SMTP_FROM ALERT_EMAIL; do
  if ! grep -q "^${key}=" "${ENV_FILE}"; then
    MISSING_KEYS+=("${key}")
  fi
done

if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
  echo "ERROR: Missing required keys in ${ENV_FILE}:" >&2
  printf '  %s\n' "${MISSING_KEYS[@]}" >&2
  echo "" >&2
  echo "Add backup credentials to ${ENV_FILE} (see config/.env.example)" >&2
  exit 1
fi

# =============================================================================
# Step 1: Install packages
# =============================================================================
echo "--- Installing rclone, msmtp, and mailutils ---"

apt-get update -qq
apt-get install -y rclone msmtp msmtp-mta mailutils

echo "  rclone: $(rclone version --check 2>/dev/null | head -1 || rclone version 2>/dev/null | head -1 || echo 'installed')"
echo "  msmtp:  $(msmtp --version 2>/dev/null | head -1 || echo 'installed')"

# =============================================================================
# Step 2: Extract credentials from .env (safe for special chars)
# =============================================================================
echo "--- Reading credentials from ${ENV_FILE} ---"

SPACES_ACCESS_KEY=$(grep '^SPACES_ACCESS_KEY=' "${ENV_FILE}" | cut -d'=' -f2-)
SPACES_SECRET_KEY=$(grep '^SPACES_SECRET_KEY=' "${ENV_FILE}" | cut -d'=' -f2-)
SPACES_REGION=$(grep '^SPACES_REGION=' "${ENV_FILE}" | cut -d'=' -f2-)
SMTP_HOST=$(grep '^SMTP_HOST=' "${ENV_FILE}" | cut -d'=' -f2-)
SMTP_PORT=$(grep '^SMTP_PORT=' "${ENV_FILE}" | cut -d'=' -f2- || echo "587")
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_FROM=$(grep '^SMTP_FROM=' "${ENV_FILE}" | cut -d'=' -f2-)
SMTP_USER=$(grep '^SMTP_USER=' "${ENV_FILE}" | cut -d'=' -f2- || true)
SMTP_PASSWORD=$(grep '^SMTP_PASSWORD=' "${ENV_FILE}" | cut -d'=' -f2- || true)
ALERT_EMAIL=$(grep '^ALERT_EMAIL=' "${ENV_FILE}" | cut -d'=' -f2-)

echo "  Spaces region: ${SPACES_REGION}"
echo "  SMTP host: ${SMTP_HOST}:${SMTP_PORT}"
echo "  Alert email: ${ALERT_EMAIL}"

# =============================================================================
# Step 3: Deploy rclone config (BACK-02)
# =============================================================================
echo "--- Deploying rclone configuration ---"

RCLONE_DEST="${DEPLOY_DIR}/rclone.conf"

# Use awk for substitution (safe for special characters in credentials)
awk \
  -v access_key="${SPACES_ACCESS_KEY}" \
  -v secret_key="${SPACES_SECRET_KEY}" \
  -v region="${SPACES_REGION}" \
  '{
    gsub(/SPACES_ACCESS_KEY_PLACEHOLDER/, access_key)
    gsub(/SPACES_SECRET_KEY_PLACEHOLDER/, secret_key)
    gsub(/SPACES_REGION_PLACEHOLDER/, region)
    print
  }' "${CONFIG_DIR}/rclone.conf.example" > "${RCLONE_DEST}"

chmod 600 "${RCLONE_DEST}"
echo "  Deployed: ${RCLONE_DEST} (mode 600)"

# =============================================================================
# Step 4: Deploy msmtp config
# =============================================================================
echo "--- Deploying msmtp configuration ---"

MSMTP_DEST="/etc/msmtprc"

# Use awk for substitution (safe for special characters in passwords)
awk \
  -v smtp_host="${SMTP_HOST}" \
  -v smtp_port="${SMTP_PORT}" \
  -v smtp_from="${SMTP_FROM}" \
  -v smtp_user="${SMTP_USER}" \
  -v smtp_password="${SMTP_PASSWORD}" \
  '{
    gsub(/SMTP_HOST_PLACEHOLDER/, smtp_host)
    gsub(/SMTP_PORT_PLACEHOLDER/, smtp_port)
    gsub(/SMTP_FROM_PLACEHOLDER/, smtp_from)
    gsub(/SMTP_USER_PLACEHOLDER/, smtp_user)
    gsub(/SMTP_PASSWORD_PLACEHOLDER/, smtp_password)
    print
  }' "${CONFIG_DIR}/msmtprc.example" > "${MSMTP_DEST}"

chmod 600 "${MSMTP_DEST}"
echo "  Deployed: ${MSMTP_DEST} (mode 600)"

# =============================================================================
# Step 5: Deploy cron entries (BACK-01, BACK-02)
# =============================================================================
echo "--- Deploying cron entries ---"

cp "${CONFIG_DIR}/backup-cron" /etc/cron.d/odoo-backup
chmod 644 /etc/cron.d/odoo-backup
echo "  Deployed: /etc/cron.d/odoo-backup"

# =============================================================================
# Step 6: Copy backup/restore scripts to deployment directory
# =============================================================================
echo "--- Deploying backup scripts ---"

mkdir -p "${DEPLOY_DIR}/scripts"

for script in 06-backup-daily.sh 07-sync-offsite.sh 08-restore-backup.sh; do
  cp "${SCRIPT_DIR}/${script}" "${DEPLOY_DIR}/scripts/${script}"
  chmod +x "${DEPLOY_DIR}/scripts/${script}"
  echo "  Deployed: ${DEPLOY_DIR}/scripts/${script}"
done

# =============================================================================
# Step 7: Create backup directories on Block Storage
# =============================================================================
echo "--- Creating backup directories ---"

mkdir -p "${VOLUME_MOUNT}/backups/daily"
mkdir -p "${VOLUME_MOUNT}/backups/weekly"

echo "  Created: ${VOLUME_MOUNT}/backups/daily"
echo "  Created: ${VOLUME_MOUNT}/backups/weekly"

# =============================================================================
# Step 8: Test rclone connectivity
# =============================================================================
echo "--- Testing rclone connectivity ---"

if rclone lsd --config "${RCLONE_DEST}" "${RCLONE_REMOTE}" &>/dev/null; then
  echo "  rclone: Connected to ${RCLONE_REMOTE}"
else
  echo "  WARNING: rclone could not list ${RCLONE_REMOTE}"
  echo "  Verify SPACES_ACCESS_KEY and SPACES_SECRET_KEY in ${ENV_FILE}"
  echo "  (This may be expected if the bucket doesn't exist yet)"
fi

# =============================================================================
# Step 9: Test msmtp (non-fatal)
# =============================================================================
echo "--- Testing email delivery ---"

if echo "Backup system configured on $(hostname) at $(date -Iseconds)." \
   | mail -s "Odoo Backup Setup Test — $(hostname)" "${ALERT_EMAIL}" 2>/dev/null; then
  echo "  Test email sent to ${ALERT_EMAIL}"
else
  echo "  WARNING: Test email failed (check SMTP credentials in ${ENV_FILE})"
  echo "  Backup system will still function — email alerts may not work"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Backup Infrastructure Setup Complete ==="
echo ""
echo "  BACK-01: Daily backup cron at 2:30 AM"
echo "  BACK-02: Offsite sync cron at 3:30 AM (rclone → DO Spaces)"
echo "  BACK-03: Retention: 7 daily + 4 weekly (local), 30 days (Spaces)"
echo "  BACK-04: Restore script at ${DEPLOY_DIR}/scripts/08-restore-backup.sh"
echo ""
echo "  Config:  ${RCLONE_DEST} (rclone)"
echo "  Config:  ${MSMTP_DEST} (msmtp)"
echo "  Cron:    /etc/cron.d/odoo-backup"
echo "  Scripts: ${DEPLOY_DIR}/scripts/06-backup-daily.sh"
echo "           ${DEPLOY_DIR}/scripts/07-sync-offsite.sh"
echo "           ${DEPLOY_DIR}/scripts/08-restore-backup.sh"
echo "  Backups: ${VOLUME_MOUNT}/backups/{daily,weekly}"
echo ""
echo "To run a manual backup now:"
echo "  sudo bash ${DEPLOY_DIR}/scripts/06-backup-daily.sh"
echo ""
echo "To verify restore from latest backup:"
echo "  sudo bash ${DEPLOY_DIR}/scripts/08-restore-backup.sh --verify-only"
