<script lang="ts">
	/** Pieces one player has taken, with their material lead if they are ahead. */
	let {
		pieces,
		takenColor,
		by,
		lead = 0
	}: {
		pieces: string[];
		/** Colour of the pieces that were taken: 'w' or 'b'. */
		takenColor: 'w' | 'b';
		by: 'white' | 'black';
		lead?: number;
	} = $props();

	// The U+FE0E suffix forces text (not emoji) style; U+265F is an emoji on some systems.
	const GLYPH: Record<string, string> = { q: '♛', r: '♜', b: '♝', n: '♞', p: '♟︎' };
	const NAME: Record<string, string> = { q: 'queen', r: 'rook', b: 'bishop', n: 'knight', p: 'pawn' };
</script>

<span class="captured" class:has={pieces.length > 0} data-by={by} aria-label="Pieces taken by {by}">
	{#each pieces as p, i (i)}
		<span class="p {takenColor}" data-piece={takenColor + p} title={NAME[p]}>{GLYPH[p]}</span>
	{/each}
	{#if lead > 0}<span class="lead">+{lead}</span>{/if}
</span>

<style>
	.captured {
		display: inline-flex;
		align-items: center;
		min-height: 1.6rem;
		font-size: 1.15rem;
		line-height: 1;
		align-self: flex-start;
		padding: 0 8px;
		border-radius: 12px;
	}
	/* Light chip so black pieces stay visible on the dark page. */
	.captured.has {
		background: #d9cdbd;
	}
	.p {
		margin-right: -0.15em; /* overlap like a stack of taken pieces */
		font-family: 'Segoe UI Symbol', 'Noto Sans Symbols 2', 'DejaVu Sans', serif;
	}
	.p.w {
		color: #fff;
		text-shadow: 0 0 2px #000, 0 0 1px #000, 0 0 1px #000;
	}
	.p.b {
		color: #1c1c1c;
	}
	.lead {
		margin-left: 0.7em;
		font-size: 0.85rem;
		font-weight: 700;
		color: #3a322b;
	}
</style>
