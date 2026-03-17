# Odoo 19.x Production Build

## What This Is

A production-ready, Infrastructure-as-Code deployment of Odoo Community edition on DigitalOcean. The project delivers working Terraform configs, Docker Compose files, hardening scripts, and documentation to deploy a containerized Odoo instance with Nginx/SSL reverse proxy and Icinga2 monitoring integration — all PCI-DSS hardened for a 10-user CRM/project management workload. WireGuard VPN gateway deferred to v2.

## Core Value

Run `terraform apply` and get a fully hardened, monitored Odoo deployment with Nginx/SSL — reproducible, secure, and production-ready from day one.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Terraform IaC for all DigitalOcean resources (droplets, VPC, volumes, firewalls)
- [ ] Terraform IaC for all DigitalOcean resources (VPC, firewall, droplet, volume, Spaces)
- [ ] Containerized Odoo Community (latest stable) with CRM and Project modules
- [ ] Separate PostgreSQL container for independent scaling
- [ ] PCI-DSS baseline hardening (UFW, fail2ban, SSH hardening, kernel params, auto-updates, auditd)
- [ ] Docker hardening (non-root, resource limits, iptables:false, dual-network isolation)
- [ ] Nginx reverse proxy with Let's Encrypt SSL (DNS-01 challenge)
- [ ] Icinga2 agent connecting to existing master server
- [ ] Custom monitoring checks (containers, PostgreSQL, system resources)
- [ ] PostgreSQL backups to local volume AND DigitalOcean Spaces
- [ ] Odoo + PostgreSQL performance tuning for 10-user workload
- [ ] Comprehensive documentation alongside all code
- [ ] Deployed and tested on actual DigitalOcean infrastructure

### Out of Scope

- WireGuard VPN gateway — deferred to v2; single droplet architecture for v1
- Odoo Enterprise edition — Community only for v1; short getting-started doc if needed later
- CI/CD pipeline — manual deployment for now, add later
- Multiple environments (staging/dev) — production only for v1
- Odoo modules beyond CRM and Project Management — keep minimal
- Horizontal Odoo scaling — vertical scaling sufficient for 10 users
- Mobile app or custom Odoo module development

## Context

- **Existing infrastructure:** Icinga2 master server operational, DigitalOcean account with API token ready
- **Target OS:** Ubuntu 24.04 LTS
- **Network architecture:** Single droplet — Nginx (host) → Odoo container ← PostgreSQL container, all in DO VPC
- **Access pattern:** Public HTTPS via Nginx/reverse proxy for users, SSH for admin management
- **Backup strategy:** Local DigitalOcean Volume for fast restore + DO Spaces for disaster recovery
- **User load:** 10 concurrent users, moderate database growth
- **Deliverable:** Working code + documentation in one repo, deployed and verified on DO

## Constraints

- **Cloud provider**: DigitalOcean only — no AWS/GCP/Azure resources
- **IaC tool**: Terraform with DigitalOcean provider (no Pulumi)
- **Container runtime**: Docker with Docker Compose (no Kubernetes)
- **Odoo edition**: Community only (no Enterprise license)
- **Scale**: 10 users — architecture should be right-sized, not over-engineered
- **Compliance**: PCI-DSS baseline — defense-in-depth with container segmentation and hardened host
- **State management**: Terraform remote state (DO Spaces or Terraform Cloud)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Defer WireGuard to v2 | Simplifies v1 to single droplet; VPN not needed for initial deployment | — Pending |
| Community edition only | Sufficient for CRM + Project, no license cost | — Pending |
| Prod-only for v1 | 10 users, get it working first, add staging later | — Pending |
| Nginx reverse proxy + Let's Encrypt | Public HTTPS for user access, SSH for admin | — Pending |
| Local + Spaces backups | Fast local restore + offsite DR covers both scenarios | — Pending |
| Two Spaces buckets: Standard for tfstate, Cold for backups | Terraform state is tiny but read/written constantly (bad fit for Cold Storage 30-day retention + retrieval fees). Backups are write-once/rarely-read — Cold Storage is 3x cheaper ($0.007 vs $0.02/GiB/mo) | `odoo-prod-tfstate` (Standard), `odoo-prod-backups` (Cold, Phase 3) |
| Skip CI/CD for v1 | Manual deployment acceptable for initial setup | — Pending |
| Terraform (not Pulumi) | Primary IaC tool per user preference | — Pending |

---
*Last updated: 2026-02-20 after requirements definition*
