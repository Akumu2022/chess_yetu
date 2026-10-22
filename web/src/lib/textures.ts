/** Which SVG filters (see TextureDefs.svelte) to lay over a board's squares, and how strongly. */
export const TEXTURES: Record<string, { filter: string; opacity: number }[]> = {
	solid: [],
	wood: [{ filter: 'tex-wood', opacity: 0.55 }],
	marble: [
		{ filter: 'tex-cloud', opacity: 0.35 },
		{ filter: 'tex-marble', opacity: 0.4 }
	]
};
