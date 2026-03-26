# UBOP Foundation Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend OdooKit and the Odoo production deployment to support the UBOP foundation: install Sales + Invoicing modules, enable custom addon deployment, configure team users, and verify end-to-end.

**Architecture:** OdooKit's existing Playwright-based setup/audit tests are extended with two new modules (Sales, Invoicing). The Docker Compose stack gains a custom-addons volume mount and an `addons_path` directive in odoo.conf. A new `make deploy-addon` target handles the SCP + restart lifecycle. All verification tests expand from 2-module to 4-module checks.

**Tech Stack:** Playwright (TypeScript, ES modules), Docker Compose, Odoo 19, Nginx, Bash, Make

**Spec:** `docs/ubop-foundation-setup.md`

---

## Scope Note

This plan covers the **infra and OdooKit changes in the `odoo-19.x-build` repo only**. The `ubop-lite` repo (source of `loodon_proposals` module) is not modified. Manual Odoo UI configuration (sales defaults, payment terms, project templates) is documented but not automated.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `odookit/tests/setup/install-modules.spec.ts` | Add Sales + Invoicing install tests |
| Modify | `odookit/tests/smoke/modules.spec.ts` | Add Sales + Invoicing smoke checks |
| Modify | `odookit/tests/audit/odoo-ui-audit.spec.ts` | Add Sales + Invoicing audit checks |
| Modify | `config/docker-compose.yml` | Add custom-addons volume mount |
| Modify | `config/odoo.conf` | Add `addons_path` with custom addons directory |
| Create | `scripts/ops/deploy-addon.sh` | SCP module to droplet, fix ownership, restart Odoo |
| Modify | `Makefile` | Add `deploy-addon` target |
| Modify | `docs/ubop-foundation-setup.md` | Update with actual Make commands, fix prerequisite gap |

---

## Task 1: Add Sales and Invoicing to Module Installation Tests

**Files:**
- Modify: `odookit/tests/setup/install-modules.spec.ts`

- [ ] **Step 1: Add Sales module installation test**

Add after the "install Project module" test (line 60), before the verification test:

```typescript
  test('install Sales module', async ({ adminPage }) => {
    test.slow();

    const settings = new SettingsPage(adminPage);

    const alreadyInstalled = await settings.isModuleInstalled('Sales');
    if (alreadyInstalled) {
      // eslint-disable-next-line no-console
      console.log('Sales module already installed — skipping installation');
      return;
    }

    await settings.installModule('Sales');
    await adminPage.waitForTimeout(5000);

    const isInstalled = await settings.isModuleInstalled('Sales');
    expect(isInstalled).toBe(true);
  });

  test('install Invoicing module', async ({ adminPage }) => {
    test.slow();

    const settings = new SettingsPage(adminPage);

    const alreadyInstalled = await settings.isModuleInstalled('Invoicing');
    if (alreadyInstalled) {
      // eslint-disable-next-line no-console
      console.log('Invoicing module already installed — skipping installation');
      return;
    }

    await settings.installModule('Invoicing');
    await adminPage.waitForTimeout(5000);

    const isInstalled = await settings.isModuleInstalled('Invoicing');
    expect(isInstalled).toBe(true);
  });
```

- [ ] **Step 2: Update the verification test to check all 4 modules**

Replace the existing "verify both modules appear in app menu" test (lines 62-70) with:

```typescript
  test('verify all modules appear in app menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);

    for (const app of ['CRM', 'Sales', 'Project', 'Invoicing']) {
      const installed = await appMenu.isAppInstalled(app);
      expect(installed, `${app} should appear in app menu`).toBe(true);
    }
  });
```

- [ ] **Step 3: Commit**

```bash
git add odookit/tests/setup/install-modules.spec.ts
git commit -m "feat(odookit): add Sales and Invoicing module installation tests"
```

---

## Task 2: Add Sales and Invoicing to Smoke Tests

**Files:**
- Modify: `odookit/tests/smoke/modules.spec.ts`

- [ ] **Step 1: Add smoke checks for Sales and Invoicing**

Add after the existing "Project module is installed" test, before the CRM app accessibility test:

```typescript
  test('Sales module is installed', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Sales');
    expect(isInstalled).toBe(true);
  });

  test('Invoicing module is installed', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Invoicing');
    expect(isInstalled).toBe(true);
  });
```

Add after the existing "Project app is accessible from menu" test:

```typescript
  test('Sales app is accessible from menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);
    const isAvailable = await appMenu.isAppInstalled('Sales');
    expect(isAvailable).toBe(true);
  });

  test('Invoicing app is accessible from menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);
    const isAvailable = await appMenu.isAppInstalled('Invoicing');
    expect(isAvailable).toBe(true);
  });
```

- [ ] **Step 2: Commit**

```bash
git add odookit/tests/smoke/modules.spec.ts
git commit -m "feat(odookit): add Sales and Invoicing smoke tests"
```

---

## Task 3: Add Sales and Invoicing to Audit Tests

**Files:**
- Modify: `odookit/tests/audit/odoo-ui-audit.spec.ts`

- [ ] **Step 1: Add audit checks for Sales and Invoicing**

Add after the "Project module is installed and accessible" test:

```typescript
  test('Sales module is installed and accessible', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Sales');

    expect(isInstalled).toBe(true);
  });

  test('Invoicing module is installed and accessible', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Invoicing');

    expect(isInstalled).toBe(true);
  });
```

- [ ] **Step 2: Commit**

```bash
git add odookit/tests/audit/odoo-ui-audit.spec.ts
git commit -m "feat(odookit): add Sales and Invoicing audit checks"
```

---

## Task 4: Add Custom Addons Volume Mount to Docker Compose

The current `config/docker-compose.yml` has no custom-addons directory. The `loodon_proposals` module (and any future custom modules) need a host directory mapped into the container plus an `addons_path` in odoo.conf.

**Files:**
- Modify: `config/docker-compose.yml`
- Modify: `config/odoo.conf`
- Modify: `scripts/03-deploy-stack.sh`

- [ ] **Step 1: Add custom-addons volume to docker-compose.yml**

In the `odoo` service `volumes:` section (after line 78), add:

```yaml
      - /opt/odoo/custom-addons:/mnt/extra-addons:ro
```

The full `volumes:` block for the `odoo` service becomes:

```yaml
    volumes:
      - /mnt/odoo-prod-data/odoo-filestore:/var/lib/odoo
      - ./odoo.conf:/etc/odoo/odoo.conf:ro
      - /opt/odoo/custom-addons:/mnt/extra-addons:ro
```

- [ ] **Step 2: Add addons_path to odoo.conf**

Add after the `data_dir = /var/lib/odoo` line (line 24) in `config/odoo.conf`:

```ini
; Custom addons path — host-mounted at /opt/odoo/custom-addons
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
```

Note: Custom addons path is listed first so custom modules take precedence. This is also forward-compatible with the enterprise migration path documented in `docs/enterprise-migration.md`, where enterprise modules in `/mnt/extra-addons` need to override their community counterparts.

- [ ] **Step 3: Create custom-addons directory in deploy script**

In `scripts/03-deploy-stack.sh`, add after the existing `mkdir -p` calls for data directories (around line 73):

```bash
# Custom addons directory (mounted into Odoo container at /mnt/extra-addons)
mkdir -p "${DEPLOY_DIR}/custom-addons"
chown -R 100:101 "${DEPLOY_DIR}/custom-addons"
```

- [ ] **Step 4: Commit**

```bash
git add config/docker-compose.yml config/odoo.conf scripts/03-deploy-stack.sh
git commit -m "feat: add custom-addons volume mount for Odoo modules

Adds /opt/odoo/custom-addons host directory mapped to /mnt/extra-addons
in the Odoo container. Sets addons_path in odoo.conf to include both
built-in and custom addon directories."
```

---

## Task 5: Create deploy-addon Operational Script and Makefile Target

**Files:**
- Create: `scripts/ops/deploy-addon.sh`
- Modify: `Makefile`

- [ ] **Step 1: Create deploy-addon.sh**

```bash
#!/usr/bin/env bash
# =============================================================================
# deploy-addon.sh — Deploy a Custom Odoo Module (Operational)
# =============================================================================
# Copies a local Odoo module directory to the droplet's custom-addons path,
# fixes ownership for the Odoo container (uid 100, gid 101), and restarts
# Odoo to detect the new/updated module.
#
# After running this script, install the module via the Odoo UI:
#   1. Settings -> Developer Tools -> Activate Developer Mode
#   2. Apps -> Update Apps List -> Update
#   3. Search for the module name -> Install
#
# Usage:
#   sudo bash scripts/ops/deploy-addon.sh <module-path>
#
# Example:
#   sudo bash scripts/ops/deploy-addon.sh /opt/odoo/custom-addons/loodon_proposals
#
# This script runs ON THE DROPLET. Use `make deploy-addon` from your local
# machine to handle the SCP + remote execution.
# =============================================================================

set -euo pipefail

CUSTOM_ADDONS_DIR="/opt/odoo/custom-addons"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <module-name>" >&2
  echo "  Expects the module to already be in ${CUSTOM_ADDONS_DIR}/<module-name>" >&2
  exit 1
fi

MODULE_NAME="$1"
MODULE_PATH="${CUSTOM_ADDONS_DIR}/${MODULE_NAME}"

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (or via sudo)" >&2
  exit 1
fi

# Verify module exists
if [[ ! -d "$MODULE_PATH" ]]; then
  echo "ERROR: Module not found at ${MODULE_PATH}" >&2
  echo "  SCP the module first: scp -P 9292 -r /path/to/module deploy@host:${CUSTOM_ADDONS_DIR}/" >&2
  exit 1
fi

# Verify __manifest__.py exists (valid Odoo module)
if [[ ! -f "${MODULE_PATH}/__manifest__.py" ]]; then
  echo "ERROR: ${MODULE_PATH}/__manifest__.py not found — not a valid Odoo module" >&2
  exit 1
fi

echo "=== Deploy Addon: ${MODULE_NAME} ==="

# Fix ownership — Odoo container runs as uid 100, gid 101
echo "[1/3] Setting ownership (100:101)..."
chown -R 100:101 "${MODULE_PATH}"
echo "  OK"

# Restart Odoo to detect new/updated module
echo "[2/3] Restarting Odoo..."
docker restart odoo-app > /dev/null
echo "  OK"

# Wait for health check
echo "[3/3] Waiting for Odoo health check..."
for i in $(seq 1 30); do
  if curl -fsS http://localhost:8069/web/health > /dev/null 2>&1; then
    echo "  Odoo is healthy"
    break
  fi
  if [[ "$i" -eq 30 ]]; then
    echo "  WARNING: Odoo did not pass health check within 60s" >&2
    echo "  Check logs: docker logs odoo-app --tail 50" >&2
    exit 1
  fi
  sleep 2
done

echo ""
echo "=== Module ${MODULE_NAME} deployed ==="
echo ""
echo "Next steps — install via Odoo UI:"
echo "  1. Log in to https://portal.loodon.com/web"
echo "  2. Settings -> Developer Tools -> Activate Developer Mode"
echo "  3. Apps -> Update Apps List -> Update"
echo "  4. Search for '${MODULE_NAME}' -> Install"
```

Make executable:
```bash
chmod +x scripts/ops/deploy-addon.sh
```

- [ ] **Step 2: Add Makefile variables and target**

Add `ADDON_PATH` variable in the Configuration section (after `ALIAS_DOMAIN`):

```makefile
ADDON_PATH   ?=
```

Add the `deploy-addon` target in the Operations section (after `set-domain`):

```makefile
.PHONY: deploy-addon
deploy-addon: upload ## Deploy custom Odoo module (requires ADDON_PATH=local/path/to/module)
	@[ -n "$(DROPLET_IP)" ] || { echo "ERROR: DROPLET_IP not set"; exit 1; }
	@[ -n "$(ADDON_PATH)" ] || { echo "ERROR: ADDON_PATH not set (e.g., make deploy-addon ADDON_PATH=../ubop-lite/odoo_modules/loodon_proposals)"; exit 1; }
	@[ -d "$(ADDON_PATH)" ] || { echo "ERROR: $(ADDON_PATH) is not a directory"; exit 1; }
	@echo "Uploading $(ADDON_PATH) to droplet..."
	$(SCP_CMD) -r $(ADDON_PATH) $(SSH_USER)@$(DROPLET_IP):/opt/odoo/custom-addons/
	@echo "Running deploy-addon.sh on droplet..."
	$(SSH_CMD) "sudo bash /tmp/odoo-setup/scripts/ops/deploy-addon.sh $$(basename $(ADDON_PATH))"
```

Note: The `deploy-addon` target depends on `upload` (ensuring ops scripts are on the droplet), then SCP's the module directly to `/opt/odoo/custom-addons/`, and calls the remote script for ownership fix + restart.

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck scripts/ops/deploy-addon.sh
```

Expected: clean (exit 0).

- [ ] **Step 4: Commit**

```bash
git add scripts/ops/deploy-addon.sh Makefile
git commit -m "feat: add make deploy-addon for custom Odoo module deployment

New operational script (scripts/ops/deploy-addon.sh) handles ownership
fix and Odoo restart after SCP. Makefile target handles the full
local-to-droplet lifecycle."
```

---

## Task 6: Update team-members.json.example for UBOP Users

**Files:**
- Modify: `odookit/team-members.json.example`

- [ ] **Step 1: Update example with UBOP-appropriate groups**

Replace the existing users array with Loodon-specific examples that include Sales and Invoicing groups:

```json
{
  "_comment": [
    "Copy this file to team-members.json and update with real values:",
    "  cp team-members.json.example team-members.json",
    "",
    "The admin user entry is for reference only -- the admin password is set",
    "during initial Odoo setup and is not managed by this config file.",
    "",
    "Each non-admin user needs a unique password. Share passwords with users",
    "securely out-of-band (not via email or chat).",
    "",
    "Password safety: avoid these characters in passwords:",
    "  $  (dollar sign)     -- interpreted as variable reference",
    "  `  (backtick)        -- interpreted as command substitution",
    "  \"  (double quote)    -- breaks quoting",
    "  '  (single quote)    -- breaks quoting",
    "  \\  (backslash)       -- interpreted as escape character",
    "Use only alphanumeric characters and safe symbols: - _ . @ # % ^ & * + ="
  ],
  "users": [
    {
      "name": "Admin User",
      "login": "admin@loodon.com",
      "role": "admin",
      "note": "Admin password is set during Odoo initial setup, not managed here"
    },
    {
      "name": "Jane Smith",
      "login": "jane@loodon.com",
      "password": "CHANGE_ME_unique_password_1",
      "role": "user",
      "groups": {
        "Sales": "User: All Documents",
        "Project": "User",
        "Invoicing": "Invoicing"
      }
    },
    {
      "name": "John Doe",
      "login": "john@loodon.com",
      "password": "CHANGE_ME_unique_password_2",
      "role": "user",
      "groups": {
        "Sales": "User: All Documents",
        "Project": "User",
        "Invoicing": "Invoicing"
      }
    }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add odookit/team-members.json.example
git commit -m "docs(odookit): update team-members example with UBOP groups

Adds Invoicing group to example users, updates domain to loodon.com,
and aligns with the 4-module UBOP stack (CRM, Sales, Project, Invoicing)."
```

---

## Task 7: Update ubop-foundation-setup.md

**Files:**
- Modify: `docs/ubop-foundation-setup.md`

- [ ] **Step 1: Fix the custom-addons prerequisite gap**

The doc's Phase 2 assumes `/opt/odoo/custom-addons/` exists on the droplet, but it doesn't without Task 4's changes. Update Phase 2 to reference `make deploy-addon`:

Replace the manual SCP + chown + restart steps in Phase 2 (lines 109-123) with:

```markdown
### Steps

**Prerequisite:** Task 4 of the implementation plan must be applied first — the
Docker Compose stack needs the custom-addons volume mount. After applying, restart
the stack on the droplet:

\```bash
ssh -p 9292 deploy@45.55.164.120
cd /opt/odoo
sudo docker compose pull && sudo docker compose up -d
\```

**Deploy the module:**

\```bash
make deploy-addon ADDON_PATH=../ubop-lite/odoo_modules/loodon_proposals
\```

This SCP's the module, fixes ownership, and restarts Odoo. Then in the Odoo UI:
1. Settings -> Developer Tools -> Activate Developer Mode
2. Apps -> Update Apps List -> Update
3. Search for "Loodon Proposals" -> Install
```

- [ ] **Step 2: Fix UID/GID in Phase 2**

The spec says `101:101` on line 116 but the Odoo 19 Docker image runs as uid `100`, gid `101`. The deploy scripts (`03-deploy-stack.sh`) already use `100:101`. Fix line 116 of the spec:

Change:
```
  "sudo chown -R 101:101 /opt/odoo/custom-addons/loodon_proposals"
```

To:
```
  "sudo chown -R 100:101 /opt/odoo/custom-addons/loodon_proposals"
```

- [ ] **Step 3: Update Phase 1 to reference `make` commands**

Update the "Run" section (line 94-99) to be specific about production targeting:

```markdown
### Run

For local testing:
\```bash
cd odookit
npm run setup:local
\```

For production (via SSH tunnel):
\```bash
cd odookit
npm run test:prod -- --grep "Module installation"
\```
```

- [ ] **Step 4: Commit**

```bash
git add docs/ubop-foundation-setup.md
git commit -m "docs: fix custom-addons gap, UID/GID, and add make targets to UBOP setup"
```

---

## Task 8: Apply Custom-Addons Changes to Live Droplet

This task applies the docker-compose.yml and odoo.conf changes from Task 4 to the running production droplet. This is an operational step, not a code change.

**Prerequisites:** Tasks 4 and 5 committed and uploaded to droplet.

- [ ] **Step 1: Upload updated config to droplet**

```bash
make upload
```

- [ ] **Step 2: SSH to droplet and apply changes**

```bash
make ssh
```

On the droplet:

```bash
# Create the custom-addons directory
sudo mkdir -p /opt/odoo/custom-addons
sudo chown -R 100:101 /opt/odoo/custom-addons

# Copy updated docker-compose.yml and odoo.conf
sudo cp /tmp/odoo-setup/config/docker-compose.yml /opt/odoo/docker-compose.yml
sudo cp /tmp/odoo-setup/config/odoo.conf /opt/odoo/odoo.conf

# Re-inject credentials into odoo.conf (the file was just overwritten with placeholders)
# Read credentials from existing .env
ODOO_ADMIN_PASSWORD=$(grep '^ODOO_ADMIN_PASSWORD=' /opt/odoo/.env | cut -d= -f2-)
POSTGRES_USER=$(grep '^POSTGRES_USER=' /opt/odoo/.env | cut -d= -f2-)
POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' /opt/odoo/.env | cut -d= -f2-)
POSTGRES_DB=$(grep '^POSTGRES_DB=' /opt/odoo/.env | cut -d= -f2-)

sudo awk \
  -v admin_pwd="${ODOO_ADMIN_PASSWORD}" \
  -v db_user="${POSTGRES_USER}" \
  -v db_pwd="${POSTGRES_PASSWORD}" \
  -v db_name="${POSTGRES_DB}" \
  '{
    gsub(/ADMIN_PASSWORD_PLACEHOLDER/, admin_pwd)
    gsub(/DB_USER_PLACEHOLDER/, db_user)
    gsub(/DB_PASSWORD_PLACEHOLDER/, db_pwd)
    gsub(/DB_NAME_PLACEHOLDER/, db_name)
    print
  }' /opt/odoo/odoo.conf > /opt/odoo/odoo.conf.tmp \
  && sudo mv /opt/odoo/odoo.conf.tmp /opt/odoo/odoo.conf

# Restart the stack to pick up the new volume mount and addons_path
cd /opt/odoo
sudo docker compose up -d --force-recreate
```

- [ ] **Step 3: Verify Odoo comes back up**

```bash
# Wait for health
curl -fsS http://localhost:8069/web/health

# Verify the custom-addons mount is visible inside the container
sudo docker exec odoo-app ls -la /mnt/extra-addons/

# Should show an empty directory (no modules deployed yet)
```

- [ ] **Step 4: Exit droplet and run smoke tests from local**

```bash
cd odookit
npm run test:smoke
```

---

## Execution Order

Tasks 1-3 (OdooKit test changes) are independent of each other and can be done in parallel.

Task 4 (Docker Compose + odoo.conf) must be done before Task 5 (deploy-addon script) and Task 8 (live apply).

Task 5 depends on Task 4 (the custom-addons directory must exist).

Task 6 (team-members example) is independent.

Task 7 (doc update) depends on Tasks 4 and 5 being defined.

Task 8 (live apply) depends on Tasks 4 and 5 being committed.

```
Tasks 1, 2, 3, 6  (parallel — independent OdooKit + doc changes)
      ↓
Task 4             (Docker Compose + odoo.conf infra)
      ↓
Tasks 5, 7         (parallel — deploy-addon script + doc update)
      ↓
Task 8             (live apply to droplet)
```

---

## Out of Scope (Manual Steps After Plan)

These are documented in `docs/ubop-foundation-setup.md` but not automated:

1. **Deploy `loodon_proposals`** — `make deploy-addon ADDON_PATH=../ubop-lite/odoo_modules/loodon_proposals` then install via Odoo UI
2. **Configure `team-members.json`** — copy example, fill real names/emails/passwords
3. **Run user provisioning** — `make verify-prod` or run create-team-users directly
4. **Sales defaults** — quotation validity, payment terms (Odoo UI)
5. **Project template** — stages and template project (Odoo UI)
6. **Company settings** — name, address, logo (Odoo UI or OdooKit system-settings test)
7. **Manual E2E walkthrough** — lead → quotation → proposal → invoice flow
