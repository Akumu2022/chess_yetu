import { expect, test, type Browser, type BrowserContext, type BrowserContextOptions, type Page } from '@playwright/test';

const pageErrors: string[] = [];

/** Call once at the top of a spec: any uncaught exception in any page fails the test. */
export function trackPageErrors() {
	test.beforeEach(() => void (pageErrors.length = 0));
	test.afterEach(() => expect(pageErrors, 'uncaught page errors').toEqual([]));
}

export interface PlayerOptions {
	/** Point this player's app at a different backend port (e.g. through the lag proxy). */
	apiPort?: number;
	context?: BrowserContextOptions;
}

export interface Player {
	ctx: BrowserContext;
	page: Page;
}

/** Each player gets an isolated browser context (own localStorage), like two real devices. */
export async function newPlayer(browser: Browser, opts: PlayerOptions = {}): Promise<Player> {
	const ctx = await browser.newContext(opts.context);
	if (opts.apiPort) {
		await ctx.addInitScript((port) => localStorage.setItem('chess_yetu:api_port', String(port)), opts.apiPort);
	}
	const page = await ctx.newPage();
	page.on('pageerror', (e) => (console.log('PAGEERROR', e.message), pageErrors.push(e.message)));
	page.on('console', (m) => {
		const text = m.text();
		// Expected noise: the favicon and deliberate network drops.
		if (m.type() === 'error' && !/favicon|404|ERR_INTERNET_DISCONNECTED|WebSocket connection/.test(text)) {
			console.log('CONSOLE', text);
		}
	});
	return { ctx, page };
}

/** Navigate and wait for hydration; clicking earlier would hit a page with no handlers yet. */
export async function open(page: Page, url: string) {
	await page.goto(url);
	await page.locator('body[data-hydrated="true"]').waitFor();
}

export const sq = (page: Page, name: string) => page.locator(`rect[data-square="${name}"]`);
export const piece = (page: Page, at: string, kind: string) =>
	page.locator(`[data-piece="${kind}"][data-at="${at}"]`);

export async function move(page: Page, from: string, to: string) {
	await sq(page, from).click();
	await sq(page, to).click();
}

/** A creates a friend game from the lobby; B opens the link as a guest. */
export async function startFriendGame(browser: Browser, opts: PlayerOptions = {}) {
	const a = await newPlayer(browser, opts);
	const b = await newPlayer(browser, opts);
	await open(a.page, '/');
	await a.page.getByRole('button', { name: 'Challenge a friend (link)' }).click();
	await a.page.waitForURL(/\/game\//);
	await expect(a.page.getByText('Waiting for an opponent')).toBeVisible();
	await open(b.page, a.page.url());
	await expect(b.page.locator('main[data-color="black"]')).toBeVisible();
	await expect(a.page.getByText('Waiting for an opponent')).toBeHidden(); // game_started reached A
	return { a, b, url: a.page.url() };
}

export async function register(page: Page, username: string) {
	await open(page, '/login');
	await page.getByRole('button', { name: 'Create an account' }).click();
	await page.getByLabel('Username').fill(username);
	await page.getByLabel('Password').fill('password123');
	await page.getByRole('button', { name: 'Create account', exact: true }).click();
	await page.waitForURL('/');
	await expect(page.getByText(username)).toBeVisible();
}
