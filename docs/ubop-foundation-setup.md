# UBOP Foundation Setup via OdooKit

**Date:** 2026-03-26
**Status:** Ready to execute
**Requested by:** UBOP project (ubop-lite)
**Depends on:** portal.loodon.com domain setup (see `portal-domain-setup.md`)

---

## Summary

Use OdooKit to automate the UBOP foundation build Tasks 8 and 10: install core Odoo modules, deploy the custom `loodon_proposals` module, configure users/roles, and verify the system end-to-end.

This replaces manual Odoo UI work with OdooKit's Playwright-based setup tests and production provisioning.

## Prerequisites

- `portal.loodon.com` is live (or `odoo.loodon.com` until domain cutover)
- SSH access: `ssh -p 9292 deploy@45.55.164.120`
- OdooKit installed: `cd odookit && npm install`
- OdooKit `.env` configured with admin credentials
- `team-members.json` configured with the 3 Loodon users

---

## Phase 1: Install Core Modules (Task 8, Step 1)

### What to install

| Module | Odoo Technical Name | OdooKit Module Name |
|--------|-------------------|-------------------|
| CRM | `crm` | `CRM` |
| Sales | `sale_management` | `Sales` |
| Project | `project` | `Project` |
| Invoicing | `account` | `Invoicing` |

Contacts (`contacts`) auto-installs with CRM.

### Approach: Extend `install-modules.spec.ts`

The existing `tests/setup/install-modules.spec.ts` installs CRM and Project. It needs to be extended to also install Sales and Invoicing.

Add two new test cases to `tests/setup/install-modules.spec.ts`:

```typescript
test('install Sales module', async ({ adminPage }) => {
  test.slow();
  const settings = new SettingsPage(adminPage);

  const alreadyInstalled = await settings.isModuleInstalled('Sales');
  if (alreadyInstalled) {
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
    console.log('Invoicing module already installed — skipping installation');
    return;
  }

  await settings.installModule('Invoicing');
  await adminPage.waitForTimeout(5000);

  const isInstalled = await settings.isModuleInstalled('Invoicing');
  expect(isInstalled).toBe(true);
});
```

Update the final verification test to check all 4 modules:

```typescript
test('verify all modules appear in app menu', async ({ adminPage }) => {
  const appMenu = new AppMenuPage(adminPage);

  for (const app of ['CRM', 'Sales', 'Project', 'Invoicing']) {
    const installed = await appMenu.isAppInstalled(app);
    expect(installed, `${app} should be installed`).toBe(true);
  }
});
```

### Run

For local testing:
```bash
cd odookit
npm run setup:local
```

For production (via SSH tunnel):
```bash
cd odookit
npm run test:prod -- --grep "Module installation"
```

---

## Phase 2: Deploy `loodon_proposals` Custom Module (Task 8, Steps 2-6)

This is not automatable via OdooKit — it requires SCP + Docker restart + Odoo module install.

### Prerequisites

The Docker Compose stack needs the custom-addons volume mount (`/opt/odoo/custom-addons` -> `/mnt/extra-addons`). This was added in the `config/docker-compose.yml` and `config/odoo.conf` changes. If not yet applied to the droplet, upload and apply first:

```bash
make upload
make ssh
# On the droplet: see Task 8 of the implementation plan for apply steps
```

### Deploy the module

```bash
make deploy-addon ADDON_PATH=../ubop-lite/odoo_modules/loodon_proposals
```

This uploads the module to `/opt/odoo/custom-addons/`, fixes ownership (uid 100, gid 101), and restarts Odoo. Then in the Odoo UI:
1. Settings -> Developer Tools -> Activate Developer Mode
2. Apps -> Update Apps List -> Update
3. Search for "Loodon Proposals" -> Install

### Verification (can be added to OdooKit audit)

After installation, verify via the Odoo UI or add a new audit test:

```typescript
// tests/audit/custom-modules.spec.ts (new file)
test('loodon_proposals module is installed', async ({ adminPage }) => {
  const settings = new SettingsPage(adminPage);
  const isInstalled = await settings.isModuleInstalled('Loodon Proposals');
  expect(isInstalled).toBe(true);
});

test('Proposal tab visible on sale order form', async ({ adminPage }) => {
  await adminPage.goto('/odoo/sales/quotations/new');
  await adminPage.locator('.o_form_view').waitFor({ state: 'visible' });

  const proposalTab = adminPage.getByRole('tab', { name: 'Proposal' });
  await expect(proposalTab).toBeVisible();
});
```

---

## Phase 3: Configure Users and Roles (Task 10, Steps 1-2)

### `team-members.json`

Configure the 3 Loodon users. Copy and edit:

```bash
cd odookit
cp team-members.json.example team-members.json
```

Edit `team-members.json` with the actual users:

```json
{
  "users": [
    {
      "name": "Admin User",
      "login": "admin@loodon.com",
      "role": "admin",
      "note": "Admin password set during initial Odoo setup"
    },
    {
      "name": "User 2 Name",
      "login": "user2@loodon.com",
      "password": "CHANGE_ME",
      "role": "user",
      "groups": {
        "Sales": "User: All Documents",
        "Project": "User",
        "Invoicing": "Invoicing"
      }
    },
    {
      "name": "User 3 Name",
      "login": "user3@loodon.com",
      "password": "CHANGE_ME",
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

Adjust names, emails, passwords, and group assignments per user's actual role. If a user should be Sales Manager rather than Sales User, change `"Sales": "User: All Documents"` to `"Sales": "Administrator"`.

### Run user provisioning

```bash
# Via production verification (includes user creation as stage 4)
make verify-prod

# Or directly via Playwright
npx playwright test tests/production/create-team-users.spec.ts --project=production
```

This is idempotent — existing users are skipped.

---

## Phase 4: Configure System Settings (Task 10, Steps 3-6)

### Company settings (Step 1)

The existing `tests/setup/system-settings.spec.ts` handles company name configuration. Update it to set the company name to "Loodon" instead of "OdooKit Test Company":

In the `configure company name` test, change:

```typescript
await targetInput.fill('Loodon');
```

Or configure manually via the Odoo UI: Settings -> Companies -> update name, address, logo.

### Sales defaults (Step 3)

Manual via Odoo UI — not currently automatable via OdooKit:
- Sales -> Configuration -> Settings -> Default quotation validity: 30 days

### Payment terms (Step 4)

Manual via Odoo UI:
- Invoicing -> Configuration -> Payment Terms
- Create: Net 15, Net 30, Due on Receipt

### Project template (Step 5)

Manual via Odoo UI:
- Project -> Configuration -> Stages: Kickoff, In Progress, Review, Complete
- Create project: "Client Onboarding Template"

### Potential OdooKit automation

A new `tests/setup/ubop-config.spec.ts` could automate the above settings if needed. The SettingsPage and navigation patterns already exist — it's a matter of writing the specific field interactions for Sales/Invoicing configuration pages.

---

## Phase 5: End-to-End Verification

### Smoke tests

```bash
npm run test:smoke
```

Verifies: health endpoint, login page, database manager blocked, core modules installed.

### Full production verification

```bash
make verify-prod
```

Runs all 5 stages: smoke, infra audit, Odoo audit, user creation, backup verification.

### Manual E2E test (Task 10, Step 6)

Walk through the full flow in the Odoo UI:
1. CRM: Create lead -> move through pipeline stages
2. Sales: Create quotation from opportunity -> add products -> fill Proposal tab -> print PDF
3. Test all 3 proposal styles (modern, classic, minimal)
4. Confirm quotation -> sale order -> create invoice
5. Project: Create project, assign tasks

### Potential OdooKit E2E automation

The existing `tests/workflows/crm-lead.spec.ts` and `project-task.spec.ts` can be extended to cover the full lead-to-invoice flow. A new `tests/workflows/proposal-pdf.spec.ts` could verify proposal generation — though PDF content verification via Playwright is limited to checking the download succeeds.

---

## Execution Order

| Step | What | How | Automated? |
|------|------|-----|-----------|
| 1 | Install core modules | OdooKit `install-modules.spec.ts` (extended) | Yes |
| 2 | Deploy `loodon_proposals` | SCP + Docker restart + UI install | Partially |
| 3 | Configure company | OdooKit `system-settings.spec.ts` or manual | Yes |
| 4 | Create users | OdooKit `create-team-users.spec.ts` | Yes |
| 5 | Configure sales/invoicing | Manual Odoo UI | No |
| 6 | Create project template | Manual Odoo UI | No |
| 7 | Run smoke tests | `npm run test:smoke` | Yes |
| 8 | Run full verification | `make verify-prod` | Yes |
| 9 | Manual E2E walkthrough | Odoo UI | No |
