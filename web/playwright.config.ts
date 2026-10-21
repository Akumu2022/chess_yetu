import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { defineConfig } from '@playwright/test';

// Tests run against their own servers and a throwaway database,
// so they never touch the dev servers (5273 / 8765) or real data.
const API_PORT = 8766;
const WEB_PORT = 5174;
// A throwaway database FILE per run. (An in-memory SQLite shares one connection, so two
// simultaneous requests would collide and give flaky 500s that real deployments never see.)
const TEST_DB = `sqlite:///${resolve(tmpdir(), `chess_yetu_e2e_${Date.now()}.db`).replaceAll('\\', '/')}`;
// Forward slashes + quotes work in both cmd and bash shells.
const PYTHON = resolve('../backend/.venv/Scripts/python.exe').replaceAll('\\', '/');

export default defineConfig({
	testDir: 'e2e',
	timeout: 60_000,
	fullyParallel: false,
	workers: 1,
	reporter: [['list']],
	use: { baseURL: `http://localhost:${WEB_PORT}`, channel: 'chrome', trace: 'retain-on-failure' },
	webServer: [
		{
			command: `"${PYTHON}" -m uvicorn app.main:app --port ${API_PORT}`,
			cwd: '../backend',
			url: `http://localhost:${API_PORT}/health`,
			reuseExistingServer: false,
			env: {
				DATABASE_URL: TEST_DB,
				JWT_SECRET: 'e2e-secret-e2e-secret-e2e-secret-0123456789',
				CORS_ORIGINS: `http://localhost:${WEB_PORT}`
			}
		},
		{
			command: `npm run dev -- --port ${WEB_PORT} --strictPort`,
			url: `http://localhost:${WEB_PORT}`,
			reuseExistingServer: false,
			env: { VITE_API_PORT: String(API_PORT) }
		}
	]
});
