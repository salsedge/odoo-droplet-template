# Project Research Summary

**Project:** Odoo 19.x Production Build
**Domain:** Containerized Odoo ERP deployment on DigitalOcean with Terraform IaC, WireGuard VPN, and Icinga2 monitoring
**Researched:** 2026-02-20
**Confidence:** MEDIUM

## Executive Summary

This project delivers production-ready Infrastructure-as-Code for a 10-user Odoo Community deployment on DigitalOcean: a single `terraform apply` produces a fully hardened, monitored Odoo ERP behind a WireGuard VPN gateway. The architecture is a two-droplet pattern — a minimal WireGuard gateway that fronts all admin access, and an Odoo application server running three Docker containers (Nginx, Odoo, PostgreSQL) on an isolated Docker bridge network with persistent Block Storage. This is the well-established production pattern for single-instance Odoo deployments; it is neither over-engineered (no Kubernetes, no ELK, no replication) nor under-engineered (full PCI-DSS hardening, offsite backups, Icinga2 integration). All research findings are based on mature, stable technology patterns — the primary confidence gap is the Odoo 19.0 release status, which must be verified before choosing the Docker image tag.

The recommended build approach follows a strict dependency-driven phase order: Terraform foundation first (state backend, VPC, firewall), then compute, then OS hardening before any service is deployed, then WireGuard before SSH is locked down, then the Docker application stack, then SSL, then monitoring, and finally backup operations. This sequence eliminates a class of pitfalls (locked-out droplets, unhardened windows, data on ephemeral storage) that catch operators who jump straight to `docker compose up`. The hardening-before-services ordering is non-negotiable for PCI-DSS compliance.

The dominant risks are data loss from Docker volume mismanagement, infrastructure-level secrets leakage through unprotected Terraform state, Docker silently bypassing UFW iptables rules (a well-documented but frequently missed issue), and the WireGuard gateway becoming an unrecoverable single point of failure. All four are preventable at build time by following the mitigations documented in PITFALLS.md. None require external tooling or architectural changes — they require discipline in the Terraform module structure, Docker Compose configuration, and documented operational procedures.

## Key Findings

### Recommended Stack

The stack is constrained by project requirements (DigitalOcean, Terraform, Docker Compose, Odoo Community) and research validates that these constraints are the correct choices for the scale. The most important version decision is Odoo's: the project is named "19.x" but Odoo 19.0 availability was unconfirmed at research time. **This must be verified before implementation.** If Odoo 19.0 is available, use it; if not, use 18.0, which is confirmed stable and well-documented. PostgreSQL 16.x is the safe companion for Odoo 18.0; verify compatibility if using Odoo 19.0.

The infrastructure layer is high confidence: Terraform 1.14.x (confirmed from live local tooling), DigitalOcean provider ~2.40, DO Spaces as the S3-compatible remote state backend, Ubuntu 24.04 LTS as the base OS (preferred over 22.04 for newer kernel and longer support), and WireGuard via the Ubuntu in-kernel module. For the application layer, Nginx should be host-installed (not containerized) to simplify Let's Encrypt certbot integration, and Icinga2 agent must be host-installed (not containerized) to retain visibility into Docker daemon failures.

**Core technologies:**
- Odoo Community 18.0 (or 19.0 if released): ERP application — the official Docker Hub image; verify version before committing
- PostgreSQL 16.x: Database — `postgres:16-bookworm`, confirmed compatible with Odoo 18.0
- Nginx 1.27.x: Reverse proxy and SSL termination — host-installed for simpler certbot integration
- Terraform 1.14.x: IaC provisioning — confirmed from local tooling; pin `required_version = ">= 1.9"`
- Docker Engine 27.x + Compose v2: Container runtime — from Docker's official apt repo, not Ubuntu's `docker.io`
- WireGuard: VPN gateway — in-kernel since Ubuntu 20.04, minimal config overhead
- Ubuntu 24.04 LTS: Base OS — preferred for newer kernel, security support until 2029
- DigitalOcean Spaces: Terraform remote state + offsite backup destination
- DigitalOcean Block Storage Volumes: Persistent data (PostgreSQL data dir + Odoo filestore)
- Icinga2 agent: Host-level monitoring daemon connecting to existing master
- fail2ban + UFW: Host firewall and brute-force protection (PCI-DSS requirement)
- Certbot with certbot-dns-digitalocean: SSL certificate management (DNS-01 challenge preferred)
- rclone: Backup sync to DO Spaces (more flexible than s3cmd)

### Expected Features

Research confirmed a clear feature boundary. Everything in the v1 MVP list is required for a PCI-DSS baseline production deployment — none of these are optional, and all are achievable in a single focused build effort. The differentiator features (image scanning, Nginx rate limiting, Fail2ban Odoo jail) are low-complexity and should be added in the same build pass rather than a separate "v1.x" phase, since the marginal cost is low once the foundation is in place.

**Must have (table stakes):**
- Terraform IaC for all DO resources (VPC, firewall, droplets, volumes, Spaces) — core value proposition
- WireGuard gateway droplet with client peer configs — PCI-DSS admin access isolation
- Full system hardening (SSH, UFW, fail2ban, kernel params, auto-updates) — PCI-DSS baseline
- Docker + Docker Compose with hardened daemon configuration — container runtime
- PostgreSQL container with persistent Block Storage and performance tuning — database layer
- Odoo container (CRM + Project modules) with worker configuration — application layer
- Nginx reverse proxy with Let's Encrypt TLS — public HTTPS access
- Automated PostgreSQL backups to local volume + DO Spaces — disaster recovery
- Icinga2 agent with container, system, PostgreSQL, and backup monitoring checks — operational visibility
- Deployment and operational documentation — required for a reproducible, handoff-ready deliverable

**Should have (add in same build pass):**
- Container image scanning (Trivy) — low complexity, meaningfully improves security posture
- Fail2ban Odoo login jail — extends existing fail2ban setup to cover Odoo authentication
- Nginx rate limiting on /web/login — single directive, prevents brute-force at proxy layer
- Audit logging (auditd) — PCI-DSS 10.x requirement, should not be deferred
- Docker daemon `iptables: false` with manual iptables management — critical for UFW to actually work

**Defer to v2+:**
- CI/CD pipeline — explicitly out of scope; low deployment frequency does not justify setup cost
- Staging environment — single production environment for v1
- PgBouncer connection pooling — not needed at 10 users with correct `db_maxconn` tuning
- Prometheus/Grafana — Icinga2 provides sufficient operational visibility at this scale
- Database replication — RTO target of 30 minutes is met by backup/restore approach

**Anti-features to avoid:**
- Kubernetes/Docker Swarm — massively overkill for 10 users
- Odoo Enterprise — not needed for CRM + Project
- External secrets managers (Vault, AWS SSM) — unnecessary complexity; .env files with correct permissions are sufficient
- ELK/EFK log aggregation — Elasticsearch alone needs 4GB+ RAM; Docker log rotation is sufficient

### Architecture Approach

The architecture is a two-droplet design within a single DigitalOcean VPC: a minimal WireGuard gateway droplet ($6/month, 1 vCPU / 1 GB RAM) and an Odoo application server droplet (recommended s-4vcpu-8gb for comfortable headroom). All persistent data lives on a separately provisioned DO Block Storage Volume mounted at `/mnt/data`, subdivided into `pg_data/`, `odoo_filestore/`, and `backups/`. The Docker Compose stack uses a dual-network pattern: a `frontend` bridge network connecting Nginx and Odoo, and a `backend` internal bridge network connecting Odoo and PostgreSQL. PostgreSQL is unreachable from Nginx and has no outbound internet access. Icinga2 agent runs on the host — not in a container — to maintain visibility across Docker daemon failures.

**Major components:**
1. **Terraform modules** (networking, wireguard, odoo-server, backup) — provision all DO resources and execute bootstrap scripts via `remote-exec` provisioners
2. **WireGuard gateway droplet** — sole public-facing management endpoint; routes admin traffic to Odoo droplet via VPC private network
3. **Nginx reverse proxy** (host-installed) — TLS termination, HTTP-to-HTTPS redirect, proxy_pass to Odoo on 8069/8072, security headers
4. **Odoo container** — application logic, CRM and Project modules, configured with 2-3 workers for prefork mode (not threaded)
5. **PostgreSQL container** (backend network only) — data store, performance-tuned for 4-8GB RAM host, data on Block Storage
6. **DO Block Storage Volume** — persistent data plane; survives droplet destruction; independently resizable
7. **DO Spaces** — Terraform remote state backend + offsite backup destination; separate access keys for each use
8. **Icinga2 agent** (host-installed) — custom check scripts for container health, PostgreSQL, backup age, SSL expiry
9. **Hardening scripts** — PCI-DSS baseline executed by Terraform provisioners: UFW, fail2ban, SSH config, kernel params, Docker daemon hardening

### Critical Pitfalls

1. **Docker bypasses UFW iptables rules** — Docker injects its own iptables rules directly, making UFW's "deny all" policies ineffective for published container ports. Fix: set `"iptables": false` in `/etc/docker/daemon.json` and manage iptables manually, or bind all container ports to `127.0.0.1`. This is the most common false-sense-of-security issue on Docker hosts and must be addressed in the hardening phase before any containers are deployed.

2. **Terraform state file exposes secrets in plaintext** — all resource attributes, including database passwords and API tokens, are stored in `terraform.tfstate` regardless of `sensitive = true` in HCL. Configure DO Spaces as the remote backend with `encrypt = true` and bucket versioning before the first `terraform apply`. Add `*.tfstate*` to `.gitignore` at project initialization. Never generate SSH private keys via `tls_private_key` resource (they land in state).

3. **Docker volume data loss from `docker compose down -v`** — the official Odoo image defines `VOLUME` directives that create anonymous volumes unless explicitly overridden. All volumes must be named or bind-mounted to `/mnt/data` subdirectories backed by DO Block Storage. Never run `docker compose down -v` in production. Verify with `docker inspect` that mounts point to Block Storage paths.

4. **WireGuard gateway as single point of failure for admin access** — once SSH is locked to VPN-only (PCI-DSS requirement), a failed WireGuard droplet means zero management access. Mitigate by: documenting the DO Console browser-VNC "break glass" procedure, backing up WireGuard keys to DO Spaces, and testing droplet rebuild from Terraform before going live.

5. **Terraform force-replaces production droplets on config changes** — changing `image`, `region`, or `user_data` on a `digitalocean_droplet` resource triggers destruction and recreation. Add `lifecycle { prevent_destroy = true }` to droplet and volume resources. All persistent data must be on Block Storage Volumes (separate Terraform resources that survive droplet replacement). Always review `terraform plan` output for `# forces replacement` before applying.

## Implications for Roadmap

Based on research, the build follows a strict dependency-driven 8-phase sequence. Each phase is a hard prerequisite for the next. The ordering is not a preference — it is enforced by infrastructure and security dependencies.

### Phase 1: Terraform Foundation and Remote State
**Rationale:** Cannot provision anything until Terraform is configured with a secure remote state backend. State security (DO Spaces backend + encryption) must be established before any secrets land in state files. This is the only phase with no infrastructure prerequisites.
**Delivers:** Working Terraform project structure, DO Spaces backend configured, provider pinned, `.gitignore` with `*.tfstate*`, variable files with documented required inputs.
**Addresses:** Terraform IaC for all DO resources (starting point), remote state backend (DO Spaces).
**Avoids:** Terraform state secrets exposure (Pitfall 2). This pitfall is unrecoverable after the fact — it must be addressed here.

### Phase 2: Networking and Compute
**Rationale:** VPC and firewall must exist before droplets are created. Droplets must exist before any configuration can be applied. Block Storage Volume must attach before any container data is written.
**Delivers:** DO VPC, Cloud Firewall rules (Terraform-managed), WireGuard gateway droplet, Odoo application droplet, Block Storage Volume attached and formatted.
**Addresses:** VPC + Cloud Firewall, WireGuard gateway droplet, Odoo host droplet with block storage.
**Avoids:** Terraform force-replacement (Pitfall 6) — `lifecycle { prevent_destroy = true }` and `ignore_changes = [user_data]` go in here; PostgreSQL data loss (Pitfall 1) — Block Storage established as the data plane before any service is deployed.

### Phase 3: Base OS Hardening (Both Droplets)
**Rationale:** Hardening must happen before any service is deployed. Installing Docker before hardening creates an unhardened window. The Docker daemon's iptables manipulation (Pitfall — UFW bypass) must be addressed before Docker is installed, because installing Docker first and then trying to reconfigure iptables requires a Docker restart that drops live connections.
**Delivers:** UFW with default-deny plus explicit allow rules, fail2ban with SSH jail, SSH hardened (key-only, non-root, MaxAuthTries), kernel params applied (SYN flood, ICMP redirect), unattended-upgrades configured, Docker daemon.json pre-staged with `"iptables": false` before Docker installation.
**Addresses:** Full system hardening (SSH, UFW, fail2ban, kernel, auto-updates), PCI-DSS baseline.
**Avoids:** Docker iptables bypass (Pitfall — UFW bypass in PITFALLS.md Security Mistakes section). Hardening scripts must be idempotent (check-before-modify) per FEATURES.md differentiator.

### Phase 4: WireGuard VPN
**Rationale:** WireGuard must be operational before SSH is locked to VPN-only access. Attempting to lock down SSH before the VPN works results in complete admin lockout. The "break glass" recovery procedure must be documented and tested in this phase — not after.
**Delivers:** WireGuard server on gateway droplet (wg0 interface, UDP 51820, iptables NAT), client peer configurations generated and distributed, VPN connectivity verified (SSH through tunnel to Odoo droplet private IP), DO Console "break glass" procedure documented and tested.
**Addresses:** WireGuard VPN for admin access, client peer configs, IP forwarding and NAT, split tunneling.
**Avoids:** WireGuard single point of failure (Pitfall 3) — break glass procedure and key backup to DO Spaces happen here.

### Phase 5: Docker Installation and Application Stack
**Rationale:** Docker must be installed after hardening (Phase 3) with `iptables: false` pre-configured. The application stack deploys in dependency order (PostgreSQL first via healthcheck, then Odoo, then Nginx). All volumes must bind-mount to `/mnt/data` on Block Storage — no anonymous volumes.
**Delivers:** Docker CE + Compose plugin from official apt repo, Docker daemon hardened (userns-remap, log limits, icc=false, no-new-privileges), `docker-compose.yml` with dual-network isolation, PostgreSQL container with performance-tuned `postgresql.conf`, Odoo container with CRM/Project modules pre-installed and worker configuration, Nginx reverse proxy with initial self-signed cert (replaced in Phase 6), container health checks, resource limits.
**Addresses:** Docker + daemon hardening, PostgreSQL container + tuning, Odoo container + CRM/Project modules, container health checks, worker configuration, database manager disabled.
**Avoids:** Docker volume data loss (Pitfall 1) — explicit named volumes bound to Block Storage; Odoo running as root (Pitfall 4) — `user: odoo`, `cap_drop: ALL`, `no-new-privileges:true`; PostgreSQL exposure (Pitfall 5) — no `ports:` directive on PostgreSQL service, backend network is `internal: true`.

### Phase 6: SSL and Public Access
**Rationale:** Nginx must be running (from Phase 5) before Let's Encrypt certificate issuance can succeed. DNS must be pointing to the correct droplet IP before certbot runs. Use certbot-dns-digitalocean (DNS-01 challenge) to avoid needing port 80 open, which eliminates the firewall/timing issue.
**Delivers:** DNS A record confirmed pointing to Odoo droplet public IP, certbot with `certbot-dns-digitalocean` plugin, valid Let's Encrypt certificate, Nginx reconfigured for TLS, HTTP-to-HTTPS redirect, security headers (HSTS, X-Frame-Options, CSP), longpolling/WebSocket proxy for Odoo port 8072, `certbot renew --dry-run` verified, systemd timer for auto-renewal.
**Addresses:** Nginx reverse proxy with Let's Encrypt TLS, security headers, Odoo longpolling proxy.
**Avoids:** Let's Encrypt silent failure (Pitfall 7) — `--dry-run` before real cert, DNS-01 challenge avoids port 80 issues, self-signed cert in place from Phase 5 means Nginx stays up during cert issuance.

### Phase 7: Monitoring
**Rationale:** Monitoring checks target containers and services that must be running first (Phases 5-6). Icinga2 agent registration requires access to the existing master — this is an external dependency that may require coordination. Setting up monitoring after the application is running means checks can be immediately verified as functional.
**Delivers:** Icinga2 agent installed on host (not containerized), agent registered with existing master via ticket-based CSR, custom check scripts for container health (Odoo, PostgreSQL, Nginx), PostgreSQL-specific checks, Docker daemon monitoring, SSL certificate expiry check (30-day warning), backup age check, standard system checks (disk, CPU, memory), host and service definitions added to master.
**Addresses:** Icinga2 agent with core monitoring checks, container health monitoring, PostgreSQL monitoring, SSL certificate monitoring.
**Research flag:** Icinga2 agent-to-master registration workflow (CSR signing vs. ticket-based) needs verification against the existing master's configuration. This is an external dependency — test connectivity and registration process early to avoid blocking the phase.

### Phase 8: Backup, Restore Testing, and Operational Documentation
**Rationale:** Backup configuration comes last because it requires a running PostgreSQL instance to test. Restore testing must be performed in the same phase to confirm backups are actually functional. Documentation is finalized here because all components are now deployed and verified.
**Delivers:** `pg_dump` daily cron (systemd timer) to `/mnt/data/backups/`, rclone sync to DO Spaces with 30-day retention, separate Spaces access key for backups (not shared with Terraform state key), restore procedure tested to a fresh temporary container, Icinga2 backup age check active and alerting, architecture diagram, deployment runbook, variable reference, operational runbook (backup/restore/update/scale procedures).
**Addresses:** Automated PostgreSQL backups (local + DO Spaces), backup monitoring, deployment documentation, operational documentation.
**Avoids:** Backup not restorable (PITFALLS.md "Looks Done But Isn't" checklist item) — restore test is a required deliverable of this phase, not an afterthought.

### Phase Ordering Rationale

- **State before everything:** Terraform remote state security cannot be retrofitted. It must exist before any `terraform apply` writes secrets to state.
- **Networking before compute:** Droplets need a VPC to join and a firewall to attach to at creation time.
- **Hardening before services:** UFW/iptables configuration must precede Docker installation to prevent the Docker iptables bypass issue. This is the most commonly violated ordering in Docker + UFW deployments.
- **WireGuard before SSH lockdown:** SSH can only be restricted to VPN-only access after the VPN is verified working. These two steps are logically sequential within Phase 4.
- **Application stack before SSL:** Nginx must be running and serving HTTP before certbot can complete validation (even with DNS-01, Nginx needs to be proxying Odoo to be worth having a cert).
- **Monitoring after application:** Checks need live targets. Attempting to configure checks before containers run produces only noise.
- **Backup last:** Requires PostgreSQL running for `pg_dump`. Restore test requires a fresh database container to restore into.

### Research Flags

Phases needing careful verification during implementation:

- **Phase 1 (Terraform Foundation):** Verify the exact DO Spaces backend configuration flags required (`skip_credentials_validation`, `skip_metadata_api_check`, `skip_requesting_account_id`) for the current DigitalOcean Terraform provider version. These flags are not AWS-standard and vary by provider version.
- **Phase 2 (Networking and Compute):** **Verify Odoo version** — confirm whether `odoo:19.0` exists on Docker Hub before committing to an image tag. If not available, use `odoo:18.0`. Also verify current DigitalOcean provider version on registry.terraform.io.
- **Phase 7 (Monitoring):** Icinga2 agent registration with the existing master is an external dependency requiring coordination. The ticket-based CSR workflow needs verification against the master's actual configuration. Budget time for this — it is frequently the slowest phase due to external coordination.

Phases with well-established patterns (standard implementation, no deep research needed):

- **Phase 3 (Hardening):** UFW, fail2ban, SSH hardening, and kernel parameters are fully documented Linux system administration topics. Scripts follow well-known patterns with no novel integration challenges.
- **Phase 4 (WireGuard):** WireGuard configuration is minimal and extremely well-documented. The Ubuntu in-kernel module eliminates most historical complexity.
- **Phase 5 (Docker stack):** Docker Compose dual-network pattern, PostgreSQL tuning for 4-8GB RAM, and Odoo worker configuration are all well-documented. The postgresql.conf values can be generated by pgtune.leopard.in.ua.
- **Phase 6 (SSL):** certbot-dns-digitalocean is well-documented. The main risk is DNS propagation timing, which dry-run catches.
- **Phase 8 (Backup):** pg_dump + rclone to S3-compatible storage is a standard pattern with extensive documentation.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Terraform version confirmed from live tooling (HIGH). Docker versions confirmed locally (HIGH). Odoo version unconfirmed (LOW) — must verify 19.0 availability before implementation. PostgreSQL 16 + Odoo 18 compatibility is training-data based (MEDIUM). DO provider version ~2.40 unverified against live registry (MEDIUM). |
| Features | MEDIUM | Feature set derived from project requirements (HIGH confidence source) and well-established Odoo/PCI-DSS deployment patterns (MEDIUM). Anti-features are clearly justified by scale (10 users). WebSearch unavailable for live Odoo documentation verification. |
| Architecture | MEDIUM | Two-droplet pattern, dual-network Docker isolation, host-level Icinga2, and DO Block Storage for persistence are all mature, well-documented patterns with HIGH confidence. Specific resource attribute names in the DO Terraform provider should be verified against current provider docs during Phase 1. |
| Pitfalls | MEDIUM-HIGH | The Docker/UFW iptables bypass, Terraform state plaintext storage, and Docker volume lifecycle behaviors are extensively documented in official Docker and Terraform documentation. These are not speculative risks — they are known, confirmed failure modes. Confidence is HIGH for the technical accuracy of each pitfall. MEDIUM overall because exact mitigation syntax (daemon.json flags, Terraform lifecycle block syntax) should be verified against current tool versions. |

**Overall confidence:** MEDIUM

### Gaps to Address

- **Odoo 19.0 availability:** The single most important open question. Check `docker pull odoo:19.0` or `docker pull odoo:latest` and inspect the resulting image tag before writing any `docker-compose.yml`. If 19.0 is not yet released, the entire stack uses 18.0 (which is fully documented and stable).
- **Odoo 19.0 PostgreSQL compatibility:** If Odoo 19.0 is available, verify its PostgreSQL version requirements from the release notes before committing to PostgreSQL 16. It may require PostgreSQL 17.
- **DO Terraform provider current version:** Verify `~> 2.40` against https://registry.terraform.io/providers/digitalocean/digitalocean/latest before writing `versions.tf`.
- **Icinga2 master registration workflow:** Coordinate with whoever manages the existing Icinga2 master before Phase 7. Determine whether ticket-based or CSR-signing workflow is in use. This cannot be scripted without knowing the master's configuration.
- **DO Spaces backend Terraform flags:** The `skip_credentials_validation`, `skip_metadata_api_check`, and `skip_requesting_account_id` flags required for DO Spaces (S3-compatible but not AWS) may have changed with newer provider versions. Verify the backend configuration block against current documentation.
- **Docker daemon `iptables: false` interaction with Docker Compose networks:** When `iptables: false` is set, Docker does not manage iptables at all. The manual iptables rules must allow inter-container communication on Docker bridge networks (the `frontend` and `backend` Compose networks). This requires careful rule ordering and testing. Reference the `ufw-docker` project documentation as an alternative mitigation if manual iptables management proves complex.

## Sources

### Primary (HIGH confidence)
- `.planning/PROJECT.md` and `artifacts/Initial_Prompt.md` — project requirements, constraints, and out-of-scope decisions
- Local `terraform version` output — Terraform 1.14.5 confirmed (2026-02-20)
- Local `docker version` output — Docker Engine 29.1.5, Docker Compose v5.0.1 confirmed (2026-02-20)

### Secondary (MEDIUM confidence)
- Training data: Docker Compose networking, dual-network isolation pattern, named volumes vs anonymous volumes behavior
- Training data: Terraform DigitalOcean provider resource types (`digitalocean_droplet`, `digitalocean_vpc`, `digitalocean_firewall`, `digitalocean_volume`, `digitalocean_spaces_bucket`)
- Training data: Docker daemon `iptables: false` and UFW bypass — well-documented behavior in Docker and UFW official documentation
- Training data: WireGuard configuration on Ubuntu, in-kernel module, `wg-quick` toolchain
- Training data: Odoo 18.0 deployment — worker configuration, `odoo.conf` parameters, CRM/Project module installation
- Training data: PostgreSQL 16.x tuning parameters for 4-8GB RAM workloads (pgtune methodology)
- Training data: PCI-DSS v4.0 control mapping to technical controls (UFW, fail2ban, audit logging, SSH hardening)
- Training data: Icinga2 agent-master TLS model, zone configuration, custom check script patterns
- Training data: Let's Encrypt ACME protocol, certbot-dns-digitalocean plugin, DNS-01 vs HTTP-01 challenge trade-offs
- Training data: Terraform state file plaintext behavior, `lifecycle` blocks, force-replacement attributes

### Tertiary (LOW confidence — verify before implementation)
- Odoo 19.0 existence and Docker Hub availability — **unverified**; project name implies intent but release is unconfirmed
- DigitalOcean Terraform provider version ~2.40 — training data, unverified against live registry
- Icinga2 agent apt repository setup for Ubuntu 24.04 — may require verification against packages.icinga.com

---
*Research completed: 2026-02-20*
*Ready for roadmap: yes*
