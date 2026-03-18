import { test, expect } from '@playwright/test';

/**
 * Audit tests: HTTP security headers
 *
 * NON-DESTRUCTIVE — safe for production environments.
 * Verifies security headers configured in Nginx (config/nginx/odoo.conf):
 *   - PROXY-03: HSTS
 *   - PROXY-04: X-Frame-Options, X-Content-Type-Options, CSP, Referrer-Policy
 *
 * SSL-specific tests skip automatically when running against localhost (no Nginx/SSL).
 */

const isLocalhost = (url: string | undefined): boolean =>
  !url || url.startsWith('http://localhost') || url.startsWith('http://127.0.0.1');

test.describe('HTTP security headers', () => {
  test('HSTS header is present with max-age >= 1 year', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'HSTS requires HTTPS — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const hsts = response!.headers()['strict-transport-security'];
    expect(hsts).toBeDefined();

    // Extract max-age value and verify >= 31536000 (1 year)
    const maxAgeMatch = hsts?.match(/max-age=(\d+)/);
    expect(maxAgeMatch).not.toBeNull();

    const maxAge = parseInt(maxAgeMatch![1], 10);
    expect(maxAge).toBeGreaterThanOrEqual(31536000);
  });

  test('X-Content-Type-Options is nosniff', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'Security headers require Nginx — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const header = response!.headers()['x-content-type-options'];
    expect(header).toBe('nosniff');
  });

  test('X-Frame-Options is SAMEORIGIN or DENY', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'Security headers require Nginx — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const header = response!.headers()['x-frame-options'];
    expect(header).toBeDefined();
    expect(['SAMEORIGIN', 'DENY', 'sameorigin', 'deny']).toContain(header!.toUpperCase());
  });

  test('Referrer-Policy is set', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'Security headers require Nginx — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const header = response!.headers()['referrer-policy'];
    expect(header).toBeDefined();

    // Accept any restrictive referrer policy
    const validPolicies = [
      'no-referrer',
      'no-referrer-when-downgrade',
      'origin',
      'origin-when-cross-origin',
      'same-origin',
      'strict-origin',
      'strict-origin-when-cross-origin',
    ];
    expect(validPolicies).toContain(header);
  });

  test('Content-Security-Policy is present', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'Security headers require Nginx — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const csp = response!.headers()['content-security-policy'];
    expect(csp).toBeDefined();
    // Just verify CSP exists — don't validate full policy (Odoo needs permissive CSP)
    expect(csp!.length).toBeGreaterThan(0);
  });

  test('HTTP redirects to HTTPS', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'HTTP→HTTPS redirect requires Nginx — skipping on localhost');

    // Make a request to the HTTP version and verify it redirects
    const httpUrl = baseURL!.replace('https://', 'http://');
    const response = await page.goto(httpUrl, { waitUntil: 'commit' });
    expect(response).not.toBeNull();

    // After following redirects, we should be on HTTPS
    const finalUrl = page.url();
    expect(finalUrl).toMatch(/^https:\/\//);
  });

  test('no Server header leaks version info', async ({ page, baseURL }) => {
    test.skip(isLocalhost(baseURL), 'Server header check requires Nginx — skipping on localhost');

    const response = await page.goto('/web/login');
    expect(response).not.toBeNull();

    const serverHeader = response!.headers()['server'];
    if (serverHeader) {
      // server_tokens off in Nginx should suppress version info
      // Should be just "nginx" not "nginx/1.x.x"
      expect(serverHeader).not.toMatch(/nginx\/\d/);
    }
    // If no server header at all, that's even better (fully hidden)
  });
});
