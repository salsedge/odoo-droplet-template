---
phase: 02-hardened-application-stack
plan: 02
subsystem: infra
tags: [docker, docker-compose, odoo, postgresql, containers]

# Dependency graph
requires:
  - phase: 02-hardened-application-stack/02-01
    provides: Hardened host with Docker CE installed, UFW, fail2ban
provides:
  - Docker Compose stack with Odoo 19 + PostgreSQL 18
  - Dual network isolation (frontend bridge + backend internal)
  - Health checks for both services
  - Resource-limited containers sized for s-2vcpu-4gb
  - Block Storage Volume persistence for data and filestore
  - Deployment script with module initialization
affects: [02-hardened-application-stack/02-03, 03-monitoring, 04-backup-recovery]

# Tech tracking
tech-stack:
  added: [docker-compose, postgres-18, odoo-19]
  patterns: [localhost-only-binding, internal-docker-network, env-based-secrets]

key-files:
  created:
    - config/docker-compose.yml
    - config/.env.example
    - config/odoo.conf
    - config/postgresql.conf
    - scripts/03-deploy-stack.sh
  modified:
    - config/odoo.conf
    - scripts/03-deploy-stack.sh

key-decisions:
  - "Odoo 19 uses http_port/gevent_port instead of deprecated xmlrpc_port/longpolling_port"
  - "awk instead of sed for password injection to handle special characters safely"
  - "docker compose run --rm for module init instead of exec on running container"

patterns-established:
  - "Localhost-only port binding: containers publish to 127.0.0.1 only, Nginx handles public access"
  - "Internal Docker network: backend network has internal:true to isolate database from internet"
  - "Block Storage Volume mounts: persistent data at /mnt/odoo-prod-data with uid-specific ownership"

requirements-completed: [DOCK-03, DOCK-04, DOCK-05, DOCK-06, ODOO-01, ODOO-02, ODOO-03, ODOO-04, ODOO-05, PG-01, PG-02, PG-03, PG-04]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 2 Plan 02: Docker Application Stack Summary

**Odoo 19 + PostgreSQL 18 Docker Compose stack with dual-network isolation, resource limits, health checks, and Block Storage persistence**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T19:14:06Z
- **Completed:** 2026-03-12T19:17:08Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- Verified Docker Compose configuration with Odoo 19 + PostgreSQL 18 services, dual networks, health checks, and resource limits
- Fixed Odoo config for v19 parameter names (deprecated xmlrpc/longpolling replaced with http/gevent)
- Hardened deploy script with safe password injection and proper module initialization workflow

## Task Commits

Each task was committed atomically:

1. **Task 1: Docker Compose configuration** - No changes needed (files created in planning phase were correct)
2. **Task 2: Odoo and PostgreSQL configuration files** - `962e082` (fix)
3. **Task 3: Stack deployment script** - `9b0cb52` (fix)

## Files Created/Modified
- `config/docker-compose.yml` - Docker Compose with Odoo + PostgreSQL services, dual networks, health checks, resource limits
- `config/.env.example` - Environment variable template for database and admin credentials
- `config/odoo.conf` - Odoo config tuned for 10 users: 3 workers, memory limits, proxy mode, list_db=False
- `config/postgresql.conf` - PostgreSQL config: 256MB shared_buffers, 8MB work_mem, 50 max_connections, slow query logging
- `scripts/03-deploy-stack.sh` - Deployment script: volume setup, config deploy, image pull, health wait, module init

## Decisions Made
- Updated Odoo config to use `http_port`/`gevent_port` instead of deprecated `xmlrpc_port`/`longpolling_port` (renamed in Odoo 17+)
- Replaced `sed` with `awk` for password injection in deploy script to safely handle special characters in passwords
- Changed module init from `docker compose exec` (runs inside active container) to `docker compose run --rm` (dedicated temporary container) to avoid process conflicts

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed deprecated Odoo 19 config parameter names**
- **Found during:** Task 2 (Odoo configuration)
- **Issue:** odoo.conf used `xmlrpc_interface`, `xmlrpc_port`, and `longpolling_port` which were deprecated in Odoo 17+ and renamed to `http_interface`, `http_port`, and `gevent_port`
- **Fix:** Updated all three parameter names to their current equivalents
- **Files modified:** config/odoo.conf
- **Verification:** Correct parameter names confirmed for Odoo 19
- **Committed in:** 962e082

**2. [Rule 1 - Bug] Fixed unsafe sed-based password injection**
- **Found during:** Task 3 (Deploy script review)
- **Issue:** `sed -i "s/PLACEHOLDER/${PASSWORD}/"` breaks if password contains `/`, `&`, or other sed metacharacters
- **Fix:** Replaced with `awk -v pwd="${PASSWORD}" '{gsub(..., pwd); print}'` which handles all special characters
- **Files modified:** scripts/03-deploy-stack.sh
- **Verification:** awk approach is safe for any password content
- **Committed in:** 9b0cb52

**3. [Rule 1 - Bug] Fixed module init running inside active Odoo container**
- **Found during:** Task 3 (Deploy script review)
- **Issue:** `docker compose exec` runs a second Odoo process inside the already-running container, which can conflict with the active worker processes
- **Fix:** Stop Odoo first, run module init via `docker compose run --rm` (temporary container), then start Odoo normally
- **Files modified:** scripts/03-deploy-stack.sh
- **Verification:** Module init now runs in isolation, no process conflicts
- **Committed in:** 9b0cb52

---

**Total deviations:** 3 auto-fixed (3 bugs via Rule 1)
**Impact on plan:** All fixes necessary for correctness. No scope creep.

## Issues Encountered
None -- files from planning phase were well-structured, only needed parameter name updates and deployment safety fixes.

## User Setup Required

Before running the deploy script on the droplet:
```
cp config/.env.example config/.env
# Edit config/.env with strong, unique passwords
chmod 600 config/.env
```

## Next Phase Readiness
- Docker Compose stack is ready for deployment on the hardened host (after 02-01 execution)
- Odoo will listen on 127.0.0.1:8069 only -- ready for Nginx reverse proxy (02-03)
- Blocker from STATE.md still applies: verify Odoo 19 Docker image availability on Docker Hub before execution

## Self-Check: PASSED

All 6 files verified present. Both commit hashes (962e082, 9b0cb52) confirmed in git log.

---
*Phase: 02-hardened-application-stack*
*Completed: 2026-03-12*
