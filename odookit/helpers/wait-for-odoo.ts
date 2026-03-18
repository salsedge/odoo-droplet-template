/**
 * Poll Odoo's /web/health endpoint until it returns HTTP 200 or timeout.
 * Uses native fetch (Node 18+).
 */
export async function waitForOdoo(url: string, timeoutMs = 120_000): Promise<void> {
  const start = Date.now();
  const pollInterval = 2_000;

  console.log(`Waiting for Odoo at ${url}/web/health (timeout: ${timeoutMs / 1000}s)...`);

  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${url}/web/health`);
      if (res.ok) {
        const elapsed = ((Date.now() - start) / 1000).toFixed(1);
        console.log(`Odoo ready at ${url} (${elapsed}s)`);
        return;
      }
    } catch {
      // Not ready yet — connection refused or other network error
    }

    const elapsed = ((Date.now() - start) / 1000).toFixed(0);
    console.log(`  ...waiting (${elapsed}s elapsed)`);
    await new Promise(r => setTimeout(r, pollInterval));
  }

  throw new Error(`Odoo not ready at ${url} after ${timeoutMs / 1000}s`);
}
