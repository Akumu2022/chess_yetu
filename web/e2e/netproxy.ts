import net from 'node:net';

export interface LagProxy {
	/** Cut every open connection, like a phone losing signal. New connections still work. */
	killAll(): void;
	close(): Promise<void>;
}

/**
 * A TCP proxy that delays every chunk in each direction, so `delayMs: 250`
 * gives about 500 ms round trip. Order is preserved because the delay is constant.
 */
export function startLagProxy(listenPort: number, targetPort: number, delayMs: number): Promise<LagProxy> {
	const sockets = new Set<net.Socket>();
	const server = net.createServer((client) => {
		const upstream = net.connect(targetPort, '127.0.0.1');
		sockets.add(client).add(upstream);

		const pipe = (from: net.Socket, to: net.Socket) => {
			from.on('data', (chunk) =>
				setTimeout(() => {
					if (!to.destroyed) to.write(chunk);
				}, delayMs)
			);
			from.on('close', () => setTimeout(() => to.destroy(), delayMs));
			from.on('error', () => to.destroy());
		};
		pipe(client, upstream);
		pipe(upstream, client);
		for (const s of [client, upstream]) s.on('close', () => sockets.delete(s));
	});

	return new Promise((resolve) =>
		server.listen(listenPort, '127.0.0.1', () =>
			resolve({
				killAll: () => sockets.forEach((s) => s.destroy()),
				close: () =>
					new Promise<void>((done) => {
						sockets.forEach((s) => s.destroy());
						server.close(() => done());
					})
			})
		)
	);
}
