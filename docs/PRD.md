# Product Requirements Document: Odoo 19.x Production Build

**Version:** 1.0
**Date:** 2026-02-20
**Status:** Phase 2 of 5 — In Progress
**Owner:** SALS Edge / Bibbeo Infrastructure

---

## 1. Overview

This project delivers a production-ready, Infrastructure-as-Code deployment of Odoo Community 19.x on DigitalOcean. A single `terraform apply` provisions all cloud infrastructure, and a set of sequential scripts harden the host, deploy containerized Odoo + PostgreSQL, and configure Nginx with Let's Encrypt SSL — all PCI-DSS compliant, reproducible, and ready for a 10-user CRM/project management workload from day one.

## 2. Problem Statement

Bibbeo needs a self-hosted Odoo instance for CRM and project management that meets enterprise security requirements without the complexity of managed Kubernetes or multi-cloud architectures. The deployment must be:

- **Reproducible** — teardown and rebuild from code, no snowflake servers
- **Secure** — PCI-DSS baseline hardening at host, container, application, and network layers
- **Monitored** — integrated with the existing Icinga2 master for operational visibility
- **Right-sized** — 10 concurrent users, not over-engineered for scale that isn't needed

## 3. Goals and Non-Goals

### Goals (v1)

- Terraform-managed DigitalOcean infrastructure (VPC, firewall, droplet, volume, Spaces)
- PCI-DSS host hardening (SSH, UFW, fail2ban, sysctl, auditd, unattended-upgrades)
- Containerized Odoo 19 + PostgreSQL 18 with Docker Compose
- Docker security (non-root, resource limits, iptables:false, dual-network isolation)
- Nginx reverse proxy with Let's Encrypt SSL and security headers
- Icinga2 agent with custom container/system/database checks
- Automated daily backups to local volume + DO Spaces
- Tested restore procedure with verification
- Complete documentation (architecture, runbook, operational procedures)

### Non-Goals (deferred to v2 or out of scope)

| Item | Reason |
|------|--------|
| WireGuard VPN gateway | Deferred to v2 — single droplet sufficient for v1 |
| Odoo Enterprise edition | Community covers CRM + Project needs |
| CI/CD pipeline | Manual deployment acceptable at this scale |
| Staging/dev environments | Production-only for v1 |
| Horizontal Odoo scaling | Vertical scaling sufficient for 10 users |
| Kubernetes / Docker Swarm | Massively overkill for 10 users |
| Database replication | Backup/restore meets RTO target |
| ELK/EFK log aggregation | Docker log rotation + Icinga2 sufficient |
| External secrets manager (Vault) | .env with restricted permissions sufficient at this scale |
| PgBouncer connection pooling | Not needed at 10 users with correct db_maxconn |
| Prometheus/Grafana | Icinga2 provides sufficient visibility |

## 4. Target Users

| User | Role | Access |
|------|------|--------|
| CRM/PM team (10 users) | Create leads, manage projects/tasks | HTTPS via browser, restricted Odoo permissions |
| Odoo admin (1 user) | Install modules, manage users, system settings | HTTPS via browser, Odoo admin role |
| Infrastructure operator | Deploy, update, monitor, troubleshoot | SSH (port 9292, key-only), Icinga2 dashboard |

## 5. Architecture

### 5.1 Topology

```
                    ┌─────────────────────────────────────────────────────┐
                    │              DigitalOcean VPC (10.100.0.0/24)       │
                    │                                                     │
  Internet          │   ┌───────────────────────────────────────────┐     │
     │              │   │        Ubuntu 24.04 Droplet               │     │
     │              │   │        (s-2vcpu-4gb / $24 mo)             │     │
     ▼              │   │                                           │     │
 ┌───────┐  :443   │   │   ┌─────────┐     ┌──────────────────┐   │     │
 │  DO   │────────────▶│   │  Nginx  │────▶│  Odoo 19         │   │     │
 │  FW   │  :80    │   │   │  (host) │     │  (container)     │   │     │
 │       │────────────▶│   │         │     │  127.0.0.1:8069  │   │     │
 │       │  :9292  │   │   └─────────┘     │  127.0.0.1:8072  │   │     │
 │       │────────────▶│   SSH (deploy)    │                   │   │     │
 └───────┘         │   │                   │  frontend network │   │     │
                   │   │                   └────────┬──────────┘   │     │
                   │   │                            │              │     │
                   │   │                    backend network        │     │
                   │   │                    (internal, no          │     │
                   │   │                     outbound)             │     │
                   │   │                            │              │     │
                   │   │                   ┌────────▼──────────┐   │     │
                   │   │                   │  PostgreSQL 18    │   │     │
                   │   │                   │  (container)      │   │     │
                   │   │                   │  No published     │   │     │
                   │   │                   │  ports            │   │     │
                   │   │                   └────────┬──────────┘   │     │
                   │   │                            │              │     │
                   │   │                   ┌────────▼──────────┐   │     │
                   │   │                   │  DO Block Storage │   │     │
                   │   │                   │  Volume (25 GB)   │   │     │
                   │   │                   │  /mnt/odoo-prod-  │   │     │
                   │   │                   │  data/            │   │     │
                   │   │                   │  ├─ postgres-data/ │   │     │
                   │   │                   │  └─ odoo-filestore/│   │     │
                   │   │                   └───────────────────┘   │     │
                   │   └───────────────────────────────────────────┘     │
                   └─────────────────────────────────────────────────────┘
```

### 5.2 Network Design

| Network | Purpose | Containers |
|---------|---------|------------|
| `odoo-frontend` (bridge) | Host Nginx ↔ Odoo | Odoo |
| `odoo-backend` (bridge, internal) | Odoo ↔ PostgreSQL, no outbound | Odoo, PostgreSQL |

Docker daemon runs with `iptables: false` — UFW is the single source of truth for all firewall rules. Containers bind to `127.0.0.1` only; public traffic routes through Nginx.

### 5.3 Resource Allocation

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Droplet | 2 vCPU | 4 GB | 80 GB (ephemeral) |
| Odoo container | 1.0 CPU limit | 2 GB limit, 768 MB reserved | Filestore on Block Storage |
| PostgreSQL container | 0.5 CPU limit | 1.2 GB limit, 512 MB reserved | Data on Block Storage |
| Block Storage Volume | — | — | 25 GB (ext4) |

Odoo runs 3 workers + 1 cron thread, tuned for 10 concurrent users on 2 vCPU / 4 GB.

## 6. Requirements

### 6.1 Infrastructure as Code (Phase 1 — Complete)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| IAC-01 | Terraform provisions DigitalOcean VPC with private networking | VPC created in target region with specified CIDR |
| IAC-02 | Terraform provisions DO firewall rules (SSH, HTTP, HTTPS only) | SSH restricted to operator IPs, HTTP/HTTPS open |
| IAC-03 | Terraform provisions Odoo droplet (Ubuntu 24.04 LTS) | Droplet created with specified size, image, SSH keys |
| IAC-04 | Terraform provisions and attaches Block Storage Volume | Volume created, formatted ext4, attached to droplet |
| IAC-05 | Terraform configures DO Spaces for remote state backend | State stored in encrypted Spaces bucket |
| IAC-06 | Terraform uses tfvars for environment-specific config | No hardcoded secrets in HCL files |
| IAC-07 | Terraform executes bootstrap via remote-exec provisioners | SSH connectivity and block device verified |
| IAC-08 | Terraform outputs critical info | Droplet IP, volume mount path, Spaces endpoint |

### 6.2 System Hardening (Phase 2)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| HARD-01 | SSH hardened | Key-only auth, no root login, port 9292, idle timeout, MaxAuthTries 3 |
| HARD-02 | UFW firewall configured | Default deny, allow 9292/tcp, 80/tcp, 443/tcp |
| HARD-03 | fail2ban installed | SSH jail + Odoo login failure jail, 10-min ban after 5 failures |
| HARD-04 | Kernel parameters hardened | SYN cookies, no IP forwarding, no ICMP redirects, anti-spoofing |
| HARD-05 | Automatic security updates | unattended-upgrades for security origins, auto-clean weekly |
| HARD-06 | File permissions restricted | SSH dir 700, sshd_config 600, .env 600, shadow 640 |
| HARD-07 | auditd for PCI-DSS 10.x | Rules for admin actions, auth changes, file ops, time changes, immutable config |

### 6.3 Docker and Containers (Phase 2)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| DOCK-01 | Docker CE from official repository | Not Ubuntu docker.io package |
| DOCK-02 | Docker daemon with iptables:false | UFW is sole firewall authority |
| DOCK-03 | Docker Compose deploys Odoo + PostgreSQL | Two services, separate containers |
| DOCK-04 | Non-root containers with resource limits | CPU/memory limits and reservations set |
| DOCK-05 | Dual network isolation | frontend (bridge) + backend (bridge, internal) |
| DOCK-06 | Health checks on both services | pg_isready for DB, curl /web/health for Odoo |
| DOCK-07 | Docker log rotation | json-file driver, 10 MB max-size, 3 files max |

### 6.4 Odoo Application (Phase 2)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| ODOO-01 | Odoo Community with CRM + Project modules | Modules installed and functional after deploy |
| ODOO-02 | Worker count and memory tuned for 10 users | 3 workers, 1 cron, 768 MB soft / 1 GB hard per worker |
| ODOO-03 | Database manager disabled | `list_db = False` in odoo.conf |
| ODOO-04 | Filestore on Block Storage Volume | `/mnt/odoo-prod-data/odoo-filestore` |
| ODOO-05 | Admin password set, db_manager routes blocked | Password from .env, Nginx returns 403 on `/web/database/*` |

### 6.5 PostgreSQL Database (Phase 2)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| PG-01 | PostgreSQL 18 with data on Block Storage | `/mnt/odoo-prod-data/postgres-data` |
| PG-02 | Tuned for 10-user workload | shared_buffers 256 MB, work_mem 8 MB, max_connections 50 |
| PG-03 | Accessible only via Docker backend network | No published ports, internal network |
| PG-04 | Credentials in .env with restricted permissions | .env mode 600 |

### 6.6 Reverse Proxy and SSL (Phase 2)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| PROXY-01 | Nginx on host as reverse proxy | Proxies to 127.0.0.1:8069 and 8072 |
| PROXY-02 | Let's Encrypt SSL via HTTP-01 challenge | Valid cert, certbot webroot method |
| PROXY-03 | HTTPS redirect + HSTS | 301 redirect, HSTS max-age=31536000 |
| PROXY-04 | Block /web/database/* routes | Returns 403 |
| PROXY-05 | Certbot auto-renewal | systemd timer, twice daily with random delay |

### 6.7 Backup and Recovery (Phase 3)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| BACK-01 | Daily pg_dump to local Block Storage | Automated via cron/systemd timer |
| BACK-02 | Backup sync to DO Spaces via rclone | Offsite copy after each local dump |
| BACK-03 | Retention policy enforced | 7 daily + 4 weekly local, 30 days on Spaces |
| BACK-04 | Tested restore procedure | Documented, executed, verified against fresh container |

### 6.8 Documentation (Phase 3)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| DOC-01 | Architecture overview with topology diagram | Network, containers, volumes, firewalls documented |
| DOC-02 | Deployment runbook | Fresh clone → running Odoo, step-by-step |
| DOC-03 | Operational procedures | Backup, restore, Odoo updates, resource scaling |
| DOC-04 | Enterprise migration path | Short getting-started doc for edition upgrade |

### 6.9 Monitoring (Phase 5)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| MON-01 | Icinga2 agent registered with master | Appears in Icinga2 dashboard |
| MON-02 | Docker container health monitoring | Alert on stop, restart count, resource usage |
| MON-03 | PostgreSQL checks | Connections, database size, query latency |
| MON-04 | System resource checks | CPU, memory, disk, load average |
| MON-05 | Service definitions for master integration | Config files provided and documented |

## 7. Phased Delivery

### Phase 1: Terraform Foundation and Compute — COMPLETE
**Delivered:** VPC, cloud firewall, Ubuntu 24.04 droplet, Block Storage Volume, Spaces state backend
**Completed:** 2026-02-21

### Phase 2: Hardened Application Stack — COMPLETE
**Delivers:** PCI-DSS host hardening, Docker + Compose stack, Nginx/SSL reverse proxy
**Requirements:** HARD-01–07, DOCK-01–07, ODOO-01–05, PG-01–04, PROXY-01–05 (28 requirements)
**Success Criteria:**
1. SSH requires key auth on port 9292 — password and root login rejected
2. `https://[domain]` loads Odoo login with valid cert, HSTS, HTTP→HTTPS redirect
3. CRM and Project modules work, database manager disabled, `/web/database/*` returns 403
4. PostgreSQL reachable only from Odoo container — no published ports, no outbound internet
5. All persistent data on Block Storage Volume

### Phase 3: Backup, Recovery, and Documentation
**Delivers:** Automated backups, tested restore, complete documentation
**Requirements:** BACK-01–04, DOC-01–04

### Phase 4: Deployment Verification and User Setup
**Delivers:** Real user accounts, end-to-end verification of Phases 1-3
**Covers:** Cross-cutting validation of IAC, HARD, DOCK, ODOO, PG, PROXY, BACK, DOC requirements

### Phase 5: Monitoring
**Delivers:** Icinga2 agent, custom checks for containers/PostgreSQL/system resources
**Requirements:** MON-01–05
**Note:** Blocked on external Icinga2 master being built and operational

## 8. Security and Compliance

### PCI-DSS Controls Mapping

| PCI-DSS Requirement | Implementation |
|---------------------|----------------|
| 1.x — Firewall configuration | DO Cloud Firewall + UFW (default-deny, explicit rules) |
| 2.x — No vendor defaults | Custom SSH port, strong passwords from .env, no default accounts |
| 6.x — Secure systems | Unattended security updates, Docker CE from official repo |
| 7.x — Restrict access | Non-root containers, deploy user with key-only SSH, Odoo role-based access |
| 8.x — Authentication | SSH key-only, fail2ban brute-force protection, Odoo login jail |
| 10.x — Logging and monitoring | auditd with immutable rules, Icinga2 agent, Docker log rotation |
| 11.x — Regular testing | Phase 5 end-to-end verification |

### Defense-in-Depth Layers

1. **Network** — DO Cloud Firewall + UFW (port restriction, default deny)
2. **Host** — SSH hardening, kernel params, fail2ban, auditd, auto-updates
3. **Container** — Non-root, resource limits, dual-network isolation, iptables:false
4. **Application** — Database manager disabled, admin password set, proxy_mode enabled
5. **Transport** — TLS 1.2/1.3, HSTS, strong cipher suite, OCSP stapling
6. **Proxy** — Route blocking, security headers (CSP, X-Frame-Options, X-Content-Type-Options)

## 9. Constraints and Assumptions

### Constraints

- **Cloud provider:** DigitalOcean only
- **IaC tool:** Terraform with DigitalOcean provider
- **Container runtime:** Docker with Docker Compose (no Kubernetes)
- **Odoo edition:** Community only
- **Scale:** 10 users — architecture right-sized, not over-engineered
- **State management:** Terraform remote state on DO Spaces

### Assumptions

- DigitalOcean account with API token and Spaces access keys available
- SSH key pair exists or will be created
- DNS A record will be pointed to droplet IP before SSL setup
- Icinga2 master server is operational and admin available for agent registration (Phase 5 — master being built separately)
- Odoo 19 Docker image available on Docker Hub (fallback: pin to 18 if needed)

## 10. Open Questions and v2 Backlog

### Open Questions

- Verify Odoo 19 Docker Hub image availability before Phase 2 execution
- Confirm Icinga2 agent-to-master registration workflow with master admin (Phase 5 dependency — master being built separately)

### v2 Backlog

| ID | Feature | Notes |
|----|---------|-------|
| VPN-01 | WireGuard gateway on dedicated droplet | Front Odoo server |
| VPN-02 | WireGuard client peer configs | Admin team |
| VPN-03 | SSH locked to VPN-only after verification | |
| DSEC-01 | Container image scanning with Trivy | CI pipeline |
| DSEC-02 | Docker Content Trust | Image verification |
| AMON-01 | Security event monitoring | Failed logins, firewall blocks |
| AMON-02 | Backup success/failure alerting | Via Icinga2 |
| OPS-01 | CI/CD pipeline | GitHub Actions |
| OPS-02 | Staging environment | Separate tfvars |
| OPS-03 | Nginx rate limiting on /web/login | Brute-force mitigation |

---

*Defined: 2026-02-20 | Last updated: 2026-03-12*
*Source: .planning/PROJECT.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md*
