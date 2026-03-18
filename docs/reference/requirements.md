# Requirements Reference

All 48 v1 requirements for the Odoo 19.x Production Build. Each requirement has a prefixed ID used across planning docs, scripts, and config files.

---

## Infrastructure as Code (Phase 1)

| ID | Requirement | Status |
|----|-------------|--------|
| IAC-01 | Terraform provisions DigitalOcean VPC with private networking | :white_check_mark: Complete |
| IAC-02 | Terraform provisions DO firewall rules (SSH, HTTP, HTTPS only) | :white_check_mark: Complete |
| IAC-03 | Terraform provisions Odoo application droplet (Ubuntu 24.04 LTS) | :white_check_mark: Complete |
| IAC-04 | Terraform provisions and attaches DO Block Storage Volume | :white_check_mark: Complete |
| IAC-05 | Terraform configures DO Spaces bucket for remote state backend | :white_check_mark: Complete |
| IAC-06 | Terraform uses tfvars for environment-specific configuration | :white_check_mark: Complete |
| IAC-07 | Terraform executes bootstrap scripts via remote-exec provisioners | :white_check_mark: Complete |
| IAC-08 | Terraform outputs critical info (droplet IP, volume path, Spaces endpoint) | :white_check_mark: Complete |

## System Hardening (Phase 2)

| ID | Requirement | Status |
|----|-------------|--------|
| HARD-01 | SSH hardened (key-only auth, no root login, port 9292, idle timeout) | :white_check_mark: Complete |
| HARD-02 | UFW configured with default-deny and explicit allow rules | :white_check_mark: Complete |
| HARD-03 | fail2ban installed with SSH and Odoo login jails | :white_check_mark: Complete |
| HARD-04 | Kernel parameters hardened (sysctl) | :white_check_mark: Complete |
| HARD-05 | Automatic unattended security updates enabled | :white_check_mark: Complete |
| HARD-06 | File permissions restricted on sensitive configs | :white_check_mark: Complete |
| HARD-07 | auditd installed for PCI-DSS 10.x compliance logging | :white_check_mark: Complete |

## Docker and Containers (Phase 2)

| ID | Requirement | Status |
|----|-------------|--------|
| DOCK-01 | Docker CE from official apt repository | :white_check_mark: Complete |
| DOCK-02 | Docker daemon with `iptables: false` | :white_check_mark: Complete |
| DOCK-03 | Docker Compose deploys Odoo + PostgreSQL as separate services | :white_check_mark: Complete |
| DOCK-04 | Non-root containers with resource limits (CPU, memory) | :white_check_mark: Complete |
| DOCK-05 | Dual network isolation (frontend + backend) | :white_check_mark: Complete |
| DOCK-06 | Container health checks for Odoo and PostgreSQL | :white_check_mark: Complete |
| DOCK-07 | Docker log rotation configured | :white_check_mark: Complete |

## Odoo Application (Phase 2)

| ID | Requirement | Status |
|----|-------------|--------|
| ODOO-01 | Odoo Community with CRM and Project modules | :white_check_mark: Complete |
| ODOO-02 | Worker count and memory tuned for 10 users | :white_check_mark: Complete |
| ODOO-03 | Database manager disabled (`list_db = False`) | :white_check_mark: Complete |
| ODOO-04 | Filestore on Block Storage Volume | :white_check_mark: Complete |
| ODOO-05 | Admin password set, db_manager routes blocked | :white_check_mark: Complete |

## PostgreSQL Database (Phase 2)

| ID | Requirement | Status |
|----|-------------|--------|
| PG-01 | PostgreSQL 18 with data on Block Storage | :white_check_mark: Complete |
| PG-02 | Tuned for 10-user workload | :white_check_mark: Complete |
| PG-03 | Accessible only via Docker backend network | :white_check_mark: Complete |
| PG-04 | Credentials in .env with restricted permissions | :white_check_mark: Complete |

## Reverse Proxy and SSL (Phase 2)

| ID | Requirement | Status |
|----|-------------|--------|
| PROXY-01 | Nginx on host as reverse proxy | :white_check_mark: Complete |
| PROXY-02 | Let's Encrypt SSL via HTTP-01 challenge | :white_check_mark: Complete |
| PROXY-03 | HTTPS redirect + HSTS | :white_check_mark: Complete |
| PROXY-04 | Block /web/database/* routes | :white_check_mark: Complete |
| PROXY-05 | Certbot auto-renewal via systemd timer | :white_check_mark: Complete |

## Backup and Recovery (Phase 3)

| ID | Requirement | Status |
|----|-------------|--------|
| BACK-01 | Daily pg_dump to local Block Storage | :white_check_mark: Complete |
| BACK-02 | Backup sync to DO Spaces via rclone | :white_check_mark: Complete |
| BACK-03 | Retention policy enforced (7 daily + 4 weekly local, 30 days Spaces) | :white_check_mark: Complete |
| BACK-04 | Tested restore procedure with verification | :white_check_mark: Complete |

## Documentation (Phase 3)

| ID | Requirement | Status |
|----|-------------|--------|
| DOC-01 | Architecture overview with topology diagram | :white_check_mark: Complete |
| DOC-02 | Deployment runbook | :white_check_mark: Complete |
| DOC-03 | Operational procedures | :white_check_mark: Complete |
| DOC-04 | Enterprise migration path | :white_check_mark: Complete |

## Monitoring (Phase 5 — Blocked)

!!! warning "Blocked on Icinga2 master"
    Phase 5 cannot proceed until the external Icinga2 master server is built and operational.

| ID | Requirement | Status |
|----|-------------|--------|
| MON-01 | Icinga2 agent registered with master | :hourglass: Pending |
| MON-02 | Docker container health monitoring | :hourglass: Pending |
| MON-03 | PostgreSQL checks (connections, size, latency) | :hourglass: Pending |
| MON-04 | System resource checks (CPU, memory, disk, load) | :hourglass: Pending |
| MON-05 | Service definitions for master integration | :hourglass: Pending |

---

## Coverage Summary

- **v1 requirements:** 48 total
- **Complete:** 43 (Phases 1-3)
- **Pending:** 5 (Phase 5 — blocked)
- **Unmapped:** 0
