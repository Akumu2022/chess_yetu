import { expect, test } from '@playwright/test';
import { newPlayer, open, register, trackPageErrors } from './helpers';

trackPageErrors();

const tag = () => Date.now().toString().slice(-6) + Math.floor(Math.random() * 90 + 10);

test('arena: two players join, are paired automatically, play, and the standings update', async ({ browser }) => {
	test.setTimeout(120_000);
	const t = tag();
	const a = await newPlayer(browser);
	const b = await newPlayer(browser);
	await register(a.page, `arena_a${t}`);
	await register(b.page, `arena_b${t}`);

	// A creates a tournament that is already running
	await open(a.page, '/tournaments');
	await a.page.getByPlaceholder('Friday night blitz').fill(`Test Arena ${t}`);
	await a.page.getByLabel('Starts in (min)').fill('0');
	await a.page.getByRole('button', { name: 'Create' }).click();
	await a.page.waitForURL(/\/tournaments\/\d+$/);
	await expect(a.page.getByText(/Live · .* left/)).toBeVisible();

	// B finds it in the list and joins
	await open(b.page, '/tournaments');
	await b.page.getByRole('link', { name: new RegExp(`Test Arena ${t}`) }).click();
	await b.page.waitForURL(/\/tournaments\/\d+$/);
	await b.page.getByRole('button', { name: 'Join' }).click();
	await a.page.getByRole('button', { name: 'Join' }).click();
	await expect(a.page.getByText(/Waiting for an opponent/)).toBeVisible();

	// the pairing loop puts them in a game together, without anyone clicking
	await a.page.waitForURL(/\/game\//, { timeout: 30_000 });
	await b.page.waitForURL(/\/game\//, { timeout: 30_000 });
	const colorA = await a.page.locator('main').getAttribute('data-color');
	const colorB = await b.page.locator('main').getAttribute('data-color');
	expect(new Set([colorA, colorB]).size).toBe(2);

	// B resigns, so A takes 2 points
	b.page.once('dialog', (d) => d.accept());
	await b.page.getByRole('button', { name: 'Resign' }).click();
	await expect(a.page.getByText('You won by resignation')).toBeVisible();
	await a.page.getByRole('link', { name: 'Back to tournament' }).click();
	await a.page.waitForURL(/\/tournaments\/\d+$/);
	const rowA = a.page.locator('tbody tr', { hasText: `arena_a${t}` });
	await expect(rowA.locator('.pts')).toHaveText('2');
	await expect(a.page.locator('tbody tr', { hasText: `arena_b${t}` }).locator('.pts')).toHaveText('0');
	await expect(a.page.locator('tbody tr').first()).toContainText(`arena_a${t}`); // leader on top

	// a rematch is not forced straight away (they just played each other), so both are back waiting
	await expect(a.page.getByText(/Waiting for an opponent/)).toBeVisible();

	// the player profile page works from the standings
	await rowA.getByRole('link', { name: `arena_a${t}` }).click();
	await expect(a.page.getByRole('heading', { name: `arena_a${t}` })).toBeVisible();
	await expect(a.page.getByText('1 won')).toBeVisible();

	await a.ctx.close();
	await b.ctx.close();
});

test('leaderboard page loads and links to profiles; guests can read it', async ({ page }) => {
	await open(page, '/leaderboard');
	await expect(page.getByRole('heading', { name: 'Leaderboard' })).toBeVisible();
	await open(page, '/players/nobody_exists_here');
	await expect(page.getByText('No such player')).toBeVisible();
});

test('guests are told to sign in before joining a tournament', async ({ page }) => {
	await open(page, '/tournaments');
	await expect(page.getByText('to create or join a tournament')).toBeVisible();
});
