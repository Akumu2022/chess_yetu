import { expect, test } from '@playwright/test';
import { newPlayer, open, register, startFriendGame, trackPageErrors } from './helpers';

trackPageErrors();

const tag = () => Date.now().toString().slice(-6) + Math.floor(Math.random() * 90 + 10);

test('every page has a way back, and it goes somewhere sensible', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await register(page, `nav${tag()}`);

	const cases: [string, RegExp, string][] = [
		['/puzzles', /← Back/, '/'],
		['/tournaments', /← Lobby/, '/'],
		['/leaderboard', /← Lobby/, '/'],
		['/login', /← Back/, '/']
	];
	for (const [url, label, target] of cases) {
		await open(page, url);
		await page.getByRole('link', { name: label }).click();
		await page.waitForURL(`**${target}`);
	}

	// a tournament goes back to the list; a profile goes back to the leaderboard
	await open(page, '/players/someone_unknown');
	await expect(page.getByRole('link', { name: /← Leaderboard/ })).toBeVisible();
	await open(page, '/review/nothing');
	await expect(page.getByRole('link', { name: /← Lobby/ })).toBeVisible();
	await ctx.close();
});

test('a game has a back link to the lobby that does not end the game', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await a.page.getByTestId('game-back').click();
	await a.page.waitForURL(/\/$/);
	// the opponent sees them as away, and the game is still there to return to
	await expect(b.page.locator('.dot.off')).toBeVisible({ timeout: 10_000 });
	await a.page.goBack();
	await expect(a.page.locator('main[data-color="white"], main[data-color="black"]')).toBeVisible();
	await expect(b.page.locator('.dot.off')).toBeHidden({ timeout: 15_000 });
	await a.ctx.close();
	await b.ctx.close();
});

test('a game that no longer exists says so and stops reconnecting', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await ctx.addInitScript(() =>
		sessionStorage.setItem(
			'chess_yetu:seat:ghostgame',
			JSON.stringify({ game_id: 'ghostgame', color: 'white', token: 'x' })
		)
	);
	await open(page, '/game/ghostgame');
	await expect(page.getByText('This game is no longer available')).toBeVisible();
	await expect(page.getByText('Reconnecting')).toHaveCount(0);
	await page.getByRole('link', { name: 'Lobby', exact: true }).last().click();
	await page.waitForURL(/\/$/);
	await ctx.close();
});

test('searching polls once per tick, and cancelling stops all polling', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await register(page, `dbl${tag()}`);
	let polls = 0;
	await page.route('**/queue', (route) => {
		if (route.request().method() === 'GET') polls++;
		return route.continue();
	});
	const button = page.getByRole('button', { name: /Play online/ });
	await button.click();
	await expect(page.getByText('Searching for an opponent')).toBeVisible();
	await page.waitForTimeout(6000);
	// one poller at 1.5 s is about 4 polls in 6 s; two would be about 8
	expect(polls).toBeLessThanOrEqual(5);
	await page.getByRole('button', { name: /cancel/ }).click();
	const before = polls;
	await page.waitForTimeout(3500);
	expect(polls).toBe(before); // nothing keeps polling after cancel
	await ctx.close();
});
