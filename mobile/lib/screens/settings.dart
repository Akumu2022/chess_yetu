import 'package:flutter/material.dart';

import '../board.dart';
import '../game_controller.dart' show startFen;
import '../prefs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Prefs.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          BoardView(
            fen: startFen,
            perspective: 'white',
            lastFrom: 'e2',
            lastTo: 'e4',
            selected: 'g1',
            targets: const {'f3', 'h3'},
            onTap: (_) {},
          ),
          const SizedBox(height: 16),
          Text('Board colours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in boardThemes)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: b.dark),
                label: Text(b.name),
                selected: p.boardId == b.id,
                onSelected: (_) => p.set(board: b.id),
              ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Show dots where a piece can move'),
            value: p.hints,
            onChanged: (v) => p.set(hints: v),
          ),
          SwitchListTile(title: const Text('Highlight the last move'), value: p.lastMove, onChanged: (v) => p.set(lastMove: v)),
          SwitchListTile(title: const Text('Show coordinates'), value: p.coords, onChanged: (v) => p.set(coords: v)),
          SwitchListTile(title: const Text('Move sounds'), value: p.sound, onChanged: (v) => p.set(sound: v)),
          SwitchListTile(title: const Text('Vibrate on moves'), value: p.haptics, onChanged: (v) => p.set(haptics: v)),
        ]),
      ),
    );
  }
}
