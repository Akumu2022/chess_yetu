<script lang="ts">
	import { goto } from '$app/navigation';
	import { login, register } from '../../lib/api';
	import { session } from '../../lib/session.svelte';

	let mode = $state<'login' | 'register'>('login');
	let username = $state('');
	let password = $state('');
	let error = $state('');
	let busy = $state(false);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = '';
		try {
			const fn = mode === 'login' ? login : register;
			const { token, user } = await fn(username.trim(), password);
			session.signIn(token, user);
			await goto('/');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Something went wrong';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head><title>{mode === 'login' ? 'Sign in' : 'Create account'} · Chess Yetu</title></svelte:head>

<main>
	<a class="back" href="/">← Back</a>
	<h1>{mode === 'login' ? 'Sign in' : 'Create account'}</h1>
	<p class="hint">Rated games and your rating need an account. Guests can still play friends.</p>

	<form onsubmit={submit}>
		<label>
			Username
			<input bind:value={username} autocomplete="username" required minlength="3" maxlength="24" />
		</label>
		<label>
			Password
			<input
				type="password"
				bind:value={password}
				autocomplete={mode === 'login' ? 'current-password' : 'new-password'}
				required
				minlength="8"
			/>
		</label>
		{#if mode === 'register'}<small>Username: 3–24 letters, digits or underscores. Password: 8+ characters.</small>{/if}
		{#if error}<p class="err">{error}</p>{/if}
		<button class="primary" disabled={busy}>{mode === 'login' ? 'Sign in' : 'Create account'}</button>
	</form>

	<p class="switch">
		{#if mode === 'login'}
			New here? <button class="link" onclick={() => ((mode = 'register'), (error = ''))}>Create an account</button>
		{:else}
			Have an account? <button class="link" onclick={() => ((mode = 'login'), (error = ''))}>Sign in</button>
		{/if}
	</p>
</main>

<style>
	main {
		max-width: 420px;
		margin: 0 auto;
		padding: 2rem 16px;
	}
	.back {
		color: #f5a623;
		text-decoration: none;
	}
	h1 {
		margin: 1rem 0 0.25rem;
	}
	.hint {
		color: #a89a8a;
		margin: 0 0 1.5rem;
	}
	form {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-weight: 600;
	}
	input {
		padding: 0.7rem;
		border-radius: 6px;
		border: 1px solid #4a4038;
		background: #1b1815;
		color: inherit;
		font-size: 1rem;
	}
	small {
		color: #a89a8a;
	}
	.primary {
		padding: 0.7rem;
		border: none;
		border-radius: 6px;
		background: #f5a623;
		color: #1b1815;
		font-weight: 700;
		font-size: 1rem;
		cursor: pointer;
	}
	.primary:disabled {
		opacity: 0.5;
	}
	.err {
		color: #ff6b6b;
		margin: 0;
	}
	.switch {
		margin-top: 1.5rem;
		color: #a89a8a;
	}
	.link {
		background: none;
		border: none;
		color: #f5a623;
		cursor: pointer;
		font-size: inherit;
		padding: 0;
	}
</style>
