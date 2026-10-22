import 'package:flutter/material.dart';

import '../api.dart';
import 'review.dart';

class ProfileScreen extends StatelessWidget {
  final Api api;
  final String username;
  const ProfileScreen({super.key, required this.api, required this.username});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(username)),
        body: FutureBuilder<Map<String, dynamic>>(
          future: api.profile(username),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final p = snap.data!;
            final rec = p['record'];
            final recent = p['recent'] as List;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: Text('${p['rating']}', style: Theme.of(context).textTheme.displayMedium)),
              Center(
                child: Text(
                  p['rank'] == null ? 'Unranked (needs 5 rated games)' : 'Rank #${p['rank']}  ·  ${p['games']} games',
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                _stat(context, 'Won', rec['won']),
                _stat(context, 'Drawn', rec['drawn']),
                _stat(context, 'Lost', rec['lost']),
              ]),
              const SizedBox(height: 16),
              if (recent.isNotEmpty) Text('Recent rated games', style: Theme.of(context).textTheme.titleMedium),
              for (final g in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${_cap(g['outcome'])} vs ${g['opponent']}'),
                  subtitle: Text('${g['moves']} moves as ${g['color']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReviewScreen(api: api, gameId: g['id'])),
                  ),
                ),
            ]);
          },
        ),
      );

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _stat(BuildContext context, String label, int n) => Expanded(
        child: Column(children: [
          Text('$n', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
