import { execSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import { waitForOdoo } from './wait-for-odoo.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const COMPOSE_DIR = path.resolve(__dirname, '..');

/**
 * Start the local Docker Compose staging stack and wait for Odoo to be ready.
 * Runs `docker compose up -d --wait` then polls /web/health.
 */
export async function composeUp(): Promise<void> {
  console.log('Starting local staging stack...');
  execSync('docker compose up -d --wait', {
    cwd: COMPOSE_DIR,
    stdio: 'inherit',
  });

  await waitForOdoo('http://localhost:8069');
  console.log('Local staging stack is ready.');
}

/**
 * Stop the local Docker Compose staging stack.
 * @param removeVolumes - If true, also removes volumes (wipes all data).
 */
export function composeDown(removeVolumes = false): void {
  const flags = removeVolumes ? 'down -v' : 'down';
  console.log(`Stopping local staging stack${removeVolumes ? ' (removing volumes)' : ''}...`);
  execSync(`docker compose ${flags}`, {
    cwd: COMPOSE_DIR,
    stdio: 'inherit',
  });
  console.log('Local staging stack stopped.');
}
