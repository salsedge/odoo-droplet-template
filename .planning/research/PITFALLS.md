# Pitfalls Research

**Domain:** Containerized Odoo deployment on DigitalOcean with Terraform IaC, WireGuard VPN, Icinga2 monitoring, PCI-DSS hardening
**Researched:** 2026-02-20
**Confidence:** MEDIUM (based on training data for mature, well-documented technologies; WebSearch/WebFetch unavailable for live verification)

## Critical Pitfalls

### Pitfall 1: Odoo Filestore and PostgreSQL Data Loss from Docker Volume Mismanagement

**What goes wrong:**
Odoo stores critical data in two places: PostgreSQL (business data) and the filesystem filestore (attachments, reports, images). If Docker volumes are not correctly configured, a `docker-compose down -v` or container recreation destroys all production data. Named volumes vs bind mounts vs anonymous volumes have different lifecycle behaviors, and operators routinely conflate them.

**Why it happens:**
Docker Compose anonymous volumes are deleted on `docker-compose down -v`. Developers who test with `down -v` during development carry that habit to production. Additionally, the official Odoo Docker image defines `VOLUME` directives in the Dockerfile, which create anonymous volumes by default if not explicitly mapped. Many tutorials omit the distinction.

**How to avoid:**
- Always use explicitly named volumes or bind mounts to host paths for both `/var/lib/odoo` (filestore) and PostgreSQL data (`/var/lib/postgresql/data`).
- Back the volumes with DigitalOcean Block Storage Volumes attached via Terraform, not ephemeral droplet disk.
- Never use `docker-compose down -v` in production. Alias or script `down` without `-v` and document this.
- Add a pre-flight check script that verifies volume mounts are pointing at persistent storage before starting containers.
- In `docker-compose.yml`, define volumes explicitly in the top-level `volumes:` section with `external: true` or named volumes, never rely on Dockerfile VOLUME declarations.

**Warning signs:**
- `docker volume ls` shows unnamed/hash-named volumes associated with your containers.
- Filestore directory is empty after container restart.
- Terraform provisions droplets but does not attach/mount Block Storage Volumes before Docker Compose runs.
- Your `docker-compose.yml` lacks a top-level `volumes:` section.

**Phase to address:**
Phase: Docker Compose Configuration (container + volume setup). Must be resolved before first production data enters the system.

---

### Pitfall 2: Terraform State File Contains Secrets in Plaintext

**What goes wrong:**
Terraform state files (`terraform.tfstate`) contain every resource attribute in plaintext, including database passwords, API tokens, SSH private keys, and any `sensitive` variable values. Storing state locally or in an unencrypted backend exposes all infrastructure secrets.

**Why it happens:**
Terraform's state file is fundamentally a plaintext JSON document. Even variables marked `sensitive` in HCL are stored in plaintext in the state. New Terraform users assume `sensitive = true` means encrypted. DigitalOcean API tokens passed as variables appear in the state. This is by design, not a bug.

**How to avoid:**
- Use DigitalOcean Spaces as a remote backend with `encrypt = true` (Spaces supports server-side encryption).
- Enable Spaces bucket versioning so state corruption is recoverable.
- Lock down Spaces access keys to the minimum permission scope.
- Never commit `terraform.tfstate` or `*.tfstate.backup` to Git. Add to `.gitignore` immediately at project init.
- Use `terraform output -json` rather than reading state directly.
- For database passwords and API tokens, generate them outside Terraform (e.g., using `random_password` resource) and reference them -- but understand they still land in state.
- Evaluate whether Terraform Cloud (free tier for small teams) is preferable for state management with built-in encryption-at-rest.

**Warning signs:**
- `terraform.tfstate` file exists in the repo working directory.
- `.gitignore` does not include `*.tfstate*`.
- State backend block is missing from Terraform configuration.
- `grep -r "password\|token\|secret" terraform.tfstate` returns matches (it will -- that's the point, it needs to be in a secure backend).

**Phase to address:**
Phase: IaC Project Structure and Setup. Must be the very first thing configured before any `terraform apply`.

---

### Pitfall 3: WireGuard Gateway Becomes Single Point of Failure for Admin Access

**What goes wrong:**
The WireGuard droplet fronts the Odoo droplet for all management access. If the WireGuard droplet fails, goes unreachable, or its config is corrupted, you lose all SSH/admin access to the Odoo infrastructure. Since PCI-DSS hardening locks down SSH to VPN-only, you have zero out-of-band access to recover.

**Why it happens:**
The architecture correctly isolates admin access behind WireGuard. But operators forget that this isolation means the WireGuard droplet itself is the single recovery path. If kernel updates break WireGuard, if the droplet runs out of disk, if UFW rules get misconfigured, or if DigitalOcean has a hypervisor issue, there is no way in.

**How to avoid:**
- Configure DigitalOcean Droplet Console access (browser-based VNC through the DO control panel) as an emergency backdoor. This bypasses network entirely.
- Maintain a documented "break glass" procedure: DO Console -> fix WireGuard -> restore normal access.
- Ensure the WireGuard droplet has a DigitalOcean Monitoring alert for reachability.
- Back up WireGuard private keys and config to DO Spaces (encrypted) so a replacement gateway can be stood up from Terraform.
- Consider a secondary WireGuard peer configuration (e.g., mobile device) for emergency access if primary workstation VPN fails.
- Keep WireGuard droplet minimal -- no unnecessary services that could destabilize it.

**Warning signs:**
- No documented "break glass" procedure exists.
- WireGuard droplet has no monitoring/alerting configured.
- WireGuard private keys exist only on the droplet (not backed up).
- Team has never tested recovery by rebuilding the WireGuard droplet from Terraform.

**Phase to address:**
Phase: WireGuard Configuration. Document recovery procedures at deploy time, not after.

---

### Pitfall 4: Odoo Running as Root Inside Container

**What goes wrong:**
The official Odoo Docker image has historically run processes as root or with broad privileges. If Odoo or any dependency has a remote code execution vulnerability (common in large Python applications with many modules), the attacker gains root inside the container. Combined with insufficient Docker security settings (no seccomp, no AppArmor, no read-only rootfs), this can escalate to host compromise.

**Why it happens:**
Default Docker behavior runs processes as root. The official Odoo image does create an `odoo` user, but custom Dockerfiles or `docker-compose.yml` overrides can inadvertently run as root. Bind-mounting host directories often forces root to avoid permission errors. Operators choose the "easy" path.

**How to avoid:**
- Verify the Odoo container runs as non-root by checking `docker exec <container> whoami` returns `odoo`, not `root`.
- In `docker-compose.yml`, explicitly set `user: odoo` or `user: "1000:1000"`.
- Use `security_opt: [no-new-privileges:true]` in Compose.
- Set `read_only: true` for rootfs with explicit `tmpfs` mounts for writable paths Odoo needs (`/tmp`, `/var/lib/odoo/sessions`).
- Drop all Linux capabilities and add back only what is needed: `cap_drop: [ALL]`.
- Fix file ownership on volumes before starting: `chown -R 1000:1000 /path/to/filestore` in an init script.
- Scan images with Trivy or Grype as part of build process.

**Warning signs:**
- `docker-compose.yml` lacks `user:`, `security_opt:`, or `cap_drop:` directives.
- Permission errors that are "fixed" by adding `privileged: true` or running as root.
- Custom Dockerfile uses `USER root` without switching back.

**Phase to address:**
Phase: Docker Security Hardening. Must be enforced before deploying any version that handles production data.

---

### Pitfall 5: PostgreSQL Exposed Beyond Docker Network or Using Default Credentials

**What goes wrong:**
PostgreSQL is accessible from outside the Docker network (bound to 0.0.0.0 instead of only the Docker bridge), or uses weak/default credentials (postgres/postgres or odoo/odoo). Combined with a misconfigured DigitalOcean firewall, the database is reachable from the internet. Automated scanners find exposed PostgreSQL instances within minutes.

**Why it happens:**
Docker Compose `ports:` directive publishes to 0.0.0.0 by default. Tutorial examples use `ports: ["5432:5432"]` for debugging convenience. Developers forget to remove this for production. Default passwords in example docker-compose files get copied verbatim. DigitalOcean Cloud Firewalls are stateful but must be explicitly created via Terraform -- if forgotten, all ports the droplet listens on are publicly reachable.

**How to avoid:**
- Never publish PostgreSQL ports in `docker-compose.yml`. Use Docker's internal networking only: Odoo connects to `db:5432` via the Compose network, no `ports:` section needed on the PostgreSQL service.
- If you must expose the port for debugging, bind to localhost only: `ports: ["127.0.0.1:5432:5432"]`.
- Generate strong random passwords (32+ characters) for PostgreSQL using Terraform's `random_password` resource.
- Configure `pg_hba.conf` to reject connections from unexpected sources.
- Terraform must provision DigitalOcean Cloud Firewalls that whitelist only ports 443 (HTTPS), 51820 (WireGuard), and nothing else inbound.
- Use the DigitalOcean VPC for inter-droplet communication -- keep PostgreSQL traffic entirely on the private network.

**Warning signs:**
- `docker-compose.yml` has `ports:` under the PostgreSQL service.
- `docker ps` shows `0.0.0.0:5432->5432/tcp` in the PORTS column.
- Password values are hardcoded strings in docker-compose or terraform files rather than generated secrets.
- Terraform configuration lacks `digitalocean_firewall` resources.

**Phase to address:**
Phase: Docker Compose Configuration and IaC Networking Module. Both must be correct before first deployment.

---

### Pitfall 6: Terraform Destroys and Recreates Droplets on Config Changes (Data Loss)

**What goes wrong:**
Changing certain Terraform resource attributes (like `image`, `region`, `size` in some cases, or `user_data`) on `digitalocean_droplet` forces Terraform to destroy and recreate the droplet instead of updating in-place. This destroys everything on the droplet including Docker volumes, containers, and all data not on separately attached Block Storage.

**Why it happens:**
Terraform differentiates between "update in-place" and "force replacement" attributes. For DigitalOcean droplets, changing the base image or region triggers replacement. The `user_data` field (cloud-init) also forces replacement on change. Operators modify these fields assuming Terraform will just "update" the droplet. Terraform's plan output shows `# forces replacement` but operators miss this in large plans.

**How to avoid:**
- Always run `terraform plan` and review output carefully before `apply`. Search for `# forces replacement` or `must be replaced`.
- Use `lifecycle { prevent_destroy = true }` on critical droplet resources to prevent accidental destruction.
- Store all persistent data on DigitalOcean Block Storage Volumes (attached via `digitalocean_volume` + `digitalocean_volume_attachment`), not on the droplet's root disk. Block Storage survives droplet destruction.
- Use `lifecycle { ignore_changes = [user_data] }` after initial provisioning if cloud-init changes shouldn't trigger rebuild.
- Tag droplets with `prevent-destroy` and have CI checks that flag destruction of tagged resources.
- Test Terraform changes against a throwaway droplet first.

**Warning signs:**
- `terraform plan` output contains `forces replacement` for any production resource.
- Persistent data lives on root disk rather than attached Block Storage.
- No `lifecycle` blocks on critical infrastructure resources.
- `user_data` is modified after initial deployment.

**Phase to address:**
Phase: IaC Compute Module. Lifecycle protections must be in place before the infrastructure holds any production data.

---

### Pitfall 7: Let's Encrypt Certificate Issuance Fails Silently, Users Hit Self-Signed or HTTP

**What goes wrong:**
Nginx is configured for SSL with Let's Encrypt via Certbot, but certificate issuance fails (DNS not propagated, port 80 blocked by firewall, rate limited). Nginx either falls back to a self-signed cert (browser warnings, users can't access) or fails to start entirely. Since this is behind WireGuard for admin access, the operator may not notice the failure immediately.

**Why it happens:**
Let's Encrypt requires HTTP-01 or DNS-01 challenge validation. HTTP-01 needs port 80 open to the internet and DNS pointing to the correct IP. In the project architecture, the WireGuard droplet and Odoo droplet are separate -- DNS must point to the right IP (the one with Nginx, not the WireGuard gateway). DigitalOcean firewalls may block port 80 if not explicitly opened for ACME challenges. Rate limiting (5 certs per domain per week) catches operators who retry aggressively during debugging.

**How to avoid:**
- Ensure Terraform opens port 80 inbound temporarily (or permanently for renewal) on the droplet running Nginx.
- Verify DNS A record points to the Nginx/Odoo droplet's public IP (or a floating IP), not the WireGuard droplet.
- Use `certbot --dry-run` before requesting real certificates.
- Implement DNS-01 challenge validation using DigitalOcean DNS API (via `certbot-dns-digitalocean` plugin) to avoid needing port 80 entirely -- this is the superior approach for this architecture.
- Configure Nginx to start with a self-signed cert initially, then replace after Certbot succeeds, so the service is not blocked on cert issuance.
- Set up Icinga2 monitoring for certificate expiry (check_ssl_cert with 30-day warning threshold).
- Set up a cron job or systemd timer for `certbot renew` and test it works.

**Warning signs:**
- Nginx fails to start after deployment.
- Users report browser security warnings.
- `certbot certificates` shows no managed certificates.
- Port 80 is not open in DigitalOcean firewall rules.
- DNS A record points to wrong IP.

**Phase to address:**
Phase: Nginx/SSL Configuration, after networking and firewall setup is validated.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoding IPs in WireGuard/firewall configs instead of using Terraform variables | Faster initial setup | Every IP change requires manual edits across multiple files; drift between Terraform and reality | Never -- use Terraform template files and variables from day one |
| Using `remote-exec` provisioners for all configuration | Quick to get working | Provisioners only run on creation, not updates; no idempotency; difficult to debug; Terraform marks resource tainted on failure | Acceptable for initial bootstrap only; move to configuration pull model (scripts on the droplet triggered externally) for ongoing management |
| Single `docker-compose.yml` for all services (Odoo, PostgreSQL, Nginx, monitoring) | Simpler project structure | Cannot restart/update one service without affecting others; monolithic lifecycle coupling | Acceptable for 10-user workload. Revisit if adding more services |
| Storing Odoo admin password in `odoo.conf` plaintext | Required by Odoo | Password sits in file readable by anyone with container access | Never fully avoidable with Odoo, but restrict file permissions to 600 and ensure the container runs as non-root |
| Skipping Terraform state locking | No lock backend to configure | Concurrent applies corrupt state; two operators can destroy infrastructure simultaneously | Never -- use DynamoDB-equivalent or Terraform Cloud. For DO Spaces backend, note that S3-compatible locking requires a separate DynamoDB-like mechanism or use Terraform Cloud free tier |
| Using `latest` tag for Docker images | Always get newest version | Builds are not reproducible; surprise breaking changes on restart; security auditing impossible | Never in production. Always pin to specific version tags (e.g., `odoo:18.0`, `postgres:16.4`) |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Icinga2 agent to master | Generating CSR/cert on agent manually and mismatching CN/SAN with expected hostname, causing TLS handshake failures | Use `icinga2 node wizard` or `icinga2 pki` toolchain to generate certificates that match the endpoint name configured on the master. Automate via provisioner script that accepts master hostname and ticket as variables |
| Odoo to PostgreSQL | Using `localhost` as the database host in `odoo.conf`, which tries to connect via Unix socket (unavailable across containers) | Use the Docker Compose service name (e.g., `db`) as the host. Docker DNS resolves this to the PostgreSQL container's IP on the shared Compose network |
| Certbot with DigitalOcean DNS | Not installing the `certbot-dns-digitalocean` plugin, or providing an API token with read-only scope | Install `python3-certbot-dns-digitalocean` and use a DO API token with read+write scope for DNS. Store the token in a credentials file with 600 permissions |
| Terraform remote state on DO Spaces | Using the `s3` backend with wrong endpoint format or missing `skip_credentials_validation`/`skip_metadata_api_check` flags required for S3-compatible (non-AWS) backends | Configure backend with `endpoint = "https://<region>.digitaloceanspaces.com"`, `skip_credentials_validation = true`, `skip_metadata_api_check = true`, `skip_requesting_account_id = true` |
| DigitalOcean VPC with Docker networking | Assigning the droplet a VPC private IP range that conflicts with Docker's default bridge subnet (172.17.0.0/16 or 172.18.0.0/16) | Choose a DO VPC range outside Docker's defaults (e.g., 10.10.0.0/16). Or configure Docker daemon's `default-address-pools` in `/etc/docker/daemon.json` to use a non-conflicting range |
| Backup to DO Spaces | Using the same API token/key for both Terraform state and backup scripts -- revocation of one breaks the other | Create separate Spaces access keys: one for Terraform state backend, one for backup scripts. Scope permissions appropriately |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| No PostgreSQL connection pooling | Odoo opens a new PostgreSQL connection per worker process; connections pile up; PostgreSQL hits `max_connections` and refuses new connections | Set `db_maxconn` in `odoo.conf` (default is 64, which is too high for a small deployment -- use 8-16 per worker). Set PostgreSQL `max_connections` to match total Odoo workers * `db_maxconn` + monitoring overhead. For larger scale, add PgBouncer | At ~5+ workers (current 10-user scale is fine with tuning, but breaks immediately if defaults are left unchanged and workers are increased) |
| Odoo workers set to 0 (threaded mode) | Odoo runs single-process multi-threaded, which is GIL-bound; longpolling blocks request handling; CPU underutilized | Set `workers = 2-3` for 10 users (formula: `(CPU_cores * 2) + 1`, but constrained by RAM). Set `max_cron_threads = 1`. Configure `limit_memory_hard`, `limit_memory_soft`, `limit_time_cpu`, `limit_time_real` | Immediately noticeable with any concurrent users -- threaded mode is for development only |
| PostgreSQL without tuned shared_buffers and work_mem | Uses PostgreSQL defaults (128MB shared_buffers), wasting available RAM; queries hit disk instead of buffer cache | Set `shared_buffers = 25% of container RAM`, `effective_cache_size = 75% of container RAM`, `work_mem = 4-8MB`, `maintenance_work_mem = 256MB`. Use pgtune.leopard.in.ua for initial values | Noticeable when database exceeds ~500MB or reports take >5 seconds |
| No resource limits on Docker containers | One container consumes all host RAM/CPU, starving others. Odoo cron jobs or report generation can spike memory. OOM killer kills random containers | Set `deploy.resources.limits` in Compose for both CPU and memory. Set `mem_limit` and `cpus`. PostgreSQL: 1GB+ RAM, 1 CPU. Odoo: 2GB+ RAM, 2 CPUs. Adjust based on droplet size | First heavy report generation or unoptimized custom module execution |
| Odoo filestore on root disk without size monitoring | Attachments, report PDFs, and asset bundles accumulate; root disk fills up; Odoo hangs or crashes; Docker daemon cannot create containers | Mount filestore on DO Block Storage Volume. Set Icinga2 disk usage alert at 80%. Consider `odoo.conf` `--limit-memory-hard` to prevent single requests from dumping huge files | Varies -- typically 6-12 months of active use for 10 users |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Leaving Odoo database manager accessible (`/web/database/manager`) | Anyone on the network can create, duplicate, drop, or backup entire databases without authentication if the master password is weak or default | Set `list_db = False` in `odoo.conf` for production. Set a strong `admin_passwd` (database manager password). Block `/web/database/*` routes in Nginx reverse proxy config |
| Not restricting Docker daemon socket | If any container mounts `/var/run/docker.sock`, that container has root-equivalent access to the host. Some monitoring tools request this | Never mount the Docker socket into application containers. For Docker monitoring in Icinga2, use the `docker` CLI from the host via Icinga2 check commands, not from inside containers. If socket access is truly needed, use a read-only Docker socket proxy like `tecnativa/docker-socket-proxy` |
| UFW rules not accounting for Docker's iptables manipulation | Docker modifies iptables directly, bypassing UFW entirely. Ports published by Docker are publicly accessible regardless of UFW rules. Operators believe UFW is protecting them when it is not | Configure Docker daemon with `"iptables": false` in `/etc/docker/daemon.json` and manage iptables rules manually, OR use `ufw-docker` utility, OR bind container ports only to 127.0.0.1 and use Nginx on the host to proxy. The `iptables: false` approach is cleanest for PCI-DSS compliance |
| WireGuard private keys generated with weak entropy or stored unencrypted on disk | Key compromise means VPN can be impersonated; all "secure" admin access is compromised | Generate keys with `wg genkey` (uses `/dev/urandom`, cryptographically strong). Store private keys with 600 permissions owned by root. Back up encrypted to DO Spaces. Rotate keys on any suspected compromise. Do not embed private keys in Terraform state -- generate on the droplet and only store the public key in Terraform |
| SSH key management in Terraform exposes private keys | If private SSH keys are generated by Terraform's `tls_private_key` resource, the private key is stored in Terraform state in plaintext | Generate SSH keypairs outside of Terraform. Only import the public key via `digitalocean_ssh_key` resource. Never use `tls_private_key` for production infrastructure |
| PCI-DSS: No audit logging for container actions | PCI-DSS requires logging all access to cardholder data environments; Docker actions are not logged by default | Enable Docker daemon audit logging (`"log-driver": "json-file"` with `max-size` and `max-file` limits). Use `auditd` on the host to monitor Docker socket access and container lifecycle events. Ship logs to a central location |
| Odoo session cookies without Secure/HttpOnly flags behind reverse proxy | Session hijacking is possible if cookies traverse any non-HTTPS link, or are accessible to JavaScript | Ensure Nginx sets `proxy_cookie_path` with Secure and HttpOnly attributes. Configure `proxy_set_header X-Forwarded-Proto https;` so Odoo knows it is behind HTTPS and sets Secure flag on cookies. Set `proxy_mode = True` in `odoo.conf` |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Terraform deploys successfully:** Does not mean firewalls are actually applied to droplets -- verify `digitalocean_firewall` resources have correct `droplet_ids` in their definition, not just that they exist
- [ ] **Docker Compose starts all containers:** Does not mean volumes are persistent -- run `docker inspect <container>` and verify `Mounts` show named volumes or bind mounts to Block Storage paths, not anonymous volumes
- [ ] **Odoo loads in browser:** Does not mean workers are configured -- check `odoo.conf` for `workers > 0`; threaded mode "works" but is unsuitable for production
- [ ] **WireGuard handshake succeeds:** Does not mean routing works -- verify you can reach the Odoo droplet's private IP through the VPN tunnel, not just the WireGuard endpoint itself. Test SSH to the Odoo droplet through the tunnel
- [ ] **Certbot obtains certificate:** Does not mean auto-renewal works -- `certbot renew --dry-run` must succeed, and a cron/systemd timer must be configured. Certs expire in 90 days; this will fail silently if renewal is broken
- [ ] **Icinga2 agent connects to master:** Does not mean checks are functional -- verify that service check results are flowing back to the master. An agent connection with no configured checks looks "green" but monitors nothing
- [ ] **Backups run on schedule:** Does not mean they are restorable -- test restore to a fresh container at least once. A backup that cannot be restored is not a backup
- [ ] **UFW shows correct rules:** Does not mean Docker respects them -- run `iptables -L -n` and verify Docker is not bypassing UFW with its own rules. This is the single most common false-sense-of-security issue on Docker hosts
- [ ] **PCI-DSS hardening script completes:** Does not mean all settings survived reboot -- reboot the droplet and verify: fail2ban is running, UFW is enabled, SSH is hardened, kernel parameters persisted, Docker daemon config is loaded
- [ ] **Terraform state is remote:** Does not mean it is encrypted or locked -- verify the DO Spaces bucket has encryption enabled and that concurrent `terraform apply` is prevented (state locking)

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Data loss from Docker volume destruction | HIGH | Restore PostgreSQL from latest backup on DO Spaces (`pg_restore`). Restore Odoo filestore from backup. If no backup exists, data is unrecoverable. Implement backup verification immediately |
| Terraform state corruption/loss | HIGH | If state is versioned on DO Spaces, restore previous version. If state is lost entirely, `terraform import` each resource manually (extremely tedious for 10+ resources). Always enable Spaces bucket versioning |
| WireGuard droplet unreachable | LOW | Access via DigitalOcean Console (browser-based VNC). Check WireGuard service status, UFW rules, disk space. If unrecoverable, `terraform destroy` + `terraform apply` the WireGuard module only (data lives on Odoo droplet) |
| PostgreSQL exposed to internet | MEDIUM | Immediately remove `ports:` from Compose and restart. Audit `pg_stat_activity` for unknown connections. Change all passwords. Review PostgreSQL logs for unauthorized access. Consider data breach notification if PCI data was exposed |
| Terraform destroys production droplet | HIGH | Re-provision droplet via Terraform. Reattach Block Storage Volume (if data was on Block Storage, it survives). Redeploy Docker Compose stack. Restore any data from backups. If data was on root disk, treat as total data loss |
| Let's Encrypt rate limited | LOW | Wait for rate limit reset (1 week). Use Let's Encrypt staging environment for testing. Switch to DNS-01 validation which has higher rate limits. Use a self-signed cert temporarily if needed |
| Docker bypassing UFW (ports publicly exposed) | MEDIUM | Immediately set `"iptables": false` in Docker daemon config and restart Docker. Manually configure iptables rules. Audit access logs for unauthorized connections during the exposure window |
| Icinga2 certificate mismatch | LOW | Re-run `icinga2 pki` workflow to regenerate agent certificate. Update master endpoint configuration. Restart both agent and master Icinga2 services |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Docker volume data loss | Docker Compose Configuration | `docker inspect` confirms named volumes; Block Storage mounted at expected path; test: stop and restart all containers, verify data persists |
| Terraform state secrets exposure | IaC Project Structure and Setup | State file is on remote backend (DO Spaces); `.gitignore` includes `*.tfstate*`; `terraform state pull` only accessible to authorized operators |
| WireGuard single point of failure | WireGuard Configuration | "Break glass" document exists; DO Console access tested; WireGuard config backed up to Spaces; secondary peer configured |
| Odoo running as root | Docker Security Hardening | `docker exec odoo-container whoami` returns `odoo`; `docker inspect` shows SecurityOpt includes `no-new-privileges`; capabilities are dropped |
| PostgreSQL exposure | Docker Compose + IaC Networking | `docker ps` shows no published ports for PostgreSQL; `nmap` from external IP shows only 443 and 51820 open |
| Terraform force-replacement | IaC Compute Module | `lifecycle { prevent_destroy = true }` present on droplet and volume resources; all persistent data on Block Storage |
| Let's Encrypt failure | Nginx/SSL Configuration | `certbot certificates` shows valid cert; `certbot renew --dry-run` succeeds; cron job exists; Icinga2 checks cert expiry |
| Docker bypassing UFW | Base System Hardening | Docker daemon.json contains `"iptables": false`; `iptables -L -n` matches expected rules; external port scan confirms only expected ports |
| Database manager exposed | Odoo Configuration | `curl -s https://domain/web/database/manager` returns 403/404; `odoo.conf` contains `list_db = False` |
| Backup not restorable | Backup Configuration | Documented restore procedure exists; restore tested to fresh container; backup files verified non-empty on DO Spaces |
| PCI-DSS settings not surviving reboot | Base System Hardening | Reboot droplet; verify all hardening settings are intact; automated Icinga2 checks confirm compliance after reboot |
| VPC/Docker subnet conflict | IaC Networking + Docker Configuration | VPC range and Docker bridge range do not overlap; containers can reach internet and each other; Odoo connects to PostgreSQL successfully |

## Sources

- Training data knowledge on Docker, Terraform, DigitalOcean, WireGuard, Odoo, PostgreSQL, PCI-DSS, Icinga2 (MEDIUM confidence -- these are mature, well-documented technologies with stable pitfall patterns)
- Docker official documentation: Docker iptables interaction and UFW bypass is extensively documented
- Terraform documentation: Force-replacement behavior and state sensitivity are documented in Terraform core docs
- Odoo deployment documentation: Worker configuration, database manager security, proxy mode documented in official Odoo deploy guide
- Let's Encrypt rate limits and challenge types: documented at letsencrypt.org
- PCI-DSS v4.0 requirements: logging, access control, encryption requirements are public standard
- Note: WebSearch and WebFetch were unavailable during this research session. All findings are based on training data for well-established technologies. Recommend verification of version-specific details (especially Odoo 18/19 Docker image behavior and current DigitalOcean Terraform provider attributes) during implementation phases

---
*Pitfalls research for: Containerized Odoo on DigitalOcean with Terraform, WireGuard, Icinga2, PCI-DSS*
*Researched: 2026-02-20*
