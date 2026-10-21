import { expect, test } from '@playwright/test';
import { move, newPlayer, open, trackPageErrors } from './helpers';

trackPageErrors();

async function createdGame(a: Awaited<ReturnType<typeof newPlayer>>) {
	await open(a.page, '/');
	await a.page.getByRole('button', { name: 'Challenge a friend (link)' }).click();
	await a.page.waitForURL(/\/game\//);
	await expect(a.page.getByText('Waiting for an opponent')).toBeVisible();
	return a.page.url();
}

for (const how of ['full link', 'bare code', 'link with spaces and a query']) {
	test(`a friend can join by pasting the ${how} in the lobby, and moves cross both ways`, async ({ browser }) => {
		const a = await newPlayer(browser);
		const b = await newPlayer(browser);
		const url = await createdGame(a);
		const code = new URL(url).pathname.split('/').pop()!;
		const pasted = how === 'full link' ? url : how === 'bare code' ? code : `  ${url}?utm=share  `;

		await open(b.page, '/');
		await b.page.getByLabel('Game link or code').fill(pasted);
		await b.page.getByRole('button', { name: 'Join', exact: true }).click();
		await b.page.waitForURL(`**/game/${code}`);
		await expect(b.page.locator('main[data-color="black"]')).toBeVisible();
		await expect(a.page.getByText('Waiting for an opponent')).toBeHidden();

		await move(a.page, 'e2', 'e4');
		await expect(b.page.locator('[data-piece="wp"][data-at="e4"]')).toHaveCount(1, { timeout: 10_000 });
		await move(b.page, 'e7', 'e5');
		await expect(a.page.locator('[data-piece="bp"][data-at="e5"]')).toHaveCount(1, { timeout: 10_000 });
		await a.ctx.close();
		await b.ctx.close();
	});
}

test('a wrong code says so plainly', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/');
	await page.getByLabel('Game link or code').fill('http://localhost/game/doesnotexist');
	await page.getByRole('button', { name: 'Join', exact: true }).click();
	await expect(page.getByText('No game with that code')).toBeVisible();
	await ctx.close();
});

test('the lobby explains what the time control means', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await open(page, '/');
	await page.getByRole('button', { name: '5+3', exact: true }).click();
	await expect(page.getByText(/5 minutes on their clock, plus 3 extra seconds after every move/)).toBeVisible();
	await page.getByRole('button', { name: '10+0', exact: true }).click();
	await expect(page.getByText(/no extra time per move/)).toBeVisible();
	await ctx.close();
});
