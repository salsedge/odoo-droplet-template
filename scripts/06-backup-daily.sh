#!/usr/bin/env bash
# =============================================================================
# 06-backup-daily.sh — Daily PostgreSQL + Filestore Backup
# =============================================================================
# Requirements: BACK-01 (daily pg_dump), BACK-03 (retention policy)
#
# Creates daily backups of PostgreSQL database (custom format) and Odoo
# filestore (tar.gz). Promotes Sunday backups to weekly. Enforces retention:
# 7 daily, 4 weekly on local Block Storage. Writes status file for Phase 5
# Icinga2 monitoring and sends email on failure.
#
# Designed to be called by cron:
#   30 2 * * * root /opt/odoo/scripts/06-backup-daily.sh >> /var/log/odoo-backup.log 2>&1
#
# Prerequisites:
#   - 05-setup-backups.sh completed (msmtp configured)
#   - Docker stack running (03-deploy-stack.sh)
#   - .env file at /opt/odoo/.env with PostgreSQL credentials
# =============================================================================

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================
BACKUP_DIR="/mnt/odoo-prod-data/backups"
FILESTORE_DIR="/mnt/odoo-prod-data/odoo-filestore"
ENV_FILE="/opt/odoo/.env"
STATUS_FILE="/opt/odoo/backup-status.json"
LOG_TAG="odoo-backup"
TODAY="$(date +%Y-%m-%d)"
START_TIME="$(date +%s)"

# =============================================================================
# Error handling — write failure status + send email on any error
# =============================================================================
cleanup_on_error() {
  local exit_code=$?
  local duration=$(( $(date +%s) - START_TIME ))
  local error_msg="${1:-Backup failed with exit code ${exit_code}}"

  echo "[$(date -Iseconds)] ERROR: ${error_msg}" >&2

  # Write failure status file (Nagios convention: 2 = CRITICAL)
  cat > "${STATUS_FILE}" <<EOF
{
  "status": 2,
  "message": "Backup FAILED: ${error_msg}",
  "timestamp": "$(date -Iseconds)",
  "duration_seconds": ${duration}
}
EOF
  chmod 644 "${STATUS_FILE}"

  # Send failure email (non-fatal if mail fails)
  local alert_email
  alert_email=$(grep '^ALERT_EMAIL=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  if [[ -n "${alert_email}" ]]; then
    echo "Backup FAILED on $(hostname) at $(date -Iseconds).

Error: ${error_msg}

Check /var/log/odoo-backup.log for details." \
      | mail -s "[CRITICAL] Odoo Backup Failed — $(hostname)" "${alert_email}" 2>/dev/null || true
  fi

  # Remove any incomplete temp files
  rm -f "${BACKUP_DIR}/daily/.odoo-db-${TODAY}.dump.tmp" 2>/dev/null || true
  rm -f "${BACKUP_DIR}/daily/.odoo-files-${TODAY}.tar.gz.tmp" 2>/dev/null || true

  exit "${exit_code}"
}

trap 'cleanup_on_error' ERR

echo "=== Odoo Daily Backup — ${TODAY} ==="
echo "[$(date -Iseconds)] Starting backup"

# =============================================================================
# Pre-flight checks
# =============================================================================

# Must run as root (cron runs as root)
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Check Docker is running
if ! docker info &>/dev/null; then
  echo "ERROR: Docker is not running" >&2
  exit 1
fi

# Check odoo-db container is healthy
DB_HEALTH=$(docker inspect --format '{{.State.Health.Status}}' odoo-db 2>/dev/null || echo "not found")
if [[ "${DB_HEALTH}" != "healthy" ]]; then
  echo "ERROR: odoo-db container is not healthy (status: ${DB_HEALTH})" >&2
  exit 1
fi

# Check available disk space on backup volume (fail if less than 2GB free)
AVAIL_KB=$(df --output=avail /mnt/odoo-prod-data 2>/dev/null | tail -1 | tr -d ' ')
AVAIL_KB="${AVAIL_KB:-0}"
MIN_KB=2097152  # 2 GB in KB
if [[ "${AVAIL_KB}" -lt "${MIN_KB}" ]]; then
  echo "ERROR: Insufficient disk space on /mnt/odoo-prod-data (${AVAIL_KB} KB available, need ${MIN_KB} KB)" >&2
  exit 1
fi

# Check .env file exists
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found" >&2
  exit 1
fi

# Create backup directories if they don't exist
mkdir -p "${BACKUP_DIR}/daily"
mkdir -p "${BACKUP_DIR}/weekly"

# =============================================================================
# Retention cleanup — run BEFORE backup to free space first (BACK-03)
# =============================================================================
echo "[$(date -Iseconds)] Running retention cleanup..."

# Daily: remove backups older than 7 days
find "${BACKUP_DIR}/daily/" -name "odoo-*" -mtime +7 -delete 2>/dev/null || true

# Weekly: remove backups older than 28 days (4 weeks)
find "${BACKUP_DIR}/weekly/" -name "odoo-*" -mtime +28 -delete 2>/dev/null || true

echo "  Retention cleanup complete"

# =============================================================================
# Extract credentials from .env (safe for special chars — no sourcing)
# =============================================================================
POSTGRES_USER=$(grep '^POSTGRES_USER=' "${ENV_FILE}" | cut -d'=' -f2-)
POSTGRES_DB=$(grep '^POSTGRES_DB=' "${ENV_FILE}" | cut -d'=' -f2-)
POSTGRES_DB="${POSTGRES_DB:-odoo}"

if [[ -z "${POSTGRES_USER}" ]]; then
  echo "ERROR: POSTGRES_USER not found in ${ENV_FILE}" >&2
  exit 1
fi

# =============================================================================
# Database backup (BACK-01) — pg_dump custom format
# =============================================================================
echo "[$(date -Iseconds)] Backing up PostgreSQL database..."

DB_TEMP="${BACKUP_DIR}/daily/.odoo-db-${TODAY}.dump.tmp"
DB_FILE="${BACKUP_DIR}/daily/odoo-db-${TODAY}.dump"

# Write to temp file first, rename on success (prevents corrupt partial backups)
docker exec odoo-db pg_dump \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  -Fc \
  --no-owner \
  --no-privileges \
  > "${DB_TEMP}"

# Verify dump is non-empty
if [[ ! -s "${DB_TEMP}" ]]; then
  rm -f "${DB_TEMP}"
  echo "ERROR: pg_dump produced empty output" >&2
  exit 1
fi

mv "${DB_TEMP}" "${DB_FILE}"
DB_SIZE=$(stat -c%s "${DB_FILE}" 2>/dev/null || stat -f%z "${DB_FILE}" 2>/dev/null || echo "0")
echo "  Database backup: ${DB_FILE} ($(numfmt --to=iec "${DB_SIZE}" 2>/dev/null || echo "${DB_SIZE} bytes"))"

# =============================================================================
# Filestore backup — tar.gz excluding sessions and addons
# =============================================================================
echo "[$(date -Iseconds)] Backing up Odoo filestore..."

FILES_TEMP="${BACKUP_DIR}/daily/.odoo-files-${TODAY}.tar.gz.tmp"
FILES_FILE="${BACKUP_DIR}/daily/odoo-files-${TODAY}.tar.gz"

# Exclude sessions (ephemeral) and addons (from Docker image)
tar -czf "${FILES_TEMP}" \
  --exclude='sessions' \
  --exclude='addons' \
  -C /mnt/odoo-prod-data \
  odoo-filestore/

mv "${FILES_TEMP}" "${FILES_FILE}"
FILES_SIZE=$(stat -c%s "${FILES_FILE}" 2>/dev/null || stat -f%z "${FILES_FILE}" 2>/dev/null || echo "0")
echo "  Filestore backup: ${FILES_FILE} ($(numfmt --to=iec "${FILES_SIZE}" 2>/dev/null || echo "${FILES_SIZE} bytes"))"

# =============================================================================
# Weekly promotion (BACK-03) — Sunday's daily -> weekly
# =============================================================================
if [[ "$(date +%u)" == "7" ]]; then
  echo "[$(date -Iseconds)] Sunday — promoting to weekly backup..."

  # Hard link (no extra disk space) with fallback to copy
  cp -l "${DB_FILE}" "${BACKUP_DIR}/weekly/odoo-db-${TODAY}.dump" 2>/dev/null \
    || cp "${DB_FILE}" "${BACKUP_DIR}/weekly/odoo-db-${TODAY}.dump"

  cp -l "${FILES_FILE}" "${BACKUP_DIR}/weekly/odoo-files-${TODAY}.tar.gz" 2>/dev/null \
    || cp "${FILES_FILE}" "${BACKUP_DIR}/weekly/odoo-files-${TODAY}.tar.gz"

  echo "  Weekly promotion complete"
fi

# =============================================================================
# Write success status file (Phase 5 Icinga2 prep)
# =============================================================================
DURATION=$(( $(date +%s) - START_TIME ))

cat > "${STATUS_FILE}" <<EOF
{
  "status": 0,
  "message": "Backup completed successfully",
  "timestamp": "$(date -Iseconds)",
  "db_size_bytes": ${DB_SIZE},
  "files_size_bytes": ${FILES_SIZE},
  "duration_seconds": ${DURATION}
}
EOF
chmod 644 "${STATUS_FILE}"

echo ""
echo "=== Backup Complete ==="
echo "  Database:  ${DB_FILE} (${DB_SIZE} bytes)"
echo "  Filestore: ${FILES_FILE} (${FILES_SIZE} bytes)"
echo "  Duration:  ${DURATION}s"
echo "  Status:    ${STATUS_FILE}"
echo "[$(date -Iseconds)] Backup finished successfully"
