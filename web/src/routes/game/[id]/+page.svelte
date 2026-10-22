<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { page } from '$app/state';
	import { joinGame, KID_PHRASES, loadSeat, saveSeat, type Seat } from '../../../lib/api';
	import { GameClient } from '../../../lib/gameClient.svelte';
	import { figurine } from '../../../lib/captured';
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

	// On wide screens the move list is always open next to the board; on phones it folds away.
	let wide = $state(false);
	let movesOpen = $state(false);
	let moveBox = $state<HTMLElement | null>(null);
	onMount(() => {
		const mq = window.matchMedia('(min-width: 900px)');
		const sync = () => (wide = mq.matches);
		sync();
		mq.addEventListener('change', sync);
		return () => mq.removeEventListener('change', sync);
	});
	// keep the latest move in view
	$effect(() => {
		game?.moves.length;
		if (moveBox) moveBox.scrollTop = moveBox.scrollHeight;
	});

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
		<div class="table">
		<div class="bar top">
			<div class="side">
				<div class="who">
					<span class="avatar {opp}" aria-hidden="true">{game.vsBot ? '♞' : '♚'}</span>
					<span class="dot" class:off={!game.opponentConnected}></span>
					{label(game, opp, `Opponent (${opp})`)}
					{#if game.vsBot && game.status === 'active' && game.turn === opp}<span class="thinking">thinking<i>.</i><i>.</i><i>.</i></span>{/if}
					{#if game.said[opp]}<span class="bubble" data-said={game.said[opp]}>{KID_PHRASES[game.said[opp]!]}</span>{/if}
				</div>
				<CapturedPieces by={opp} {...takenBy(game, opp)} />
			</div>
			<div class="clock" class:run={game.status === 'active' && game.turn === opp} class:low={game.clocks[opp] < 10000}>
				{fmt(game.clocks[opp])}
			</div>
		</div>

		<div class="boardwrap">
		<Board
			fen={game.fen}
			orientation={game.you}
			lastMove={game.lastMove}
			interactive={game.canMove()}
			legalTargets={(s) => game!.legalTargets(s)}
			onmove={(f, t, promo) => game!.move(f, t, promo)}
		/>
		</div>

		<div class="bar bottom">
			<div class="side">
				<div class="who">
					<span class="avatar {game.you}" aria-hidden="true">♚</span>
					{label(game, game.you, `You (${game.you})`)}
					{#if game.said[game.you]}<span class="bubble mine">{KID_PHRASES[game.said[game.you]!]}</span>{/if}
				</div>
				<CapturedPieces by={game.you} {...takenBy(game, game.you)} />
			</div>
			<div class="clock" class:run={game.status === 'active' && game.turn === game.you} class:low={game.clocks[game.you] < 10000}>
				{fmt(game.clocks[game.you])}
			</div>
		</div>

		<div class="under">
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

		</div>
		<details class="movelist" open={wide || movesOpen} ontoggle={(e) => !wide && (movesOpen = e.currentTarget.open)}>
			<summary>Moves ({game.history.san.length})</summary>
			<ol class="moves" bind:this={moveBox}>
				{#each game.history.san as m, i}
					<li class:last={i === game.history.san.length - 1}>{#if i % 2 === 0}<span class="n">{`${i / 2 + 1}. `}</span>{/if}{figurine(m)}</li>
				{/each}
			</ol>
		</details>
		</div>
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
		background: var(--accent);
		color: var(--on-accent);
		font-weight: 700;
		font-size: 0.85rem;
		padding: 2px 10px;
		border-radius: 12px;
		animation: pop 0.2s ease-out;
	}
	.bubble.mine {
		background: var(--good);
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
		color: var(--muted);
		margin-top: 16px;
	}
	.who {
		display: flex;
		align-items: center;
		gap: 8px;
		font-weight: 600;
	}
	.thinking {
		font-weight: 400;
		font-size: 0.85rem;
		color: var(--muted);
	}
	.thinking i {
		font-style: normal;
		animation: blink 1.2s infinite;
	}
	.thinking i:nth-child(2) {
		animation-delay: 0.2s;
	}
	.thinking i:nth-child(3) {
		animation-delay: 0.4s;
	}
	@keyframes blink {
		0%,
		60%,
		100% {
			opacity: 0.2;
		}
		30% {
			opacity: 1;
		}
	}
	.dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--good);
	}
	.dot.off {
		background: var(--muted);
	}
	.clock {
		font-variant-numeric: tabular-nums;
		font-size: 1.5rem;
		font-weight: 700;
		padding: 4px 14px;
		border-radius: 8px;
		background: var(--card);
		color: var(--muted);
	}
	.clock.run {
		color: var(--text);
		background: var(--card-2);
	}
	.clock.low.run {
		color: var(--bad);
	}
	.banner {
		background: var(--accent-bg);
		border: 1px solid var(--accent-line);
		padding: 8px 12px;
		border-radius: 6px;
		text-align: center;
	}
	.panel {
		background: var(--card);
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
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
	}
	a {
		color: var(--accent-text);
	}
	.err {
		color: var(--bad);
	}
	.delta {
		color: var(--bad);
		font-size: 0.9rem;
		margin-top: 2px;
	}
	.delta.up {
		color: var(--good);
	}
	.moves {
		list-style: none;
		padding: 0;
		margin: 16px 0 0;
		display: flex;
		flex-wrap: wrap;
		gap: 4px 10px;
		color: var(--muted);
		font-size: 1.1rem;
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', system-ui, sans-serif;
	}
	.moves .n {
		color: var(--muted);
		opacity: 0.8;
	}
	.moves li.last {
		color: var(--text);
		font-weight: 700;
	}
	.avatar {
		display: inline-grid;
		place-items: center;
		flex: none;
		width: 28px;
		height: 28px;
		border-radius: 50%;
		font-size: 1.1rem;
		line-height: 1;
		background: var(--card-2);
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', serif;
	}
	.avatar.white {
		color: var(--pc-w);
		-webkit-text-stroke: 0.6px var(--pc-w-line);
	}
	.avatar.black {
		color: var(--pc-b);
		-webkit-text-stroke: 0.6px var(--pc-b-line);
	}
	.table {
		display: contents;
	}
	.boardwrap {
		margin: 0;
	}

	/* Wide screens: players on the left, clocks and the move list on the right, in a framed table. */
	@media (min-width: 900px) {
		main {
			max-width: 1060px;
		}
		.table {
			display: grid;
			grid-template-columns: 210px minmax(0, 1fr) 250px;
			grid-template-rows: auto minmax(0, 1fr) auto auto;
			grid-template-areas:
				'oside board oclock'
				'.     board moves'
				'yside board yclock'
				'under under under';
			gap: 14px 18px;
			padding: 18px;
			background: var(--card);
			border: 8px solid #1b1815;
			border-radius: 28px;
			box-shadow: 0 12px 40px rgba(40, 20, 0, 0.25);
		}
		.bar {
			display: contents;
		}
		.top .side {
			grid-area: oside;
		}
		.top .clock {
			grid-area: oclock;
		}
		.bottom .side {
			grid-area: yside;
		}
		.bottom .clock {
			grid-area: yclock;
		}
		.boardwrap {
			grid-area: board;
		}
		.under {
			grid-area: under;
		}
		.side {
			align-items: center;
			text-align: center;
			gap: 8px;
		}
		.who {
			flex-direction: column;
			gap: 6px;
			font-size: 1.05rem;
		}
		.avatar {
			width: 84px;
			height: 84px;
			font-size: 3.4rem;
			box-shadow: inset 0 0 0 3px var(--border);
		}
		.top .side {
			align-self: start;
		}
		.bottom .side {
			align-self: end;
		}
		.clock {
			align-self: center;
			text-align: center;
			font-size: 2.6rem;
			padding: 10px 14px;
			border-radius: 12px;
		}
		.clock.run {
			background: var(--accent);
			color: var(--on-accent);
		}
		.clock.low.run {
			background: var(--bad);
			color: #fff;
		}
		.movelist {
			grid-area: moves;
			position: relative;
			min-height: 180px;
			background: var(--inset);
			border: 1px solid var(--line);
			border-radius: 12px;
		}
		.movelist summary {
			display: none;
		}
		.moves {
			position: absolute;
			inset: 0;
			margin: 0;
			padding: 12px 14px;
			overflow-y: auto;
			display: grid;
			grid-template-columns: 1fr 1fr;
			align-content: start;
			gap: 6px 8px;
			font-size: 1.2rem;
		}
		.moves li:nth-child(odd) {
			grid-column: 1;
		}
		.moves li:nth-child(even) {
			grid-column: 2;
		}
	}
</style>
