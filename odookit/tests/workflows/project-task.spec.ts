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

    // Verify at least the first and last tasks appear
    await expect(adminPage.getByText(taskNames[0])).toBeVisible();
    await expect(adminPage.getByText(taskNames[2])).toBeVisible();
  });

  test('change task stage', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    // Open the first task and change its stage
    await project.openProjects();
    await project.openProject(projectName);
    await project.openTask(taskNames[0]);

    // Change stage to "In Progress" (or similar — Odoo default project stages)
    await project.setTaskStage('In Progress');

    // Verify stage changed
    // o_statusbar_status .o_arrow_button_current: active stage (version-sensitive class)
    const activeStage = adminPage.locator('.o_statusbar_status button.o_arrow_button_current');
    const stageText = await activeStage.textContent();
    expect(stageText?.trim()).toContain('In Progress');

    // Change to "Done"
    await project.setTaskStage('Done');
    const doneStageText = await activeStage.textContent();
    expect(doneStageText?.trim()).toContain('Done');
  });

  test('tasks persist after page reload', async ({ adminPage }) => {
    test.slow();
    const project = new ProjectPage(adminPage);

    // Navigate to the project
    await project.openProjects();
    await project.openProject(projectName);

    // Reload the page
    await adminPage.reload();
    await adminPage.waitForTimeout(2000);

    // Verify tasks still exist after reload
    await expect(adminPage.getByText(taskNames[0])).toBeVisible();
    await expect(adminPage.getByText(taskNames[1])).toBeVisible();
    await expect(adminPage.getByText(taskNames[2])).toBeVisible();
  });
});
