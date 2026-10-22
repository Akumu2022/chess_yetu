import { expect, test } from '@playwright/test';
import { move, newPlayer, open, startFriendGame, trackPageErrors } from './helpers';

trackPageErrors();

const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');

test('an old sign-in is dropped at page load, with an explanation', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	const old = `${b64({ alg: 'HS256' })}.${b64({ sub: '1', typ: 'adult', exp: Math.floor(Date.now() / 1000) - 60 })}.x`;
	await ctx.addInitScript((t) => {
		localStorage.setItem('chess_yetu:auth', t);
		sessionStorage.setItem('chess_yetu:auth', t);
	}, old);
	await open(page, '/');
	await expect(page.getByText('Your sign-in expired')).toBeVisible();
	await expect(page.locator('header').getByRole('link', { name: 'Sign in' })).toBeVisible();
	expect(await page.evaluate(() => localStorage.getItem('chess_yetu:auth'))).toBeNull();
	await ctx.close();
});

test('a piece slides to its new square (the same piece, not a new one appearing)', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	const before = await b.page.locator('[data-piece="wp"][data-at="e2"]').elementHandle();
	await move(a.page, 'e2', 'e4');
	await expect(b.page.locator('[data-piece="wp"][data-at="e4"]')).toHaveCount(1, { timeout: 10_000 });
	expect(await before!.evaluate((el) => (el as SVGElement).dataset.at)).toBe('e4'); // same element, moved
	await a.ctx.close();
	await b.ctx.close();
});

test('the computer shows it is thinking, and the lobby offers 10+5', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/');
	await page.getByRole('button', { name: '10+5', exact: true }).click();
	await expect(page.getByText(/plus 5 extra seconds/)).toBeVisible();
	await page.getByRole('button', { name: 'White', exact: true }).click();
	await page.getByRole('button', { name: /Play vs computer \(10\+5\)/ }).click();
	await page.waitForURL(/\/game\//);
	await move(page, 'e2', 'e4');
	await expect(page.getByText(/thinking/)).toBeVisible();
	await expect(page.locator('.moves li')).toHaveCount(2, { timeout: 15_000 });
	await expect(page.getByText(/thinking/)).toBeHidden();
	await ctx.close();
});
