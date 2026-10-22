<script lang="ts">
	import { onMount } from 'svelte';

	type Outcome = 'win' | 'loss' | 'draw';
	type Person = { name: string; rating: number | null } | undefined;

	let {
		outcome,
		headline,
		detail,
		sentence,
		score,
		you,
		opponent,
		delta = null,
		ratingNow = null,
		kids = false,
		casual = false,
		reviewHref = null,
		onRematch = null,
		newHref,
		newLabel,
		onclose
	}: {
		outcome: Outcome;
		/** "You won!" */
		headline: string;
		/** "by checkmate" */
		detail: string;
		/** The whole result in one sentence, announced to screen readers. */
		sentence: string;
		/** "1-0", "0-1" or "1/2-1/2" */
		score: string;
		you: Person;
		opponent: Person;
		/** Rating change for rated games, null when the game was casual. */
		delta?: number | null;
		ratingNow?: number | null;
		kids?: boolean;
		/** An unrated game: say so instead of showing a rating change. */
		casual?: boolean;
		reviewHref?: string | null;
		onRematch?: (() => void) | null;
		newHref: string;
		newLabel: string;
		onclose: () => void;
	} = $props();

	let reviewEl = $state<HTMLElement | null>(null);
	let newEl = $state<HTMLElement | null>(null);
	// keyboard and screen-reader users land on the main action
	onMount(() => (reviewEl ?? newEl)?.focus());

	const ICON: Record<Outcome, string> = { win: '🏆', loss: '😕', draw: '🤝' };
	const initial = (p: Person) => (p?.name ?? '?').trim().charAt(0).toUpperCase() || '?';
</script>

<svelte:window onkeydown={(e) => e.key === 'Escape' && onclose()} />

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="scrim" onclick={(e) => e.target === e.currentTarget && onclose()}>
	<div class="card {outcome}" role="dialog" aria-modal="true" aria-labelledby="result-title" data-result={outcome}>
		<header>
			<button class="x" onclick={onclose} aria-label="Close result">✕</button>
			<div class="icon" aria-hidden="true">{ICON[outcome]}</div>
			<h2 id="result-title">{headline}</h2>
			{#if detail}<p class="detail">{detail}</p>{/if}
			{#if sentence !== headline}<p class="sr" role="status">{sentence}</p>{/if}
		</header>

		<div class="players">
			<div class="p">
				<span class="av you" aria-hidden="true">{initial(you)}</span>
				<b>{you?.name ?? 'You'}</b>
				{#if you?.rating}<small>{you.rating}</small>{/if}
			</div>
			<div class="score">{score}</div>
			<div class="p">
				<span class="av" aria-hidden="true">{initial(opponent)}</span>
				<b>{opponent?.name ?? 'Opponent'}</b>
				{#if opponent?.rating}<small>{opponent.rating}</small>{/if}
			</div>
		</div>

		{#if delta !== null && !kids}
			<div class="rating">
				{#if ratingNow !== null}<span class="now">{ratingNow}</span>{/if}
				<span class="delta" class:up={delta >= 0}>Rating {delta >= 0 ? '+' : ''}{delta.toFixed(1)}</span>
			</div>
		{:else if casual && !kids}
			<div class="rating"><span class="casual">Casual game · not rated</span></div>
		{:else if kids && delta !== null && delta > 0}
			<div class="rating"><span class="delta up">Level +{delta.toFixed(0)} ⭐</span></div>
		{/if}

		<div class="actions">
			{#if reviewHref}
				<a class="review" href={reviewHref} bind:this={reviewEl}>Review game</a>
			{/if}
			<div class="row">
				{#if onRematch}<button class="alt" onclick={onRematch}>Rematch</button>{/if}
				<a class="alt" href={newHref} bind:this={newEl}>{newLabel}</a>
			</div>
		</div>
	</div>
</div>

<style>
	.scrim {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		padding: 16px;
		background: rgb(0 0 0 / 0.55);
		animation: fade 0.2s ease-out;
	}
	.card {
		width: min(100%, 400px);
		background: var(--card, #fff);
		color: var(--text, inherit);
		border-radius: 16px;
		overflow: hidden;
		box-shadow: 0 12px 40px rgb(0 0 0 / 0.35);
		animation: rise 0.28s cubic-bezier(0.2, 1.2, 0.4, 1);
	}
	header {
		position: relative;
		padding: 18px 16px 18px;
		text-align: center;
		color: #fff;
		background: #6b7280;
	}
	.win header {
		background: #5e8f32;
	}
	.loss header {
		background: #b23a3a;
	}
	.x {
		position: absolute;
		top: 6px;
		right: 6px;
		flex: none;
		width: 36px;
		height: 36px;
		padding: 0;
		border: 0;
		border-radius: 50%;
		background: transparent;
		color: #fff;
		font-size: 1.1rem;
		cursor: pointer;
	}
	.x:hover {
		background: rgb(255 255 255 / 0.18);
	}
	.icon {
		font-size: 3rem;
		line-height: 1.1;
		animation: pop 0.5s cubic-bezier(0.2, 1.6, 0.4, 1);
	}
	h2 {
		margin: 4px 0 0;
		font-size: 1.9rem;
		font-weight: 800;
	}
	.detail {
		margin: 2px 0 0;
		opacity: 0.85;
	}
	.sr {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
	.players {
		display: grid;
		grid-template-columns: 1fr auto 1fr;
		align-items: start;
		gap: 8px;
		padding: 16px 16px 4px;
	}
	.p {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		min-width: 0;
		text-align: center;
	}
	.p b {
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.p small {
		color: var(--muted, #666);
	}
	.av {
		display: grid;
		place-items: center;
		width: 52px;
		height: 52px;
		border-radius: 50%;
		background: #e5e7eb;
		color: #1f2937;
		font-size: 1.4rem;
		font-weight: 700;
	}
	.av.you {
		background: var(--accent, #8b5e3c);
		color: var(--on-accent, #fff);
	}
	.score {
		padding-top: 14px;
		font-size: 1.3rem;
		font-weight: 800;
	}
	.rating {
		display: flex;
		align-items: baseline;
		justify-content: center;
		gap: 10px;
		padding: 8px 16px 0;
	}
	.now {
		font-size: 1.9rem;
		font-weight: 800;
	}
	.casual {
		color: var(--muted, #666);
	}
	.delta {
		font-weight: 700;
		color: #b23a3a;
	}
	.delta.up {
		color: #5e8f32;
	}
	.actions {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 16px;
	}
	.row {
		display: flex;
		gap: 10px;
	}
	.review,
	.alt {
		flex: 1;
		display: block;
		padding: 0.75rem 1rem;
		border: 0;
		border-radius: 999px;
		text-align: center;
		text-decoration: none;
		font: inherit;
		font-weight: 700;
		cursor: pointer;
	}
	.review {
		padding: 0.9rem 1rem;
		font-size: 1.1rem;
		background: #5e8f32;
		color: #fff;
	}
	.alt {
		background: var(--card-2, #eee);
		color: var(--accent-text, inherit);
	}
	.review:focus-visible,
	.alt:focus-visible,
	.x:focus-visible {
		outline: 3px solid var(--accent, #8b5e3c);
		outline-offset: 2px;
	}
	@keyframes fade {
		from {
			opacity: 0;
		}
	}
	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(24px) scale(0.96);
		}
	}
	@keyframes pop {
		from {
			transform: scale(0.3);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.scrim,
		.card,
		.icon {
			animation: none;
		}
	}
</style>
