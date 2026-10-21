import { expect, test, type Page } from '@playwright/test';
import { move, newPlayer, open, register, trackPageErrors } from './helpers';

trackPageErrors();

const API = 'http://localhost:8766';
const tag = () => Date.now().toString().slice(-6) + Math.floor(Math.random() * 90 + 10);
const NICK = /^[A-Z][a-z]+[A-Z][a-z]+\d{3}$/;

/** On /kids as a signed-in parent: set the PIN. */
async function setPin(page: Page, pin = '4321') {
	await page.getByPlaceholder('New PIN (4 to 6 digits)').fill(pin);
	await page.getByRole('button', { name: 'Save PIN' }).click();
	await expect(page.getByText('PIN saved')).toBeVisible();
}

/** Add a child with consent; returns the generated nickname. */
async function addChild(page: Page): Promise<string> {
	const before = await page.locator('article.child').count();
	await page.getByLabel(/I am this child/).check();
	await page.getByRole('button', { name: 'Create profile' }).click();
	await expect(page.locator('article.child')).toHaveCount(before + 1);
	const nick = (await page.locator('article.child .nick').last().textContent())!.trim();
	expect(nick).toMatch(NICK);
	return nick;
}

test('guests see what kids mode promises, and a way to sign in', async ({ page }) => {
	await open(page, '/kids');
	await expect(page.getByText('Kids only play other kids')).toBeVisible();
	await expect(page.getByRole('link', { name: /Sign in or create a parent account/ })).toBeVisible();
	await open(page, '/');
	await expect(page.getByRole('link', { name: /Chess for kids/ })).toBeVisible();
});

test('parent journey: consent, PIN, child plays a friendly bot, parent PIN to return, sees and deletes', async ({
	browser
}) => {
	test.setTimeout(120_000);
	const { ctx, page } = await newPlayer(browser);
	await register(page, `mama${tag()}`);
	await open(page, '/kids');
	await expect(page.getByText('No child profiles yet')).toBeVisible();

	// consent is required before anything is created
	await expect(page.getByRole('button', { name: 'Create profile' })).toBeDisabled();
	// a child cannot be handed the device before a PIN exists
	const nick = await addChild(page);
	await expect(page.getByRole('button', { name: `Play as ${nick}` })).toBeDisabled();
	await setPin(page, '4321');

	// daily limit is adjustable and shown
	await expect(page.getByText('of 60 min')).toBeVisible();
	await page.locator('article.child select').selectOption('30');
	await expect(page.getByText('of 30 min')).toBeVisible();

	// hand the device to the child
	await page.getByRole('button', { name: `Play as ${nick}` }).click();
	await expect(page.getByText(`Hi ${nick}!`)).toBeVisible();
	await expect(page.getByText(/30 minutes of play left today/)).toBeVisible();

	// the adult lobby is out of reach: it bounces back to kids mode ...
	await open(page, '/');
	await page.waitForURL('**/kids');
	// ... and the server refuses adult features for this session
	const status = await page.evaluate(async (api) => {
		const token = sessionStorage.getItem('chess_yetu:auth');
		const r = await fetch(`${api}/me`, { headers: { authorization: `Bearer ${token}` } });
		return r.status;
	}, API);
	expect(status).toBe(403);

	// play a friendly computer, with preset chat
	await page.getByRole('button', { name: /Zuri the Gentle/ }).click();
	await page.waitForURL(/\/game\//);
	await expect(page.getByText('Zuri the Gentle')).toBeVisible();
	await page.getByRole('button', { name: 'Good luck!', exact: true }).click();
	await expect(page.locator('.bubble.mine')).toHaveText('Good luck!');
	await expect(page.locator('main[data-color]')).toBeVisible();
	const mine = await page.locator('main').getAttribute('data-color');
	if (mine === 'white') {
		await move(page, 'e2', 'e4');
		await expect(page.locator('.moves li')).toHaveCount(2, { timeout: 15_000 });
	} else {
		await expect(page.locator('.moves li')).toHaveCount(1, { timeout: 15_000 }); // the bot opened
	}
	page.once('dialog', (d) => d.accept());
	await page.getByRole('button', { name: 'Resign' }).click();
	await expect(page.getByText('Every game makes you stronger')).toBeVisible(); // gentle result
	await expect(page.getByText(/Rating -/)).toHaveCount(0); // children never see a rating drop
	await page.getByRole('link', { name: 'Play again' }).click();
	await page.waitForURL('**/kids');
	await expect(page.getByText(`Hi ${nick}!`)).toBeVisible();

	// leaving kids mode needs the PIN
	await page.getByRole('button', { name: /leave kids mode/ }).click();
	await page.getByPlaceholder('Parent PIN').fill('0000');
	await page.getByRole('button', { name: 'Open' }).click();
	await expect(page.getByText('Wrong PIN')).toBeVisible();
	await page.getByPlaceholder('Parent PIN').fill('4321');
	await page.getByRole('button', { name: 'Open' }).click();
	await expect(page.getByText('Your children')).toBeVisible();

	// the parent sees the game, then erases everything
	await page.getByRole('button', { name: 'See games' }).click();
	await expect(page.getByText(/vs Zuri the Gentle/)).toBeVisible();
	page.once('dialog', (d) => d.accept());
	await page.getByRole('button', { name: 'Delete', exact: true }).click();
	await expect(page.getByText(/and all their data were deleted/)).toBeVisible();
	await expect(page.locator('article.child')).toHaveCount(0);
	await ctx.close();
});

test('two kids on one device-browser are matched with each other and can only chat with presets', async ({
	browser
}) => {
	test.setTimeout(120_000);
	const { ctx, page: tab1 } = await newPlayer(browser);
	await register(tab1, `mama${tag()}`);
	await open(tab1, '/kids');
	await addChild(tab1);
	await addChild(tab1);
	await setPin(tab1);
	const tab2 = await ctx.newPage();
	await open(tab2, '/kids'); // pins the parent's sign-in to this tab before tab 1 switches to a child

	await tab1.getByRole('button', { name: /^Play as/ }).first().click();
	await tab2.getByRole('button', { name: /^Play as/ }).last().click();
	await expect(tab1.getByText(/^Hi /)).toBeVisible();
	await expect(tab2.getByText(/^Hi /)).toBeVisible();
	const hi1 = await tab1.getByText(/^Hi /).textContent();
	const hi2 = await tab2.getByText(/^Hi /).textContent();
	expect(hi1).not.toEqual(hi2); // two different children

	await tab1.getByRole('button', { name: 'Find a kid to play' }).click();
	await expect(tab1.getByText('Looking for a friend')).toBeVisible();
	await tab2.getByRole('button', { name: 'Find a kid to play' }).click();
	await tab1.waitForURL(/\/game\//, { timeout: 15_000 });
	await tab2.waitForURL(/\/game\//, { timeout: 15_000 });

	// the only way to talk is the preset buttons; there is no text box at all
	await expect(tab1.locator('input[type="text"], textarea')).toHaveCount(0);
	await tab1.getByRole('button', { name: 'Hello!', exact: true }).click();
	await expect(tab2.locator('.bubble[data-said="hi"]')).toHaveText('Hello!');
	await tab2.getByRole('button', { name: 'Good game!', exact: true }).click();
	await expect(tab1.locator('.bubble[data-said="gg"]')).toHaveText('Good game!');

	// and they can play: white moves, black sees it
	const c1 = await tab1.locator('main').getAttribute('data-color');
	const [white, black] = c1 === 'white' ? [tab1, tab2] : [tab2, tab1];
	await move(white, 'e2', 'e4');
	await expect(black.locator('[data-piece="wp"][data-at="e4"]')).toHaveCount(1, { timeout: 10_000 });
	await ctx.close();
});

test('when the daily time is used up, play buttons are off and the child is told kindly', async ({ browser }) => {
	const { ctx, page } = await newPlayer(browser);
	// pretend the server says this child has no time left
	await ctx.addInitScript(() => sessionStorage.setItem('chess_yetu:auth', 'fake-kid-token'));
	await page.route('**/whoami', (route) =>
		route.fulfill({
			contentType: 'application/json',
			body: JSON.stringify({
				kind: 'kid',
				child: { id: 1, nickname: 'BraveSimba123', rating: 1500, rd: 350, games: 3, birth_year: 2018,
					daily_limit_min: 30, minutes_today: 30, minutes_left: 0 }
			})
		})
	);
	await page.route('**/kids/me/games', (route) => route.fulfill({ contentType: 'application/json', body: '[]' }));
	await open(page, '/kids');
	await expect(page.getByText('Time’s up for today')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Find a kid to play' })).toBeDisabled();
	for (const bot of ['Zuri the Gentle', 'Simba the Brave', 'Mzee Kobe the Wise']) {
		await expect(page.getByRole('button', { name: new RegExp(bot) })).toBeDisabled();
	}
	await ctx.close();
});
