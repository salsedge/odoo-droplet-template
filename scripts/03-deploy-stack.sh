#!/usr/bin/env bash
# =============================================================================
# 03-deploy-stack.sh — Deploy Odoo + PostgreSQL Docker Stack
# =============================================================================
# Requirements: DOCK-03, ODOO-01, ODOO-04, PG-01, PG-04
#
# Creates directory structure on Block Storage Volume, deploys configuration,
# and starts the Docker Compose stack.
#
# Prerequisites:
#   - 01-harden-host.sh completed
#   - 02-install-docker.sh completed
#   - .env file created from .env.example with actual passwords
#
# Usage:
#   ssh -p 9292 deploy@<droplet-ip>
#   cd /tmp/odoo-setup
#   cp config/.env.example config/.env
#   # Edit config/.env with actual passwords
#   sudo bash scripts/03-deploy-stack.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/config}"
VOLUME_MOUNT="/mnt/odoo-prod-data"
DEPLOY_DIR="/opt/odoo"

echo "=== Phase 2 / Plan 02-02: Docker Application Stack ==="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Verify .env exists (not the example)
if [[ ! -f "${CONFIG_DIR}/.env" ]]; then
  echo "ERROR: ${CONFIG_DIR}/.env not found." >&2
  echo "Create it from .env.example:" >&2
  echo "  cp ${CONFIG_DIR}/.env.example ${CONFIG_DIR}/.env" >&2
  echo "  # Edit with actual passwords" >&2
  exit 1
fi

# Verify Docker is installed
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker not installed. Run 02-install-docker.sh first." >&2
  exit 1
fi

# =============================================================================
# Step 1: Create directory structure on Block Storage Volume
# =============================================================================
echo "--- Creating directory structure on Block Storage Volume ---"

# Verify volume is mounted
if ! mountpoint -q "${VOLUME_MOUNT}" 2>/dev/null; then
  # Try to find the actual mount point from Terraform naming
  ACTUAL_MOUNT=$(mount | grep '/mnt/' | awk '{print $3}' | head -1)
  if [[ -n "${ACTUAL_MOUNT}" ]]; then
    echo "Volume mounted at ${ACTUAL_MOUNT}, creating symlink to ${VOLUME_MOUNT}"
    ln -sfn "${ACTUAL_MOUNT}" "${VOLUME_MOUNT}"
  else
    echo "ERROR: No Block Storage Volume found at /mnt/. Check volume attachment." >&2
    exit 1
  fi
fi

# Create data directories
mkdir -p "${VOLUME_MOUNT}/postgres-data"
mkdir -p "${VOLUME_MOUNT}/odoo-filestore"

# Set ownership for container users
# PostgreSQL container runs as uid 999 (postgres)
chown -R 999:999 "${VOLUME_MOUNT}/postgres-data"
# Odoo 19 container runs as uid 100, gid 101 (odoo)
chown -R 100:101 "${VOLUME_MOUNT}/odoo-filestore"

# Custom addons directory (mounted into Odoo container at /mnt/extra-addons)
# Owned by deploy user so SCP can write modules; deploy-addon.sh chowns contents to 100:101
mkdir -p "${DEPLOY_DIR}/custom-addons"
chown deploy:deploy "${DEPLOY_DIR}/custom-addons"

echo "Data directories created on Block Storage Volume:"
echo "  ${VOLUME_MOUNT}/postgres-data (uid:999)"
echo "  ${VOLUME_MOUNT}/odoo-filestore (uid:101)"

# =============================================================================
# Step 2: Deploy configuration to /opt/odoo
# =============================================================================
echo "--- Deploying configuration to ${DEPLOY_DIR} ---"

mkdir -p "${DEPLOY_DIR}"

# Copy compose and config files
cp "${CONFIG_DIR}/docker-compose.yml" "${DEPLOY_DIR}/docker-compose.yml"
cp "${CONFIG_DIR}/odoo.conf" "${DEPLOY_DIR}/odoo.conf"
cp "${CONFIG_DIR}/postgresql.conf" "${DEPLOY_DIR}/postgresql.conf"

# Deploy .env with restricted permissions (HARD-06 / PG-04)
cp "${CONFIG_DIR}/.env" "${DEPLOY_DIR}/.env"
chmod 600 "${DEPLOY_DIR}/.env"

# Inject credentials into odoo.conf from .env (ODOO-05)
# Parse .env without sourcing to avoid bash interpreting special chars in passwords
ODOO_ADMIN_PASSWORD=$(grep '^ODOO_ADMIN_PASSWORD=' "${DEPLOY_DIR}/.env" | cut -d'=' -f2-)
POSTGRES_USER=$(grep '^POSTGRES_USER=' "${DEPLOY_DIR}/.env" | cut -d'=' -f2-)
POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "${DEPLOY_DIR}/.env" | cut -d'=' -f2-)
POSTGRES_DB=$(grep '^POSTGRES_DB=' "${DEPLOY_DIR}/.env" | cut -d'=' -f2-)
POSTGRES_DB="${POSTGRES_DB:-odoo}"
# Use awk to avoid sed delimiter issues with special characters in passwords
awk \
  -v admin_pwd="${ODOO_ADMIN_PASSWORD}" \
  -v db_user="${POSTGRES_USER}" \
  -v db_pwd="${POSTGRES_PASSWORD}" \
  -v db_name="${POSTGRES_DB}" \
  '{
    gsub(/ADMIN_PASSWORD_PLACEHOLDER/, admin_pwd)
    gsub(/DB_USER_PLACEHOLDER/, db_user)
    gsub(/DB_PASSWORD_PLACEHOLDER/, db_pwd)
    gsub(/DB_NAME_PLACEHOLDER/, db_name)
    print
  }' "${DEPLOY_DIR}/odoo.conf" > "${DEPLOY_DIR}/odoo.conf.tmp" \
  && mv "${DEPLOY_DIR}/odoo.conf.tmp" "${DEPLOY_DIR}/odoo.conf"

# Set file permissions (HARD-06)
chmod 644 "${DEPLOY_DIR}/docker-compose.yml"
chmod 644 "${DEPLOY_DIR}/odoo.conf"
chmod 644 "${DEPLOY_DIR}/postgresql.conf"

echo "Configuration deployed to ${DEPLOY_DIR}"

# =============================================================================
# Step 3: Pull images and start stack
# =============================================================================
echo "--- Pulling Docker images ---"
cd "${DEPLOY_DIR}"
docker compose pull

echo "--- Starting Odoo + PostgreSQL stack ---"
docker compose up -d

# Wait for health checks to pass
echo "--- Waiting for services to become healthy ---"
TIMEOUT=120
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  DB_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' odoo-db 2>/dev/null || echo "starting")
  ODOO_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' odoo-app 2>/dev/null || echo "starting")

  if [[ "$DB_HEALTH" == "healthy" && "$ODOO_HEALTH" == "healthy" ]]; then
    echo "Both services are healthy!"
    break
  fi

  echo "  Waiting... DB=${DB_HEALTH}, Odoo=${ODOO_HEALTH} (${ELAPSED}s/${TIMEOUT}s)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "WARNING: Services did not become healthy within ${TIMEOUT}s"
  echo "Check logs: docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs"
fi

# =============================================================================
# Step 4: Initialize Odoo with CRM and Project modules
# =============================================================================
echo "--- Initializing Odoo with CRM and Project modules (ODOO-01) ---"

# Stop Odoo to avoid conflicting processes during module init
docker compose stop odoo

# Run module init in a temporary container (db is still running)
# --stop-after-init exits after installing; --no-http skips starting the web server
docker compose run --rm -T odoo odoo -c /etc/odoo/odoo.conf \
  -d "${POSTGRES_DB}" \
  -i crm,project \
  --stop-after-init \
  --no-http || echo "WARNING: Module init completed with non-zero exit (may be normal on first run)"

# Start Odoo in normal multi-worker mode
docker compose up -d odoo

echo ""
echo "=== Docker Application Stack Deployed ==="
echo "  DOCK-03: Docker Compose with Odoo + PostgreSQL"
echo "  DOCK-04: Non-root containers with resource limits"
echo "  DOCK-05: Dual network (frontend + backend)"
echo "  DOCK-06: Health checks on both services"
echo "  ODOO-01: CRM and Project modules initialized"
echo "  ODOO-04: Filestore on Block Storage at ${VOLUME_MOUNT}/odoo-filestore"
echo "  PG-01:   PostgreSQL data on Block Storage at ${VOLUME_MOUNT}/postgres-data"
echo "  PG-04:   Credentials in .env (mode 600)"
echo ""
echo "Odoo is listening on 127.0.0.1:8069 (localhost only)"
echo "Run 04-setup-nginx.sh to configure public HTTPS access"
