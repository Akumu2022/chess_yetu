<script lang="ts">
	import { onMount } from 'svelte';
	import '../lib/prefs.svelte'; // applies the saved display choices as soon as the app starts

	let { children } = $props();

	// Lets end-to-end tests wait until click handlers are attached.
	onMount(() => {
		document.body.dataset.hydrated = 'true';
	});
</script>

{@render children()}

<style global>
	/* The app starts in light mode; dark is a choice on the Settings page. */
	:global(:root),
	:global(:root[data-theme='light']) {
		color-scheme: light;
		--bg: #f6f1e9;
		--card: #ffffff;
		--card-2: #efe7da;
		--inset: #f4eee4;
		--text: #2a2118;
		--text-2: #3b3027;
		--muted: #6f6254;
		--muted-2: #54483c;
		--border: #d6cab8;
		--border-strong: #b39c7c;
		--line: #e7ddcd;
		--accent: #f5a623;
		--accent-hover: #ffb940;
		--accent-text: #a45f00;
		--accent-strong: #7a4800;
		--accent-bg: #fdecc9;
		--accent-bg-2: #fbe0aa;
		--accent-line: #e3b25f;
		--on-accent: #1b1815;
		--good: #1e7e34;
		--bad: #c62828;
		--bad-bg: #fbe3e3;
		--warn: #b3541e;
		--meh: #8a6d00;
		--shadow: 0 2px 10px rgba(60, 40, 10, 0.1);
	}
	:global(:root[data-theme='dark']) {
		color-scheme: dark;
		--bg: #1b1815;
		--card: #2a2520;
		--card-2: #3a322b;
		--inset: #1b1815;
		--text: #f3ece4;
		--text-2: #f0e6d8;
		--muted: #a89a8a;
		--muted-2: #cdbfae;
		--border: #4a4038;
		--border-strong: #6b5a44;
		--line: #38302a;
		--accent: #f5a623;
		--accent-hover: #ffb940;
		--accent-text: #f5a623;
		--accent-strong: #ffd48a;
		--accent-bg: #3a2e1a;
		--accent-bg-2: #4a3818;
		--accent-line: #5a4524;
		--on-accent: #1b1815;
		--good: #6fcf6f;
		--bad: #ff6b6b;
		--bad-bg: #3a2222;
		--warn: #ff9b6b;
		--meh: #e6c84f;
		--shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
	}

	/* Board colours (squares) */
	:global(:root),
	:global(:root[data-board='classic']) {
		--sq-light: #f0d9b5;
		--sq-dark: #b58863;
	}
	:global(:root[data-board='green']) {
		--sq-light: #eeeed2;
		--sq-dark: #769656;
	}
	:global(:root[data-board='ocean']) {
		--sq-light: #dee3e6;
		--sq-dark: #8ca2ad;
	}
	:global(:root[data-board='violet']) {
		--sq-light: #efe6f5;
		--sq-dark: #8877b7;
	}
	:global(:root[data-board='slate']) {
		--sq-light: #e3e3e3;
		--sq-dark: #7d8796;
	}
	:global(:root[data-board='savanna']) {
		--sq-light: #f6e7b8;
		--sq-dark: #c47a2c;
	}

	/* Piece colours */
	:global(:root),
	:global(:root[data-pieces='classic']) {
		--pc-w: #ffffff;
		--pc-w-line: #222222;
		--pc-b: #1c1c1c;
		--pc-b-line: #000000;
	}
	:global(:root[data-pieces='ivory']) {
		--pc-w: #fff6d8;
		--pc-w-line: #4a3320;
		--pc-b: #3b2416;
		--pc-b-line: #1a0f08;
	}
	:global(:root[data-pieces='gold']) {
		--pc-w: #f5c542;
		--pc-w-line: #5a4200;
		--pc-b: #1d2d5c;
		--pc-b-line: #0a1230;
	}
	:global(:root[data-pieces='contrast']) {
		--pc-w: #ffffff;
		--pc-w-line: #000000;
		--pc-b: #000000;
		--pc-b-line: #ffffff;
	}

	:global(body) {
		margin: 0;
		background: var(--bg);
		color: var(--text);
		font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
	}
	/* One look for every "go back" link, with a thumb-sized tap area. */
	:global(a.back) {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		padding: 0 12px 0 0;
		color: var(--muted-2);
		text-decoration: none;
		font-size: 0.95rem;
	}
	:global(a.back:hover) {
		color: var(--accent-text);
	}
</style>
