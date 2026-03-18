import { type Page } from '@playwright/test';

/**
 * Odoo 19 User Management — User CRUD via the Settings > Users UI
 *
 * Methods for creating, deleting, and checking user existence through
 * the Odoo web interface.
 */
export class UserManagementPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  /**
   * Navigate to Settings > Users & Companies > Users.
   */
  async openUsers(): Promise<void> {
    await this.page.goto('/odoo/settings/users');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
  }

  /**
   * Create a new user via the Odoo UI form.
   *
   * @param name - Display name for the user
   * @param login - Email/login for the user
   * @param password - Password to set (via the "Change Password" action)
   * @param options.groups - Optional list of group names to assign
   */
  async createUser(
    name: string,
    login: string,
    password: string,
    options?: { groups?: string[] }
  ): Promise<void> {
    await this.openUsers();

    // Click "New" to create a user
    await this.page.getByRole('button', { name: 'New' }).click();
    await this.page.waitForTimeout(500);

    // Fill the user name
    await this.page.locator('input[name="name"]').fill(name);
    await this.page.waitForTimeout(300);

    // Fill the login/email
    await this.page.locator('input[name="login"]').fill(login);
    await this.page.waitForTimeout(500);

    // Handle group assignments if specified
    if (options?.groups) {
      for (const group of options.groups) {
        // Groups are typically selection fields or checkboxes in the Access Rights tab
        const groupOption = this.page.getByText(group, { exact: false });
        if (await groupOption.isVisible({ timeout: 2000 }).catch(() => false)) {
          await groupOption.click();
          await this.page.waitForTimeout(300);
        }
      }
    }

    // Save the user form
    // o_form_button_save: Odoo form save button (version-sensitive class)
    const saveButton = this.page.locator('.o_form_button_save');
    if (await saveButton.isVisible()) {
      await saveButton.click();
    }
    await this.page.waitForTimeout(1000);

    // Set the password via the action menu
    await this.page.getByRole('button', { name: 'Action' }).click();
    await this.page.waitForTimeout(300);
    await this.page.getByText('Change Password').click();
    await this.page.waitForTimeout(500);

    // Fill the new password in the dialog
    // o_dialog: Odoo dialog container (version-sensitive class)
    const dialog = this.page.locator('.o_dialog');
    const passwordInput = dialog.locator('input[name="new_passwd"], input[type="password"]').first();
    await passwordInput.fill(password);

    // Confirm the password change
    await dialog.getByRole('button', { name: 'Change Password' }).click();
    await this.page.waitForTimeout(1000);
  }

  /**
   * Archive (soft-delete) a user by login email.
   */
  async deleteUser(login: string): Promise<void> {
    await this.openUsers();

    // Find and click the user in the list
    await this.page.getByText(login, { exact: false }).first().click();
    // o_form_view: Odoo form view container (version-sensitive class)
    await this.page.locator('.o_form_view').waitFor({ state: 'visible' });

    // Archive via Action menu
    await this.page.getByRole('button', { name: 'Action' }).click();
    await this.page.waitForTimeout(300);
    await this.page.getByText('Archive').click();

    // Confirm the archive dialog
    // o_dialog: Odoo dialog container (version-sensitive class)
    const dialog = this.page.locator('.o_dialog');
    if (await dialog.isVisible({ timeout: 2000 }).catch(() => false)) {
      await dialog.getByRole('button', { name: 'OK' }).click();
    }

    await this.page.waitForTimeout(1000);
  }

  /**
   * Check if a user with the given login exists in the users list.
   */
  async userExists(login: string): Promise<boolean> {
    await this.openUsers();

    // Search for the user by login
    const searchInput = this.page.locator('.o_searchview_input');
    await searchInput.fill(login);
    await searchInput.press('Enter');
    await this.page.waitForTimeout(1000);

    // Check if any result matches
    const userRow = this.page.getByText(login, { exact: false });
    return userRow.isVisible({ timeout: 2000 }).catch(() => false);
  }
}
