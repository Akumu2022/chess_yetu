import { expect, test, type Page } from '@playwright/test';
import { move, openMoves, newPlayer, open, piece, register, sq, startFriendGame, trackPageErrors } from './helpers';

trackPageErrors();

test('friend game: moves sync, clocks tick, resign ends it for both', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);

	// white clock starts at 10:00 and ticks down on its own
	await expect(a.page.locator('.clock').last()).not.toHaveText('10:00', { timeout: 5000 });

	// selecting a pawn shows exactly its two legal targets
	await sq(a.page, 'e2').click();
	await expect(a.page.locator('circle.hint')).toHaveCount(2);

	await sq(a.page, 'e5').click(); // not a legal target: nothing moves
	await expect(piece(a.page, 'e2', 'wp')).toHaveCount(1);

	await move(a.page, 'e2', 'e4');
	await expect(piece(a.page, 'e4', 'wp')).toHaveCount(1); // instant (optimistic)
	await expect(piece(b.page, 'e4', 'wp')).toHaveCount(1); // pushed to opponent

	// black is not allowed to move white's pieces or move out of turn
	await move(b.page, 'e7', 'e5');
	await expect(piece(a.page, 'e5', 'bp')).toHaveCount(1);
	await expect(a.page.locator('.moves li')).toHaveCount(2);

	b.page.once('dialog', (d) => d.accept());
	await b.page.getByRole('button', { name: 'Resign' }).click();
	await expect(b.page.getByText('You lost by resignation')).toBeVisible();
	await expect(a.page.getByText('You won by resignation')).toBeVisible();
	await expect(a.page.getByText('Casual game · not rated')).toBeVisible();

	await a.ctx.close();
	await b.ctx.close();
});

test('captured pieces are shown for each side, with the material lead', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	const takenBy = (p: Page, who: 'white' | 'black', kind: string) =>
		p.locator(`.captured[data-by="${who}"] [data-piece="${kind}"]`);

	await expect(a.page.locator('.captured [data-piece]')).toHaveCount(0); // nothing taken yet

	await move(a.page, 'e2', 'e4');
	await move(b.page, 'd7', 'd5');
	await move(a.page, 'e4', 'd5'); // white takes a pawn
	for (const p of [a.page, b.page]) {
		await expect(takenBy(p, 'white', 'bp')).toHaveCount(1);
		await expect(p.locator('.captured[data-by="white"] .lead')).toHaveText('+1');
	}
	await move(b.page, 'd8', 'd5'); // black takes it back
	for (const p of [a.page, b.page]) {
		await expect(takenBy(p, 'black', 'wp')).toHaveCount(1);
		await expect(p.locator('.lead')).toHaveCount(0); // level again
	}

	// the move list uses standard notation
	await openMoves(a.page);
	await expect(a.page.locator('.moves li')).toHaveText(['1. e4', 'd5', '2. exd5', '♕xd5']);
	await a.ctx.close();
	await b.ctx.close();
});

test('en passant counts as a capture and removes the pawn', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await move(a.page, 'e2', 'e4');
	await move(b.page, 'a7', 'a6');
	await move(a.page, 'e4', 'e5');
	await move(b.page, 'd7', 'd5');
	await move(a.page, 'e5', 'd6'); // en passant
	for (const p of [a.page, b.page]) {
		await expect(piece(p, 'd6', 'wp')).toHaveCount(1);
		await expect(piece(p, 'd5', 'bp')).toHaveCount(0); // the passed pawn is gone
		await expect(p.locator('.captured[data-by="white"] [data-piece="bp"]')).toHaveCount(1);
	}
	await a.ctx.close();
	await b.ctx.close();
});

test('draw offer is accepted by the opponent', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await a.page.getByRole('button', { name: 'Offer draw' }).click();
	await expect(b.page.getByRole('button', { name: 'Accept draw' })).toBeVisible();
	await b.page.getByRole('button', { name: 'Accept draw' }).click();
	await expect(a.page.getByText('Draw by agreement')).toBeVisible();
	await expect(b.page.getByText('Draw by agreement')).toBeVisible();
	await a.ctx.close();
	await b.ctx.close();
});

test('pawn promotion shows a picker and the chosen piece reaches the opponent', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	// 1.h4 g5 2.hxg5 h6 3.gxh6 Nf6 4.h7 Rg8 5.hxg8=N
	await move(a.page, 'h2', 'h4');
	await move(b.page, 'g7', 'g5');
	await move(a.page, 'h4', 'g5');
	await move(b.page, 'h7', 'h6');
	await move(a.page, 'g5', 'h6');
	await move(b.page, 'g8', 'f6');
	await move(a.page, 'h6', 'h7');
	await move(b.page, 'h8', 'g8');

	await sq(a.page, 'h7').click();
	await sq(a.page, 'g8').click();
	await expect(a.page.locator('.choice')).toHaveCount(4); // picker is up, nothing sent yet
	await expect(piece(b.page, 'g8', 'br')).toHaveCount(1);
	await a.page.locator('.choice').nth(3).click(); // q, r, b, n -> knight

	await expect(piece(a.page, 'g8', 'wn')).toHaveCount(1);
	await expect(piece(b.page, 'g8', 'wn')).toHaveCount(1);
	await openMoves(b.page);
	await expect(b.page.locator('.moves li').last()).toContainText('hxg8=♘'); // readable notation, not raw f6g7
	await a.ctx.close();
	await b.ctx.close();
});

test('reconnect: a player who drops offline resyncs the moves they missed', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await move(a.page, 'e2', 'e4');
	await expect(piece(b.page, 'e4', 'wp')).toHaveCount(1);

	await b.ctx.setOffline(true);
	await expect(a.page.getByText('Opponent disconnected')).toBeVisible({ timeout: 25_000 });
	await expect(b.page.getByText('Reconnecting')).toBeVisible({ timeout: 25_000 });

	await b.ctx.setOffline(false);
	await expect(b.page.getByText('Reconnecting')).toBeHidden({ timeout: 20_000 });
	await expect(a.page.getByText('Opponent disconnected')).toBeHidden();

	// the game continues normally after the resume
	await move(b.page, 'e7', 'e5');
	await expect(piece(a.page, 'e5', 'bp')).toHaveCount(1);
	await a.ctx.close();
	await b.ctx.close();
});

test('refreshing the page rejoins the same seat with the position intact', async ({ browser }) => {
	const { a, b } = await startFriendGame(browser);
	await move(a.page, 'd2', 'd4');
	await expect(piece(b.page, 'd4', 'wp')).toHaveCount(1);
	await b.page.reload();
	await expect(b.page.locator('main[data-color="black"]')).toBeVisible();
	await expect(piece(b.page, 'd4', 'wp')).toHaveCount(1);
	await move(b.page, 'd7', 'd5');
	await expect(piece(a.page, 'd5', 'bp')).toHaveCount(1);
	await a.ctx.close();
	await b.ctx.close();
});

test('joining a full game or a bad code shows a clear error', async ({ browser, page }) => {
	const { a, b, url } = await startFriendGame(browser);
	const c = await newPlayer(browser);
	await open(c.page, url);
	await expect(c.page.getByText('already has two players')).toBeVisible();

	await open(page, '/');
	await page.getByLabel('Game link or code').fill('nope123');
	await page.getByRole('button', { name: 'Join', exact: true }).click();
	await expect(page.getByText('No game with that code')).toBeVisible();
	for (const p of [a, b, c]) await p.ctx.close();
});

test('rated quick match: sign up, pair, play to checkmate, ratings update', async ({ browser }) => {
	const a = await newPlayer(browser);
	const b = await newPlayer(browser);
	const tag = Date.now().toString().slice(-6);
	await register(a.page, `kamau${tag}`);
	await register(b.page, `achieng${tag}`);

	// wrong password is rejected with a message
	const c = await newPlayer(browser);
	await open(c.page, '/login');
	await c.page.getByLabel('Username').fill(`kamau${tag}`);
	await c.page.getByLabel('Password').fill('totally-wrong');
	await c.page.getByRole('button', { name: 'Sign in', exact: true }).click();
	await expect(c.page.getByText('Wrong username or password')).toBeVisible();
	await c.ctx.close();

	await a.page.getByRole('button', { name: /Play online/ }).click();
	await expect(a.page.getByText('Searching for an opponent')).toBeVisible();
	await b.page.getByRole('button', { name: /Play online/ }).click();
	await a.page.waitForURL(/\/game\//, { timeout: 15_000 });
	await b.page.waitForURL(/\/game\//, { timeout: 15_000 });

	// the two players got opposite colours and both see the rated names
	await expect(a.page.locator('main[data-color]')).toBeVisible();
	const colorA = await a.page.locator('main').getAttribute('data-color');
	const [white, black] = colorA === 'white' ? [a, b] : [b, a];
	await expect(white.page.getByText(`(1500)`).first()).toBeVisible();

	// fool's mate: black wins
	// wait for each move to reach both boards so the next click is never sent out of turn
	const play = async (mover: typeof white, other: typeof white, from: string, to: string, kind: string) => {
		await move(mover.page, from, to);
		await expect(piece(mover.page, to, kind)).toHaveCount(1);
		await expect(piece(other.page, to, kind)).toHaveCount(1);
	};
	await play(white, black, 'f2', 'f3', 'wp');
	await play(black, white, 'e7', 'e5', 'bp');
	await play(white, black, 'g2', 'g4', 'wp');
	await move(black.page, 'd8', 'h4');

	await expect(black.page.getByText('You won by checkmate')).toBeVisible();
	await expect(white.page.getByText('You lost by checkmate')).toBeVisible();
	await expect(black.page.getByText(/Rating \+\d+\.\d/)).toBeVisible();
	await expect(white.page.getByText(/Rating -\d+\.\d/)).toBeVisible();

	// lobby shows the new ratings and the game in history
	await black.page.getByRole('link', { name: 'New game' }).click();
	await expect(black.page.locator('.rating')).toHaveText(/^16\d\d\?$/);
	await expect(black.page.locator('.history li').first()).toContainText('Won');
	await white.page.getByRole('link', { name: 'New game' }).click();
	await expect(white.page.locator('.rating')).toHaveText(/^13\d\d\?$/);
	await expect(white.page.locator('.history li').first()).toContainText('Lost');

	// session survives a reload; sign out returns to guest
	await black.page.reload();
	await expect(black.page.locator('.rating')).toBeVisible();
	await black.page.getByRole('button', { name: 'Sign out' }).click();
	await expect(black.page.locator('header').getByRole('link', { name: 'Sign in' })).toBeVisible();
	await a.ctx.close();
	await b.ctx.close();
});

test('cancelling quick match leaves the queue', async ({ browser }) => {
	const a = await newPlayer(browser);
	const b = await newPlayer(browser);
	const tag = Date.now().toString().slice(-6);
	await register(a.page, `zuri${tag}`);
	await register(b.page, `omondi${tag}`);
	await a.page.getByRole('button', { name: /Play online/ }).click();
	await a.page.getByRole('button', { name: /cancel/ }).click();
	await b.page.getByRole('button', { name: /Play online/ }).click();
	// B must NOT be paired with the player who cancelled
	await expect(b.page.getByText('Searching for an opponent')).toBeVisible();
	await b.page.waitForTimeout(3500);
	await expect(b.page).toHaveURL(/\/$/);
	await a.ctx.close();
	await b.ctx.close();
});
