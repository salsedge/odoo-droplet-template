# CLAUDE.md — Odoo 19.x Production Template

## Project Summary

Production-ready IaC template for deploying Odoo Community 19.x on DigitalOcean. Configurable via `instance.conf` — an interactive setup wizard generates all instance-specific configs from a single source of truth. Terraform provisions infrastructure, sequential bash scripts harden the host and deploy containerized Odoo + PostgreSQL via Docker Compose, and Nginx with Let's Encrypt SSL handles the reverse proxy. Single-droplet architecture.

## Tech Stack

- **IaC:** Terraform ≥ 1.6.3 with DigitalOcean provider ~> 2.0
- **OS:** Ubuntu 24.04 LTS
- **Containers:** Docker CE (official repo) + Docker Compose v2
- **Application:** Odoo Community 19, PostgreSQL 18
- **Reverse Proxy:** Nginx (host-installed, not containerized) + Let's Encrypt (certbot)
- **Monitoring:** Icinga2 agent → existing master (optional, configs in `monitoring/`)
- **State Backend:** DigitalOcean Spaces (S3-compatible)

## Directory Structure

```
instance.conf.example   Template configuration with all instance-specific defaults
setup.sh                Interactive setup wizard — writes instance.conf, runs generate.sh
generate.sh             Config generator — reads instance.conf, produces all derived files
Makefile                Lifecycle automation (init, tf-init, tf-apply, deploy, generate)

infra/                  Terraform HCL — all DO resources (flat layout, no modules)
  ├── providers.tf          Provider + version constraints (static)
  ├── variables.tf          All input variables (static)
  ├── main.tf               Resource definitions (SSH key, VPC, volume, droplet, firewall) (static)
  ├── outputs.tf            Droplet IP, volume path, Spaces endpoint (static)
  ├── backend.tf.example    Remote state config template (generated → backend.tf, gitignored)
  └── terraform.tfvars.example  Variable values template (generated → terraform.tfvars, gitignored)

config/                 .example files are committed references; generated files are gitignored
  ├── .env.example              Secrets template → .env at deploy time
  ├── docker-compose.yml.example  Odoo + PostgreSQL stack template → docker-compose.yml
  ├── odoo.conf.example         Odoo app config template → odoo.conf
  ├── postgresql.conf           PG tuning (static — not instance-specific)
  ├── daemon.json               Docker daemon config (iptables:false, log rotation) (static)
  ├── sshd-hardening.conf       SSH drop-in override (port 9292, key-only) (static)
  ├── sysctl-hardening.conf     Kernel parameter hardening (static)
  ├── jail.local                fail2ban SSH + Odoo login jails (static)
  ├── audit.rules               auditd PCI-DSS 10.x compliance rules (static)
  ├── backup-cron               Cron schedule for backup jobs (static)
  ├── msmtprc.example           Mail relay config template
  ├── rclone.conf.example       Offsite sync config template
  └── nginx/
      ├── odoo-pre-ssl.conf.example   Certbot HTTP-01 challenge config template
      ├── odoo-single.conf.example    Full SSL single-domain config template
      └── odoo-multi.conf.example     Full SSL multi-tenant config template

scripts/                Deployment scripts — run sequentially on target host
  ├── 01-harden-host.sh         HARD-01 through HARD-07
  ├── 02-install-docker.sh      DOCK-01, DOCK-02, DOCK-07
  ├── 03-deploy-stack.sh        DOCK-03–06, ODOO-01–05, PG-01–04
  ├── 04-setup-nginx.sh         PROXY-01 through PROXY-05
  ├── 05-setup-backups.sh       BACK-01 through BACK-04
  ├── 06-backup-daily.sh        BACK-05 — daily backup runner
  ├── 07-sync-offsite.sh        BACK-06 — offsite rclone sync
  ├── 08-restore-backup.sh      BACK-07 — restore from backup
  └── ops/
      ├── deploy-addon.sh       Deploy a custom Odoo addon
      └── set-domain.sh         Update domain + regenerate Nginx config

monitoring/             Optional Icinga2 monitoring (connect agent to existing master)
  ├── README.md
  ├── plugins/
  │   ├── check_docker_stack    Custom plugin for Docker stack health
  │   └── check_postgres_health Custom plugin for PostgreSQL health
  └── icinga2/
      ├── commands.conf.example Icinga2 check command definitions
      ├── services.conf         Service definitions for this host
      └── notifications.conf    Notification rules

docs/                   Generalized documentation
  ├── architecture.md         System architecture and design decisions
  ├── deployment-runbook.md   Step-by-step deployment guide
  ├── operations.md           Day-to-day operations and maintenance
  └── enterprise-migration.md Migrating from Community to Enterprise
```

## Template Lifecycle

```bash
make init       # Interactive setup: runs setup.sh, writes instance.conf, generates configs
make tf-init    # Initialize Terraform backend (requires generated backend.tf)
make tf-apply   # Provision infrastructure on DigitalOcean
make deploy     # Full deployment pipeline (copies files, runs scripts 01–04)
make generate   # Regenerate all derived configs after editing instance.conf
```

Manually, after `make init`:

```bash
# Review and optionally edit instance.conf
make generate    # Regenerate if you made edits

# Provision
cd infra/ && terraform plan && terraform apply

# Deploy to droplet — scripts run sequentially
# make deploy handles this, or manually:
ssh root@<droplet-ip>
bash /tmp/odoo-setup/scripts/01-harden-host.sh
# After 01: reconnect on new SSH port
ssh -p 9292 deploy@<droplet-ip>
sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh
sudo bash /tmp/odoo-setup/scripts/03-deploy-stack.sh
sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh
```

## Conventions

### File Types: Static vs. Generated

- **Static** — committed as-is. Not instance-specific (e.g., `sshd-hardening.conf`, `audit.rules`, `postgresql.conf`).
- **`.example` files** — committed as reference/documentation. `generate.sh` reads `instance.conf` and produces the real file from the template.
- **Generated files** — listed in `.gitignore`. Never edit these directly; edit `instance.conf` and run `make generate`.

`instance.conf` is the single source of truth for all instance-specific values (domain, SSH port, Spaces bucket names, droplet size, etc.).

### Requirement IDs

Every requirement has a prefixed ID used across scripts and configs:
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

`NN-verb-noun.sh` — numbered for execution order. Always run sequentially: 01 → 02 → ... → 08.

### Config Deployment Pattern

Config files (static or generated) live in `config/`, scripts copy them to target locations:
- `config/sshd-hardening.conf` → `/etc/ssh/sshd_config.d/99-hardening.conf`
- `config/daemon.json` → `/etc/docker/daemon.json`
- `config/docker-compose.yml` → `/opt/odoo/docker-compose.yml`

Scripts use `${VOLUME_MOUNT:-/mnt/odoo-data}` pattern for path overrides from `instance.conf`.

### Terraform Layout

Flat single-directory layout in `infra/` — one file per concern, no modules. `backend.tf` is generated (gitignored); all other `.tf` files are static. Resources ordered by dependency in `main.tf`.

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| `instance.conf` as single source of truth | One place to configure an instance; `generate.sh` derives all other files. Avoids Jinja2 dependency and keeps templates readable. |
| GitHub template repository | Clone-and-configure model (vs Terraform workspaces) — each instance is an independent repo with its own state. |
| `iptables: false` in Docker daemon | UFW is the single firewall source of truth. Docker's iptables manipulation bypasses UFW rules. |
| Nginx on host (not containerized) | Simpler certbot integration, survives Docker daemon restarts. |
| `deploy` user, not root | Root login disabled after hardening. `deploy` has sudo + SSH key access. |
| Two-stage Nginx config | Pre-SSL config serves certbot HTTP-01 challenge, replaced with full SSL config after cert issuance. |
| Dual Docker networks | `frontend` (Nginx ↔ Odoo) + `backend` (Odoo ↔ PG, internal, no outbound). |
| Separate volume_attachment | Not inline `volume_ids` on droplet — prevents destroy-ordering issues. |
| Block Storage for all data | PostgreSQL data + Odoo filestore on DO Volume, not ephemeral disk. |
| 3 workers + 1 cron | Default sizing for 2 vCPU / 4 GB with ~10 concurrent users. Adjust in `instance.conf`. |
| Two Spaces buckets | One (Standard) for Terraform state, one (Cold Storage) for backups. Cold is ~3x cheaper with 30-day retention. |

## Development Workflow

### Provisioning a New Instance

```bash
git clone https://github.com/salsedge/odoo-droplet-template my-odoo
cd my-odoo
make init       # Interactive setup
make tf-init    # Init Terraform backend
make tf-apply   # Provision droplet
make deploy     # Deploy Odoo stack
```

### Secrets Management

- All secrets in `.env` files — never in HCL, scripts, or configs
- `.env` files are chmod 600 and listed in `.gitignore`
- Terraform secrets via environment variables: `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `odoo.conf` uses `ADMIN_PASSWORD_PLACEHOLDER` token, replaced by deploy script at runtime

### Modifying an Instance

```bash
# Edit instance.conf (instance-specific values)
vim instance.conf

# Regenerate all derived files
make generate

# Re-deploy changed configs (or run the relevant script on the droplet)
```

## Security Rules — Non-Negotiable

- **Never hardcode secrets** — use `.env` + environment variables exclusively
- **`.env` always chmod 600** — deploy scripts enforce this
- **No root containers** — Odoo runs as uid 101, PostgreSQL as uid 999
- **No published database ports** — PostgreSQL on internal backend network only
- **UFW is the firewall** — Docker daemon runs with `iptables: false`
- **SSH key-only** — password auth disabled, root login disabled
- **Block database manager** — `list_db = False` in odoo.conf AND Nginx 403 on `/web/database/*`

## What NOT To Do

- **Don't edit generated files directly** — edit `instance.conf` and run `make generate`
- **Don't add Kubernetes or Docker Swarm** — massively overkill for a small-team workload
- **Don't containerize Nginx** — host install is simpler for certbot and survives Docker restarts
- **Don't use Ubuntu's `docker.io` package** — use official Docker CE from `download.docker.com`
- **Don't let Docker manage iptables** — it bypasses UFW. Keep `iptables: false`
- **Don't use PgBouncer** — not needed at ~10 users with `max_connections = 50`
- **Don't add Prometheus/Grafana** — Icinga2 is the monitoring stack
- **Don't skip the deploy user** — root login is disabled after script 01

## Current Status

- Template conversion: complete
- OdooKit: extracted to separate repo (`github.com/salsedge/odookit`)
