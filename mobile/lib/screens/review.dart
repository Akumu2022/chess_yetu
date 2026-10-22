import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import '../api.dart';
import '../board.dart';
import '../game_controller.dart' show startFen;

const _gradeColors = {
  'best': Color(0xFF2E7D32),
  'good': Color(0xFF689F38),
  'inaccuracy': Color(0xFFF9A825),
  'mistake': Color(0xFFEF6C00),
  'blunder': Color(0xFFC62828),
};

/// Steps through a finished game, with Stockfish grades once the game has been analysed.
class ReviewScreen extends StatefulWidget {
  final Api api;
  final String gameId;
  const ReviewScreen({super.key, required this.api, required this.gameId});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  Map<String, dynamic>? _review, _analysis;
  String? _error;
  bool _analysing = false;
  int _ply = 0; // number of moves played on the board
  late List<String> _moves;
  late List<String> _fens; // position after each ply, index 0 = start

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.review(widget.gameId);
      _moves = List<String>.from(r['moves']);
      final e = ch.Chess.fromFEN(startFen);
      _fens = [startFen];
      for (final uci in _moves) {
        e.move({
          'from': uci.substring(0, 2),
          'to': uci.substring(2, 4),
          if (uci.length > 4) 'promotion': uci.substring(4),
        });
        _fens.add(e.fen);
      }
      _review = r;
      _analysis = r['analysis'] == null ? null : Map<String, dynamic>.from(r['analysis']);
      _ply = _moves.length;
    } on ApiError catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() {});
  }

  Future<void> _analyse() async {
    setState(() {
      _analysing = true;
      _error = null;
    });
    try {
      // Stockfish can take a while on long games
      _analysis = await widget.api.analyze(widget.gameId);
    } on ApiError catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _analysing = false);
  }

  void _go(int ply) => setState(() => _ply = ply.clamp(0, _moves.length));

  Map<String, dynamic>? _graded(int ply) =>
      _analysis == null || ply < 1 ? null : Map<String, dynamic>.from(_analysis!['moves'][ply - 1]);

  String _label(int i) => '${i ~/ 2 + 1}${i.isEven ? '.' : '...'}';

  Widget _accuracy(String color) {
    final a = _analysis!['accuracy'][color];
    final c = Map<String, dynamic>.from(_analysis!['counts'][color]);
    return Expanded(
      child: Column(children: [
        Text(color == 'white' ? 'White' : 'Black', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(a == null ? '-' : '$a%', style: Theme.of(context).textTheme.titleLarge),
        Text('${c['inaccuracy']} inaccuracies · ${c['mistake']} mistakes · ${c['blunder']} blunders',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _review;
    return Scaffold(
      appBar: AppBar(title: const Text('Game review')),
      body: r == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : SafeArea(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${r['players']['white']} vs ${r['players']['black']}  ·  ${r['result']}  ·  ${(r['reason'] as String).replaceAll('_', ' ')}',
                      textAlign: TextAlign.center),
                ),
                BoardView(
                  fen: _fens[_ply],
                  perspective: 'white',
                  lastFrom: _ply > 0 ? _moves[_ply - 1].substring(0, 2) : null,
                  lastTo: _ply > 0 ? _moves[_ply - 1].substring(2, 4) : null,
                  onTap: (_) {},
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: () => _go(0), icon: const Icon(Icons.first_page)),
                  IconButton(onPressed: () => _go(_ply - 1), icon: const Icon(Icons.chevron_left)),
                  Text('$_ply / ${_moves.length}'),
                  IconButton(onPressed: () => _go(_ply + 1), icon: const Icon(Icons.chevron_right)),
                  IconButton(onPressed: () => _go(_moves.length), icon: const Icon(Icons.last_page)),
                ]),
                if (_graded(_ply) case final g?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${g['san']} is ${g['cls']}'
                      '${g['best_san'] != null ? '. Best was ${g['best_san']}.' : '.'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _gradeColors[g['cls']], fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center)),
                if (_analysis == null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: _analysing
                          ? const Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Stockfish is reviewing the game…')])
                          : r['engine'] == true
                              ? FilledButton(onPressed: _moves.isEmpty ? null : _analyse, child: const Text('Analyse with Stockfish'))
                              : const Text('Analysis is not available on this server.'),
                    ),
                  )
                else
                  Padding(padding: const EdgeInsets.all(12), child: Row(children: [_accuracy('white'), _accuracy('black')])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (var i = 0; i < _moves.length; i++)
                      ChoiceChip(
                        label: Text(
                          '${i.isEven ? '${_label(i)} ' : ''}${_graded(i + 1)?['san'] ?? _moves[i]}',
                          style: TextStyle(color: _graded(i + 1) == null ? null : _gradeColors[_graded(i + 1)!['cls']]),
                        ),
                        selected: _ply == i + 1,
                        onSelected: (_) => _go(i + 1),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
              ]),
            ),
    );
  }
}
