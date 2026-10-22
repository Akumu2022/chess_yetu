import 'package:flutter/material.dart';

import '../api.dart';

class LeaderboardScreen extends StatelessWidget {
  final Api api;
  const LeaderboardScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leaderboard')),
        body: FutureBuilder<List<dynamic>>(
          future: api.leaderboard(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final players = snap.data!;
            if (players.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No ranked players yet. Play 5 rated games to appear here.')));
            }
            final me = api.user?.username;
            return ListView.builder(
              itemCount: players.length,
              itemBuilder: (_, i) {
                final p = players[i];
                final mine = p['username'] == me;
                return ListTile(
                  tileColor: mine ? Theme.of(context).colorScheme.primaryContainer : null,
                  leading: SizedBox(width: 32, child: Text('${p['rank']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  title: Text(p['username']),
                  subtitle: Text('${p['games']} games'),
                  trailing: Text('${p['rating']}', style: Theme.of(context).textTheme.titleMedium),
                );
              },
            );
          },
        ),
      );
}
