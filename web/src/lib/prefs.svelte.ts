/** Display choices a player can make. Saved on this device only; the app starts in light mode. */

export const THEMES = [
	{ id: 'light', name: 'Light' },
	{ id: 'dark', name: 'Dark' }
] as const;

/** Square colours (light, dark) and how the squares are surfaced. The CSS colours live in +layout.svelte, keyed by data-board. */
export const BOARDS = [
	{ id: 'classic', name: 'Classic', group: 'Colours', light: '#f0d9b5', dark: '#b58863', surface: 'solid' },
	{ id: 'green', name: 'Green', group: 'Colours', light: '#eeeed2', dark: '#769656', surface: 'solid' },
	{ id: 'ocean', name: 'Ocean', group: 'Colours', light: '#dee3e6', dark: '#8ca2ad', surface: 'solid' },
	{ id: 'violet', name: 'Violet', group: 'Colours', light: '#efe6f5', dark: '#8877b7', surface: 'solid' },
	{ id: 'slate', name: 'Slate', group: 'Colours', light: '#e3e3e3', dark: '#7d8796', surface: 'solid' },
	{ id: 'savanna', name: 'Savanna', group: 'Colours', light: '#f6e7b8', dark: '#c47a2c', surface: 'solid' },
	{ id: 'blue', name: 'Blue', group: 'Colours', light: '#eaf0f6', dark: '#4f7cac', surface: 'solid' },
	{ id: 'coral', name: 'Coral', group: 'Colours', light: '#fce8e0', dark: '#e07a5f', surface: 'solid' },
	{ id: 'rose', name: 'Rose', group: 'Colours', light: '#f8e5ea', dark: '#c9718a', surface: 'solid' },
	{ id: 'sand', name: 'Sand', group: 'Colours', light: '#f5efe0', dark: '#bfae8b', surface: 'solid' },
	{ id: 'newspaper', name: 'Newspaper', group: 'Colours', light: '#ffffff', dark: '#a9a9a9', surface: 'solid' },
	{ id: 'midnight', name: 'Midnight', group: 'Colours', light: '#6e86a8', dark: '#1e2f4d', surface: 'solid' },
	{ id: 'contrast', name: 'Black & white', group: 'Bold', light: '#ffffff', dark: '#111111', surface: 'solid' },
	{ id: 'gold', name: 'Gold & black', group: 'Bold', light: '#f2c14e', dark: '#1b1b1b', surface: 'solid' },
	{ id: 'tournament', name: 'Tournament', group: 'Bold', light: '#ebecd0', dark: '#739552', surface: 'solid' },
	{ id: 'crimson', name: 'Crimson', group: 'Bold', light: '#f3e1da', dark: '#9b2d30', surface: 'solid' },
	{ id: 'maple', name: 'Maple wood', group: 'Wood', light: '#ebcfa0', dark: '#b07a45', surface: 'wood' },
	{ id: 'walnut', name: 'Walnut wood', group: 'Wood', light: '#d2a877', dark: '#5b3a29', surface: 'wood' },
	{ id: 'ebony', name: 'Ebony wood', group: 'Wood', light: '#c9a57a', dark: '#2e2118', surface: 'wood' },
	{ id: 'marble', name: 'Marble', group: 'Marble', light: '#ededed', dark: '#8b8f96', surface: 'marble' },
	{ id: 'onyx', name: 'Onyx marble', group: 'Marble', light: '#d8d5cf', dark: '#2b2b30', surface: 'marble' },
	{ id: 'jade', name: 'Jade marble', group: 'Marble', light: '#dce8da', dark: '#5e8c6a', surface: 'marble' }
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
export type Surface = (typeof BOARDS)[number]['surface'];
export type PiecesId = (typeof PIECES)[number]['id'];

interface Saved {
	theme: ThemeId;
	board: BoardId;
	pieces: PiecesId;
	hints: boolean;
	coords: boolean;
	lastMove: boolean;
	animate: boolean;
	frame: boolean;
}

const KEY = 'chess_yetu:prefs';
const DEFAULTS: Saved = { theme: 'light', board: 'classic', pieces: 'classic', hints: true, coords: true, lastMove: true, animate: true, frame: false };

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
			animate: raw.animate ?? DEFAULTS.animate,
			frame: raw.frame ?? DEFAULTS.frame
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
	/** Draw the board inside a frame, with the letters and numbers around the outside. */
	frame = $state(DEFAULTS.frame);

	/** How the current board's squares are surfaced: flat colour, wood grain or marble. */
	get surface(): Surface {
		return BOARDS.find((b) => b.id === this.board)?.surface ?? 'solid';
	}

	constructor() {
		if (typeof window === 'undefined') return;
		Object.assign(this, read());
		this.apply();
	}

	set<K extends keyof Saved>(key: K, value: Saved[K]) {
		(this as Saved)[key] = value;
		this.apply();
		try {
			const { theme, board, pieces, hints, coords, lastMove, animate, frame } = this;
			localStorage.setItem(KEY, JSON.stringify({ theme, board, pieces, hints, coords, lastMove, animate, frame }));
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
