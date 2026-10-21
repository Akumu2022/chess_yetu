import { Chess } from 'chess.js';
import { WS, type Seat } from './api';
import { materialDiff, replay } from './captured';

const DEAD_AFTER_MS = 12_000; // heartbeat is every 5s
const FATAL: Record<string, string> = {
	no_such_game: 'This game is no longer available. It may have ended, or the server was restarted.',
	bad_token: 'This game link belongs to a different player.',
	bad_version: 'This page is out of date. Please refresh.'
};
type Color = 'white' | 'black';
type Clocks = { white: number; black: number };

/**
 * Live game state. The server is the only authority: moves are shown
 * optimistically but only `move_made` / `resync` make them official.
 */
export class GameClient {
	chess = new Chess();
	fen = $state(this.chess.fen());
	moves = $state<string[]>([]);
	status = $state<'connecting' | 'waiting' | 'active' | 'over'>('connecting');
	turn = $state<Color>('white');
	you = $state<Color>('white');
	result = $state<string | null>(null);
	reason = $state<string | null>(null);
	connected = $state(false);
	opponentConnected = $state(true);
	drawOfferedBy = $state<Color | null>(null);
	error = $state<string | null>(null);
	/** The game cannot continue on this link (it no longer exists, or the seat is not ours). */
	fatal = $state<string | null>(null);
	notice = $state<string | null>(null);
	vsBot = $state(false);
	/** Kids' games: preset messages only. The latest message each side said, shown for a few seconds. */
	kids = $state(false);
	/** Set for arena games: the tournament to return to afterwards. */
	tournament = $state<number | null>(null);
	said = $state<Record<string, string | null>>({ white: null, black: null });
	private saidTimers: Record<string, ReturnType<typeof setTimeout> | undefined> = {};
	lastMove = $state<{ from: string; to: string } | null>(null);
	players = $state<Record<string, { name: string; rating: number | null }>>({});
	rated = $state(false);
	ratingChange = $state<Clocks | null>(null);
	/** Notation and captured pieces, rebuilt from the move list. */
	history = $derived.by(() => replay(this.moves));
	/** Material lead in pawns, from white's point of view. */
	materialLead = $derived(materialDiff(this.fen));
	/** Smoothly ticking clock values, in ms. */
	clocks = $state<Clocks>({ white: 0, black: 0 });

	private ws: WebSocket | null = null;
	private seq = 0;
	private serverClocks: Clocks = { white: 0, black: 0 };
	private clockBase = 0; // performance.now() when serverClocks were received
	private retry = 0;
	private closed = false;
	private rtt = 0;
	private timers: ReturnType<typeof setInterval>[] = [];
	private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
	private pending: { seq: number; move: string } | null = null;
	private lastHeard = 0; // performance.now() of the last message from the server

	constructor(private seat: Seat) {
		this.you = seat.color;
	}

	start() {
		this.connect();
		this.timers.push(setInterval(() => this.tickClock(), 100));
		this.timers.push(setInterval(() => this.ping(), 5000));
		window.addEventListener('online', this.onOnline);
	}

	stop() {
		this.closed = true;
		this.timers.forEach(clearInterval);
		if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
		window.removeEventListener('online', this.onOnline);
		this.ws?.close();
	}

	private onOnline = () => {
		if (!this.connected) this.connect();
	};

	private connect() {
		if (this.closed || this.ws?.readyState === WebSocket.OPEN || this.ws?.readyState === WebSocket.CONNECTING)
			return;
		const ws = new WebSocket(`${WS}/ws/games/${this.seat.game_id}`);
		this.ws = ws;
		ws.onopen = () => {
			this.lastHeard = performance.now();
			this.retry = 0;
			this.connected = true;
			this.error = null;
			ws.send(JSON.stringify({ type: 'hello', v: 1, token: this.seat.token, seq: this.seq }));
		};
		ws.onmessage = (e) => {
			this.lastHeard = performance.now();
			this.onMessage(JSON.parse(e.data));
		};
		ws.onclose = () => {
			if (this.ws !== ws) return;
			this.connected = false;
			if (this.closed) return;
			// Exponential backoff: 1s, 2s, 4s ... capped at 8s.
			const delay = Math.min(8000, 1000 * 2 ** this.retry++);
			this.reconnectTimer = setTimeout(() => this.connect(), delay);
		};
	}

	/** Abandon a dead socket without waiting for its close handshake, then reconnect. */
	private dropSocket() {
		const old = this.ws;
		this.ws = null;
		this.connected = false;
		if (old) {
			old.onclose = old.onmessage = null;
			try {
				old.close();
			} catch {}
		}
		this.retry = 0;
		this.connect();
	}

	private send(msg: object) {
		if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg));
	}

	private ping() {
		// No reply for 3 heartbeats: the connection is dead even if the browser hasn't noticed.
		if (this.ws && this.connected && performance.now() - this.lastHeard > DEAD_AFTER_MS) {
			this.dropSocket();
			return;
		}
		const t = performance.now();
		this.send({ type: 'ping', t, rtt: Math.round(this.rtt) });
	}

	private applySnapshot(m: any) {
		this.chess = new Chess(m.fen);
		this.fen = m.fen;
		this.moves = m.moves;
		this.seq = m.seq;
		this.turn = m.turn;
		this.status = m.status;
		this.result = m.result;
		this.reason = m.reason;
		this.drawOfferedBy = m.draw_offer;
		this.players = m.players ?? {};
		this.rated = !!m.rated;
		this.vsBot = !!m.vs_bot;
		this.kids = !!m.kids;
		this.tournament = m.tournament ?? null;
		this.pending = null;
		const last = m.moves.at(-1);
		this.lastMove = last ? { from: last.slice(0, 2), to: last.slice(2, 4) } : null;
		this.setClocks(m.clocks);
	}

	private setClocks(c: Clocks) {
		this.serverClocks = { ...c };
		this.clockBase = performance.now();
		this.clocks = { ...c };
	}

	private tickClock() {
		if (this.status !== 'active') return;
		const elapsed = performance.now() - this.clockBase;
		const c = { ...this.serverClocks };
		c[this.turn] = Math.max(0, c[this.turn] - elapsed);
		this.clocks = c;
	}

	private onMessage(m: any) {
		switch (m.type) {
			case 'resync':
			case 'game_started':
				this.applySnapshot(m);
				break;
			case 'move_made': {
				if (m.seq !== this.seq + 1) {
					// Missed something: reconnecting triggers a full resync.
					this.ws?.close();
					break;
				}
				if (this.pending && this.pending.seq === m.seq && this.pending.move === m.move) {
					// Our optimistic move was confirmed.
					this.pending = null;
				} else {
					this.chess.move({ from: m.move.slice(0, 2), to: m.move.slice(2, 4), promotion: m.move[4] });
				}
				this.fen = this.chess.fen();
				this.moves = [...this.moves, m.move];
				this.seq = m.seq;
				this.turn = this.chess.turn() === 'w' ? 'white' : 'black';
				this.lastMove = { from: m.move.slice(0, 2), to: m.move.slice(2, 4) };
				this.drawOfferedBy = null;
				this.setClocks(m.clocks);
				break;
			}
			case 'pong':
				this.rtt = performance.now() - m.t;
				break;
			case 'opponent_status':
				if (m.color !== this.you) this.opponentConnected = m.connected;
				break;
			case 'said':
				this.said[m.by] = m.id;
				clearTimeout(this.saidTimers[m.by]);
				this.saidTimers[m.by] = setTimeout(() => (this.said[m.by] = null), 4000);
				break;
			case 'draw_declined':
				this.notice = 'The computer declined your draw offer';
				setTimeout(() => (this.notice = null), 4000);
				break;
			case 'draw_offered':
				this.drawOfferedBy = m.by;
				break;
			case 'game_over':
				this.status = 'over';
				this.result = m.result;
				this.reason = m.reason;
				this.ratingChange = m.rating_change;
				break;
			case 'error':
				if (FATAL[m.code]) {
					// The game is gone (e.g. the server restarted) or this seat is not ours: stop retrying.
					this.fatal = FATAL[m.code];
					this.closed = true;
					this.timers.forEach(clearInterval);
					this.ws?.close();
					break;
				}
				if (m.code === 'too_fast') break; // chatting too quickly is not worth an error message
				this.error = m.message || m.code;
				if (this.pending) {
					// Server rejected our optimistic move: roll back.
					this.pending = null;
					this.ws?.close();
				}
				break;
		}
	}

	/** Legal destination squares for a piece, from the local rules engine. */
	legalTargets(from: string): string[] {
		// A promoting pawn has four moves (Q/R/B/N) to the same square; list each square once.
		return [...new Set(this.chess.moves({ square: from as any, verbose: true }).map((mv) => mv.to))];
	}

	canMove(): boolean {
		return this.connected && this.status === 'active' && this.turn === this.you && !this.pending;
	}

	/** Play a move now (optimistic) and tell the server. */
	move(from: string, to: string, promotion = 'q'): boolean {
		if (!this.canMove()) return false;
		let made;
		try {
			made = this.chess.move({ from, to, promotion });
		} catch {
			return false;
		}
		const uci = made.from + made.to + (made.promotion ?? '');
		this.pending = { seq: this.seq + 1, move: uci };
		this.fen = this.chess.fen();
		this.turn = this.you === 'white' ? 'black' : 'white';
		this.lastMove = { from: made.from, to: made.to };
		this.send({ type: 'move', seq: this.seq + 1, move: uci });
		return true;
	}

	say(id: string) {
		this.send({ type: 'say', id });
	}
	resign() {
		this.send({ type: 'resign' });
	}
	offerDraw() {
		this.send({ type: 'draw' });
	}
}
