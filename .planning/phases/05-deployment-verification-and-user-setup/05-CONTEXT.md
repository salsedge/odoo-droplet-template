# Phase 5: Deployment Verification and User Setup - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Run OdooKit (Phase 4's Playwright test suite) against the live production droplet to create real user accounts and verify the entire system works end-to-end. This phase creates no new test tooling — it configures OdooKit for production targeting, creates real team member accounts, and runs verification suites to confirm Phases 1-4 deliver a working system.

</domain>

<decisions>
## Implementation Decisions

### User accounts
- Team members defined in a config file (not hardcoded in tests) — add/remove users without editing test code
- 3+ users: at least one admin, remaining are named team members with real accounts
- Regular users get full app access (all installed modules) but no admin Settings or user management
- Each user gets a unique password defined in the config file — shared securely out-of-band
- No "force change on first login" — passwords are set per-user in config

### Execution target
- SSH tunnel to droplet for Playwright connectivity — tests don't hit the public URL directly
- Tunnel forwards port 443 via Nginx so tests also verify SSL and security headers end-to-end
- Two-stage execution: run against local Docker Compose stack first (dry run), then production
- SSH connection uses deploy user on port 9292 (matching Phase 2 hardening)

### Verification scope
- Production test suites: smoke tests, infrastructure audit, audit tests (HTTP headers + Odoo config)
- Workflow tests (CRM lead, project task) are NOT run against production — Phase 4 local validation is sufficient
- Backup verification: trigger a backup and confirm files appear in local storage + DO Spaces — no restore on production
- Infrastructure audit (infra-audit.sh) runs over a separate SSH session, not the Playwright tunnel
- Reporting: both HTML report (saved to odookit/reports/) and console pass/fail output

### Execution order and safety
- Strict ordering: Smoke → Infrastructure Audit → Odoo Audit → User Creation
- If smoke tests fail: stop everything — no user creation or further tests until smoke passes
- Partial user creation failure: keep successfully created users, report which ones failed
- Setup is idempotent: if a user already exists, skip creation and move on — safe to re-run

### Claude's Discretion
- Production Playwright config approach (env vars vs separate config file) — whichever is cleanest for switching between local and production
- SSH tunnel setup scripting details
- HTML report format and content
- Exact timeout and retry settings for production tests

</decisions>

<specifics>
## Specific Ideas

- SSH tunnel through Nginx (port 443) rather than direct to Odoo (8069) — ensures SSL/header verification is part of every test, not just audit tests
- Config file for users means the same setup script works for any Odoo deployment, not just this one
- Two-stage (local dry run → production) catches config mistakes before touching the live system

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-deployment-verification-and-user-setup*
*Context gathered: 2026-03-19*
