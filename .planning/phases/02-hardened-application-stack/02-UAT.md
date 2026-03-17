---
status: testing
phase: 02-hardened-application-stack
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md]
started: 2026-03-13T12:00:00Z
updated: 2026-03-13T12:00:00Z
---

## Current Test

number: 1
name: Host Hardening Script Exists and Covers All 7 HARD Requirements
expected: |
  `scripts/01-harden-host.sh` exists, is executable-ready (bash script with shebang), and contains
  sections or comments referencing all 7 requirements: HARD-01 (SSH), HARD-02 (UFW), HARD-03 (fail2ban),
  HARD-04 (sysctl), HARD-05 (unattended-upgrades), HARD-06 (file permissions), HARD-07 (auditd).
  The script should check for root and validate config file presence before executing.
awaiting: user response

## Tests

### 1. Host Hardening Script Exists and Covers All 7 HARD Requirements
expected: `scripts/01-harden-host.sh` exists, is executable-ready (bash script with shebang), and contains sections or comments referencing all 7 requirements: HARD-01 (SSH), HARD-02 (UFW), HARD-03 (fail2ban), HARD-04 (sysctl), HARD-05 (unattended-upgrades), HARD-06 (file permissions), HARD-07 (auditd). The script should check for root and validate config file presence before executing.
result: [pending]

### 2. SSH Hardening Config Uses Correct OpenSSH 9.6 Directives
expected: `config/sshd-hardening.conf` sets Port 9292, disables root login, enforces key-only auth, and uses `KbdInteractiveAuthentication no` (not the deprecated `ChallengeResponseAuthentication`). Should include idle timeout and max auth tries.
result: [pending]

### 3. UFW Firewall Rules and Sysctl Hardening
expected: `config/sysctl-hardening.conf` enables `net.ipv4.ip_forward=1` (required for Docker), disables ICMP redirects, enables SYN cookies, and enables martian logging. The hardening script configures UFW with default-deny incoming.
result: [pending]

### 4. fail2ban Jails Configured Correctly
expected: `config/jail.local` defines an SSH jail using `backend = systemd` (no logpath, since Ubuntu 24.04 uses journald) and an Odoo login jail using `backend = auto` for file-based log polling.
result: [pending]

### 5. Auditd PCI-DSS Compliance Rules
expected: `config/audit.rules` contains rules covering PCI-DSS 10.2.1 through 10.2.7 (login events, privilege escalation, object access, audit log tampering, system-level changes). Rules should include Docker, SSH, and firewall activity tracking. Config should be made immutable at the end.
result: [pending]

### 6. Docker CE Installation Script with iptables:false
expected: `scripts/02-install-docker.sh` installs Docker CE from the official repo (not Ubuntu's docker.io), deploys `config/daemon.json` with `iptables: false` and log rotation (10MB/3-file). GPG key import uses `--batch --yes` for idempotent re-runs. Deploy user is added to the docker group.
result: [pending]

### 7. Docker Compose Stack with Dual Network Isolation
expected: `config/docker-compose.yml` defines Odoo 19 and PostgreSQL 18 services with two networks: a `frontend` bridge (Nginx-to-Odoo) and a `backend` internal network (Odoo-to-PG, no outbound). Containers bind to 127.0.0.1 only. Health checks are defined for both services. Resource limits are set (appropriate for s-2vcpu-4gb).
result: [pending]

### 8. Odoo Configuration Uses v19 Parameter Names
expected: `config/odoo.conf` uses `http_port`, `http_interface`, and `gevent_port` (not the deprecated `xmlrpc_port`/`longpolling_port`). Should set 3 workers + 1 cron worker, memory limits, proxy_mode=True, and `list_db = False`.
result: [pending]

### 9. PostgreSQL Tuned for 10-User Workload
expected: `config/postgresql.conf` sets `shared_buffers = 256MB`, `work_mem = 8MB`, `max_connections = 50`, and enables slow query logging.
result: [pending]

### 10. Deploy Script with Safe Password Injection
expected: `scripts/03-deploy-stack.sh` uses `awk` (not `sed`) to inject passwords from `.env` into `odoo.conf`, avoiding issues with special characters. Module initialization uses `docker compose run --rm` (not `exec` on a running container). Script sets up volume directories with correct ownership.
result: [pending]

### 11. Nginx SSL Config with Security Headers and Route Blocking
expected: `config/nginx/odoo.conf` configures TLS 1.2/1.3, HSTS, OCSP stapling with a DNS resolver directive (1.1.1.1/1.0.0.1), Content Security Policy, X-Frame-Options, and X-Content-Type-Options. Routes matching `/web/database/*` return 403. Uses DOMAIN_PLACEHOLDER for sed replacement during deployment.
result: [pending]

### 12. Pre-SSL Nginx Config for Certbot Challenge
expected: `config/nginx/odoo-pre-ssl.conf` is a minimal port-80 config that serves the `.well-known/acme-challenge/` location for certbot HTTP-01 verification. Uses DOMAIN_PLACEHOLDER for domain substitution.
result: [pending]

### 13. Nginx Setup Script with DNS Pre-Check
expected: `scripts/04-setup-nginx.sh` accepts domain and email as arguments. Performs a DNS resolution check (using `dig`) before running certbot to avoid wasting rate-limited attempts. Implements two-stage deploy: pre-SSL config first, certbot, then full SSL config. Sets up certbot auto-renewal via systemd timer.
result: [pending]

### 14. Terraform Firewall Updated for SSH Port 9292
expected: `infra/variables.tf` defines an `ssh_port` variable defaulting to 9292. `infra/main.tf` uses `var.ssh_port` in the cloud firewall SSH rule instead of hardcoded port 22.
result: [pending]

### 15. Environment Variables Template
expected: `config/.env.example` documents all required environment variables (database credentials, Odoo admin password) without containing any actual secret values. Serves as a template for creating the real `.env` file.
result: [pending]

## Summary

total: 15
passed: 0
issues: 0
pending: 15
skipped: 0

## Gaps

[none yet]
