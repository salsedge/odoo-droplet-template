import { test, expect } from '../../fixtures/auth.fixture.js';
import { UserManagementPage } from '../../pages/user-management.page.js';
import { LoginPage } from '../../pages/login.page.js';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Production user creation — config-driven team member provisioning
 *
 * Reads team member definitions from team-members.json and creates
 * accounts for each non-admin user. Each user's login is verified
 * by actually logging in with the created credentials.
 *
 * IDEMPOTENT — existing users are skipped without error.
 * NO CLEANUP — these are persistent production accounts.
 *
 * Serial execution required — users must be created in order so
 * that group/role changes don't conflict.
 */

// --- Config loading ---

interface TeamMember {
  name: string;
  login: string;
  password?: string;
  role: 'admin' | 'user';
  groups?: Record<string, string>;
}

interface TeamConfig {
  users: TeamMember[];
}

const configPath = resolve(__dirname, '../../team-members.json');
let teamConfig: TeamConfig;

try {
  teamConfig = JSON.parse(readFileSync(configPath, 'utf-8'));
} catch {
  throw new Error(
    'Cannot read team-members.json. Copy team-members.json.example to team-members.json and fill in passwords.\n' +
    `  cp team-members.json.example team-members.json\n` +
    `  Expected path: ${configPath}`
  );
}

// Filter to regular users only — admin is managed separately
const regularUsers = teamConfig.users.filter((u) => u.role === 'user');

// --- Tests ---

test.describe.configure({ mode: 'serial' });

test.describe('Production team user creation', () => {
  for (const user of regularUsers) {
    test.describe(`${user.name} (${user.login})`, () => {
      test(`create user: ${user.name} (${user.login})`, async ({ adminPage }) => {
        test.slow();

        if (!user.password) {
          throw new Error(
            `No password set for ${user.login} in team-members.json. ` +
            'Each user must have a password defined.'
          );
        }

        const userMgmt = new UserManagementPage(adminPage);

        // Idempotent: skip if user already exists
        const exists = await userMgmt.userExists(user.login);
        if (exists) {
          // eslint-disable-next-line no-console
          console.log(`User ${user.login} already exists — skipping creation`);
          return;
        }

        // Create user with name, login, password, and optional groups
        await userMgmt.createUser(user.name, user.login, user.password, {
          groups: user.groups,
        });

        // Verify user was created
        const userExists = await userMgmt.userExists(user.login);
        expect(userExists).toBe(true);
      });

      test(`verify login: ${user.name} (${user.login})`, async ({ browser }) => {
        if (!user.password) {
          throw new Error(`No password set for ${user.login} — cannot verify login`);
        }

        const context = await browser.newContext();
        const page = await context.newPage();
        const loginPage = new LoginPage(page);

        await loginPage.goto();
        await loginPage.login(user.login, user.password);

        // o_main_navbar: Odoo 19 top navigation bar (version-sensitive class)
        await expect(page.locator('.o_main_navbar')).toBeVisible();

        await context.close();
      });
    });
  }
});
