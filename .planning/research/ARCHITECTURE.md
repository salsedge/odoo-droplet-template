# Architecture Research

**Domain:** Containerized Odoo ERP deployment on DigitalOcean with IaC, VPN, and monitoring
**Researched:** 2026-02-20
**Confidence:** MEDIUM (based on well-established patterns for mature technologies; web verification unavailable so relying on training data for a domain where patterns are stable)

## Standard Architecture

### System Overview

```
                          INTERNET
                             |
                             | HTTPS (443)
                             v
┌────────────────────────────────────────────────────────────────────┐
│                    DigitalOcean VPC (10.10.0.0/16)                 │
│                                                                    │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐  │
│  │  WireGuard Gateway       │    │  Odoo Application Server     │  │
│  │  Droplet (10.10.1.1)     │    │  Droplet (10.10.1.2)         │  │
│  │                          │    │                              │  │
│  │  ┌────────────────────┐  │    │  ┌────────────────────────┐  │  │
│  │  │ WireGuard (wg0)    │  │    │  │ Nginx Reverse Proxy    │  │  │
│  │  │ UDP 51820 (public) │  │    │  │ (container)            │  │  │
│  │  │ VPN: 10.8.0.0/24   │──┼────┼─>│ :80 / :443             │  │  │
│  │  └────────────────────┘  │    │  └──────────┬─────────────┘  │  │
│  │                          │    │             │ proxy_pass :8069│  │
│  │  ┌────────────────────┐  │    │  ┌──────────v─────────────┐  │  │
│  │  │ UFW + fail2ban     │  │    │  │ Odoo 18 Community      │  │  │
│  │  │ SSH hardening      │  │    │  │ (container)            │  │  │
│  │  │ PCI-DSS baseline   │  │    │  │ :8069 (HTTP)           │  │  │
│  │  └────────────────────┘  │    │  │ :8072 (longpolling)    │  │  │
│  │                          │    │  └──────────┬─────────────┘  │  │
│  │  Admin SSH via VPN only  │    │             │                │  │
│  └──────────────────────────┘    │  ┌──────────v─────────────┐  │  │
│                                  │  │ PostgreSQL 16          │  │  │
│                                  │  │ (container)            │  │  │
│                                  │  │ :5432 (internal only)  │  │  │
│                                  │  └──────────┬─────────────┘  │  │
│                                  │             │                │  │
│                                  │  ┌──────────v─────────────┐  │  │
│                                  │  │ DO Volume (ext4)       │  │  │
│                                  │  │ /mnt/data              │  │  │
│                                  │  │ - pg_data/             │  │  │
│                                  │  │ - odoo_filestore/      │  │  │
│                                  │  │ - backups/             │  │  │
│                                  │  └────────────────────────┘  │  │
│                                  │                              │  │
│                                  │  ┌────────────────────────┐  │  │
│                                  │  │ Icinga2 Agent          │  │  │
│                                  │  │ (host-level daemon)    │  │  │
│                                  │  │ -> Icinga2 Master      │  │  │
│                                  │  └────────────────────────┘  │  │
│                                  │                              │  │
│                                  │  UFW + fail2ban + PCI-DSS   │  │
│                                  └──────────────────────────────┘  │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  DO Spaces (S3-compatible)                                   │  │
│  │  - Terraform remote state                                    │  │
│  │  - PostgreSQL backup offsite (disaster recovery)             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  DO Cloud Firewall (Terraform-managed)                       │  │
│  │  - WG Droplet: allow 51820/UDP, 443/TCP from anywhere       │  │
│  │  - Odoo Droplet: allow 443/TCP from anywhere,               │  │
│  │    SSH only from VPC + VPN CIDR                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘

         EXTERNAL
  ┌─────────────────────┐
  │ Icinga2 Master      │
  │ (pre-existing)      │
  │ Receives agent      │
  │ check results       │
  └─────────────────────┘
```

### Two-Droplet vs Single-Droplet Decision

The architecture uses **two droplets** (WireGuard gateway + Odoo application server). This is the correct choice for this project because:

1. **Security boundary isolation** -- the VPN gateway has a fundamentally different threat model (internet-facing tunnel endpoint) than the application server (business logic + database). Mixing them means a VPN exploit gives direct database access.
2. **Independent patching** -- WireGuard kernel module updates and reboots do not take down the Odoo application.
3. **Firewall simplicity** -- the Odoo droplet never needs to expose SSH to the public internet. All management access routes through the VPN.
4. **Cost is minimal** -- a WireGuard gateway needs only a $6/month droplet (1 vCPU, 1 GB RAM). The overhead is negligible.

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **Terraform** | Provision all DO resources (droplets, VPC, firewalls, volumes, Spaces, DNS) | HCL files organized in modules, remote state in DO Spaces |
| **WireGuard Gateway Droplet** | VPN tunnel endpoint, routes admin traffic to app server, optional NAT for Odoo outbound | Ubuntu 24.04, WireGuard kernel module, UFW, fail2ban |
| **Nginx Reverse Proxy** | TLS termination, HTTP-to-Odoo proxying, static file serving, rate limiting | Docker container (nginx:alpine), Let's Encrypt via certbot sidecar or host-level certbot |
| **Odoo Application** | ERP business logic, CRM module, Project Management module, web interface | Docker container (official odoo:18 image or custom build) |
| **PostgreSQL** | Persistent data storage for Odoo, all business data | Docker container (postgres:16-alpine), data on DO Volume |
| **DO Volume** | Persistent block storage for database data, Odoo filestore, local backups | ext4-formatted, mounted at /mnt/data on Odoo droplet |
| **DO Spaces** | Remote backup destination, Terraform state backend | S3-compatible object storage |
| **DO Cloud Firewall** | Network-level access control at the hypervisor level (before packets reach the droplet) | Terraform-managed `digitalocean_firewall` resources |
| **DO VPC** | Private network isolation between droplets | 10.10.0.0/16 subnet, all droplets placed in same VPC |
| **Icinga2 Agent** | Send monitoring data to existing Icinga2 master, execute local check plugins | Host-level daemon on Odoo droplet, custom check scripts for Docker/PG |
| **Hardening Scripts** | PCI-DSS baseline: UFW rules, SSH config, fail2ban, kernel params, auto-updates | Bash scripts executed by Terraform remote-exec provisioners |

## Recommended Project Structure

```
odoo-19.x-build/
├── terraform/
│   ├── main.tf                  # Root module: provider, backend, module calls
│   ├── variables.tf             # Input variables (droplet sizes, regions, SSH keys)
│   ├── outputs.tf               # Droplet IPs, VPN endpoint, connection info
│   ├── terraform.tfvars.example # Example variable values (committed)
│   ├── terraform.tfvars         # Actual values (gitignored)
│   ├── backend.tf               # DO Spaces remote state config
│   ├── versions.tf              # Required providers and version constraints
│   │
│   ├── modules/
│   │   ├── networking/          # VPC, firewall rules, DNS records
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── wireguard/           # WireGuard gateway droplet + provisioning
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── templates/       # WireGuard config templates
│   │   ├── odoo-server/         # Odoo app droplet, volume, provisioning
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── templates/       # Docker Compose, Odoo config templates
│   │   └── backup/              # DO Spaces bucket for backups + state
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   └── scripts/                 # Provisioning scripts (run via remote-exec)
│       ├── base-harden.sh       # PCI-DSS hardening (UFW, fail2ban, SSH, kernel)
│       ├── install-docker.sh    # Docker CE + Compose plugin installation
│       ├── setup-wireguard.sh   # WireGuard server configuration
│       ├── deploy-odoo.sh       # Docker Compose up, initial Odoo setup
│       ├── setup-icinga2.sh     # Icinga2 agent install + certificate registration
│       └── setup-backups.sh     # Cron jobs for pg_dump + s3cmd to Spaces
│
├── docker/
│   ├── docker-compose.yml       # Production Compose file (Nginx + Odoo + PostgreSQL)
│   ├── docker-compose.override.yml.example  # Dev overrides template
│   ├── .env.example             # Environment variables template
│   ├── .env                     # Actual env vars (gitignored)
│   │
│   ├── nginx/
│   │   ├── nginx.conf           # Main Nginx config
│   │   ├── conf.d/
│   │   │   └── odoo.conf        # Odoo upstream + server block
│   │   └── ssl/                 # Let's Encrypt certs (mounted volume, gitignored)
│   │
│   ├── odoo/
│   │   ├── Dockerfile           # Custom Odoo image (non-root, extra modules if needed)
│   │   ├── odoo.conf            # Odoo server configuration
│   │   └── addons/              # Custom/third-party addons (if any)
│   │
│   └── postgres/
│       ├── postgresql.conf      # Tuned PostgreSQL config for 10-user workload
│       └── init/                # SQL initialization scripts (run on first start)
│
├── monitoring/
│   ├── icinga2/
│   │   ├── agent-setup.conf     # Icinga2 agent zones.conf template
│   │   └── check_scripts/       # Custom Nagios-compatible check plugins
│   │       ├── check_docker_container.sh
│   │       ├── check_postgres_container.sh
│   │       ├── check_odoo_health.sh
│   │       ├── check_docker_daemon.sh
│   │       ├── check_backup_age.sh
│   │       └── check_wireguard.sh
│   └── icinga2-master/
│       └── service_definitions/  # Host/service objects to add to master
│           └── odoo-server.conf
│
├── scripts/
│   ├── backup-postgres.sh       # pg_dump wrapper with rotation
│   ├── restore-postgres.sh      # Restore from backup
│   ├── rotate-secrets.sh        # Rotate DB passwords, Odoo admin password
│   └── update-containers.sh     # Pull new images, recreate with zero-downtime
│
├── docs/                        # Documentation
│   └── ...
│
├── artifacts/                   # Project planning artifacts
│   └── Initial_Prompt.md
│
└── .planning/                   # GSD planning files
    ├── PROJECT.md
    └── research/
        └── ARCHITECTURE.md      # This file
```

### Structure Rationale

- **terraform/** -- All IaC in one top-level directory. Modules subdivide by concern (networking, wireguard, odoo-server, backup). Scripts live alongside Terraform because they are executed by Terraform provisioners.
- **docker/** -- Everything Docker Compose needs to bring up the application stack. This directory gets synced to the Odoo droplet. Separating Nginx, Odoo, and PostgreSQL configs into subdirectories keeps them independently manageable.
- **monitoring/** -- Icinga2 agent config and custom check scripts. Separate from docker/ because Icinga2 runs on the host, not in a container. The master service definitions subdirectory contains objects the operator manually adds to their existing Icinga2 master.
- **scripts/** -- Operational scripts for day-2 tasks (backup, restore, secrets rotation, updates). Separate from terraform/scripts/ which are provisioning-time only.

## Architectural Patterns

### Pattern 1: Terraform Modules with Remote-Exec Provisioners

**What:** Terraform provisions DigitalOcean resources (droplets, VPC, firewalls, volumes) and then uses `remote-exec` provisioners to run shell scripts that configure the OS and deploy containers. Configuration files are uploaded via `file` provisioners using `templatefile()` for variable interpolation.

**When to use:** Small-to-medium deployments where a full configuration management tool (Ansible, Chef) is overkill. The 2-droplet scope of this project fits perfectly.

**Trade-offs:**
- Pro: Single tool (Terraform) manages everything. No Ansible inventory to maintain.
- Pro: Scripts are idempotent bash -- easy to understand, test, and debug.
- Con: Terraform provisioners are a "last resort" per HashiCorp -- they run only on create, not on subsequent applies. Changes to scripts require `terraform taint` + re-apply or manual SSH.
- Con: No convergence model -- if a script partially fails, Terraform marks the resource as tainted.

**Mitigation for cons:** Keep provisioner scripts short and idempotent. For configuration changes post-initial-deploy, use SSH + script execution directly. Accept that Terraform handles Day 0 provisioning, and Day 2 operations are script-based.

**Example:**
```hcl
resource "digitalocean_droplet" "odoo" {
  name     = "odoo-production"
  image    = "ubuntu-24-04-x64"
  size     = "s-2vcpu-4gb"
  region   = var.region
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [digitalocean_ssh_key.deploy.fingerprint]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    host        = self.ipv4_address
  }

  provisioner "file" {
    source      = "${path.module}/scripts/"
    destination = "/tmp/provision/"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/provision/*.sh",
      "/tmp/provision/base-harden.sh",
      "/tmp/provision/install-docker.sh",
    ]
  }
}
```

### Pattern 2: Docker Compose with Named Networks and Explicit Service Dependencies

**What:** Use a single `docker-compose.yml` defining three services (nginx, odoo, postgres) on a shared Docker bridge network. PostgreSQL is not exposed to the host -- only Odoo can reach it. Nginx is the only service binding to host ports (80/443).

**When to use:** Always for this project. Docker Compose is the right abstraction for a single-host multi-container deployment.

**Trade-offs:**
- Pro: Simple, well-understood, declarative.
- Pro: `depends_on` with health checks ensures proper startup order.
- Con: Single-host only. No built-in failover. Acceptable for 10-user workload.

**Example:**
```yaml
version: "3.8"

services:
  nginx:
    image: nginx:1.27-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - certbot-webroot:/var/www/certbot:ro
      - certbot-certs:/etc/letsencrypt:ro
    depends_on:
      odoo:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - frontend

  odoo:
    build:
      context: ./odoo
      dockerfile: Dockerfile
    environment:
      - HOST=postgres
      - PORT=5432
      - USER=${POSTGRES_USER}
      - PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - odoo-filestore:/var/lib/odoo/filestore
      - ./odoo/odoo.conf:/etc/odoo/odoo.conf:ro
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "1.5"
    user: "odoo"
    networks:
      - frontend
      - backend

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - pg-data:/var/lib/postgresql/data
      - ./postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
    command: ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: "1.0"
    networks:
      - backend

volumes:
  pg-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data/pg_data
  odoo-filestore:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data/odoo_filestore
  certbot-webroot:
  certbot-certs:

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true    # No external access -- postgres isolated
```

### Pattern 3: Dual-Network Isolation (Frontend/Backend)

**What:** Docker Compose defines two networks: `frontend` (Nginx + Odoo) and `backend` (Odoo + PostgreSQL, marked `internal: true`). Nginx cannot reach PostgreSQL directly. PostgreSQL has no route to the internet.

**When to use:** Any deployment with a database container. This is a fundamental security pattern.

**Trade-offs:**
- Pro: Defense in depth -- even if Nginx is compromised, the attacker cannot directly reach PostgreSQL.
- Pro: PostgreSQL container has no outbound internet access (cannot exfiltrate data directly).
- Con: Slightly more complex Compose file. Worth it for security.

### Pattern 4: Host-Level Icinga2 Agent (Not Containerized)

**What:** Install Icinga2 agent directly on the Odoo droplet host OS, not in a container. The agent connects to the existing Icinga2 master via TLS. Custom check scripts run on the host where they have access to `docker` CLI, system metrics, and can inspect container health directly.

**When to use:** Always when monitoring Docker containers. A containerized monitoring agent has limited visibility into sibling containers and the host.

**Trade-offs:**
- Pro: Full visibility -- can run `docker inspect`, `docker stats`, check systemd services, read host logs.
- Pro: Survives container failures -- if Docker daemon crashes, the Icinga2 agent can still report the failure.
- Con: One non-containerized service to manage. Acceptable because Icinga2 is infrastructure, not application.

### Pattern 5: Volume-Backed Persistent Storage on DO Volumes

**What:** Mount a DigitalOcean Block Storage Volume to the Odoo droplet at `/mnt/data`. Bind-mount subdirectories into Docker containers for PostgreSQL data, Odoo filestore, and local backups. The DO Volume is a separate Terraform resource that survives droplet destruction.

**When to use:** Always for production data. Never rely on the droplet's root filesystem for persistent data.

**Trade-offs:**
- Pro: Data survives `terraform destroy` + `terraform apply` cycles (if volume is preserved).
- Pro: Can be resized independently of the droplet.
- Pro: Can be snapshotted via DO API for point-in-time recovery.
- Con: DO Volumes can only attach to one droplet at a time (no shared storage). Fine for this single-host architecture.

## Data Flow

### User Request Flow (Public HTTPS)

```
User Browser
    |
    | HTTPS request (port 443)
    v
DO Cloud Firewall -----> Allow 443/TCP from 0.0.0.0/0
    |
    v
Odoo Droplet Host
    |
    | Port mapping: host 443 -> container nginx:443
    v
Nginx Container (frontend network)
    |
    | TLS termination (Let's Encrypt cert)
    | proxy_pass http://odoo:8069
    | (longpolling: proxy_pass http://odoo:8072)
    v
Odoo Container (frontend + backend networks)
    |
    | PostgreSQL wire protocol (port 5432)
    | Connection string: host=postgres user=odoo dbname=odoo
    v
PostgreSQL Container (backend network only)
    |
    | Read/write to data directory
    v
DO Volume (/mnt/data/pg_data -> /var/lib/postgresql/data)
```

### Admin/Management Access Flow (VPN)

```
Admin Workstation
    |
    | WireGuard tunnel (UDP 51820 to WG droplet public IP)
    v
WireGuard Gateway Droplet
    |
    | IP forwarding enabled, iptables MASQUERADE
    | VPN client gets 10.8.0.x address
    | Routes 10.10.0.0/16 (VPC) via VPN tunnel
    v
VPC Private Network (10.10.0.0/16)
    |
    | SSH (port 22) to Odoo droplet private IP (10.10.1.2)
    | Or direct HTTPS to Odoo droplet for admin panel
    v
Odoo Droplet
    |
    | docker compose exec, logs, etc.
    v
Application containers
```

### Backup Flow

```
Cron job (daily, on Odoo droplet host)
    |
    | docker exec postgres pg_dump -Fc odoo > /mnt/data/backups/odoo_YYYYMMDD.dump
    v
Local backup on DO Volume (/mnt/data/backups/)
    |
    | s3cmd put to DO Spaces (encrypted at rest)
    v
DO Spaces (offsite disaster recovery)
    |
    | Retention policy: 7 daily, 4 weekly, 3 monthly
    v
Old backups pruned automatically
```

### Monitoring Flow

```
Icinga2 Agent (Odoo droplet host)
    |
    | Executes check plugins on schedule:
    |   - check_docker_container (odoo, postgres, nginx)
    |   - check_postgres_container (connections, replication lag, size)
    |   - check_odoo_health (HTTP health endpoint)
    |   - check_docker_daemon (docker info, disk usage)
    |   - check_backup_age (last backup timestamp)
    |   - Standard checks (disk, CPU, memory, load)
    |
    | TLS-encrypted check results via Icinga2 API (port 5665)
    v
Icinga2 Master (existing, external)
    |
    | Stores check results, evaluates thresholds
    | Sends notifications (email, Slack, etc.)
    v
Ops team alerted
```

### Terraform Provisioning Flow

```
Developer workstation
    |
    | terraform init (fetches DO provider, configures Spaces backend)
    | terraform plan (shows what will be created)
    | terraform apply (provisions resources)
    v
DigitalOcean API
    |
    | Creates: VPC, SSH key, firewall rules
    | Creates: WireGuard droplet (s-1vcpu-1gb)
    | Creates: Odoo droplet (s-2vcpu-4gb)
    | Creates: Block storage volume (50GB)
    | Creates: Spaces bucket (backups)
    v
Droplets boot with Ubuntu 24.04
    |
    | Terraform remote-exec provisioners SSH in as root
    | Upload scripts + config files
    | Execute: base-harden.sh -> install-docker.sh -> deploy-odoo.sh
    v
Odoo stack running
    |
    | Separate provisioner on WG droplet: setup-wireguard.sh
    | Separate provisioner on Odoo droplet: setup-icinga2.sh
    v
Full stack operational
```

## Key Data Flows

1. **User traffic:** Browser -> DO Firewall -> Nginx (TLS) -> Odoo -> PostgreSQL -> DO Volume. All within VPC except the initial internet hop.
2. **Admin traffic:** Workstation -> WireGuard tunnel -> VPC -> Odoo droplet SSH. Never touches the public internet after the VPN handshake.
3. **Monitoring data:** Icinga2 agent -> Icinga2 master (TLS on port 5665). Agent initiates connection outbound. Master never needs to reach into the VPC.
4. **Backup data:** PostgreSQL -> local dump -> DO Spaces. Two-tier: fast local restore + offsite DR.
5. **IaC state:** Terraform -> DO Spaces (encrypted remote state). Enables collaboration and prevents state loss.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-10 users (current target) | Single Odoo droplet (s-2vcpu-4gb), single PostgreSQL container. Odoo in prefork mode with 2 workers + 1 cron worker. PostgreSQL tuned for 4GB RAM host (shared_buffers=1GB, effective_cache_size=2GB). This architecture as designed. |
| 10-50 users | Vertical scale: upgrade to s-4vcpu-8gb droplet. Increase Odoo workers to 4-6. Increase PostgreSQL shared_buffers to 2GB. Add PgBouncer container for connection pooling. No architectural change needed. |
| 50-200 users | Separate PostgreSQL to its own droplet (Terraform module change). Add Managed Database (DO offers this) to offload DB operations. Odoo still single-instance with more workers. Add Redis container for session storage. |
| 200+ users | Beyond scope. Would need load balancer + multiple Odoo droplets, managed database, shared filestore (DO Spaces or NFS). Fundamentally different architecture -- not a minor change. |

### Scaling Priorities

1. **First bottleneck: Odoo worker count.** Odoo's prefork model requires `(2 * CPU_cores) + 1` workers. A 2-vCPU droplet supports ~5 workers. Each worker handles one request at a time. At 10 users this is fine. At 30+ concurrent users, upgrade the droplet.
2. **Second bottleneck: PostgreSQL memory.** PostgreSQL performance is dominated by `shared_buffers` and `effective_cache_size`. With 4GB total RAM (shared with Odoo), PostgreSQL gets ~1GB shared_buffers. This is comfortable for a 10-user CRM workload but will strain with heavy reporting queries.
3. **Third bottleneck: Disk I/O.** DO Block Storage Volumes are network-attached and have higher latency than local NVMe. For a 10-user workload this is not a concern, but at scale, PostgreSQL IOPS become a factor.

## Anti-Patterns

### Anti-Pattern 1: Running PostgreSQL on the Droplet Root Filesystem

**What people do:** Skip the DO Volume and let PostgreSQL store data in a Docker named volume on the droplet's root disk.
**Why it's wrong:** If the droplet is destroyed (intentionally via Terraform or accidentally), all data is lost. Root disks are ephemeral in infrastructure-as-code workflows. Additionally, root disk IOPS are shared with the OS.
**Do this instead:** Always use a DO Block Storage Volume. Mount it at `/mnt/data`. Bind-mount subdirectories into containers. The volume is a separate Terraform resource that can outlive the droplet.

### Anti-Pattern 2: Exposing PostgreSQL to the Host Network

**What people do:** Map PostgreSQL port 5432 to the host (`ports: "5432:5432"`) for "easy debugging."
**Why it's wrong:** Exposes the database to the VPC network and potentially the internet if firewall rules are misconfigured. Violates PCI-DSS requirement for network segmentation.
**Do this instead:** Use Docker's `internal: true` backend network. PostgreSQL should only be reachable by the Odoo container via Docker DNS (`postgres:5432`). For debugging, use `docker exec -it postgres psql`.

### Anti-Pattern 3: Single Docker Network for All Services

**What people do:** Put Nginx, Odoo, and PostgreSQL all on one Docker bridge network.
**Why it's wrong:** Nginx can directly connect to PostgreSQL. If Nginx is compromised (e.g., via an HTTP vulnerability), the attacker has a direct path to the database. No defense in depth.
**Do this instead:** Two networks -- `frontend` (Nginx <-> Odoo) and `backend` (Odoo <-> PostgreSQL, internal). Odoo bridges both networks.

### Anti-Pattern 4: Certbot as a Separate Long-Running Container

**What people do:** Run a persistent certbot container alongside Nginx that handles certificate renewal via a cron-like mechanism inside the container.
**Why it's wrong:** Adds complexity, and the certbot container must be carefully orchestrated with Nginx to reload certs. Container restarts can lose the cron schedule.
**Do this instead:** Run certbot on the host via a systemd timer or cron job. Mount the `/etc/letsencrypt` directory into the Nginx container as a read-only volume. Use `docker exec nginx nginx -s reload` in the renewal hook. Simpler, more reliable, easier to debug.

### Anti-Pattern 5: Putting Icinga2 Agent in a Docker Container

**What people do:** Containerize the Icinga2 agent to "keep everything in Docker."
**Why it's wrong:** A containerized monitoring agent cannot reliably monitor the Docker daemon itself. If the Docker daemon crashes, the monitoring container dies silently. The agent also has limited access to host metrics, systemd status, and kernel logs.
**Do this instead:** Install Icinga2 agent on the host via apt. Give it access to the Docker socket (read-only) for container inspection. It can monitor both host and container health, and survives Docker failures.

### Anti-Pattern 6: Terraform State in Local File

**What people do:** Use the default local backend (`terraform.tfstate` file on disk).
**Why it's wrong:** State file contains sensitive data (IP addresses, resource IDs). It is not shared with collaborators. Accidental deletion means Terraform loses track of all resources. No locking -- concurrent applies can corrupt state.
**Do this instead:** Configure DO Spaces as a remote backend with encryption. State is shared, versioned, and locked.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **DigitalOcean API** | Terraform provider (`digitalocean/digitalocean`) | API token stored as env var `DIGITALOCEAN_TOKEN`, never in .tf files |
| **DO Spaces** | S3-compatible API via `s3cmd` or `aws cli` with custom endpoint | Used for backups and Terraform state. Requires Spaces access key (separate from API token) |
| **Let's Encrypt** | ACME protocol via certbot, HTTP-01 challenge | Requires port 80 open during certificate issuance. Nginx serves `/.well-known/acme-challenge/` |
| **Icinga2 Master** | Agent-to-master TLS connection on port 5665 | Agent initiates outbound. Requires CSR signing on master or ticket-based registration |
| **DNS Provider** | A records pointing to Odoo droplet public IP (or WG droplet if routing HTTPS through VPN) | Managed outside Terraform unless using DO DNS. Required for Let's Encrypt domain validation |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **Nginx <-> Odoo** | HTTP proxy_pass on Docker `frontend` network | Nginx resolves `odoo` via Docker DNS. Proxy both 8069 (web) and 8072 (longpolling/websocket) |
| **Odoo <-> PostgreSQL** | PostgreSQL wire protocol on Docker `backend` network | Odoo resolves `postgres` via Docker DNS. Connection params via environment variables |
| **WG Droplet <-> Odoo Droplet** | VPC private network (10.10.0.0/16) | WG droplet forwards VPN client traffic to Odoo droplet private IP. IP forwarding + iptables NAT |
| **Host <-> Containers** | Docker socket + `docker exec` for management | Icinga2 checks use `docker inspect` and `docker exec`. Backup scripts use `docker exec postgres pg_dump` |
| **Terraform <-> Droplets** | SSH (remote-exec provisioner) | Only during initial provisioning. Uses deploy SSH key. Post-provision, admin uses WireGuard VPN |

## Suggested Build Order

The build order is driven by infrastructure dependencies: you cannot configure software on a droplet that does not exist yet, and you cannot deploy containers without Docker installed.

```
Phase 1: Terraform Foundation
    ├── DO provider + Spaces backend
    ├── VPC + Cloud Firewall rules
    ├── SSH key resource
    └── DO Spaces bucket (backups)
         |
Phase 2: Compute + Storage
    ├── WireGuard gateway droplet
    ├── Odoo application droplet
    └── Block storage volume (attach to Odoo droplet)
         |
Phase 3: Base OS Hardening (both droplets)
    ├── base-harden.sh (UFW, fail2ban, SSH, kernel, auto-updates)
    └── Reboot to apply kernel params
         |
Phase 4: WireGuard VPN
    ├── Install WireGuard on gateway droplet
    ├── Generate server + client keys
    ├── Configure wg0 interface
    ├── Enable IP forwarding + iptables NAT
    └── Verify tunnel connectivity
         |
Phase 5: Docker + Application Stack
    ├── Install Docker CE + Compose plugin on Odoo droplet
    ├── Docker daemon hardening (userns-remap, log limits)
    ├── Mount DO Volume at /mnt/data
    ├── Create directory structure (pg_data, odoo_filestore, backups)
    ├── Deploy docker-compose.yml + config files
    └── docker compose up -d
         |
Phase 6: SSL + Public Access
    ├── DNS A record -> Odoo droplet public IP
    ├── Certbot initial certificate (HTTP-01 challenge)
    ├── Configure Nginx with TLS
    ├── Set up certbot renewal cron/timer
    └── Verify HTTPS access
         |
Phase 7: Monitoring
    ├── Install Icinga2 agent on Odoo droplet
    ├── Register agent with Icinga2 master (CSR or ticket)
    ├── Deploy custom check scripts
    ├── Configure host + service definitions on master
    └── Verify checks reporting
         |
Phase 8: Backup + Operations
    ├── Configure pg_dump cron job
    ├── Configure s3cmd for DO Spaces upload
    ├── Test backup + restore cycle
    ├── Document operational procedures
    └── Final end-to-end verification
```

**Dependency rationale:**
- Phase 1 before Phase 2: Droplets need VPC and firewall to be created first.
- Phase 3 before Phase 4-5: Hardening must happen before exposing services. If you install Docker first, the unhardened window is a risk.
- Phase 4 before Phase 5: Admin needs VPN access to troubleshoot Docker deployment issues. Without VPN, you rely on Terraform provisioners running blind.
- Phase 5 before Phase 6: Nginx must be running before requesting Let's Encrypt certificates.
- Phase 7 after Phase 5: Monitoring checks target containers that must exist first.
- Phase 8 last: Backup procedures are the final operational layer. They require a running database to test.

## Sources

- Training data knowledge of Docker Compose networking, Terraform DigitalOcean provider, WireGuard architecture, Icinga2 agent-master model, Nginx reverse proxy patterns, and PostgreSQL container deployment. Confidence: MEDIUM -- these are mature, well-documented technologies with stable architectural patterns, but specific version details (e.g., Odoo 18/19 Docker image tags, exact Terraform provider versions) should be verified against official documentation during implementation.
- Project context from `.planning/PROJECT.md` and `artifacts/Initial_Prompt.md` in this repository.

**Verification notes:**
- Odoo Docker official image structure, available tags, and health check endpoints should be verified against https://hub.docker.com/_/odoo during implementation.
- DigitalOcean Terraform provider resource names and attributes should be verified against https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs during implementation.
- Icinga2 agent registration flow (CSR signing vs. ticket-based) should be verified against https://icinga.com/docs/icinga-2/latest/ during implementation.
- WireGuard configuration syntax should be verified against https://www.wireguard.com/quickstart/ during implementation.

---
*Architecture research for: Containerized Odoo on DigitalOcean with Terraform IaC, WireGuard VPN, and Icinga2 monitoring*
*Researched: 2026-02-20*
