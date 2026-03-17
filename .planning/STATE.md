# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Run `terraform apply` and get a fully hardened, monitored Odoo deployment with Nginx/SSL -- reproducible, secure, and production-ready from day one.
**Current focus:** Phase 3: Backup, Recovery, and Documentation

## Current Position

Phase: 2 of 5 (Hardened Application Stack) -- COMPLETE
Plan: 3 of 3 executed in current phase (02-01, 02-02, 02-03 all complete)
Status: Phase 2 complete, ready for Phase 3 (Backup, Recovery, and Documentation)
Last activity: 2026-03-12 -- Executed 02-01 (Host Hardening & Docker Installation)

Progress: [██████░░░░] 60%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 2.4 min
- Total execution time: 0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 - Terraform Foundation | 2 | 3 min | 1.5 min |
| 2 - Hardened Application Stack | 3 | 10 min | 3.3 min |

**Recent Trend:**
- Last 5 plans: 01-01 (2 min), 01-02 (1 min), 02-02 (3 min), 02-03 (3 min), 02-01 (4 min)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: WireGuard VPN deferred to v2 -- single droplet architecture simplifies phases
- [Roadmap]: Nginx host-installed (not containerized) for simpler certbot integration
- [Roadmap]: Icinga2 agent host-installed (not containerized) to retain Docker daemon failure visibility
- [Roadmap]: Added end-to-end deployment verification with real user accounts (now Phase 4)
- [Roadmap]: Reordered phases — Monitoring moved from Phase 3 to Phase 5, blocked on external Icinga2 master build. Backup/Docs→Phase 3, Verification→Phase 4
- [01-01]: Flat Terraform layout in infra/ (single file per concern, no modules)
- [01-01]: Backend bucket hardcoded (Terraform backend blocks cannot use variables)
- [01-01]: Env vars preferred for secrets (DIGITALOCEAN_TOKEN, AWS_ACCESS_KEY_ID/SECRET)
- [01-02]: Separate volume_attachment resource (not inline volume_ids) for correct destroy ordering
- [01-02]: Conditional SSH key logic: data source lookup for existing, resource upload for new
- [01-02]: Remote-exec verifies SSH and block device only; mount verification deferred to post-attachment
- [02-01]: SSH port change in cloud firewall via Terraform variable (apply before host hardening)
- [02-01]: Deploy user created with sudo + SSH keys (root login disabled after hardening)
- [02-01]: fail2ban Odoo jail pre-configured but only activates when Odoo logs exist
- [02-01]: Docker daemon iptables: false -- UFW is single source of truth for firewall
- [02-01]: net.ipv4.ip_forward=1 required despite hardening -- Docker bridge networking needs it even with iptables:false
- [02-01]: KbdInteractiveAuthentication replaces deprecated ChallengeResponseAuthentication (OpenSSH 9.6 / Ubuntu 24.04)
- [02-01]: fail2ban sshd uses systemd journal backend (no logpath); odoo-login uses auto backend for file polling
- [02-01]: Docker GPG key import uses --batch --yes for idempotent script re-runs
- [02-02]: Odoo container resource limits: 2GB RAM / 1 CPU; PostgreSQL: 1.2GB / 0.5 CPU
- [02-02]: 3 Odoo workers + 1 cron worker for 10-user workload
- [02-02]: Backend Docker network is internal (no outbound internet from PostgreSQL)
- [02-02]: Module init via docker compose run --rm (not exec) with -i crm,project --stop-after-init
- [02-02]: Odoo 19 uses http_port/gevent_port (deprecated xmlrpc_port/longpolling_port in 17+)
- [02-02]: awk for password injection instead of sed to handle special characters safely
- [02-03]: Two-stage Nginx config: pre-SSL for certbot, then full SSL after cert issuance
- [02-03]: HSTS without includeSubDomains (safe for potential future subdomains)
- [02-03]: Certbot renewal via systemd timer (not cron), twice daily with random delay
- [02-03]: DNS resolver (1.1.1.1/1.0.0.1) required for OCSP stapling -- added during execution
- [02-03]: DNS pre-check before certbot prevents wasted rate-limited attempts
- [02-03]: HTTP-01 challenge (not DNS-01) for simpler setup without DO API token
- [Infra]: Two Spaces buckets — `odoo-prod-tfstate` (Standard) for TF state, `odoo-prod-backups` (Cold Storage) for Phase 3 backups. Cold Storage is 3x cheaper but has 30-day retention + retrieval fees, unsuitable for frequently accessed state files

### Pending Todos

- Execute `terraform apply` to update cloud firewall SSH port to 9292
- SCP scripts/ and config/ to droplet and execute in order

### Blockers/Concerns

- [Phase 2]: Verify Odoo 19 Docker image availability on Docker Hub before execution (may need version pin or 18 fallback)
- [Phase 5]: Icinga2 agent-to-master registration workflow requires coordination with existing master admin — blocked until Icinga2 master is built

## Session Continuity

Last session: 2026-03-12
Stopped at: Completed 02-01-PLAN.md (Host Hardening & Docker Installation) -- Phase 2 complete
Resume file: None
