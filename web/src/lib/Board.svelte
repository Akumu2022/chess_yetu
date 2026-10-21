<script lang="ts">
	import { Chess } from 'chess.js';

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

	const pieces = $derived(
		board.flat().flatMap((p) => (p ? [{ ...p, ...pos(p.square) }] : []))
	);

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

<svg viewBox="0 0 8 8" class="board" role="grid" aria-label="Chess board">
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
		{#if lastMove && (lastMove.from === s.name || lastMove.to === s.name)}
			<rect x={s.x} y={s.y} width="1" height="1" class="last" pointer-events="none" />
		{/if}
		{#if checkSquare === s.name}
			<rect x={s.x} y={s.y} width="1" height="1" class="check" pointer-events="none" />
		{/if}
		{#if selected === s.name}
			<rect x={s.x} y={s.y} width="1" height="1" class="sel" pointer-events="none" />
		{/if}
	{/each}

	{#each pieces as p (p.square + p.type + p.color)}
		<text
			x={p.x + 0.5}
			y={p.y + 0.5}
			class="piece {p.color}"
			data-piece={p.color + p.type}
			data-at={p.square}
			text-anchor="middle"
			dominant-baseline="central"
			pointer-events="none">{GLYPH[p.type]}</text
		>
	{/each}

	{#each targets as t (t)}
		{@const q = pos(t)}
		<circle cx={q.x + 0.5} cy={q.y + 0.5} r="0.16" class="hint" pointer-events="none" />
	{/each}

	{#each squares as s (s.name)}
		{#if s.x === 0}
			<text x="0.05" y={s.y + 0.22} class="coord {s.dark ? 'on-dark' : 'on-light'}" pointer-events="none"
				>{s.name[1]}</text
			>
		{/if}
		{#if s.y === 7}
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
		fill: #2a2520;
	}
	.choice {
		cursor: pointer;
	}
	.choice-bg {
		fill: #3a322b;
	}
	.choice:hover .choice-bg {
		fill: #f5a623;
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
		fill: #f0d9b5;
	}
	.dark {
		fill: #8a5a3c;
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
	.piece {
		font-size: 0.86px;
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', serif;
		stroke-width: 0.03px;
	}
	.piece.w {
		fill: #fdfdfd;
		stroke: #222;
	}
	.piece.b {
		fill: #1c1c1c;
		stroke: #000;
	}
	.coord {
		font-size: 0.22px;
		font-family: sans-serif;
		font-weight: 700;
	}
	.on-dark {
		fill: #f0d9b5;
	}
	.on-light {
		fill: #8a5a3c;
	}
</style>
