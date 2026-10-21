import { getToken, setToken, whoami, type Child, type User } from './api';

/** Who is signed in on this tab: nobody (guest), an adult, or a child's session. */
class Session {
	kind = $state<'guest' | 'adult' | 'kid'>('guest');
	user = $state<User | null>(null);
	child = $state<Child | null>(null);
	ready = $state(false);

	async load() {
		if (!this.ready) await this.refresh();
	}

	/** Re-read who we are, e.g. to pick up a rating changed by a finished game. */
	async refresh() {
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
	}

	/** Hand this tab to a child. Leaving again takes the parent's PIN. */
	startKid(token: string, child: Child) {
		setToken(token);
		this.kind = 'kid';
		this.child = child;
		this.user = null;
	}

	signOut() {
		setToken(null);
		this.clear();
	}
}

export const session = new Session();
