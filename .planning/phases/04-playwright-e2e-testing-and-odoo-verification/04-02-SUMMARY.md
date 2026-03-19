---
phase: 04-playwright-e2e-testing-and-odoo-verification
plan: 02
subsystem: testing
tags: [playwright, e2e, smoke-tests, workflow-tests, crm, project, odoo]

# Dependency graph
requires:
  - phase: 04-playwright-e2e-testing-and-odoo-verification
    plan: 01
    provides: "Page Object Models (LoginPage, CRMPage, ProjectPage, SettingsPage, AppMenuPage), auth fixtures, helper utilities"
provides:
  - "Smoke tests verifying Odoo health, login, and CRM/Project module installation"
  - "CRM lead lifecycle workflow test (create -> advance -> won/lost)"
  - "Project + task management workflow test (create -> add tasks -> stage changes -> persistence)"
affects: [04-03, 04-04, 05-deployment-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Serial workflow tests with test.describe.serial()", "Production skip guard via PROD_ODOO_URL comparison", "Self-contained smoke tests (no auth fixture) vs authenticated module checks"]

key-files:
  created:
    - odookit/tests/smoke/login.spec.ts
    - odookit/tests/smoke/health.spec.ts
    - odookit/tests/smoke/modules.spec.ts
    - odookit/tests/workflows/crm-lead.spec.ts
    - odookit/tests/workflows/project-task.spec.ts
  modified:
    - odookit/tests/setup/create-users.spec.ts
    - odookit/tests/setup/install-modules.spec.ts
    - odookit/tests/setup/system-settings.spec.ts

key-decisions:
  - "Smoke tests use @playwright/test directly (self-contained), module checks use auth fixture"
  - "Workflow tests skip on production via PROD_ODOO_URL env var comparison"
  - "Serial execution for workflow tests that depend on previous test state"
  - "Unique names with Date.now() suffix to avoid test data collisions"

patterns-established:
  - "Production skip guard: beforeEach checks baseURL against PROD_ODOO_URL"
  - "Serial workflow tests: test.describe.serial() for dependent test sequences"
  - "test.slow() on workflow tests that involve multiple form mutations"
  - "Page content assertion via page.content() for Odoo state indicators (won/lost)"

requirements-completed: [ODOO-01, ODOO-02, ODOO-03, ODOO-05, DOCK-06, PROXY-03, PROXY-04]

# Metrics
duration: 3min
completed: 2026-03-18
---

# Phase 4 Plan 02: Smoke and Workflow Tests Summary

**10 smoke tests (login, health, database manager, module checks) and 8 workflow tests (CRM lead create/advance/won/lost, project task create/stage/persist) using Odoo 19 page objects**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-18T08:49:00Z
- **Completed:** 2026-03-18T08:51:55Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Three smoke test files: login (admin auth, invalid creds, page load), health (/web/health, login accessible, database manager blocked), modules (CRM/Project installed and accessible from app menu)
- CRM lead lifecycle workflow: create lead with contact info, advance through Qualified and Proposition stages, mark as won, create second lead and mark as lost
- Project task management workflow: create project, add 3 tasks, change task stages (In Progress, Done), verify persistence after page reload
- Production safety: workflow tests auto-skip when running against PROD_ODOO_URL, smoke tests are non-destructive

## Task Commits

Each task was committed atomically:

1. **Task 1: Create smoke tests for login, health endpoint, and module verification** - `01dd9ca` (feat)
2. **Task 2: Create CRM lead lifecycle and project task management workflow tests** - `7550f91` (feat)

## Files Created/Modified

- `odookit/tests/smoke/login.spec.ts` - Admin login, invalid credential rejection, login page load verification
- `odookit/tests/smoke/health.spec.ts` - /web/health endpoint, login page accessibility, database manager blocking (ODOO-03, PROXY-04)
- `odookit/tests/smoke/modules.spec.ts` - CRM and Project module installation and app menu presence checks
- `odookit/tests/workflows/crm-lead.spec.ts` - Full CRM lead lifecycle: create, advance stages, won, lost (serial)
- `odookit/tests/workflows/project-task.spec.ts` - Project + task: create, add tasks, stage changes, reload persistence (serial)
- `odookit/tests/setup/create-users.spec.ts` - Fixed JSDoc glob pattern causing TS compilation error
- `odookit/tests/setup/install-modules.spec.ts` - Fixed JSDoc glob pattern causing TS compilation error
- `odookit/tests/setup/system-settings.spec.ts` - Fixed JSDoc glob pattern causing TS compilation error

## Decisions Made

- **Self-contained smoke tests**: Login and health smoke tests import directly from `@playwright/test` instead of the auth fixture. Only module checks need admin auth since they access Settings. This keeps smoke tests minimal and fast.
- **Production skip guard**: Workflow tests use a `beforeEach` hook that compares `PROD_ODOO_URL` against `testInfo.project.use.baseURL` to skip data-creating tests on production environments.
- **Serial execution**: Both workflow test suites use `test.describe.serial()` since tests build on state from previous tests (e.g., create lead -> advance lead -> mark won).
- **Date.now() unique names**: Test data uses `Date.now()` suffix in lead/project/task names to prevent collisions across test runs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed JSDoc glob patterns in pre-existing setup test files**
- **Found during:** Task 2 (TypeScript compilation verification)
- **Issue:** Three files in `tests/setup/` contained `testIgnore: ['**/setup/**']` in JSDoc comments, which TypeScript interpreted as invalid type references, blocking `tsc --noEmit` for the entire project
- **Fix:** Replaced backtick-quoted glob patterns with plain text descriptions
- **Files modified:** `odookit/tests/setup/create-users.spec.ts`, `odookit/tests/setup/install-modules.spec.ts`, `odookit/tests/setup/system-settings.spec.ts`
- **Verification:** `npx tsc --noEmit` passes with zero errors
- **Committed in:** 7550f91 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minimal — fixed JSDoc comment formatting in pre-existing files that blocked compilation. No scope creep.

## Issues Encountered

None beyond the JSDoc glob pattern issue documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 18 tests across 5 files ready for execution against local Odoo stack
- Smoke tests can run against both local and production environments
- Workflow tests auto-skip on production, safe to run with `test:local` script
- Plan 03 (setup tests) and Plan 04 (infrastructure audit) can build on this test foundation
- To run locally: `cd odookit && docker compose up -d && npm run test:local`

## Self-Check: PASSED

- All 5 created files verified present on disk
- Both task commits (01dd9ca, 7550f91) verified in git log
