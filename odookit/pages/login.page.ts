import { type Locator, type Page } from '@playwright/test';

/**
 * Odoo 19 Login Page — /web/login
 *
 * Selectors from Odoo 19 webclient_templates.xml:
 * - form.oe_login_form
 * - input[name="login"] (type="text", autocomplete="username")
 * - input[name="password"] (type="password", autocomplete="current-password")
 * - .oe_login_form button[type="submit"] (class="btn btn-primary")
 */
export class LoginPage {
  readonly page: Page;
  readonly loginInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.loginInput = page.locator('input[name="login"]');
    this.passwordInput = page.locator('input[name="password"]');
    this.submitButton = page.locator('.oe_login_form button[type="submit"]');
  }

  /** Navigate to the login page. */
  async goto(): Promise<void> {
    await this.page.goto('/web/login');
  }

  /**
   * Fill credentials and submit the login form.
   * Waits for the Odoo main navbar to confirm successful login.
   */
  async login(email: string, password: string): Promise<void> {
    await this.loginInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
    // o_main_navbar: Odoo 19 top navigation bar (version-sensitive class)
    await this.page.locator('.o_main_navbar').waitFor({ state: 'visible' });
  }

  /**
   * Check if the user is currently logged in by testing navbar visibility.
   */
  async isLoggedIn(): Promise<boolean> {
    // o_main_navbar: Odoo 19 top navigation bar (version-sensitive class)
    return this.page.locator('.o_main_navbar').isVisible();
  }
}
