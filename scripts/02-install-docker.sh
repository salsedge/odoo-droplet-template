#!/usr/bin/env bash
# =============================================================================
# 02-install-docker.sh — Docker CE & Compose v2 Installation
# =============================================================================
# Requirements: DOCK-01, DOCK-02, DOCK-07
#
# Installs Docker CE from the official Docker apt repository (NOT the Ubuntu
# docker.io package). Deploys daemon.json with iptables:false and log rotation.
#
# Run as root on the target droplet after 01-harden-host.sh.
#
# Usage:
#   ssh -p 9292 deploy@<droplet-ip> 'sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh'
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/config}"

echo "=== Phase 2 / Plan 02-01: Docker Installation ==="

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_DIR}/daemon.json" ]]; then
  echo "ERROR: Missing config file: ${CONFIG_DIR}/daemon.json" >&2
  exit 1
fi

# =============================================================================
# DOCK-01: Install Docker CE from official repository
# =============================================================================
echo "--- Installing Docker CE from official repo (DOCK-01) ---"

export DEBIAN_FRONTEND=noninteractive

# Remove any conflicting packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

# Install prerequisites
apt-get update -q
apt-get install -y -q \
  ca-certificates \
  curl \
  gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker apt repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker CE + Compose plugin
apt-get update -q
apt-get install -y -q \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

echo "Docker CE installed: $(docker --version)"
echo "Docker Compose v2 installed: $(docker compose version)"

# =============================================================================
# DOCK-02 + DOCK-07: Docker daemon configuration
# =============================================================================
echo "--- Deploying daemon.json (DOCK-02, DOCK-07) ---"

mkdir -p /etc/docker
cp "${CONFIG_DIR}/daemon.json" /etc/docker/daemon.json
chmod 644 /etc/docker/daemon.json

# Restart Docker to apply daemon.json
systemctl restart docker
systemctl enable docker

echo "Docker daemon configured: iptables=false, log rotation enabled"

# =============================================================================
# Add deploy user to docker group
# =============================================================================
if id -u deploy &>/dev/null; then
  usermod -aG docker deploy
  echo "User 'deploy' added to docker group"
fi

# =============================================================================
# Verify installation
# =============================================================================
echo ""
echo "--- Verifying Docker installation ---"
docker run --rm hello-world > /dev/null 2>&1 && echo "Docker: hello-world test passed" || echo "WARNING: hello-world test failed"

echo ""
echo "=== Docker Installation Complete ==="
echo "  DOCK-01: Docker CE from official apt repository"
echo "  DOCK-02: daemon.json with iptables: false"
echo "  DOCK-07: Log rotation: 10MB max-size, 3 max-file"
