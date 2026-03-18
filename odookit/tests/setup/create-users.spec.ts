import { test, expect } from '../../fixtures/auth.fixture.js';
import { UserManagementPage } from '../../pages/user-management.page.js';
import { LoginPage } from '../../pages/login.page.js';
import { AppMenuPage } from '../../pages/app-menu.page.js';

/**
 * Setup tests: User creation and role verification
 *
 * DESTRUCTIVE — creates and removes test users.
 * Excluded from production project via testIgnore pattern in playwright.config.ts.
 *
 * Serial execution required — each test depends on the user created in the first test.
 * Skips the entire suite if TEST_USER_LOGIN is not set.
 */
test.describe.configure({ mode: 'serial' });

test.describe('Test user creation and verification', () => {
  const testLogin = process.env.TEST_USER_LOGIN;
  const testPassword = process.env.TEST_USER_PASSWORD;
  const testName = 'OdooKit Test User';

  test.beforeAll(() => {
    // Skip entire suite if test user credentials not configured
    test.skip(!testLogin || !testPassword, 'TEST_USER_LOGIN / TEST_USER_PASSWORD not set — skipping user setup');
  });

  test('create test user with CRM and Project access', async ({ adminPage }) => {
    test.slow();

    const userMgmt = new UserManagementPage(adminPage);

    // Check if user already exists
    const exists = await userMgmt.userExists(testLogin!);
    if (exists) {
      // eslint-disable-next-line no-console
      console.log(`User ${testLogin} already exists — skipping creation`);
      return;
    }

    // Create user with CRM and Project access groups
    // Odoo 19 groups: field label -> dropdown option text
    await userMgmt.createUser(testName, testLogin!, testPassword!, {
      groups: {
        'Sales': 'User: Own Documents Only',
        'Project': 'User',
      },
    });

    // Verify user was created
    const userExists = await userMgmt.userExists(testLogin!);
    expect(userExists).toBe(true);
  });

  test('verify test user can log in', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login(testLogin!, testPassword!);

    // Verify login succeeded by checking for the main navbar
    // o_main_navbar: Odoo 19 top navigation bar (version-sensitive class)
    await expect(page.locator('.o_main_navbar')).toBeVisible();
    expect(await loginPage.isLoggedIn()).toBe(true);

    await context.close();
  });

  test('verify test user can access CRM', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login(testLogin!, testPassword!);
    await page.locator('.o_main_navbar').waitFor({ state: 'visible' });

    const appMenu = new AppMenuPage(page);
    await appMenu.openApp('CRM');

    // Verify CRM loaded — the view controller should be visible
    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await expect(page.locator('.o_action_manager .o_view_controller')).toBeVisible();

    await context.close();
  });

  test('verify test user can access Project', async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    const loginPage = new LoginPage(page);

    await loginPage.goto();
    await loginPage.login(testLogin!, testPassword!);
    await page.locator('.o_main_navbar').waitFor({ state: 'visible' });

    const appMenu = new AppMenuPage(page);
    await appMenu.openApp('Project');

    // o_action_manager .o_view_controller: Odoo view container (version-sensitive classes)
    await expect(page.locator('.o_action_manager .o_view_controller')).toBeVisible();

    await context.close();
  });

  test('clean up: remove test user', async ({ adminPage }) => {
    // Mark as cleanup — don't fail the suite if this fails
    test.fixme(false, 'Cleanup test — failure is non-critical');

    const userMgmt = new UserManagementPage(adminPage);

    try {
      await userMgmt.deleteUser(testLogin!);
      // eslint-disable-next-line no-console
      console.log(`Cleaned up test user: ${testLogin}`);
    } catch (error) {
      // Archive/delete may fail if user was already removed or never fully created.
      // Log but don't fail the suite.
      // eslint-disable-next-line no-console
      console.warn(`Cleanup warning — could not remove user ${testLogin}:`, error);
    }
  });
});
