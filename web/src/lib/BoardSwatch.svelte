<script lang="ts">
	import { TEXTURES } from './textures';

	let { light, dark, surface }: { light: string; dark: string; surface: string } = $props();
</script>

<!-- A 4x4 preview of a board style. The 8x8 viewBox keeps the texture the same scale as the real board. -->
<svg viewBox="0 0 8 8" class="swatch-board" aria-hidden="true">
	{#each Array(16) as _, i}
		<rect x={(i % 4) * 2} y={Math.floor(i / 4) * 2} width="2" height="2" fill={(i + Math.floor(i / 4)) % 2 === 0 ? light : dark} />
	{/each}
	{#each TEXTURES[surface] ?? [] as t}
		<rect x="0" y="0" width="8" height="8" filter="url(#{t.filter})" opacity={t.opacity} />
	{/each}
</svg>

<style>
	.swatch-board {
		display: block;
		width: 100%;
		aspect-ratio: 1;
		border-radius: 6px;
	}
</style>
