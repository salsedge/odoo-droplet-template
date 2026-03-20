# Phase 5: Deployment Verification and User Setup - Research

**Researched:** 2026-03-19
**Domain:** Production deployment verification, SSH tunneling, Playwright production targeting, user provisioning
**Confidence:** HIGH

## Summary

Phase 5 runs the existing OdooKit Playwright test suite from Phase 4 against the live production droplet to verify the entire system works end-to-end and to create real user accounts. No new test tooling is created -- this phase adds production targeting infrastructure (SSH tunnel scripts, production Playwright config, team member config file) and orchestration scripts to execute tests in the correct order with proper safety gates.

The existing OdooKit codebase provides everything needed: smoke tests, audit tests (UI + HTTP headers), infrastructure audit (SSH-based), setup tests (module install, user creation), and workflow tests. The Phase 4 `playwright.config.ts` already has a `production` project with `testIgnore: ['**/setup/**']` -- setup tests are excluded from production runs by design. The key work is: (1) an SSH tunnel script to forward port 443 from the droplet to localhost for Playwright connectivity, (2) a team members config file for user definitions, (3) a production user creation test that reads from the config file instead of env vars, (4) an orchestration script that enforces execution order (smoke -> infra audit -> odoo audit -> user creation), and (5) backup verification via SSH.

**Primary recommendation:** Create a single orchestration script (`odookit/scripts/run-production.sh`) that manages the SSH tunnel lifecycle, runs tests in the mandated order with fail-fast on smoke tests, and generates an HTML report. Team members are defined in `odookit/team-members.json` and user creation uses a dedicated production-specific test file that reads this config.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Team members defined in a config file (not hardcoded in tests) -- add/remove users without editing test code
- 3+ users: at least one admin, remaining are named team members with real accounts
- Regular users get full app access (all installed modules) but no admin Settings or user management
- Each user gets a unique password defined in the config file -- shared securely out-of-band
- No "force change on first login" -- passwords are set per-user in config
- SSH tunnel to droplet for Playwright connectivity -- tests don't hit the public URL directly
- Tunnel forwards port 443 via Nginx so tests also verify SSL and security headers end-to-end
- Two-stage execution: run against local Docker Compose stack first (dry run), then production
- SSH connection uses deploy user on port 9292 (matching Phase 2 hardening)
- Production test suites: smoke tests, infrastructure audit, audit tests (HTTP headers + Odoo config)
- Workflow tests (CRM lead, project task) are NOT run against production -- Phase 4 local validation is sufficient
- Backup verification: trigger a backup and confirm files appear in local storage + DO Spaces -- no restore on production
- Infrastructure audit (infra-audit.sh) runs over a separate SSH session, not the Playwright tunnel
- Reporting: both HTML report (saved to odookit/reports/) and console pass/fail output
- Strict ordering: Smoke -> Infrastructure Audit -> Odoo Audit -> User Creation
- If smoke tests fail: stop everything -- no user creation or further tests until smoke passes
- Partial user creation failure: keep successfully created users, report which ones failed
- Setup is idempotent: if a user already exists, skip creation and move on -- safe to re-run

### Claude's Discretion
- Production Playwright config approach (env vars vs separate config file) -- whichever is cleanest for switching between local and production
- SSH tunnel setup scripting details
- HTML report format and content
- Exact timeout and retry settings for production tests

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

Phase 5 is a cross-cutting verification phase -- it validates that all requirements from Phases 1-3 work together in production. No new requirement IDs are introduced.

| ID | Description | Research Support |
|----|-------------|-----------------|
| IAC-01 through IAC-08 | Terraform infrastructure | Verified indirectly: if Playwright can reach Odoo through the tunnel, the infrastructure is provisioned correctly |
| HARD-01 | SSH hardening | infra-audit.sh checks SSH port, root login disabled, password auth disabled |
| HARD-02 | UFW firewall | infra-audit.sh checks UFW status and allowed ports |
| HARD-03 | fail2ban | infra-audit.sh checks fail2ban service and SSH jail |
| HARD-05 | Unattended upgrades | infra-audit.sh checks service status |
| HARD-07 | auditd PCI-DSS | infra-audit.sh checks auditd service status |
| DOCK-02 | Docker iptables:false | infra-audit.sh checks daemon.json |
| DOCK-03 | Docker Compose stack | Smoke tests verify Odoo responds; infra-audit.sh checks container health |
| DOCK-06 | Container health checks | infra-audit.sh checks Docker container status |
| ODOO-01 | CRM + Project modules | Odoo UI audit tests verify module installation |
| ODOO-03 | Database manager disabled | Odoo UI audit + smoke test verifies /web/database/* blocked |
| ODOO-05 | Admin password + db routes | Odoo UI audit verifies database manager route returns 403 |
| PG-01 | PostgreSQL 18 | Verified by Odoo being functional (depends on PG) |
| PG-03 | PG accessible only from Odoo | infra-audit.sh verifies no published PG ports (Docker network isolation) |
| PG-04 | PG credentials in .env | Verified by stack running correctly with env-based credentials |
| PROXY-03 | HTTPS redirect + HSTS | HTTP headers audit tests verify HSTS, HTTP->HTTPS redirect |
| PROXY-04 | Block /web/database/* | HTTP headers audit + Odoo UI audit verify 403 response |
| BACK-01 | Automated daily pg_dump | Backup verification triggers backup and checks local file |
| BACK-02 | Sync to DO Spaces | Backup verification checks file appears in Spaces after sync |
| BACK-03 | Retention policy | Verified by backup script running successfully |
| BACK-04 | Documented restore procedure | Phase 3 verified restore; Phase 5 confirms backup files are present |
| DOC-01 through DOC-04 | Documentation | Verified by existence; Phase 5 focuses on runtime verification |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Playwright | ^1.58 | Browser automation against production | Already installed in OdooKit from Phase 4 |
| SSH (OpenSSH) | System | Tunnel + infra audit connectivity | Standard macOS/Linux tool; deploy user on port 9292 already configured |
| Bash | System | Orchestration script, SSH tunnel management | Shell scripting matches project convention (scripts/*.sh) |
| dotenv | ^16 | Environment variable loading | Already in OdooKit from Phase 4 |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | System | Parse backup-status.json and sync-status.json over SSH | Backup verification checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SSH tunnel for Playwright | Direct HTTPS to public URL | Tunnel verifies SSL end-to-end AND avoids exposing test traffic to internet; tunnel is the locked decision |
| JSON config for team members | YAML config | JSON is native to Node.js (no parser dependency); simpler for this use case |
| Bash orchestration script | Node.js script | Bash aligns with project convention (scripts/*.sh); orchestration is mostly exec calls + conditionals |

## Architecture Patterns

### Production Test Execution Flow

```
run-production.sh
├── 1. Pre-flight checks (SSH connectivity, local dry run passed)
├── 2. Start SSH tunnel (port 443 → localhost:8443)
├── 3. Run smoke tests via Playwright (--project=production)
│   └── FAIL → stop, close tunnel, report error
├── 4. Run infra audit via separate SSH session
│   └── FAIL → warn but continue (non-blocking)
├── 5. Run Odoo UI audit + HTTP headers audit via Playwright
│   └── FAIL → warn but continue (non-blocking)
├── 6. Run user creation tests via Playwright
│   └── Partial failure → report which users failed, continue
├── 7. Run backup verification via SSH
│   └── FAIL → warn but continue (non-blocking)
├── 8. Close SSH tunnel
└── 9. Generate HTML report + console summary
```

### SSH Tunnel Pattern

```bash
# Forward remote 443 to local 8443 (avoid needing root for local 443)
ssh -f -N -L 8443:localhost:443 -p 9292 deploy@$DROPLET_IP

# Playwright baseURL for production: https://localhost:8443
# --ignore-https-errors flag needed because cert is for domain, not localhost

# Kill tunnel after tests
kill $(lsof -ti:8443) 2>/dev/null
```

**Key detail:** The SSH tunnel forwards remote port 443 (Nginx HTTPS) to a local port. Playwright connects to `https://localhost:<local_port>`. The SSL certificate is issued for the domain name, not localhost, so Playwright needs `ignoreHTTPSErrors: true` in the production project config. However, the HTTP headers audit test for HSTS and the HTTP->HTTPS redirect test should still work because they check response headers, not browser certificate validation.

### Team Members Config File

```
odookit/team-members.json
```

```json
{
  "users": [
    {
      "name": "Admin User",
      "login": "admin@company.com",
      "password": "set-in-env-or-config",
      "role": "admin"
    },
    {
      "name": "Team Member 1",
      "login": "user1@company.com",
      "password": "set-per-user",
      "role": "user",
      "groups": {
        "Sales": "User: Own Documents Only",
        "Project": "User"
      }
    }
  ]
}
```

**Security note:** This file contains passwords. It MUST be added to `.gitignore` with a `.example` template committed instead. Passwords are shared out-of-band per the user's decision.

### Production Playwright Config Approach (Discretion Area)

**Recommendation: Environment variables, not a separate config file.**

Rationale:
- `playwright.config.ts` already has a `production` project that reads `PROD_ODOO_URL`
- Adding a few more env vars (`PROD_LOCAL_PORT`, tunnel port) is cleaner than duplicating config
- The `.env` file already has `PROD_ODOO_URL`, `INFRA_SSH_HOST`, `INFRA_SSH_PORT`, `INFRA_SSH_USER`
- The orchestration script sets env vars before invoking Playwright

The production project config needs one change: when connecting through the SSH tunnel, `baseURL` should be `https://localhost:<tunnel_port>` and `ignoreHTTPSErrors` should be `true`. The orchestration script handles this by setting `PROD_ODOO_URL=https://localhost:8443` and the config reads it.

### Recommended File Structure

```
odookit/
├── team-members.json.example    # Template for team member config (committed)
├── team-members.json            # Actual config with passwords (gitignored)
├── scripts/
│   ├── infra-audit.sh           # Already exists from Phase 4
│   ├── run-production.sh        # NEW: Orchestration script
│   ├── ssh-tunnel.sh            # NEW: SSH tunnel start/stop helper
│   └── verify-backup.sh         # NEW: Backup verification over SSH
└── tests/
    ├── production/
    │   └── create-team-users.spec.ts  # NEW: Production user creation from config
    └── ... (existing test directories)
```

### Idempotent User Creation Pattern

The existing `UserManagementPage.userExists()` method checks if a user exists before creation. The production user creation test should follow this same pattern:

```typescript
for (const member of teamMembers.users.filter(u => u.role !== 'admin')) {
  const exists = await userMgmt.userExists(member.login);
  if (exists) {
    console.log(`User ${member.login} already exists — skipping`);
    continue;
  }
  await userMgmt.createUser(member.name, member.login, member.password, {
    groups: member.groups,
  });
}
```

### Two-Stage Execution Pattern

```
Stage 1 (Dry Run): npm run test:local → tests/smoke/ + tests/setup/
  - Verifies all tests pass against local Docker stack
  - Catches config mistakes before touching production

Stage 2 (Production): bash scripts/run-production.sh
  - Opens SSH tunnel
  - Runs smoke → infra audit → odoo audit → user creation → backup verify
  - Generates HTML report
```

### Backup Verification via SSH

```bash
# Trigger a manual backup
ssh -p 9292 deploy@$HOST "sudo /opt/odoo/scripts/06-backup-daily.sh"

# Check backup-status.json
ssh -p 9292 deploy@$HOST "cat /opt/odoo/backup-status.json" | jq '.status'
# Expected: 0 (OK)

# Check local backup files exist
ssh -p 9292 deploy@$HOST "ls -la /mnt/odoo-prod-data/backups/daily/odoo-db-$(date +%Y-%m-%d).dump"

# Trigger offsite sync
ssh -p 9292 deploy@$HOST "sudo /opt/odoo/scripts/07-sync-offsite.sh"

# Check sync-status.json
ssh -p 9292 deploy@$HOST "cat /opt/odoo/sync-status.json" | jq '.status'
# Expected: 0 (OK)
```

### Anti-Patterns to Avoid
- **Running workflow tests against production:** User decision explicitly says no. Workflow tests create throwaway data (leads, projects). Only smoke, audit, and user creation run against production.
- **Hitting the public URL directly:** All test traffic goes through the SSH tunnel. This is a locked decision.
- **Hardcoding user credentials in test files:** Users come from `team-members.json`. The Phase 4 `create-users.spec.ts` pattern (env var-based, test user cleanup) is for local staging only.
- **Attempting database restore on production:** Backup verification checks file existence and status codes, not restore. Locked decision.
- **Using port 443 locally for the tunnel:** Would require root. Use 8443 (or similar) and set `PROD_ODOO_URL=https://localhost:8443`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH tunnel management | Custom Node.js SSH client | ssh CLI + shell script | SSH is built-in, reliable, zero dependencies |
| JSON config parsing | Custom config parser | Node.js built-in JSON.parse | team-members.json is pure JSON; no library needed |
| User creation automation | New page objects or API calls | Existing `UserManagementPage` from Phase 4 | Already tested against Odoo 19 UI |
| Test orchestration | Complex Node.js test runner | Bash script calling `npx playwright test` | Matches project convention; simple conditional logic |
| Backup status checking | Custom monitoring | Read backup-status.json + sync-status.json | Phase 3 scripts already write Nagios-convention status files |

**Key insight:** Phase 5 is an integration/orchestration phase, not a build phase. The heavy lifting (page objects, test infrastructure, backup scripts) was done in Phases 2-4. Phase 5 wires them together and runs them against production.

## Common Pitfalls

### Pitfall 1: SSH Tunnel Port Conflicts
**What goes wrong:** Local port 8443 (or whatever is chosen) is already in use by another service, causing tunnel setup to fail silently or hang.
**Why it happens:** macOS can have services on various ports; re-running the script without cleaning up the previous tunnel leaves orphaned SSH processes.
**How to avoid:** Check if port is in use before opening tunnel. Kill any existing tunnel on that port first. Use `lsof -ti:<port>` to detect. The orchestration script should clean up tunnels on exit (trap EXIT).
**Warning signs:** "Address already in use" error, or Playwright connects but gets unexpected responses.

### Pitfall 2: SSL Certificate Mismatch Through Tunnel
**What goes wrong:** Playwright rejects the HTTPS connection because the SSL certificate is for `odoo.example.com` but the connection is to `localhost:8443`.
**Why it happens:** Let's Encrypt cert is issued for the domain, not localhost.
**How to avoid:** Set `ignoreHTTPSErrors: true` in the Playwright production project config. The HTTP headers audit tests still verify HSTS/headers because they read response headers, not the certificate chain.
**Warning signs:** `ERR_CERT_AUTHORITY_INVALID` or `NET::ERR_CERT_COMMON_NAME_INVALID` in test output.

### Pitfall 3: Setup Tests Running Against Production
**What goes wrong:** The `tests/setup/` directory (module install, throwaway test user creation/deletion) runs against the production system, potentially installing modules or creating/deleting users unintentionally.
**Why it happens:** Running `npx playwright test --project=production` without proper `testIgnore` patterns.
**How to avoid:** The existing `playwright.config.ts` already has `testIgnore: ['**/setup/**']` for the production project. The new `tests/production/` directory for real user creation is separate from `tests/setup/`. The orchestration script only runs specific test paths, not the full suite.
**Warning signs:** Test output showing "install CRM module" or "clean up: remove test user" during production run.

### Pitfall 4: Backup Verification Timing
**What goes wrong:** Offsite sync verification fails because rclone sync hasn't completed yet.
**Why it happens:** `06-backup-daily.sh` and `07-sync-offsite.sh` run sequentially via the orchestration script, but the sync to DO Spaces can take time depending on backup size and network speed.
**How to avoid:** Run backup and sync sequentially over SSH (not in background). Check sync-status.json after the sync script completes (it writes status on exit). The sync script already verifies files exist on the remote via `rclone ls`.
**Warning signs:** `sync-status.json` shows status 2, or `files_synced: 0`.

### Pitfall 5: Stale SSH Known Hosts
**What goes wrong:** SSH tunnel or infra audit fails with "Host key verification failed" if the droplet was rebuilt.
**Why it happens:** Rebuilding the droplet (terraform destroy + apply) generates new SSH host keys. The local `~/.ssh/known_hosts` has the old key.
**How to avoid:** The infra-audit.sh already uses `-o StrictHostKeyChecking=accept-new`. The tunnel script should use the same option. Alternatively, document the `ssh-keygen -R` step in the runbook.
**Warning signs:** "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED" in SSH output.

### Pitfall 6: team-members.json Committed to Git
**What goes wrong:** Real user passwords are pushed to the repository.
**Why it happens:** Forgetting to add team-members.json to .gitignore.
**How to avoid:** Add `team-members.json` to `.gitignore` in the same commit that creates `.json.example`. The orchestration script should check for the file's existence and fail with a helpful message if missing.
**Warning signs:** `git status` shows team-members.json as tracked.

## Code Examples

### SSH Tunnel Helper Script

```bash
#!/usr/bin/env bash
# ssh-tunnel.sh — Manage SSH tunnel to production Odoo
set -euo pipefail

ACTION="${1:-start}"
REMOTE_HOST="${INFRA_SSH_HOST:?INFRA_SSH_HOST not set}"
REMOTE_PORT="${INFRA_SSH_PORT:-9292}"
REMOTE_USER="${INFRA_SSH_USER:-deploy}"
LOCAL_PORT="${TUNNEL_LOCAL_PORT:-8443}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 -o ServerAliveCountMax=3"

case "$ACTION" in
  start)
    # Kill existing tunnel on this port
    lsof -ti:${LOCAL_PORT} | xargs kill 2>/dev/null || true
    sleep 1

    # Open tunnel: remote 443 -> local $LOCAL_PORT
    ssh -f -N -L ${LOCAL_PORT}:localhost:443 \
      -p ${REMOTE_PORT} ${SSH_OPTS} \
      ${REMOTE_USER}@${REMOTE_HOST}

    echo "SSH tunnel open: localhost:${LOCAL_PORT} -> ${REMOTE_HOST}:443"
    ;;
  stop)
    lsof -ti:${LOCAL_PORT} | xargs kill 2>/dev/null || true
    echo "SSH tunnel closed on port ${LOCAL_PORT}"
    ;;
esac
```

### Team Members Config Example

```json
{
  "users": [
    {
      "name": "Admin User",
      "login": "admin@company.com",
      "role": "admin",
      "note": "Admin password is set during Odoo initial setup, not managed here"
    },
    {
      "name": "Sarah Johnson",
      "login": "sarah@company.com",
      "password": "CHANGE_ME_unique_password_1",
      "role": "user",
      "groups": {
        "Sales": "User: Own Documents Only",
        "Project": "User"
      }
    },
    {
      "name": "Mike Chen",
      "login": "mike@company.com",
      "password": "CHANGE_ME_unique_password_2",
      "role": "user",
      "groups": {
        "Sales": "User: Own Documents Only",
        "Project": "User"
      }
    }
  ]
}
```

### Production User Creation Test Pattern

```typescript
// tests/production/create-team-users.spec.ts
import { test, expect } from '../../fixtures/auth.fixture.js';
import { UserManagementPage } from '../../pages/user-management.page.js';
import { LoginPage } from '../../pages/login.page.js';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

interface TeamMember {
  name: string;
  login: string;
  password?: string;
  role: 'admin' | 'user';
  groups?: Record<string, string>;
}

interface TeamConfig {
  users: TeamMember[];
}

// Load team members config
const configPath = resolve(__dirname, '../../team-members.json');
let teamConfig: TeamConfig;
try {
  teamConfig = JSON.parse(readFileSync(configPath, 'utf-8'));
} catch {
  throw new Error(`Cannot read ${configPath}. Copy team-members.json.example to team-members.json.`);
}

const regularUsers = teamConfig.users.filter(u => u.role === 'user');

test.describe.configure({ mode: 'serial' });

test.describe('Production team user setup', () => {
  for (const user of regularUsers) {
    test(`create user: ${user.name} (${user.login})`, async ({ adminPage }) => {
      test.slow();
      const userMgmt = new UserManagementPage(adminPage);

      const exists = await userMgmt.userExists(user.login);
      if (exists) {
        console.log(`User ${user.login} already exists — skipping`);
        return;
      }

      await userMgmt.createUser(user.name, user.login, user.password!, {
        groups: user.groups,
      });

      const created = await userMgmt.userExists(user.login);
      expect(created).toBe(true);
    });

    test(`verify login: ${user.name} (${user.login})`, async ({ browser }) => {
      const context = await browser.newContext();
      const page = await context.newPage();
      const loginPage = new LoginPage(page);

      await loginPage.goto();
      await loginPage.login(user.login, user.password!);

      await expect(page.locator('.o_main_navbar')).toBeVisible();
      await context.close();
    });
  }
});
```

### Orchestration Script Structure

```bash
#!/usr/bin/env bash
# run-production.sh — Production deployment verification
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ODOOKIT_DIR="$(dirname "$SCRIPT_DIR")"

# Source .env
source "${ODOOKIT_DIR}/.env"

# Cleanup on exit
trap 'bash "${SCRIPT_DIR}/ssh-tunnel.sh" stop' EXIT

# 1. Pre-flight
[[ -f "${ODOOKIT_DIR}/team-members.json" ]] || { echo "ERROR: team-members.json not found"; exit 1; }
[[ -n "${INFRA_SSH_HOST}" ]] || { echo "ERROR: INFRA_SSH_HOST not set"; exit 1; }

# 2. Open SSH tunnel
bash "${SCRIPT_DIR}/ssh-tunnel.sh" start
export PROD_ODOO_URL="https://localhost:${TUNNEL_LOCAL_PORT:-8443}"

# 3. Smoke tests (fail-fast)
echo "=== Stage 1: Smoke Tests ==="
cd "$ODOOKIT_DIR"
npx playwright test --project=production tests/smoke/ || { echo "SMOKE TESTS FAILED — aborting"; exit 1; }

# 4. Infrastructure audit (non-blocking)
echo "=== Stage 2: Infrastructure Audit ==="
bash "${SCRIPT_DIR}/infra-audit.sh" --host "${INFRA_SSH_HOST}" || echo "WARNING: Some infra checks failed"

# 5. Odoo audit (non-blocking)
echo "=== Stage 3: Odoo Audit ==="
npx playwright test --project=production tests/audit/ || echo "WARNING: Some audit checks failed"

# 6. User creation
echo "=== Stage 4: User Creation ==="
npx playwright test --project=production tests/production/ || echo "WARNING: Some user creation failed"

# 7. Backup verification (non-blocking)
echo "=== Stage 5: Backup Verification ==="
bash "${SCRIPT_DIR}/verify-backup.sh" || echo "WARNING: Backup verification issues"

echo "=== Production Verification Complete ==="
```

### Playwright Config Update for Production Tunnel

```typescript
// In playwright.config.ts, update the production project:
{
  name: 'production',
  use: {
    baseURL: process.env.PROD_ODOO_URL,
    ignoreHTTPSErrors: true,  // Required for SSH tunnel (cert is for domain, not localhost)
    ...devices['Desktop Chrome'],
  },
  testDir: './tests',
  testIgnore: ['**/setup/**'],  // Exclude local-only setup tests
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct SSH to production for verification | SSH tunnel + Playwright automation | Phase 4-5 design | Repeatable, automated verification vs manual spot-checks |
| Single admin account for everything | Config-driven multi-user provisioning | Phase 5 design | Proper RBAC, audit trail, real-world access patterns |
| Manual backup verification | Script-driven backup trigger + status file check | Phase 3 (status files) | Nagios-convention status files enable automated checking |

**Relevant to Phase 5:**
- Odoo 19 user management UI uses dropdown textboxes for role groups (verified in Phase 4 04-04)
- Direct URL navigation (`/odoo/settings/users`) works in Odoo 19 (verified in Phase 4)
- `UserManagementPage` page object handles the full user creation flow including password setting via Action menu (verified in Phase 4)

## Open Questions

1. **SSL certificate validation through tunnel**
   - What we know: `ignoreHTTPSErrors: true` suppresses Playwright's certificate check, allowing connection through the tunnel. HTTP header audit tests still read response headers correctly.
   - What's unclear: Whether the HTTP->HTTPS redirect test (`http://` to `https://` check) works through the tunnel, since both sides of the tunnel are on localhost.
   - Recommendation: The redirect test may need to be skipped when running through the tunnel (the redirect is already verified by the HTTP headers audit checking for HSTS). Alternatively, test the redirect directly via curl over SSH (`ssh deploy@host "curl -I http://localhost:8069"`).

2. **Tunnel local port selection**
   - What we know: 8443 is a common alternative HTTPS port, unlikely to conflict.
   - What's unclear: Whether any specific macOS service uses 8443 by default.
   - Recommendation: Use 8443 as default, make it configurable via `TUNNEL_LOCAL_PORT` env var. The tunnel script checks for port conflicts before starting.

3. **Production test timeout tuning**
   - What we know: Local tests use 60s timeout, 10s expect timeout.
   - What's unclear: How much latency the SSH tunnel adds. Production Odoo with 3 workers may respond differently than local single-process.
   - Recommendation: Increase production timeouts modestly (90s test timeout, 15s expect). The orchestration script can set these via Playwright CLI flags or a production-specific config override.

## Sources

### Primary (HIGH confidence)
- Phase 4 OdooKit codebase: `odookit/` directory -- all page objects, tests, helpers, config
- Phase 2 deployment scripts: `scripts/01-harden-host.sh` through `scripts/04-setup-nginx.sh`
- Phase 3 backup scripts: `scripts/06-backup-daily.sh`, `scripts/07-sync-offsite.sh`
- Playwright config: `odookit/playwright.config.ts` -- existing production project definition
- SSH hardening config: `config/sshd-hardening.conf` -- port 9292, deploy user
- Phase 5 CONTEXT.md: User decisions on scope, execution order, safety gates

### Secondary (MEDIUM confidence)
- SSH tunnel forwarding pattern: Standard OpenSSH `-L` flag behavior
- Playwright `ignoreHTTPSErrors`: Documented Playwright config option for self-signed/mismatched certs

### Tertiary (LOW confidence)
- None -- all findings are based on direct code inspection and standard tooling

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools already exist in the project or are system utilities
- Architecture: HIGH -- Patterns directly extend Phase 4 infrastructure; user decisions are specific and detailed
- Pitfalls: HIGH -- Based on direct analysis of existing code (SSL mismatch, port conflicts, testIgnore patterns)

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable -- no external dependency changes expected)
