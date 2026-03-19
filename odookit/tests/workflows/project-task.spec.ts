import { test, expect } from '../../fixtures/auth.fixture.js';
import { ProjectPage } from '../../pages/project.page.js';

/**
 * Project + Task Management — Workflow test
 *
 * CREATES DATA — run against local staging only, not production.
 * Tests project creation, task management, stage changes, and persistence.
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

test.describe.serial('Project and task management', () => {
  const projectName = `Test Project ${Date.now()}`;
  const taskNames = [
    `Task Alpha ${Date.now()}`,
    `Task Beta ${Date.now()}`,
    `Task Gamma ${Date.now()}`,
  ];

  test('create a new project', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    await project.openProjects();
    await project.createProject(projectName);

    // Verify the project appears in the view
    await expect(adminPage.getByText(projectName)).toBeVisible();
  });

  test('add tasks to the project', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    // Create each task in the project
    for (const taskName of taskNames) {
      await project.openProjects();
      await project.createTask(projectName, taskName);
    }

    // Navigate back to the project to verify all tasks are visible
    await project.openProjects();
    await project.openProject(projectName);

    // Switch to list view for reliable task name visibility
    // (kanban columns may collapse task names)
    const listViewBtn = adminPage.getByRole('button', { name: 'List View' });
    if (await listViewBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await listViewBtn.click();
      await adminPage.waitForTimeout(1000);
    }

    // Odoo 19 list view groups tasks by stage; collapsed groups hide task names.
    // Expand any collapsed group headers to reveal individual rows.
    const groupHeaders = adminPage.locator('.o_group_header');
    const groupCount = await groupHeaders.count();
    for (let i = 0; i < groupCount; i++) {
      const header = groupHeaders.nth(i);
      // Collapsed groups don't have .o_group_open class
      const isOpen = await header.evaluate(el => el.classList.contains('o_group_open'));
      if (!isOpen) {
        await header.click();
        await adminPage.waitForTimeout(500);
      }
    }

    // Verify at least the first and last tasks appear
    await expect(adminPage.getByText(taskNames[0])).toBeVisible({ timeout: 10000 });
    await expect(adminPage.getByText(taskNames[2])).toBeVisible({ timeout: 10000 });
  });

  test('change task stage', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    // Open the project and switch to list view to reliably find tasks
    await project.openProjects();
    await project.openProject(projectName);

    // Switch to list view (kanban may fold columns and hide task names)
    const listViewBtn = adminPage.getByRole('button', { name: 'List View' });
    if (await listViewBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await listViewBtn.click();
      await adminPage.waitForTimeout(1000);
    }

    // Expand collapsed group headers
    const groupHeaders = adminPage.locator('.o_group_header');
    const groupCount = await groupHeaders.count();
    for (let i = 0; i < groupCount; i++) {
      const header = groupHeaders.nth(i);
      const isOpen = await header.evaluate(el => el.classList.contains('o_group_open'));
      if (!isOpen) {
        await header.click();
        await adminPage.waitForTimeout(500);
      }
    }

    await project.openTask(taskNames[0]);

    // Change stage to "In Progress" (or similar — Odoo default project stages)
    await project.setTaskStage('In Progress');

    // Verify stage changed — Odoo 19 project tasks use either a status bar button
    // or a standalone stage dropdown button showing the current stage text
    await expect(adminPage.getByRole('button', { name: /In Progress/i })).toBeVisible({ timeout: 5000 });

    // Change to "Done"
    await project.setTaskStage('Done');
    await expect(adminPage.getByRole('button', { name: /Done/i })).toBeVisible({ timeout: 5000 });
  });

  test('tasks persist after page reload', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    // Navigate to the project
    await project.openProjects();
    await project.openProject(projectName);

    // Switch to list view for reliable task name visibility
    const listViewBtn = adminPage.getByRole('button', { name: 'List View' });
    if (await listViewBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await listViewBtn.click();
      await adminPage.waitForTimeout(1000);
    }

    // Reload the page
    await adminPage.reload();
    await adminPage.waitForTimeout(2000);

    // Expand collapsed group headers after reload
    const groupHeaders = adminPage.locator('.o_group_header');
    const groupCount = await groupHeaders.count();
    for (let i = 0; i < groupCount; i++) {
      const header = groupHeaders.nth(i);
      const isOpen = await header.evaluate(el => el.classList.contains('o_group_open'));
      if (!isOpen) {
        await header.click();
        await adminPage.waitForTimeout(500);
      }
    }

    // Verify tasks persist after reload. Note: taskNames[0] (Alpha) was moved
    // to "Done" in the previous test and may be filtered out by the "Open"
    // filter. Beta and Gamma remain in their original stage and prove persistence.
    await expect(adminPage.getByText(taskNames[1])).toBeVisible({ timeout: 10000 });
    await expect(adminPage.getByText(taskNames[2])).toBeVisible({ timeout: 10000 });
  });
});
