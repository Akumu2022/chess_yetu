<script lang="ts">
	import { goto } from '$app/navigation';
	import { onDestroy, onMount } from 'svelte';
	import {
		ApiError,
		createKidBotGame,
		enterKidQueue,
		exitKidsMode,
		kidGames,
		KID_BOTS,
		leaveKidQueue,
		leaveQueueOnExit,
		pollKidQueue,
		saveSeat,
		type KidGame,
		type QueueState,
		type Seat
	} from '../api';
	import { session } from '../session.svelte';

	let error = $state('');
	let info = $state('');
	let busy = $state(false);
	let searching = $state(false);
	let searchSeconds = $state(0);
	let history = $state<KidGame[]>([]);
	let askingPin = $state(false);
	let pin = $state('');
	let poller: ReturnType<typeof setInterval> | null = null;
	let ticker: ReturnType<typeof setInterval> | null = null;

	let child = $derived(session.child!);
	let outOfTime = $derived(child.minutes_left <= 0);

	const onPageHide = () => searching && leaveQueueOnExit('/kids/queue');

	onMount(async () => {
		window.addEventListener('pagehide', onPageHide);
		await session.refresh(); // fresh rating and time left
		if (session.kind !== 'kid') return goto('/kids');
		try {
			history = await kidGames();
		} catch {}
	});
	onDestroy(() => {
		if (typeof window !== 'undefined') window.removeEventListener('pagehide', onPageHide);
		stopTimers();
		if (searching) leaveKidQueue().catch(() => {});
	});

	function stopTimers() {
		if (poller) clearInterval(poller);
		if (ticker) clearInterval(ticker);
		poller = ticker = null;
	}

	async function enter(seat: Seat) {
		saveSeat(seat);
		await goto(`/game/${seat.game_id}`);
	}

	function problem(e: unknown) {
		stopTimers();
		searching = false;
		if (e instanceof ApiError && e.status === 401) {
			session.signOut();
			error = 'This session ended. Ask a grown-up to start it again.';
			goto('/kids');
		} else {
			error = e instanceof Error ? e.message : 'Something went wrong';
			session.refresh(); // e.g. "Time's up" changes what we show
		}
	}

	async function playBot(bot: number) {
		busy = true;
		error = info = '';
		try {
			if (searching) await cancel();
			await enter(await createKidBotGame(bot, 'random'));
		} catch (e) {
			problem(e);
		} finally {
			busy = false;
		}
	}

	async function handle(state: QueueState) {
		if (state.status === 'matched') {
			stopTimers();
			searching = false;
			await enter(state.seat);
		} else if (state.status === 'waiting' && state.already_searching) {
			stopTimers();
			searching = false;
			info = 'You are already looking for a friend on another screen.';
		} else if (state.status === 'idle' && searching) {
			stopTimers();
			searching = false;
			info = 'The search ended. Tap the button to try again.';
		}
	}

	async function findKid() {
		error = info = '';
		try {
			searching = true;
			searchSeconds = 0;
			ticker = setInterval(() => searchSeconds++, 1000);
			await handle(await enterKidQueue());
			if (searching) {
				poller = setInterval(async () => {
					try {
						await handle(await pollKidQueue());
					} catch (e) {
						if (e instanceof ApiError && e.status === 401) problem(e);
					}
				}, 1500);
			}
		} catch (e) {
			problem(e);
		}
	}

	async function cancel() {
		stopTimers();
		searching = false;
		try {
			await leaveKidQueue();
		} catch {}
	}

	async function leave(e: SubmitEvent) {
		e.preventDefault();
		error = '';
		try {
			const { token, user } = await exitKidsMode(pin);
			session.signIn(token, user);
			await goto('/kids');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Something went wrong';
			pin = '';
		}
	}

	function resultText(g: KidGame) {
		if (g.result === '1/2-1/2') return 'Draw';
		return (g.result === '1-0') === (g.color === 'white') ? 'Won' : 'Keep going';
	}
</script>

<section class="hello">
	<h2>Hi {child.nickname}! 👋</h2>
	<p class="stats">Level {child.rating} · {child.games} games played</p>
	<p class="time" class:low={child.minutes_left <= 10}>
		{#if outOfTime}
			Time’s up for today. Come back tomorrow! 🌙
		{:else}
			{child.minutes_left} minutes of play left today
		{/if}
	</p>
</section>

<section>
	<h2>Puzzles</h2>
	<a class="puzzle-link" href="/puzzles">🧩 Today’s puzzles: find the checkmate</a>
</section>

<section>
	<h2>Play a friendly computer</h2>
	<div class="bots">
		{#each KID_BOTS as b (b.bot)}
			<button class="bot" disabled={busy || outOfTime} onclick={() => playBot(b.bot)} data-bot={b.name}>
				<b>{b.name}</b>
				<span>{b.blurb}</span>
			</button>
		{/each}
	</div>
</section>

<section>
	<h2>Play another kid</h2>
	{#if searching}
		<button class="primary" onclick={cancel}>Looking for a friend… (cancel)</button>
		{#if searchSeconds >= 10}
			<p class="note">Nobody yet. <button class="link" onclick={() => playBot(1)}>Play Zuri the Gentle instead</button></p>
		{/if}
	{:else}
		<button class="primary" disabled={outOfTime} onclick={findKid}>Find a kid to play</button>
		<p class="note">You will only ever meet other kids. You can say nice things with the buttons in the game.</p>
	{/if}
</section>

{#if info}<p class="info">{info}</p>{/if}
{#if error}<p class="err">{error}</p>{/if}

{#if history.length}
	<section>
		<h2>Your games</h2>
		<ul class="history">
			{#each history as g (g.id)}
				<li>
					<b class="res {resultText(g).toLowerCase().replace(' ', '')}">{resultText(g)}</b>
					<span>vs {g.opponent}</span>
					<span class="delta">{g.rated && g.delta > 0 ? `+${g.delta}` : ''}</span>
				</li>
			{/each}
		</ul>
	</section>
{/if}

<section class="parent">
	{#if askingPin}
		<form onsubmit={leave}>
			<input type="password" inputmode="numeric" maxlength="6" placeholder="Parent PIN" bind:value={pin} autocomplete="off" />
			<button class="primary" disabled={!/^\d{4,6}$/.test(pin)}>Open</button>
		</form>
	{:else}
		<button class="link" onclick={() => (askingPin = true)}>Grown-ups: leave kids mode</button>
	{/if}
</section>

<style>
	.puzzle-link {
		display: block;
		padding: 0.9rem 1rem;
		border-radius: 8px;
		background: var(--inset);
		color: inherit;
		text-decoration: none;
		font-weight: 600;
	}
	section {
		background: var(--card);
		border-radius: 12px;
		padding: 1rem;
		margin-bottom: 1rem;
	}
	.hello {
		background: linear-gradient(135deg, var(--accent-bg), var(--card));
	}
	h2 {
		font-size: 1.1rem;
		margin: 0 0 0.6rem;
	}
	.stats {
		margin: 0;
		color: var(--muted-2);
	}
	.time {
		margin: 6px 0 0;
		font-weight: 700;
		color: var(--good);
	}
	.time.low {
		color: var(--accent-text);
	}
	.bots {
		display: grid;
		gap: 10px;
	}
	.bot {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		padding: 0.9rem 1rem;
		font-size: 1.05rem;
		text-align: left;
	}
	.bot span {
		color: var(--muted);
		font-size: 0.9rem;
	}
	button {
		padding: 0.7rem;
		border-radius: 10px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
		cursor: pointer;
	}
	button.primary {
		background: var(--accent);
		color: var(--on-accent);
		border: none;
		font-weight: 700;
		width: 100%;
		font-size: 1.1rem;
		padding: 0.9rem;
	}
	button.link {
		background: none;
		border: none;
		color: var(--muted);
		padding: 0;
		text-decoration: underline;
		font-size: 0.9rem;
	}
	.note .link {
		color: var(--accent-text);
	}
	button:disabled {
		opacity: 0.45;
		cursor: default;
	}
	.note {
		color: var(--muted);
		font-size: 0.9rem;
		margin: 8px 0 0;
	}
	.info {
		background: var(--card-2);
		border-left: 3px solid var(--accent);
		padding: 10px 12px;
		border-radius: 6px;
	}
	.err {
		color: var(--bad);
	}
	.history {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.history li {
		display: grid;
		grid-template-columns: 5.5rem 1fr auto;
		gap: 8px;
		font-size: 0.95rem;
		color: var(--muted);
	}
	.res.won {
		color: var(--good);
	}
	.res.keepgoing {
		color: var(--accent-text);
	}
	.parent {
		background: none;
		padding: 0;
		text-align: center;
	}
	form {
		display: flex;
		gap: 8px;
	}
	input {
		flex: 1;
		min-width: 0;
		padding: 0.6rem;
		border-radius: 8px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
	}
	form .primary {
		width: auto;
		padding: 0.6rem 1.2rem;
	}
</style>
