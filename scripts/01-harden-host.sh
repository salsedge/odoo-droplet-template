#!/usr/bin/env bash
# =============================================================================
# 01-harden-host.sh — PCI-DSS Host Hardening
# =============================================================================
# Requirements: HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, HARD-06, HARD-07
#
# Run as root on the target droplet. Assumes:
#   - Ubuntu 24.04 LTS
#   - SSH keys already provisioned (Phase 1 Terraform)
#   - Cloud firewall already updated to allow port 9292 (terraform apply)
#   - Config files available in the same directory or specified via CONFIG_DIR
#
# Usage:
#   scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/
#   ssh root@<droplet-ip> 'bash /tmp/odoo-setup/scripts/01-harden-host.sh'
# =============================================================================

set -euo pipefail

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$(dirname "$SCRIPT_DIR")/config}"

echo "=== Phase 2 / Plan 02-01: Host Hardening ==="
echo "Config directory: ${CONFIG_DIR}"

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root" >&2
  exit 1
fi

# Verify config files exist
for f in sshd-hardening.conf sysctl-hardening.conf jail.local audit.rules; do
  if [[ ! -f "${CONFIG_DIR}/${f}" ]]; then
    echo "ERROR: Missing config file: ${CONFIG_DIR}/${f}" >&2
    exit 1
  fi
done

# =============================================================================
# Step 1: System update
# =============================================================================
echo "--- Updating system packages ---"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q

# =============================================================================
# Step 2: Install required packages
# =============================================================================
echo "--- Installing hardening packages ---"
apt-get install -y -q \
  ufw \
  fail2ban \
  auditd \
  audispd-plugins \
  unattended-upgrades \
  apt-listchanges

# =============================================================================
# HARD-01: SSH Hardening
# =============================================================================
echo "--- Configuring SSH hardening (HARD-01) ---"

# Deploy drop-in config (Ubuntu 24.04 uses Include /etc/ssh/sshd_config.d/*.conf)
cp "${CONFIG_DIR}/sshd-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf
chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf

# Create a deploy user for SSH access (no root login after hardening)
if ! id -u deploy &>/dev/null; then
  useradd -m -s /bin/bash -G sudo deploy
  # Copy root's authorized_keys to deploy user
  mkdir -p /home/deploy/.ssh
  cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
  chown -R deploy:deploy /home/deploy/.ssh
  chmod 700 /home/deploy/.ssh
  chmod 600 /home/deploy/.ssh/authorized_keys
  # Allow deploy user to sudo without password (for provisioning)
  echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
  chmod 440 /etc/sudoers.d/deploy
  echo "Created deploy user with sudo and SSH key access"
fi

# Validate sshd config before restarting
sshd -t -f /etc/ssh/sshd_config
echo "SSH config validated"

# Restart SSH (connection on port 22 stays alive; new connections use 9292)
systemctl restart sshd
echo "SSH restarted on port 9292"

# =============================================================================
# HARD-02: UFW Firewall
# =============================================================================
echo "--- Configuring UFW firewall (HARD-02) ---"

# Reset UFW to defaults
ufw --force reset

# Default policies: deny incoming, allow outgoing
ufw default deny incoming
ufw default allow outgoing

# Allow SSH on non-standard port
ufw allow 9292/tcp comment 'SSH'

# Allow HTTP (certbot ACME challenge + redirect)
ufw allow 80/tcp comment 'HTTP'

# Allow HTTPS
ufw allow 443/tcp comment 'HTTPS'

# Enable UFW (--force skips confirmation prompt)
ufw --force enable
echo "UFW enabled with rules: 9292/tcp, 80/tcp, 443/tcp"

# =============================================================================
# HARD-03: fail2ban
# =============================================================================
echo "--- Configuring fail2ban (HARD-03) ---"

# Deploy jail configuration
cp "${CONFIG_DIR}/jail.local" /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/jail.local

# Create Odoo login failure filter
mkdir -p /etc/fail2ban/filter.d
cat > /etc/fail2ban/filter.d/odoo-login.conf << 'FILTER'
[Definition]
failregex = ^ \d+ WARNING \S+ odoo\.http\.rpc\.request: Login failed for db:\S+ login:\S+ from <HOST>
ignoreregex =
FILTER
chmod 644 /etc/fail2ban/filter.d/odoo-login.conf

systemctl enable fail2ban
systemctl restart fail2ban
echo "fail2ban configured with SSH and Odoo login jails"

# =============================================================================
# HARD-04: Kernel Hardening (sysctl)
# =============================================================================
echo "--- Applying kernel hardening (HARD-04) ---"

cp "${CONFIG_DIR}/sysctl-hardening.conf" /etc/sysctl.d/99-hardening.conf
chmod 644 /etc/sysctl.d/99-hardening.conf

# Apply immediately
sysctl --system > /dev/null 2>&1
echo "Kernel parameters hardened"

# =============================================================================
# HARD-05: Unattended Security Updates
# =============================================================================
echo "--- Configuring unattended upgrades (HARD-05) ---"

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'APT'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
APT

systemctl enable unattended-upgrades
echo "Unattended security upgrades enabled"

# =============================================================================
# HARD-06: File Permissions (system files)
# =============================================================================
echo "--- Restricting file permissions (HARD-06) ---"

# SSH directory and configs
chmod 700 /etc/ssh
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config.d/*

# Restrict shadow and gshadow
chmod 640 /etc/shadow
chmod 640 /etc/gshadow

echo "System file permissions restricted"

# =============================================================================
# HARD-07: auditd (PCI-DSS 10.x)
# =============================================================================
echo "--- Configuring auditd (HARD-07) ---"

cp "${CONFIG_DIR}/audit.rules" /etc/audit/rules.d/99-pci-dss.rules
chmod 640 /etc/audit/rules.d/99-pci-dss.rules

# Load rules
systemctl enable auditd
systemctl restart auditd
augenrules --load 2>/dev/null || true
echo "auditd configured with PCI-DSS 10.x rules"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Host Hardening Complete ==="
echo "  HARD-01: SSH on port 9292, key-only, no root login"
echo "  HARD-02: UFW default-deny, allow 9292/80/443"
echo "  HARD-03: fail2ban SSH + Odoo login jails"
echo "  HARD-04: Kernel parameters hardened"
echo "  HARD-05: Unattended security upgrades enabled"
echo "  HARD-06: File permissions restricted"
echo "  HARD-07: auditd PCI-DSS 10.x rules loaded"
echo ""
echo "IMPORTANT: SSH is now on port 9292. Reconnect with:"
echo "  ssh -p 9292 deploy@<droplet-ip>"
