<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchLeaderboard, type Ranked } from '../../lib/api';

	let players = $state<Ranked[]>([]);
	let minGames = $state(5);
	let loaded = $state(false);
	let error = $state('');

	onMount(async () => {
		try {
			const r = await fetchLeaderboard();
			players = r.players;
			minGames = r.min_games;
		} catch (e) {
			error = e instanceof Error ? e.message : 'Could not load the leaderboard';
		}
		loaded = true;
	});
</script>

<svelte:head><title>Leaderboard · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/">← Lobby</a>
	<h1>Leaderboard</h1>
	<p class="sub">Top rated players. You appear after {minGames} rated games.</p>
	{#if loaded && players.length === 0}<p class="muted">No ranked players yet. Play some rated games!</p>{/if}
	<ol>
		{#each players as p (p.username)}
			<li data-rank={p.rank}>
				<span class="rank">{p.rank}</span>
				<a href="/players/{p.username}">{p.username}</a>
				<span class="games">{p.games} games</span>
				<b class="rating">{p.rating}</b>
			</li>
		{/each}
	</ol>
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
	ol {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	li {
		display: grid;
		grid-template-columns: 2rem 1fr auto 3.5rem;
		gap: 8px;
		align-items: center;
		background: var(--card);
		border-radius: 8px;
		padding: 0.6rem 0.8rem;
	}
	li[data-rank='1'] {
		border-left: 4px solid var(--accent);
	}
	.rank {
		color: var(--muted);
	}
	.games {
		color: var(--muted);
		font-size: 0.8rem;
	}
	.rating {
		text-align: right;
		color: var(--accent-text);
	}
	a {
		color: inherit;
	}
	.err {
		color: var(--bad);
	}
</style>
