<script lang="ts">
	import { Chess } from 'chess.js';
	import Board from '../../lib/Board.svelte';
	import BoardSwatch from '../../lib/BoardSwatch.svelte';
	import { BOARDS, PIECES, THEMES, prefs } from '../../lib/prefs.svelte';

	const GROUPS = [...new Set(BOARDS.map((b) => b.group))];

	// A sample position to try the choices on. Tap a piece to see the move dots.
	const fen = 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 4 4';
	const lastMove = { from: 'g1', to: 'f3' };
	const legalTargets = (from: string) => [
		...new Set(new Chess(fen).moves({ square: from as any, verbose: true }).map((m) => m.to))
	];
</script>

<svelte:head><title>Settings · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/">← Back</a>
	<h1>Settings</h1>
	<p class="note">Your choices are saved on this device. Chess Yetu always starts in light mode until you pick dark.</p>

	<div class="preview">
		<Board {fen} orientation="white" {lastMove} interactive {legalTargets} onmove={() => {}} />
	</div>

	<section class="card">
		<h2>Appearance</h2>
		<div class="seg" role="group" aria-label="Theme">
			{#each THEMES as t}
				<button class:active={prefs.theme === t.id} onclick={() => prefs.set('theme', t.id)}>{t.name}</button>
			{/each}
		</div>
	</section>

	<section class="card">
		<h2>Board style</h2>
		{#each GROUPS as g}
			<h3>{g}</h3>
			<div class="swatches" role="group" aria-label="Board style: {g}">
				{#each BOARDS.filter((b) => b.group === g) as b}
					<button class="swatch board-swatch" class:active={prefs.board === b.id} onclick={() => prefs.set('board', b.id)} aria-label={b.name} aria-pressed={prefs.board === b.id}>
						<BoardSwatch light={b.light} dark={b.dark} surface={b.surface} />
						<span>{b.name}</span>
					</button>
				{/each}
			</div>
		{/each}
	</section>

	<section class="card">
		<h2>Pieces</h2>
		<div class="swatches" role="group" aria-label="Piece colours">
			{#each PIECES as p}
				<button class="swatch" class:active={prefs.pieces === p.id} onclick={() => prefs.set('pieces', p.id)} aria-label={p.name} aria-pressed={prefs.pieces === p.id}>
					<span class="pc">
						<span style="color:{p.white}; -webkit-text-stroke:1px {p.id === 'contrast' ? '#000' : '#333'}">♚</span>
						<span style="color:{p.black}; -webkit-text-stroke:1px {p.id === 'contrast' ? '#fff' : '#000'}">♚</span>
					</span>
					<span>{p.name}</span>
				</button>
			{/each}
		</div>
	</section>

	<section class="card">
		<h2>On the board</h2>
		<label class="row"><input type="checkbox" checked={prefs.hints} onchange={(e) => prefs.set('hints', e.currentTarget.checked)} /> Show dots where a piece can move</label>
		<label class="row"><input type="checkbox" checked={prefs.lastMove} onchange={(e) => prefs.set('lastMove', e.currentTarget.checked)} /> Highlight the last move</label>
		<label class="row"><input type="checkbox" checked={prefs.animate} onchange={(e) => prefs.set('animate', e.currentTarget.checked)} /> Slide pieces when they move</label>
		<label class="row"><input type="checkbox" checked={prefs.frame} onchange={(e) => prefs.set('frame', e.currentTarget.checked)} /> Framed board, with the letters and numbers outside</label>
		<label class="row"><input type="checkbox" checked={prefs.coords} onchange={(e) => prefs.set('coords', e.currentTarget.checked)} /> Show letters and numbers on the edge</label>
	</section>

	<button class="reset" onclick={() => prefs.reset()}>Reset to defaults</button>
</main>

<style>
	main {
		max-width: 460px;
		margin: 0 auto;
		padding: 1rem 16px 3rem;
	}
	h1 {
		margin: 0 0 0.25rem;
	}
	.note {
		color: var(--muted);
		font-size: 0.85rem;
		margin: 0 0 1rem;
	}
	.preview {
		margin-bottom: 1rem;
	}
	.card {
		background: var(--card);
		border: 1px solid var(--line);
		border-radius: 14px;
		padding: 1.1rem;
		margin-bottom: 1rem;
		box-shadow: var(--shadow);
	}
	h2 {
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--muted);
		margin: 0 0 0.75rem;
	}
	button {
		min-height: 44px;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
	}
	button:focus-visible,
	input:focus-visible {
		outline: 2px solid var(--accent);
		outline-offset: 2px;
	}
	button.active {
		border-color: var(--accent);
		background: var(--accent-bg);
		color: var(--accent-strong);
		font-weight: 700;
	}
	.seg {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
	}
	.swatches {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 8px;
	}
	.swatch {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		padding: 8px 4px;
		font-size: 0.8rem;
	}
	.board-swatch {
		padding: 6px;
	}
	h3 {
		margin: 14px 0 6px;
		font-size: 0.8rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--muted);
	}
	h3:first-of-type {
		margin-top: 4px;
	}
	.pc {
		display: flex;
		gap: 4px;
		font-size: 1.7rem;
		line-height: 28px;
		height: 28px;
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', serif;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 10px;
		min-height: 44px;
	}
	.row input {
		width: 20px;
		height: 20px;
		accent-color: var(--accent);
	}
	.reset {
		width: 100%;
	}
</style>
