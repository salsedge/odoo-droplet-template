---
phase: 06-monitoring
plan: 01
subsystem: monitoring
tags: [icinga2, nagios, docker, postgresql, bash, check-plugins]

# Dependency graph
requires:
  - phase: 02-hardened-application-stack
    provides: Docker Compose stack with odoo-app and odoo-db containers
provides:
  - check_docker_stack Nagios/Icinga2 plugin for container health monitoring
  - check_postgres_health Nagios/Icinga2 plugin for PostgreSQL metrics
affects: [06-monitoring plan 02 (service definitions reference these plugins)]

# Tech tracking
tech-stack:
  added: [nagios-plugin-api]
  patterns: [nagios-check-plugin-bash, docker-inspect-go-templates, docker-exec-psql]

key-files:
  created:
    - monitoring/plugins/check_docker_stack
    - monitoring/plugins/check_postgres_health
  modified: []

key-decisions:
  - "Bash over Python for both plugins — minimal dependencies, no interpreter needed on host"
  - "Worst-status-wins across all metrics/containers — complete perfdata always collected"
  - "bc fallback to integer comparison for cache hit ratio on minimal systems"

patterns-established:
  - "Nagios Plugin API: exit codes 0/1/2/3, single-line status, perfdata after pipe character"
  - "Docker monitoring via docker inspect --format Go templates (not docker ps parsing)"
  - "PostgreSQL monitoring via docker exec -i psql (no host-level PG client)"

requirements-completed: [MON-02, MON-03]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 6 Plan 1: Custom Check Plugins Summary

**Two Nagios/Icinga2-compatible bash check plugins for Docker container health (MON-02) and PostgreSQL metrics (MON-03) with configurable thresholds and perfdata output**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-22T16:38:09Z
- **Completed:** 2026-03-22T16:40:42Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Docker container health plugin monitoring running state, healthcheck status, and restart counts across all stack containers
- PostgreSQL metrics plugin collecting 4 key indicators: connections, database size, query latency, and cache hit ratio
- Both plugins fully configurable via CLI flags with sensible defaults matching the 10-user Odoo workload

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Docker container health check plugin** - `88b9af0` (feat)
2. **Task 2: Create PostgreSQL health check plugin** - `fe52f0c` (feat)

## Files Created/Modified
- `monitoring/plugins/check_docker_stack` - Monitors odoo-app and odoo-db container health via docker inspect
- `monitoring/plugins/check_postgres_health` - Collects PostgreSQL metrics via docker exec + psql

## Decisions Made
- Bash for both plugins (no Python dependency, minimal runtime requirements on host)
- Worst-status-wins pattern: collect all metrics/containers before deciding final exit code, ensuring complete perfdata in every invocation
- bc with integer fallback for floating-point cache hit ratio comparison (handles minimal server installs without bc)
- Docker inspect with Go templates instead of parsing docker ps output (structured, reliable)
- Query latency includes docker exec overhead — thresholds set at 100ms/500ms to account for this

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Both plugins ready for Plan 02 (Icinga2 service definitions) which will reference these plugins as CheckCommand objects
- Plugins should be deployed to `/usr/lib/nagios/plugins/` on the Odoo host (handled by Icinga2 master integration)
- nagios user needs docker group membership for both plugins to function

## Self-Check: PASSED

---
*Phase: 06-monitoring*
*Completed: 2026-03-22*
