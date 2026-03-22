import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '.env') });

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: 1,
  reporter: process.env.REPORT
    ? [['html', { open: 'never', outputFolder: 'reports' }]]
    : [['list']],
  use: {
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'local',
      use: {
        baseURL: process.env.LOCAL_ODOO_URL || 'http://localhost:8069',
        ...devices['Desktop Chrome'],
      },
      testIgnore: ['**/production/**'],
    },
    {
      name: 'production',
      timeout: 90_000,
      expect: { timeout: 15_000 },
      use: {
        baseURL: process.env.PROD_ODOO_URL,
        ignoreHTTPSErrors: true,  // Required: SSH tunnel cert is for domain, not localhost
        ...devices['Desktop Chrome'],
      },
      testIgnore: ['**/setup/**'],
    },
  ],
});
