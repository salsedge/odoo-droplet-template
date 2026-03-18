import { type Page } from '@playwright/test';
import { AppMenuPage } from './app-menu.page.js';

/**
 * Odoo 19 Project Module — Project and task management
 *
 * Methods cover: project creation, task creation with optional assignment,
 * navigation, and stage changes.
 */
export class ProjectPage {
  readonly page: Page;
  readonly appMenu: AppMenuPage;

  constructor(page: Page) {
    this.page = page;
    this.appMenu = new AppMenuPage(page);
  }

  /** Navigate to the Project module via the app menu. */
  async openProjects(): Promise<void> {
    await this.appMenu.openApp('Project');
  }

  /**
   * Create a new project.
   * Clicks "New" in the project list/kanban, fills the name, and confirms.
   */
  async createProject(name: string): Promise<void> {
    await this.page.getByRole('button', { name: 'New' }).click();

    // The project creation may be a quick-create input or a dialog
    const nameInput = this.page.locator('input[name="name"]').first();
    await nameInput.fill(name);

    // Wait for any onchange responses
    await this.page.waitForTimeout(500);

    // Try to confirm — could be a dialog button or form save
    const createButton = this.page.getByRole('button', { name: 'Create' });
    if (await createButton.isVisible({ timeout: 1000 }).catch(() => false)) {
      await createButton.click();
    } else {
      // o_form_button_save: Odoo form save button (version-sensitive class)
      const saveButton = this.page.locator('.o_form_button_save');
      if (await saveButton.isVisible()) {
        await saveButton.click();
      }
    }

    await this.page.waitForTimeout(1000);
  }

  /**
   * Open an existing project by name from the project list/kanban.
   */
  async openProject(name: string): Promise<void> {
    await this.page.getByText(name, { exact: false }).first().click();
    // Wait for the view controller to load the project's tasks
    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
  }

  /**
   * Create a task within a project.
   * Opens the project first, then creates a new task.
   */
  async createTask(projectName: string, taskName: string, options?: { assignee?: string }): Promise<void> {
    await this.openProject(projectName);

    // Click "New" to create a task (may be quick-create in kanban or form-based)
    await this.page.getByRole('button', { name: 'New' }).click();
    await this.page.waitForTimeout(500);

    // Fill task name — could be a kanban quick-create input or a form field
    const nameInput = this.page.locator('input[name="name"], input[name="display_name"]').first();
    await nameInput.fill(taskName);
    await this.page.waitForTimeout(300);

    // Press Enter to confirm quick-create, or the input triggers a form
    await nameInput.press('Enter');
    await this.page.waitForTimeout(500);

    // If assignee is specified, open the task and set it
    if (options?.assignee) {
      await this.openTask(taskName);

      // Many2many assignee field — type the user name and select from dropdown
      const assigneeInput = this.page.locator('.o_field_many2many[name="user_ids"] input, input[name="user_ids"]').first();
      if (await assigneeInput.isVisible({ timeout: 2000 }).catch(() => false)) {
        await assigneeInput.fill(options.assignee);
        await this.page.waitForTimeout(500);
        // Select first dropdown result
        // ui-autocomplete: jQuery UI autocomplete dropdown (version-sensitive class)
        await this.page.locator('.ui-autocomplete .ui-menu-item, .o_m2o_dropdown_option').first().click();
        await this.page.waitForTimeout(500);
      }

      // Save the form
      // o_form_button_save: Odoo form save button (version-sensitive class)
      const saveButton = this.page.locator('.o_form_button_save');
      if (await saveButton.isVisible()) {
        await saveButton.click();
      }
      await this.page.waitForTimeout(500);
    }
  }

  /**
   * Open an existing task by name from the task kanban/list view.
   */
  async openTask(taskName: string): Promise<void> {
    await this.page.getByText(taskName, { exact: false }).first().click();
    // o_form_view: Odoo form view container (version-sensitive class)
    await this.page.locator('.o_form_view').waitFor({ state: 'visible' });
  }

  /**
   * Change the stage of the currently open task via the status bar.
   */
  async setTaskStage(stageName: string): Promise<void> {
    // o_statusbar_status: Odoo status bar with stage buttons (version-sensitive class)
    const stageButton = this.page.locator('.o_statusbar_status button', { hasText: stageName });
    await stageButton.click();
    await this.page.waitForTimeout(1000);
  }
}
