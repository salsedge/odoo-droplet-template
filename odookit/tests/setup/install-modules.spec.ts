import { test, expect } from '../../fixtures/auth.fixture.js';
import { SettingsPage } from '../../pages/settings.page.js';
import { AppMenuPage } from '../../pages/app-menu.page.js';

/**
 * Setup tests: Module installation
 *
 * DESTRUCTIVE — modifies Odoo state by installing modules.
 * Excluded from production project via testIgnore pattern in playwright.config.ts.
 *
 * Serial execution required — module installation triggers server reload.
 */
test.describe.configure({ mode: 'serial' });

test.describe('Module installation', () => {
  test('install CRM module', async ({ adminPage }) => {
    // Module installation can take 30-60s
    test.slow();

    const settings = new SettingsPage(adminPage);

    // Check if already installed to make test idempotent
    const alreadyInstalled = await settings.isModuleInstalled('CRM');
    if (alreadyInstalled) {
      // eslint-disable-next-line no-console
      console.log('CRM module already installed — skipping installation');
      return;
    }

    await settings.installModule('CRM');

    // After module install, Odoo may reload — wait for page to stabilize
    // Re-authenticate if the session was lost during reload
    await adminPage.waitForTimeout(5000);

    // Verify by navigating to apps and checking installed list
    const isInstalled = await settings.isModuleInstalled('CRM');
    expect(isInstalled).toBe(true);
  });

  test('install Project module', async ({ adminPage }) => {
    // Module installation can take 30-60s
    test.slow();

    const settings = new SettingsPage(adminPage);

    const alreadyInstalled = await settings.isModuleInstalled('Project');
    if (alreadyInstalled) {
      // eslint-disable-next-line no-console
      console.log('Project module already installed — skipping installation');
      return;
    }

    await settings.installModule('Project');

    await adminPage.waitForTimeout(5000);

    const isInstalled = await settings.isModuleInstalled('Project');
    expect(isInstalled).toBe(true);
  });

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

  test('verify all modules appear in app menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);

    for (const app of ['CRM', 'Sales', 'Project', 'Invoicing']) {
      const installed = await appMenu.isAppInstalled(app);
      expect(installed, `${app} should appear in app menu`).toBe(true);
    }
  });
});
