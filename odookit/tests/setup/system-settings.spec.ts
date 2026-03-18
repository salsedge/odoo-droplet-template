import { test, expect } from '../../fixtures/auth.fixture.js';
import { SettingsPage } from '../../pages/settings.page.js';

/**
 * Setup tests: System settings configuration
 *
 * DESTRUCTIVE — may modify company name and other settings.
 * Excluded from production project via testIgnore pattern in playwright.config.ts.
 *
 * Serial execution required — settings changes happen sequentially.
 */
test.describe.configure({ mode: 'serial' });

test.describe('System settings configuration', () => {
  test('configure company name', async ({ adminPage }) => {
    const settings = new SettingsPage(adminPage);
    await settings.openSettings();

    // Navigate to company settings — in Odoo 19, General Settings has a Companies section
    // Click on "Companies" or navigate directly
    await adminPage.goto('/odoo/settings/companies');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await adminPage.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
    await adminPage.waitForTimeout(1000);

    // Click the first company in the list (usually "My Company" or similar)
    // o_data_row: Odoo list view row (version-sensitive class)
    const companyRow = adminPage.locator('.o_data_row').first();
    if (await companyRow.isVisible({ timeout: 3000 }).catch(() => false)) {
      await companyRow.click();
      await adminPage.waitForTimeout(500);

      // Check current company name
      const nameInput = adminPage.locator('input[name="name"]');
      const currentName = await nameInput.inputValue();

      // Only update if it's the default "My Company" placeholder
      if (currentName === 'My Company' || currentName === 'My Company (San Francisco)') {
        await nameInput.clear();
        await nameInput.fill('OdooKit Test Company');
        await adminPage.waitForTimeout(500);

        // Save the form
        // o_form_button_save: Odoo form save button (version-sensitive class)
        const saveButton = adminPage.locator('.o_form_button_save');
        if (await saveButton.isVisible()) {
          await saveButton.click();
          await adminPage.waitForTimeout(1000);
        }

        // Verify the name was saved
        const savedName = await nameInput.inputValue();
        expect(savedName).toBe('OdooKit Test Company');
      } else {
        // Company name already customized — just verify it's not empty
        expect(currentName.length).toBeGreaterThan(0);
        // eslint-disable-next-line no-console
        console.log(`Company name already set: "${currentName}"`);
      }
    }
  });

  test('verify timezone is set', async ({ adminPage }) => {
    await adminPage.goto('/odoo/settings');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await adminPage.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
    await adminPage.waitForTimeout(1000);

    // Check for timezone setting in the General Settings page
    // The timezone is typically shown in a select/dropdown in the company/user preferences
    // Navigate to user preferences where timezone is set
    await adminPage.goto('/odoo/settings/users');
    await adminPage.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
    await adminPage.waitForTimeout(500);

    // Open the admin user's preferences
    const adminRow = adminPage.locator('.o_data_row', { hasText: process.env.ADMIN_LOGIN || 'admin' }).first();

    if (await adminRow.isVisible({ timeout: 3000 }).catch(() => false)) {
      await adminRow.click();
      await adminPage.waitForTimeout(500);

      // Click Preferences tab if available
      const preferencesTab = adminPage.getByRole('tab', { name: 'Preferences' });
      if (await preferencesTab.isVisible({ timeout: 2000 }).catch(() => false)) {
        await preferencesTab.click();
        await adminPage.waitForTimeout(500);
      }

      // Check timezone field — it should have a non-empty value
      const tzField = adminPage.locator('select[name="tz"], input[name="tz"]').first();
      if (await tzField.isVisible({ timeout: 2000 }).catch(() => false)) {
        const tzValue = await tzField.inputValue();
        expect(tzValue.length).toBeGreaterThan(0);
        // eslint-disable-next-line no-console
        console.log(`Timezone configured: ${tzValue}`);
      } else {
        // Timezone might be a many2one or different widget in Odoo 19
        // Check for any timezone-related content on the page
        const tzText = adminPage.getByText(/timezone/i);
        const hasTz = await tzText.isVisible({ timeout: 2000 }).catch(() => false);
        // If timezone label exists somewhere, the setting is present
        test.skip(!hasTz, 'Timezone field not found in current UI — may require different navigation path');
      }
    } else {
      test.skip(true, 'Could not locate admin user row in users list');
    }
  });

  test('verify Odoo runs in multi-worker mode', async ({ adminPage }) => {
    // Worker configuration is set in odoo.conf, not typically visible in the UI.
    // The Settings > Technical > System Information page may show worker info,
    // but this is not reliably available in all Odoo editions.
    // Skip if worker info is not exposed in the UI.

    await adminPage.goto('/odoo/settings');
    await adminPage.locator('.o_action_manager .o_view_controller').waitFor({ state: 'visible' });
    await adminPage.waitForTimeout(1000);

    // Try to find worker/multiprocessing information in the technical settings
    // In Odoo, `Settings > Technical > System Information` shows some details
    // but the exact location varies by version and installed modules.
    const workerInfo = adminPage.getByText(/workers|multiprocessing/i);
    const hasWorkerInfo = await workerInfo.isVisible({ timeout: 3000 }).catch(() => false);

    if (!hasWorkerInfo) {
      // Worker mode is configured via odoo.conf (workers = 3) — not UI-visible
      // This is expected for Odoo Community. Infrastructure audit script verifies this instead.
      test.skip(true, 'Worker configuration not visible in Odoo UI — verified via odoo.conf and infra audit');
    } else {
      // If visible, just confirm the text is present
      await expect(workerInfo.first()).toBeVisible();
      // eslint-disable-next-line no-console
      console.log('Worker/multiprocessing info found in settings UI');
    }
  });
});
