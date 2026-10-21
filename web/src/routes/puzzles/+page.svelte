<script lang="ts">
	import { Chess } from 'chess.js';
	import { onMount } from 'svelte';
	import { ApiError, nextPuzzle, puzzleMove, type Puzzle, type PuzzleState } from '../../lib/api';
	import { session } from '../../lib/session.svelte';
	import Board from '#lib/Board.svelte';

	let daily = $state<PuzzleState | null>(null);
	let puzzle = $state<Puzzle | null>(null);
	let chess = new Chess();
	let fen = $state(new Chess().fen());
	let lastMove = $state<{ from: string; to: string } | null>(null);
	let played = $state<string[]>([]);
	let phase = $state<'loading' | 'play' | 'solved' | 'limit' | 'guest'>('loading');
	let message = $state('');
	let error = $state('');
	let busy = $state(false);

	let kid = $derived(session.kind === 'kid');
	let backHref = $derived(kid ? '/kids' : '/');

	onMount(async () => {
		await session.refresh();
		if (session.kind === 'guest') phase = 'guest';
		else await load();
	});

	async function load() {
		error = message = '';
		try {
			const r = await nextPuzzle();
			daily = r;
			if ('limit_reached' in r) {
				puzzle = null;
				phase = 'limit';
				return;
			}
			puzzle = r.puzzle;
			chess = new Chess(r.puzzle.fen);
			fen = chess.fen();
			lastMove = null;
			played = [];
			phase = 'play';
		} catch (e) {
			if (e instanceof ApiError && e.status === 401) phase = 'guest';
			else error = e instanceof Error ? e.message : 'Could not load a puzzle';
		}
	}

	const legalTargets = (from: string) =>
		[...new Set(chess.moves({ square: from as any, verbose: true }).map((m) => m.to))];

	async function onmove(from: string, to: string, promo?: string) {
		if (!puzzle || busy || phase !== 'play') return;
		let made;
		try {
			made = chess.move({ from, to, promotion: promo ?? 'q' });
		} catch {
			return;
		}
		const uci = made.from + made.to + (made.promotion ?? '');
		fen = chess.fen();
		lastMove = { from: made.from, to: made.to };
		busy = true;
		message = '';
		try {
			const r = await puzzleMove(puzzle.id, [...played, uci]);
			if (r.status === 'wrong') {
				chess.undo();
				fen = chess.fen();
				lastMove = null;
				message = kid ? 'Not quite. Have another look!' : 'Not that one. Try again.';
			} else if (r.status === 'continue') {
				played = [...played, uci];
				await new Promise((res) => setTimeout(res, 450));
				const reply = chess.move({ from: r.reply.slice(0, 2), to: r.reply.slice(2, 4), promotion: r.reply[4] });
				fen = chess.fen();
				lastMove = { from: reply.from, to: reply.to };
				message = 'Good! Keep going.';
			} else {
				daily = r;
				phase = 'solved';
			}
		} catch (e) {
			chess.undo();
			fen = chess.fen();
			error = e instanceof Error ? e.message : 'Something went wrong';
			if (e instanceof ApiError && e.status === 403) await load();
		} finally {
			busy = false;
		}
	}

	let toGo = $derived(daily ? Math.max(0, daily.limit - daily.solved_today) : 0);
</script>

<svelte:head><title>Puzzles · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href={backHref}>← Back</a>
	<h1>Daily puzzles</h1>

	{#if phase === 'guest'}
		<p>Sign in to play puzzles and keep your streak.</p>
		<a class="cta" href="/login">Sign in</a>
	{:else if phase === 'loading'}
		<p>Loading…</p>
	{:else}
		{#if daily}
			<div class="stats">
				<span class="streak" data-streak={daily.streak.current}>🔥 {daily.streak.current}-day streak</span>
				<span>{daily.solved_today} of {daily.limit} today</span>
			</div>
		{/if}

		{#if phase === 'limit'}
			<section class="done">
				<h2>{kid ? 'Great work today! 🌟' : 'That is all for today'}</h2>
				<p>You solved {daily?.limit} puzzles. Come back tomorrow to keep your streak going.</p>
				<a class="cta" href={backHref}>Back</a>
			</section>
		{:else if puzzle}
			<p class="goal" data-theme={puzzle.theme}>
				<b>{puzzle.to_move === 'white' ? 'White' : 'Black'} to move.</b>
				{puzzle.theme}: find the checkmate.
			</p>
			<Board {fen} orientation={puzzle.to_move} {lastMove} interactive={phase === 'play' && !busy} {legalTargets} {onmove} />
			{#if message}<p class="msg" role="status">{message}</p>{/if}
			{#if phase === 'solved'}
				<section class="done" data-solved>
					<h2>{kid ? 'Checkmate! You did it! 🎉' : 'Solved!'}</h2>
					{#if daily && daily.streak.current > 0}<p>🔥 {daily.streak.current}-day streak</p>{/if}
					{#if toGo > 0}
						<button class="primary" onclick={load}>Next puzzle</button>
					{:else}
						<p>That was your last puzzle for today.</p>
						<a class="cta" href={backHref}>Back</a>
					{/if}
				</section>
			{/if}
		{/if}
	{/if}
	{#if error}<p class="err">{error}</p>{/if}
</main>

<style>
	main {
		max-width: 460px;
		margin: 0 auto;
		padding: 1.5rem 16px 3rem;
	}
	.back {
		color: #a89a8a;
		text-decoration: none;
	}
	h1 {
		margin: 0.5rem 0 1rem;
	}
	.stats {
		display: flex;
		justify-content: space-between;
		margin-bottom: 0.75rem;
		color: #cdbfae;
	}
	.streak {
		color: #f5a623;
		font-weight: 700;
	}
	.goal {
		margin: 0 0 0.5rem;
	}
	.msg {
		color: #f5a623;
		margin: 0.5rem 0;
	}
	.done {
		background: #2a2520;
		border-radius: 10px;
		padding: 1rem;
		margin-top: 1rem;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.done h2 {
		margin: 0;
	}
	button.primary,
	.cta {
		background: #f5a623;
		color: #1b1815;
		border: none;
		border-radius: 8px;
		padding: 0.8rem 1rem;
		font-size: 1rem;
		font-weight: 700;
		text-align: center;
		text-decoration: none;
		cursor: pointer;
	}
	.err {
		color: #ff6b6b;
	}
</style>
