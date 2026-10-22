/** Display choices a player can make. Saved on this device only; the app starts in light mode. */

export const THEMES = [
	{ id: 'light', name: 'Light' },
	{ id: 'dark', name: 'Dark' }
] as const;

/** Square colours (light, dark). The CSS for each lives in +layout.svelte, keyed by data-board. */
export const BOARDS = [
	{ id: 'classic', name: 'Classic', light: '#f0d9b5', dark: '#b58863' },
	{ id: 'green', name: 'Green', light: '#eeeed2', dark: '#769656' },
	{ id: 'ocean', name: 'Ocean', light: '#dee3e6', dark: '#8ca2ad' },
	{ id: 'violet', name: 'Violet', light: '#efe6f5', dark: '#8877b7' },
	{ id: 'slate', name: 'Slate', light: '#e3e3e3', dark: '#7d8796' },
	{ id: 'savanna', name: 'Savanna', light: '#f6e7b8', dark: '#c47a2c' }
] as const;

/** Piece colours (white side, black side). */
export const PIECES = [
	{ id: 'classic', name: 'Classic', white: '#ffffff', black: '#1c1c1c' },
	{ id: 'ivory', name: 'Ivory & ebony', white: '#fff6d8', black: '#3b2416' },
	{ id: 'gold', name: 'Gold & navy', white: '#f5c542', black: '#1d2d5c' },
	{ id: 'contrast', name: 'High contrast', white: '#ffffff', black: '#000000' }
] as const;

export type ThemeId = (typeof THEMES)[number]['id'];
export type BoardId = (typeof BOARDS)[number]['id'];
export type PiecesId = (typeof PIECES)[number]['id'];

interface Saved {
	theme: ThemeId;
	board: BoardId;
	pieces: PiecesId;
	hints: boolean;
	coords: boolean;
	lastMove: boolean;
	animate: boolean;
}

const KEY = 'chess_yetu:prefs';
const DEFAULTS: Saved = { theme: 'light', board: 'classic', pieces: 'classic', hints: true, coords: true, lastMove: true, animate: true };

const oneOf = <T extends { id: string }>(list: readonly T[], id: unknown, fallback: T['id']) =>
	list.some((x) => x.id === id) ? (id as T['id']) : fallback;

function read(): Saved {
	try {
		const raw = JSON.parse(localStorage.getItem(KEY) ?? '{}');
		return {
			theme: oneOf(THEMES, raw.theme, DEFAULTS.theme) as ThemeId,
			board: oneOf(BOARDS, raw.board, DEFAULTS.board) as BoardId,
			pieces: oneOf(PIECES, raw.pieces, DEFAULTS.pieces) as PiecesId,
			hints: raw.hints ?? DEFAULTS.hints,
			coords: raw.coords ?? DEFAULTS.coords,
			lastMove: raw.lastMove ?? DEFAULTS.lastMove,
			animate: raw.animate ?? DEFAULTS.animate
		};
	} catch {
		return { ...DEFAULTS };
	}
}

class Prefs {
	theme = $state<ThemeId>(DEFAULTS.theme);
	board = $state<BoardId>(DEFAULTS.board);
	pieces = $state<PiecesId>(DEFAULTS.pieces);
	/** Dots on the squares a selected piece can move to. */
	hints = $state(DEFAULTS.hints);
	/** a-h and 1-8 labels on the board edge. */
	coords = $state(DEFAULTS.coords);
	/** Tint the squares of the last move. */
	lastMove = $state(DEFAULTS.lastMove);
	/** Slide pieces from square to square instead of jumping. */
	animate = $state(DEFAULTS.animate);

	constructor() {
		if (typeof window === 'undefined') return;
		Object.assign(this, read());
		this.apply();
	}

	set<K extends keyof Saved>(key: K, value: Saved[K]) {
		(this as Saved)[key] = value;
		this.apply();
		try {
			const { theme, board, pieces, hints, coords, lastMove, animate } = this;
			localStorage.setItem(KEY, JSON.stringify({ theme, board, pieces, hints, coords, lastMove, animate }));
		} catch {}
	}

	reset() {
		for (const [k, v] of Object.entries(DEFAULTS)) this.set(k as keyof Saved, v as never);
	}

	/** Put the choices on <html>, where the stylesheets pick them up. */
	apply() {
		const el = document.documentElement;
		el.dataset.theme = this.theme;
		el.dataset.board = this.board;
		el.dataset.pieces = this.pieces;
	}
}

export const prefs = new Prefs();
