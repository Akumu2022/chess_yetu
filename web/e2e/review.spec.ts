import { expect, test } from '@playwright/test';
import { move, piece, startFriendGame, trackPageErrors } from './helpers';

trackPageErrors();

test('after a game, Review game shows Stockfish grades, and the blunder is flagged', async ({ browser }) => {
	test.setTimeout(120_000);
	const { a, b } = await startFriendGame(browser);
	const [white, black] = (await a.page.locator('main').getAttribute('data-color')) === 'white' ? [a, b] : [b, a];

	// fool's mate: 1.f3 e5 2.g4?? Qh4#
	await move(white.page, 'f2', 'f3');
	await expect(piece(black.page, 'f3', 'wp')).toHaveCount(1);
	await move(black.page, 'e7', 'e5');
	await expect(piece(white.page, 'e5', 'bp')).toHaveCount(1);
	await move(white.page, 'g2', 'g4');
	await expect(piece(black.page, 'g4', 'wp')).toHaveCount(1);
	await move(black.page, 'd8', 'h4');
	await expect(white.page.getByText('You lost by checkmate')).toBeVisible();

	await white.page.getByRole('link', { name: 'Review game' }).click();
	await white.page.waitForURL('**/review/**');
	await expect(white.page.getByText(/vs .* · Black won \(checkmate\)/)).toBeVisible();
	await expect(white.page.locator('.side[data-side="white"] .acc')).toBeVisible({ timeout: 60_000 });

	// step back to the blunder: move 3 (g4)
	await white.page.getByRole('button', { name: 'Previous move' }).click(); // from Qh4# back to g4
	await expect(white.page.locator('.comment[data-cls="blunder"]')).toContainText('g4 was a blunder');
	await expect(white.page.locator('.comment')).toContainText('Better was');

	// the move list marks it, and the final position shows black mating
	await expect(white.page.locator('.mv[data-cls="blunder"]')).toHaveCount(1);
	await white.page.keyboard.press('End');
	await expect(piece(white.page, 'h4', 'bq')).toHaveCount(1);
	await expect(white.page.getByText('Black mates')).toBeVisible();

	// a second visit is served from the stored analysis
	await white.page.reload();
	await expect(white.page.locator('.side[data-side="black"] .acc')).toBeVisible();
	await a.ctx.close();
	await b.ctx.close();
});

test('an unknown review link says so', async ({ page }) => {
	await page.goto('/review/doesnotexist');
	await expect(page.getByText('No finished game with that link')).toBeVisible();
});
