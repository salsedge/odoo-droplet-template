# Phase 2: Hardened Application Stack - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Take the bare DigitalOcean droplet provisioned by Phase 1 and turn it into a secure, production-ready Odoo server. This phase covers: PCI-DSS host hardening, Docker container deployment (Odoo + PostgreSQL), and Nginx reverse proxy with Let's Encrypt SSL. The result is a working Odoo instance accessible via HTTPS from the public internet. Monitoring, backups, and user setup are separate phases.

</domain>

<decisions>
## Implementation Decisions

### SSH and access policy
- SSH on port 9292 (non-standard)
- Allow SSH from any IP — key-only authentication, no password login, no root login
- SSH keys already provisioned by Phase 1 Terraform — no key deployment needed in this phase
- fail2ban with standard thresholds: 5 failed attempts, 10-minute ban
- WireGuard lockdown deferred to v2 — document that SSH will move to VPN-only access later

### Docker networking and firewall strategy
- Docker daemon configured with `iptables: false` — UFW is the single source of truth for all firewall rules
- UFW explicit allow rules for SSH (9292), HTTP (80), HTTPS (443) with default-deny
- Nginx runs on the host (not containerized) — installed via apt, manages SSL/certbot directly
- Odoo container publishes port bound to localhost only (127.0.0.1:8069) — only reachable from host Nginx
- PostgreSQL container has no published ports — reachable only from Odoo via Docker backend network
- Docker Compose with two networks: frontend (host↔Odoo) and backend (Odoo↔PostgreSQL)
- Container resource limits sized based on Phase 1 droplet size (read from Terraform config)

### Odoo configuration
- Official `odoo:19` Docker Hub image (maintained by Odoo S.A.)
- CRM and Project modules auto-installed at deploy time via `-i` flag — ready immediately, no manual steps
- Additional modules can be installed later through the UI
- Multi-worker mode (2-4 workers + cron worker) for 10-user concurrency
- Worker count and memory limits tuned based on available droplet resources
- Admin master password stored in `.env` file with restricted permissions (600)
- Database manager disabled (`list_db = False`)
- Odoo filestore persisted on DO Block Storage Volume

### SSL and domain setup
- Let's Encrypt SSL via HTTP-01 challenge (no DNS API credentials needed)
- Port 80 remains open in UFW for ACME challenge verification and HTTP→HTTPS redirect
- HSTS enabled for main domain only (no includeSubDomains) — safe for potential other subdomains
- Full security headers: X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Content-Security-Policy
- Nginx blocks access to `/web/database/*` routes (returns 403)
- Certbot auto-renewal via systemd timer

### Claude's Discretion
- Exact sysctl kernel hardening parameters (SYN cookies, ICMP redirects, IP forwarding)
- auditd rules for PCI-DSS 10.x compliance logging
- Docker log rotation configuration (max-size, max-file)
- Exact Odoo worker count tuning within the 2-4 range
- PostgreSQL tuning parameters (shared_buffers, work_mem, max_connections) for 10 users
- Nginx proxy buffer sizes and timeout values
- Content-Security-Policy specifics for Odoo compatibility
- Unattended security updates configuration
- File permission specifics for sensitive configs

</decisions>

<specifics>
## Specific Ideas

- "Once WireGuard is setup we'll move to only accessing SSH via private network" — design SSH config so the port/access change is straightforward later
- Auto-install CRM + Project at deploy for faster startup, but keep the ability to install more modules through the UI later
- DNS is managed externally (not DigitalOcean) — HTTP-01 challenge chosen to avoid DNS provider coupling

</specifics>

<deferred>
## Deferred Ideas

- WireGuard VPN for SSH lockdown — v2 (VPN-01, VPN-02, VPN-03)
- Nginx rate limiting on /web/login — v2 (OPS-03)
- Container image scanning with Trivy — v2 (DSEC-01)

</deferred>

---

*Phase: 02-hardened-application-stack*
*Context gathered: 2026-02-21*
