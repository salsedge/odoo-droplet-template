# Phase 4: Playwright E2E Testing and Odoo Verification - Research

**Researched:** 2026-03-18
**Domain:** Browser automation, E2E testing, Odoo web client, infrastructure verification
**Confidence:** HIGH

## Summary

OdooKit is a Playwright-based Odoo automation and verification toolkit that lives in `odookit/` and serves three functions: (1) browser-based E2E tests for smoke testing, CRM/Project workflow verification, and backup restore validation, (2) an infrastructure verification shell script that audits server hardening over SSH, and (3) UI-based setup automation for module installation, system settings, and user creation. Tests run from the dev machine (Mac Studio) against both a local Docker Compose staging environment and production.

The standard stack is Playwright v1.58 with TypeScript, using Page Object Model for Odoo page abstractions, dotenv for multi-environment configuration, and a local Docker Compose file that spins up the same Odoo 19 + PostgreSQL 18 stack used in production. The infrastructure audit script should be pure bash (consistent with the project's existing scripts/ pattern) rather than Node.js, keeping it zero-dependency and portable.

**Primary recommendation:** Structure OdooKit as a standalone TypeScript Playwright project in `odookit/` with Page Object Models for Odoo's login, app menu, CRM, and Project pages. Use Playwright projects (not separate config files) to switch between local and production targets. The infrastructure audit script lives at `odookit/scripts/infra-audit.sh` and runs independently via SSH.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Tests target both production and local staging environments
  - Production: smoke tests and non-destructive verification
  - Local: full test suite including destructive/setup tests
- Local staging uses Docker Compose — OdooKit auto-spins a local Odoo+PG stack, with option to leave it running for human UAT handoff
- Tests run locally from dev machine (Mac Studio) for now; CI (GitHub Actions) deferred to a future version
- Authentication via .env file — admin credentials for setup/config tests, a limited test user for workflow tests, all configurable by end user
- Smoke tests: login works, key pages load, modules installed
- Key workflow tests: CRM lead lifecycle (create -> advance stages -> won/lost), project + task management (create -> add tasks -> assign -> status change), module installation verification
- User management: test user creation with throwaway accounts in Phase 4; real production users created in Phase 5
- Backup restore validation: simplest approach — restore dump into container, confirm Odoo boots and admin can log in. Document plans for data integrity checks and full round-trip validation as future enhancements
- Console output by default for quick runs
- `--report` flag generates Playwright HTML report with traces and screenshots
- Video recording retained on test failure only (not on pass)
- UAT handoff mode: prints Odoo URL, login credentials, and summary of what was set up (modules installed, users created, test data present)
- Odoo UI audit: Check settings through the web interface — modules installed, database manager disabled, company settings. Audit + prompt mode: report issues and let user decide whether to fix each one
- HTTP/SSL headers: Verify security headers against industry best practices (Mozilla Observatory level), not just our Nginx config
- Infrastructure checks: Separate shell script within OdooKit (not connected to Playwright tests) — verifies SSH port, fail2ban status, Docker settings, UFW rules via SSH
- Named "OdooKit" — a Playwright-based Odoo automation and verification toolkit
- Lives in `odookit/` directory inside this repo initially; extract to separate repo when it matures
- Designed to grow beyond testing — can evolve into a full Odoo automation bot for UI-only tasks

### Claude's Discretion
- Playwright project structure and test organization
- Docker Compose configuration for local staging environment
- Infrastructure check script implementation (bash vs node)
- Test data fixtures and cleanup strategy
- Exact Playwright configuration (timeouts, retries, browser settings)

### Deferred Ideas (OUT OF SCOPE)
- GitHub Actions CI pipeline for automated test runs — future version
- Separate DO droplet for true staging environment — future version (local Docker Compose for now)
- Data integrity verification in backup restore tests (verify specific records survive restore) — document as enhancement
- Full round-trip backup test (create data -> backup -> restore -> verify) — document as enhancement
- Additional Odoo automation bot capabilities beyond initial test suite — post-launch
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@playwright/test` | ^1.58 | E2E testing framework | Official Playwright test runner with built-in assertions, fixtures, projects, reporters |
| TypeScript | ^5.x | Type-safe test code | Catches missing awaits, enforces interface contracts on page objects, IDE autocomplete |
| `dotenv` | ^16.x | Environment variable loading | Standard way to load .env files; Playwright doesn't natively parse .env |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@types/node` | ^22.x | Node.js type definitions | Always — needed for process.env typing |
| Docker Compose | v2 (system) | Local staging environment | Local test runs — spins up Odoo 19 + PG 18 stack |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| TypeScript | JavaScript | JS is simpler but loses type safety on page objects and env vars — TypeScript wins for a toolkit that will grow |
| dotenv | Playwright's built-in env | Playwright doesn't load .env files natively — dotenv is required |
| Bash (infra audit) | Node.js SSH library | Bash is consistent with existing scripts/, zero-dependency, and runs over SSH directly. Node would add ssh2 dependency for no benefit |
| Single playwright.config.ts | Separate configs per env | Playwright projects handle multi-env cleanly within one config file |

**Installation:**
```bash
cd odookit/
npm init -y
npm install -D @playwright/test typescript @types/node dotenv
npx playwright install chromium --with-deps
npx tsc --init
```

## Architecture Patterns

### Recommended Project Structure
```
odookit/
├── playwright.config.ts        # Playwright config with projects for local/prod
├── package.json
├── tsconfig.json
├── .env.example                 # Template: ODOO_URL, ADMIN_LOGIN, ADMIN_PASSWORD, etc.
├── .env                         # (gitignored) Actual credentials
├── docker-compose.yml           # Local staging Odoo 19 + PG 18 stack
├── pages/                       # Page Object Models
│   ├── login.page.ts            # Odoo login page
│   ├── app-menu.page.ts         # App launcher / main menu
│   ├── crm.page.ts              # CRM module (leads, pipeline)
│   ├── project.page.ts          # Project module (projects, tasks)
│   ├── settings.page.ts         # Odoo Settings page
│   └── user-management.page.ts  # User creation/management
├── tests/
│   ├── smoke/                   # Non-destructive (safe for production)
│   │   ├── login.spec.ts        # Admin login, test user login
│   │   ├── modules.spec.ts      # CRM + Project modules installed
│   │   └── health.spec.ts       # /web/health, key pages load
│   ├── workflows/               # CRM lead lifecycle, project management
│   │   ├── crm-lead.spec.ts     # Create -> advance stages -> won/lost
│   │   └── project-task.spec.ts # Create project -> add tasks -> assign -> status
│   ├── setup/                   # Destructive — local only
│   │   ├── install-modules.spec.ts  # Module installation automation
│   │   ├── create-users.spec.ts     # Throwaway test user creation
│   │   └── system-settings.spec.ts  # Company settings, system config
│   └── audit/                   # Configuration auditing
│       ├── odoo-ui-audit.spec.ts    # Web UI settings verification
│       └── http-headers.spec.ts     # SSL/security headers check
├── scripts/
│   └── infra-audit.sh           # Infrastructure verification (SSH-based)
├── fixtures/
│   └── auth.fixture.ts          # Login fixtures (admin session, test user session)
├── helpers/
│   ├── env.ts                   # Type-safe env var loader
│   ├── wait-for-odoo.ts         # Health check polling before tests
│   └── docker-compose.ts        # Compose up/down helpers for local staging
└── reports/                     # (gitignored) HTML reports, traces, screenshots
```

### Pattern 1: Page Object Model for Odoo
**What:** Each Odoo page/view gets a class that encapsulates selectors and actions
**When to use:** Every test that interacts with the Odoo web UI

**Example — Login Page Object:**
```typescript
// Source: Playwright official POM docs + Odoo 19 login template
import { type Locator, type Page, expect } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly loginInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;

  constructor(page: Page) {
    this.page = page;
    // Odoo 19 login form uses: form.oe_login_form, input[name="login"], input[name="password"]
    this.loginInput = page.locator('input[name="login"]');
    this.passwordInput = page.locator('input[name="password"]');
    this.submitButton = page.locator('.oe_login_form button[type="submit"]');
  }

  async goto() {
    await this.page.goto('/web/login');
  }

  async login(email: string, password: string) {
    await this.loginInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
    // Wait for Odoo web client to load (main navbar appears)
    await this.page.locator('.o_main_navbar').waitFor({ state: 'visible' });
  }
}
```

### Pattern 2: Playwright Projects for Multi-Environment
**What:** Single config file with multiple "projects" — one for local staging, one for production
**When to use:** Always — avoids maintaining separate config files

**Example:**
```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '.env') });

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,          // Odoo pages can be slow to load
  expect: { timeout: 10_000 },
  fullyParallel: false,      // Odoo tests must be sequential (shared state)
  retries: 1,
  reporter: process.env.REPORT
    ? [['html', { open: 'never' }]]
    : [['list']],
  use: {
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'local',
      use: {
        baseURL: process.env.LOCAL_ODOO_URL || 'http://localhost:8069',
        ...devices['Desktop Chrome'],
      },
      testIgnore: [],  // Run everything locally
    },
    {
      name: 'production',
      use: {
        baseURL: process.env.PROD_ODOO_URL,
        ...devices['Desktop Chrome'],
      },
      testIgnore: ['**/setup/**'],  // Never run destructive tests against prod
    },
  ],
});
```

### Pattern 3: Auth Fixtures for Session Reuse
**What:** Custom Playwright fixtures that handle login once and reuse the authenticated state
**When to use:** All tests that need a logged-in session

**Example:**
```typescript
// fixtures/auth.fixture.ts
import { test as base, expect } from '@playwright/test';
import { LoginPage } from '../pages/login.page';

type AuthFixtures = {
  adminPage: Page;
  testUserPage: Page;
};

export const test = base.extend<AuthFixtures>({
  adminPage: async ({ browser }, use) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(process.env.ADMIN_LOGIN!, process.env.ADMIN_PASSWORD!);
    await use(page);
    await context.close();
  },
});
```

### Pattern 4: Local Docker Compose Staging
**What:** A docker-compose.yml in odookit/ that mirrors the production stack for local testing
**When to use:** Before running local tests, or for UAT handoff

The local compose file should be a simplified version of `config/docker-compose.yml` — same images (odoo:19, postgres:18) but without production volume mounts, resource limits, or network isolation. Key differences:

- Ports exposed directly (8069:8069) — no Nginx needed locally
- No block storage volume mounts — use Docker volumes
- No resource limits — local dev machine has plenty
- Data is ephemeral — `docker compose down -v` wipes everything
- Same `.env` variable names but different values

### Pattern 5: UAT Handoff Mode
**What:** Run setup tests, leave stack running, print instructions for human tester
**When to use:** When handing off a configured local environment for manual testing

```bash
# Example CLI invocation
cd odookit/
npm run setup:local     # Starts stack, runs setup tests, leaves running
# Output:
# ✓ Local Odoo stack running at http://localhost:8069
# ✓ CRM module installed
# ✓ Project module installed
# ✓ Test user created: testuser@example.com / [password]
# ✓ Sample CRM lead created
#
# UAT Ready — test manually, then: npm run teardown:local
```

### Anti-Patterns to Avoid
- **Relying on CSS classes for Odoo selectors:** Odoo's `o_` prefixed classes change between versions. Prefer `input[name="..."]`, `[data-menu-xmlid="..."]`, and text-based locators where stable. Fall back to `o_` classes only when no better selector exists, and isolate them in page objects so they're easy to update.
- **Running tests in parallel against Odoo:** Odoo has shared server state (database, sessions). Tests that create/modify data will conflict. Use `fullyParallel: false`.
- **Hardcoding credentials in test files:** Always load from `.env` via dotenv. Never commit credentials.
- **Running setup/destructive tests against production:** Use Playwright project `testIgnore` to exclude `setup/` directory from the production project.
- **Skipping waits after Odoo UI actions:** Odoo's web client does XHR calls after field changes. Always wait for network idle or specific element visibility after mutations.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test runner + assertions | Custom test harness | `@playwright/test` | Built-in expect, fixtures, projects, reporters, parallel workers |
| Browser automation | Puppeteer wrapper | Playwright (included) | Auto-waiting, locators, trace viewer, codegen |
| HTML report generation | Custom report template | Playwright HTML reporter | Traces, screenshots, video embedding, timeline |
| Multi-env config | Separate config files | Playwright projects | One config, multiple targets, per-project test filtering |
| Docker Compose lifecycle | Custom bash scripts for up/down | `child_process.execSync` in a helper | Simple spawn of `docker compose up -d` with health polling |
| .env loading | Manual file parsing | `dotenv` package | Handles edge cases, widely tested |
| HTTP header verification | Custom fetch + parsing | Playwright `page.goto()` + `response.headers()` | Already in Playwright's API, no extra dependencies |
| SSL certificate validation | openssl s_client wrapper | Playwright's response API + browser behavior | Browser validates certificates natively; test fails if cert invalid |

**Key insight:** Playwright already provides everything needed for browser testing, reporting, and HTTP inspection. The only custom code needed is Odoo-specific page objects and the infrastructure audit script.

## Common Pitfalls

### Pitfall 1: Odoo Page Load Timing
**What goes wrong:** Tests fail intermittently because Odoo's web client takes variable time to render after navigation
**Why it happens:** Odoo uses OWL framework (Odoo Web Library) which renders components asynchronously. After navigation, the URL changes before the UI is ready. Standard `waitForLoadState('networkidle')` is unreliable because Odoo keeps longpolling connections open.
**How to avoid:** Wait for specific Odoo UI markers after each navigation:
- After login: wait for `.o_main_navbar` to be visible
- After opening an app: wait for the view container (`.o_action_manager .o_view_controller`) to be visible
- After form save: wait for the success notification or the form to leave edit mode
**Warning signs:** Flaky tests that pass on retry, timeouts on CI but not locally

### Pitfall 2: Odoo Field Change Side Effects
**What goes wrong:** Filling a form field then immediately clicking Save loses data
**Why it happens:** Odoo triggers `onchange` RPC calls when fields lose focus. If you click Save before the onchange completes, the save includes stale data or fails.
**How to avoid:** After filling each field, either:
1. Tab to the next field and wait for any loading indicators to disappear
2. Use `page.waitForResponse()` to wait for the onchange RPC to complete
3. Add a small explicit wait if the onchange is known to be slow
**Warning signs:** Saved records missing field values that were definitely filled

### Pitfall 3: Database Manager Disabled Breaks First Login
**What goes wrong:** Odoo redirects to `/web/database/selector` or shows a database selection page when `list_db = False` but the database isn't initialized
**Why it happens:** On first boot with a fresh database, Odoo needs to know which database to use. With `list_db = False`, it uses `db_name` from config.
**How to avoid:** The local Docker Compose should set `POSTGRES_DB` to match the `db_name` in odoo.conf. The health check helper should wait until `/web/login` returns HTTP 200 (not a redirect) before tests begin.
**Warning signs:** Tests fail at the login page with unexpected redirects

### Pitfall 4: Video/Trace Storage Bloat
**What goes wrong:** Test output directory fills up with gigabytes of video recordings
**Why it happens:** Default `video: 'on'` records every test. Odoo workflows involve many page loads generating large videos.
**How to avoid:** Use `video: 'retain-on-failure'` — only keeps videos for failed tests. Also set `outputDir` to `reports/` and add it to `.gitignore`.
**Warning signs:** Disk usage growing rapidly after test runs

### Pitfall 5: Stale Authenticated State
**What goes wrong:** Tests fail with "session expired" or redirect to login mid-workflow
**Why it happens:** Odoo sessions expire (default 7200s), and long test suites can exceed this. Also, running setup tests that restart Odoo invalidates all sessions.
**How to avoid:** Create fresh browser contexts per test file (not per test suite). Don't share authenticated state across test files that may modify server state.
**Warning signs:** Tests pass individually but fail when run together

### Pitfall 6: Local vs Production Environment Drift
**What goes wrong:** Tests pass locally but fail in production (or vice versa)
**Why it happens:** Local Docker Compose stack may use different Odoo configuration, missing modules, or different database state than production.
**How to avoid:** Keep the local docker-compose.yml as close to production as possible (same images, same odoo.conf template). Use the same `.env` variable names. Run smoke tests against both environments regularly.
**Warning signs:** Environment-specific test failures

## Code Examples

Verified patterns from official sources:

### Odoo 19 Login Page Selectors
```typescript
// Source: Odoo 19 webclient_templates.xml (GitHub odoo/odoo 19.0 branch)
// Form: form.oe_login_form, action="/web/login", method="post"
// Login input: input[name="login"], type="text", autocomplete="username"
// Password input: input[name="password"], type="password", autocomplete="current-password"
// Submit button: .oe_login_form button[type="submit"], class="btn btn-primary"
// Hidden: input[name="csrf_token"], input[name="redirect"]
// DB selector (if multiple): input[name="db"], type="text", readonly
```

### Environment Variable Configuration
```typescript
// Source: Playwright docs (parameterize tests) + dotenv docs
// odookit/.env.example
//
// # Target Environment
// LOCAL_ODOO_URL=http://localhost:8069
// PROD_ODOO_URL=https://odoo.example.com
//
// # Admin credentials (for setup/config tests)
// ADMIN_LOGIN=admin@example.com
// ADMIN_PASSWORD=CHANGE_ME
//
// # Test user credentials (created by setup tests, used by workflow tests)
// TEST_USER_LOGIN=testuser@example.com
// TEST_USER_PASSWORD=CHANGE_ME
//
// # Local staging database (must match docker-compose.yml)
// LOCAL_POSTGRES_USER=odoo
// LOCAL_POSTGRES_PASSWORD=odoo_local_dev
// LOCAL_POSTGRES_DB=odoo
//
// # Infrastructure audit SSH target
// INFRA_SSH_HOST=
// INFRA_SSH_PORT=9292
// INFRA_SSH_USER=deploy
//
// # Reporting
// REPORT=             # Set to any value to generate HTML report
```

### HTTP Security Header Verification
```typescript
// Source: Playwright Response API docs
// tests/audit/http-headers.spec.ts
import { test, expect } from '@playwright/test';

test('verify security headers', async ({ page }) => {
  const response = await page.goto('/web/login');
  const headers = response!.headers();

  // HSTS
  expect(headers['strict-transport-security']).toContain('max-age=31536000');
  // X-Content-Type-Options
  expect(headers['x-content-type-options']).toBe('nosniff');
  // X-Frame-Options
  expect(headers['x-frame-options']).toBe('SAMEORIGIN');
  // Referrer-Policy
  expect(headers['referrer-policy']).toBe('strict-origin-when-cross-origin');
  // Content-Security-Policy
  expect(headers['content-security-policy']).toBeTruthy();
});
```

### Docker Compose Health Check Polling
```typescript
// Source: Standard Node.js pattern
// helpers/wait-for-odoo.ts
import { execSync } from 'child_process';

export async function waitForOdoo(url: string, timeoutMs = 120_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/web/health`);
      if (res.ok) return;
    } catch {
      // Not ready yet
    }
    await new Promise(r => setTimeout(r, 2000));
  }
  throw new Error(`Odoo not ready at ${url} after ${timeoutMs}ms`);
}
```

### Infrastructure Audit Script Pattern
```bash
#!/usr/bin/env bash
# odookit/scripts/infra-audit.sh — Infrastructure verification via SSH
# Runs independently from Playwright tests
# Usage: bash scripts/infra-audit.sh [--host HOST] [--port PORT] [--user USER]
#
# Checks:
#   - SSH on non-standard port (HARD-01)
#   - fail2ban running with SSH + Odoo jails (HARD-03)
#   - UFW active with correct rules (HARD-02)
#   - Docker daemon iptables:false (DOCK-02)
#   - Docker containers running and healthy (DOCK-06)
#   - unattended-upgrades enabled (HARD-05)
#   - auditd running (HARD-07)
#
# Output: [PASS]/[FAIL] per check, summary at end (matches backup verify pattern)
```

### Local Staging Docker Compose
```yaml
# odookit/docker-compose.yml — Local staging for OdooKit tests
# Simplified version of config/docker-compose.yml (no resource limits, no block storage)
services:
  db:
    image: postgres:18
    container_name: odookit-db
    environment:
      POSTGRES_USER: ${LOCAL_POSTGRES_USER:-odoo}
      POSTGRES_PASSWORD: ${LOCAL_POSTGRES_PASSWORD:-odoo_local_dev}
      POSTGRES_DB: ${LOCAL_POSTGRES_DB:-odoo}
    volumes:
      - odookit-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${LOCAL_POSTGRES_USER:-odoo}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  odoo:
    image: odoo:19
    container_name: odookit-odoo
    depends_on:
      db:
        condition: service_healthy
    environment:
      HOST: db
      PORT: 5432
      USER: ${LOCAL_POSTGRES_USER:-odoo}
      PASSWORD: ${LOCAL_POSTGRES_PASSWORD:-odoo_local_dev}
    ports:
      - "8069:8069"
      - "8072:8072"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8069/web/health || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 60s

volumes:
  odookit-pgdata:
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Selenium WebDriver | Playwright | 2020+ | Auto-waiting, trace viewer, codegen, better DX — Playwright is the standard for new E2E projects |
| Separate config files per env | Playwright projects | Playwright v1.20+ | Single config with multiple targets, per-project test filtering |
| Manual screenshot capture | `screenshot: 'only-on-failure'` | Built-in | Automatic artifact capture on failure, no custom code needed |
| xmlrpc_port / longpolling_port | http_port / gevent_port | Odoo 17+ | Config key names changed — affects health check URLs and port references |
| Odoo Widget framework | OWL (Odoo Web Library) | Odoo 14+ | Modern component framework — affects selector strategies and timing |
| Chrome for Testing (CfT) | Default in Playwright v1.57+ | 2025 | More reliable Chrome version management, matches actual Chrome behavior |

**Deprecated/outdated:**
- `page.waitForNavigation()`: Replaced by `page.waitForURL()` in Playwright v1.33+
- `page.accessibility`: Removed in Playwright v1.57. Use `@axe-core/playwright` if needed.
- Odoo `xmlrpc_port` / `longpolling_port`: Renamed to `http_port` / `gevent_port` in Odoo 17+

## Open Questions

1. **Exact Odoo 19 app menu selectors**
   - What we know: Odoo uses `o_main_navbar` for the top bar, and apps have `data-menu-xmlid` attributes. CRM is likely `crm.crm_menu_root`, Project is likely `project.menu_main_pm`.
   - What's unclear: Exact selector path for opening CRM and Project apps in Odoo 19 — the app launcher mechanism may have changed from 18.
   - Recommendation: Use Playwright codegen (`npx playwright codegen http://localhost:8069`) against a running local instance to discover exact selectors during implementation. Isolate selectors in page objects so they're easy to update.

2. **Odoo CRM kanban stage selectors**
   - What we know: CRM pipeline uses kanban view with stages as columns. Leads can be dragged between stages or have their stage changed via the form.
   - What's unclear: Whether stage changes should use drag-and-drop (fragile) or form-based stage selection (more reliable).
   - Recommendation: Use form-based stage changes (open lead -> change stage field -> save). More reliable than drag-and-drop and easier to assert.

3. **Backup restore test integration**
   - What we know: The existing `scripts/08-restore-backup.sh` handles verify-only mode with temp containers. Context says "simplest approach — restore dump into container, confirm Odoo boots and admin can log in."
   - What's unclear: Whether to invoke the existing bash script from the test or reimplement the restore logic in the Playwright test.
   - Recommendation: Invoke the existing `08-restore-backup.sh --verify-only` from within a Playwright test using `child_process.execSync`, then verify the temporary Odoo instance is accessible. This reuses proven code and keeps the single source of truth for restore logic.

4. **`--report` flag implementation**
   - What we know: User wants `--report` flag to generate HTML report. Playwright supports `reporter` config.
   - What's unclear: Whether to use an npm script flag, a Playwright CLI flag, or an environment variable.
   - Recommendation: Use the `REPORT` environment variable approach: `REPORT=1 npx playwright test`. This is clean and doesn't require custom CLI parsing. The playwright.config.ts checks `process.env.REPORT` to switch between `list` and `html` reporters.

## Sources

### Primary (HIGH confidence)
- [Playwright official docs — Best Practices](https://playwright.dev/docs/best-practices) — locator strategy, test isolation, POM pattern
- [Playwright official docs — Configuration](https://playwright.dev/docs/test-configuration) — projects, use options, reporters, timeouts
- [Playwright official docs — Docker](https://playwright.dev/docs/docker) — Docker image tags, recommended flags
- [Playwright official docs — Page Object Model](https://playwright.dev/docs/pom) — POM pattern with TypeScript
- [Playwright official docs — Release Notes](https://playwright.dev/docs/release-notes) — v1.58 current stable
- Odoo 19 `webclient_templates.xml` (GitHub odoo/odoo 19.0) — login form selectors confirmed

### Secondary (MEDIUM confidence)
- [Playwright .env loading with dotenv](https://www.browserstack.com/guide/playwright-env-variables) — verified against Playwright docs parameterize section
- [Odoo 19 web client overview](https://www.odoo.com/documentation/19.0/developer/reference/frontend/framework_overview.html) — OWL framework, `o_main_navbar` class
- [Odoo forum — Playwright timeout issues](https://www.odoo.com/forum/help-1/trying-to-avoid-timeouts-testing-my-odoo-app-with-playwright-257851) — field change timing, onchange delays

### Tertiary (LOW confidence)
- Odoo CRM/Project app menu xmlid values (`crm.crm_menu_root`, `project.menu_main_pm`) — inferred from Odoo naming conventions, needs validation via codegen against running instance
- Exact kanban stage selectors for CRM pipeline — needs discovery via Playwright codegen

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Playwright v1.58 confirmed via npm/release notes, TypeScript + dotenv are standard
- Architecture: HIGH — POM pattern from official Playwright docs, project structure follows community consensus
- Odoo selectors: MEDIUM — Login page confirmed from source, but app menu and CRM/Project selectors need validation via codegen
- Pitfalls: HIGH — Odoo timing issues confirmed by community reports and official OWL documentation
- Infrastructure audit: HIGH — Bash is consistent with project conventions, SSH checks are straightforward

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (stable — Playwright releases monthly but APIs are backward-compatible; Odoo 19 selectors stable within major version)
