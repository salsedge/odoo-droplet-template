import { test as base, type Page } from '@playwright/test';
export { expect } from '@playwright/test';
import { LoginPage } from '../pages/login.page.js';

/**
 * Auth fixtures — provide pre-authenticated browser contexts for tests.
 *
 * - `adminPage`: Logged in with ADMIN_LOGIN / ADMIN_PASSWORD (required)
 * - `testUserPage`: Logged in with TEST_USER_LOGIN / TEST_USER_PASSWORD (skips if not set)
 *
 * Each fixture creates a fresh browser context, logs in, provides the page,
 * and closes the context after the test.
 */
type AuthFixtures = {
  adminPage: Page;
  testUserPage: Page;
};

export const test = base.extend<AuthFixtures>({
  adminPage: async ({ browser }, use) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login(
      process.env.ADMIN_LOGIN!,
      process.env.ADMIN_PASSWORD!
    );

    await use(page);
    await context.close();
  },

  testUserPage: async ({ browser }, use, testInfo) => {
    const login = process.env.TEST_USER_LOGIN;
    const password = process.env.TEST_USER_PASSWORD;

    if (!login || !password) {
      testInfo.skip(true, 'TEST_USER_LOGIN / TEST_USER_PASSWORD not set — skipping test user fixture');
      return;
    }

    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login(login, password);

    await use(page);
    await context.close();
  },
});
