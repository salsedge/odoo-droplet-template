# Feature Research

**Domain:** Production containerized Odoo deployment on DigitalOcean with PCI-DSS compliance
**Researched:** 2026-02-20
**Confidence:** MEDIUM (based on training data + project requirements; web verification tools unavailable)

## Feature Landscape

### Table Stakes (Users Expect These)

Features that are non-negotiable for a production-ready, PCI-DSS-hardened Odoo deployment. Missing any of these means the deployment is not production-grade.

#### Infrastructure as Code

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Terraform DigitalOcean provider setup | Reproducible infrastructure; single `terraform apply` is the core value proposition | LOW | Pin provider version, configure DO API token via env var, remote state on DO Spaces |
| Modular Terraform structure | Maintainability; separate networking, compute, security concerns | MEDIUM | Modules: networking (VPC, firewall), compute (droplets, volumes), wireguard, monitoring |
| Remote state backend (DO Spaces) | Team collaboration, state locking, disaster recovery of state | LOW | S3-compatible backend with encryption-at-rest; separate from app Spaces bucket |
| Variable files for environment config | Customization without code changes (IPs, sizes, keys) | LOW | Use .tfvars files; never commit secrets; document all required variables |
| Terraform outputs for critical info | Post-deploy usability (IPs, endpoints, connection strings) | LOW | Output droplet IPs, VPN endpoint, Odoo URL, SSH connection commands |

#### Compute and Networking

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| DigitalOcean VPC with private networking | Network isolation between droplets; PCI-DSS network segmentation requirement | LOW | All droplets in same VPC; inter-droplet communication on private IPs only |
| Separate WireGuard gateway droplet | Dedicated security boundary; admin access isolated from app workload | MEDIUM | Smallest droplet sufficient (1 vCPU/1GB); only public-facing management endpoint |
| Odoo/PostgreSQL host droplet | Right-sized for 10 users; room for moderate growth | LOW | 2 vCPU / 4GB RAM minimum; 4 vCPU / 8GB for comfortable headroom |
| DigitalOcean Block Storage volumes | Persistent data survives droplet destruction; independent scaling of storage | LOW | Separate volumes for PostgreSQL data and Odoo filestore; ext4 formatted |
| DigitalOcean Cloud Firewalls | Network-level access control; defense-in-depth with host UFW | LOW | Allow HTTPS (443) from anywhere, SSH (22) from VPN only, Icinga2 (5665) from master only |

#### System Hardening (PCI-DSS Baseline)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| SSH hardening | PCI-DSS 2.2.x: disable root login, password auth; key-only, non-standard port | LOW | Ed25519 keys, MaxAuthTries 3, AllowUsers directive, idle timeout 300s |
| UFW firewall with default-deny | PCI-DSS 1.x: deny all inbound by default, allow only required ports | LOW | Allow: 443 (HTTPS), 51820 (WireGuard on gateway), 5665 (Icinga2 agent); deny rest |
| fail2ban with aggressive policies | PCI-DSS 8.1.6: lockout after failed attempts; brute-force protection | LOW | SSH jail, Odoo web login jail (custom filter on Odoo logs), recidive jail |
| Automatic security updates | PCI-DSS 6.2: timely patching of security vulnerabilities | LOW | unattended-upgrades for security patches; reboot notification via monitoring |
| Kernel hardening (sysctl) | PCI-DSS 2.2: harden system against common attacks | LOW | Disable IP forwarding (except WireGuard), SYN flood protection, ICMP redirect blocking |
| File permission hardening | PCI-DSS 7.x: restrict access to system files | LOW | Restrict cron, at; secure /tmp mount; remove unnecessary SUID binaries |
| Audit logging | PCI-DSS 10.x: record access to sensitive data and system events | MEDIUM | auditd rules for file access, privilege escalation, authentication events |

#### Docker and Container Security

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Docker Compose with separate Odoo and PostgreSQL services | Independent lifecycle management; the whole point of containerization | LOW | docker-compose.yml with version pinning, named volumes, restart policies |
| Non-root container users | PCI-DSS 2.2: minimize privilege; Docker security best practice | LOW | Odoo official image runs as odoo user (UID 101); verify PostgreSQL runs as postgres |
| Container resource limits | Prevent resource exhaustion; predictable performance | LOW | Memory limits, CPU limits, pids limit in Compose; right-sized for 10 users |
| Docker network isolation | PCI-DSS 1.x: network segmentation between containers and host | LOW | Custom bridge network for Odoo-PostgreSQL; no unnecessary port exposure to host |
| Container health checks | Operational reliability; auto-restart on failure | LOW | HTTP health check for Odoo, pg_isready for PostgreSQL; compose healthcheck directive |
| Docker daemon hardening | PCI-DSS 2.2: secure the container runtime itself | MEDIUM | daemon.json: userns-remap, live-restore, no-new-privileges, log rotation, icc=false |
| Read-only root filesystem where possible | Minimize container attack surface | LOW | Odoo needs write to filestore/sessions; PostgreSQL needs write to data dir; tmpfs for /tmp |
| Docker secrets or env file for credentials | PCI-DSS 3.x: protect stored credentials | LOW | .env file with restricted permissions (600); never commit to git; document required vars |

#### Reverse Proxy and TLS

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Nginx reverse proxy | Standard production pattern; TLS termination, request buffering, security headers | MEDIUM | Containerized or host-level; proxy_pass to Odoo container; WebSocket support for longpolling |
| Let's Encrypt SSL/TLS with auto-renewal | PCI-DSS 4.x: encrypt data in transit; HTTPS is non-negotiable | MEDIUM | Certbot with nginx plugin or standalone; cron-based renewal; redirect HTTP to HTTPS |
| Security headers | Defense against XSS, clickjacking, MIME sniffing | LOW | HSTS, X-Content-Type-Options, X-Frame-Options, CSP, Referrer-Policy |
| Odoo longpolling/WebSocket proxy | Real-time features (chat, notifications) require separate endpoint | MEDIUM | Odoo uses gevent on port 8072 for longpolling; Nginx must route /longpolling separately |

#### WireGuard VPN

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| WireGuard server on gateway droplet | Admin access isolation; PCI-DSS network segmentation | MEDIUM | wg0 interface, UDP 51820, PostUp/PostDown iptables rules for NAT |
| Client peer configuration | Admins need to connect; generate config for each admin | LOW | Pre-generate 2-3 peer configs; distribute securely; document connection process |
| IP forwarding and NAT on gateway | Route VPN traffic to private VPC network | LOW | sysctl ip_forward=1 on gateway only; iptables MASQUERADE for VPN subnet |
| Split tunneling for admin access | Only route management traffic through VPN, not all internet | LOW | AllowedIPs = VPC CIDR only; keeps user experience clean |

#### Database Management

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| PostgreSQL container with persistent volume | Data survives container restart/recreation | LOW | Named volume mapped to DO Block Storage; regular VACUUM via cron |
| PostgreSQL performance tuning for 10 users | Right-sized config prevents performance issues | MEDIUM | shared_buffers=1GB, effective_cache_size=3GB, work_mem=64MB for 4GB RAM droplet |
| Automated PostgreSQL backups (local + offsite) | PCI-DSS 3.x + disaster recovery; data loss is unacceptable | MEDIUM | pg_dump daily to local volume + s3cmd/rclone push to DO Spaces; 30-day retention |
| Backup verification/restore testing | Backups are worthless if they cannot be restored | MEDIUM | Monthly automated restore test to temporary container; alert on failure |
| Database access restricted to Odoo container only | PCI-DSS 7.x: least privilege; no external PostgreSQL access | LOW | PostgreSQL listens on Docker network only; pg_hba.conf restricts to Odoo container IP/subnet |

#### Odoo Application Configuration

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Odoo config file with production settings | Proper database filtering, workers, logging | MEDIUM | odoo.conf: db_host, db_port, dbfilter, workers=2, max_cron_threads=1, log_level=warn |
| Odoo worker configuration for 10 users | Performance + stability; default single-process mode is not production-grade | MEDIUM | 2 workers + 1 cron thread for 10 users on 4GB; limit_memory_hard=2684354560 |
| CRM and Project modules installed | Core business functionality the deployment exists to serve | LOW | Pre-install via Odoo CLI: odoo -i crm,project --stop-after-init |
| Database manager disabled in production | Security: prevents unauthorized database creation/deletion/backup via web | LOW | list_db = False in odoo.conf; admin_passwd set to strong value or disabled |
| Odoo admin password hardened | PCI-DSS 8.x: strong authentication for admin access | LOW | Change default admin password; set master password in odoo.conf; document rotation |

#### Monitoring (Icinga2 Integration)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Icinga2 agent installed and connected to master | Connects to existing monitoring infrastructure | MEDIUM | Agent mode, TLS certificates, zone/endpoint configuration; automated via provisioner |
| Container health monitoring checks | Know when Odoo or PostgreSQL containers are down | MEDIUM | Custom check scripts: docker inspect --format for state, health status |
| System resource monitoring | CPU, memory, disk, network baseline and alerting | LOW | Standard Icinga2 plugins: check_disk, check_load, check_memory, check_swap |
| PostgreSQL-specific monitoring | Database performance visibility | MEDIUM | check_postgres or custom: connection count, replication lag, table bloat, query time |
| Docker daemon monitoring | Container runtime health | LOW | Check Docker socket responsiveness, disk usage in /var/lib/docker |
| SSL certificate expiry monitoring | Prevent service outage from expired cert | LOW | check_http with --ssl flag and certificate age threshold (30 days warning) |
| Backup success/failure monitoring | Know when backups fail before you need them | MEDIUM | Custom check: verify backup file exists, is recent (< 25 hours), and is non-zero size |

#### Documentation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Architecture diagram (ASCII or Mermaid) | Team understanding of system topology | LOW | Show: Internet -> WireGuard -> VPC -> Nginx -> Odoo -> PostgreSQL; Icinga2 agent -> master |
| Deployment runbook | Reproducible deployment steps beyond just `terraform apply` | MEDIUM | Pre-requisites, step-by-step, post-deploy verification, common troubleshooting |
| Variable reference documentation | Users need to know what to customize | LOW | Table of all Terraform variables, .env variables, config file parameters |
| Operational runbook | Day-2 operations: backup, restore, update, scale | MEDIUM | Container management, Odoo module updates, PostgreSQL maintenance, log access |

### Differentiators (Competitive Advantage)

Features that elevate this from "works in production" to "well-engineered production deployment." Not required, but significantly valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Idempotent hardening scripts | Run scripts multiple times safely; IaC principle applied to bash | MEDIUM | Check-before-modify pattern in all bash scripts; exit codes; logging |
| Container image scanning in deployment pipeline | Catch known CVEs before deploying | LOW | Trivy scan of Odoo/PostgreSQL images; fail on CRITICAL; document results |
| Log aggregation and rotation | Centralized troubleshooting; prevent disk fill from container logs | MEDIUM | Docker json-file driver with max-size/max-file; optional: ship to syslog or Loki |
| Automated Odoo session/attachment cleanup | Prevent filestore bloat over time; Odoo does not auto-clean | LOW | Cron job to clean ir_attachment orphans, old sessions; run inside Odoo container |
| Terraform plan as pre-flight check | Prevent destructive changes; review before apply | LOW | Document `terraform plan` workflow; output plan file; apply from plan |
| Infrastructure drift detection | Know when manual changes have diverged from IaC state | LOW | Scheduled `terraform plan` with alerting on drift; simple cron + notification |
| Nginx rate limiting | Protect against brute-force login attempts at proxy level | LOW | limit_req_zone for /web/login; 10 req/min with burst of 5 |
| PostgreSQL connection pooling | Better resource utilization under load | MEDIUM | PgBouncer container between Odoo and PostgreSQL; transaction pooling mode |
| Automated restore drill | Prove backups work; PCI-DSS 9.5 adjacent requirement | HIGH | Monthly: pull backup from Spaces, restore to temp container, verify Odoo starts, destroy |
| Separate Nginx container | Full container isolation; independent updates and scaling | LOW | Nginx in its own container in Compose; shares Docker network with Odoo |
| Fail2ban Odoo login jail | Detect and block brute-force Odoo login attempts (beyond SSH) | MEDIUM | Custom filter parsing Odoo log for failed login; ban after 5 attempts |
| Grafana/Prometheus monitoring stack | Rich dashboards and alerting beyond Icinga2 checks | HIGH | Overkill for 10 users but nice; Prometheus + node_exporter + postgres_exporter + Grafana |
| git-crypt or SOPS for secrets in repo | Secrets management without external service | MEDIUM | Encrypt .tfvars and .env files at rest in git; team members decrypt with GPG keys |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem valuable but create more problems than they solve for a 10-user deployment.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Kubernetes / Docker Swarm orchestration | "Container orchestration is best practice" | Massive complexity overhead for 10 users; single-host Docker Compose is perfectly adequate; K8s adds etcd, API server, kubelet, networking plugins -- all attack surface with zero scaling benefit at this scale | Docker Compose with restart policies and health checks; scale vertically first |
| Multi-environment (dev/staging/prod) in v1 | "Best practice to have staging" | Triples infrastructure cost and IaC complexity; 10-user workload does not justify; validate prod works first | Single production environment; add staging in v2 once prod is stable; use Terraform workspaces when ready |
| CI/CD pipeline for v1 | "Automate all deployments" | Premature automation; deployment frequency will be low initially; pipeline setup time exceeds manual deploy time for months | Document manual `terraform apply` + `docker compose pull && up -d` process; add CI/CD when deployment frequency justifies it |
| Horizontal Odoo scaling with load balancer | "Scale out for reliability" | 10 users = 2 Odoo workers maximum; load balancer adds TLS complexity, session stickiness requirements, and monitoring burden; vertical scaling (bigger droplet) is simpler and sufficient to 50+ users | Single Odoo container with proper worker config; vertical scale the droplet via Terraform variable change |
| Odoo Enterprise edition | "More features and support" | License cost for 10 users; Community covers CRM + Project adequately; Enterprise adds payroll, accounting, manufacturing modules not needed here | Community edition; document upgrade path if Enterprise features become needed |
| Custom Odoo module development | "Customize everything" | Scope creep; custom modules require Python development, testing, upgrade compatibility management; standard modules cover CRM + Project needs | Use built-in CRM and Project modules; customize via Odoo Studio (Enterprise) or configuration only |
| Automated Odoo version upgrades | "Stay current automatically" | Odoo major version upgrades are breaking changes requiring database migration, module compatibility testing, and potential custom code updates; auto-upgrade risks data loss | Manual, planned upgrades with backup-first approach; test on clone before production; document upgrade runbook |
| External secrets manager (Vault, AWS SSM) | "Enterprise secrets management" | HashiCorp Vault adds operational complexity (unsealing, HA, backup of Vault itself); AWS SSM pulls in non-DO dependency; 10-user deployment does not justify | .env files with restricted permissions (600), excluded from git; document secret rotation procedure; consider git-crypt for repo-stored secrets |
| Full ELK/EFK log aggregation stack | "Centralized logging is best practice" | Elasticsearch alone needs 4GB+ RAM; entire stack doubles infrastructure cost; 10-user deployment generates minimal logs | Docker log driver with rotation (json-file, max-size=10m, max-file=3); grep container logs directly; add Loki (lightweight) later if needed |
| Database replication (primary-replica) | "High availability for the database" | 10 users can tolerate minutes of downtime for restore; replication adds complexity (lag monitoring, failover, split-brain); single PostgreSQL with good backups is sufficient | Single PostgreSQL with automated daily backups to local volume + DO Spaces; documented restore procedure; RTO target: 30 minutes |
| Real-time file sync / shared storage (GlusterFS, Ceph) | "Distributed storage for containers" | Single-host deployment means local volumes are fine; distributed storage adds latency, complexity, and failure modes | DO Block Storage volumes mounted to host, bind-mounted into containers; simple, reliable, performant |

## Feature Dependencies

```
[Terraform Provider Setup]
    |-- requires --> [DO API Token + Spaces credentials]
    |
    +-->[VPC + Firewall Module]
    |       |-- requires --> [Terraform Provider]
    |       +-->[WireGuard Gateway Droplet]
    |       |       |-- requires --> [VPC + Firewall]
    |       |       +-->[WireGuard Configuration]
    |       |               |-- requires --> [Gateway Droplet provisioned]
    |       |               +-->[Client Peer Configs]
    |       |
    |       +-->[Odoo Host Droplet + Volumes]
    |               |-- requires --> [VPC + Firewall]
    |               +-->[System Hardening]
    |               |       |-- requires --> [Droplet provisioned]
    |               |       +-->[SSH Hardening]
    |               |       +-->[UFW Firewall Rules]
    |               |       +-->[fail2ban]
    |               |       +-->[Kernel Hardening]
    |               |       +-->[Audit Logging]
    |               |
    |               +-->[Docker Installation + Hardening]
    |                       |-- requires --> [System Hardening complete]
    |                       +-->[Docker Compose Deployment]
    |                               |-- requires --> [Docker installed]
    |                               +-->[PostgreSQL Container]
    |                               |       +-->[DB Performance Tuning]
    |                               |       +-->[Backup Automation]
    |                               |
    |                               +-->[Odoo Container]
    |                               |       |-- requires --> [PostgreSQL running]
    |                               |       +-->[Odoo Config + Modules]
    |                               |       +-->[Worker Tuning]
    |                               |
    |                               +-->[Nginx Container]
    |                                       |-- requires --> [Odoo running]
    |                                       +-->[Let's Encrypt TLS]
    |                                       +-->[Security Headers]
    |                                       +-->[Longpolling Proxy]

[Icinga2 Agent Setup]
    |-- requires --> [Droplet provisioned + hardened]
    |-- requires --> [Existing Icinga2 master (external)]
    +-->[Custom Check Scripts]
            +-->[Container Health Checks]  (requires Docker running)
            +-->[PostgreSQL Checks]        (requires PostgreSQL running)
            +-->[Backup Monitoring]        (requires Backup automation)
            +-->[SSL Cert Monitoring]      (requires Let's Encrypt)
```

### Dependency Notes

- **Odoo container requires PostgreSQL container:** Odoo cannot start without a database connection; PostgreSQL must be healthy first (use depends_on with healthcheck condition)
- **Nginx requires Odoo:** Reverse proxy has nothing to proxy without Odoo running; use depends_on
- **Let's Encrypt requires DNS pointing to droplet:** TLS cert provisioning needs the domain resolving to the Nginx host; Terraform can output the IP but DNS is likely manual
- **WireGuard is independent of Odoo stack:** Can be provisioned in parallel with app host; only dependency is VPC being created first
- **Icinga2 agent requires master coordination:** Agent certificate signing or ticket-based registration requires access to the existing Icinga2 master; this is a manual/external dependency
- **System hardening must precede Docker installation:** Hardening scripts configure UFW and kernel params that affect Docker networking; order matters to avoid lockouts
- **Backup monitoring requires backup automation:** Cannot monitor backup success without the backup cron job existing first

## MVP Definition

### Launch With (v1)

Minimum viable production deployment -- what is needed to run Odoo securely for 10 users.

- [ ] **Terraform IaC for all DO resources** -- Core value proposition; reproducible infrastructure
- [ ] **VPC + Cloud Firewall** -- Network-level isolation; PCI-DSS requirement
- [ ] **WireGuard gateway droplet** -- Admin access isolation; PCI-DSS network segmentation
- [ ] **Odoo host droplet with block storage** -- Compute and persistent storage
- [ ] **Full system hardening** (SSH, UFW, fail2ban, kernel, auto-updates) -- PCI-DSS baseline
- [ ] **Docker + Docker Compose with hardened daemon** -- Container runtime
- [ ] **PostgreSQL container with tuned config** -- Database layer
- [ ] **Odoo container with CRM + Project modules** -- Application layer
- [ ] **Nginx reverse proxy with Let's Encrypt** -- Public HTTPS access
- [ ] **Automated PostgreSQL backups** (local + DO Spaces) -- Disaster recovery
- [ ] **Icinga2 agent with core monitoring checks** -- Operational visibility
- [ ] **Deployment documentation** -- Runbook for initial deploy and verification

### Add After Validation (v1.x)

Features to add once the core deployment is running and validated.

- [ ] **Container image scanning** -- Add when establishing update cadence
- [ ] **Fail2ban Odoo login jail** -- Add after observing login attempt patterns in logs
- [ ] **Nginx rate limiting** -- Add after baseline traffic patterns are understood
- [ ] **Backup restore drill automation** -- Add once manual restore has been verified at least once
- [ ] **Infrastructure drift detection** -- Add once team is comfortable with Terraform workflow
- [ ] **Log rotation optimization** -- Add after observing actual log volume for 2-4 weeks
- [ ] **Automated filestore cleanup** -- Add after observing filestore growth rate
- [ ] **git-crypt for secrets** -- Add when more team members need repo access

### Future Consideration (v2+)

Features to defer until the deployment has proven stable and requirements grow.

- [ ] **CI/CD pipeline** -- Defer until deployment frequency exceeds monthly
- [ ] **Staging environment** -- Defer until team wants to test changes before production
- [ ] **PgBouncer connection pooling** -- Defer until connection count exceeds PostgreSQL limits (unlikely at 10 users)
- [ ] **Prometheus/Grafana monitoring** -- Defer unless Icinga2 proves insufficient for visibility needs
- [ ] **Database replication** -- Defer until RTO requirements tighten below 30 minutes
- [ ] **Horizontal scaling** -- Defer until user count exceeds 50+

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Terraform IaC (all resources) | HIGH | MEDIUM | P1 |
| VPC + Cloud Firewall | HIGH | LOW | P1 |
| WireGuard gateway + VPN config | HIGH | MEDIUM | P1 |
| System hardening (SSH, UFW, fail2ban, kernel) | HIGH | MEDIUM | P1 |
| Docker + daemon hardening | HIGH | LOW | P1 |
| PostgreSQL container + tuning | HIGH | MEDIUM | P1 |
| Odoo container + CRM/Project modules | HIGH | MEDIUM | P1 |
| Nginx + Let's Encrypt TLS | HIGH | MEDIUM | P1 |
| Automated backups (local + Spaces) | HIGH | MEDIUM | P1 |
| Icinga2 agent + core checks | HIGH | MEDIUM | P1 |
| Deployment documentation | HIGH | MEDIUM | P1 |
| Container health checks | MEDIUM | LOW | P1 |
| Odoo worker tuning | MEDIUM | LOW | P1 |
| Database manager disabled | MEDIUM | LOW | P1 |
| Security headers (Nginx) | MEDIUM | LOW | P1 |
| Audit logging (auditd) | MEDIUM | MEDIUM | P1 |
| Longpolling/WebSocket proxy | MEDIUM | LOW | P1 |
| Container image scanning | MEDIUM | LOW | P2 |
| Fail2ban Odoo login jail | MEDIUM | MEDIUM | P2 |
| Nginx rate limiting | MEDIUM | LOW | P2 |
| Backup restore drill | HIGH | HIGH | P2 |
| Drift detection | LOW | LOW | P2 |
| Log aggregation/rotation | MEDIUM | MEDIUM | P2 |
| Filestore cleanup cron | LOW | LOW | P2 |
| Secrets management (git-crypt) | LOW | MEDIUM | P2 |
| CI/CD pipeline | LOW | HIGH | P3 |
| Staging environment | LOW | HIGH | P3 |
| PgBouncer | LOW | MEDIUM | P3 |
| Prometheus/Grafana | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch -- deployment is not production-ready without it
- P2: Should have, add in v1.x once core is validated
- P3: Nice to have, future consideration for v2+

## Competitor Feature Analysis

Comparison of deployment approaches for Odoo in production.

| Feature | Odoo.sh (Official SaaS) | Manual VPS Deploy | This Project (IaC + Docker) |
|---------|--------------------------|-------------------|----------------------------|
| Reproducible infrastructure | N/A (managed) | No -- manual setup, undocumented drift | Yes -- Terraform + scripts, git-tracked |
| Container isolation | Yes (managed) | No -- Odoo installed directly on host | Yes -- Docker Compose with network isolation |
| PCI-DSS hardening | Partial (Odoo handles some) | Manual, often incomplete | Comprehensive -- scripted, auditable, documented |
| VPN isolation for admin | Not available | Optional, usually not done | Built-in -- dedicated WireGuard gateway |
| Monitoring integration | Built-in (basic) | Manual, often skipped | Icinga2 agent with custom container checks |
| Backup automation | Built-in | Manual pg_dump cron at best | Automated local + offsite with monitoring |
| Cost (10 users) | ~$200-400/mo (Odoo.sh) | ~$24-48/mo (DO droplets) | ~$36-72/mo (DO droplets + gateway + storage) |
| Maintenance burden | Zero (managed) | High (unscripted, ad-hoc) | Low-medium (IaC + documented runbooks) |
| Customization control | Limited | Full but fragile | Full and reproducible |
| Disaster recovery | Managed by Odoo | Manual, often untested | Documented, automated, testable |

## Sources

- Project requirements from `.planning/PROJECT.md` and `artifacts/Initial_Prompt.md` (HIGH confidence -- primary source)
- Odoo official Docker image documentation on Docker Hub (MEDIUM confidence -- based on training data, not live-verified)
- Odoo 18.0 deployment documentation patterns (MEDIUM confidence -- based on training data for Odoo deployment best practices)
- PCI-DSS v4.0 requirements mapping (MEDIUM confidence -- based on training data for PCI-DSS controls)
- Docker security best practices from Docker documentation (MEDIUM confidence -- well-established patterns)
- WireGuard deployment patterns (HIGH confidence -- well-established, stable protocol)
- Icinga2 agent configuration patterns (MEDIUM confidence -- based on training data)
- DigitalOcean Terraform provider documentation (MEDIUM confidence -- based on training data)

**Note:** WebSearch and WebFetch were unavailable during this research. All findings are based on training data and project context documents. Confidence is capped at MEDIUM for claims that could not be verified against live documentation. Key areas to verify during implementation:
- Odoo 19.x Docker image availability and configuration (19.x may not be released yet; may need to use 18.0)
- Current PostgreSQL version compatibility with latest Odoo
- DigitalOcean Terraform provider latest version and any API changes
- Icinga2 agent registration workflow with existing master

---
*Feature research for: Production containerized Odoo deployment on DigitalOcean*
*Researched: 2026-02-20*
