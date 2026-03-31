#!/usr/bin/env bash
# =============================================================================
# 07-sync-offsite.sh — Offsite Backup Sync to DO Spaces Cold Storage
# =============================================================================
# Requirements: BACK-02 (automated sync to DO Spaces via rclone)
#
# Copies today's backup files to DO Spaces Cold Storage bucket organized
# by year/month. Uses rclone copy (NOT sync) to preserve older remote backups
# beyond the 7-day local retention window.
#
# Designed to be called by cron 1 hour after daily backup:
#   30 3 * * * root /opt/odoo/scripts/07-sync-offsite.sh >> /var/log/odoo-backup-sync.log 2>&1
#
# Prerequisites:
#   - 05-setup-backups.sh completed (rclone configured)
#   - 06-backup-daily.sh completed (today's backups exist)
# =============================================================================

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================
RCLONE_CONF="/opt/odoo/rclone.conf"
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/odoo-prod-data}"
BACKUP_DIR="${VOLUME_MOUNT}/backups/daily"
RCLONE_REMOTE="${RCLONE_REMOTE:-spaces:odoo-prod-backups}"
ENV_FILE="/opt/odoo/.env"
SYNC_STATUS_FILE="/opt/odoo/sync-status.json"
TODAY="$(date +%Y-%m-%d)"
YEAR="$(date +%Y)"
MONTH="$(date +%m)"
START_TIME="$(date +%s)"

# =============================================================================
# Error handling — write failure status + send email
# =============================================================================
cleanup_on_error() {
  local exit_code=$?
  local duration=$(( $(date +%s) - START_TIME ))
  local error_msg="${1:-Offsite sync failed with exit code ${exit_code}}"

  echo "[$(date -Iseconds)] ERROR: ${error_msg}" >&2

  # Write failure status
  cat > "${SYNC_STATUS_FILE}" <<EOF
{
  "status": 2,
  "message": "Offsite sync FAILED: ${error_msg}",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": ${duration}
}
EOF
  chmod 644 "${SYNC_STATUS_FILE}"

  # Send failure email (non-fatal)
  local alert_email
  alert_email=$(grep '^ALERT_EMAIL=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  if [[ -n "${alert_email}" ]]; then
    echo "Offsite backup sync FAILED on $(hostname) at $(date -Iseconds).

Error: ${error_msg}

Check /var/log/odoo-backup-sync.log for details." \
      | mail -s "[CRITICAL] Odoo Offsite Sync Failed — $(hostname)" "${alert_email}" 2>/dev/null || true
  fi

  exit "${exit_code}"
}

trap 'cleanup_on_error' ERR

echo "=== Odoo Offsite Sync — ${TODAY} ==="
echo "[$(date -Iseconds)] Starting offsite sync to DO Spaces"

# =============================================================================
# Pre-flight checks
# =============================================================================

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Check rclone is installed
if ! command -v rclone &>/dev/null; then
  echo "ERROR: rclone is not installed. Run 05-setup-backups.sh first." >&2
  exit 1
fi

# Check rclone config exists
if [[ ! -f "${RCLONE_CONF}" ]]; then
  echo "ERROR: rclone config not found at ${RCLONE_CONF}" >&2
  exit 1
fi

# Check today's backups exist
if ! ls "${BACKUP_DIR}"/odoo-*-"${TODAY}".* &>/dev/null; then
  echo "ERROR: No backup files found for ${TODAY} in ${BACKUP_DIR}" >&2
  exit 1
fi

# =============================================================================
# Sync today's backups to DO Spaces (BACK-02)
# =============================================================================
# Use rclone copy (NOT sync) — sync would delete older remote backups
# Organize by year/month: ${RCLONE_REMOTE}/YYYY/MM/

REMOTE_PATH="${RCLONE_REMOTE}/${YEAR}/${MONTH}/"

echo "[$(date -Iseconds)] Copying to ${REMOTE_PATH}..."

rclone copy \
  --config "${RCLONE_CONF}" \
  "${BACKUP_DIR}/" \
  "${REMOTE_PATH}" \
  --include "odoo-*-${TODAY}.*" \
  --log-level INFO

RCLONE_EXIT=$?

if [[ ${RCLONE_EXIT} -ne 0 ]]; then
  echo "ERROR: rclone copy failed with exit code ${RCLONE_EXIT}" >&2
  exit ${RCLONE_EXIT}
fi

# =============================================================================
# Verify files were uploaded
# =============================================================================
echo "[$(date -Iseconds)] Verifying upload..."

REMOTE_FILES=$(rclone ls \
  --config "${RCLONE_CONF}" \
  "${REMOTE_PATH}" \
  --include "odoo-*-${TODAY}.*" 2>/dev/null | wc -l)

if [[ "${REMOTE_FILES}" -lt 1 ]]; then
  echo "WARNING: Could not verify uploaded files on remote" >&2
fi

echo "  Verified ${REMOTE_FILES} file(s) on remote"

# =============================================================================
# Write success status file
# =============================================================================
DURATION=$(( $(date +%s) - START_TIME ))

cat > "${SYNC_STATUS_FILE}" <<EOF
{
  "status": 0,
  "message": "Offsite sync completed successfully",
  "timestamp": "$(date -Iseconds)",
  "remote_path": "${REMOTE_PATH}",
  "files_synced": ${REMOTE_FILES},
  "duration_seconds": ${DURATION}
}
EOF
chmod 644 "${SYNC_STATUS_FILE}"

echo ""
echo "=== Offsite Sync Complete ==="
echo "  Remote:   ${REMOTE_PATH}"
echo "  Files:    ${REMOTE_FILES}"
echo "  Duration: ${DURATION}s"
echo "[$(date -Iseconds)] Offsite sync finished successfully"
