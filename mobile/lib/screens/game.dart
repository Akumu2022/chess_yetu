import 'package:flutter/material.dart';

import '../api.dart';
import '../board.dart';
import '../game_controller.dart';
import 'lobby.dart' show copyCode;

class GameScreen extends StatefulWidget {
  final Api api;
  final Seat seat;
  final String? shareCode;
  const GameScreen({super.key, required this.api, required this.seat, this.shareCode});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController g = GameController(widget.api, widget.seat);
  String? _selected;
  Map<String, bool> _targets = {};

  @override
  void dispose() {
    g.dispose();
    super.dispose();
  }

  Future<void> _tap(String sq) async {
    if (!g.myTurn) return;
    final from = _selected;
    if (from != null && _targets.containsKey(sq)) {
      String? promo;
      if (_targets[sq]!) {
        promo = await _askPromotion();
        if (promo == null) return;
      }
      setState(() {
        _selected = null;
        _targets = {};
      });
      g.playMove(from, sq, promo);
      return;
    }
    final t = g.legalFrom(sq);
    setState(() {
      _selected = t.isEmpty ? null : sq;
      _targets = t;
    });
  }

  Future<String?> _askPromotion() => showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(title: const Text('Promote to'), children: [
          for (final p in const {'q': 'Queen', 'r': 'Rook', 'b': 'Bishop', 'n': 'Knight'}.entries)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, p.key), child: Text(p.value)),
        ]),
      );

  Future<void> _confirm(String title, VoidCallback ok) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(title: Text(title), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
      ]),
    );
    if (yes == true) ok();
  }

  String _clock(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _bar(String color) {
    final p = g.players[color];
    final name = p == null ? 'Waiting…' : '${p['name']}${p['rating'] != null ? ' (${p['rating']})' : ''}';
    final active = g.status == 'active' && g.turn == color;
    final low = g.status == 'active' && g.clockMs(color) < 20000;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: active ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Row(children: [
        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        if (color != g.you && !g.opponentOnline)
          const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.wifi_off, size: 16)),
        Text(
          _clock(g.clockMs(color)),
          style: TextStyle(fontSize: 20, fontFeatures: const [FontFeature.tabularFigures()], color: low ? Colors.red : null),
        ),
      ]),
    );
  }

  String _resultText() {
    final why = (g.reason ?? '').replaceAll('_', ' ');
    if (g.result == '1/2-1/2') return 'Draw by $why';
    return (g.result == '1-0') == (g.you == 'white') ? 'You won by $why' : 'You lost by $why';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: g,
        builder: (context, _) {
          final opp = g.you == 'white' ? 'black' : 'white';
          final last = g.lastMove;
          final delta = g.ratingChange?[g.you];
          return Scaffold(
            appBar: AppBar(title: Text(g.vsBot ? 'Vs computer' : 'Game ${g.seat.gameId}')),
            body: SafeArea(
              child: SingleChildScrollView(
                child: Column(children: [
                  if (!g.connected && g.status != 'over')
                    Container(
                      width: double.infinity,
                      color: Colors.amber,
                      padding: const EdgeInsets.all(4),
                      child: Text(g.error ?? 'Connecting…', textAlign: TextAlign.center),
                    ),
                  _bar(opp),
                  BoardView(
                    fen: g.engine.fen,
                    perspective: g.you,
                    selected: _selected,
                    targets: _targets.keys.toSet(),
                    lastFrom: last?.substring(0, 2),
                    lastTo: last?.substring(2, 4),
                    onTap: _tap,
                  ),
                  _bar(g.you),
                  const SizedBox(height: 8),
                  if (g.status == 'waiting') ...[
                    const Text('Waiting for an opponent…'),
                    if (widget.shareCode != null)
                      TextButton.icon(
                        onPressed: () => copyCode(context, widget.shareCode!),
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text('Code: ${widget.shareCode}  (tap to copy)'),
                      ),
                  ],
                  if (g.status == 'active') ...[
                    Text(g.myTurn ? 'Your move' : "Opponent's move"),
                    if (g.drawOffer != null && g.drawOffer != g.you)
                      const Text('Your opponent offers a draw. Press "Offer draw" to accept.'),
                    if (g.drawDeclined) const Text('The computer declined the draw.'),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      OutlinedButton(onPressed: () => _confirm('Offer a draw?', g.offerDraw), child: const Text('Offer draw')),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: () => _confirm('Resign this game?', g.resign), child: const Text('Resign')),
                    ]),
                  ],
                  if (g.status == 'over') ...[
                    Text(_resultText(), style: Theme.of(context).textTheme.titleMedium),
                    if (delta != null) Text('Rating ${delta >= 0 ? '+' : ''}$delta'),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to lobby')),
                  ],
                ]),
              ),
            ),
          );
        },
      );
}
