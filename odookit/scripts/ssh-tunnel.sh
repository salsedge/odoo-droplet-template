#!/usr/bin/env bash
# =============================================================================
# ssh-tunnel.sh -- SSH tunnel lifecycle manager for production Odoo
# =============================================================================
# Manages an SSH tunnel forwarding remote port 443 (Nginx HTTPS) to a local
# port for Playwright production testing. The tunnel goes through Nginx so
# tests verify SSL and security headers end-to-end.
#
# Usage:
#   bash scripts/ssh-tunnel.sh start    # Open tunnel (default)
#   bash scripts/ssh-tunnel.sh stop     # Close tunnel
#
# Environment variables:
#   INFRA_SSH_HOST       (required) Droplet IP or hostname
#   INFRA_SSH_PORT       (default: 9292) SSH port on remote host
#   INFRA_SSH_USER       (default: deploy) SSH user on remote host
#   TUNNEL_LOCAL_PORT    (default: 8443) Local port to forward to
# =============================================================================

set -euo pipefail

# --- Configuration ---

ACTION="${1:-start}"
REMOTE_HOST="${INFRA_SSH_HOST:?INFRA_SSH_HOST not set}"
REMOTE_PORT="${INFRA_SSH_PORT:-9292}"
REMOTE_USER="${INFRA_SSH_USER:-deploy}"
LOCAL_PORT="${TUNNEL_LOCAL_PORT:-8443}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 -o ServerAliveCountMax=3"

# --- Functions ---

kill_tunnel() {
  lsof -ti:"${LOCAL_PORT}" | xargs kill 2>/dev/null || true
}

# --- Actions ---

case "$ACTION" in
  start)
    echo "Starting SSH tunnel: localhost:${LOCAL_PORT} -> ${REMOTE_HOST}:443"

    # Kill any existing process on the local port
    kill_tunnel
    sleep 1

    # Open tunnel: remote 443 -> local $LOCAL_PORT
    ssh -f -N -L "${LOCAL_PORT}:localhost:443" \
      -p "${REMOTE_PORT}" ${SSH_OPTS} \
      "${REMOTE_USER}@${REMOTE_HOST}"

    echo "SSH tunnel open: localhost:${LOCAL_PORT} -> ${REMOTE_HOST}:443"
    echo "Playwright baseURL: https://localhost:${LOCAL_PORT}"
    ;;

  stop)
    echo "Stopping SSH tunnel on port ${LOCAL_PORT}..."
    kill_tunnel
    echo "SSH tunnel closed on port ${LOCAL_PORT}"
    ;;

  *)
    echo "Usage: $(basename "$0") {start|stop}" >&2
    exit 1
    ;;
esac
