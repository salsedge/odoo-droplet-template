#!/usr/bin/env bash
# =============================================================================
# verify-backup.sh -- Backup trigger and verification over SSH
# =============================================================================
# Triggers a manual backup and offsite sync on the production droplet via SSH,
# then verifies status files report success (Nagios convention: 0 = OK).
#
# Usage:
#   bash scripts/verify-backup.sh
#
# Environment variables:
#   INFRA_SSH_HOST       (required) Droplet IP or hostname
#   INFRA_SSH_PORT       (default: 9292) SSH port on remote host
#   INFRA_SSH_USER       (default: deploy) SSH user on remote host
# =============================================================================

set -euo pipefail

# --- Configuration ---

REMOTE_HOST="${INFRA_SSH_HOST:?INFRA_SSH_HOST not set}"
REMOTE_PORT="${INFRA_SSH_PORT:-9292}"
REMOTE_USER="${INFRA_SSH_USER:-deploy}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"
TODAY=$(date +%Y-%m-%d)

# --- Counters ---

TOTAL=0
PASSED=0
FAILED=0

# --- SSH helper ---

ssh_cmd() {
  ssh -p "${REMOTE_PORT}" ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "$@"
}

# --- Check runner ---

run_step() {
  local description="$1"
  local result="$2"  # 0 = pass, non-zero = fail

  TOTAL=$((TOTAL + 1))

  if [[ "$result" -eq 0 ]]; then
    echo "[PASS] ${description}"
    PASSED=$((PASSED + 1))
  else
    echo "[FAIL] ${description}"
    FAILED=$((FAILED + 1))
  fi
}

# =============================================================================
# Verification Steps
# =============================================================================

echo "=== Backup Verification ==="
echo "Target: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}"
echo "Date: ${TODAY}"
echo ""

# --- Step 1: Trigger manual backup ---
echo "--- Step 1: Triggering manual backup..."
STEP_RESULT=0
ssh_cmd "sudo /opt/odoo/scripts/06-backup-daily.sh" 2>&1 || STEP_RESULT=$?
run_step "Step 1: Trigger manual backup (06-backup-daily.sh)" "$STEP_RESULT"

# --- Step 2: Check backup-status.json ---
echo "--- Step 2: Checking backup-status.json..."
STEP_RESULT=1
BACKUP_STATUS=$(ssh_cmd "cat /opt/odoo/backup-status.json" 2>/dev/null) || true
if echo "$BACKUP_STATUS" | grep -q '"status"[[:space:]]*:[[:space:]]*0'; then
  STEP_RESULT=0
else
  echo "       backup-status.json: ${BACKUP_STATUS:-<not found>}"
fi
run_step "Step 2: backup-status.json reports OK (status: 0)" "$STEP_RESULT"

# --- Step 3: Trigger offsite sync ---
echo "--- Step 3: Triggering offsite sync..."
STEP_RESULT=0
ssh_cmd "sudo /opt/odoo/scripts/07-sync-offsite.sh" 2>&1 || STEP_RESULT=$?
run_step "Step 3: Trigger offsite sync (07-sync-offsite.sh)" "$STEP_RESULT"

# --- Step 4: Check sync-status.json ---
echo "--- Step 4: Checking sync-status.json..."
STEP_RESULT=1
SYNC_STATUS=$(ssh_cmd "cat /opt/odoo/sync-status.json" 2>/dev/null) || true
if echo "$SYNC_STATUS" | grep -q '"status"[[:space:]]*:[[:space:]]*0'; then
  STEP_RESULT=0
else
  echo "       sync-status.json: ${SYNC_STATUS:-<not found>}"
fi
run_step "Step 4: sync-status.json reports OK (status: 0)" "$STEP_RESULT"

# --- Step 5: Verify backup file exists for today ---
echo "--- Step 5: Checking for today's backup file..."
STEP_RESULT=1
BACKUP_FILES=$(ssh_cmd "ls /mnt/odoo-prod-data/backups/daily/ 2>/dev/null | grep '${TODAY}'" 2>/dev/null) || true
if [[ -n "$BACKUP_FILES" ]]; then
  STEP_RESULT=0
  echo "       Found: ${BACKUP_FILES}"
else
  echo "       No backup file found for ${TODAY}"
fi
run_step "Step 5: Backup file exists for today (${TODAY})" "$STEP_RESULT"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=== Backup Verification Summary ==="
echo "${PASSED}/${TOTAL} checks passed"

if [[ $FAILED -gt 0 ]]; then
  echo "${FAILED} check(s) FAILED"
  exit 1
else
  echo "All checks passed"
  exit 0
fi
