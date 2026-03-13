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

## Quick Start

### 1. Clone and configure

```bash
git clone <repo-url> && cd odoo-19.x-build

# Terraform variables
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit terraform.tfvars with your values (SSH key name, allowed IPs, etc.)

# Set credentials as environment variables
export DIGITALOCEAN_TOKEN="your-api-token"
export AWS_ACCESS_KEY_ID="your-spaces-access-key"        # DO Spaces key, not AWS
export AWS_SECRET_ACCESS_KEY="your-spaces-secret-key"     # DO Spaces secret, not AWS
```

### 2. Provision infrastructure

```bash
cd infra/
terraform init
terraform plan      # Review what will be created
terraform apply     # Provision VPC, firewall, droplet, volume
```

### 3. Deploy to droplet

```bash
# Copy files to droplet
DROPLET_IP=$(terraform output -raw droplet_ip)
scp -r ../config/ ../scripts/ root@${DROPLET_IP}:/tmp/odoo-setup/

# SSH in and run scripts sequentially
ssh root@${DROPLET_IP}

# 1. Harden host (SSH moves to port 9292 after this)
bash /tmp/odoo-setup/scripts/01-harden-host.sh

# Reconnect on new port with deploy user
exit
ssh -p 9292 deploy@${DROPLET_IP}

# 2. Install Docker
sudo bash /tmp/odoo-setup/scripts/02-install-docker.sh

# 3. Deploy Odoo + PostgreSQL stack
cp /tmp/odoo-setup/config/.env.example /tmp/odoo-setup/config/.env
# Edit .env with strong passwords
sudo bash /tmp/odoo-setup/scripts/03-deploy-stack.sh

# 4. Setup Nginx + SSL (requires DNS A record already pointing to droplet)
sudo bash /tmp/odoo-setup/scripts/04-setup-nginx.sh odoo.example.com admin@example.com
```

### 4. Verify

```bash
curl -I https://odoo.example.com           # Should return 200/302 + HSTS header
curl -I https://odoo.example.com/web/database  # Should return 403
```

## Project Structure

```
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
