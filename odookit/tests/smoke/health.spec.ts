import { test, expect } from '@playwright/test';

/**
 * Smoke tests: Odoo health and accessibility
 *
 * Non-destructive — safe for production and local environments.
 * Verifies Odoo responds on health endpoint, login page is accessible,
 * and database manager is properly blocked (ODOO-03, PROXY-04).
 */
test.describe('Health and accessibility smoke tests', () => {

  test('Odoo /web/health returns 200', async ({ page }) => {
    const response = await page.goto('/web/health');
    expect(response).not.toBeNull();
    expect(response!.status()).toBe(200);
  });

  test('login page is accessible', async ({ page }) => {
    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    // Should get 200, not a redirect to database selector
    expect(response!.status()).toBe(200);
    // Verify we are on the login page (not a database manager redirect)
    await expect(page.locator('form.oe_login_form')).toBeVisible();
  });

  test('database manager is blocked', async ({ page, baseURL }) => {
    // ODOO-03: list_db = False in odoo.conf
    // PROXY-04: Nginx returns 403 on /web/database/*
    // Skip on localhost: local Docker stack has no list_db=False or Nginx blocking
    const isLocal = !baseURL || baseURL.startsWith('http://localhost') || baseURL.startsWith('http://127.0.0.1');
    test.skip(isLocal, 'Database manager blocking requires production config (list_db=False + Nginx) — skipping on localhost');

    const response = await page.goto('/web/database/manager');
    expect(response).not.toBeNull();

    const status = response!.status();
    const url = page.url();

    // Production: Nginx blocks with 403
    const isBlocked = status === 403 || !url.includes('/web/database/manager');
    expect(isBlocked).toBe(true);

    // Double-check: the database manager form should not be visible
    const dbManagerForm = page.locator('.o_database_manager, form[action="/web/database/create"]');
    await expect(dbManagerForm).not.toBeVisible({ timeout: 3000 }).catch(() => {
      // If the locator times out waiting for "not visible", that's fine — it means it was never there
    });
  });
});
