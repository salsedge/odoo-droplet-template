# Key Decisions

Architectural and implementation decisions made during the project, with rationale. These explain *why* the system is built this way — useful context for operators and future contributors.

---

## Architecture

| Decision | Rationale |
|----------|-----------|
| Single-droplet architecture | 10-user workload doesn't justify multi-server complexity. WireGuard VPN deferred to v2. |
| `iptables: false` in Docker daemon | UFW is the single firewall source of truth. Docker's iptables manipulation bypasses UFW rules. |
| Nginx on host (not containerized) | Simpler certbot integration, survives Docker daemon restarts. |
| `deploy` user, not root | Root login disabled after hardening. `deploy` has sudo + SSH key access. |
| Dual Docker networks | `frontend` (Nginx ↔ Odoo) + `backend` (Odoo ↔ PG, internal, no outbound). |
| Block Storage for all data | PostgreSQL data + Odoo filestore on DO Volume, not ephemeral disk. |

## Application

| Decision | Rationale |
|----------|-----------|
| 3 workers + 1 cron | Right-sized for 2 vCPU / 4 GB with 10 concurrent users. |
| Community edition only | Sufficient for CRM + Project, no license cost. |
| Database manager disabled | Security — prevents unauthorized database operations via web UI. |
| `net.ipv4.ip_forward=1` kept enabled | Docker bridge networking requires it even with `iptables: false`. |

## Infrastructure

| Decision | Rationale |
|----------|-----------|
| Flat Terraform layout | Single file per concern in `infra/`, no modules. Right-sized for single-droplet. |
| Separate `volume_attachment` resource | Not inline `volume_ids` on droplet — prevents destroy-ordering issues in Terraform. |
| Two Spaces buckets | `{PROJECT_NAME}-tfstate` (Standard) for TF state, `{PROJECT_NAME}-backups` (Cold Storage) for backups. Cold is 3× cheaper but has 30-day retention + retrieval fees. |
| Remote-exec for bootstrap only | Verifies SSH and block device; mount verification deferred to post-attachment. |

## Deployment

| Decision | Rationale |
|----------|-----------|
| Two-stage Nginx config | Pre-SSL config serves certbot HTTP-01 challenge, replaced with full SSL config after cert issuance. |
| HTTP-01 challenge (not DNS-01) | Simpler setup without requiring DO API token in certbot. |
| HSTS without `includeSubDomains` | Safe for potential future subdomains. |
| Certbot renewal via systemd timer | More reliable than cron, twice daily with random delay. |

## Backup

| Decision | Rationale |
|----------|-----------|
| Local + Spaces backups | Fast local restore + offsite DR covers both scenarios. |
| Retention cleanup before new backup | Frees space on volume before writing new dump. |
| Restore script defaults to verify-only | Requires explicit `--production` flag for live restore — prevents accidental overwrites. |
| Status files use Nagios convention | `0=OK, 2=CRITICAL` — ready for Phase 5 Icinga2 integration. |

## Explicitly Not Done

| What | Why Not |
|------|---------|
| Kubernetes / Docker Swarm | Massively overkill for 10 users. |
| PgBouncer | Not needed at 10 users with `max_connections = 50`. |
| Prometheus / Grafana | Icinga2 is the monitoring stack. |
| ELK/EFK log aggregation | Elasticsearch needs 4 GB+ RAM; Docker log rotation sufficient. |
| External secrets manager (Vault) | `.env` with restricted permissions sufficient at this scale. |
| CI/CD pipeline | Manual deployment acceptable for initial setup. |
