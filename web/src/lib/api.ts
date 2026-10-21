const HOST = typeof location !== 'undefined' ? location.hostname : 'localhost';
function devPortOverride(): string | null {
	if (!import.meta.env.DEV) return null; // never in production builds
	try {
		return localStorage.getItem('chess_yetu:api_port');
	} catch {
		return null;
	}
}
const PORT = devPortOverride() ?? import.meta.env.VITE_API_PORT ?? '8765';
export const API = `http://${HOST}:${PORT}`;
export const WS = `ws://${HOST}:${PORT}`;

export interface Seat {
	game_id: string;
	color: 'white' | 'black';
	token: string;
}

export interface User {
	id: number;
	username: string;
	rating: number;
	rd: number;
	games: number;
}

export interface GameSummary {
	id: string;
	result: string;
	reason: string;
	rated: boolean;
	color: 'white' | 'black';
	delta: number;
	moves: number;
	played_at: string;
}

// ---- auth token (a convenience copy; the server is the authority) ----
//
// Each tab pins its own account in sessionStorage, so two tabs can be signed in as two
// different people (handy for testing). localStorage only remembers the latest sign-in
// so that a NEW tab starts signed in.

const TOKEN_KEY = 'chess_yetu:auth';

export function getToken(): string | null {
	try {
		const pinned = sessionStorage.getItem(TOKEN_KEY);
		if (pinned) return pinned;
		const remembered = localStorage.getItem(TOKEN_KEY);
		if (remembered) sessionStorage.setItem(TOKEN_KEY, remembered); // pin it to this tab
		return remembered;
	} catch {
		return null;
	}
}

export function setToken(token: string | null) {
	try {
		if (token) {
			sessionStorage.setItem(TOKEN_KEY, token);
			localStorage.setItem(TOKEN_KEY, token);
		} else {
			sessionStorage.removeItem(TOKEN_KEY);
			// Signing out also stops new tabs from starting signed in.
			localStorage.removeItem(TOKEN_KEY);
		}
	} catch {}
}

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
	const token = getToken();
	const headers: Record<string, string> = { ...(init.headers as Record<string, string>) };
	if (init.body) headers['content-type'] = 'application/json';
	if (token) headers.authorization = `Bearer ${token}`;
	const r = await fetch(`${API}${path}`, { ...init, headers });
	if (!r.ok) {
		if (r.status === 401 && token && !path.startsWith('/auth/')) {
			setToken(null); // the saved sign-in no longer works
			throw new ApiError(401, 'Your session expired. Please sign in again.');
		}
		let detail = 'Request failed';
		try {
			const body = await r.json();
			detail = typeof body.detail === 'string' ? body.detail : (body.detail?.[0]?.msg ?? detail);
		} catch {}
		throw new ApiError(r.status, detail);
	}
	return r.json();
}

export class ApiError extends Error {
	constructor(
		public status: number,
		message: string
	) {
		super(message);
	}
}

export const register = (username: string, password: string) =>
	call<{ token: string; user: User }>('/auth/register', {
		method: 'POST',
		body: JSON.stringify({ username, password })
	});

export const login = (username: string, password: string) =>
	call<{ token: string; user: User }>('/auth/login', {
		method: 'POST',
		body: JSON.stringify({ username, password })
	});

export const fetchMe = () => call<User>('/me');
export const fetchMyGames = () => call<GameSummary[]>('/me/games');

export const createGame = (minutes: number, increment: number) =>
	call<Seat>('/games', { method: 'POST', body: JSON.stringify({ minutes, increment }) });

/** Accepts a bare code or a whole pasted link (".../game/Ab3x_9Qz?x=1") and returns the code. */
export function gameCodeFrom(input: string): string {
	const text = input.trim();
	const m = text.match(/\/game\/([A-Za-z0-9_-]+)/);
	return m ? m[1] : text;
}

export async function joinGame(input: string): Promise<Seat> {
	const id = gameCodeFrom(input);
	try {
		return await call<Seat>(`/games/${encodeURIComponent(id)}/join`, { method: 'POST' });
	} catch (e) {
		if (e instanceof ApiError && e.status === 404) throw new Error('No game with that code');
		if (e instanceof ApiError && e.status === 409) throw new Error(e.message);
		throw e;
	}
}

export const BOT_LEVELS = [
	{ level: 1, name: 'Beginner' },
	{ level: 2, name: 'Easy' },
	{ level: 3, name: 'Medium' },
	{ level: 4, name: 'Hard' },
	{ level: 5, name: 'Master' }
];
export type BotColor = 'white' | 'black' | 'random';

export async function createBotGame(
	level: number,
	color: BotColor,
	minutes: number,
	increment: number
): Promise<Seat> {
	try {
		return await call<Seat>('/games/ai', {
			method: 'POST',
			body: JSON.stringify({ level, color, minutes, increment })
		});
	} catch (e) {
		if (e instanceof ApiError && e.status === 503) throw new Error('The computer opponent is not available right now');
		throw e;
	}
}

export type QueueState = { status: 'waiting' | 'idle'; already_searching?: boolean } | { status: 'matched'; seat: Seat };

export const enterQueue = (minutes: number, increment: number) =>
	call<QueueState>('/queue', { method: 'POST', body: JSON.stringify({ minutes, increment }) });
export const pollQueue = () => call<QueueState>('/queue');
/** Best-effort removal from the queue while the page is going away (a normal fetch would be cancelled). */
export function leaveQueueOnExit(path = '/queue') {
	const token = getToken();
	if (!token) return;
	try {
		fetch(`${API}${path}`, { method: 'DELETE', keepalive: true, headers: { authorization: `Bearer ${token}` } });
	} catch {}
}

export const leaveQueue = () => call<QueueState>('/queue', { method: 'DELETE' });

// ---- seats: which colour/token I hold in each game ----

const seatKey = (id: string) => `chess_yetu:seat:${id}`;

// Per tab (sessionStorage), never shared: two tabs of one browser playing each other must
// each keep their own colour, otherwise both would load the same seat and neither could move.
export function saveSeat(seat: Seat) {
	try {
		sessionStorage.setItem(seatKey(seat.game_id), JSON.stringify(seat));
	} catch {}
}

export function loadSeat(id: string): Seat | null {
	try {
		const raw = sessionStorage.getItem(seatKey(id));
		return raw ? (JSON.parse(raw) as Seat) : null;
	} catch {
		return null;
	}
}

// ---- who is signed in --------------------------------------------------------

export type Who = { kind: 'guest' } | { kind: 'adult'; user: User } | { kind: 'kid'; child: Child };
export const whoami = () => call<Who>('/whoami');

// ---- chess for kids ------------------------------------------------------------

export interface Child {
	id: number;
	nickname: string;
	rating: number;
	rd: number;
	games: number;
	birth_year: number;
	daily_limit_min: number;
	minutes_today: number;
	minutes_left: number;
}

export interface KidGame {
	id: string;
	result: string;
	reason: string;
	color: 'white' | 'black';
	opponent: string;
	rated: boolean;
	moves: number;
	minutes: number;
	delta: number;
	played_at: string;
}

/** The only things a child can say; the server relays ids, never text. */
export const KID_PHRASES: Record<string, string> = {
	hi: 'Hello!',
	gl: 'Good luck!',
	nm: 'Nice move!',
	oops: 'Oops!',
	wp: 'Well played!',
	ty: 'Thank you!',
	gg: 'Good game!',
	rm: 'Rematch?'
};

export const KID_BOTS = [
	{ bot: 1, name: 'Zuri the Gentle', blurb: 'Just learning too' },
	{ bot: 2, name: 'Simba the Brave', blurb: 'A fair fight' },
	{ bot: 3, name: 'Mzee Kobe the Wise', blurb: 'A real challenge' }
];

// parent area
export const kidsPinStatus = () => call<{ set: boolean }>('/kids/pin');
export const setKidsPin = (pin: string, current?: string) =>
	call<{ set: boolean }>('/kids/pin', { method: 'PUT', body: JSON.stringify({ pin, current }) });
export const listChildren = () => call<Child[]>('/kids/children');
export const createChild = (birth_year: number, consent: boolean) =>
	call<Child>('/kids/children', { method: 'POST', body: JSON.stringify({ birth_year, consent }) });
export const setChildLimit = (id: number, daily_limit_min: number) =>
	call<Child>(`/kids/children/${id}`, { method: 'PATCH', body: JSON.stringify({ daily_limit_min }) });
export const deleteChild = (id: number) => call<{ deleted: boolean }>(`/kids/children/${id}`, { method: 'DELETE' });
export const childGames = (id: number) => call<KidGame[]>(`/kids/children/${id}/games`);
export const startKidSession = (id: number) =>
	call<{ token: string; child: Child }>(`/kids/children/${id}/session`, { method: 'POST' });

// child area
export const kidGames = () => call<KidGame[]>('/kids/me/games');
export const exitKidsMode = (pin: string) =>
	call<{ token: string; user: User }>('/kids/exit', { method: 'POST', body: JSON.stringify({ pin }) });
export const createKidBotGame = (bot: number, color: BotColor, minutes = 10, increment = 5) =>
	call<Seat>('/kids/games/ai', { method: 'POST', body: JSON.stringify({ bot, color, minutes, increment }) });
export const enterKidQueue = (minutes = 10, increment = 5) =>
	call<QueueState>('/kids/queue', { method: 'POST', body: JSON.stringify({ minutes, increment }) });
export const pollKidQueue = () => call<QueueState>('/kids/queue');
export const leaveKidQueue = () => call<QueueState>('/kids/queue', { method: 'DELETE' });

// ---- puzzles (adults and kids share the same endpoints) ----

export interface Puzzle {
	id: number;
	fen: string;
	depth: number;
	theme: string;
	to_move: 'white' | 'black';
}
export interface PuzzleState {
	solved_today: number;
	limit: number;
	streak: { current: number; best: number; freezes: number };
}
export type NextPuzzle = ({ puzzle: Puzzle } | { limit_reached: true }) & PuzzleState;
export type PuzzleMove =
	| { status: 'wrong' }
	| { status: 'continue'; reply: string }
	| ({ status: 'solved' } & PuzzleState);

export const nextPuzzle = () => call<NextPuzzle>('/puzzles/next');
export const puzzleMove = (id: number, played: string[]) =>
	call<PuzzleMove>(`/puzzles/${id}/move`, { method: 'POST', body: JSON.stringify({ played }) });

// ---- game review ----

export type MoveClass = 'best' | 'good' | 'inaccuracy' | 'mistake' | 'blunder';
export interface Analysis {
	evals: number[];
	moves: { uci: string; san: string; cls: MoveClass; loss: number; best: string | null; best_san: string | null }[];
	accuracy: { white: number | null; black: number | null };
	counts: Record<'white' | 'black', Record<MoveClass, number>>;
}
export interface Review {
	id: string;
	moves: string[];
	result: string;
	reason: string;
	rated: boolean;
	players: { white: string; black: string };
	analysis: Analysis | null;
	engine: boolean;
}
export const getReview = (id: string) => call<Review>(`/review/${encodeURIComponent(id)}`);
export const analyzeGame = (id: string) => call<Analysis>(`/review/${encodeURIComponent(id)}/analyze`, { method: 'POST' });

// ---- leaderboard, profiles, tournaments ----

export interface Ranked {
	rank: number;
	username: string;
	rating: number;
	games: number;
}
export const fetchLeaderboard = () => call<{ min_games: number; players: Ranked[] }>('/leaderboard');

export interface Profile {
	username: string;
	rating: number;
	games: number;
	rank: number | null;
	record: { won: number; drawn: number; lost: number };
	recent: { id: string; opponent: string; color: 'white' | 'black'; outcome: 'win' | 'draw' | 'loss'; moves: number; played_at: string }[];
}
export const fetchProfile = (username: string) => call<Profile>(`/players/${encodeURIComponent(username)}`);

export interface TournamentInfo {
	id: number;
	name: string;
	minutes: number;
	increment: number;
	starts_at: string;
	ends_at: string;
	duration_min: number;
	status: 'upcoming' | 'running' | 'finishing' | 'finished';
	players: number;
	joined: boolean;
	creator: string | null;
}
export interface Standing {
	rank: number;
	username: string;
	rating: number;
	points: number;
	games: number;
	wins: number;
	draws: number;
	losses: number;
	active: boolean;
}
export type TournamentDetail = TournamentInfo & { standings: Standing[]; winner: string | null };

export const listTournaments = () => call<TournamentInfo[]>('/tournaments');
export const getTournament = (id: number | string) => call<TournamentDetail>(`/tournaments/${id}`);
export const createTournament = (b: {
	name: string;
	minutes: number;
	increment: number;
	starts_in_min: number;
	duration_min: number;
}) => call<TournamentInfo>('/tournaments', { method: 'POST', body: JSON.stringify(b) });
export const joinTournament = (id: number) => call<{ joined: boolean }>(`/tournaments/${id}/join`, { method: 'POST' });
export const leaveTournament = (id: number) => call<{ joined: boolean }>(`/tournaments/${id}/join`, { method: 'DELETE' });
export const tournamentPoll = (id: number) =>
	call<{ status: 'not_joined' | 'waiting' } | { status: 'matched'; seat: Seat }>(`/tournaments/${id}/me`);
