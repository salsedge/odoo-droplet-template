import { type Page, expect } from '@playwright/test';
import { AppMenuPage } from './app-menu.page.js';

/**
 * Odoo 19 CRM Module — Lead/opportunity management
 *
 * Methods cover the CRM lead lifecycle: create, open, stage changes, won/lost.
 * Uses form-based stage changes (more reliable than kanban drag-and-drop).
 */
export class CRMPage {
  readonly page: Page;
  readonly appMenu: AppMenuPage;

  constructor(page: Page) {
    this.page = page;
    this.appMenu = new AppMenuPage(page);
  }

  /** Navigate to the CRM module via the app menu. */
  async openCRM(): Promise<void> {
    await this.appMenu.openApp('CRM');
  }

  /**
   * Create a new CRM lead/opportunity.
   * Clicks "New", fills the form, and saves.
   */
  async createLead(name: string, options?: { contactName?: string; email?: string }): Promise<void> {
    // Click the "New" button to create a new record
    await this.page.getByRole('button', { name: 'New' }).click();

    // Fill the lead name (expected_revenue field triggers onchange)
    await this.page.locator('input[name="name"]').fill(name);

    // Wait for any onchange responses after the name field
    await this.page.waitForTimeout(500);

    if (options?.contactName) {
      await this.page.locator('input[name="contact_name"]').fill(options.contactName);
      await this.page.waitForTimeout(300);
    }

    if (options?.email) {
      await this.page.locator('input[name="email_from"]').fill(options.email);
      await this.page.waitForTimeout(300);
    }

    // Save the form via keyboard shortcut (most reliable across Odoo versions)
    // o_form_button_save: Odoo form save button (version-sensitive class)
    const saveButton = this.page.locator('.o_form_button_save');
    if (await saveButton.isVisible()) {
      await saveButton.click();
    }

    // Wait for the form to leave edit mode or a breadcrumb update
    await this.page.waitForTimeout(1000);
  }

  /**
   * Open an existing lead by name from the list/kanban view.
   */
  async openLead(name: string): Promise<void> {
    // Click the lead in the current view (works for both kanban and list)
    await this.page.getByText(name, { exact: false }).first().click();
    // Wait for the form view to load
    // o_form_view: Odoo form view container (version-sensitive class)
    await this.page.locator('.o_form_view').waitFor({ state: 'visible' });
  }

  /**
   * Change the stage of the currently open lead via the status bar.
   * More reliable than kanban drag-and-drop.
   */
  async setStage(stageName: string): Promise<void> {
    // o_statusbar_status: Odoo status bar with stage buttons (version-sensitive class)
    const stageButton = this.page.locator('.o_statusbar_status button', { hasText: stageName });
    await stageButton.click();

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
    await this.page.getByRole('button', { name: 'Won' }).click();
    await this.page.waitForTimeout(1000);
  }

  /** Mark the current lead as Lost. Handles the loss reason dialog if it appears. */
  async markLost(): Promise<void> {
    await this.page.getByRole('button', { name: 'Lost' }).click();

    // Odoo may show a "lost reason" dialog — confirm it if visible
    // o_dialog: Odoo dialog container (version-sensitive class)
    const dialog = this.page.locator('.o_dialog');
    if (await dialog.isVisible({ timeout: 2000 }).catch(() => false)) {
      await dialog.getByRole('button', { name: 'Submit' }).click();
    }

    await this.page.waitForTimeout(1000);
  }
}
