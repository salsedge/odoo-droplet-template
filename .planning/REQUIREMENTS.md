# Requirements: Odoo 19.x Production Build

**Defined:** 2026-02-20
**Core Value:** Run `terraform apply` and get a fully hardened, monitored Odoo deployment with Nginx/SSL — reproducible, secure, and production-ready from day one.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Infrastructure as Code

- [x] **IAC-01**: Terraform provisions DigitalOcean VPC with private networking
- [x] **IAC-02**: Terraform provisions DO firewall rules (SSH, HTTP, HTTPS only)
- [x] **IAC-03**: Terraform provisions Odoo application droplet (Ubuntu 24.04 LTS)
- [x] **IAC-04**: Terraform provisions and attaches DO Block Storage Volume for persistent data
- [x] **IAC-05**: Terraform configures DO Spaces bucket for remote state backend
- [x] **IAC-06**: Terraform uses tfvars for environment-specific configuration (IPs, droplet sizes, SSH keys, domain)
- [x] **IAC-07**: Terraform executes bootstrap scripts via remote-exec provisioners
- [x] **IAC-08**: Terraform outputs critical info (droplet IP, volume mount path, Spaces endpoint)

### System Hardening

- [x] **HARD-01**: SSH hardened (key-only auth, no root login, non-standard port, idle timeout)
- [x] **HARD-02**: UFW configured with default-deny and explicit allow rules for SSH, HTTP, HTTPS
- [x] **HARD-03**: fail2ban installed with jails for SSH and Odoo login failures
- [x] **HARD-04**: Kernel parameters hardened (sysctl: disable IP forwarding, enable SYN cookies, disable ICMP redirects)
- [x] **HARD-05**: Automatic unattended security updates enabled
- [x] **HARD-06**: File permissions restricted on sensitive configs (/etc/ssh, Docker configs, .env files)
- [x] **HARD-07**: auditd installed and configured for PCI-DSS 10.x compliance logging

### Docker and Containers

- [x] **DOCK-01**: Docker CE installed from official apt repository (not Ubuntu docker.io package)
- [x] **DOCK-02**: Docker daemon configured with `iptables: false` to prevent UFW bypass
- [x] **DOCK-03**: Docker Compose v2 deploys Odoo and PostgreSQL as separate services
- [x] **DOCK-04**: Containers run as non-root users with resource limits (CPU, memory)
- [x] **DOCK-05**: Docker networks isolate frontend (Nginx-Odoo) and backend (Odoo-PostgreSQL)
- [x] **DOCK-06**: Container health checks configured for both Odoo and PostgreSQL
- [x] **DOCK-07**: Docker log rotation configured to prevent disk exhaustion

### Odoo Application

- [x] **ODOO-01**: Odoo Community edition deployed with CRM and Project modules enabled
- [x] **ODOO-02**: Odoo worker count and memory limits tuned for 10-user workload
- [x] **ODOO-03**: Odoo database manager disabled (`list_db = False`)
- [x] **ODOO-04**: Odoo filestore persisted on DO Block Storage Volume
- [x] **ODOO-05**: Odoo admin password set and `db_manager` routes blocked in Nginx

### PostgreSQL Database

- [x] **PG-01**: PostgreSQL 18 container with data directory on DO Block Storage Volume
- [x] **PG-02**: PostgreSQL tuned for 10-user workload (shared_buffers, work_mem, max_connections)
- [x] **PG-03**: PostgreSQL accessible only from Odoo container via Docker backend network
- [x] **PG-04**: PostgreSQL credentials stored in .env file with restricted file permissions

### Reverse Proxy and SSL

- [x] **PROXY-01**: Nginx installed on host as reverse proxy to Odoo container
- [x] **PROXY-02**: Let's Encrypt SSL certificate via certbot with HTTP-01 challenge (--webroot)
- [x] **PROXY-03**: Nginx enforces HTTPS redirect and HSTS headers
- [x] **PROXY-04**: Nginx blocks access to /web/database/* routes
- [x] **PROXY-05**: Certbot auto-renewal configured via systemd timer

### Monitoring

- [ ] **MON-01**: Icinga2 agent installed on host and registered with existing Icinga2 master
- [ ] **MON-02**: Custom check monitors Docker container health (running, restart count, resource usage)
- [ ] **MON-03**: Custom check monitors PostgreSQL (connections, database size, query latency)
- [ ] **MON-04**: System resource checks (CPU, memory, disk usage, load average)
- [ ] **MON-05**: Icinga2 service definitions provided for integration with master

### Backup and Recovery

- [ ] **BACK-01**: Automated daily pg_dump to local DO Block Storage Volume
- [ ] **BACK-02**: Automated sync of backups to DO Spaces via rclone
- [ ] **BACK-03**: Backup retention policy (7 daily, 4 weekly on local; 30 days on Spaces)
- [ ] **BACK-04**: Documented and tested restore procedure with verification script

### Documentation

- [ ] **DOC-01**: Architecture overview document with network topology diagram
- [ ] **DOC-02**: Deployment runbook (step-by-step from fresh clone to running Odoo)
- [ ] **DOC-03**: Operational procedures (backup, restore, update Odoo, scale resources)
- [ ] **DOC-04**: Short getting-started document for Enterprise edition migration path

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### VPN

- **VPN-01**: WireGuard gateway on dedicated droplet fronting Odoo server
- **VPN-02**: WireGuard client peer configurations for admin team
- **VPN-03**: SSH locked to VPN-only access after WireGuard verification

### Docker Security

- **DSEC-01**: Container image scanning with Trivy in CI pipeline
- **DSEC-02**: Docker Content Trust for image verification

### Advanced Monitoring

- **AMON-01**: Security event monitoring (failed logins, firewall blocks)
- **AMON-02**: Backup success/failure alerting via Icinga2

### Operations

- **OPS-01**: CI/CD pipeline for automated deployment (GitHub Actions)
- **OPS-02**: Staging environment with separate tfvars
- **OPS-03**: Nginx rate limiting on /web/login

## Out of Scope

| Feature | Reason |
|---------|--------|
| Kubernetes / Docker Swarm | Massively overkill for 10 users |
| Odoo Enterprise edition | Community sufficient for CRM + Project |
| Multiple environments (dev/staging) | Single production environment for v1 |
| Horizontal Odoo scaling | Vertical scaling sufficient for 10 users |
| Database replication | Backup/restore meets RTO target for 10 users |
| ELK/EFK log aggregation | Elasticsearch needs 4GB+ RAM; Docker log rotation sufficient |
| External secrets manager (Vault) | .env files with restricted permissions sufficient at this scale |
| PgBouncer connection pooling | Not needed at 10 users with correct db_maxconn |
| Mobile app | Web access only |
| Prometheus/Grafana | Icinga2 provides sufficient visibility at this scale |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IAC-01 | Phase 1 | Complete |
| IAC-02 | Phase 1 | Complete |
| IAC-03 | Phase 1 | Complete |
| IAC-04 | Phase 1 | Complete |
| IAC-05 | Phase 1 | Complete |
| IAC-06 | Phase 1 | Complete |
| IAC-07 | Phase 1 | Complete |
| IAC-08 | Phase 1 | Complete |
| HARD-01 | Phase 2 | Complete |
| HARD-02 | Phase 2 | Complete |
| HARD-03 | Phase 2 | Complete |
| HARD-04 | Phase 2 | Complete |
| HARD-05 | Phase 2 | Complete |
| HARD-06 | Phase 2 | Complete |
| HARD-07 | Phase 2 | Complete |
| DOCK-01 | Phase 2 | Complete |
| DOCK-02 | Phase 2 | Complete |
| DOCK-03 | Phase 2 | Complete |
| DOCK-04 | Phase 2 | Complete |
| DOCK-05 | Phase 2 | Complete |
| DOCK-06 | Phase 2 | Complete |
| DOCK-07 | Phase 2 | Complete |
| ODOO-01 | Phase 2 | Complete |
| ODOO-02 | Phase 2 | Complete |
| ODOO-03 | Phase 2 | Complete |
| ODOO-04 | Phase 2 | Complete |
| ODOO-05 | Phase 2 | Complete |
| PG-01 | Phase 2 | Complete |
| PG-02 | Phase 2 | Complete |
| PG-03 | Phase 2 | Complete |
| PG-04 | Phase 2 | Complete |
| PROXY-01 | Phase 2 | Complete |
| PROXY-02 | Phase 2 | Complete |
| PROXY-03 | Phase 2 | Complete |
| PROXY-04 | Phase 2 | Complete |
| PROXY-05 | Phase 2 | Complete |
| MON-01 | Phase 3 | Pending |
| MON-02 | Phase 3 | Pending |
| MON-03 | Phase 3 | Pending |
| MON-04 | Phase 3 | Pending |
| MON-05 | Phase 3 | Pending |
| BACK-01 | Phase 4 | Pending |
| BACK-02 | Phase 4 | Pending |
| BACK-03 | Phase 4 | Pending |
| BACK-04 | Phase 4 | Pending |
| DOC-01 | Phase 4 | Pending |
| DOC-02 | Phase 4 | Pending |
| DOC-03 | Phase 4 | Pending |
| DOC-04 | Phase 4 | Pending |

**Phase 5 note:** Phase 5 (Deployment Verification and User Setup) introduces no new requirements. It is a cross-cutting integration verification phase that validates all 48 existing requirements work together end-to-end with real user accounts.

**Coverage:**
- v1 requirements: 48 total
- Mapped to phases: 48
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap revision (Phase 5 added)*
