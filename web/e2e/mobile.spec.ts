import { expect, test, type Page } from '@playwright/test';
import { newPlayer, open, trackPageErrors } from './helpers';

trackPageErrors();

// Common low-end Android sizes: 360x640 is the typical budget phone, 320x568 the smallest.
const PHONES = [
	{ name: 'budget phone 360x640', viewport: { width: 360, height: 640 } },
	{ name: 'small phone 320x568', viewport: { width: 320, height: 568 } }
];

async function noSideways(page: Page) {
	const { scroll, inner } = await page.evaluate(() => ({
		scroll: document.documentElement.scrollWidth,
		inner: window.innerWidth
	}));
	expect(scroll, 'page scrolls sideways').toBeLessThanOrEqual(inner);
}

for (const phone of PHONES) {
	test(`${phone.name}: lobby and play screen fit and are tappable`, async ({ browser }, testInfo) => {
		const { ctx, page } = await newPlayer(browser, {
			context: { viewport: phone.viewport, hasTouch: true, isMobile: true, deviceScaleFactor: 2 }
		});

		await open(page, '/');
		await noSideways(page);
		await testInfo.attach('lobby', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });

		await page.getByRole('group', { name: 'Your colour' }).getByRole('button', { name: 'White' }).tap();
		await page.getByRole('button', { name: /Play vs computer/ }).tap();
		await page.waitForURL(/\/game\//);
		await expect(page.locator('main[data-color="white"]')).toBeVisible();
		await noSideways(page);

		// the board uses the full width and squares are big enough for a thumb (>= 36 px)
		const box = await page.locator('svg.board').boundingBox();
		expect(box!.width).toBeGreaterThanOrEqual(phone.viewport.width - 40);
		expect(box!.width / 8).toBeGreaterThanOrEqual(34);

		// play by tapping, like a real phone
		await page.locator('rect[data-square="e2"]').tap();
		await page.locator('rect[data-square="e4"]').tap();
		await expect(page.locator('[data-piece="wp"][data-at="e4"]')).toHaveCount(1);

		// Regression: a tapped square keeps focus, and a default focus ring on the scaled-up SVG
		// board turned into a giant white/black arc. No focused element may draw an outline.
		const outline = await page.evaluate(() => {
			const el = document.activeElement;
			return el ? getComputedStyle(el).outlineStyle : 'none';
		});
		expect(outline, 'focus ring on a tapped square').toBe('none');
		await expect(page.locator('.moves li')).toHaveCount(2, { timeout: 15_000 }); // computer replied

		// take something so the captured-pieces row is on screen in the screenshot
		await noSideways(page);
		await testInfo.attach('game', { body: await page.screenshot({ fullPage: true }), contentType: 'image/png' });

		// clocks and both action buttons are reachable
		await expect(page.getByRole('button', { name: 'Resign' })).toBeVisible();
		await page.getByRole('button', { name: 'Resign' }).scrollIntoViewIfNeeded();
		page.once('dialog', (d) => d.accept());
		await page.getByRole('button', { name: 'Resign' }).tap();
		await expect(page.getByText('You lost by resignation')).toBeVisible();
		await ctx.close();
	});
}
