import { getToken, setToken, whoami, type Child, type User } from './api';

/** When a sign-in token runs out, in ms since 1970 (read from the token itself; the server is what enforces it). */
function tokenExpiry(token: string | null): number | null {
	try {
		const exp = JSON.parse(atob(token!.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp;
		return typeof exp === 'number' ? exp * 1000 : null;
	} catch {
		return null;
	}
}
const tokenExpired = (token: string | null) => {
	const exp = tokenExpiry(token);
	return exp !== null && exp <= Date.now();
};

/** Who is signed in on this tab: nobody (guest), an adult, or a child's session. */
class Session {
	kind = $state<'guest' | 'adult' | 'kid'>('guest');
	user = $state<User | null>(null);
	child = $state<Child | null>(null);
	ready = $state(false);
	/** Why the player was signed out, shown once on the lobby. */
	notice = $state('');
	private expiryTimer: ReturnType<typeof setTimeout> | null = null;

	async load() {
		if (!this.ready) await this.refresh();
	}

	/** Re-read who we are, e.g. to pick up a rating changed by a finished game. */
	async refresh() {
		if (tokenExpired(getToken())) this.expire();
		if (getToken()) {
			try {
				const who = await whoami();
				this.kind = who.kind;
				this.user = who.kind === 'adult' ? who.user : null;
				this.child = who.kind === 'kid' ? who.child : null;
			} catch {
				setToken(null); // expired or revoked
				this.clear();
			}
		} else {
			this.clear();
		}
		this.ready = true;
		this.watchExpiry();
	}

	/** Adult sign-ins last 30 days. Sign out when that time is up, even if the page is left open. */
	private watchExpiry() {
		if (this.expiryTimer) clearTimeout(this.expiryTimer);
		this.expiryTimer = null;
		const exp = this.kind === 'adult' ? tokenExpiry(getToken()) : null;
		if (!exp) return;
		this.expiryTimer = setTimeout(() => this.expire(), Math.min(Math.max(0, exp - Date.now()), 2 ** 31 - 1));
	}

	private expire() {
		setToken(null);
		this.clear();
		this.notice = 'Your sign-in expired. Please sign in again.';
	}

	private clear() {
		this.kind = 'guest';
		this.user = null;
		this.child = null;
	}

	signIn(token: string, user: User) {
		setToken(token);
		this.kind = 'adult';
		this.user = user;
		this.child = null;
		this.notice = '';
		this.watchExpiry();
	}

	/** Hand this tab to a child. Leaving again takes the parent's PIN. */
	startKid(token: string, child: Child) {
		setToken(token);
		this.kind = 'kid';
		this.child = child;
		this.user = null;
	}

	signOut() {
		if (this.expiryTimer) clearTimeout(this.expiryTimer);
		setToken(null);
		this.clear();
	}
}

export const session = new Session();
