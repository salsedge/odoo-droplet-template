# Phase 6: Monitoring - Context

**Gathered:** 2026-03-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Custom Icinga2 check plugins and service definitions for the Odoo host — monitoring Docker container health and PostgreSQL metrics. The Icinga2 master project handles agent installation/registration AND standard system checks (CPU, memory, disk, load average). This phase delivers only the Odoo-specific custom monitoring that the master doesn't cover.

**In scope:** MON-02 (Docker container health), MON-03 (PostgreSQL checks), MON-05 (service definitions)
**Handled by Icinga2 master project:** MON-01 (agent install), MON-04 (system resource checks)

</domain>

<decisions>
## Implementation Decisions

### Check plugin design
- Two custom check plugins: one for Docker stack, one for PostgreSQL
- Docker check is a single plugin monitoring all containers (odoo + postgres) — not per-container
- PostgreSQL check is a single plugin reporting all PG metrics in one invocation
- Plugins follow standard Nagios plugin conventions: exit codes 0/1/2/3 (OK/WARN/CRIT/UNKNOWN), perfdata after `|`, one-line status output
- Plugins live in `monitoring/` directory (top-level, separate from `config/`)
- PG check authenticates via `docker exec` + `psql` inside the PostgreSQL container — no host-level PG client needed

### Alert thresholds — Docker
- Critical: container not running, unhealthy Docker health status, or restart count >= 5
- Warning: restart count >= 2
- Checks Docker health status (healthcheck configured in compose) — unhealthy containers alert even if technically running

### Alert thresholds — PostgreSQL
- Connections: warn at 35, critical at 45 (of max_connections=50) — 70%/90%
- Database size: thresholded (not just perfdata) — warn 5GB / crit 10GB to catch unexpected growth
- Query latency: SELECT 1 round-trip timing (thresholds at Claude's discretion)
- Cache hit ratio: warn below 90%, critical below 80%

### Service definitions
- Parameterized templates with README documentation — not ready-to-drop .conf files
- Master admin customizes host names, zones, and notification groups from templates
- 5-minute check interval for all custom checks
- Include example notification templates (email) that the admin can enable/customize
- Checks grouped into an 'odoo-production' service group for dashboard organization

### Claude's Discretion
- Plugin language choice (bash vs python) per check — pick the best fit
- Query latency warn/crit thresholds
- DB size warn/crit values (5GB/10GB suggested but can adjust if more appropriate)
- Exact perfdata output format details
- Script error handling patterns
- Template parameterization approach

</decisions>

<specifics>
## Specific Ideas

- PG authentication via `docker exec` keeps the architecture Docker-only — no host-level database clients
- Single-plugin-per-domain approach (one Docker check, one PG check) minimizes overhead and deployment complexity
- Service definition templates should be self-documenting enough that the Icinga2 master admin can integrate without needing to contact the Odoo project team

</specifics>

<deferred>
## Deferred Ideas

- AMON-01 (security event monitoring — failed logins, firewall blocks) — advanced monitoring, future phase
- AMON-02 (backup success/failure alerting via Icinga2) — could extend the backup check plugin later

</deferred>

---

*Phase: 06-monitoring*
*Context gathered: 2026-03-22*
