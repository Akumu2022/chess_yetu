import { expect, test } from '@playwright/test';
import { move, openMoves, piece, startFriendGame, trackPageErrors } from './helpers';
import { startLagProxy, type LagProxy } from './netproxy';

trackPageErrors();

// Launch checklist: "Game completes correctly with 500 ms latency and three forced disconnects."
const BACKEND = 8766;
const PROXY = 8767;

let proxy: LagProxy;
test.beforeAll(async () => {
	proxy = await startLagProxy(PROXY, BACKEND, 250); // 250 ms each way = 500 ms round trip
});
test.afterAll(async () => {
	await proxy.close();
});

test('game completes with 500 ms latency and three forced disconnects', async ({ browser }) => {
	test.setTimeout(120_000);
	const { a, b } = await startFriendGame(browser, { apiPort: PROXY });

	/** Cut every connection, then wait until both players are back online. */
	async function dropAndRecover() {
		proxy.killAll();
		for (const p of [a.page, b.page]) {
			await expect(p.getByText('Reconnecting')).toBeVisible({ timeout: 10_000 });
		}
		for (const p of [a.page, b.page]) {
			await expect(p.getByText('Reconnecting')).toBeHidden({ timeout: 30_000 });
		}
	}

	// 1.f3 e5 2.g4 Qh4#, with a dropout after each of the first three moves
	await move(a.page, 'f2', 'f3');
	await expect(piece(b.page, 'f3', 'wp')).toHaveCount(1, { timeout: 10_000 });
	await dropAndRecover();

	await move(b.page, 'e7', 'e5');
	await expect(piece(a.page, 'e5', 'bp')).toHaveCount(1, { timeout: 10_000 });
	await dropAndRecover();

	await move(a.page, 'g2', 'g4');
	await expect(piece(b.page, 'g4', 'wp')).toHaveCount(1, { timeout: 10_000 });
	await dropAndRecover();

	// every earlier move survived the reconnects
	for (const p of [a.page, b.page]) {
		await expect(piece(p, 'f3', 'wp')).toHaveCount(1);
		await expect(piece(p, 'e5', 'bp')).toHaveCount(1);
		await expect(piece(p, 'g4', 'wp')).toHaveCount(1);
	}

	await move(b.page, 'd8', 'h4');
	await expect(b.page.getByText('You won by checkmate')).toBeVisible({ timeout: 15_000 });
	await expect(a.page.getByText('You lost by checkmate')).toBeVisible({ timeout: 15_000 });
	await openMoves(a.page);
	await expect(a.page.locator('.moves li')).toHaveText(['1. f3', 'e5', '2. g4', '♕h4#']);

	await a.ctx.close();
	await b.ctx.close();
});

test('a move is not accepted while offline, and play resumes cleanly after', async ({ browser }) => {
	test.setTimeout(90_000);
	const { a, b } = await startFriendGame(browser, { apiPort: PROXY });

	await a.ctx.setOffline(true);
	await expect(a.page.getByText('Reconnecting')).toBeVisible({ timeout: 25_000 });

	// the board does not pretend to accept a move that could never be sent
	await a.page.locator('rect[data-square="e2"]').click();
	await expect(a.page.locator('circle.hint')).toHaveCount(0);
	await expect(piece(a.page, 'e2', 'wp')).toHaveCount(1);

	await a.ctx.setOffline(false);
	await expect(a.page.getByText('Reconnecting')).toBeHidden({ timeout: 30_000 });
	await move(a.page, 'e2', 'e4');
	await expect(piece(b.page, 'e4', 'wp')).toHaveCount(1, { timeout: 10_000 });
	await a.ctx.close();
	await b.ctx.close();
});
