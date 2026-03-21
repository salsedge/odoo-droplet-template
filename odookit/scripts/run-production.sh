#!/usr/bin/env bash
# =============================================================================
# run-production.sh -- Production verification orchestration
# =============================================================================
# Single command to verify the entire production Odoo system and create team
# member accounts. Runs 5 stages in strict order with fail-fast on smoke tests.
#
# Usage:
#   bash scripts/run-production.sh
#   npm run verify:prod     (from odookit/)
#
# Stages:
#   1. Smoke Tests       (BLOCKING -- failure aborts everything)
#   2. Infrastructure Audit (non-blocking)
#   3. Odoo Audit        (non-blocking)
#   4. User Creation     (non-blocking -- partial failure keeps successes)
#   5. Backup Verification (non-blocking)
#
# Environment variables:
#   INFRA_SSH_HOST       (required) Droplet IP or hostname
#   INFRA_SSH_PORT       (default: 9292) SSH port
#   INFRA_SSH_USER       (default: deploy) SSH user
#   TUNNEL_LOCAL_PORT    (default: 8443) Local port for SSH tunnel
#   ADMIN_LOGIN          (required) Odoo admin login
#   ADMIN_PASSWORD       (required) Odoo admin password
# =============================================================================

set -euo pipefail

# --- Resolve paths ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODOOKIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Source .env ---

if [[ -f "${ODOOKIT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${ODOOKIT_DIR}/.env"
  set +a
fi

# --- Pre-flight checks ---

echo "=========================================="
echo "  Production Verification"
echo "=========================================="
echo ""

# team-members.json must exist
if [[ ! -f "${ODOOKIT_DIR}/team-members.json" ]]; then
  echo "ERROR: team-members.json not found." >&2
  echo "  cp team-members.json.example team-members.json" >&2
  echo "  Then fill in real passwords for each user." >&2
  exit 1
fi

# INFRA_SSH_HOST must be set
if [[ -z "${INFRA_SSH_HOST:-}" ]]; then
  echo "ERROR: INFRA_SSH_HOST is not set." >&2
  echo "  Set it in .env or export it: export INFRA_SSH_HOST=your.server.ip" >&2
  exit 1
fi

# Admin credentials must be set
if [[ -z "${ADMIN_LOGIN:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
  echo "ERROR: ADMIN_LOGIN and ADMIN_PASSWORD must be set." >&2
  echo "  Set them in .env or export them." >&2
  exit 1
fi

# SSH connectivity test
SSH_PORT="${INFRA_SSH_PORT:-9292}"
SSH_USER="${INFRA_SSH_USER:-deploy}"
echo "Testing SSH connectivity to ${SSH_USER}@${INFRA_SSH_HOST}:${SSH_PORT}..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -p "${SSH_PORT}" "${SSH_USER}@${INFRA_SSH_HOST}" "echo ok" >/dev/null 2>&1; then
  echo "ERROR: Cannot connect via SSH to ${SSH_USER}@${INFRA_SSH_HOST}:${SSH_PORT}" >&2
  echo "  Troubleshooting:" >&2
  echo "    - Verify INFRA_SSH_HOST, INFRA_SSH_PORT, INFRA_SSH_USER in .env" >&2
  echo "    - Check that your SSH key is loaded: ssh-add -l" >&2
  echo "    - Try manually: ssh -p ${SSH_PORT} ${SSH_USER}@${INFRA_SSH_HOST}" >&2
  exit 1
fi
echo "SSH connectivity OK"
echo ""

# --- Tunnel cleanup on exit ---

trap 'bash "${SCRIPT_DIR}/ssh-tunnel.sh" stop 2>/dev/null' EXIT

# --- Environment for Playwright ---

LOCAL_PORT="${TUNNEL_LOCAL_PORT:-8443}"
export PROD_ODOO_URL="https://127.0.0.1:${LOCAL_PORT}"
export REPORT=1

# =============================================================================
# Stage 1: Smoke Tests (BLOCKING)
# =============================================================================

echo "=== Stage 1/5: Smoke Tests ==="
cd "$ODOOKIT_DIR"
bash "${SCRIPT_DIR}/ssh-tunnel.sh" start
npx playwright test --project=production tests/smoke/ || { echo "SMOKE TESTS FAILED — aborting production verification"; exit 1; }
echo ""

# =============================================================================
# Stage 2: Infrastructure Audit (non-blocking)
# =============================================================================

echo "=== Stage 2/5: Infrastructure Audit ==="
bash "${SCRIPT_DIR}/infra-audit.sh" --host "${INFRA_SSH_HOST}" --port "${SSH_PORT}" --user "${SSH_USER}" || echo "WARNING: Some infrastructure checks failed (non-blocking)"
echo ""

# =============================================================================
# Stage 3: Odoo Audit (non-blocking)
# =============================================================================

echo "=== Stage 3/5: Odoo Audit ==="
npx playwright test --project=production tests/audit/ || echo "WARNING: Some audit checks failed (non-blocking)"
echo ""

# =============================================================================
# Stage 4: User Creation (non-blocking)
# =============================================================================

echo "=== Stage 4/5: User Creation ==="
npx playwright test --project=production tests/production/ || echo "WARNING: Some user creation tasks failed — check report for details"
echo ""

# =============================================================================
# Stage 5: Backup Verification (non-blocking)
# =============================================================================

echo "=== Stage 5/5: Backup Verification ==="
bash "${SCRIPT_DIR}/verify-backup.sh" || echo "WARNING: Backup verification issues detected (non-blocking)"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "=========================================="
echo "  Production Verification Complete"
echo "=========================================="
echo "Report: odookit/reports/index.html"
echo ""
