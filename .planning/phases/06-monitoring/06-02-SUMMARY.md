---
phase: 06-monitoring
plan: 02
subsystem: monitoring
tags: [icinga2, nagios, monitoring, service-definitions, notifications]

# Dependency graph
requires:
  - phase: 06-monitoring plan 01
    provides: Custom check plugins (check_docker_stack, check_postgres_health)
provides:
  - Icinga2 CheckCommand definitions for docker-stack and postgres-health
  - Service apply rules with command_endpoint for agent-side execution
  - ServiceGroup odoo-production for dashboard organisation
  - Notification apply rules using built-in mail-service-notification
  - Self-contained integration README for Icinga2 master admin
affects: []

# Tech tracking
tech-stack:
  added: [icinga2-dsl]
  patterns: [command_endpoint agent execution, parameterised templates with placeholders, service group aggregation]

key-files:
  created:
    - monitoring/icinga2/commands.conf
    - monitoring/icinga2/services.conf
    - monitoring/icinga2/notifications.conf
    - monitoring/README.md
  modified: []

key-decisions:
  - "Parameterised templates with PLACEHOLDER markers rather than ready-to-drop configs"
  - "Built-in mail-service-notification command rather than custom notification scripts"
  - "CustomPluginDir constant in commands.conf for adjustable plugin path"
  - "Example host object commented out in services.conf for admin reference"

patterns-established:
  - "Icinga2 service definitions use command_endpoint for agent-side plugin execution"
  - "All custom checks grouped in odoo-production ServiceGroup"
  - "Template files use /* PLACEHOLDER: ... */ markers for admin customisation"

requirements-completed: [MON-01, MON-04, MON-05]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 6 Plan 02: Icinga2 Service Definitions Summary

**Icinga2 DSL templates for CheckCommand, Service, and Notification objects with self-contained integration README for master admin**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-22T16:38:31Z
- **Completed:** 2026-03-22T16:41:24Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Two CheckCommand objects mapping CLI arguments to Icinga2 custom variables with sensible defaults
- Two Service apply rules with command_endpoint, 5-minute intervals, and odoo-production grouping
- Notification apply rules routing alerts via built-in mail-service-notification to odoo-admins
- Comprehensive README covering architecture, prerequisites, deployment steps, threshold tuning, and troubleshooting

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Icinga2 service definition templates** - `4c76530` (feat)
2. **Task 2: Create monitoring integration README** - `7464276` (docs)

## Files Created/Modified
- `monitoring/icinga2/commands.conf` - CheckCommand objects for docker-stack and postgres-health plugins
- `monitoring/icinga2/services.conf` - Service apply rules, ServiceGroup, and example host object
- `monitoring/icinga2/notifications.conf` - Notification apply rules with User and UserGroup examples
- `monitoring/README.md` - Self-contained integration guide for Icinga2 master admin

## Decisions Made
- Used `/* PLACEHOLDER: ... */` comment syntax for markers the admin must customise, keeping them visible in Icinga2 DSL
- Defined `CustomPluginDir` constant in commands.conf so the plugin path is adjustable per environment
- Provided example host object as a comment block rather than an active object to avoid conflicts with existing host definitions
- Used built-in `mail-service-notification` command for notifications rather than custom scripts, reducing maintenance burden
- Documented MON-01 (agent install) and MON-04 (system checks) as prerequisites handled by the Icinga2 master project, setting clear scope boundaries

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. The Icinga2 master admin follows the README to deploy templates and fill in placeholders.

## Next Phase Readiness
- Phase 6 plan 01 (custom check plugins) can be executed independently; the commands.conf references are forward-compatible
- After both plans complete, the full monitoring package is ready for handoff to the Icinga2 master admin
- No blockers for the monitoring integration

## Self-Check: PASSED

All 4 created files verified on disk. Both task commits (4c76530, 7464276) verified in git log.

---
*Phase: 06-monitoring*
*Completed: 2026-03-22*
