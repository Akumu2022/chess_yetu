<script lang="ts">
	import { Chess } from 'chess.js';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { analyzeGame, getReview, type Analysis, type MoveClass, type Review } from '../../../lib/api';
	import Board from '#lib/Board.svelte';

	const id = page.params.id!;
	let review = $state<Review | null>(null);
	let analysis = $state<Analysis | null>(null);
	let failure = $state('');
	let analysing = $state(false);
	let ply = $state(0); // 0 = start position, n = after move n
	let flipped = $state(false);

	const MARK: Record<MoveClass, string> = { best: '★', good: '', inaccuracy: '?!', mistake: '?', blunder: '??' };
	const LABEL: Record<MoveClass, string> = {
		best: 'the best move',
		good: 'a good move',
		inaccuracy: 'an inaccuracy',
		mistake: 'a mistake',
		blunder: 'a blunder'
	};

	onMount(async () => {
		try {
			review = await getReview(id);
			analysis = review.analysis;
			ply = review.moves.length; // start at the end, like a post-mortem
			if (!analysis && review.engine && review.moves.length) {
				analysing = true;
				analysis = await analyzeGame(id);
			}
		} catch (e) {
			failure = e instanceof Error ? e.message : 'Could not load this game';
		} finally {
			analysing = false;
		}
	});

	// The position after `ply` moves, and the move that led to it.
	let position = $derived.by(() => {
		const c = new Chess();
		let last: { from: string; to: string } | null = null;
		for (const uci of review?.moves.slice(0, ply) ?? []) {
			const m = c.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
			last = { from: m.from, to: m.to };
		}
		return { fen: c.fen(), last };
	});

	let current = $derived(ply > 0 ? analysis?.moves[ply - 1] : undefined);
	let evalNow = $derived(analysis ? analysis.evals[ply] : 0);
	// White's share of the bar, 0..100, using the same curve as the win-chance grading.
	let whiteShare = $derived(50 + 50 * (2 / (1 + Math.exp(-0.00368208 * evalNow)) - 1));

	function evalText(cp: number) {
		if (Math.abs(cp) >= 900) return cp > 0 ? 'White mates' : 'Black mates';
		return `${cp >= 0 ? '+' : ''}${(cp / 100).toFixed(1)}`;
	}

	const total = $derived(review?.moves.length ?? 0);
	const go = (n: number) => (ply = Math.max(0, Math.min(total, n)));
	function onKey(e: KeyboardEvent) {
		if (e.key === 'ArrowLeft') go(ply - 1);
		else if (e.key === 'ArrowRight') go(ply + 1);
		else if (e.key === 'Home') go(0);
		else if (e.key === 'End') go(total);
	}

	// Evaluation graph: one point per position, clickable.
	const GW = 300;
	const GH = 70;
	let path = $derived.by(() => {
		if (!analysis) return '';
		const n = analysis.evals.length - 1 || 1;
		return analysis.evals
			.map((cp, i) => {
				const y = GH - (GH * (50 + 50 * (2 / (1 + Math.exp(-0.00368208 * cp)) - 1))) / 100;
				return `${i === 0 ? 'M' : 'L'}${((i / n) * GW).toFixed(1)},${y.toFixed(1)}`;
			})
			.join(' ');
	});
	function graphClick(e: MouseEvent) {
		const r = (e.currentTarget as SVGElement).getBoundingClientRect();
		go(Math.round(((e.clientX - r.left) / r.width) * total));
	}

	function resultText(r: Review) {
		const why = r.reason.replace('_', ' ');
		return r.result === '1/2-1/2' ? `Draw (${why})` : `${r.result === '1-0' ? 'White' : 'Black'} won (${why})`;
	}
</script>

<svelte:window onkeydown={onKey} />
<svelte:head><title>Game review · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/">← Lobby</a>
	{#if failure}
		<p class="err">{failure}</p>
	{:else if !review}
		<p>Loading…</p>
	{:else}
		<h1>Game review</h1>
		<p class="sub">{review.players.white} vs {review.players.black} · {resultText(review)}</p>

		<div class="boardrow">
			<div class="evalbar" aria-label="Evaluation" data-eval={evalNow}>
				<div class="white" style="height:{analysis ? whiteShare : 50}%"></div>
			</div>
			<div class="boardwrap">
				<Board
					fen={position.fen}
					orientation={flipped ? 'black' : 'white'}
					lastMove={position.last}
					interactive={false}
					legalTargets={() => []}
					onmove={() => {}}
				/>
			</div>
		</div>

		<div class="nav">
			<button onclick={() => go(0)} aria-label="Start">⏮</button>
			<button onclick={() => go(ply - 1)} aria-label="Previous move">◀</button>
			<span class="where">{ply} / {total}</span>
			<button onclick={() => go(ply + 1)} aria-label="Next move">▶</button>
			<button onclick={() => go(total)} aria-label="End">⏭</button>
			<button onclick={() => (flipped = !flipped)} aria-label="Flip board">⇅</button>
		</div>

		{#if analysing}
			<p class="note" role="status">Stockfish is analysing the game…</p>
		{:else if !review.engine}
			<p class="note">Computer analysis is not available on this server. You can still step through the moves.</p>
		{/if}

		{#if analysis}
			<p class="eval">Evaluation: <b>{evalText(evalNow)}</b></p>
			{#if current}
				<p class="comment" data-cls={current.cls}>
					<b>{current.san}</b> was {LABEL[current.cls]}.
					{#if current.best_san && current.cls !== 'best' && current.cls !== 'good'}
						Better was <b>{current.best_san}</b>.
					{/if}
				</p>
			{/if}

			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
			<svg class="graph" viewBox="0 0 {GW} {GH}" preserveAspectRatio="none" onclick={graphClick} role="img" aria-label="Evaluation graph">
				<rect width={GW} height={GH} fill="#2a2520" />
				<line x1="0" x2={GW} y1={GH / 2} y2={GH / 2} stroke="#4a4038" />
				<path d={path} fill="none" stroke="#f5a623" stroke-width="2" vector-effect="non-scaling-stroke" />
				<line x1={(ply / (total || 1)) * GW} x2={(ply / (total || 1)) * GW} y1="0" y2={GH} stroke="#fff" opacity="0.6" />
			</svg>

			<div class="summary">
				{#each ['white', 'black'] as const as side}
					<div class="side" data-side={side}>
						<b>{review.players[side]}</b>
						<span class="acc">{analysis.accuracy[side] ?? '–'}% accuracy</span>
						<span class="counts">
							{analysis.counts[side].blunder} blunders · {analysis.counts[side].mistake} mistakes ·
							{analysis.counts[side].inaccuracy} inaccuracies
						</span>
					</div>
				{/each}
			</div>
		{/if}

		<ol class="moves">
			{#each review.moves as _, i}
				{@const m = analysis?.moves[i]}
				{#if i % 2 === 0}<li class="num">{i / 2 + 1}.</li>{/if}
				<li>
					<button class="mv" class:on={ply === i + 1} data-cls={m?.cls} onclick={() => go(i + 1)}>
						{m?.san ?? review.moves[i]}<sup>{m ? MARK[m.cls] : ''}</sup>
					</button>
				</li>
			{/each}
		</ol>
	{/if}
</main>

<style>
	main {
		max-width: 520px;
		margin: 0 auto;
		padding: 1rem 16px 3rem;
	}
	.back {
		color: #a89a8a;
		text-decoration: none;
	}
	h1 {
		margin: 0.4rem 0 0;
	}
	.sub {
		color: #a89a8a;
		margin: 0.2rem 0 0.8rem;
	}
	.boardrow {
		display: flex;
		gap: 6px;
		align-items: stretch;
	}
	.boardwrap {
		flex: 1;
		min-width: 0;
	}
	.evalbar {
		width: 14px;
		background: #1b1815;
		border-radius: 4px;
		display: flex;
		flex-direction: column-reverse;
		overflow: hidden;
	}
	.evalbar .white {
		background: #f0e6d8;
		transition: height 0.2s;
	}
	.nav {
		display: flex;
		justify-content: center;
		align-items: center;
		gap: 8px;
		margin: 10px 0;
	}
	.nav button {
		padding: 0.5rem 0.8rem;
		border-radius: 6px;
		border: 1px solid #4a4038;
		background: #2a2520;
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
	}
	.where {
		min-width: 4.5rem;
		text-align: center;
		color: #cdbfae;
	}
	.note {
		color: #f5a623;
	}
	.eval {
		margin: 0.3rem 0;
	}
	.comment {
		margin: 0.3rem 0 0.6rem;
		padding: 8px 10px;
		border-radius: 8px;
		background: #2a2520;
		border-left: 4px solid #6fcf6f;
	}
	.comment[data-cls='inaccuracy'] {
		border-color: #e6c84f;
	}
	.comment[data-cls='mistake'] {
		border-color: #ff9b6b;
	}
	.comment[data-cls='blunder'] {
		border-color: #ff5d5d;
	}
	.graph {
		width: 100%;
		height: 70px;
		border-radius: 6px;
		cursor: pointer;
		display: block;
	}
	.summary {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
		margin: 12px 0;
	}
	.side {
		background: #2a2520;
		border-radius: 8px;
		padding: 8px 10px;
		display: flex;
		flex-direction: column;
		gap: 2px;
		font-size: 0.9rem;
	}
	.acc {
		color: #f5a623;
		font-weight: 700;
	}
	.counts {
		color: #a89a8a;
		font-size: 0.8rem;
	}
	.moves {
		list-style: none;
		padding: 0;
		margin: 8px 0 0;
		display: flex;
		flex-wrap: wrap;
		gap: 2px 4px;
		align-items: center;
	}
	.num {
		color: #a89a8a;
		margin-left: 6px;
	}
	.mv {
		background: none;
		border: none;
		color: inherit;
		font-size: 1rem;
		padding: 4px 6px;
		border-radius: 4px;
		cursor: pointer;
	}
	.mv.on {
		background: #4a4038;
	}
	.mv[data-cls='inaccuracy'] sup {
		color: #e6c84f;
	}
	.mv[data-cls='mistake'] sup {
		color: #ff9b6b;
	}
	.mv[data-cls='blunder'] sup {
		color: #ff5d5d;
	}
	.mv[data-cls='best'] sup {
		color: #6fcf6f;
	}
	.err {
		color: #ff6b6b;
	}
</style>
