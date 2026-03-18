import { test, expect } from '@playwright/test';
import { LoginPage } from '../../pages/login.page.js';
import { loadEnv } from '../../helpers/env.js';

/**
 * Smoke tests: Login functionality
 *
 * Non-destructive — safe for production and local environments.
 * Verifies admin login, credential rejection, and login page availability.
 */
test.describe('Login smoke tests', () => {
  let env: ReturnType<typeof loadEnv>;

  test.beforeAll(() => {
    env = loadEnv();
  });

  test('admin can log in', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login(env.ADMIN_LOGIN, env.ADMIN_PASSWORD);

    // o_main_navbar: Odoo 19 top navigation bar (version-sensitive class)
    await expect(page.locator('.o_main_navbar')).toBeVisible();
    expect(await loginPage.isLoggedIn()).toBe(true);
  });

  test('invalid credentials are rejected', async ({ page }) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();

    await loginPage.loginInput.fill(env.ADMIN_LOGIN);
    await loginPage.passwordInput.fill('definitely-wrong-password-12345');
    await loginPage.submitButton.click();

    // Odoo shows .alert-danger with "Wrong login/password" on failed auth
    await expect(page.locator('.alert-danger')).toBeVisible();
    await expect(page.locator('.alert-danger')).toContainText(/wrong login\/password/i);
  });

  test('login page loads', async ({ page }) => {
    await page.goto('/web/login');

    // The login form should be present
    await expect(page.locator('form.oe_login_form')).toBeVisible();
    await expect(page.locator('input[name="login"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
  });
});
