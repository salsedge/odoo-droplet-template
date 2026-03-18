import { type Page } from '@playwright/test';

/**
 * Odoo 19 App Menu — Home menu / app launcher
 *
 * Provides navigation to Odoo applications via the home menu or navbar.
 * Uses role-based and text locators as primary strategy, falling back
 * to Odoo-specific classes where necessary.
 */
export class AppMenuPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  /**
   * Open an Odoo application by name (e.g., "CRM", "Project", "Settings").
   * Navigates to the home menu first, then clicks the app tile.
   * Waits for the view controller to load after clicking.
   */
  async openApp(appName: string): Promise<void> {
    // Navigate to home menu to see all app tiles
    await this.page.goto('/odoo');

    // Primary: role-based locator for the app menu item
    const appItem = this.page.getByRole('menuitem', { name: appName });

    // Fallback: if menuitem role isn't found, try the home menu link by text
    // o_apps: Odoo home menu container (version-sensitive class)
    const fallback = this.page.locator('.o_apps .o_app', { hasText: appName });

    const target = await appItem.isVisible() ? appItem : fallback;
    await target.click();

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
  }

  /**
   * Check if an application is installed by looking for its tile in the home menu.
   */
  async isAppInstalled(appName: string): Promise<boolean> {
    await this.page.goto('/odoo');

    const appItem = this.page.getByRole('menuitem', { name: appName });
    // o_apps .o_app: Odoo home menu app tile (version-sensitive classes)
    const fallback = this.page.locator('.o_apps .o_app', { hasText: appName });

    return (await appItem.isVisible()) || (await fallback.isVisible());
  }
}
