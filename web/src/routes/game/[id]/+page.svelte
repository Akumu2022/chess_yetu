<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { page } from '$app/state';
	import { joinGame, KID_PHRASES, loadSeat, saveSeat, type Seat } from '../../../lib/api';
	import { GameClient } from '../../../lib/gameClient.svelte';
	import Board from '#lib/Board.svelte';
	import CapturedPieces from '#lib/CapturedPieces.svelte';

	let game = $state<GameClient | null>(null);
	let failure = $state('');
	let copied = $state(false);
	const id = page.params.id!;

	onMount(async () => {
		let seat: Seat | null = loadSeat(id);
		if (!seat) {
			try {
				seat = await joinGame(id);
				saveSeat(seat);
			} catch (e) {
				failure = e instanceof Error ? e.message : 'Could not join';
				return;
			}
		}
		game = new GameClient(seat);
		game.start();
	});
	onDestroy(() => game?.stop());

	function fmt(ms: number) {
		const s = Math.ceil(ms / 1000);
		if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`;
		return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
	}

	async function copyLink() {
		try {
			await navigator.clipboard.writeText(location.href);
			copied = true;
			setTimeout(() => (copied = false), 1500);
		} catch {}
	}

	const REASONS: Record<string, string> = {
		checkmate: 'by checkmate',
		timeout: 'on time',
		resignation: 'by resignation',
		agreement: 'by agreement',
		stalemate: 'by stalemate',
		insufficient_material: 'insufficient material',
		repetition: 'by repetition',
		fifty_moves: 'fifty-move rule'
	};

	let chatCooldown = $state(false);
	function say(phrase: string) {
		if (chatCooldown) return;
		game?.say(phrase);
		chatCooldown = true;
		setTimeout(() => (chatCooldown = false), 1500);
	}

	/** Gentler wording for children: celebrate effort and progress, not only wins. */
	function kidOutcome(g: GameClient) {
		if (g.result === '1/2-1/2') return 'A draw! Well played. 🤝';
		const won = (g.result === '1-0') === (g.you === 'white');
		if (won) {
			const theirs = g.players[g.you === 'white' ? 'black' : 'white']?.rating;
			const mine = g.players[g.you]?.rating;
			return theirs && mine && theirs > mine ? 'You beat a stronger player! 🎉' : 'You won! 🎉';
		}
		return 'Good game! Every game makes you stronger. 💪';
	}

	function outcome(g: GameClient) {
		if (g.kids) return kidOutcome(g);
		const why = REASONS[g.reason ?? ''] ?? g.reason ?? '';
		if (g.result === '1/2-1/2') return `Draw ${why}`;
		const winner = g.result === '1-0' ? 'white' : 'black';
		return `${winner === g.you ? 'You won' : 'You lost'} ${why}`;
	}

	function label(g: GameClient, color: 'white' | 'black', fallback: string) {
		const p = g.players[color];
		if (!p) return fallback;
		return p.rating ? `${p.name} (${p.rating})` : p.name;
	}

	/** What `color` has taken, and how far ahead it is. White takes black pieces, so takenColor is the other one. */
	function takenBy(g: GameClient, color: 'white' | 'black') {
		return {
			pieces: color === 'white' ? g.history.byWhite : g.history.byBlack,
			takenColor: (color === 'white' ? 'b' : 'w') as 'w' | 'b',
			lead: Math.max(0, color === 'white' ? g.materialLead : -g.materialLead)
		};
	}

	// Where "back" goes depends on what kind of game this is.
	let backHref = $derived(game?.kids ? '/kids' : game?.tournament ? `/tournaments/${game.tournament}` : '/');
	let backLabel = $derived(game?.kids ? 'Kids home' : game?.tournament ? 'Tournament' : 'Lobby');

	let opp = $derived<'white' | 'black'>(game ? (game.you === 'white' ? 'black' : 'white') : 'black');
</script>

<svelte:head><title>Game · Chess Yetu</title></svelte:head>

<main data-color={game?.you}>
	<a class="back" href={backHref} data-testid="game-back">← {backLabel}</a>
	{#if failure}
		<p class="err">{failure}</p>
	{:else if !game}
		<p>Loading…</p>
	{:else}
		<div class="bar top">
			<div class="side">
				<div class="who">
					<span class="dot" class:off={!game.opponentConnected}></span>
					{label(game, opp, `Opponent (${opp})`)}
					{#if game.said[opp]}<span class="bubble" data-said={game.said[opp]}>{KID_PHRASES[game.said[opp]!]}</span>{/if}
				</div>
				<CapturedPieces by={opp} {...takenBy(game, opp)} />
			</div>
			<div class="clock" class:run={game.status === 'active' && game.turn === opp} class:low={game.clocks[opp] < 10000}>
				{fmt(game.clocks[opp])}
			</div>
		</div>

		<Board
			fen={game.fen}
			orientation={game.you}
			lastMove={game.lastMove}
			interactive={game.canMove()}
			legalTargets={(s) => game!.legalTargets(s)}
			onmove={(f, t, promo) => game!.move(f, t, promo)}
		/>

		<div class="bar bottom">
			<div class="side">
				<div class="who">
					{label(game, game.you, `You (${game.you})`)}
					{#if game.said[game.you]}<span class="bubble mine">{KID_PHRASES[game.said[game.you]!]}</span>{/if}
				</div>
				<CapturedPieces by={game.you} {...takenBy(game, game.you)} />
			</div>
			<div class="clock" class:run={game.status === 'active' && game.turn === game.you} class:low={game.clocks[game.you] < 10000}>
				{fmt(game.clocks[game.you])}
			</div>
		</div>

		{#if game.fatal}
			<div class="panel" role="alert" data-fatal>
				<b>{game.fatal}</b>
				<a href={backHref}>{backLabel}</a>
			</div>
		{:else if !game.connected}
			<p class="banner">Reconnecting…</p>
		{:else if game.status === 'active' && !game.opponentConnected}
			<p class="banner">Opponent disconnected. Waiting for them to return…</p>
		{/if}

		{#if game.kids && game.status !== 'over'}
			<div class="chat" role="group" aria-label="Say something nice">
				{#each Object.entries(KID_PHRASES) as [pid, text] (pid)}
					<button disabled={chatCooldown} onclick={() => say(pid)} data-say={pid}>{text}</button>
				{/each}
			</div>
		{/if}

		{#if game.status === 'waiting'}
			<div class="panel">
				<p>Waiting for an opponent. Share this link or code <b>{id}</b>:</p>
				<button onclick={copyLink}>{copied ? 'Copied!' : 'Copy game link'}</button>
			</div>
		{:else if game.status === 'over'}
			<div class="panel over">
				<div>
					<b>{outcome(game)}</b>
					{#if game.ratingChange}
						{@const d = game.ratingChange[game.you]}
						{#if !game.kids}
							<div class="delta" class:up={d >= 0}>Rating {d >= 0 ? '+' : ''}{d.toFixed(1)}</div>
						{:else if d > 0}
							<div class="delta up">Level +{d.toFixed(0)} ⭐</div>
						{/if}
					{:else if game.rated === false && !game.kids}
						<div class="delta">Casual game · not rated</div>
					{/if}
				</div>
				<div class="after">
					{#if !game.kids && game.moves.length > 0}<a class="review" href="/review/{id}">Review game</a>{/if}
					{#if game.tournament}
						<a class="back-to" href="/tournaments/{game.tournament}">Back to tournament</a>
					{:else}
						<a href={game.kids ? '/kids' : '/'}>{game.kids ? 'Play again' : 'New game'}</a>
					{/if}
				</div>
			</div>
		{:else if game.status === 'active'}
			<div class="actions">
				<button onclick={() => game!.offerDraw()}>
					{game.drawOfferedBy && game.drawOfferedBy !== game.you ? 'Accept draw' : 'Offer draw'}
				</button>
				<button onclick={() => confirm('Resign this game?') && game!.resign()}>Resign</button>
			</div>
		{/if}

		{#if game.notice}<p class="banner">{game.notice}</p>{/if}
		{#if game.error}<p class="err">{game.error}</p>{/if}

		<details class="movelist">
			<summary>Moves ({game.history.san.length})</summary>
			<ol class="moves">
				{#each game.history.san as m, i}
					<li>{i % 2 === 0 ? `${i / 2 + 1}.` : ''} {m}</li>
				{/each}
			</ol>
		</details>
	{/if}
</main>

<style>
	main {
		max-width: 520px;
		margin: 0 auto;
		padding: 12px 16px 32px;
	}
	.bar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin: 8px 0;
	}
	.bubble {
		background: #f5a623;
		color: #1b1815;
		font-weight: 700;
		font-size: 0.85rem;
		padding: 2px 10px;
		border-radius: 12px;
		animation: pop 0.2s ease-out;
	}
	.bubble.mine {
		background: #6fcf6f;
	}
	@keyframes pop {
		from {
			transform: scale(0.6);
			opacity: 0;
		}
	}
	.chat {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 6px;
		margin-top: 12px;
	}
	.chat button {
		flex: none;
		padding: 0.45rem 0.2rem;
		font-size: 0.8rem;
	}
	.side {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.movelist summary {
		cursor: pointer;
		color: #a89a8a;
		margin-top: 16px;
	}
	.who {
		display: flex;
		align-items: center;
		gap: 8px;
		font-weight: 600;
	}
	.dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: #4caf50;
	}
	.dot.off {
		background: #888;
	}
	.clock {
		font-variant-numeric: tabular-nums;
		font-size: 1.5rem;
		font-weight: 700;
		padding: 4px 14px;
		border-radius: 8px;
		background: #2a2520;
		color: #a89a8a;
	}
	.clock.run {
		color: #fff;
		background: #3a322b;
	}
	.clock.low.run {
		color: #ff6b6b;
	}
	.banner {
		background: #5a3b00;
		padding: 8px 12px;
		border-radius: 6px;
		text-align: center;
	}
	.panel {
		background: #2a2520;
		border-radius: 10px;
		padding: 12px 16px;
		margin-top: 12px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.panel.over {
		flex-direction: row;
		justify-content: space-between;
		align-items: center;
	}
	.after {
		display: flex;
		gap: 14px;
	}
	.actions {
		display: flex;
		gap: 8px;
		margin-top: 12px;
	}
	button {
		flex: 1;
		padding: 0.6rem;
		border-radius: 6px;
		border: 1px solid #4a4038;
		background: #1b1815;
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
	}
	a {
		color: #f5a623;
	}
	.err {
		color: #ff6b6b;
	}
	.delta {
		color: #ff6b6b;
		font-size: 0.9rem;
		margin-top: 2px;
	}
	.delta.up {
		color: #6fcf6f;
	}
	.moves {
		list-style: none;
		padding: 0;
		margin: 16px 0 0;
		display: flex;
		flex-wrap: wrap;
		gap: 4px 10px;
		color: #a89a8a;
		font-size: 0.9rem;
	}
</style>
