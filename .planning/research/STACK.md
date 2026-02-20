# Stack Research

**Domain:** Containerized Odoo ERP deployment with IaC on DigitalOcean
**Researched:** 2026-02-20
**Confidence:** MEDIUM (web search/fetch tools unavailable; versions verified via local tooling where possible, otherwise based on training data with caveats noted)

## Version Verification Notes

The following versions were verified from live local tooling output on 2026-02-20:
- Terraform: local install is v1.5.7, reports latest as **v1.14.5** (live signal)
- Docker Engine: **29.1.5** (live signal)
- Docker Compose: **v5.0.1** (live signal)

All other versions are based on training data (cutoff ~May 2025) and marked accordingly. **Validate Odoo and PostgreSQL versions against official sources before implementation.**

---

## Recommended Stack

### Core Application

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Odoo Community | 18.0 (LTS) | ERP application (CRM + Project) | The project repo is named "19.x" but Odoo 19 has not been confirmed as released at the time of this research. Odoo 18.0 was the latest stable release as of late 2024. **Action required:** verify whether Odoo 19.0 has shipped. If 19.0 is available, use it. If not, use 18.0. The official Docker image (`odoo:18.0` or `odoo:19.0`) is the deployment vehicle. | LOW -- version needs live verification |
| PostgreSQL | 16.x | Relational database for Odoo | Odoo 18.0 officially supports PostgreSQL 12-16. PostgreSQL 16 is the recommended choice: mature, well-tested with Odoo, strong performance improvements (parallelism, logical replication). PostgreSQL 17 released late 2024 but Odoo compatibility should be verified. Use the official `postgres:16-bookworm` Docker image. | MEDIUM -- PG 16 is safe; PG 17 compatibility unconfirmed |
| Nginx | 1.27.x (mainline) or 1.26.x (stable) | Reverse proxy, SSL termination, static file serving | Industry standard for Odoo reverse proxying. Handles websocket proxying for Odoo's live chat/notifications. Use the official `nginx:1.27-alpine` Docker image or install directly on the host. | MEDIUM |

### Infrastructure as Code

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Terraform | >= 1.9, recommend 1.14.x | IaC provisioning of all DigitalOcean resources | Project constraint specifies Terraform. v1.14.5 confirmed as latest via local `terraform version` output. Use >= 1.9 for stable provider protocol and moved block support. Pin in `required_version`. | HIGH -- version confirmed from live tool output |
| DigitalOcean Terraform Provider | >= 2.40 (latest available) | DigitalOcean resource management | The `digitalocean/digitalocean` provider covers all needed resources: `digitalocean_droplet`, `digitalocean_vpc`, `digitalocean_firewall`, `digitalocean_volume`, `digitalocean_spaces_bucket`, `digitalocean_project`. Pin to latest `~> 2.40` in `required_providers`. | MEDIUM -- 2.40+ is training-data based; verify latest on registry |
| Terraform Backend | S3-compatible (DO Spaces) | Remote state storage | DigitalOcean Spaces is S3-compatible, works natively with Terraform's `s3` backend. No need for Terraform Cloud. Cheaper, simpler, stays within DO ecosystem. Encrypt state at rest. | HIGH -- well-documented pattern |

### Container Runtime

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Docker Engine | 27.x (on server) | Container runtime | Project constraint specifies Docker. Use the latest stable 27.x branch on the server (Ubuntu packages from Docker's official apt repository). Local dev is at 29.x but server should track the LTS-aligned releases. Install from `download.docker.com`, not Ubuntu default `docker.io` package. | MEDIUM -- 27.x is conservative; server may have 28.x available |
| Docker Compose | v2.x (plugin) | Multi-container orchestration | Docker Compose v2 ships as a Docker CLI plugin (`docker compose` not `docker-compose`). Sufficient for this workload. No Kubernetes needed for 10 users. Define services, networks, volumes, and health checks in `compose.yml`. | HIGH -- standard approach |

### Networking and Security

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| WireGuard | Kernel module (Ubuntu 22.04+) | VPN gateway for admin access | WireGuard is in-kernel since Linux 5.6 (Ubuntu 20.04+). Vastly simpler than OpenVPN, better performance, smaller attack surface. Install via `apt install wireguard wireguard-tools`. Runs on a dedicated gateway droplet. | HIGH -- mature, well-documented |
| UFW | System default | Host firewall | Ubuntu's standard firewall frontend. Simple rule management, sufficient for this use case. Configure to allow only WireGuard (51820/udp), HTTP/HTTPS (80/443), and Icinga2 (5665/tcp) from VPC. | HIGH |
| fail2ban | Latest from apt | Brute-force protection | Monitors SSH, Odoo web login, and Nginx logs. Essential for PCI-DSS compliance. Configure jails for sshd, nginx-http-auth, and a custom Odoo filter. | HIGH |
| Let's Encrypt (Certbot) | Latest from apt/snap | SSL/TLS certificates | Free, automated SSL. Use certbot with nginx plugin or standalone mode. Configure auto-renewal via systemd timer. The Nginx container (or host Nginx) handles SSL termination. | HIGH |

### Monitoring

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Icinga2 Agent | Latest from Icinga apt repo | Monitoring agent connecting to existing master | Project requirement. Install from Icinga's official apt repository (not Ubuntu's outdated packages). Register with existing master via ticket-based CSR. The agent runs on the host, not in a container, because it needs to monitor the host OS, Docker daemon, and containers. | MEDIUM -- verify current Icinga2 apt repo setup for Ubuntu 24.04 |
| Monitoring Plugins (nagios-plugins) | Latest from apt | Standard check plugins | Provide `check_disk`, `check_load`, `check_procs`, `check_tcp`, etc. Base for custom checks. | HIGH |

### Backup and Storage

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| DigitalOcean Spaces | N/A (managed service) | Offsite backup storage (S3-compatible) | Disaster recovery target. Use `s3cmd` or `rclone` for scheduled PostgreSQL dump uploads. Also serves as Terraform state backend. | HIGH |
| DigitalOcean Volumes | N/A (managed service) | Persistent block storage | Attach to droplet for PostgreSQL data directory and Odoo filestore. Survives droplet destruction. Provisioned via Terraform. | HIGH |
| pg_dump / pg_dumpall | Bundled with PostgreSQL | Database backup tool | Standard PostgreSQL backup. Run via `docker exec` on a schedule (cron or systemd timer). Dump to local volume, then sync to Spaces. | HIGH |
| rclone | Latest from apt or binary | S3-compatible file sync | Sync backups to DigitalOcean Spaces. More flexible than `s3cmd`, supports encryption, bandwidth limits. | HIGH |

### Base OS

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Ubuntu | 24.04 LTS (Noble Numbat) | Server operating system | Prefer 24.04 over 22.04: newer kernel (6.8) with better WireGuard and container support, security updates until 2029, newer default packages. Both are project-acceptable; 24.04 is the better choice for a new deployment. Use DigitalOcean's official Ubuntu 24.04 image. | HIGH |

### Supporting Libraries and Tools

| Library/Tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| cloud-init | Bundled with DO image | First-boot provisioning | Terraform `user_data` for initial SSH key injection, package installation bootstrap |
| systemd timers | System default | Scheduled tasks | Replace cron for backup schedules, certificate renewal, log rotation. Better logging and dependency management than cron. |
| logrotate | System default | Log management | Rotate Odoo, Nginx, PostgreSQL, and Docker logs to prevent disk exhaustion |
| htpasswd (apache2-utils) | From apt | Basic auth for monitoring endpoints | Protect Nginx status pages and health check endpoints from public access |
| jq | From apt | JSON processing in scripts | Parse Docker inspect output, API responses in monitoring check scripts |
| curl | System default | HTTP checks | Used in Docker health checks and Icinga2 custom checks |

## Development Tools (Local Workstation)

| Tool | Purpose | Notes |
|------|---------|-------|
| Terraform >= 1.9 | Write and apply IaC | Pin version in `.terraform-version` or use `tfenv` |
| `doctl` (DO CLI) | DigitalOcean API access, debugging | Useful for `doctl compute ssh`, spaces management |
| WireGuard client | VPN access to deployed infrastructure | `brew install wireguard-tools` (macOS) |
| `terraform-docs` | Auto-generate module documentation | Run in pre-commit hook |
| `tflint` | Terraform linting | Catches provider-specific issues before `terraform plan` |
| `tfsec` or `trivy` | Terraform security scanning | Detect misconfigurations (open firewalls, unencrypted storage) |
| `shellcheck` | Bash script linting | All provisioning scripts should pass shellcheck |

## Installation / Provisioning

### On Server (via Terraform provisioners or cloud-init)

```bash
# Docker (official repository, not Ubuntu's docker.io)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# WireGuard
apt-get install -y wireguard wireguard-tools

# Security hardening
apt-get install -y ufw fail2ban unattended-upgrades

# Monitoring
wget -O - https://packages.icinga.com/icinga.key | gpg --dearmor -o /usr/share/keyrings/icinga-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/ubuntu icinga-$(lsb_release -cs) main" > /etc/apt/sources.list.d/icinga.list
apt-get update && apt-get install -y icinga2 monitoring-plugins

# Backup tools
apt-get install -y rclone

# Let's Encrypt
snap install --classic certbot
```

### On Local Workstation

```bash
# macOS (Homebrew)
brew install terraform doctl wireguard-tools terraform-docs tflint trivy shellcheck jq

# Or use tfenv for Terraform version management
brew install tfenv
tfenv install 1.14.5
tfenv use 1.14.5
```

### Docker Compose Services (compose.yml)

```yaml
services:
  odoo:
    image: odoo:18.0  # or 19.0 if released -- VERIFY
    # ...
  postgres:
    image: postgres:16-bookworm
    # ...
  nginx:
    image: nginx:1.27-alpine
    # ...
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Terraform | Pulumi | If team prefers TypeScript/Python IaC over HCL. Project constraint explicitly chose Terraform. |
| Docker Compose | Kubernetes (k3s) | If scaling beyond ~50 users or needing zero-downtime deployments. Massively overkill for 10 users. |
| PostgreSQL 16 | PostgreSQL 17 | If Odoo officially supports PG 17 at deployment time. PG 17 offers incremental sort improvements but PG 16 is the safe choice. |
| Ubuntu 24.04 | Ubuntu 22.04 | If a specific dependency requires 22.04. Unlikely for this stack; all components support 24.04. |
| rclone | s3cmd | If only simple S3 uploads needed. rclone is more versatile (encryption, bandwidth limits, multi-cloud). |
| Nginx (container) | Nginx (host-installed) | Host-installed Nginx is simpler for Let's Encrypt cert management (certbot nginx plugin). Container Nginx is cleaner for Docker-only stacks. **Recommend host-installed** for this project because Nginx needs to handle SSL for the public interface and interact with certbot cleanly. |
| Icinga2 (host-installed) | Icinga2 (containerized) | Always install Icinga2 agent on the host. It needs to monitor the host OS, kernel, disk, Docker daemon -- all of which are invisible from inside a container. |
| systemd timers | cron | cron is simpler for one-off schedules. systemd timers provide logging, dependency ordering, and better failure handling. Use timers for production. |
| Certbot (standalone/nginx) | Traefik with auto-SSL | Traefik is great for dynamic container discovery. Overkill here -- we have a single Odoo service. Certbot is simpler and well-understood. |
| DO Spaces (Terraform backend) | Terraform Cloud | Terraform Cloud adds a UI and run history but introduces an external dependency. Spaces keeps everything in DO. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `docker.io` Ubuntu package | Outdated, lags behind official Docker releases by months. Missing security patches and features. | Docker CE from `download.docker.com` official apt repository |
| `docker-compose` (v1, Python) | Deprecated since July 2023. No longer maintained. | `docker compose` v2 (Go-based CLI plugin, ships with Docker CE) |
| OpenVPN | Complex configuration, larger attack surface, slower than WireGuard, harder to automate | WireGuard -- simpler, faster, kernel-integrated, ~4000 LOC vs OpenVPN's ~100K LOC |
| Kubernetes / k3s | Extreme overkill for a single-instance 10-user deployment. Adds operational complexity (etcd, API server, kubelet, ingress controllers) with zero benefit at this scale. | Docker Compose |
| Ansible (for provisioning) | Adds another tool to learn/maintain. Terraform provisioners + bash scripts handle everything for a single-server deployment. Ansible adds value at 5+ servers. | Terraform `remote-exec` provisioners + idempotent bash scripts |
| Terraform `local-exec` provisioner | Runs on the machine executing Terraform, not the target server. Common source of confusion and bugs. | `remote-exec` provisioner (runs on the target droplet via SSH) or `file` provisioner + `remote-exec` |
| Odoo.sh | Odoo's own hosting platform. No self-hosting control, no VPN isolation, vendor lock-in. | Self-hosted on DigitalOcean per project requirements |
| Self-built Odoo Docker image (from source) | Unnecessary complexity. Official image is well-maintained, includes all dependencies, supports custom addons via volume mount. | Official `odoo:18.0` (or `19.0`) Docker Hub image |
| PostgreSQL in the Odoo container | Couples database to application, prevents independent scaling, makes backups harder, violates separation of concerns. | Separate `postgres:16-bookworm` container |
| Terraform workspaces for env separation | Workspaces share state backend and config, leading to accidental production changes. | Separate directories per environment (but this project is prod-only for v1, so not relevant yet) |

## Stack Patterns by Variant

**If Odoo 19.0 is released and available on Docker Hub:**
- Use `odoo:19.0` image tag
- Verify PostgreSQL version compatibility in Odoo 19.0 release notes
- May require PostgreSQL 17.x -- check before committing to PG 16

**If staying on Odoo 18.0:**
- Use `odoo:18.0` image tag
- PostgreSQL 16.x is confirmed compatible
- Stable, well-documented community support

**If needing to add custom Odoo modules later:**
- Mount custom addons directory as a Docker volume: `-v ./addons:/mnt/extra-addons`
- Set `--addons-path=/mnt/extra-addons` in Odoo config
- Do NOT build a custom Docker image unless you need system-level Python dependencies

**If scaling beyond 10 users in the future:**
- Add Odoo workers (multi-process mode): `--workers=4 --max-cron-threads=1`
- Increase PostgreSQL `shared_buffers`, `work_mem`
- Consider DO droplet resize via Terraform variable change
- At 50+ users, evaluate moving PostgreSQL to DO Managed Database

## Version Compatibility Matrix

| Odoo Version | PostgreSQL Versions | Python | Notes |
|--------------|---------------------|--------|-------|
| 18.0 | 12, 13, 14, 15, 16 | 3.10+ | Current stable. PG 16 recommended. |
| 17.0 | 12, 13, 14, 15, 16 | 3.10+ | Previous stable. Still supported. |
| 19.0 (if released) | TBD -- verify | TBD | Check release notes for PG version requirements |

| Terraform Version | DO Provider | Notes |
|-------------------|-------------|-------|
| >= 1.9 | >= 2.30 | Minimum for stable feature set |
| 1.14.x | ~> 2.40 | Recommended. Latest confirmed available. |

| Docker Engine | Compose Plugin | Ubuntu |
|---------------|----------------|--------|
| 27.x | v2.29+ | 24.04 LTS |
| 28.x | v2.30+ | 24.04 LTS |

## Terraform Module Structure

```
terraform/
  main.tf              # Provider config, backend, module calls
  variables.tf         # Input variables
  outputs.tf           # Output values (IPs, endpoints)
  terraform.tfvars     # Variable values (gitignored if secrets)
  versions.tf          # required_version, required_providers
  modules/
    networking/        # VPC, firewall rules
    compute/           # Droplets, volumes, SSH keys
    wireguard/         # WireGuard gateway droplet
    dns/               # Domain records (if applicable)
  scripts/
    bootstrap.sh       # Docker install, base packages
    harden.sh          # PCI-DSS hardening
    deploy-odoo.sh     # Docker Compose up, initial config
    setup-wireguard.sh # WireGuard server config
    setup-icinga2.sh   # Icinga2 agent registration
    backup.sh          # Scheduled backup script
```

## Key Terraform Resource Mapping

| Project Need | Terraform Resource | Notes |
|--------------|-------------------|-------|
| Odoo/PG host | `digitalocean_droplet` | s-4vcpu-8gb recommended for 10 users |
| WireGuard gateway | `digitalocean_droplet` | s-1vcpu-1gb sufficient |
| Private network | `digitalocean_vpc` | Isolate all droplets |
| Firewall | `digitalocean_firewall` | Restrict by VPC and WireGuard |
| Persistent storage | `digitalocean_volume` | For PG data + Odoo filestore |
| Backup storage | `digitalocean_spaces_bucket` | For offsite backups + TF state |
| SSH access | `digitalocean_ssh_key` | Managed via Terraform |
| DNS (optional) | `digitalocean_domain` + `digitalocean_record` | If using DO DNS |
| Project grouping | `digitalocean_project` | Organize all resources |

## Sources

- **Terraform version:** Confirmed v1.14.5 latest via local `terraform version` output (2026-02-20) -- HIGH confidence
- **Docker version:** Confirmed v29.1.5 locally, Docker Compose v5.0.1 locally (2026-02-20) -- HIGH confidence for local; server versions will differ
- **Odoo versions:** Based on training data (Odoo 18.0 released Oct 2024). Odoo 19.0 availability UNVERIFIED -- LOW confidence, needs validation
- **PostgreSQL compatibility:** Based on training data (Odoo 18.0 docs). PG 16 compatibility MEDIUM confidence
- **DigitalOcean provider:** Version ~2.40 based on training data -- MEDIUM confidence, verify on registry.terraform.io
- **WireGuard:** In-kernel since Linux 5.6, well-documented on Ubuntu -- HIGH confidence
- **Icinga2:** Based on training data for apt repository setup -- MEDIUM confidence, verify apt repo URL for Ubuntu 24.04
- **Ubuntu 24.04 LTS:** Released April 2024, confirmed in production use -- HIGH confidence

---
*Stack research for: Containerized Odoo ERP on DigitalOcean with Terraform IaC*
*Researched: 2026-02-20*
*Limitation: WebSearch and WebFetch tools were unavailable during this research session. All version claims beyond local tool output are based on training data (cutoff ~May 2025) and should be verified against official sources before implementation.*
