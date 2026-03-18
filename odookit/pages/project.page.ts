import { type Page } from '@playwright/test';
import { AppMenuPage } from './app-menu.page.js';
import { dismissNotifications } from '../helpers/dismiss-notifications.js';

/**
 * Odoo 19 Project Module -- Project and task management
 *
 * Methods cover: project creation, task creation with optional assignment,
 * navigation, and stage changes.
 *
 * Odoo 19 project creation uses a dialog ("Create a Project") with:
 *   - Name field (placeholder "e.g. Office Party")
 *   - "Create project" / "Discard" buttons
 *
 * Task creation in kanban uses quick-create with a name input and Enter to confirm.
 */
export class ProjectPage {
  readonly page: Page;
  readonly appMenu: AppMenuPage;

  constructor(page: Page) {
    this.page = page;
    this.appMenu = new AppMenuPage(page);
  }

  /** Navigate to the Project module via direct URL. */
  async openProjects(): Promise<void> {
    await this.appMenu.openApp('Project');
  }

  /**
   * Create a new project.
   * Odoo 19 shows a "Create a Project" dialog after clicking "New".
   */
  async createProject(name: string): Promise<void> {
    await this.page.getByRole('button', { name: 'New' }).click();
    await this.page.waitForTimeout(500);

    // Odoo 19: "Create a Project" dialog with Name field
    // Try the dialog Name textbox first
    const dialogNameField = this.page.getByRole('textbox', { name: /name/i });
    const fallbackInput = this.page.locator('input[name="name"]').first();

    const nameTarget = await dialogNameField.isVisible({ timeout: 3000 }).catch(() => false)
      ? dialogNameField
      : fallbackInput;

    await nameTarget.fill(name);
    await this.page.waitForTimeout(500);

    // Click "Create project" button (Odoo 19 dialog) or "Create" or save
    const createProjectBtn = this.page.getByRole('button', { name: /create project/i });
    const createBtn = this.page.getByRole('button', { name: 'Create' });
    const saveBtn = this.page.locator('.o_form_button_save');

    if (await createProjectBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await createProjectBtn.click();
    } else if (await createBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
      await createBtn.click();
    } else if (await saveBtn.isVisible()) {
      await saveBtn.click();
    }

    await this.page.waitForTimeout(1000);
  }

  /**
   * Open an existing project by name from the project list/kanban.
   */
  async openProject(name: string): Promise<void> {
    // Wait for projects to load
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible', timeout: 10000 });
    await this.page.waitForTimeout(500);

    // Dismiss notification banners that can intercept clicks
    await dismissNotifications(this.page);

    await this.page.getByText(name, { exact: false }).first().click({ force: true });
    // Wait for the view controller to load the project's tasks
    await this.page.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible', timeout: 10000 });
    await this.page.waitForTimeout(500);
  }

  /**
   * Create a task within a project.
   * Opens the project first, then creates a new task via kanban quick-create.
   */
  async createTask(projectName: string, taskName: string, options?: { assignee?: string }): Promise<void> {
    await this.openProject(projectName);

    // Click "New" or the quick-add button to create a task
    const newBtn = this.page.getByRole('button', { name: 'New' });
    await newBtn.click();
    await this.page.waitForTimeout(500);

    // Fill task name -- Odoo 19 may open a full form view with "Task Title..." placeholder
    // or a kanban quick-create input
    const formTitleField = this.page.getByRole('textbox', { name: /task title/i });
    const nameInput = this.page.getByRole('textbox', { name: /name/i }).first();
    const fallbackInput = this.page.locator('input[name="name"], input[name="display_name"]').first();

    let nameTarget;
    if (await formTitleField.isVisible({ timeout: 3000 }).catch(() => false)) {
      nameTarget = formTitleField;
    } else if (await nameInput.isVisible({ timeout: 2000 }).catch(() => false)) {
      nameTarget = nameInput;
    } else {
      nameTarget = fallbackInput;
    }

    await nameTarget.fill(taskName);
    await this.page.waitForTimeout(300);

    // In form view: save via the save button or keyboard shortcut
    // In kanban quick-create: press Enter or click Add
    const saveManually = this.page.getByRole('button', { name: 'Save manually' });
    const addBtn = this.page.getByRole('button', { name: 'Add' });
    const saveBtn = this.page.locator('.o_form_button_save');

    if (await saveManually.isVisible({ timeout: 1000 }).catch(() => false)) {
      await saveManually.click();
    } else if (await addBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
      await addBtn.click();
    } else if (await saveBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
      await saveBtn.click();
    } else {
      await nameTarget.press('Enter');
    }
    await this.page.waitForTimeout(500);

    // If assignee is specified, open the task and set it
    if (options?.assignee) {
      await this.openTask(taskName);

      const assigneeInput = this.page.locator('.o_field_many2many[name="user_ids"] input, input[name="user_ids"]').first();
      if (await assigneeInput.isVisible({ timeout: 2000 }).catch(() => false)) {
        await assigneeInput.fill(options.assignee);
        await this.page.waitForTimeout(500);
        await this.page.locator('.o-autocomplete--dropdown-item, .o_m2o_dropdown_option, .ui-menu-item').first().click();
        await this.page.waitForTimeout(500);
      }

      const saveBtn = this.page.locator('.o_form_button_save');
      if (await saveBtn.isVisible()) {
        await saveBtn.click();
      }
      await this.page.waitForTimeout(500);
    }
  }

  /**
   * Open an existing task by name from the task kanban/list view.
   */
  async openTask(taskName: string): Promise<void> {
    await dismissNotifications(this.page);
    await this.page.getByText(taskName, { exact: false }).first().click({ force: true });
    // o_form_view: Odoo form view container (version-sensitive class)
    await this.page.locator('.o_form_view').waitFor({ state: 'visible', timeout: 10000 });
  }

  /**
   * Change the stage of the currently open task via the stage dropdown.
   *
   * Odoo 19 project tasks use a dropdown button for stage selection
   * (not CRM-style status bar buttons). The current stage is shown as
   * a button inside the form view; clicking it reveals a dropdown
   * with all available stages.
   */
  async setTaskStage(stageName: string): Promise<void> {
    await dismissNotifications(this.page);

    // Odoo 19 project tasks: try the status bar buttons first (CRM-style)
    const statusBarButton = this.page.locator('.o_statusbar_status button', { hasText: stageName });
    if (await statusBarButton.isVisible({ timeout: 2000 }).catch(() => false)) {
      await statusBarButton.click({ force: true });
      await this.page.waitForTimeout(1000);
      return;
    }

    // Odoo 19 project tasks: the stage dropdown button is inside the form
    // sheet content area, next to the task title and priority stars.
    // Use the main content area locator to avoid matching control panel buttons.
    const mainContent = this.page.locator('main .o_form_view, .o_form_view .o_form_sheet_bg');
    const stageBtn = mainContent.locator('button').filter({ hasText: /in progress|done|cancelled|changes requested|approved|new/i }).first();

    const target = stageBtn;

    await target.click();
    await this.page.waitForTimeout(500);

    // Select the desired stage from the dropdown menu
    const stageOption = this.page.getByRole('menuitem', { name: stageName });
    const dropdownItem = this.page.locator('.dropdown-menu .dropdown-item, .o-dropdown--menu .dropdown-item', { hasText: stageName });

    if (await stageOption.isVisible({ timeout: 2000 }).catch(() => false)) {
      await stageOption.click();
    } else if (await dropdownItem.first().isVisible({ timeout: 2000 }).catch(() => false)) {
      await dropdownItem.first().click();
    } else {
      // Fallback: click text inside form view only (not control panel)
      await this.page.locator('.o_form_view').getByText(stageName, { exact: true }).first().click();
    }

    await this.page.waitForTimeout(1000);
  }
}
