<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { createTournament, listTournaments, type TournamentInfo } from '../../lib/api';
	import { session } from '../../lib/session.svelte';

	let items = $state<TournamentInfo[]>([]);
	let loaded = $state(false);
	let error = $state('');
	let busy = $state(false);

	let name = $state('');
	let minutes = $state(3);
	let increment = $state(0);
	let startsIn = $state(5);
	let duration = $state(30);

	onMount(async () => {
		await session.refresh();
		if (session.kind === 'kid') return goto('/kids');
		try {
			items = await listTournaments();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not load tournaments';
		}
		loaded = true;
	});

	async function create() {
		busy = true;
		error = '';
		try {
			const t = await createTournament({
				name,
				minutes,
				increment,
				starts_in_min: startsIn,
				duration_min: duration
			});
			await goto(`/tournaments/${t.id}`);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not create the tournament';
		} finally {
			busy = false;
		}
	}

	const when = (iso: string) => new Date(iso).toLocaleString([], { weekday: 'short', hour: '2-digit', minute: '2-digit' });
	const LABEL = { upcoming: 'Starts', running: 'Live now', finishing: 'Wrapping up', finished: 'Finished' };
</script>

<svelte:head><title>Tournaments · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/">← Lobby</a>
	<h1>Tournaments</h1>
	<p class="sub">Play as many games as you can in the time window. Win 2 points, draw 1.</p>

	{#if loaded && items.length === 0}<p class="muted">No tournaments yet. Create the first one below.</p>{/if}
	<ul class="list">
		{#each items as t (t.id)}
			<li data-status={t.status}>
				<a href="/tournaments/{t.id}">
					<b>{t.name}</b>
					<span class="meta">{t.minutes}+{t.increment} · {t.duration_min} min · {t.players} players</span>
					<span class="state {t.status}">{LABEL[t.status]}{t.status === 'upcoming' ? ' ' + when(t.starts_at) : ''}{t.joined ? ' · joined' : ''}</span>
				</a>
			</li>
		{/each}
	</ul>

	<section>
		<h2>Create a tournament</h2>
		{#if session.kind === 'adult'}
			<label>Name <input bind:value={name} maxlength="60" placeholder="Friday night blitz" /></label>
			<div class="row">
				<label>Minutes per side <input type="number" min="1" max="30" bind:value={minutes} /></label>
				<label>Increment (s) <input type="number" min="0" max="30" bind:value={increment} /></label>
			</div>
			<div class="row">
				<label>Starts in (min) <input type="number" min="0" max="10080" bind:value={startsIn} /></label>
				<label>Lasts (min) <input type="number" min="10" max="180" bind:value={duration} /></label>
			</div>
			<button class="primary" disabled={busy || name.trim().length < 3} onclick={create}>Create</button>
		{:else}
			<p class="muted"><a href="/login">Sign in</a> to create or join a tournament.</p>
		{/if}
	</section>
	{#if error}<p class="err">{error}</p>{/if}
</main>

<style>
	main {
		max-width: 460px;
		margin: 0 auto;
		padding: 1rem 16px 3rem;
	}
	.back {
		color: var(--muted);
		text-decoration: none;
	}
	h1 {
		margin: 0.4rem 0 0;
	}
	.sub,
	.muted {
		color: var(--muted);
	}
	.list {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.list a {
		display: flex;
		flex-direction: column;
		gap: 2px;
		background: var(--card);
		border-radius: 10px;
		padding: 0.8rem 1rem;
		color: inherit;
		text-decoration: none;
	}
	.meta {
		color: var(--muted);
		font-size: 0.9rem;
	}
	.state {
		font-size: 0.85rem;
		color: var(--muted-2);
	}
	.state.running {
		color: var(--good);
		font-weight: 700;
	}
	section {
		background: var(--card);
		border-radius: 10px;
		padding: 1rem;
		margin-top: 1rem;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	h2 {
		margin: 0;
		font-size: 1rem;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 0.9rem;
		flex: 1;
	}
	.row {
		display: flex;
		gap: 10px;
	}
	input {
		padding: 0.6rem;
		border-radius: 6px;
		border: 1px solid var(--border);
		background: var(--inset);
		color: inherit;
		font-size: 1rem;
		min-width: 0;
	}
	button.primary {
		background: var(--accent);
		color: var(--on-accent);
		border: none;
		border-radius: 8px;
		padding: 0.8rem;
		font-weight: 700;
		font-size: 1rem;
		cursor: pointer;
	}
	button:disabled {
		opacity: 0.5;
	}
	.err {
		color: var(--bad);
	}
</style>
