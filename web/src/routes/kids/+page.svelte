<script lang="ts">
	import { onMount } from 'svelte';
	import KidLobby from '../../lib/kids/KidLobby.svelte';
	import ParentPortal from '../../lib/kids/ParentPortal.svelte';
	import { session } from '../../lib/session.svelte';

	onMount(() => session.refresh());
</script>

<svelte:head><title>Chess for kids · Chess Yetu</title></svelte:head>

<main>
	<header>
		<div>
			<h1>Chess for kids</h1>
			<p class="tag">Learn, play and grow. Safe by design.</p>
		</div>
		{#if session.kind !== 'kid'}<a class="back" href="/">← Main</a>{/if}
	</header>

	{#if !session.ready}
		<p class="muted">Loading…</p>
	{:else if session.kind === 'kid'}
		<KidLobby />
	{:else if session.kind === 'adult'}
		<p class="lead">
			You are signed in as <b>{session.user?.username}</b>. Create a profile for your child, then hand over the device.
		</p>
		<ParentPortal />
	{:else}
		<section class="intro">
			<h2>For parents and schools</h2>
			<ul>
				<li>You create the profile, so you stay in control. Children get a generated nickname, never a real name.</li>
				<li>Kids only play other kids and friendly computers. No chat except preset messages like “Good game!”.</li>
				<li>Set a daily time limit. See every game. Delete everything any time.</li>
			</ul>
			<a class="cta" href="/login">Sign in or create a parent account</a>
		</section>
	{/if}
</main>

<style>
	main {
		max-width: 460px;
		margin: 0 auto;
		padding: 2rem 16px;
	}
	header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 12px;
	}
	h1 {
		font-size: 2rem;
		margin: 0;
	}
	.tag {
		color: var(--muted);
		margin: 0.25rem 0 1.5rem;
	}
	.back {
		color: var(--accent-text);
		text-decoration: none;
	}
	.lead,
	.muted {
		color: var(--muted);
	}
	.intro {
		background: var(--card);
		border-radius: 12px;
		padding: 1rem;
	}
	.intro h2 {
		margin: 0 0 0.5rem;
		font-size: 1.1rem;
	}
	.intro ul {
		padding-left: 1.2rem;
		display: flex;
		flex-direction: column;
		gap: 8px;
		color: var(--muted-2);
	}
	.cta {
		display: block;
		text-align: center;
		background: var(--accent);
		color: var(--on-accent);
		font-weight: 700;
		padding: 0.8rem;
		border-radius: 8px;
		text-decoration: none;
	}
</style>
