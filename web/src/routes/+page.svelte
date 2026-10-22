<script lang="ts">
	import { goto } from '$app/navigation';
	import { onDestroy, onMount } from 'svelte';
	import {
		ApiError,
		BOT_LEVELS,
		createBotGame,
		createGame,
		enterQueue,
		fetchMyGames,
		joinGame,
		leaveQueue,
		leaveQueueOnExit,
		pollQueue,
		saveSeat,
		type BotColor,
		type GameSummary,
		type QueueState,
		type Seat
	} from '../lib/api';
	import { session } from '../lib/session.svelte';

	let minutes = $state(10);
	let increment = $state(0);
	let code = $state('');
	let error = $state('');
	let busy = $state(false);
	let searching = $state(false);
	let searchSeconds = $state(0);
	let info = $state('');
	let botLevel = $state(2);
	let botColor = $state<BotColor>('random');
	let searchTimer: ReturnType<typeof setInterval> | null = null;
	let history = $state<GameSummary[]>([]);
	let poller: ReturnType<typeof setInterval> | null = null;

	const presets = [
		{ label: '3+2', m: 3, i: 2 },
		{ label: '5+3', m: 5, i: 3 },
		{ label: '10+0', m: 10, i: 0 },
		{ label: '10+5', m: 10, i: 5 },
		{ label: '15+10', m: 15, i: 10 }
	];

	const onPageHide = () => searching && leaveQueueOnExit();

	onMount(async () => {
		window.addEventListener('pagehide', onPageHide);
		await session.refresh();
		if (session.kind === 'kid') return goto('/kids'); // a child's session never sees adult screens
		if (session.user) {
			try {
				history = await fetchMyGames();
			} catch {}
		}
	});
	onDestroy(() => {
		if (typeof window !== 'undefined') window.removeEventListener('pagehide', onPageHide);
		stopPolling();
		if (searching) leaveQueue().catch(() => {});
	});

	async function enter(seat: Seat) {
		saveSeat(seat);
		await goto(`/game/${seat.game_id}`);
	}

	async function run(fn: () => Promise<Seat>) {
		busy = true;
		error = '';
		try {
			await enter(await fn());
		} catch (e) {
			error = e instanceof Error ? e.message : 'Something went wrong';
		} finally {
			busy = false;
		}
	}

	function stopPolling() {
		if (poller) clearInterval(poller);
		if (searchTimer) clearInterval(searchTimer);
		poller = searchTimer = null;
	}

	/** The saved sign-in stopped working (e.g. it expired): stop searching and say so. */
	function sessionExpired() {
		stopPolling();
		searching = false;
		session.signOut();
		history = [];
		error = 'Your session expired. Please sign in again.';
	}

	async function handleQueue(state: QueueState) {
		if (state.status === 'waiting' && state.already_searching) {
			// This account is already searching in another tab or device; it can't be paired with itself.
			stopPolling();
			searching = false;
			info =
				'This account is already searching in another tab or device. To test online play, sign in with a second account in another tab or a private window.';
		} else if (state.status === 'matched') {
			stopPolling();
			searching = false;
			await enter(state.seat);
		} else if (state.status === 'idle' && searching) {
			// The server dropped our search (restart, or a throttled background tab).
			stopPolling();
			searching = false;
			info = 'The search ended. Tap Play online to try again.';
		}
	}

	async function quickMatch() {
		if (searching) return; // a second tap must not start a second poller
		error = '';
		info = '';
		stopPolling();
		try {
			searching = true;
			searchSeconds = 0;
			searchTimer = setInterval(() => searchSeconds++, 1000);
			await handleQueue(await enterQueue(minutes, increment));
			if (searching) {
				poller = setInterval(async () => {
					try {
						await handleQueue(await pollQueue());
					} catch (e) {
						if (e instanceof ApiError && e.status === 401) sessionExpired();
					}
				}, 1500);
			}
		} catch (e) {
			stopPolling();
			searching = false;
			if (e instanceof ApiError && e.status === 401) sessionExpired();
			else error = e instanceof Error ? e.message : 'Could not start matchmaking';
		}
	}

	async function cancelSearch() {
		stopPolling();
		searching = false;
		try {
			await leaveQueue();
		} catch {}
	}

	async function playComputer() {
		if (searching) await cancelSearch();
		await run(() => createBotGame(botLevel, botColor, minutes, increment));
	}

	function resultLabel(g: GameSummary) {
		if (g.result === '1/2-1/2') return 'Draw';
		return (g.result === '1-0') === (g.color === 'white') ? 'Won' : 'Lost';
	}
</script>

<svelte:head><title>Chess Yetu</title></svelte:head>

<main>
	<header>
		<div class="brand">
			<span class="logo" aria-hidden="true">♞</span>
			<div>
				<h1>Chess Yetu</h1>
				<p class="tag">Challenge your mind.</p>
			</div>
		</div>
		{#if session.ready}
			{#if session.user}
				<div class="me">
					<b>{session.user.username}</b>
					<span class="rating">{session.user.rating}{session.user.rd > 110 ? '?' : ''}</span>
					<button class="link" onclick={() => (session.signOut(), (history = []))}>Sign out</button>
				</div>
			{:else}
				<a class="signin" href="/login">Sign in</a>
			{/if}
		{/if}
		<a class="gear" href="/settings" aria-label="Settings" title="Settings">⚙</a>
	</header>

	<section class="card play">
		<h2>Time control</h2>
		<div class="presets">
			{#each presets as p}
				<button class:active={minutes === p.m && increment === p.i} disabled={searching} onclick={() => ((minutes = p.m), (increment = p.i))}>
					{p.label}
				</button>
			{/each}
		</div>
		<p class="note">
			{minutes}+{increment} means each player gets {minutes} minutes on their clock{increment
				? `, plus ${increment} extra seconds after every move they make`
				: ', with no extra time per move'}. If your clock runs out you lose.
		</p>

		{#if session.user}
			{#if searching}
				<button class="primary" onclick={cancelSearch}>Searching for an opponent… (cancel)</button>
			{:else}
				<button class="primary" onclick={quickMatch}>Play online · rated</button>
			{/if}
			{#if searching && searchSeconds >= 10}
				<p class="note">No opponent yet. <button class="link inline" onclick={playComputer}>Play the computer instead</button></p>
			{:else}
				<p class="note">Paired with a player near your rating.</p>
			{/if}
		{:else if session.ready}
			<p class="note"><a href="/login">Sign in</a> to play rated games online.</p>
		{/if}

		<div class="friend">
			<h3>Play a friend</h3>
			<button class="secondary" disabled={busy || searching} onclick={() => run(() => createGame(minutes, increment))}>
				Challenge a friend (link)
			</button>
			<p class="or">or join theirs</p>
			<form onsubmit={(e) => (e.preventDefault(), run(() => joinGame(code)))}>
				<input placeholder="Paste the game link or code" aria-label="Game link or code" bind:value={code} autocomplete="off" />
				<button class="primary join" disabled={busy || !code.trim()}>Join</button>
			</form>
		</div>
	</section>

	{#if session.notice && !session.user}<p class="info">{session.notice}</p>{/if}
	{#if info}<p class="info">{info}</p>{/if}
	{#if error}<p class="err">{error} {#if !session.user}<a href="/login">Sign in</a>{/if}</p>{/if}

	<section class="card">
		<h2>Play the computer</h2>
		<div class="levels" role="group" aria-label="Difficulty">
			{#each BOT_LEVELS as l}
				<button class:active={botLevel === l.level} onclick={() => (botLevel = l.level)}>{l.name}</button>
			{/each}
		</div>
		<div class="colors" role="group" aria-label="Your colour">
			{#each [['random', 'Random'], ['white', 'White'], ['black', 'Black']] as [value, text]}
				<button class:active={botColor === value} onclick={() => (botColor = value as BotColor)}>{text}</button>
			{/each}
		</div>
		<button class="secondary" disabled={busy} onclick={playComputer}>Play vs computer ({minutes}+{increment})</button>
		<p class="note">Unrated. No account needed.</p>
	</section>

	<nav class="tiles" aria-label="More to do">
		<a class="tile kids" href="/kids">
			<span class="icon" aria-hidden="true">🧒</span>
			<b>Chess for kids</b>
			<span>A safe place to learn and play</span>
		</a>
		<a class="tile" href="/puzzles">
			<span class="icon" aria-hidden="true">🧩</span>
			<b>Daily puzzles</b>
			<span>Three a day. Build a streak</span>
		</a>
		<a class="tile" href="/tournaments">
			<span class="icon" aria-hidden="true">🏆</span>
			<b>Tournaments</b>
			<span>Play for points in an arena</span>
		</a>
		<a class="tile" href="/leaderboard">
			<span class="icon" aria-hidden="true">📈</span>
			<b>Leaderboard</b>
			<span>The top rated players</span>
		</a>
	</nav>

	{#if history.length}
		<section class="card">
			<h2>Recent games</h2>
			<ul class="history">
				{#each history as g (g.id)}
					<li>
						<span class="res {resultLabel(g).toLowerCase()}">{resultLabel(g)}</span>
						<span>{g.moves} moves · {g.reason.replace('_', ' ')} · <a href="/review/{g.id}">review</a></span>
						<span class="delta">{g.rated ? (g.delta >= 0 ? '+' : '') + g.delta : 'casual'}</span>
					</li>
				{/each}
			</ul>
		</section>
	{/if}
</main>

<style>
	main {
		max-width: 460px;
		margin: 0 auto;
		padding: 1.5rem 16px 3rem;
	}
	header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 12px;
		margin-bottom: 1.25rem;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.logo {
		display: grid;
		place-items: center;
		width: 48px;
		height: 48px;
		border-radius: 12px;
		background: linear-gradient(135deg, var(--accent), #d9822b);
		color: var(--on-accent);
		font-size: 2rem;
		line-height: 1;
	}
	h1 {
		font-size: 1.6rem;
		margin: 0;
		letter-spacing: -0.01em;
	}
	.tag {
		color: var(--muted);
		margin: 0;
		font-size: 0.9rem;
	}
	.me {
		text-align: right;
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
	}
	.rating {
		color: var(--accent-text);
		font-weight: 700;
	}
	.gear {
		display: grid;
		place-items: center;
		min-width: 44px;
		min-height: 44px;
		border-radius: 12px;
		border: 1px solid var(--border);
		background: var(--card);
		color: var(--muted-2);
		text-decoration: none;
		font-size: 1.3rem;
	}
	.signin {
		color: var(--on-accent);
		background: var(--accent);
		padding: 0.55rem 1rem;
		border-radius: 999px;
		text-decoration: none;
		font-weight: 700;
	}
	.card {
		background: var(--card);
		border: 1px solid var(--line);
		border-radius: 14px;
		padding: 1.1rem;
		margin-bottom: 1rem;
		box-shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
	}
	.card.play {
		border-color: var(--accent-line);
	}
	h2 {
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--muted);
		margin: 0 0 0.75rem;
	}
	h3 {
		font-size: 1rem;
		margin: 0 0 0.6rem;
	}
	.friend {
		margin-top: 1.1rem;
		padding-top: 1rem;
		border-top: 1px solid var(--line);
	}
	.friend .secondary {
		margin-top: 0;
	}
	.or {
		margin: 0.7rem 0 0.5rem;
		text-align: center;
		color: var(--muted);
		font-size: 0.85rem;
	}
	.tiles {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 12px;
		margin-bottom: 1rem;
	}
	.tile {
		display: flex;
		flex-direction: column;
		gap: 3px;
		background: var(--card);
		border: 1px solid var(--line);
		border-radius: 14px;
		padding: 0.9rem;
		color: inherit;
		text-decoration: none;
		min-height: 110px;
		transition: transform 0.12s, border-color 0.12s;
	}
	.tile:hover,
	.tile:focus-visible {
		border-color: var(--accent);
		transform: translateY(-2px);
	}
	.tile.kids {
		background: linear-gradient(135deg, var(--accent-bg-2), var(--card));
	}
	.tile .icon {
		font-size: 1.6rem;
		margin-bottom: 4px;
	}
	.tile span:not(.icon) {
		color: var(--muted-2);
		font-size: 0.82rem;
		line-height: 1.3;
	}
	.levels,
	.colors {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 8px;
		margin-bottom: 8px;
	}
	button.inline {
		display: inline;
		color: var(--accent-text);
		font-size: inherit;
	}
	.presets {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 6px;
		margin-bottom: 8px;
	}
	form {
		display: flex;
		gap: 8px;
	}
	input {
		flex: 1;
		min-width: 0;
		padding: 0.7rem;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
	}
	input:focus-visible {
		outline: 2px solid var(--accent);
		outline-offset: 1px;
	}
	button {
		padding: 0.7rem 0.5rem;
		min-height: 44px;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
		transition: background 0.12s, border-color 0.12s;
	}
	button:hover:not(:disabled) {
		border-color: var(--border-strong);
	}
	button:focus-visible {
		outline: 2px solid var(--accent);
		outline-offset: 2px;
	}
	button.active {
		border-color: var(--accent);
		background: var(--accent-bg);
		color: var(--accent-strong);
		font-weight: 700;
	}
	button.primary {
		background: var(--accent);
		color: var(--on-accent);
		border: none;
		font-weight: 700;
		width: 100%;
		font-size: 1.05rem;
	}
	button.primary:hover:not(:disabled) {
		background: var(--accent-hover);
	}
	button.secondary {
		width: 100%;
		margin-top: 8px;
		background: var(--inset);
		border-color: var(--border-strong);
	}
	button.join {
		width: auto;
		padding: 0.6rem 1.3rem;
	}
	button.link {
		background: none;
		border: none;
		color: var(--muted);
		padding: 0;
		min-height: 0;
		font-size: 0.85rem;
		text-decoration: underline;
	}
	button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.note {
		color: var(--muted);
		font-size: 0.85rem;
		margin: 8px 0 10px;
		line-height: 1.4;
	}
	.note a {
		color: var(--accent-text);
	}
	.err {
		color: var(--bad);
		background: var(--bad-bg);
		border-radius: 10px;
		padding: 10px 12px;
		margin: 0 0 1rem;
	}
	.err a {
		color: var(--accent-text);
	}
	.info {
		background: var(--card-2);
		border-left: 3px solid var(--accent);
		padding: 10px 12px;
		border-radius: 8px;
		margin: 0 0 1rem;
	}
	.history {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.history li {
		display: grid;
		grid-template-columns: 3.5rem 1fr auto;
		gap: 8px;
		font-size: 0.9rem;
		color: var(--muted);
	}
	.history a {
		color: var(--accent-text);
	}
	.res {
		font-weight: 700;
	}
	.res.won {
		color: var(--good);
	}
	.res.lost {
		color: var(--bad);
	}
	.delta {
		font-variant-numeric: tabular-nums;
	}
</style>
