# Roadmap: Odoo 19.x Production Build

## Overview

This roadmap delivers a production-ready Odoo Community deployment on DigitalOcean in five phases, moving from bare Terraform project to a fully hardened, backed-up, and monitored Odoo instance behind Nginx/SSL -- verified end-to-end with real users. Phase 1 provisions all DigitalOcean infrastructure via Terraform. Phase 2 is the core build -- hardening the host, deploying the Docker application stack, and configuring Nginx with SSL -- turning a bare droplet into a working Odoo instance. Phase 3 completes backup automation, tested restore procedures, and comprehensive documentation. Phase 4 creates real user accounts and verifies the entire system end-to-end -- confirming that every prior phase works together in production with actual users. Phase 5 adds Icinga2 monitoring for operational visibility once the external Icinga2 master is built and ready. WireGuard VPN is deferred to v2; this is a single-droplet architecture.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Terraform Foundation and Compute** - Provision all DigitalOcean infrastructure (VPC, firewall, droplet, volume, Spaces) via Terraform with secure remote state (completed 2026-02-21)
- [x] **Phase 2: Hardened Application Stack** - Harden the host, deploy containerized Odoo and PostgreSQL, configure Nginx reverse proxy with Let's Encrypt SSL (completed 2026-03-12)
- [ ] **Phase 3: Backup, Recovery, and Documentation** - Automated backups with tested restore, deployment runbook, and operational procedures
- [ ] **Phase 4: Deployment Verification and User Setup** - Create admin and regular user accounts, verify all system components work end-to-end with real users
- [ ] **Phase 5: Monitoring** - Install Icinga2 agent and custom checks for containers, PostgreSQL, and system resources (blocked on external Icinga2 master)

## Phase Details

### Phase 1: Terraform Foundation and Compute
**Goal**: A single `terraform apply` provisions all DigitalOcean infrastructure -- VPC, firewall, droplet, Block Storage Volume, and Spaces bucket -- with secure remote state and reproducible configuration
**Depends on**: Nothing (first phase)
**Requirements**: IAC-01, IAC-02, IAC-03, IAC-04, IAC-05, IAC-06, IAC-07, IAC-08
**Success Criteria** (what must be TRUE):
  1. Running `terraform apply` from a fresh clone provisions a VPC, cloud firewall, Ubuntu 24.04 droplet, and attached Block Storage Volume on DigitalOcean without manual intervention
  2. Terraform state is stored remotely in an encrypted DO Spaces bucket -- no local `.tfstate` files exist after apply
  3. Running `terraform destroy` followed by `terraform apply` produces an identical infrastructure -- the configuration is fully reproducible
  4. `terraform output` displays the droplet public IP, volume mount path, and Spaces endpoint
  5. All environment-specific values (SSH keys, droplet size, domain, IPs) are configured via tfvars -- no hardcoded secrets in HCL files
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- Terraform project scaffold (providers, backend, variables, tfvars template, .gitignore)
- [x] 01-02-PLAN.md -- DigitalOcean resource definitions (VPC, firewall, droplet, volume) and outputs

### Phase 2: Hardened Application Stack
**Goal**: The provisioned droplet is PCI-DSS hardened and runs a containerized Odoo instance (CRM + Project modules) behind an Nginx reverse proxy with valid SSL -- accessible via HTTPS from the public internet
**Depends on**: Phase 1
**Requirements**: HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, HARD-06, HARD-07, DOCK-01, DOCK-02, DOCK-03, DOCK-04, DOCK-05, DOCK-06, DOCK-07, ODOO-01, ODOO-02, ODOO-03, ODOO-04, ODOO-05, PG-01, PG-02, PG-03, PG-04, PROXY-01, PROXY-02, PROXY-03, PROXY-04, PROXY-05
**Success Criteria** (what must be TRUE):
  1. SSH access requires key authentication on a non-standard port -- password login and root login are rejected, and fail2ban blocks repeated failures
  2. Navigating to `https://[domain]` in a browser loads the Odoo login page with a valid Let's Encrypt certificate, HSTS headers, and HTTP-to-HTTPS redirect
  3. Odoo CRM and Project modules are accessible after login, the database manager UI is disabled, and `/web/database/*` routes return 403 from Nginx
  4. PostgreSQL is reachable only from the Odoo container via the Docker backend network -- it has no published ports and no outbound internet access
  5. All persistent data (PostgreSQL data directory and Odoo filestore) resides on the DO Block Storage Volume -- not on the droplet's ephemeral disk
**Plans**: 3 plans (2 waves)

Plans:
- [x] 02-01-PLAN.md -- Host hardening (SSH, UFW, fail2ban, sysctl, auditd, unattended-upgrades) + Docker CE installation (Wave 1)
- [x] 02-02-PLAN.md -- Docker Compose stack: Odoo 19 + PostgreSQL 18, dual networks, health checks, resource limits (Wave 2, depends: 02-01)
- [x] 02-03-PLAN.md -- Nginx reverse proxy + Let's Encrypt SSL via HTTP-01, security headers, certbot auto-renewal (Wave 2, depends: 02-01)

### Phase 3: Backup, Recovery, and Documentation
**Goal**: PostgreSQL data is automatically backed up daily with offsite copies, restore has been tested and verified, and the entire deployment is documented for reproducibility and ongoing operations
**Depends on**: Phase 2
**Requirements**: BACK-01, BACK-02, BACK-03, BACK-04, DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. A daily automated pg_dump writes to the local Block Storage Volume, and rclone syncs backups to DO Spaces -- both local and remote backups are present and current
  2. Backup retention is enforced automatically: 7 daily and 4 weekly on local storage, 30 days on Spaces
  3. The documented restore procedure has been executed against a fresh temporary container and the restored database is verified functional
  4. A deployment runbook exists that takes a new operator from fresh git clone to running Odoo in production, and operational procedures cover backup, restore, Odoo updates, and resource scaling
  5. An architecture overview document with network topology diagram describes the complete system
**Plans**: 2 plans (1 wave)

Plans:
- [x] 03-01-PLAN.md -- Backup automation scripts (daily pg_dump + filestore tar, rclone offsite sync, restore + verification, setup script + config templates) (Wave 1)
- [ ] 03-02-PLAN.md -- Documentation (architecture overview, deployment runbook, operational procedures, enterprise migration guide) (Wave 1)

### Phase 4: Deployment Verification and User Setup
**Goal**: An admin and a regular user are set up in Odoo, and the production system is verified end-to-end -- login, CRM workflow, Project workflow, SSL, and backups all function correctly with real user accounts
**Depends on**: Phase 3
**Requirements**: Cross-cutting verification of Phases 1-3 (IAC, HARD, DOCK, ODOO, PG, PROXY, BACK, DOC)
**Success Criteria** (what must be TRUE):
  1. An admin user can log in to Odoo, access Settings, install/configure CRM and Project modules, and manage user accounts
  2. A regular user with restricted permissions can log in, create a CRM lead, advance it through pipeline stages, and create and manage a Project with tasks -- without access to admin settings
  3. Both users access Odoo exclusively over HTTPS with a valid SSL certificate, HTTP requests redirect to HTTPS, and the browser shows no certificate warnings
  4. A backup runs successfully, the backup file appears in both local storage and DO Spaces, and the backup restoration procedure is confirmed functional with the live database
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: Monitoring
**Goal**: The Odoo host reports health status to the existing Icinga2 master -- container failures, PostgreSQL issues, and system resource exhaustion trigger alerts without manual log inspection
**Depends on**: Phase 2 + external Icinga2 master must be built and operational
**Requirements**: MON-01, MON-02, MON-03, MON-04, MON-05
**Success Criteria** (what must be TRUE):
  1. The Icinga2 agent on the Odoo host is registered with the existing Icinga2 master and appears as a monitored host in the Icinga2 dashboard
  2. Stopping the Odoo or PostgreSQL container triggers a critical alert on the Icinga2 master within the check interval
  3. System resource checks (CPU, memory, disk, load average) and PostgreSQL-specific checks (connections, database size, query latency) report OK under normal operation and escalate when thresholds are breached
  4. Service definition files are provided and documented so the Icinga2 master admin can integrate them
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5
Note: Phase 5 (Monitoring) is blocked on external Icinga2 master availability.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Terraform Foundation and Compute | 2/2 | Complete    | 2026-02-21 |
| 2. Hardened Application Stack | 3/3 | Complete    | 2026-03-12 |
| 3. Backup, Recovery, and Documentation | 1/2 | In Progress | - |
| 4. Deployment Verification and User Setup | 0/1 | Not started | - |
| 5. Monitoring | 0/1 | Not started (blocked on Icinga2 master) | - |
