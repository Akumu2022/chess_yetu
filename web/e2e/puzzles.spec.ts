import { Chess } from 'chess.js';
import { expect, test, type Page } from '@playwright/test';
import { move, newPlayer, open, register, trackPageErrors } from './helpers';

trackPageErrors();

const tag = () => Date.now().toString().slice(-6) + Math.floor(Math.random() * 90 + 10);

/** A move that mates in `n` (any defence): tiny search, fine for puzzle-sized positions. */
function forcing(chess: Chess, n: number): { from: string; to: string }[] {
	const out: { from: string; to: string }[] = [];
	for (const m of chess.moves({ verbose: true })) {
		chess.move(m);
		let ok = false;
		if (chess.isCheckmate()) ok = true;
		else if (n > 1 && !chess.isGameOver()) ok = chess.moves({ verbose: true }).every((r) => {
			chess.move(r);
			const good = forcing(chess, n - 1).length > 0;
			chess.undo();
			return good;
		});
		chess.undo();
		if (ok) out.push({ from: m.from, to: m.to });
	}
	return out;
}

/** Solve the puzzle on the page by playing the moves a human would find; the defender's reply comes from the server. */
async function solveCurrent(page: Page, fen: string, depth: number) {
	const chess = new Chess(fen);
	for (let left = depth; left > 0; left--) {
		const mv = forcing(chess, left)[0];
		const answered = page.waitForResponse((r) => /\/puzzles\/\d+\/move/.test(r.url()) && r.request().method() === 'POST');
		await move(page, mv.from, mv.to);
		const body = await (await answered).json();
		chess.move(mv);
		if (left > 1) {
			expect(body.status).toBe('continue');
			chess.move({ from: body.reply.slice(0, 2), to: body.reply.slice(2, 4), promotion: body.reply[4] });
			await expect(page.getByText('Good! Keep going.')).toBeVisible();
		} else {
			expect(body.status).toBe('solved');
		}
	}
}

test('guests are asked to sign in', async ({ page }) => {
	await open(page, '/puzzles');
	await expect(page.getByText('Sign in to play puzzles')).toBeVisible();
});

test('solve three puzzles, then the day is done and the streak is 1', async ({ browser }) => {
	test.setTimeout(150_000);
	const { ctx, page } = await newPlayer(browser);
	await register(page, `pz${tag()}`);
	let nextPuzzle = page.waitForResponse((r) => r.url().includes('/puzzles/next'));
	await page.getByRole('link', { name: /Daily puzzles/ }).click();
	await page.waitForURL('**/puzzles');

	for (let i = 0; i < 3; i++) {
		const { puzzle } = await (await nextPuzzle).json();
		await expect(page.locator('.goal')).toContainText('find the checkmate');
		await expect(page.getByText(`${i} of 3 today`)).toBeVisible();
		if (i === 0) {
			// a wrong move is refused and taken back
			const c = new Chess(puzzle.fen);
			const good = new Set(forcing(c, puzzle.depth).map((m) => m.from + m.to));
			const bad = c.moves({ verbose: true }).find((m) => !good.has(m.from + m.to))!;
			await move(page, bad.from, bad.to);
			await expect(page.getByText('Not that one')).toBeVisible();
		}
		await solveCurrent(page, puzzle.fen, puzzle.depth);
		await expect(page.locator('[data-solved]')).toBeVisible();
		if (i < 2) {
			nextPuzzle = page.waitForResponse((r) => r.url().includes('/puzzles/next'));
			await page.getByRole('button', { name: 'Next puzzle' }).click();
		}
	}
	await expect(page.getByText('That was your last puzzle for today')).toBeVisible();
	await expect(page.locator('.streak')).toContainText('1-day streak');
	await page.reload();
	await expect(page.getByText('That is all for today')).toBeVisible();
	await ctx.close();
});
