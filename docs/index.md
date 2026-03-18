# Odoo 19.x Production Build

Production-ready, Infrastructure-as-Code deployment of Odoo Community 19.x on DigitalOcean. A single `terraform apply` provisions all cloud infrastructure, and sequential scripts harden the host, deploy containerized Odoo + PostgreSQL via Docker Compose, and configure Nginx with Let's Encrypt SSL.

**PCI-DSS compliant. 10-user CRM/PM workload. Single-droplet architecture.**

---

## Quick Start

```bash
# 1. Clone and configure Terraform
cd infra/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Provision infrastructure
terraform init && terraform apply

# 3. Deploy to droplet (see Deployment Runbook for full steps)
scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/
ssh root@<droplet-ip>
bash /tmp/odoo-setup/scripts/01-harden-host.sh
```

See the [Deployment Runbook](deployment-runbook.md) for the complete step-by-step guide.

---

## What's Deployed

| Component | Details |
|-----------|---------|
| **OS** | Ubuntu 24.04 LTS |
| **Application** | Odoo Community 19 (3 workers + 1 cron) |
| **Database** | PostgreSQL 18 (tuned for 10 users) |
| **Reverse Proxy** | Nginx + Let's Encrypt SSL |
| **IaC** | Terraform with DO Spaces remote state |
| **Firewall** | DO Cloud Firewall + UFW (default-deny) |
| **Backups** | Daily pg_dump to local + DO Spaces |

## Architecture

```
Internet → DO Firewall → Nginx (host) → Odoo (container) → PostgreSQL (container)
                                                                    ↓
                                                          DO Block Storage (25 GB)
```

Dual Docker networks isolate traffic: `frontend` (Nginx ↔ Odoo) and `backend` (Odoo ↔ PostgreSQL, internal only). See the full [Architecture Overview](architecture.md).

## Security Layers

1. **Network** — DO Cloud Firewall + UFW (port restriction, default deny)
2. **Host** — SSH hardening, kernel params, fail2ban, auditd, auto-updates
3. **Container** — Non-root, resource limits, dual-network isolation, `iptables: false`
4. **Application** — Database manager disabled, admin password set, proxy_mode enabled
5. **Transport** — TLS 1.2/1.3, HSTS, strong cipher suite, OCSP stapling
6. **Proxy** — Route blocking, security headers (CSP, X-Frame-Options)

## Project Status

| Phase | Status |
|-------|--------|
| 1. Terraform Foundation | :white_check_mark: Complete |
| 2. Hardened Application Stack | :white_check_mark: Complete |
| 3. Backup, Recovery, and Documentation | :white_check_mark: Complete |
| 4. Deployment Verification and User Setup | :hourglass: Not started |
| 5. Monitoring (Icinga2) | :no_entry: Blocked on Icinga2 master |

## Documentation Map

| Document | Audience | Purpose |
|----------|----------|---------|
| [Architecture](architecture.md) | All team members | System topology, networks, resource allocation |
| [Deployment Runbook](deployment-runbook.md) | Infrastructure operators | Fresh clone → running Odoo |
| [Operations](operations.md) | Infrastructure operators | Day-to-day: backups, updates, scaling, troubleshooting |
| [Enterprise Migration](enterprise-migration.md) | Infrastructure operators | Community → Enterprise upgrade path |
| [Requirements](reference/requirements.md) | Project stakeholders | All 48 v1 requirements with traceability |
| [Key Decisions](reference/decisions.md) | All team members | Architectural decisions and rationale |
