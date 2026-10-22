<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { fetchProfile, type Profile } from '../../../lib/api';

	let p = $state<Profile | null>(null);
	let error = $state('');

	onMount(async () => {
		try {
			p = await fetchProfile(page.params.username!);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not load this player';
		}
	});
</script>

<svelte:head><title>{p?.username ?? 'Player'} · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/leaderboard">← Leaderboard</a>
	{#if error}
		<p class="err">{error}</p>
	{:else if !p}
		<p>Loading…</p>
	{:else}
		<h1>{p.username}</h1>
		<div class="cards">
			<div><b>{p.rating}</b><span>rating</span></div>
			<div><b>{p.rank ? '#' + p.rank : '–'}</b><span>rank</span></div>
			<div><b>{p.games}</b><span>rated games</span></div>
		</div>
		<p class="record">
			<span class="w">{p.record.won} won</span> · <span>{p.record.drawn} drawn</span> ·
			<span class="l">{p.record.lost} lost</span>
		</p>
		<h2>Recent rated games</h2>
		{#if p.recent.length === 0}<p class="muted">No rated games yet.</p>{/if}
		<ul>
			{#each p.recent as g (g.id)}
				<li>
					<b class={g.outcome}>{g.outcome === 'win' ? 'Won' : g.outcome === 'loss' ? 'Lost' : 'Draw'}</b>
					<span>vs {g.opponent} · {g.moves} moves</span>
					<a href="/review/{g.id}">review</a>
				</li>
			{/each}
		</ul>
	{/if}
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
		margin: 0.4rem 0 0.8rem;
	}
	h2 {
		font-size: 1rem;
	}
	.cards {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 8px;
	}
	.cards div {
		background: var(--card);
		border-radius: 8px;
		padding: 0.7rem;
		display: flex;
		flex-direction: column;
		align-items: center;
	}
	.cards b {
		font-size: 1.4rem;
		color: var(--accent-text);
	}
	.cards span,
	.muted {
		color: var(--muted);
		font-size: 0.85rem;
	}
	.record {
		margin: 0.8rem 0;
	}
	.w,
	.win {
		color: var(--good);
	}
	.l,
	.loss {
		color: var(--bad);
	}
	ul {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	li {
		display: grid;
		grid-template-columns: 3.5rem 1fr auto;
		gap: 8px;
		font-size: 0.9rem;
	}
	.err {
		color: var(--bad);
	}
</style>
