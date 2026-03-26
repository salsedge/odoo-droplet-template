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
    options?: { groups?: Record<string, string> }
  ): Promise<void> {
    await this.openUsers();

    // Click "New" to create a user
    await this.page.getByRole('button', { name: 'New' }).click();
    await this.page.waitForTimeout(1000);

    // Wait for the form to load
    await this.page.locator('.o_form_view').waitFor({ state: 'visible', timeout: 10000 });

    // Odoo 19 user form: name is a textbox with placeholder "e.g. John Doe"
    // Login is a textbox labeled "Login" (version-sensitive)
    const nameField = this.page.getByRole('textbox', { name: /john doe/i });
    const nameFieldFallback = this.page.locator('.o_field_widget[name="name"] input, input[name="name"]').first();
    const nameTarget = await nameField.isVisible({ timeout: 2000 }).catch(() => false) ? nameField : nameFieldFallback;
    await nameTarget.fill(name);
    await this.page.waitForTimeout(300);

    // Fill the login/email
    const loginField = this.page.getByRole('textbox', { name: 'Login' });
    const loginFieldFallback = this.page.locator('.o_field_widget[name="login"] input, input[name="login"]').first();
    const loginTarget = await loginField.isVisible({ timeout: 2000 }).catch(() => false) ? loginField : loginFieldFallback;
    await loginTarget.fill(login);
    await this.page.waitForTimeout(500);

    // Handle group assignments if specified
    if (options?.groups) {
      await this._setGroups(options.groups);
    }

    // Save the user form via the save button
    // Odoo 19 uses "Save manually" button in the control panel
    const saveManually = this.page.getByRole('button', { name: 'Save manually' });
    const saveButton = this.page.locator('.o_form_button_save');
    const saveTarget = await saveManually.isVisible({ timeout: 2000 }).catch(() => false)
      ? saveManually
      : saveButton;

    if (await saveTarget.isVisible({ timeout: 2000 }).catch(() => false)) {
      await saveTarget.click();
    }
    await this.page.waitForTimeout(2000);

    // Set the password via the action menu
    const actionsMenu = this.page.getByRole('button', { name: 'Actions menu' });
    const actionButton = this.page.getByRole('button', { name: 'Action' });
    const actionTarget = await actionsMenu.isVisible({ timeout: 2000 }).catch(() => false)
      ? actionsMenu
      : actionButton;

    await actionTarget.click();
    await this.page.waitForTimeout(300);
    await this.page.getByText('Change Password').click();
    await this.page.waitForTimeout(500);

    // Fill the new password in the dialog
    // Target the Change Password dialog specifically (not the notification banner)
    const dialog = this.page.getByRole('dialog').filter({ hasText: 'Change Password' });
    await dialog.waitFor({ state: 'visible', timeout: 5000 });

    // Odoo 19 Change Password dialog uses an editable list/table:
    // Row contains: [User Login cell] [New Password cell (click to edit)]
    // Click the password cell to activate the input, then fill it
    const passwordCell = dialog.getByRole('row', { name: new RegExp(login.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')) }).getByRole('cell').nth(1);
    await passwordCell.click();
    await this.page.waitForTimeout(300);

    // After clicking, an input should appear in the cell
    const passwordInput = dialog.locator('input[name="new_passwd"], input.o_field_widget, td.o_data_cell input, input[type="text"]').first();
    await passwordInput.fill(password);
    await this.page.waitForTimeout(300);

    // Confirm the password change
    const changeBtn = dialog.getByRole('button', { name: 'Change Password' });
    await changeBtn.click();
    await this.page.waitForTimeout(1000);
  }

  /**
   * Update group assignments for an existing user.
   * Opens the user form by login, sets groups to match the provided config, and saves.
   * Idempotent — safe to call with the same groups repeatedly.
   *
   * @param login - Email/login of the existing user
   * @param groups - Group assignments e.g. { "Sales": "Administrator", "Invoicing": "Billing Administrator" }
   */
  async updateUserGroups(login: string, groups: Record<string, string>): Promise<void> {
    await this.openUsers();

    // Search for the user
    const searchInput = this.page.locator('.o_searchview_input');
    await searchInput.fill(login);
    await searchInput.press('Enter');
    await this.page.waitForTimeout(2000);

    // Click into the user form
    const userRow = this.page.locator('.o_data_row', { hasText: login });
    if (!(await userRow.isVisible({ timeout: 3000 }).catch(() => false))) {
      throw new Error(`User ${login} not found — cannot update groups`);
    }
    await userRow.click();
    await this.page.locator('.o_form_view').waitFor({ state: 'visible', timeout: 10000 });

    // Set groups
    await this._setGroups(groups);

    // Save
    const saveManually = this.page.getByRole('button', { name: 'Save manually' });
    const saveButton = this.page.locator('.o_form_button_save');
    const saveTarget = await saveManually.isVisible({ timeout: 2000 }).catch(() => false)
      ? saveManually
      : saveButton;

    if (await saveTarget.isVisible({ timeout: 2000 }).catch(() => false)) {
      await saveTarget.click();
    }
    await this.page.waitForTimeout(2000);
  }

  /**
   * Set group dropdown values on the currently open user form.
   * Reused by both createUser and updateUserGroups.
   *
   * Odoo 19 uses dropdown textbox fields for role groups
   * (e.g., Sales: "No" -> "User: Own Documents Only")
   * Groups format: { fieldLabel: optionText }
   */
  private async _setGroups(groups: Record<string, string>): Promise<void> {
    for (const [fieldLabel, optionText] of Object.entries(groups)) {
      // Find the dropdown for this field (e.g., the "Sales?" textbox)
      const dropdown = this.page.getByRole('textbox', { name: new RegExp(fieldLabel, 'i') });
      if (await dropdown.isVisible({ timeout: 2000 }).catch(() => false)) {
        await dropdown.click();
        await this.page.waitForTimeout(300);

        // Clear existing value and type the option
        await dropdown.fill('');
        await this.page.waitForTimeout(200);
        await dropdown.fill(optionText);
        await this.page.waitForTimeout(500);

        // Select from the autocomplete dropdown
        const autocompleteOption = this.page.locator('.o-autocomplete--dropdown-item, .o_m2o_dropdown_option, .ui-menu-item').filter({ hasText: optionText }).first();
        if (await autocompleteOption.isVisible({ timeout: 3000 }).catch(() => false)) {
          await autocompleteOption.click();
        } else {
          // Try pressing Enter to select the first match
          await dropdown.press('Enter');
        }
        await this.page.waitForTimeout(300);
      }
    }
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
   * Uses the data rows in the list view (not search input text) to avoid false positives.
   */
  async userExists(login: string): Promise<boolean> {
    await this.openUsers();

    // Search for the user by login
    const searchInput = this.page.locator('.o_searchview_input');
    await searchInput.fill(login);
    await searchInput.press('Enter');
    await this.page.waitForTimeout(2000);

    // Check if any data row in the list contains this login
    // o_data_row: Odoo list view row (version-sensitive class)
    // Only check within data rows, not the search input itself
    const userRow = this.page.locator('.o_data_row', { hasText: login });
    return userRow.isVisible({ timeout: 3000 }).catch(() => false);
  }
}
