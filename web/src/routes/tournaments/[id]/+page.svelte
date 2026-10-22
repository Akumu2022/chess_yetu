<script lang="ts">
	import { goto } from '$app/navigation';
	import { onDestroy, onMount } from 'svelte';
	import { page } from '$app/state';
	import {
		ApiError,
		getTournament,
		joinTournament,
		leaveTournament,
		saveSeat,
		tournamentPoll,
		type TournamentDetail
	} from '../../../lib/api';
	import { session } from '../../../lib/session.svelte';

	const id = Number(page.params.id);
	let t = $state<TournamentDetail | null>(null);
	let error = $state('');
	let busy = $state(false);
	let now = $state(Date.now());
	let timers: ReturnType<typeof setInterval>[] = [];
	let leaving = false;

	onMount(async () => {
		await session.refresh();
		if (session.kind === 'kid') return goto('/kids');
		await load();
		timers.push(setInterval(() => (now = Date.now()), 1000));
		timers.push(setInterval(load, 4000));
		timers.push(setInterval(poll, 1500)); // heartbeat + pick up a pairing
		poll();
	});
	onDestroy(() => timers.forEach(clearInterval));

	async function load() {
		try {
			t = await getTournament(id);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not load this tournament';
		}
	}

	async function poll() {
		if (!t?.joined || leaving) return;
		try {
			const r = await tournamentPoll(id);
			if (r.status === 'matched') {
				leaving = true;
				saveSeat(r.seat);
				await goto(`/game/${r.seat.game_id}`);
			}
		} catch (e) {
			if (e instanceof ApiError && e.status === 401) error = 'Your session expired. Please sign in again.';
		}
	}

	async function toggle() {
		busy = true;
		error = '';
		try {
			if (t?.joined) await leaveTournament(id);
			else await joinTournament(id);
			await load();
			poll();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Something went wrong';
		} finally {
			busy = false;
		}
	}

	function countdown(ms: number) {
		const s = Math.max(0, Math.floor(ms / 1000));
		const h = Math.floor(s / 3600);
		const m = Math.floor((s % 3600) / 60);
		return `${h ? h + ':' : ''}${String(m).padStart(h ? 2 : 1, '0')}:${String(s % 60).padStart(2, '0')}`;
	}

	let toStart = $derived(t ? new Date(t.starts_at).getTime() - now : 0);
	let toEnd = $derived(t ? new Date(t.ends_at).getTime() - now : 0);
	let open = $derived(t && (t.status === 'upcoming' || t.status === 'running'));
</script>

<svelte:head><title>{t?.name ?? 'Tournament'} · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/tournaments">← Tournaments</a>
	{#if !t}
		{#if error}<p class="err">{error}</p>{:else}<p>Loading…</p>{/if}
	{:else}
		<h1>{t.name}</h1>
		<p class="sub">{t.minutes}+{t.increment} · {t.duration_min} min · by {t.creator} · {t.players} players</p>

		<div class="status" data-status={t.status}>
			{#if t.status === 'upcoming'}
				Starts in <b>{countdown(toStart)}</b>
			{:else if t.status === 'running'}
				Live · <b>{countdown(toEnd)}</b> left
			{:else if t.status === 'finishing'}
				Last games are finishing…
			{:else}
				Finished{t.winner ? ` · Winner: ${t.winner} 🏆` : ''}
			{/if}
		</div>

		{#if open}
			{#if session.kind === 'adult'}
				<button class="primary" disabled={busy} onclick={toggle}>{t.joined ? 'Withdraw' : 'Join'}</button>
				{#if t.joined && t.status === 'running'}
					<p class="wait" role="status">Waiting for an opponent… keep this page open.</p>
				{:else if t.joined}
					<p class="wait" role="status">You are in. Keep this page open when it starts.</p>
				{/if}
			{:else}
				<p class="muted"><a href="/login">Sign in</a> to join.</p>
			{/if}
		{/if}

		<h2>Standings</h2>
		{#if t.standings.length === 0}
			<p class="muted">Nobody has joined yet.</p>
		{:else}
			<table>
				<thead><tr><th>#</th><th>Player</th><th>Pts</th><th>Games</th><th>W-D-L</th></tr></thead>
				<tbody>
					{#each t.standings as r (r.username)}
						<tr class:me={r.username === session.user?.username} class:out={!r.active}>
							<td>{r.rank}</td>
							<td><a href="/players/{r.username}">{r.username}</a> <span class="muted">{r.rating}</span></td>
							<td class="pts">{r.points}</td>
							<td>{r.games}</td>
							<td>{r.wins}-{r.draws}-{r.losses}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		{/if}
	{/if}
	{#if error && t}<p class="err">{error}</p>{/if}
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
	h2 {
		font-size: 1rem;
		margin: 1.2rem 0 0.4rem;
	}
	.sub,
	.muted {
		color: var(--muted);
	}
	.status {
		background: var(--card);
		border-radius: 10px;
		padding: 0.8rem 1rem;
		margin: 0.6rem 0;
	}
	.status[data-status='running'] {
		border-left: 4px solid var(--good);
	}
	.wait {
		color: var(--accent-text);
	}
	button.primary {
		background: var(--accent);
		color: var(--on-accent);
		border: none;
		border-radius: 8px;
		padding: 0.8rem 1.2rem;
		font-weight: 700;
		font-size: 1rem;
		cursor: pointer;
		width: 100%;
	}
	button:disabled {
		opacity: 0.5;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.95rem;
	}
	th {
		text-align: left;
		color: var(--muted);
		font-weight: 400;
		padding: 4px;
	}
	td {
		padding: 6px 4px;
		border-top: 1px solid var(--card-2);
	}
	tr.me td {
		background: var(--accent-bg);
	}
	tr.out {
		opacity: 0.5;
	}
	.pts {
		font-weight: 700;
		color: var(--accent-text);
	}
	td a {
		color: inherit;
	}
	.err {
		color: var(--bad);
	}
</style>
