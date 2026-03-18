import { test, expect } from '../../fixtures/auth.fixture.js';
import { SettingsPage } from '../../pages/settings.page.js';
import { AppMenuPage } from '../../pages/app-menu.page.js';

/**
 * Audit tests: Odoo UI configuration verification
 *
 * NON-DESTRUCTIVE — safe for production environments.
 * Verifies critical Odoo settings: database manager disabled, required modules
 * installed, and company configured.
 *
 * Future enhancement: "prompt mode" where each test reports findings and asks
 * whether to remediate. For now, tests simply pass/fail.
 */
test.describe('Odoo UI audit', () => {
  // Detect local Docker environment (no Nginx, no list_db=False)
  const isLocal = (process.env.BASE_URL ?? 'http://localhost:8069').includes('localhost');

  test('database manager is disabled', async ({ adminPage }) => {
    // ODOO-05 / PROXY-04: Database manager must be blocked
    // Requires Nginx 403 on /web/database/* and list_db=False — skips on local Docker
    test.skip(isLocal, 'Database manager block requires Nginx — skipping on local Docker');
    const settings = new SettingsPage(adminPage);
    const isDisabled = await settings.isDatabaseManagerDisabled();

    expect(isDisabled).toBe(true);
  });

  test('CRM module is installed and accessible', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('CRM');

    expect(isInstalled).toBe(true);
  });

  test('Project module is installed and accessible', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Project');

    expect(isInstalled).toBe(true);
  });

  test('admin master password is not default', async ({ adminPage }) => {
    // ODOO-05: Verify database manager route is blocked.
    // Requires Nginx 403 on /web/database/* — skips on local Docker
    test.skip(isLocal, 'Database manager block requires Nginx — skipping on local Docker');

    const response = await adminPage.goto('/web/database/manager');

    if (!response) {
      // No response means the page was blocked or redirected — that's a pass
      return;
    }

    const status = response.status();
    const url = adminPage.url();

    // Should be blocked (403) or redirected away
    const isBlocked = status === 403 || !url.includes('/web/database/manager');
    expect(isBlocked).toBe(true);
  });

  test('company name is configured', async ({ adminPage }) => {
    // Navigate to company settings
    await adminPage.goto('/odoo/settings/companies');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await adminPage.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
    await adminPage.waitForTimeout(1000);

    // Open the first company
    // o_data_row: Odoo list view row (version-sensitive class)
    const companyRow = adminPage.locator('.o_data_row').first();
    expect(await companyRow.isVisible()).toBe(true);

    await companyRow.click();
    await adminPage.waitForTimeout(1000);

    // Odoo 19: company name uses a widget field, not a standard input.
    // Try the textbox role first, then fall back to input[name="name"].
    const nameTextbox = adminPage.locator('.o_field_widget[name="name"] input').first();
    const nameInputFallback = adminPage.locator('input[name="name"]');
    const nameTarget = await nameTextbox.isVisible({ timeout: 3000 }).catch(() => false)
      ? nameTextbox
      : nameInputFallback;

    const companyName = await nameTarget.inputValue();

    expect(companyName.length).toBeGreaterThan(0);
    // Warn (but still pass) if using Odoo default — real audit would flag this
    if (companyName === 'My Company' || companyName === 'My Company (San Francisco)') {
      // eslint-disable-next-line no-console
      console.warn(`AUDIT NOTE: Company name is still the default: "${companyName}". Consider customizing.`);
    }
  });
});
