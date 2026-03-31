# CLAUDE.md — Odoo 19.x Production Build

## Project Summary

Production-ready IaC deployment of Odoo Community 19.x on DigitalOcean. Terraform provisions infrastructure, sequential bash scripts harden the host, deploy containerized Odoo + PostgreSQL via Docker Compose, and configure Nginx with Let's Encrypt SSL. PCI-DSS compliant, 10-user CRM/PM workload. Single-droplet architecture — WireGuard VPN deferred to v2.

## Tech Stack

- **IaC:** Terraform ≥ 1.6.3 with DigitalOcean provider ~> 2.0
- **OS:** Ubuntu 24.04 LTS
- **Containers:** Docker CE (official repo) + Docker Compose v2
- **Application:** Odoo Community 19, PostgreSQL 18
- **Reverse Proxy:** Nginx (host-installed, not containerized) + Let's Encrypt (certbot)
- **Monitoring:** Icinga2 agent → existing master (Phase 5, blocked on Icinga2 master build)
- **State Backend:** DigitalOcean Spaces (S3-compatible)

## Directory Structure

```
infra/              Terraform HCL — all DO resources (flat layout, no modules)
  ├── providers.tf      Provider + version constraints
  ├── backend.tf        Remote state on DO Spaces
  ├── variables.tf      All input variables
  ├── main.tf           Resource definitions (SSH key, VPC, volume, droplet, firewall)
  ├── outputs.tf        Droplet IP, volume path, Spaces endpoint
  └── terraform.tfvars.example

config/             Configuration files deployed to target host
  ├── docker-compose.yml    Odoo + PostgreSQL stack
  ├── odoo.conf             Odoo app config (workers, memory, proxy_mode)
  ├── postgresql.conf       PG tuning for 10-user workload
  ├── daemon.json           Docker daemon (iptables:false, log rotation)
  ├── sshd-hardening.conf   SSH drop-in override (port 9292, key-only)
  ├── sysctl-hardening.conf Kernel parameter hardening
  ├── jail.local            fail2ban SSH + Odoo login jails
  ├── audit.rules           auditd PCI-DSS 10.x compliance rules
  ├── .env.example          Environment variables template (secrets)
  └── nginx/
      ├── odoo-pre-ssl.conf   Temporary config for certbot HTTP-01 challenge
      └── odoo.conf            Full SSL reverse proxy config

scripts/            Deployment scripts — run sequentially on target host
  ├── 01-harden-host.sh     HARD-01 through HARD-07
  ├── 02-install-docker.sh  DOCK-01, DOCK-02, DOCK-07
  ├── 03-deploy-stack.sh    DOCK-03–06, ODOO-01–05, PG-01–04
  └── 04-setup-nginx.sh     PROXY-01 through PROXY-05

artifacts/          Original project specification
  └── Initial_Prompt.md

docs/               Project documentation
  └── PRD.md              Product Requirements Document

.planning/          GSD planning system
  ├── PROJECT.md          Project definition, key decisions
  ├── REQUIREMENTS.md     All 48 v1 requirements with traceability
  ├── ROADMAP.md          5-phase roadmap with success criteria
  ├── STATE.md            Current progress and session continuity
  ├── phases/             Executed plan files
  └── research/           Research outputs
```

## Conventions

### Requirement IDs
Every requirement has a prefixed ID used across all planning docs, scripts, and configs:
- `IAC-XX` — Infrastructure as Code (Terraform)
- `HARD-XX` — Host security hardening
- `DOCK-XX` — Docker and container security
- `ODOO-XX` — Odoo application configuration
- `PG-XX` — PostgreSQL database
- `PROXY-XX` — Nginx reverse proxy and SSL
- `MON-XX` — Monitoring (Icinga2)
- `BACK-XX` — Backup and recovery
- `DOC-XX` — Documentation

Scripts and configs reference these IDs in comments (e.g., `# HARD-01: SSH Hardening`).

### Script Naming
`NN-verb-noun.sh` — numbered for execution order. Always run sequentially: 01 → 02 → 03 → 04.

### Config Deployment Pattern
Config files live in `config/`, scripts copy them to target locations on the host:
- `config/sshd-hardening.conf` → `/etc/ssh/sshd_config.d/99-hardening.conf`
- `config/daemon.json` → `/etc/docker/daemon.json`
- `config/docker-compose.yml` → `/opt/odoo/docker-compose.yml`

### Terraform Layout
Flat single-directory layout in `infra/` — one file per concern, no modules. Resources ordered by dependency in `main.tf`.

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| `iptables: false` in Docker daemon | UFW is the single firewall source of truth. Docker's iptables manipulation bypasses UFW rules. |
| Nginx on host (not containerized) | Simpler certbot integration, survives Docker daemon restarts |
| `deploy` user, not root | Root login disabled after hardening. `deploy` has sudo + SSH key access. |
| Two-stage Nginx config | Pre-SSL config serves certbot HTTP-01 challenge, replaced with full SSL config after cert issuance |
| Dual Docker networks | `frontend` (Nginx ↔ Odoo) + `backend` (Odoo ↔ PG, internal, no outbound) |
| Separate volume_attachment | Not inline `volume_ids` on droplet — prevents destroy-ordering issues |
| Block Storage for all data | PostgreSQL data + Odoo filestore on DO Volume, not ephemeral disk |
| 3 workers + 1 cron | Right-sized for 2 vCPU / 4 GB with 10 concurrent users |
| Two Spaces buckets | `odoo-prod-tfstate` (Standard) for TF state, `odoo-prod-backups` (Cold Storage) for backups. Cold is 3x cheaper but has 30-day retention + retrieval fees. |

## Development Workflow

### Infrastructure Changes
```bash
cd infra/
terraform plan        # Review changes
terraform apply       # Apply (requires confirmation)
```

### Script Execution on Target Host
```bash
# From local machine — copy files to droplet
scp -r config/ scripts/ root@<droplet-ip>:/tmp/odoo-setup/

# SSH to droplet and run in order
ssh root@<droplet-ip>
bash /tmp/odoo-setup/scripts/01-harden-host.sh
# After 01: reconnect on new port
ssh -p 9292 deploy@<droplet-ip>
sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh
# Create .env from .env.example with real passwords
sudo bash /tmp/odoo-setup/scripts/03-deploy-stack.sh
sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh odoo.example.com admin@example.com
```

### Secrets Management
- All secrets in `.env` files — never in HCL, scripts, or configs
- `.env` files are chmod 600 and listed in `.gitignore`
- Terraform secrets via environment variables: `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `odoo.conf` uses `ADMIN_PASSWORD_PLACEHOLDER` token, replaced by deploy script at runtime

## Security Rules — Non-Negotiable

- **Never hardcode secrets** — use `.env` + environment variables exclusively
- **`.env` always chmod 600** — deploy scripts enforce this
- **No root containers** — Odoo runs as uid 101, PostgreSQL as uid 999
- **No published database ports** — PostgreSQL on internal backend network only
- **UFW is the firewall** — Docker daemon runs with `iptables: false`
- **SSH key-only** — password auth disabled, root login disabled
- **Block database manager** — `list_db = False` in odoo.conf AND Nginx 403 on `/web/database/*`

## What NOT To Do

- **Don't add Kubernetes or Docker Swarm** — massively overkill for 10 users
- **Don't containerize Nginx** — host install is simpler for certbot and survives Docker restarts
- **Don't use Ubuntu's `docker.io` package** — use official Docker CE from `download.docker.com`
- **Don't let Docker manage iptables** — it bypasses UFW. Keep `iptables: false`
- **Don't use PgBouncer** — not needed at 10 users with `max_connections = 50`
- **Don't add Prometheus/Grafana** — Icinga2 is the monitoring stack
- **Don't skip the deploy user** — root login is disabled after Phase 2 hardening

## Planning System

The `.planning/` directory uses the GSD (Get Shit Done) planning framework:

- **PROJECT.md** — Project definition, scope, constraints, key decisions
- **REQUIREMENTS.md** — All 48 v1 requirements with phase mapping and traceability
- **ROADMAP.md** — 5-phase roadmap with dependencies, success criteria, and plan status
- **STATE.md** — Current progress, velocity, accumulated decisions, session continuity
- **phases/** — Executed plan files (research, plan docs)

When modifying plans or requirements, update the relevant `.planning/` file and keep STATE.md current.

## Current Status

- **Phase 1** — Complete (Terraform infrastructure provisioned)
- **Phase 2** — Complete (scripts and configs written, executed on droplet)
- **Phase 3** — Complete (Backup scripts, restore verification, documentation)
- **Phase 4** — Complete (Playwright E2E Testing and Odoo Verification)
- **Phase 5** — Complete (Deployment verified, users set up on production)
- **Phase 6** — Complete (Monitoring plugins and service definitions delivered; live Icinga2 verification deferred to Icinga2 master project)
- **Overall:** v1.0 Milestone Complete (6/6 phases)
- **Droplet:** `45.55.164.120` / `loodon-prod-01-odoo` — live and serving
- **Next:** Odoo CRM/Sales buildout tracked in `../ubop-lite/`
