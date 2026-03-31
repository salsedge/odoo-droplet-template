#!/usr/bin/env bash
# =============================================================================
# deploy-addon.sh — Deploy a Custom Odoo Module (Operational)
# =============================================================================
# Copies a local Odoo module directory to the droplet's custom-addons path,
# fixes ownership for the Odoo container (uid 100, gid 101), and restarts
# Odoo to detect the new/updated module.
#
# After running this script, install the module via the Odoo UI:
#   1. Settings -> Developer Tools -> Activate Developer Mode
#   2. Apps -> Update Apps List -> Update
#   3. Search for the module name -> Install
#
# Usage:
#   sudo bash scripts/ops/deploy-addon.sh <module-name>
#
# Example:
#   sudo bash scripts/ops/deploy-addon.sh my_custom_module
#
# This script runs ON THE DROPLET. Use `make deploy-addon` from your local
# machine to handle the SCP + remote execution.
# =============================================================================

set -euo pipefail

CUSTOM_ADDONS_DIR="/opt/odoo/custom-addons"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <module-name>" >&2
  echo "  Expects the module to already be in ${CUSTOM_ADDONS_DIR}/<module-name>" >&2
  exit 1
fi

MODULE_NAME="$1"
MODULE_PATH="${CUSTOM_ADDONS_DIR}/${MODULE_NAME}"

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (or via sudo)" >&2
  exit 1
fi

# Verify module exists
if [[ ! -d "$MODULE_PATH" ]]; then
  echo "ERROR: Module not found at ${MODULE_PATH}" >&2
  echo "  SCP the module first: scp -P 9292 -r /path/to/module deploy@host:${CUSTOM_ADDONS_DIR}/" >&2
  exit 1
fi

# Verify __manifest__.py exists (valid Odoo module)
if [[ ! -f "${MODULE_PATH}/__manifest__.py" ]]; then
  echo "ERROR: ${MODULE_PATH}/__manifest__.py not found — not a valid Odoo module" >&2
  exit 1
fi

echo "=== Deploy Addon: ${MODULE_NAME} ==="

# Fix ownership — Odoo container runs as uid 100, gid 101
# Parent directory stays owned by deploy user (for SCP writes)
echo "[1/3] Setting ownership (100:101)..."
chown -R 100:101 "${MODULE_PATH}"
# Ensure parent dir remains writable by deploy user for future SCPs
chown deploy:deploy "${CUSTOM_ADDONS_DIR}"
echo "  OK"

# Restart Odoo to detect new/updated module
echo "[2/3] Restarting Odoo..."
docker restart odoo-app > /dev/null
echo "  OK"

# Wait for health check
echo "[3/3] Waiting for Odoo health check..."
for i in $(seq 1 30); do
  if curl -fsS http://localhost:8069/web/health > /dev/null 2>&1; then
    echo "  Odoo is healthy"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "  WARNING: Odoo did not pass health check within 60s" >&2
    echo "  Check logs: docker logs odoo-app --tail 50" >&2
    exit 1
  fi
  sleep 2
done

echo ""
echo "=== Module ${MODULE_NAME} deployed ==="
echo ""
echo "Next steps — install via Odoo UI:"
echo "  1. Log in to your Odoo instance at https://<your-domain>/web"
echo "  2. Settings -> Developer Tools -> Activate Developer Mode"
echo "  3. Apps -> Update Apps List -> Update"
echo "  4. Search for '${MODULE_NAME}' -> Install"
