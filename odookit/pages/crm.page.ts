import { type Page, expect } from '@playwright/test';
import { AppMenuPage } from './app-menu.page.js';
import { dismissNotifications } from '../helpers/dismiss-notifications.js';

/**
 * Odoo 19 CRM Module -- Lead/opportunity management
 *
 * Methods cover the CRM lead lifecycle: create, open, stage changes, won/lost.
 * Uses form-based stage changes (more reliable than kanban drag-and-drop).
 *
 * Odoo 19 CRM quick-create uses a kanban card with:
 *   - textbox "Opportunity's Name" (not input[name="name"])
 *   - textbox "Contact Email"
 *   - combobox "Contact"
 *   - "Add" button to save quick-create
 *   - "Edit" button to open full form
 */
export class CRMPage {
  readonly page: Page;
  readonly appMenu: AppMenuPage;

  constructor(page: Page) {
    this.page = page;
    this.appMenu = new AppMenuPage(page);
  }

  /** Navigate to the CRM module via direct URL. */
  async openCRM(): Promise<void> {
    await this.appMenu.openApp('CRM');
  }

  /**
   * Create a new CRM lead/opportunity.
   * Odoo 19 uses a kanban quick-create form, then opens the full form for details.
   */
  async createLead(name: string, options?: { contactName?: string; email?: string }): Promise<void> {
    // Dismiss notification banners before interacting
    await dismissNotifications(this.page);

    // Click the "New" button to open quick-create in kanban (or full form in list view)
    // Use force:true to bypass any remaining overlays
    await this.page.getByRole('button', { name: 'New' }).click({ force: true });
    await this.page.waitForTimeout(1000);

    // Dismiss any new notifications that appeared
    await dismissNotifications(this.page);

    // Fill the opportunity name — Odoo 19 may show:
    // 1. Kanban quick-create with textbox "Opportunity's Name"
    // 2. Full form view with textbox "e.g. Product Pricing" (name placeholder)
    // 3. Standard input[name="name"]
    const nameField = this.page.getByRole('textbox', { name: /opportunity/i });
    const formNameField = this.page.getByRole('textbox', { name: /product pricing/i });
    const widgetInput = this.page.locator('.o_field_widget[name="name"] input').first();
    const nameFieldFallback = this.page.locator('input[name="name"]');

    let nameTarget;
    if (await nameField.isVisible({ timeout: 3000 }).catch(() => false)) {
      nameTarget = nameField;
    } else if (await formNameField.isVisible({ timeout: 2000 }).catch(() => false)) {
      nameTarget = formNameField;
    } else if (await widgetInput.isVisible({ timeout: 2000 }).catch(() => false)) {
      nameTarget = widgetInput;
    } else {
      nameTarget = nameFieldFallback;
    }
    await nameTarget.fill(name);
    await this.page.waitForTimeout(300);

    if (options?.email) {
      const emailField = this.page.getByRole('textbox', { name: /contact email/i });
      const emailFallback = this.page.locator('input[name="email_from"]');
      const emailTarget = await emailField.isVisible({ timeout: 2000 }).catch(() => false) ? emailField : emailFallback;
      await emailTarget.fill(options.email);
      await this.page.waitForTimeout(300);
    }

    if (options?.contactName) {
      const contactField = this.page.getByRole('combobox', { name: /contact/i });
      const contactFallback = this.page.locator('input[name="contact_name"]');
      const contactTarget = await contactField.isVisible({ timeout: 2000 }).catch(() => false) ? contactField : contactFallback;
      await contactTarget.fill(options.contactName);
      await this.page.waitForTimeout(300);
    }

    // Click "Edit" to open the full form view (instead of "Add" which saves and stays in kanban)
    const editButton = this.page.getByRole('button', { name: 'Edit' });
    const addButton = this.page.getByRole('button', { name: 'Add' });

    if (await editButton.isVisible({ timeout: 2000 }).catch(() => false)) {
      await editButton.click();
    } else if (await addButton.isVisible({ timeout: 2000 }).catch(() => false)) {
      await addButton.click();
    }

    // Wait for the form view to load
    await this.page.waitForTimeout(2000);
    // Wait for either form view or kanban view to stabilize
    await this.page.locator('.o_form_view, .o_action_manager .o_view_controller').first().waitFor({ state: 'visible', timeout: 15000 });
  }

  /**
   * Open an existing lead by name from the list/kanban view.
   */
  async openLead(name: string): Promise<void> {
    // Click the lead in the current view (works for both kanban and list)
    const lead = this.page.getByText(name, { exact: false }).first();
    await lead.click();
    // Wait for the form view to load
    // o_form_view: Odoo form view container (version-sensitive class)
    await this.page.locator('.o_form_view').waitFor({ state: 'visible', timeout: 10000 });
  }

  /**
   * Change the stage of the currently open lead via the status bar.
   * More reliable than kanban drag-and-drop.
   */
  async setStage(stageName: string): Promise<void> {
    // Dismiss notification banners that can intercept clicks
    await dismissNotifications(this.page);

    // o_statusbar_status: Odoo status bar with stage buttons (version-sensitive class)
    const stageButton = this.page.locator('.o_statusbar_status button', { hasText: stageName });
    await stageButton.click({ force: true });

    // Wait for the stage change RPC to complete
    await this.page.waitForTimeout(1000);
  }

  /**
   * Get the current active stage name from the status bar.
   */
  async getLeadStage(): Promise<string> {
    // o_statusbar_status .o_arrow_button_current: active stage (version-sensitive class)
    const activeStage = this.page.locator('.o_statusbar_status button.o_arrow_button_current');
    return (await activeStage.textContent()) ?? '';
  }

  /** Mark the current lead as Won. */
  async markWon(): Promise<void> {
    await dismissNotifications(this.page);
    await this.page.getByRole('button', { name: 'Won' }).click({ force: true });
    await this.page.waitForTimeout(2000);
  }

  /** Mark the current lead as Lost. Handles the loss reason dialog if it appears. */
  async markLost(): Promise<void> {
    await dismissNotifications(this.page);
    await this.page.getByRole('button', { name: 'Lost' }).click({ force: true });

    // Odoo may show a "lost reason" dialog -- confirm it if visible
    // o_dialog: Odoo dialog container (version-sensitive class)
    const dialog = this.page.locator('.o_dialog, .modal').first();
    if (await dialog.isVisible({ timeout: 3000 }).catch(() => false)) {
      // Try different button names for the submit/confirm action
      const submitBtn = dialog.getByRole('button', { name: /submit|mark as lost|confirm|ok/i });
      if (await submitBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
        await submitBtn.click();
      }
    }

    await this.page.waitForTimeout(1000);
  }
}
