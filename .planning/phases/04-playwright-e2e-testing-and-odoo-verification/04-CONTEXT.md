# Phase 4: Playwright E2E Testing and Odoo Verification - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Automated Playwright-based test suite ("OdooKit") that verifies the deployed Odoo instance is correctly configured, functional, and recoverable. Includes browser-based E2E tests and a separate infrastructure verification script. OdooKit also handles UI-only setup tasks (module installation, system settings, user creation) that can't be done via code, imports, or integrations. Real production user setup is Phase 5 — this phase builds the tooling and tests with throwaway accounts.

</domain>

<decisions>
## Implementation Decisions

### Test execution model
- Tests target both production and local staging environments
  - Production: smoke tests and non-destructive verification
  - Local: full test suite including destructive/setup tests
- Local staging uses Docker Compose — OdooKit auto-spins a local Odoo+PG stack, with option to leave it running for human UAT handoff
- Tests run locally from dev machine (Mac Studio) for now; CI (GitHub Actions) deferred to a future version
- Authentication via .env file — admin credentials for setup/config tests, a limited test user for workflow tests, all configurable by end user

### Verification depth
- Smoke tests: login works, key pages load, modules installed
- Key workflow tests: CRM lead lifecycle (create → advance stages → won/lost), project + task management (create → add tasks → assign → status change), module installation verification
- User management: test user creation with throwaway accounts in Phase 4; real production users created in Phase 5
- Backup restore validation: simplest approach — restore dump into container, confirm Odoo boots and admin can log in. Document plans for data integrity checks and full round-trip validation as future enhancements

### Test output & reporting
- Console output by default for quick runs
- `--report` flag generates Playwright HTML report with traces and screenshots
- Video recording retained on test failure only (not on pass)
- UAT handoff mode: prints Odoo URL, login credentials, and summary of what was set up (modules installed, users created, test data present)

### Config auditing
- **Odoo UI audit:** Check settings through the web interface — modules installed, database manager disabled, company settings. Audit + prompt mode: report issues and let user decide whether to fix each one
- **HTTP/SSL headers:** Verify security headers against industry best practices (Mozilla Observatory level), not just our Nginx config
- **Infrastructure checks:** Separate shell script within OdooKit (not connected to Playwright tests) — verifies SSH port, fail2ban status, Docker settings, UFW rules via SSH

### OdooKit identity
- Named "OdooKit" — a Playwright-based Odoo automation and verification toolkit
- Lives in `odookit/` directory inside this repo initially; extract to separate repo when it matures
- Designed to grow beyond testing — can evolve into a full Odoo automation bot for UI-only tasks

### Claude's Discretion
- Playwright project structure and test organization
- Docker Compose configuration for local staging environment
- Infrastructure check script implementation (bash vs node)
- Test data fixtures and cleanup strategy
- Exact Playwright configuration (timeouts, retries, browser settings)

</decisions>

<specifics>
## Specific Ideas

- OdooKit should feel like a toolkit, not just a test suite — it handles setup tasks (module install, system settings, user creation) that require browser automation
- UAT handoff is important: spin up local stack, run setup, leave it running with clear instructions for human testing
- Infrastructure audit script is part of OdooKit but runs independently from browser tests — different tools for different layers
- Future versions may add more UI automation capabilities as post-launch needs emerge

</specifics>

<deferred>
## Deferred Ideas

- GitHub Actions CI pipeline for automated test runs — future version
- Separate DO droplet for true staging environment — future version (local Docker Compose for now)
- Data integrity verification in backup restore tests (verify specific records survive restore) — document as enhancement
- Full round-trip backup test (create data → backup → restore → verify) — document as enhancement
- Additional Odoo automation bot capabilities beyond initial test suite — post-launch

</deferred>

---

*Phase: 04-playwright-e2e-testing-and-odoo-verification*
*Context gathered: 2026-03-18*
