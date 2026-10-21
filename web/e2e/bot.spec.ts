import { expect, test, type Page } from '@playwright/test';

// Any uncaught exception in the page fails the test, even if the UI looks fine.
const pageErrors: string[] = [];
test.beforeEach(({ page }) => {
	pageErrors.length = 0;
	page.on('pageerror', (e) => pageErrors.push(e.message));
});
test.afterEach(() => expect(pageErrors, 'uncaught page errors').toEqual([]));

async function open(page: Page, url: string) {
	await page.goto(url);
	await page.locator('body[data-hydrated="true"]').waitFor();
}
const sq = (page: Page, name: string) => page.locator(`rect[data-square="${name}"]`);
async function move(page: Page, from: string, to: string) {
	await sq(page, from).click();
	await sq(page, to).click();
}

test('guest plays the computer: it replies, then resigning ends the game', async ({ page }) => {
	await open(page, '/');
	await page.getByRole('group', { name: 'Difficulty' }).getByRole('button', { name: 'Medium' }).click();
	await page.getByRole('group', { name: 'Your colour' }).getByRole('button', { name: 'White' }).click();
	await page.getByRole('button', { name: /Play vs computer/ }).click();
	await page.waitForURL(/\/game\//);

	await expect(page.locator('main[data-color="white"]')).toBeVisible();
	await expect(page.getByText('Stockfish · Medium')).toBeVisible();

	await move(page, 'e2', 'e4');
	await expect(page.locator('.moves li')).toHaveCount(2, { timeout: 15_000 }); // the computer answered

	// it's our turn again and the board accepts a second move
	await move(page, 'g1', 'f3');
	await expect(page.locator('.moves li')).toHaveCount(4, { timeout: 15_000 });

	page.once('dialog', (d) => d.accept());
	await page.getByRole('button', { name: 'Resign' }).click();
	await expect(page.getByText('You lost by resignation')).toBeVisible();
	await expect(page.getByText('Casual game · not rated')).toBeVisible();
});

test('when the computer plays white it makes the first move', async ({ page }) => {
	await open(page, '/');
	await page.getByRole('group', { name: 'Difficulty' }).getByRole('button', { name: 'Beginner' }).click();
	await page.getByRole('group', { name: 'Your colour' }).getByRole('button', { name: 'Black' }).click();
	await page.getByRole('button', { name: /Play vs computer/ }).click();
	await page.waitForURL(/\/game\//);

	await expect(page.locator('main[data-color="black"]')).toBeVisible();
	await expect(page.locator('.moves li')).toHaveCount(1, { timeout: 15_000 });
	// board is flipped for black: our back rank is at the top, and it's our move now
	await expect(page.getByText('Stockfish · Beginner')).toBeVisible();
	await sq(page, 'e7').click();
	await expect(page.locator('circle.hint')).toHaveCount(2);
});

test('the computer declines an early draw offer and says so', async ({ page }) => {
	await open(page, '/');
	await page.getByRole('group', { name: 'Your colour' }).getByRole('button', { name: 'White' }).click();
	await page.getByRole('button', { name: /Play vs computer/ }).click();
	await page.waitForURL(/\/game\//);
	await expect(page.locator('main[data-color="white"]')).toBeVisible();
	await page.getByRole('button', { name: 'Offer draw' }).click();
	await expect(page.getByText('The computer declined your draw offer')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Resign' })).toBeVisible(); // game goes on
});

test('stuck in the matchmaking queue: offer to play the computer instead', async ({ page }) => {
	const name = `lone${Date.now().toString().slice(-6)}`;
	await open(page, '/login');
	await page.getByRole('button', { name: 'Create an account' }).click();
	await page.getByLabel('Username').fill(name);
	await page.getByLabel('Password').fill('password123');
	await page.getByRole('button', { name: 'Create account', exact: true }).click();
	await page.waitForURL('/');

	await page.getByRole('button', { name: /Play online/ }).click();
	await expect(page.getByText('Searching for an opponent')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Play the computer instead' })).toBeVisible({ timeout: 15_000 });
	await page.getByRole('button', { name: 'Play the computer instead' }).click();
	await page.waitForURL(/\/game\//);
	await expect(page.getByText(/Stockfish/)).toBeVisible();
});
