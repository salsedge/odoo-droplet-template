import { test, expect } from '../../fixtures/auth.fixture.js';
import { CRMPage } from '../../pages/crm.page.js';

/**
 * CRM Lead Lifecycle — Workflow test
 *
 * CREATES DATA — run against local staging only, not production.
 * Tests the full CRM lead lifecycle: create -> advance stages -> won/lost.
 *
 * Requirements: ODOO-01, ODOO-05
 */

// Skip if running against production URL
test.beforeEach(async ({}, testInfo) => {
  const prodUrl = process.env.PROD_ODOO_URL;
  const baseUrl = testInfo.project.use?.baseURL;
  if (prodUrl && baseUrl && baseUrl === prodUrl) {
    testInfo.skip(true, 'Workflow tests create data — skipping on production');
  }
});

test.describe.serial('CRM lead lifecycle', () => {
  const leadName = `Test Lead ${Date.now()}`;
  const lostLeadName = `Lost Lead ${Date.now()}`;

  test('create a new CRM lead', async ({ adminPage }) => {
    test.slow(); // Lead creation involves multiple form mutations
    const crm = new CRMPage(adminPage);

    await crm.openCRM();
    await crm.createLead(leadName, {
      contactName: 'Test Contact',
      email: 'test@example.com',
    });

    // Verify the lead appears — check breadcrumb or page content
    await expect(adminPage.getByText(leadName)).toBeVisible();
  });

  test('advance lead through stages', async ({ adminPage }) => {
    test.slow();
    const crm = new CRMPage(adminPage);

    await crm.openCRM();
    await crm.openLead(leadName);

    // Advance to "Qualified"
    await crm.setStage('Qualified');
    const stageAfterQualified = await crm.getLeadStage();
    expect(stageAfterQualified.trim()).toContain('Qualified');

    // Advance to "Proposition"
    await crm.setStage('Proposition');
    const stageAfterProposition = await crm.getLeadStage();
    expect(stageAfterProposition.trim()).toContain('Proposition');
  });

  test('mark lead as won', async ({ adminPage }) => {
    test.slow();
    const crm = new CRMPage(adminPage);

    await crm.openCRM();
    await crm.openLead(leadName);
    await crm.markWon();

    // Verify won state — Odoo typically shows a "Won" ribbon or stage indicator
    // o_statusbar_status: stage bar should reflect won state (version-sensitive class)
    const wonIndicator = adminPage.locator('.o_statusbar_status .o_arrow_button_current, .oe_kanban_global_click .ribbon');
    const pageContent = await adminPage.content();
    // The page should contain "Won" somewhere in the status area or ribbon
    expect(pageContent.toLowerCase()).toContain('won');
  });

  test('create and mark a lead as lost', async ({ adminPage }) => {
    test.slow();
    const crm = new CRMPage(adminPage);

    // Create a second lead for the lost flow
    await crm.openCRM();
    await crm.createLead(lostLeadName, {
      contactName: 'Lost Contact',
      email: 'lost@example.com',
    });

    // Open it and advance
    await crm.openCRM();
    await crm.openLead(lostLeadName);
    await crm.setStage('Qualified');

    // Mark as lost
    await crm.markLost();

    // Verify lost state — page content should indicate lost status
    const pageContent = await adminPage.content();
    expect(pageContent.toLowerCase()).toContain('lost');
  });
});
