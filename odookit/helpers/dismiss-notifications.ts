import { type Page } from '@playwright/test';

/**
 * Dismiss all visible Odoo notification banners.
 * Odoo 19 shows persistent "Your password is the default" notifications
 * that can intercept pointer events on underlying elements.
 *
 * Call this before interacting with elements that might be obscured by notifications.
 */
export async function dismissNotifications(page: Page): Promise<void> {
  // Remove all Odoo notification/alert banners via JavaScript injection.
  // This is the most reliable approach because:
  //   - Notifications overlay page content and intercept pointer events
  //   - Clicking close buttons can itself be intercepted by other notifications
  //   - JS removal bypasses all overlay/click-interception issues
  await page.evaluate(() => {
    // Remove .o_notification elements (standard Odoo notifications)
    document.querySelectorAll('.o_notification').forEach(el => el.remove());
    // Remove the notification container if empty
    const container = document.querySelector('.o_notification_manager');
    if (container && container.children.length === 0) {
      container.remove();
    }
  });
  await page.waitForTimeout(200);
}
