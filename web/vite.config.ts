import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	// 5173 is often taken (Docker/WSL), and the backend's CORS list expects this port.
	server: { port: 5273, strictPort: true },
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// Node adapter: the production build runs as a plain Node server (see the Dockerfile).
			adapter: adapter()
		})
	]
});
