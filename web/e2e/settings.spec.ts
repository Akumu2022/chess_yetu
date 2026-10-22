import { expect, test } from '@playwright/test';
import { newPlayer, open, sq, trackPageErrors } from './helpers';

trackPageErrors();

const root = (page: import('@playwright/test').Page, attr: string) =>
	page.evaluate((a) => document.documentElement.dataset[a], attr);
const fill = (page: import('@playwright/test').Page, name: string) =>
	sq(page, name).evaluate((el) => getComputedStyle(el).fill);

test('the app starts in light mode even when the computer prefers dark', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser, { context: { colorScheme: 'dark' } });
	await open(page, '/');
	expect(await root(page, 'theme')).toBe('light');
	const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
	expect(bg).toBe('rgb(246, 241, 233)');
	await ctx.close();
});

test('choices are saved and survive a reload', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/');
	await page.getByRole('link', { name: 'Settings' }).click();
	await page.waitForURL('**/settings');
	await expect(page.locator('rect[data-square="a1"]')).toBeVisible();

	const lightBefore = await fill(page, 'a1');
	await page.getByRole('button', { name: 'Green', exact: true }).click();
	expect(await fill(page, 'a1')).not.toBe(lightBefore);
	await page.getByRole('button', { name: 'Dark', exact: true }).click();
	await page.getByRole('button', { name: 'Gold & navy' }).click();
	expect(await root(page, 'theme')).toBe('dark');

	await page.reload();
	await page.locator('body[data-hydrated="true"]').waitFor();
	expect(await root(page, 'theme')).toBe('dark');
	expect(await root(page, 'board')).toBe('green');
	expect(await root(page, 'pieces')).toBe('gold');
	await expect(page.getByRole('button', { name: 'Green', exact: true })).toHaveAttribute('aria-pressed', 'true');

	// a game board uses them too
	await open(page, '/');
	await page.getByRole('button', { name: /Play vs computer/ }).click();
	await page.waitForURL(/\/game\//);
	await expect(page.locator('rect[data-square="a1"]')).toBeVisible();
	expect(await root(page, 'board')).toBe('green');
	await ctx.close();
});

test('move dots, last-move tint and coordinates can be switched off', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/settings');
	await sq(page, 'f6').click(); // black knight in the sample position
	await expect(page.locator('circle.hint').first()).toBeVisible();
	await expect(page.locator('rect.last').first()).toBeVisible();
	await expect(page.locator('text.coord').first()).toBeVisible();

	await page.getByLabel('Show dots where a piece can move').uncheck();
	await expect(page.locator('circle.hint')).toHaveCount(0);
	await page.getByLabel('Highlight the last move').uncheck();
	await expect(page.locator('rect.last')).toHaveCount(0);
	await page.getByLabel('Show letters and numbers on the edge').uncheck();
	await expect(page.locator('text.coord')).toHaveCount(0);

	await page.getByRole('button', { name: 'Reset to defaults' }).click();
	await expect(page.locator('rect.last').first()).toBeVisible();
	expect(await root(page, 'theme')).toBe('light');
	await page.getByRole('link', { name: /← Back/ }).click();
	await page.waitForURL(/\/$/);
	await ctx.close();
});

test('wood and marble boards draw a texture, flat colours do not, and the choice survives a reload', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/settings');
	await expect(page.locator('svg.board rect.tex')).toHaveCount(0); // classic is flat

	await page.getByRole('button', { name: 'Walnut wood' }).click();
	expect(await root(page, 'board')).toBe('walnut');
	await expect(page.locator('svg.board rect.tex[data-texture="wood"]')).toHaveCount(1);

	await page.getByRole('button', { name: 'Onyx marble' }).click();
	await expect(page.locator('svg.board rect.tex[data-texture="marble"]')).toHaveCount(2);
	await expect(page.locator('svg.board rect.tex[data-texture="wood"]')).toHaveCount(0);

	await page.reload();
	await page.locator('body[data-hydrated="true"]').waitFor();
	expect(await root(page, 'board')).toBe('onyx');
	await expect(page.locator('svg.board rect.tex[data-texture="marble"]')).toHaveCount(2);

	await page.getByRole('button', { name: 'Green', exact: true }).click();
	await expect(page.locator('svg.board rect.tex')).toHaveCount(0);
	await ctx.close();
});

test('there are 22 board styles to choose from, in groups', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/settings');
	await expect(page.locator('.board-swatch')).toHaveCount(22);
	for (const group of ['Colours', 'Bold', 'Wood', 'Marble']) {
		await expect(page.getByRole('group', { name: `Board style: ${group}` })).toBeVisible();
	}
	await ctx.close();
});

test('a framed board puts the letters and numbers outside the squares', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/settings');
	await expect(page.locator('svg.board')).toHaveAttribute('viewBox', '0 0 8 8');
	await expect(page.locator('svg.board text.coord')).toHaveCount(16); // inside the squares

	await page.getByLabel(/Framed board/).check();
	await expect(page.locator('svg.board')).toHaveAttribute('viewBox', /^-0\.42/);
	await expect(page.locator('svg.board rect.frame')).toHaveCount(1);
	await expect(page.locator('svg.board text.coord-out')).toHaveCount(16);
	await expect(page.locator('svg.board text.coord')).toHaveCount(0);
	await expect(sq(page, 'a1')).toBeVisible(); // squares still work as before

	await page.reload();
	await page.locator('body[data-hydrated="true"]').waitFor();
	await expect(page.locator('svg.board rect.frame')).toHaveCount(1);

	await page.getByLabel('Show letters and numbers on the edge').uncheck();
	await expect(page.locator('svg.board text.coord-out')).toHaveCount(0);
	await ctx.close();
});

