import 'package:flutter/material.dart';

import '../board.dart';
import '../game_controller.dart' show startFen;
import '../prefs.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _boardTile(BuildContext context, Prefs p, BoardColors b) {
    final selected = p.boardId == b.id;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: b.name,
      child: GestureDetector(
        onTap: () => p.set(board: b.id),
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
                ),
                child: BoardSwatch(b),
              ),
              const SizedBox(height: 4),
              Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Prefs.instance;
    final groups = <String>[];
    for (final b in boardThemes) {
      if (!groups.contains(b.group)) groups.add(b.group);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BoardView(
              fen: startFen,
              perspective: 'white',
              lastFrom: 'e2',
              lastTo: 'e4',
              selected: 'g1',
              targets: const {'f3', 'h3'},
              onTap: (_) {},
            ),
            for (final g in groups) ...[
              _heading(context, g == 'Colours' ? 'Board style · Colours' : g),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final b in boardThemes)
                    if (b.group == g) _boardTile(context, p, b),
                ],
              ),
            ],
            _heading(context, 'Pieces'),
            Wrap(
              spacing: 8,
              children: [
                for (final s in pieceStyles)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: s.black,
                      child: CircleAvatar(radius: 5, backgroundColor: s.white),
                    ),
                    label: Text(s.name),
                    selected: p.piecesId == s.id,
                    onSelected: (_) => p.set(pieces: s.id),
                  ),
              ],
            ),
            _heading(context, 'Display'),
            SwitchListTile(
              title: const Text('Framed board'),
              subtitle: const Text('Coordinates around the outside'),
              value: p.frame,
              onChanged: (v) => p.set(frame: v),
            ),
            SwitchListTile(
              title: const Text('Show dots where a piece can move'),
              value: p.hints,
              onChanged: (v) => p.set(hints: v),
            ),
            SwitchListTile(
              title: const Text('Highlight the last move'),
              value: p.lastMove,
              onChanged: (v) => p.set(lastMove: v),
            ),
            SwitchListTile(
              title: const Text('Show coordinates'),
              value: p.coords,
              onChanged: (v) => p.set(coords: v),
            ),
            _heading(context, 'Feedback'),
            SwitchListTile(title: const Text('Move sounds'), value: p.sound, onChanged: (v) => p.set(sound: v)),
            SwitchListTile(title: const Text('Vibrate on moves'), value: p.haptics, onChanged: (v) => p.set(haptics: v)),
          ],
        ),
      ),
    );
  }
}
