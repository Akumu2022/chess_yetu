import { Chess } from 'chess.js';

const VALUE: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9 };
const ORDER = ['q', 'r', 'b', 'n', 'p'];

export interface Replay {
	/** Moves in standard notation (Nf3, exd5, O-O, e8=Q+). */
	san: string[];
	/** Piece types taken BY white (so these are black pieces), most valuable first. */
	byWhite: string[];
	/** Piece types taken BY black (white pieces), most valuable first. */
	byBlack: string[];
}

const byValue = (a: string, b: string) => ORDER.indexOf(a) - ORDER.indexOf(b);

/** Replays UCI moves from the start position, collecting notation and captures (en passant included). */
export function replay(moves: string[]): Replay {
	const chess = new Chess();
	const san: string[] = [];
	const byWhite: string[] = [];
	const byBlack: string[] = [];
	for (const uci of moves) {
		let m;
		try {
			m = chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
		} catch {
			break; // should never happen: the server only sends legal moves
		}
		san.push(m.san);
		if (m.captured) (m.color === 'w' ? byWhite : byBlack).push(m.captured);
	}
	return { san, byWhite: byWhite.sort(byValue), byBlack: byBlack.sort(byValue) };
}

/** Material on the board, white minus black, in pawns. Positive means white is ahead. */
export function materialDiff(fen: string): number {
	let diff = 0;
	for (const ch of fen.split(' ')[0]) {
		const v = VALUE[ch.toLowerCase()];
		if (v) diff += ch === ch.toUpperCase() ? v : -v;
	}
	return diff;
}
