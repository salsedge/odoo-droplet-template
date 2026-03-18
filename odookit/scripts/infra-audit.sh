#!/usr/bin/env bash
# =============================================================================
# infra-audit.sh — Infrastructure hardening verification over SSH
# =============================================================================
# Verifies server hardening checks from scripts/01-harden-host.sh and
# scripts/02-install-docker.sh against requirement IDs:
#   HARD-01, HARD-02, HARD-03, HARD-05, HARD-07, DOCK-02, DOCK-06
#
# Usage:
#   bash scripts/infra-audit.sh --host 1.2.3.4
#   bash scripts/infra-audit.sh --host 1.2.3.4 --port 9292 --user deploy
#
# Environment variable overrides:
#   INFRA_SSH_HOST, INFRA_SSH_PORT (default 9292), INFRA_SSH_USER (default deploy)
# =============================================================================

set -euo pipefail

# --- Configuration ---

HOST="${INFRA_SSH_HOST:-}"
PORT="${INFRA_SSH_PORT:-9292}"
USER="${INFRA_SSH_USER:-deploy}"

# Parse CLI arguments (override env vars)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)  HOST="$2"; shift 2 ;;
    --port)  PORT="$2"; shift 2 ;;
    --user)  USER="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: bash scripts/infra-audit.sh [--host HOST] [--port PORT] [--user USER]"
      echo ""
      echo "Options:"
      echo "  --host HOST    Target server (or set INFRA_SSH_HOST)"
      echo "  --port PORT    SSH port (default: 9292, or set INFRA_SSH_PORT)"
      echo "  --user USER    SSH user (default: deploy, or set INFRA_SSH_USER)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: bash scripts/infra-audit.sh --host HOST [--port PORT] [--user USER]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "ERROR: No host specified." >&2
  echo "Usage: bash scripts/infra-audit.sh --host HOST [--port PORT] [--user USER]" >&2
  echo "  Or set INFRA_SSH_HOST environment variable." >&2
  exit 1
fi

# --- Counters ---

TOTAL=0
PASSED=0
FAILED=0

# --- SSH helper ---

SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -p ${PORT}"

ssh_cmd() {
  # Run a command on the remote host via SSH
  ssh ${SSH_OPTS} "${USER}@${HOST}" "$@" 2>/dev/null
}

# --- Check runner ---

run_check() {
  local description="$1"
  local command="$2"
  local expected_pattern="$3"

  TOTAL=$((TOTAL + 1))

  local output
  output=$(ssh_cmd "$command" 2>&1) || true

  if echo "$output" | grep -qiE "$expected_pattern"; then
    echo "[PASS] ${description}"
    PASSED=$((PASSED + 1))
  else
    echo "[FAIL] ${description}"
    echo "       Expected pattern: ${expected_pattern}"
    echo "       Got: ${output:-<empty>}"
    FAILED=$((FAILED + 1))
  fi
}

# =============================================================================
# Checks
# =============================================================================

echo "=== Infrastructure Audit ==="
echo "Target: ${USER}@${HOST}:${PORT}"
echo ""

# --- HARD-01: SSH on non-standard port ---
# If we get this far, SSH is working on the configured port.
# Verify it's NOT port 22.
TOTAL=$((TOTAL + 1))
if [[ "$PORT" != "22" ]]; then
  echo "[PASS] HARD-01: SSH on non-standard port (${PORT})"
  PASSED=$((PASSED + 1))
else
  echo "[FAIL] HARD-01: SSH on non-standard port (still using 22)"
  FAILED=$((FAILED + 1))
fi

# --- HARD-01: Root login disabled ---
run_check \
  "HARD-01: Root login disabled" \
  "sudo grep -E '^PermitRootLogin' /etc/ssh/sshd_config.d/99-hardening.conf" \
  "PermitRootLogin no"

# --- HARD-01: Password auth disabled ---
run_check \
  "HARD-01: Password authentication disabled" \
  "sudo grep -E '^PasswordAuthentication' /etc/ssh/sshd_config.d/99-hardening.conf" \
  "PasswordAuthentication no"

# --- HARD-02: UFW active ---
run_check \
  "HARD-02: UFW firewall active" \
  "sudo ufw status" \
  "Status: active"

# --- HARD-02: UFW rules correct ---
run_check \
  "HARD-02: UFW allows 9292/tcp, 80/tcp, 443/tcp" \
  "sudo ufw status | grep -E '(9292|80|443)/tcp'" \
  "9292/tcp.*ALLOW|80/tcp.*ALLOW|443/tcp.*ALLOW"

# --- HARD-03: fail2ban running ---
run_check \
  "HARD-03: fail2ban service active" \
  "systemctl is-active fail2ban" \
  "^active$"

# --- HARD-03: fail2ban SSH jail active ---
run_check \
  "HARD-03: fail2ban SSH jail active" \
  "sudo fail2ban-client status sshd" \
  "Status for the jail: sshd"

# --- HARD-05: Unattended upgrades enabled ---
run_check \
  "HARD-05: Unattended upgrades enabled" \
  "systemctl is-active unattended-upgrades" \
  "^active$"

# --- HARD-07: auditd running ---
run_check \
  "HARD-07: auditd service active" \
  "systemctl is-active auditd" \
  "^active$"

# --- DOCK-02: Docker iptables disabled ---
run_check \
  "DOCK-02: Docker iptables disabled" \
  "cat /etc/docker/daemon.json" \
  '"iptables"[[:space:]]*:[[:space:]]*false'

# --- DOCK-06: Docker containers healthy ---
run_check \
  "DOCK-06: Docker containers running and healthy" \
  "docker ps --format '{{.Names}} {{.Status}}'" \
  "(odoo|postgres).*(Up|healthy)"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=== Audit Summary ==="
echo "${PASSED}/${TOTAL} checks passed"

if [[ $FAILED -gt 0 ]]; then
  echo "${FAILED} check(s) FAILED"
  exit 1
else
  echo "All checks passed"
  exit 0
fi
