# Odoo 19.x Production Build

Production-ready, Infrastructure-as-Code deployment of Odoo Community 19.x on DigitalOcean — PCI-DSS hardened, containerized, with Nginx/SSL reverse proxy and Icinga2 monitoring.

## Architecture

```
Internet → DO Cloud Firewall → Ubuntu 24.04 Droplet (s-2vcpu-4gb)
                                  ├── Nginx (host) — HTTPS :443, HTTP :80 redirect
                                  │     ↓ proxy_pass
                                  ├── Odoo 19 container — 127.0.0.1:8069/8072
                                  │     ↕ backend network (internal)
                                  ├── PostgreSQL 18 container — no published ports
                                  │     ↓
                                  └── DO Block Storage Volume (25 GB)
                                        ├── postgres-data/
                                        └── odoo-filestore/
```

Single-droplet architecture in a DO VPC. Docker dual-network isolation: `frontend` (Nginx ↔ Odoo) and `backend` (Odoo ↔ PostgreSQL, internal, no outbound). All persistent data on Block Storage Volume.

## What You Get

- **Terraform IaC** — `terraform apply` provisions VPC, firewall, droplet, volume, and Spaces state backend
- **PCI-DSS host hardening** — SSH (key-only, port 9292), UFW, fail2ban, sysctl, auditd, auto-updates
- **Containerized stack** — Odoo 19 + PostgreSQL 18 via Docker Compose with resource limits, health checks, non-root
- **Nginx + Let's Encrypt** — HTTPS with HSTS, security headers, auto-renewal, database manager routes blocked
- **Icinga2 monitoring** — Agent with custom checks for containers, PostgreSQL, and system resources (Phase 3)
- **Automated backups** — Daily pg_dump to local + DO Spaces with tested restore procedure (Phase 4)

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Terraform | ≥ 1.6.3 |
| DigitalOcean account | API token + Spaces access keys |
| SSH key pair | Ed25519 recommended |
| Domain name | DNS A record pointed to droplet IP (needed before SSL setup) |
| Local machine | macOS/Linux with SSH client |

## DigitalOcean Credentials

This project requires **two separate credential sets** from DigitalOcean. They are obtained from different pages and serve different purposes. Recommend Storing all Keys and Passwords in BitWarden.

### 1. API Token (for Terraform provider)

The API token authenticates Terraform to create and manage DO resources (droplets, VPCs, firewalls, volumes).

1. Go to **[cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens)**
2. Click **Generate New Token**
3. Give it a name (e.g., `odoo-prod-terraform`)
4. Select **Full Access** (read + write — required to create/destroy resources)
5. Copy the token — it is only shown once

Set it as:
```bash
DIGITALOCEAN_TOKEN=dop_v1_xxxxxxxxxxxxxxxxxxxx
```

### 2. Spaces Access Keys (for Terraform state backend)

Spaces keys authenticate the Terraform S3 backend to store remote state. These are **not** the same as the API token above — they are object storage credentials scoped to DO Spaces.

1. Go to **[cloud.digitalocean.com/spaces/access_keys](https://cloud.digitalocean.com/spaces/access_keys)**
2. Click **Generate Access Key**
3. Choose **Full Access**
4. Give it a name (e.g., `odoo-prod-tfstate`)
5. Copy both the **Access Key** and **Secret Key** — the secret is only shown once

Set them as:
```bash
AWS_ACCESS_KEY_ID=DO00XXXXXXXXXXXXXXXXXXXX        # "Access Key" from DO Spaces page
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxx  # "Secret Key" from DO Spaces page
```

> **Why AWS variable names?** Terraform's S3 backend uses AWS variable names regardless of provider. These are DigitalOcean Spaces credentials — not AWS credentials.

### 3. Create the Spaces bucket (one-time, manual)

Terraform's remote state backend cannot create its own bucket. You must create it manually before running `terraform init`:

1. Go to **[cloud.digitalocean.com/spaces](https://cloud.digitalocean.com/spaces)**
2. Click **Create Bucket**
3. Choose the same region as your droplet (default: `nyc3`)
4. Name it `odoo-prod-tfstate` (must match `bucket` in `infra/backend.tf`)
5. Set access to **Private**
6. Leave **CDN** disabled — this bucket stores Terraform state files, not public content. CDN caching on a state bucket can cause Terraform to read stale state and produce incorrect plans or conflicts.

> The bucket name in `infra/backend.tf` is hardcoded — Terraform backend blocks cannot use variables. If you use a different name, update `backend.tf` to match.

### 4. SSH key in DO account

The Terraform config references an existing SSH key in your DO account by name.

1. Go to **[cloud.digitalocean.com/account/security](https://cloud.digitalocean.com/account/security)**
2. Under **SSH Keys**, click **Add SSH Key**
3. Paste your public key (`~/.ssh/id_ed25519.pub` or equivalent)
4. Give it a name — use this name as `ssh_key_name` in `infra/terraform.tfvars`

---

## Quick Start

### 1. Clone and configure

```bash
git clone <repo-url> && cd odoo-19.x-build

# Infrastructure credentials (Makefile auto-loads this)
cp .env.example .env
chmod 600 .env
# Edit .env — fill in DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# from the steps above

# Terraform variables (non-secret config)
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit terraform.tfvars — set ssh_key_name to your DO SSH key, allowed_ssh_ips to your IP

# Application secrets (deployed to droplet later)
cp config/.env.example config/.env
chmod 600 config/.env
# Edit config/.env — set strong passwords for POSTGRES_PASSWORD and ODOO_ADMIN_PASSWORD
```

### 2. Provision infrastructure

```bash
make tf-init        # Initialize Terraform backend (requires DO Spaces bucket)
make tf-plan        # Preview what will be created
make tf-apply       # Provision VPC, firewall, droplet, volume
```

### 3. Deploy to droplet

**First run** — upload and harden as root (SSH on port 22):

```bash
# Upload config/ and scripts/ to droplet
make upload SSH_USER=root SSH_PORT=22

# Run host hardening (SSH moves to port 9292, creates deploy user)
make run-harden SSH_USER=root SSH_PORT=22
```

**After hardening** — reconnect as deploy user on port 9292:

```bash
# Install Docker CE
make run-docker

# Deploy Odoo + PostgreSQL stack
make run-stack

# Setup Nginx + SSL (requires DNS A record pointing to droplet IP)
make run-nginx DOMAIN=odoo.example.com CERT_EMAIL=admin@example.com
```

Or run the full post-hardening sequence in one shot:

```bash
make deploy-app DOMAIN=odoo.example.com CERT_EMAIL=admin@example.com
```

### 4. Verify

```bash
curl -I https://odoo.example.com              # Should return 200/302 + HSTS header
curl -I https://odoo.example.com/web/database  # Should return 403
make status                                    # Check Docker, Nginx, UFW on droplet
```

### 5. Teardown and rebuild

```bash
make tf-destroy     # Destroy all DO infrastructure (interactive confirmation)
make tf-apply       # Re-provision from scratch
# Then repeat step 3
```

### Makefile reference

```bash
make help           # Show all available targets
```

| Target | Description |
|--------|-------------|
| `tf-init` | Initialize Terraform backend and providers |
| `tf-plan` | Preview infrastructure changes |
| `tf-apply` | Provision/update DigitalOcean infrastructure |
| `tf-destroy` | Destroy all infrastructure (interactive confirmation) |
| `upload` | Upload config/ and scripts/ to droplet |
| `run-harden` | Run host hardening script |
| `run-docker` | Run Docker CE installation script |
| `run-stack` | Run Odoo + PostgreSQL deployment script |
| `run-nginx` | Run Nginx + SSL setup (requires `DOMAIN`, `CERT_EMAIL`) |
| `deploy-phase2` | Full Phase 2: upload + all 4 scripts in order |
| `deploy-host` | Upload + hardening + Docker install |
| `deploy-app` | Upload + stack deploy + Nginx/SSL |
| `status` | Check remote service status (Docker, Nginx, UFW) |
| `ssh` | Open SSH session to droplet |
| `logs-odoo` | Tail Odoo container logs |
| `logs-postgres` | Tail PostgreSQL container logs |
| `logs-nginx` | Tail Nginx access/error logs |
| `check` | Run local validation (terraform validate + shellcheck) |

## Project Structure

```
Makefile                Wraps Terraform, SCP, and remote script execution
.env.example            Template for infrastructure credentials
.env                    Local credentials — DO token + Spaces keys (gitignored)

infra/                  Terraform — DigitalOcean infrastructure
  ├── providers.tf          Provider config + version constraints
  ├── backend.tf            Remote state on DO Spaces
  ├── variables.tf          Input variables (droplet size, SSH keys, IPs)
  ├── main.tf               Resources: VPC, firewall, droplet, volume
  ├── outputs.tf            Droplet IP, volume path, Spaces endpoint
  └── terraform.tfvars.example

config/                 Configuration files for target host
  ├── docker-compose.yml    Odoo + PostgreSQL services
  ├── odoo.conf             App config (3 workers, proxy_mode, list_db=False)
  ├── postgresql.conf       PG tuning (shared_buffers 256MB, max_connections 50)
  ├── daemon.json           Docker daemon (iptables:false, log rotation)
  ├── sshd-hardening.conf   SSH port 9292, key-only, no root
  ├── sysctl-hardening.conf Kernel hardening (SYN cookies, anti-spoofing)
  ├── jail.local            fail2ban SSH + Odoo login jails
  ├── audit.rules           auditd PCI-DSS 10.x rules
  ├── .env.example          Secrets template (PostgreSQL + Odoo passwords)
  ├── .env                  App secrets — PG + Odoo passwords (gitignored)
  └── nginx/
      ├── odoo-pre-ssl.conf   Temp config for certbot HTTP-01 challenge
      └── odoo.conf            Full SSL reverse proxy with security headers

scripts/                Deployment scripts (run in order: 01 → 04)
  ├── 01-harden-host.sh     Host hardening (HARD-01 → HARD-07)
  ├── 02-install-docker.sh  Docker CE installation
  ├── 03-deploy-stack.sh    Odoo + PostgreSQL Docker Compose stack
  └── 04-setup-nginx.sh     Nginx + Let's Encrypt SSL

docs/                   Documentation
  └── PRD.md                Product Requirements Document

.planning/              GSD planning system (PROJECT, REQUIREMENTS, ROADMAP, STATE)
artifacts/              Original project specification
```

## Configuration

### Terraform Variables (infra/terraform.tfvars)

| Variable | Default | Description |
|----------|---------|-------------|
| `project_name` | `odoo-prod` | Prefix for all resource names |
| `region` | `nyc3` | DigitalOcean region |
| `droplet_size` | `s-2vcpu-4gb` | 2 vCPU, 4 GB RAM ($24/mo) |
| `volume_size_gb` | `25` | Block Storage for PG data + Odoo filestore |
| `ssh_port` | `9292` | Non-standard SSH port |
| `allowed_ssh_ips` | — | CIDR blocks allowed to SSH (restrict to your IP) |

### Environment Variables (config/.env)

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | PostgreSQL username (default: `odoo`) |
| `POSTGRES_PASSWORD` | PostgreSQL password (strong, random) |
| `POSTGRES_DB` | Database name (default: `odoo`) |
| `ODOO_ADMIN_PASSWORD` | Odoo master admin password (strong, random) |

> **Password rules:** Values are parsed by both Docker Compose and bash. Do **not** use `$` (triggers variable interpolation), backticks, double quotes, or single quotes in passwords. Characters like `!`, `^`, `*`, `%`, `&`, `#`, `@` are safe. Do **not** wrap values in quotes — Docker Compose `.env` files treat quotes as literal characters.

## Security Highlights

| Layer | Controls |
|-------|----------|
| **Network** | DO Cloud Firewall + UFW — default deny, allow 9292/80/443 only |
| **Host** | SSH key-only on port 9292, fail2ban, kernel hardening, auditd (PCI-DSS 10.x), auto-updates |
| **Container** | Non-root users, CPU/memory limits, `iptables: false`, dual-network isolation |
| **Application** | Database manager disabled, admin password from .env, `proxy_mode = True` |
| **Transport** | TLS 1.2/1.3, HSTS, OCSP stapling, strong ciphers |
| **Proxy** | `/web/database/*` blocked, CSP headers, X-Frame-Options, X-Content-Type-Options |

## Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Terraform Foundation and Compute | Complete |
| 2 | Hardened Application Stack | In Progress (scripts ready, pending execution) |
| 3 | Monitoring (Icinga2) | Not Started |
| 4 | Backup, Recovery, Documentation | Not Started |
| 5 | Deployment Verification | Not Started |

**Overall Progress:** ~30%

See [.planning/ROADMAP.md](.planning/ROADMAP.md) for full phase details and success criteria.

## Documentation

- [Product Requirements Document](docs/PRD.md) — full requirements, architecture, security controls
- [.planning/REQUIREMENTS.md](.planning/REQUIREMENTS.md) — all 48 v1 requirements with traceability
- [.planning/ROADMAP.md](.planning/ROADMAP.md) — 5-phase delivery roadmap
- [.planning/STATE.md](.planning/STATE.md) — current progress and session state

## License

Private — SALS Edge / Bibbeo Infrastructure
