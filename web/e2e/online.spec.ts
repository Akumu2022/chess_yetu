import { expect, test } from '@playwright/test';
import { move, newPlayer, open, register, trackPageErrors } from './helpers';

trackPageErrors();

const tag = () => Date.now().toString().slice(-6) + Math.floor(Math.random() * 90 + 10);

test('two tabs of ONE browser, signed in as different accounts, can be matched online', async ({ browser }) => {
	// This is the common way to test alone: both tabs share the browser's storage.
	const { ctx, page: tab1 } = await newPlayer(browser);
	const t = tag();
	await register(tab1, `solo_a${t}`);
	const tab2 = await ctx.newPage();
	await register(tab2, `solo_b${t}`); // must NOT change who tab 1 is

	await tab1.reload();
	await tab1.locator('body[data-hydrated="true"]').waitFor();
	await expect(tab1.getByText(`solo_a${t}`)).toBeVisible();
	await expect(tab2.getByText(`solo_b${t}`)).toBeVisible();

	await tab1.getByRole('button', { name: /Play online/ }).click();
	await expect(tab1.getByText('Searching for an opponent')).toBeVisible();
	await tab2.getByRole('button', { name: /Play online/ }).click();
	await tab1.waitForURL(/\/game\//, { timeout: 15_000 });
	await tab2.waitForURL(/\/game\//, { timeout: 15_000 });

	// they are different people with opposite colours, and a move reaches the other tab
	const c1 = await tab1.locator('main').getAttribute('data-color');
	const c2 = await tab2.locator('main').getAttribute('data-color');
	expect(new Set([c1, c2]).size).toBe(2);
	const [white, black] = c1 === 'white' ? [tab1, tab2] : [tab2, tab1];
	await move(white, 'e2', 'e4');
	await expect(black.locator('[data-piece="wp"][data-at="e4"]')).toHaveCount(1, { timeout: 10_000 });
	await ctx.close();
});

test('the same account searching in two tabs gets a clear explanation, not an endless wait', async ({ browser }) => {
	const { ctx, page: tab1 } = await newPlayer(browser);
	await register(tab1, `dup${tag()}`);
	const tab2 = await ctx.newPage();
	await open(tab2, '/'); // new tab starts signed in as the same account

	await tab1.getByRole('button', { name: /Play online/ }).click();
	await expect(tab1.getByText('Searching for an opponent')).toBeVisible();
	await tab2.getByRole('button', { name: /Play online/ }).click();
	await expect(tab2.getByText(/already searching in another tab/)).toBeVisible();
	await expect(tab2.getByText('Searching for an opponent')).toBeHidden();
	await tab1.getByRole('button', { name: /cancel/ }).click(); // leave the queue like a real user would
	await ctx.close();
});

test('an expired sign-in during the search stops the spinner and says so', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await register(page, `exp${tag()}`);
	await page.getByRole('button', { name: /Play online/ }).click();
	await expect(page.getByText('Searching for an opponent')).toBeVisible();

	// the server stops accepting this sign-in (what a changed signing key looks like)
	await page.route('**/queue', (route) =>
		route.request().method() === 'GET'
			? route.fulfill({ status: 401, contentType: 'application/json', body: '{"detail":"Sign in required"}' })
			: route.continue()
	);
	await expect(page.getByText('Your session expired. Please sign in again.')).toBeVisible({ timeout: 10_000 });
	await expect(page.getByText('Searching for an opponent')).toBeHidden();
	await expect(page.locator('header').getByRole('link', { name: 'Sign in' })).toBeVisible();
	await ctx.close();
});

test('a stale saved sign-in at page load leaves a clean signed-out lobby', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	await ctx.addInitScript(() => {
		localStorage.setItem('chess_yetu:auth', 'not-a-valid-token');
		sessionStorage.setItem('chess_yetu:auth', 'not-a-valid-token');
	});
	await open(page, '/');
	await expect(page.locator('header').getByRole('link', { name: 'Sign in' })).toBeVisible();
	await expect(page.getByRole('button', { name: /Play online/ })).toHaveCount(0);
	await page.getByRole('button', { name: /Play vs computer/ }).click(); // guests still can play
	await page.waitForURL(/\/game\//);
	await ctx.close();
});
