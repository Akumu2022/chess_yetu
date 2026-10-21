<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import {
		childGames,
		createChild,
		deleteChild,
		kidsPinStatus,
		listChildren,
		setChildLimit,
		setKidsPin,
		startKidSession,
		type Child,
		type KidGame
	} from '../api';
	import { session } from '../session.svelte';

	let children = $state<Child[]>([]);
	let pinSet = $state<boolean | null>(null);
	let pin = $state('');
	let currentPin = $state('');
	let changingPin = $state(false);
	let error = $state('');
	let notice = $state('');
	let busy = $state(false);

	const thisYear = new Date().getFullYear();
	const ages = [5, 6, 7, 8, 9, 10, 11, 12, 13];
	let age = $state(8);
	let consent = $state(false);
	let viewing = $state<number | null>(null);
	let games = $state<KidGame[]>([]);

	const LIMITS = [30, 45, 60, 90, 120];

	onMount(load);

	async function load() {
		try {
			[children, pinSet] = await Promise.all([listChildren(), kidsPinStatus().then((s) => s.set)]);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not load';
		}
	}

	async function guard(fn: () => Promise<void>) {
		busy = true;
		error = notice = '';
		try {
			await fn();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Something went wrong';
		} finally {
			busy = false;
		}
	}

	const savePin = () =>
		guard(async () => {
			await setKidsPin(pin, changingPin ? currentPin : undefined);
			pinSet = true;
			pin = currentPin = '';
			changingPin = false;
			notice = 'PIN saved. You will need it to leave a child’s session.';
		});

	const addChild = () =>
		guard(async () => {
			const c = await createChild(thisYear - age, consent);
			consent = false;
			notice = `Profile created. ${c.nickname} is the nickname we generated; no real names are used.`;
			await load();
		});

	const playAs = (c: Child) =>
		guard(async () => {
			const { token, child } = await startKidSession(c.id);
			session.startKid(token, child);
			await goto('/kids');
		});

	const changeLimit = (c: Child, minutes: number) =>
		guard(async () => {
			await setChildLimit(c.id, minutes);
			await load();
		});

	const removeChild = (c: Child) =>
		guard(async () => {
			if (!confirm(`Delete ${c.nickname} and all their games? This cannot be undone.`)) return;
			await deleteChild(c.id);
			if (viewing === c.id) viewing = null;
			await load();
			notice = `${c.nickname} and all their data were deleted.`;
		});

	const toggleGames = (c: Child) =>
		guard(async () => {
			if (viewing === c.id) {
				viewing = null;
				return;
			}
			games = await childGames(c.id);
			viewing = c.id;
		});

	function resultText(g: KidGame) {
		if (g.result === '1/2-1/2') return 'Draw';
		return (g.result === '1-0') === (g.color === 'white') ? 'Won' : 'Lost';
	}
</script>

<section>
	<h2>Your children</h2>
	{#if children.length === 0}
		<p class="muted">No child profiles yet. Add one below.</p>
	{/if}
	{#each children as c (c.id)}
		<article class="child" data-child={c.nickname}>
			<header>
				<div>
					<b class="nick">{c.nickname}</b>
					<span class="muted">age {thisYear - c.birth_year} · rating {c.rating} · {c.games} games</span>
				</div>
			</header>
			<div class="time">
				<span>Today: {c.minutes_today} of {c.daily_limit_min} min</span>
				<progress max={c.daily_limit_min} value={Math.min(c.minutes_today, c.daily_limit_min)}></progress>
			</div>
			<label class="limit">
				Daily limit
				<select value={c.daily_limit_min} onchange={(e) => changeLimit(c, Number(e.currentTarget.value))}>
					{#each LIMITS as m}<option value={m}>{m} min</option>{/each}
				</select>
			</label>
			<div class="row">
				<button class="primary" disabled={busy || !pinSet} onclick={() => playAs(c)}>Play as {c.nickname}</button>
				<button disabled={busy} onclick={() => toggleGames(c)}>{viewing === c.id ? 'Hide games' : 'See games'}</button>
				<button class="danger" disabled={busy} onclick={() => removeChild(c)}>Delete</button>
			</div>
			{#if !pinSet}<p class="muted small">Set a PIN below before handing over the device.</p>{/if}
			{#if viewing === c.id}
				{#if games.length === 0}
					<p class="muted small">No games yet.</p>
				{:else}
					<ul class="games">
						{#each games as g (g.id)}
							<li>
								<b class="res {resultText(g).toLowerCase()}">{resultText(g)}</b>
								<span>vs {g.opponent} · {g.moves} moves · {g.minutes} min</span>
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		</article>
	{/each}
</section>

<section>
	<h2>Add a child</h2>
	<label>
		Age
		<select bind:value={age}>
			{#each ages as a}<option value={a}>{a} years (born {thisYear - a})</option>{/each}
		</select>
	</label>
	<label class="consent">
		<input type="checkbox" bind:checked={consent} />
		<span>
			I am this child’s parent or guardian. I consent to Chess Yetu storing a generated nickname, birth year and game
			history for them, only to run the game. I can delete all of it at any time.
		</span>
	</label>
	<button class="primary" disabled={busy || !consent} onclick={addChild}>Create profile</button>
	<p class="muted small">We never store a real name, photo, school or location. Chat is limited to preset messages.</p>
</section>

<section>
	<h2>Parent PIN</h2>
	{#if pinSet && !changingPin}
		<p class="muted">A PIN is set. It is needed to leave a child’s session.</p>
		<button onclick={() => (changingPin = true)}>Change PIN</button>
	{:else}
		{#if changingPin}
			<input type="password" inputmode="numeric" placeholder="Current PIN" bind:value={currentPin} autocomplete="off" />
		{/if}
		<input type="password" inputmode="numeric" placeholder="New PIN (4 to 6 digits)" bind:value={pin} autocomplete="off" maxlength="6" />
		<button class="primary" disabled={busy || !/^\d{4,6}$/.test(pin)} onclick={savePin}>Save PIN</button>
	{/if}
</section>

{#if notice}<p class="ok">{notice}</p>{/if}
{#if error}<p class="err">{error}</p>{/if}

<style>
	section {
		background: #2a2520;
		border-radius: 10px;
		padding: 1rem;
		margin-bottom: 1rem;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	h2 {
		font-size: 1rem;
		margin: 0;
	}
	.child {
		background: #1b1815;
		border-radius: 8px;
		padding: 12px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.nick {
		font-size: 1.1rem;
	}
	.muted {
		color: #a89a8a;
	}
	.small {
		font-size: 0.85rem;
		margin: 0;
	}
	.time {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 0.9rem;
	}
	progress {
		width: 100%;
		accent-color: #f5a623;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-weight: 600;
	}
	.limit {
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
	}
	.consent {
		flex-direction: row;
		align-items: flex-start;
		gap: 10px;
		font-weight: 400;
		font-size: 0.9rem;
	}
	.consent input {
		margin-top: 3px;
		width: 20px;
		height: 20px;
		flex: none;
	}
	.row {
		display: flex;
		gap: 8px;
		flex-wrap: wrap;
	}
	button,
	input,
	select {
		padding: 0.6rem;
		border-radius: 6px;
		border: 1px solid #4a4038;
		background: #1b1815;
		color: inherit;
		font-size: 1rem;
	}
	button {
		cursor: pointer;
	}
	button.primary {
		background: #f5a623;
		color: #1b1815;
		border: none;
		font-weight: 700;
	}
	button.danger {
		color: #ff8a8a;
	}
	button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.games {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 0.9rem;
		color: #a89a8a;
	}
	.res.won {
		color: #6fcf6f;
	}
	.res.lost {
		color: #ff9b6b;
	}
	.ok {
		color: #6fcf6f;
	}
	.err {
		color: #ff6b6b;
	}
</style>
