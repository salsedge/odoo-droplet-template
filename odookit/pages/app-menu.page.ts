import { type Page } from '@playwright/test';

/**
 * Odoo 19 App Menu — Application navigation
 *
 * In Odoo 19, `/odoo` goes to the Apps module store (not the home menu).
 * The home menu (app tiles) is accessed via the navbar toggle button.
 * This POM uses the home menu toggle or direct URL navigation as primary strategy.
 *
 * Known app URL mappings (version-sensitive):
 *   CRM      -> /odoo/crm
 *   Project  -> /odoo/project
 *   Settings -> /odoo/settings
 */

// Map of known app names to their Odoo 19 URL paths
// Map of known app names to their Odoo 19 URL paths.
// Only apps with confirmed clean URL routes belong here.
// Sales and Invoicing use action-based routing (no clean path) —
// they fall through to _isInHomeMenu / _openViaHomeMenu instead.
const APP_URL_MAP: Record<string, string> = {
  'CRM': '/odoo/crm',
  'Project': '/odoo/project',
  'Settings': '/odoo/settings',
  'Contacts': '/odoo/contacts',
  'Inventory': '/odoo/inventory',
  'Purchase': '/odoo/purchase',
};

export class AppMenuPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  /**
   * Open an Odoo application by name (e.g., "CRM", "Project", "Settings").
   * Uses direct URL navigation when possible (most reliable), falls back
   * to the home menu toggle button for unknown apps.
   */
  async openApp(appName: string): Promise<void> {
    const url = APP_URL_MAP[appName];

    if (url) {
      // Direct URL navigation — most reliable for known apps
      await this.page.goto(url);
    } else {
      // Fallback: open home menu via navbar toggle and click the app tile
      await this._openViaHomeMenu(appName);
    }

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible', timeout: 15000 });
  }

  /**
   * Check if an application is installed and accessible.
   * Navigates to the app's URL and checks if the view loads (not redirected to login or apps store).
   */
  async isAppInstalled(appName: string): Promise<boolean> {
    const url = APP_URL_MAP[appName];

    if (url) {
      // Navigate to the app URL — if installed, the view controller loads
      const response = await this.page.goto(url);
      if (!response) return false;

      // If redirected to /odoo/apps or the apps store, the module is not installed
      const currentUrl = this.page.url();
      if (currentUrl.includes('/odoo/apps') || currentUrl.includes('/web/login')) {
        return false;
      }

      // Check that the view controller actually loaded (confirms the app is functional)
      try {
        await this.page.locator('.o_action_manager .o_view_controller').waitFor({
          state: 'visible',
          timeout: 5000,
        });
        return true;
      } catch {
        return false;
      }
    }

    // Unknown app — try home menu approach
    return this._isInHomeMenu(appName);
  }

  /**
   * Open an app via the home menu toggle button in the navbar.
   * o_menu_toggle: Odoo 19 home menu button (version-sensitive class)
   */
  private async _openViaHomeMenu(appName: string): Promise<void> {
    // Click the home/hamburger button in the navbar to show the app menu
    const homeButton = this.page.locator('.o_menu_toggle, .o_navbar_apps_menu button').first();
    await homeButton.click();
    await this.page.waitForTimeout(500);

    // Look for the app in the home menu
    const appItem = this.page.getByRole('menuitem', { name: appName });
    const fallback = this.page.locator('.o_apps .o_app, .o_home_menu .o_app', { hasText: appName });

    const target = await appItem.isVisible({ timeout: 3000 }).catch(() => false)
      ? appItem
      : fallback;

    await target.click();
  }

  /**
   * Check if an app is visible in the home menu.
   */
  private async _isInHomeMenu(appName: string): Promise<boolean> {
    // Click the home/hamburger button
    const homeButton = this.page.locator('.o_menu_toggle, .o_navbar_apps_menu button').first();
    try {
      await homeButton.click({ timeout: 3000 });
      await this.page.waitForTimeout(500);

      const appItem = this.page.getByRole('menuitem', { name: appName });
      const fallback = this.page.locator('.o_apps .o_app, .o_home_menu .o_app', { hasText: appName });

      return (
        await appItem.isVisible({ timeout: 2000 }).catch(() => false) ||
        await fallback.isVisible({ timeout: 2000 }).catch(() => false)
      );
    } catch {
      return false;
    }
  }
}
