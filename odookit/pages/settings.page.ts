import { type Page } from '@playwright/test';
import { AppMenuPage } from './app-menu.page.js';

/**
 * Odoo 19 Settings Page — System configuration and module management
 *
 * Methods for verifying system settings, checking module installation status,
 * and installing modules via the Apps interface.
 */
export class SettingsPage {
  readonly page: Page;
  readonly appMenu: AppMenuPage;

  constructor(page: Page) {
    this.page = page;
    this.appMenu = new AppMenuPage(page);
  }

  /** Navigate to the Settings app. */
  async openSettings(): Promise<void> {
    await this.appMenu.openApp('Settings');
  }

  /**
   * Check that the database manager is not accessible.
   * Navigates to /web/database/manager and expects a redirect or 403.
   * Returns true if the database manager is properly disabled.
   */
  async isDatabaseManagerDisabled(): Promise<boolean> {
    const response = await this.page.goto('/web/database/manager');

    if (!response) return false;

    // Database manager should redirect to login or return 403
    const status = response.status();
    const url = this.page.url();

    // Disabled if: 403 forbidden, or redirected away from the manager page
    return status === 403 || !url.includes('/web/database/manager');
  }

  /**
   * Get a list of installed module names from the Apps page.
   * Navigates to Apps and filters by "Installed" status.
   */
  async getInstalledModules(): Promise<string[]> {
    await this.page.goto('/odoo/apps/modules');

    // Wait for the module list to load
    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });

    // Filter by installed modules
    await this.page.getByRole('button', { name: 'Filters' }).click();
    await this.page.getByText('Installed', { exact: true }).click();
    await this.page.waitForTimeout(1000);

    // Collect module names from the list/kanban
    // o_kanban_record: Odoo kanban record card (version-sensitive class)
    const moduleCards = this.page.locator('.o_kanban_record .oe_module_name, .o_kanban_record .o_module_name');
    const names: string[] = [];
    const count = await moduleCards.count();

    for (let i = 0; i < count; i++) {
      const text = await moduleCards.nth(i).textContent();
      if (text) names.push(text.trim());
    }

    return names;
  }

  /**
   * Check if a specific module is installed.
   */
  async isModuleInstalled(moduleName: string): Promise<boolean> {
    const installed = await this.getInstalledModules();
    return installed.some(name =>
      name.toLowerCase().includes(moduleName.toLowerCase())
    );
  }

  /**
   * Install a module by name from the Apps list.
   * Searches for the module, clicks Install, and waits for completion.
   */
  async installModule(moduleName: string): Promise<void> {
    await this.page.goto('/odoo/apps/modules');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });

    // Search for the module
    const searchInput = this.page.locator('.o_searchview_input');
    await searchInput.fill(moduleName);
    await searchInput.press('Enter');
    await this.page.waitForTimeout(1000);

    // Find the module card and click Install
    // o_kanban_record: Odoo kanban card (version-sensitive class)
    const moduleCard = this.page.locator('.o_kanban_record', { hasText: moduleName }).first();
    const installButton = moduleCard.getByRole('button', { name: 'Install' });

    if (await installButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await installButton.click();

      // Module installation can take a while — wait for page reload/refresh
      // The page typically reloads after installation
      await this.page.waitForTimeout(10000);
      await this.page.locator('.o_action_manager').waitFor({ state: 'visible', timeout: 60000 });
    }
  }
}
