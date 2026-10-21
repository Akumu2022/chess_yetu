<script lang="ts">
	import { onMount } from 'svelte';

	let { children } = $props();

	// Lets end-to-end tests wait until click handlers are attached.
	onMount(() => {
		document.body.dataset.hydrated = 'true';
	});
</script>

{@render children()}

<style global>
	:global(body) {
		margin: 0;
		background: #1b1815;
		color: #f3ece4;
		font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
	}
	/* One look for every "go back" link, with a thumb-sized tap area. */
	:global(a.back) {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		padding: 0 12px 0 0;
		color: #cdbfae;
		text-decoration: none;
		font-size: 0.95rem;
	}
	:global(a.back:hover) {
		color: #f5a623;
	}
</style>
