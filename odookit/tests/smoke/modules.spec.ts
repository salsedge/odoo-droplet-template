import { test, expect } from '../../fixtures/auth.fixture.js';
import { SettingsPage } from '../../pages/settings.page.js';
import { AppMenuPage } from '../../pages/app-menu.page.js';

/**
 * Smoke tests: Module installation verification
 *
 * Non-destructive — safe for production and local environments.
 * Verifies CRM and Project modules are installed (ODOO-02).
 * Uses adminPage fixture for authenticated access.
 */
test.describe('Module installation smoke tests', () => {

  test('CRM module is installed', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('CRM');
    expect(isInstalled).toBe(true);
  });

  test('Project module is installed', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    const isInstalled = await settings.isModuleInstalled('Project');
    expect(isInstalled).toBe(true);
  });

  test('CRM app is accessible from menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);
    const isAvailable = await appMenu.isAppInstalled('CRM');
    expect(isAvailable).toBe(true);
  });

  test('Project app is accessible from menu', async ({ adminPage }) => {
    const appMenu = new AppMenuPage(adminPage);
    const isAvailable = await appMenu.isAppInstalled('Project');
    expect(isAvailable).toBe(true);
  });
});
