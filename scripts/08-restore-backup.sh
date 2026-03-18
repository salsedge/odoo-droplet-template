#!/usr/bin/env bash
# =============================================================================
# 08-restore-backup.sh — Backup Restore & Verification
# =============================================================================
# Requirements: BACK-04 (documented and tested restore procedure)
#
# Restores Odoo database and filestore from backup with verification.
# Supports four modes:
#   --verify-only   Restore into temp container, run checks, tear down (default)
#   --production    Stop Odoo, restore into live database, restart
#   --file PATH     Restore from a specific backup file
#   --from-spaces   Fetch backup from DO Spaces via rclone
#   --date DATE     Specify date (YYYY-MM-DD) for --from-spaces or local lookup
#
# Usage:
#   sudo bash scripts/08-restore-backup.sh                           # verify latest local
#   sudo bash scripts/08-restore-backup.sh --file /path/to/dump      # verify specific file
#   sudo bash scripts/08-restore-backup.sh --from-spaces --date 2026-03-10  # fetch from Spaces
#   sudo bash scripts/08-restore-backup.sh --production              # restore to production
#   sudo bash scripts/08-restore-backup.sh --production --from-spaces --date 2026-03-10
# =============================================================================

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================
BACKUP_DIR="/mnt/odoo-prod-data/backups"
RCLONE_CONF="/opt/odoo/rclone.conf"
ENV_FILE="/opt/odoo/.env"
COMPOSE_FILE="/opt/odoo/docker-compose.yml"
TEMP_CONTAINER="odoo-restore-test"
TEMP_DIR=""
VERIFY_PASS=0
VERIFY_FAIL=0
VERIFY_RESULTS=()

# =============================================================================
# Usage
# =============================================================================
usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]

Restore Odoo database and filestore from backup.

Options:
  --file PATH        Restore from a specific .dump file
  --from-spaces      Fetch backup from DO Spaces via rclone
  --date YYYY-MM-DD  Date of backup to restore (used with --from-spaces or local lookup)
  --verify-only      Restore into temp container, verify, tear down (default mode)
  --production       Restore into production database (DANGEROUS — stops Odoo)
  --help             Show this help message

Examples:
  $0                                      # Verify most recent local backup
  $0 --file /path/to/odoo-db-2026-03-17.dump
  $0 --from-spaces --date 2026-03-10     # Fetch from Spaces, verify
  $0 --production                         # Restore latest local to production
  $0 --production --from-spaces --date 2026-03-10

USAGE
  exit 0
}

# =============================================================================
# Argument parsing
# =============================================================================
DUMP_FILE=""
FROM_SPACES=false
RESTORE_DATE=""
VERIFY_ONLY=true
PRODUCTION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      DUMP_FILE="$2"
      shift 2
      ;;
    --from-spaces)
      FROM_SPACES=true
      shift
      ;;
    --date)
      RESTORE_DATE="$2"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    --production)
      PRODUCTION=true
      VERIFY_ONLY=false
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

# =============================================================================
# Cleanup trap — always remove temp containers and temp dir
# =============================================================================
cleanup() {
  echo ""
  echo "--- Cleaning up ---"
  # Stop and remove temp container if it exists
  if docker inspect "${TEMP_CONTAINER}" &>/dev/null; then
    docker stop "${TEMP_CONTAINER}" &>/dev/null || true
    docker rm "${TEMP_CONTAINER}" &>/dev/null || true
    echo "  Removed temp container: ${TEMP_CONTAINER}"
  fi
  # Remove temp directory if created
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
    echo "  Removed temp directory: ${TEMP_DIR}"
  fi
}

trap cleanup EXIT

# =============================================================================
# Helper: record verification result
# =============================================================================
verify_check() {
  local name="$1"
  local result="$2"
  local detail="${3:-}"

  if [[ "${result}" == "PASS" ]]; then
    VERIFY_PASS=$(( VERIFY_PASS + 1 ))
    VERIFY_RESULTS+=("[PASS] ${name}: ${detail}")
    echo "  [PASS] ${name}: ${detail}"
  else
    VERIFY_FAIL=$(( VERIFY_FAIL + 1 ))
    VERIFY_RESULTS+=("[FAIL] ${name}: ${detail}")
    echo "  [FAIL] ${name}: ${detail}"
  fi
}

# =============================================================================
# Pre-flight checks
# =============================================================================
echo "=== Odoo Backup Restore ==="

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# =============================================================================
# Source selection: determine which dump file to restore
# =============================================================================
FILESTORE_ARCHIVE=""

# Option 1: Explicit file path
if [[ -n "${DUMP_FILE}" ]]; then
  if [[ ! -f "${DUMP_FILE}" ]]; then
    echo "ERROR: Specified file not found: ${DUMP_FILE}" >&2
    exit 1
  fi
  echo "Using specified backup file: ${DUMP_FILE}"
  # Look for matching filestore archive alongside the dump
  DUMP_BASENAME=$(basename "${DUMP_FILE}" .dump)
  DUMP_DIRNAME=$(dirname "${DUMP_FILE}")
  FILESTORE_CANDIDATE="${DUMP_DIRNAME}/${DUMP_BASENAME/odoo-db/odoo-files}.tar.gz"
  if [[ -f "${FILESTORE_CANDIDATE}" ]]; then
    FILESTORE_ARCHIVE="${FILESTORE_CANDIDATE}"
    echo "Found matching filestore archive: ${FILESTORE_ARCHIVE}"
  fi

# Option 2: Fetch from DO Spaces
elif [[ "${FROM_SPACES}" == true ]]; then
  if [[ -z "${RESTORE_DATE}" ]]; then
    echo "ERROR: --from-spaces requires --date YYYY-MM-DD" >&2
    exit 1
  fi
  if [[ ! -f "${RCLONE_CONF}" ]]; then
    echo "ERROR: rclone config not found at ${RCLONE_CONF}" >&2
    exit 1
  fi
  if ! command -v rclone &>/dev/null; then
    echo "ERROR: rclone not installed" >&2
    exit 1
  fi

  YEAR="${RESTORE_DATE:0:4}"
  MONTH="${RESTORE_DATE:5:2}"
  REMOTE_PATH="spaces:odoo-prod-backups/${YEAR}/${MONTH}/"

  TEMP_DIR=$(mktemp -d /tmp/odoo-restore-XXXXXX)
  echo "Fetching backup from DO Spaces: ${REMOTE_PATH}"

  # Fetch database dump
  rclone copy \
    --config "${RCLONE_CONF}" \
    "${REMOTE_PATH}" \
    "${TEMP_DIR}/" \
    --include "odoo-db-${RESTORE_DATE}.dump"

  DUMP_FILE="${TEMP_DIR}/odoo-db-${RESTORE_DATE}.dump"
  if [[ ! -f "${DUMP_FILE}" ]]; then
    echo "ERROR: Could not fetch odoo-db-${RESTORE_DATE}.dump from ${REMOTE_PATH}" >&2
    exit 1
  fi
  echo "  Fetched: ${DUMP_FILE}"

  # Fetch filestore archive
  rclone copy \
    --config "${RCLONE_CONF}" \
    "${REMOTE_PATH}" \
    "${TEMP_DIR}/" \
    --include "odoo-files-${RESTORE_DATE}.tar.gz"

  FILESTORE_CANDIDATE="${TEMP_DIR}/odoo-files-${RESTORE_DATE}.tar.gz"
  if [[ -f "${FILESTORE_CANDIDATE}" ]]; then
    FILESTORE_ARCHIVE="${FILESTORE_CANDIDATE}"
    echo "  Fetched: ${FILESTORE_ARCHIVE}"
  else
    echo "  WARNING: Filestore archive not found on Spaces (DB-only restore)"
  fi

# Option 3: Most recent local backup
else
  if [[ -n "${RESTORE_DATE}" ]]; then
    # Look for specific date in local backups
    DUMP_FILE="${BACKUP_DIR}/daily/odoo-db-${RESTORE_DATE}.dump"
    if [[ ! -f "${DUMP_FILE}" ]]; then
      DUMP_FILE="${BACKUP_DIR}/weekly/odoo-db-${RESTORE_DATE}.dump"
    fi
    if [[ ! -f "${DUMP_FILE}" ]]; then
      echo "ERROR: No local backup found for date ${RESTORE_DATE}" >&2
      exit 1
    fi
  else
    # Find most recent .dump file
    DUMP_FILE=$(find "${BACKUP_DIR}/daily/" -name "odoo-db-*.dump" -type f 2>/dev/null \
      | sort -r | head -1)
    if [[ -z "${DUMP_FILE}" ]]; then
      echo "ERROR: No backup files found in ${BACKUP_DIR}/daily/" >&2
      exit 1
    fi
  fi
  echo "Using local backup: ${DUMP_FILE}"

  # Look for matching filestore archive
  DUMP_BASENAME=$(basename "${DUMP_FILE}" .dump)
  DUMP_DIRNAME=$(dirname "${DUMP_FILE}")
  FILESTORE_CANDIDATE="${DUMP_DIRNAME}/${DUMP_BASENAME/odoo-db/odoo-files}.tar.gz"
  if [[ -f "${FILESTORE_CANDIDATE}" ]]; then
    FILESTORE_ARCHIVE="${FILESTORE_CANDIDATE}"
    echo "Found matching filestore archive: ${FILESTORE_ARCHIVE}"
  fi
fi

echo ""

# =============================================================================
# VERIFY-ONLY MODE: temp container restore + verification
# =============================================================================
if [[ "${VERIFY_ONLY}" == true ]]; then
  echo "--- Mode: VERIFY-ONLY (temp container) ---"
  echo ""

  # Remove any leftover temp container from previous runs
  if docker inspect "${TEMP_CONTAINER}" &>/dev/null; then
    docker stop "${TEMP_CONTAINER}" &>/dev/null || true
    docker rm "${TEMP_CONTAINER}" &>/dev/null || true
  fi

  # Start temporary PostgreSQL 18 container
  echo "[1/5] Starting temporary PostgreSQL container..."
  docker run -d \
    --name "${TEMP_CONTAINER}" \
    -e POSTGRES_USER=restore_test \
    -e POSTGRES_PASSWORD=test_only \
    -e POSTGRES_DB=odoo_restore \
    postgres:18

  # Wait for container to be ready (poll pg_isready with timeout)
  echo "[2/5] Waiting for PostgreSQL to be ready..."
  TIMEOUT=60
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if docker exec "${TEMP_CONTAINER}" pg_isready -U restore_test -d odoo_restore &>/dev/null; then
      echo "  PostgreSQL ready after ${ELAPSED}s"
      break
    fi
    sleep 2
    ELAPSED=$(( ELAPSED + 2 ))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "ERROR: Temp PostgreSQL container did not become ready within ${TIMEOUT}s" >&2
    exit 1
  fi

  # Restore the database
  echo "[3/5] Restoring database from backup..."
  docker exec -i "${TEMP_CONTAINER}" \
    pg_restore -U restore_test -d odoo_restore --no-owner --clean --if-exists \
    < "${DUMP_FILE}" 2>&1 || true
  # pg_restore may return non-zero for warnings (e.g., "role does not exist") — check data instead

  # Run verification queries
  echo "[4/5] Running verification queries..."
  echo ""

  # Check 1: Table count in public schema (expect > 100 for Odoo)
  TABLE_COUNT=$(docker exec "${TEMP_CONTAINER}" \
    psql -U restore_test -d odoo_restore -t -A -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d '[:space:]')
  TABLE_COUNT="${TABLE_COUNT:-0}"

  if [[ "${TABLE_COUNT}" -gt 100 ]]; then
    verify_check "Table count" "PASS" "${TABLE_COUNT} tables (expected > 100)"
  else
    verify_check "Table count" "FAIL" "${TABLE_COUNT} tables (expected > 100)"
  fi

  # Check 2: Key Odoo tables exist
  KEY_TABLES=("res_users" "res_partner" "crm_lead" "project_project" "ir_module_module")
  for table in "${KEY_TABLES[@]}"; do
    EXISTS=$(docker exec "${TEMP_CONTAINER}" \
      psql -U restore_test -d odoo_restore -t -A -c \
      "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='${table}');" 2>/dev/null | tr -d '[:space:]')
    if [[ "${EXISTS}" == "t" ]]; then
      verify_check "Table ${table}" "PASS" "exists"
    else
      verify_check "Table ${table}" "FAIL" "not found"
    fi
  done

  # Check 3: Row counts for key tables (expect > 0)
  for table in res_users res_partner; do
    ROW_COUNT=$(docker exec "${TEMP_CONTAINER}" \
      psql -U restore_test -d odoo_restore -t -A -c \
      "SELECT count(*) FROM ${table};" 2>/dev/null | tr -d '[:space:]')
    ROW_COUNT="${ROW_COUNT:-0}"
    if [[ "${ROW_COUNT}" -gt 0 ]]; then
      verify_check "Row count ${table}" "PASS" "${ROW_COUNT} rows"
    else
      verify_check "Row count ${table}" "FAIL" "0 rows (expected > 0)"
    fi
  done

  # Check 4: CRM and Project modules installed
  for module in crm project; do
    INSTALLED=$(docker exec "${TEMP_CONTAINER}" \
      psql -U restore_test -d odoo_restore -t -A -c \
      "SELECT state FROM ir_module_module WHERE name='${module}';" 2>/dev/null | tr -d '[:space:]')
    if [[ "${INSTALLED}" == "installed" ]]; then
      verify_check "Module ${module}" "PASS" "state=installed"
    else
      verify_check "Module ${module}" "FAIL" "state=${INSTALLED:-not found} (expected installed)"
    fi
  done

  # Optional: Test Odoo boot against restored DB
  echo ""
  echo "[5/5] Testing Odoo boot against restored database..."
  ODOO_IMAGE=$(docker inspect --format='{{.Config.Image}}' odoo-app 2>/dev/null || echo "odoo:19")
  TEMP_ODOO="odoo-restore-boot-test"

  # Clean up any leftover from previous runs
  docker stop "${TEMP_ODOO}" &>/dev/null || true
  docker rm "${TEMP_ODOO}" &>/dev/null || true

  # Get temp container's IP for Odoo to connect
  TEMP_PG_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${TEMP_CONTAINER}" 2>/dev/null || true)

  if [[ -n "${TEMP_PG_IP}" ]]; then
    # Run Odoo with --stop-after-init to test boot only
    BOOT_OUTPUT=$(docker run --rm \
      --name "${TEMP_ODOO}" \
      -e HOST="${TEMP_PG_IP}" \
      -e PORT=5432 \
      -e USER=restore_test \
      -e PASSWORD=test_only \
      "${ODOO_IMAGE}" \
      odoo --stop-after-init --no-http \
        --db_host="${TEMP_PG_IP}" --db_port=5432 \
        --db_user=restore_test --db_password=test_only \
        -d odoo_restore 2>&1 | tail -5) || true

    if echo "${BOOT_OUTPUT}" | grep -qi "odoo server running\|modules loaded\|Odoo has shut down"; then
      verify_check "Odoo boot test" "PASS" "Odoo started and shut down cleanly"
    else
      verify_check "Odoo boot test" "FAIL" "Odoo did not boot cleanly (non-critical)"
    fi
  else
    echo "  Skipped: could not determine temp container IP"
  fi

  # Print summary
  echo ""
  echo "=== Verification Summary ==="
  for result in "${VERIFY_RESULTS[@]}"; do
    echo "  ${result}"
  done
  echo ""
  echo "  PASSED: ${VERIFY_PASS}  FAILED: ${VERIFY_FAIL}"
  echo ""

  if [[ ${VERIFY_FAIL} -gt 0 ]]; then
    echo "RESULT: VERIFICATION FAILED"
    exit 1
  else
    echo "RESULT: VERIFICATION PASSED"
    exit 0
  fi
fi

# =============================================================================
# PRODUCTION MODE: restore into live database
# =============================================================================
if [[ "${PRODUCTION}" == true ]]; then
  echo "--- Mode: PRODUCTION RESTORE ---"
  echo ""
  echo "WARNING: This will:"
  echo "  1. Stop the Odoo application"
  echo "  2. Drop and restore the production database from backup"
  if [[ -n "${FILESTORE_ARCHIVE}" ]]; then
    echo "  3. Restore the filestore from archive"
  fi
  echo ""
  read -r -p "Continue? [y/N] " CONFIRM
  if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi

  # Read production PG credentials from .env
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: ${ENV_FILE} not found" >&2
    exit 1
  fi
  PROD_USER=$(grep '^POSTGRES_USER=' "${ENV_FILE}" | cut -d'=' -f2-)
  PROD_DB=$(grep '^POSTGRES_DB=' "${ENV_FILE}" | cut -d'=' -f2-)
  PROD_DB="${PROD_DB:-odoo}"

  # Step 1: Stop Odoo (keep database running)
  echo "[1/4] Stopping Odoo..."
  docker compose -f "${COMPOSE_FILE}" stop odoo
  echo "  Odoo stopped"

  # Step 2: Drop and recreate database, then restore
  echo "[2/4] Restoring database..."

  # Terminate existing connections to the database
  docker exec odoo-db psql -U "${PROD_USER}" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${PROD_DB}' AND pid <> pg_backend_pid();" \
    &>/dev/null || true

  # Drop and recreate the database
  docker exec odoo-db dropdb -U "${PROD_USER}" --if-exists "${PROD_DB}"
  docker exec odoo-db createdb -U "${PROD_USER}" -O "${PROD_USER}" "${PROD_DB}"

  # Restore from backup
  docker exec -i odoo-db pg_restore \
    -U "${PROD_USER}" \
    -d "${PROD_DB}" \
    --no-owner \
    --clean \
    --if-exists \
    < "${DUMP_FILE}" 2>&1 || true
  # pg_restore warnings are non-fatal (e.g., "role does not exist")

  echo "  Database restored"

  # Step 3: Restore filestore if archive exists
  if [[ -n "${FILESTORE_ARCHIVE}" ]]; then
    echo "[3/4] Restoring filestore..."

    FILESTORE_DIR="/mnt/odoo-prod-data/odoo-filestore"

    # Backup current filestore (safety net)
    if [[ -d "${FILESTORE_DIR}" ]]; then
      mv "${FILESTORE_DIR}" "${FILESTORE_DIR}.pre-restore.$(date +%s)"
    fi

    # Extract filestore archive
    tar -xzf "${FILESTORE_ARCHIVE}" -C /mnt/odoo-prod-data/

    # Restore ownership (Odoo container: uid 100, gid 101)
    chown -R 100:101 "${FILESTORE_DIR}"

    echo "  Filestore restored"
  else
    echo "[3/4] No filestore archive — skipping filestore restore"
  fi

  # Step 4: Restart Odoo and verify
  echo "[4/4] Restarting Odoo..."
  docker compose -f "${COMPOSE_FILE}" start odoo

  # Wait for health check
  TIMEOUT=120
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    ODOO_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' odoo-app 2>/dev/null || echo "starting")
    if [[ "${ODOO_HEALTH}" == "healthy" ]]; then
      echo "  Odoo is healthy!"
      break
    fi
    echo "  Waiting... Odoo=${ODOO_HEALTH} (${ELAPSED}s/${TIMEOUT}s)"
    sleep 10
    ELAPSED=$(( ELAPSED + 10 ))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "WARNING: Odoo did not become healthy within ${TIMEOUT}s" >&2
    echo "Check logs: docker compose -f ${COMPOSE_FILE} logs odoo" >&2
    exit 1
  fi

  echo ""
  echo "=== Production Restore Complete ==="
  echo "  Database:  Restored from $(basename "${DUMP_FILE}")"
  if [[ -n "${FILESTORE_ARCHIVE}" ]]; then
    echo "  Filestore: Restored from $(basename "${FILESTORE_ARCHIVE}")"
  fi
  echo "  Odoo:      Running and healthy"
  echo ""
  echo "Verify the application at your Odoo URL."
fi
