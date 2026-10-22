import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import '../api.dart';
import '../board.dart';

/// Daily mate puzzles. The server checks each move; we only mirror the position locally.
class PuzzleScreen extends StatefulWidget {
  final Api api;
  const PuzzleScreen({super.key, required this.api});
  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  Map<String, dynamic>? _puzzle, _state;
  ch.Chess? _engine;
  final List<String> _played = [];
  String? _selected, _lastFrom, _lastTo, _message, _error;
  Map<String, bool> _targets = {};
  bool _solved = false, _limit = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _solved = false;
      _selected = _lastFrom = _lastTo = null;
      _targets = {};
      _played.clear();
    });
    try {
      final r = await widget.api.nextPuzzle();
      _state = r;
      _limit = r['limit_reached'] == true;
      _puzzle = _limit ? null : Map<String, dynamic>.from(r['puzzle']);
      _engine = _puzzle == null ? null : ch.Chess.fromFEN(_puzzle!['fen']);
    } on ApiError catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _apply(String uci) {
    _engine!.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci.substring(4),
    });
    _lastFrom = uci.substring(0, 2);
    _lastTo = uci.substring(2, 4);
  }

  Future<String?> _askPromotion() => showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(title: const Text('Promote to'), children: [
          for (final p in const {'q': 'Queen', 'r': 'Rook', 'b': 'Bishop', 'n': 'Knight'}.entries)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, p.key), child: Text(p.value)),
        ]),
      );

  Future<void> _tap(String sq) async {
    if (_busy || _solved || _engine == null) return;
    final from = _selected;
    if (from != null && _targets.containsKey(sq)) {
      String? promo;
      if (_targets[sq]!) {
        promo = await _askPromotion();
        if (promo == null) return;
      }
      await _submit('$from$sq${promo ?? ''}');
      return;
    }
    final t = legalTargets(_engine!, sq);
    // only the side the puzzle is set for may be moved
    final mine = _puzzle!['to_move'] == 'white' ? _engine!.turn == ch.Color.WHITE : _engine!.turn == ch.Color.BLACK;
    setState(() {
      _selected = t.isEmpty || !mine ? null : sq;
      _targets = _selected == null ? {} : t;
    });
  }

  Future<void> _submit(String uci) async {
    final before = _engine!.fen;
    final lf = _lastFrom, lt = _lastTo;
    setState(() {
      _apply(uci);
      _played.add(uci);
      _selected = null;
      _targets = {};
      _busy = true;
      _message = null;
    });
    try {
      final r = await widget.api.puzzleMove(_puzzle!['id'], _played);
      setState(() {
        switch (r['status']) {
          case 'wrong':
            _engine = ch.Chess.fromFEN(before);
            _played.removeLast();
            _lastFrom = lf;
            _lastTo = lt;
            _message = 'Not quite. Try another move.';
          case 'continue':
            _apply(r['reply']);
            _message = 'Good. Keep going.';
          case 'solved':
            _solved = true;
            _state = r;
            _message = 'Checkmate! Puzzle solved.';
        }
      });
    } on ApiError catch (e) {
      setState(() => _message = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    final streak = st?['streak'];
    return Scaffold(
      appBar: AppBar(title: const Text('Puzzles')),
      body: SafeArea(
        child: ListView(children: [
          if (st != null && st['solved_today'] != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Solved today: ${st['solved_today']}/${st['limit']}'
                '${streak != null ? '   ·   Streak: ${streak['current']} (best ${streak['best']})' : ''}',
                textAlign: TextAlign.center,
              ),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_limit)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text("That's all the puzzles for today. Come back tomorrow!", textAlign: TextAlign.center),
            ),
          if (_puzzle != null && _engine != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_puzzle!['theme']}  ·  ${_puzzle!['to_move'] == 'white' ? 'White' : 'Black'} to move',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            BoardView(
              fen: _engine!.fen,
              perspective: _puzzle!['to_move'],
              selected: _selected,
              targets: _targets.keys.toSet(),
              lastFrom: _lastFrom,
              lastTo: _lastTo,
              onTap: _tap,
            ),
          ],
          if (_message != null) Padding(padding: const EdgeInsets.all(12), child: Text(_message!, textAlign: TextAlign.center)),
          if (_solved || _limit || _error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _limit
                    ? FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to lobby'))
                    : FilledButton(onPressed: _load, child: Text(_solved ? 'Next puzzle' : 'Try again')),
              ),
            ),
        ]),
      ),
    );
  }
}
