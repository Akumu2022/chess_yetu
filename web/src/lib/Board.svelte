<script lang="ts">
	import { Chess } from 'chess.js';
	import { prefs } from './prefs.svelte';

	let {
		fen,
		orientation = 'white',
		lastMove = null,
		interactive = false,
		legalTargets,
		onmove
	}: {
		fen: string;
		orientation?: 'white' | 'black';
		lastMove?: { from: string; to: string } | null;
		interactive?: boolean;
		legalTargets: (from: string) => string[];
		onmove: (from: string, to: string, promotion?: string) => void;
	} = $props();

	// The U+FE0E suffix forces text (not emoji) style; U+265F is an emoji on some systems.
	const GLYPH: Record<string, string> = { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟︎' };
	const FILES = 'abcdefgh';

	let selected = $state<string | null>(null);
	let promo = $state<{ from: string; to: string } | null>(null);
	let targets = $derived(selected ? legalTargets(selected) : []);
	let board = $derived(new Chess(fen).board());
	let checkSquare = $derived.by(() => {
		const c = new Chess(fen);
		if (!c.inCheck()) return null;
		for (const row of c.board())
			for (const p of row) if (p && p.type === 'k' && p.color === c.turn()) return p.square;
		return null;
	});
	let turn = $derived(fen.split(' ')[1]);

	// Screen position of a square (0..7), accounting for orientation.
	function pos(square: string) {
		const f = FILES.indexOf(square[0]);
		const r = Number(square[1]) - 1;
		return orientation === 'white' ? { x: f, y: 7 - r } : { x: 7 - f, y: r };
	}

	const squares = $derived(
		Array.from({ length: 64 }, (_, i) => {
			const x = i % 8;
			const y = Math.floor(i / 8);
			const f = orientation === 'white' ? x : 7 - x;
			const r = orientation === 'white' ? 8 - y : y + 1;
			return { x, y, name: FILES[f] + r, dark: (f + r) % 2 === 1 };
		})
	);

	// Each piece keeps an identity from one position to the next, so a move slides the piece
	// from where it was to where it is instead of the piece appearing out of nowhere.
	type Tracked = { id: number; square: string; type: string; color: string };
	let memory: Tracked[] = [];
	let nextId = 0;
	const pieces = $derived.by(() => {
		const fresh = board.flat().flatMap((p) => (p ? [{ square: p.square, type: p.type, color: p.color }] : []));
		const same = (a: { type: string; color: string }, b: { type: string; color: string }) =>
			a.type === b.type && a.color === b.color;
		const used = new Set<number>();
		const out: Tracked[] = [];
		const moved: typeof fresh = [];
		for (const n of fresh) {
			const o = memory.find((m) => !used.has(m.id) && m.square === n.square && same(m, n));
			if (o) (used.add(o.id), out.push({ ...n, id: o.id }));
			else moved.push(n);
		}
		for (const n of moved) {
			let o = memory.find(
				(m) => !used.has(m.id) && same(m, n) && lastMove?.from === m.square && lastMove?.to === n.square
			);
			if (!o) {
				// castling moves a second piece: the one unmatched rook of that colour is it
				const olds = memory.filter((m) => !used.has(m.id) && same(m, n));
				if (olds.length === 1 && moved.filter((q) => same(q, n)).length === 1) o = olds[0];
			}
			if (o) used.add(o.id);
			out.push({ ...n, id: o ? o.id : nextId++ });
		}
		out.sort((a, b) => a.id - b.id); // a steady order keeps the browser from restarting the slide
		memory = out;
		return out.map((p) => ({ ...p, ...pos(p.square) }));
	});

	function click(name: string) {
		if (!interactive) return;
		if (selected && targets.includes(name)) {
			const from = selected;
			selected = null;
			const piece = pieces.find((p) => p.square === from);
			if (piece?.type === 'p' && (name[1] === '8' || name[1] === '1')) {
				promo = { from, to: name }; // let the player choose the new piece
			} else {
				onmove(from, name);
			}
			return;
		}
		const piece = pieces.find((p) => p.square === name);
		const mine = piece && piece.color === turn;
		selected = mine && name !== selected ? name : null;
	}

	$effect(() => {
		fen;
		selected = null;
		promo = null;
	});

	function choose(piece: string) {
		if (!promo) return;
		const { from, to } = promo;
		promo = null;
		onmove(from, to, piece);
	}

	const PROMO_PIECES = ['q', 'r', 'b', 'n'];
</script>

<svg viewBox="0 0 8 8" class="board" class:animate={prefs.animate} role="grid" aria-label="Chess board">
	{#each squares as s (s.name)}
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<rect
			x={s.x}
			y={s.y}
			width="1"
			height="1"
			class={s.dark ? 'dark' : 'light'}
			data-square={s.name}
			role="gridcell"
			tabindex="-1"
			onclick={() => click(s.name)}
		/>
		{#if prefs.lastMove && lastMove && (lastMove.from === s.name || lastMove.to === s.name)}
			<rect x={s.x} y={s.y} width="1" height="1" class="last" pointer-events="none" />
		{/if}
		{#if checkSquare === s.name}
			<rect x={s.x} y={s.y} width="1" height="1" class="check" pointer-events="none" />
		{/if}
		{#if selected === s.name}
			<rect x={s.x} y={s.y} width="1" height="1" class="sel" pointer-events="none" />
		{/if}
	{/each}

	{#each pieces as p (p.id)}
		<g class="mover" style="transform: translate({p.x}px, {p.y}px)" pointer-events="none">
			<text
				x="0.5"
				y="0.5"
				class="piece {p.color}"
				data-piece={p.color + p.type}
				data-at={p.square}
				text-anchor="middle"
				dominant-baseline="central">{GLYPH[p.type]}</text
			>
		</g>
	{/each}

	{#each prefs.hints ? targets : [] as t (t)}
		{@const q = pos(t)}
		<circle cx={q.x + 0.5} cy={q.y + 0.5} r="0.16" class="hint" pointer-events="none" />
	{/each}

	{#each squares as s (s.name)}
		{#if prefs.coords && s.x === 0}
			<text x="0.05" y={s.y + 0.22} class="coord {s.dark ? 'on-dark' : 'on-light'}" pointer-events="none"
				>{s.name[1]}</text
			>
		{/if}
		{#if prefs.coords && s.y === 7}
			<text x={s.x + 0.95} y="7.92" text-anchor="end" class="coord {s.dark ? 'on-dark' : 'on-light'}" pointer-events="none"
				>{s.name[0]}</text
			>
		{/if}
	{/each}

	{#if promo}
		<rect x="0" y="0" width="8" height="8" class="shade" role="presentation" onclick={() => (promo = null)} />
		<rect x="1.5" y="3.2" width="5" height="1.6" rx="0.15" class="promo-bg" />
		{#each PROMO_PIECES as pc, i}
			<!-- svelte-ignore a11y_click_events_have_key_events -->
			<g role="button" tabindex="-1" class="choice" onclick={() => choose(pc)}>
				<rect x={1.7 + i * 1.2} y="3.4" width="1.1" height="1.2" rx="0.1" class="choice-bg" />
				<text x={2.25 + i * 1.2} y="4" text-anchor="middle" dominant-baseline="central" class="piece {turn}">{GLYPH[pc]}</text>
			</g>
		{/each}
	{/if}
</svg>

<style>
	/* The board is an SVG scaled ~80x, so the browser's 1px focus ring on a tapped square
	   becomes a giant white/black arc. Squares are tap targets, not keyboard stops. */
	rect:focus,
	rect:focus-visible,
	g:focus,
	g:focus-visible {
		outline: none;
	}
	.shade {
		fill: rgba(0, 0, 0, 0.45);
	}
	.promo-bg {
		fill: var(--card);
	}
	.choice {
		cursor: pointer;
	}
	.choice-bg {
		fill: var(--card-2);
	}
	.choice:hover .choice-bg {
		fill: var(--accent);
	}
	.board {
		width: 100%;
		height: auto;
		display: block;
		border-radius: 6px;
		touch-action: manipulation;
		user-select: none;
	}
	.light {
		fill: var(--sq-light);
	}
	.dark {
		fill: var(--sq-dark);
	}
	.last {
		fill: #f5a623;
		opacity: 0.55;
	}
	.check {
		fill: #e5383b;
		opacity: 0.6;
	}
	.sel {
		fill: #f5a623;
		opacity: 0.8;
	}
	.hint {
		fill: rgba(20, 20, 20, 0.35);
	}
	.animate .mover {
		transition: transform 0.28s ease-out;
	}
	@media (prefers-reduced-motion: reduce) {
		.animate .mover {
			transition: none;
		}
	}
	.piece {
		font-size: 0.86px;
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', serif;
		stroke-width: 0.03px;
	}
	.piece.w {
		fill: var(--pc-w);
		stroke: var(--pc-w-line);
	}
	.piece.b {
		fill: var(--pc-b);
		stroke: var(--pc-b-line);
	}
	.coord {
		font-size: 0.22px;
		font-family: sans-serif;
		font-weight: 700;
	}
	.on-dark {
		fill: var(--sq-light);
	}
	.on-light {
		fill: var(--sq-dark);
	}
</style>
