import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export interface OdooKitEnv {
  // Target environments
  LOCAL_ODOO_URL: string;
  PROD_ODOO_URL: string | undefined;

  // Admin credentials (required)
  ADMIN_LOGIN: string;
  ADMIN_PASSWORD: string;

  // Test user credentials (optional — created by setup tests)
  TEST_USER_LOGIN: string | undefined;
  TEST_USER_PASSWORD: string | undefined;

  // Local staging database
  LOCAL_POSTGRES_USER: string;
  LOCAL_POSTGRES_PASSWORD: string;
  LOCAL_POSTGRES_DB: string;

  // Infrastructure audit SSH target
  INFRA_SSH_HOST: string | undefined;
  INFRA_SSH_PORT: string;
  INFRA_SSH_USER: string;

  // Reporting
  REPORT: string | undefined;
}

/**
 * Load and validate environment variables from .env file.
 * Throws descriptive errors if required variables are missing.
 */
export function loadEnv(): OdooKitEnv {
  dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

  const missing: string[] = [];

  if (!process.env.ADMIN_LOGIN) missing.push('ADMIN_LOGIN');
  if (!process.env.ADMIN_PASSWORD) missing.push('ADMIN_PASSWORD');

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}\n` +
      'Copy .env.example to .env and fill in your values:\n' +
      '  cp .env.example .env'
    );
  }

  return {
    LOCAL_ODOO_URL: process.env.LOCAL_ODOO_URL || 'http://localhost:8069',
    PROD_ODOO_URL: process.env.PROD_ODOO_URL || undefined,

    ADMIN_LOGIN: process.env.ADMIN_LOGIN!,
    ADMIN_PASSWORD: process.env.ADMIN_PASSWORD!,

    TEST_USER_LOGIN: process.env.TEST_USER_LOGIN || undefined,
    TEST_USER_PASSWORD: process.env.TEST_USER_PASSWORD || undefined,

    LOCAL_POSTGRES_USER: process.env.LOCAL_POSTGRES_USER || 'odoo',
    LOCAL_POSTGRES_PASSWORD: process.env.LOCAL_POSTGRES_PASSWORD || 'odoo_local_dev',
    LOCAL_POSTGRES_DB: process.env.LOCAL_POSTGRES_DB || 'odoo',

    INFRA_SSH_HOST: process.env.INFRA_SSH_HOST || undefined,
    INFRA_SSH_PORT: process.env.INFRA_SSH_PORT || '9292',
    INFRA_SSH_USER: process.env.INFRA_SSH_USER || 'deploy',

    REPORT: process.env.REPORT || undefined,
  };
}
