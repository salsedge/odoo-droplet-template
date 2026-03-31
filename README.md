# Odoo Droplet Template

Reusable IaC template for deploying Odoo Community 19.x on DigitalOcean. Terraform provisions infrastructure, sequential bash scripts harden the host, Docker Compose runs Odoo + PostgreSQL, and Nginx handles SSL termination with Let's Encrypt. Designed for 10–20 concurrent users on a single droplet.

## Architecture

- Single DigitalOcean Droplet (Ubuntu 24.04 LTS)
- Docker CE + Compose v2 — Odoo 19 + PostgreSQL 18 in containers
- Nginx on host (not containerized) with Let's Encrypt auto-renewal
- UFW firewall — Docker daemon runs with `iptables: false`
- DO Cloud Firewall as outer perimeter (deny-all default)
- All persistent data on DO Block Storage Volume (PG data + Odoo filestore)
- Automated daily backups to DO Spaces (Cold Storage)
- Optional Icinga2 agent for monitoring

## Prerequisites

- DigitalOcean account with API token and Spaces access keys
- Terraform >= 1.6.3
- SSH key pair (Ed25519 recommended) added to your DO account
- Domain with DNS access (A record must resolve before SSL setup)
- `s3cmd` or `doctl` (for creating Spaces buckets before `terraform init`)

## Quickstart

```bash
# 1. Create repo from template
# Use "Use this template" on GitHub, or:
git clone https://github.com/salsedge/odoo-droplet-template my-odoo-instance
cd my-odoo-instance

# 2. Run interactive setup (creates instance.conf, .env, terraform.tfvars)
make init

# 3. Set environment variables
export DIGITALOCEAN_TOKEN="your-token"
export AWS_ACCESS_KEY_ID="your-spaces-key"
export AWS_SECRET_ACCESS_KEY="your-spaces-secret"

# 4. Provision infrastructure
make tf-init
make tf-apply

# 5. Deploy everything
make deploy
```

After `make deploy` completes, your Odoo instance is live at `https://<PRIMARY_DOMAIN>`.

## Configuration Reference

All instance-specific values live in `instance.conf`. Copy `instance.conf.example` to `instance.conf` and edit, or run `make init` for an interactive prompt.

### Project

| Key | Default | Description |
|-----|---------|-------------|
| `PROJECT_NAME` | `odoo-demo` | Prefix applied to all resource names |
| `ORGANIZATION` | `Acme Corp` | Display name used in generated configs |

### Domain

| Key | Default | Description |
|-----|---------|-------------|
| `DOMAIN_MODE` | `single` | `single` or `multi` (multi enables alias domains) |
| `PRIMARY_DOMAIN` | `odoo.example.com` | Primary domain — must resolve before SSL setup |
| `ALIAS_DOMAINS` | _(empty)_ | Comma-separated aliases, only used if `DOMAIN_MODE=multi` |
| `ADMIN_EMAIL` | `admin@example.com` | Let's Encrypt registration + Odoo admin notifications |

### Infrastructure

| Key | Default | Description |
|-----|---------|-------------|
| `DO_REGION` | `nyc3` | DigitalOcean region for all resources |
| `DROPLET_SIZE` | `s-2vcpu-4gb` | 2 vCPU / 4 GB RAM ($24/mo) — right-sized for 10 users |
| `VOLUME_SIZE_GB` | `25` | Block Storage size in GB |
| `SSH_KEY_FINGERPRINT` | _(auto)_ | Leave blank to upload `~/.ssh/id_ed25519.pub` automatically |
| `SSH_PORT` | `9292` | Non-standard SSH port applied during hardening |

### Database

| Key | Default | Description |
|-----|---------|-------------|
| `DB_NAME` | `odoo-01` | PostgreSQL database name |
| `DB_USER` | `odoo` | PostgreSQL username |

### Spaces

| Key | Default | Description |
|-----|---------|-------------|
| `TFSTATE_BUCKET` | `${PROJECT_NAME}-tfstate` | Bucket for Terraform remote state (Standard storage) |
| `BACKUP_BUCKET` | `${PROJECT_NAME}-backups` | Bucket for daily backups (Cold Storage — 3x cheaper) |
| `SPACES_REGION` | `${DO_REGION}` | Region for both Spaces buckets |

### Backup

| Key | Default | Description |
|-----|---------|-------------|
| `BACKUP_RETENTION_DAYS` | `30` | Days to retain backup files in Spaces |
| `BACKUP_NOTIFY_EMAIL` | `${ADMIN_EMAIL}` | Email address for backup failure alerts |

### Monitoring

| Key | Default | Description |
|-----|---------|-------------|
| `ICINGA2_ENABLED` | `false` | Set to `true` to install and register Icinga2 agent |
| `ICINGA2_MASTER` | _(empty)_ | Hostname or IP of your Icinga2 master |

### OdooKit

| Key | Default | Description |
|-----|---------|-------------|
| `ODOOKIT_REPO` | `https://github.com/salsedge/odookit` | Source repo for E2E verification tooling |

## Day-2 Operations

```bash
make ssh              # Open SSH session to the droplet
make status           # Check Docker, Nginx, and UFW status on the droplet
make logs             # Tail Odoo container logs (Ctrl-C to exit)
make backup-now       # Trigger an immediate backup to Spaces
make set-domain       # Update PRIMARY_DOMAIN and regenerate Nginx config
make deploy-addon     # Upload and install a custom Odoo addon
make tf-destroy       # Destroy all DigitalOcean infrastructure (interactive confirmation)
```

Run `make help` for the full target list.

## Regenerating Configs

After editing `instance.conf`, regenerate all derived configs (Terraform vars, Nginx, Compose, Odoo conf) by running:

```bash
make generate
```

This replaces all template placeholders without touching secrets in `.env`. Re-run `make deploy` to push updated configs to the droplet.

## Companion Tools — OdooKit

For E2E deployment verification, see [OdooKit](https://github.com/salsedge/odookit). Clone it into your project:

```bash
git clone https://github.com/salsedge/odookit odookit/
make test
```

OdooKit runs Playwright-based smoke tests against a live Odoo instance — login, CRM, invoicing, and module health checks.

## Destroying an Instance

```bash
make tf-destroy
```

This destroys all DigitalOcean resources created by Terraform (droplet, volume, VPC, firewall, Spaces buckets). Data on the volume is permanently deleted. Confirm the backup Spaces bucket contents before destroying if you need to retain data.

## Further Reading

- [docs/PRD.md](docs/PRD.md) — Product requirements, architecture decisions, security controls
- [.planning/REQUIREMENTS.md](.planning/REQUIREMENTS.md) — Full requirements traceability
- [.planning/ROADMAP.md](.planning/ROADMAP.md) — Phase roadmap and delivery history

## License

Private — SALS Edge / Bibbeo Infrastructure
