import { expect, test } from '@playwright/test';
import { move, open, startFriendGame, trackPageErrors } from './helpers';

trackPageErrors();

test('checkmate: the winner gets a trophy card, the loser a clear defeat card, and either can close it', async ({
	browser
}) => {
	const { a: white, b: black } = await startFriendGame(browser);
	// fool's mate: black wins
	await move(white.page, 'f2', 'f3');
	await move(black.page, 'e7', 'e5');
	await move(white.page, 'g2', 'g4');
	await move(black.page, 'd8', 'h4');

	const won = black.page.getByRole('dialog');
	await expect(won).toBeVisible();
	await expect(won).toHaveAttribute('data-result', 'win');
	await expect(won.getByRole('heading', { name: 'You won!' })).toBeVisible();
	await expect(won.getByText('by checkmate', { exact: true })).toBeVisible();
	await expect(won.getByText('0-1')).toBeVisible();
	await expect(won.getByRole('link', { name: 'Review game' })).toBeVisible();
	await expect(won.getByRole('link', { name: 'New game' })).toBeVisible();

	const lost = white.page.getByRole('dialog');
	await expect(lost).toHaveAttribute('data-result', 'loss');
	await expect(lost.getByRole('heading', { name: 'You lost' })).toBeVisible();
	await expect(lost.getByText('Casual game · not rated')).toBeVisible();

	// closing the card leaves the final board, and "Show result" brings it back
	await won.getByRole('button', { name: 'Close result' }).click();
	await expect(black.page.getByRole('dialog')).toHaveCount(0);
	await expect(black.page.getByText('You won by checkmate')).toBeVisible(); // the slim bar keeps the result
	await expect(black.page.getByRole('link', { name: 'New game' })).toBeVisible();
	await black.page.getByRole('button', { name: 'Show result' }).click();
	await expect(black.page.getByRole('dialog')).toBeVisible();

	// Escape closes it too
	await black.page.keyboard.press('Escape');
	await expect(black.page.getByRole('dialog')).toHaveCount(0);

	await white.ctx.close();
	await black.ctx.close();
});

test('a draw is shown as a draw for both players', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await a.page.getByRole('button', { name: 'Offer draw' }).click();
	await b.page.getByRole('button', { name: 'Accept draw' }).click();
	for (const p of [a.page, b.page]) {
		const card = p.getByRole('dialog');
		await expect(card).toHaveAttribute('data-result', 'draw');
		await expect(card.getByRole('heading', { name: 'Draw' })).toBeVisible();
		await expect(card.getByText('by agreement', { exact: true })).toBeVisible();
	}
	await a.ctx.close();
	await b.ctx.close();
});

test('against the computer: resign, then Rematch starts a fresh game with the same settings', async ({ page }) => {
	await open(page, '/');
	await page.getByRole('group', { name: 'Difficulty' }).getByRole('button', { name: 'Beginner' }).click();
	await page.getByRole('group', { name: 'Your colour' }).getByRole('button', { name: 'White' }).click();
	await page.getByRole('button', { name: /Play vs computer/ }).click();
	await page.waitForURL(/\/game\//);
	const firstGame = page.url();
	await expect(page.locator('main[data-color="white"]')).toBeVisible();

	page.once('dialog', (d) => d.accept());
	await page.getByRole('button', { name: 'Resign' }).click();
	const card = page.getByRole('dialog');
	await expect(card).toHaveAttribute('data-result', 'loss');
	await card.getByRole('button', { name: 'Rematch' }).click();

	await page.waitForURL((u) => u.href !== firstGame && /\/game\//.test(u.href));
	await expect(page.getByText('Stockfish · Beginner')).toBeVisible();
	await expect(page.locator('main[data-color="white"]')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Resign' })).toBeVisible(); // a live game, no card
	await expect(page.getByRole('dialog')).toHaveCount(0);
});

test('the card is a proper dialog: focus lands on the main action', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await a.page.getByRole('button', { name: 'Offer draw' }).click();
	await b.page.getByRole('button', { name: 'Accept draw' }).click();
	await expect(a.page.getByRole('dialog')).toBeVisible();
	// a draw with no moves has nothing to review, so "New game" is the main action
	await expect(a.page.getByRole('link', { name: 'New game' })).toBeFocused();
	await a.ctx.close();
	await b.ctx.close();
});
