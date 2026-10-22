import 'package:flutter/material.dart';

import '../api.dart';
import '../board.dart';
import '../game_controller.dart';
import '../replay.dart';
import '../result.dart';
import 'lobby.dart' show copyCode;
import 'result_card.dart';
import 'review.dart';

class GameScreen extends StatefulWidget {
  final Api api;
  final Seat seat;
  final String? shareCode;

  /// Starts a fresh game with the same settings; null when "play again" doesn't make sense (e.g. rated matches).
  final Future<(Seat, String?)> Function()? again;

  /// Offer "New game" after a rated quick match: closes this screen with the result 'search' so the lobby queues again.
  final bool canSearch;
  const GameScreen({
    super.key,
    required this.api,
    required this.seat,
    this.shareCode,
    this.again,
    this.canSearch = false,
  });
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController g = GameController(widget.api, widget.seat);
  String? _selected;
  Map<String, bool> _targets = {};
  bool _flipped = false, _starting = false, _cardOpen = false, _cardScheduled = false;
  Future<Map<String, String>>? _phrases;

  @override
  void initState() {
    super.initState();
    g.addListener(_onChange);
  }

  /// When the game ends, give the last move a moment to register, then slide the result card in.
  void _onChange() {
    if (g.status == 'over' && !_cardScheduled) {
      _cardScheduled = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _cardOpen = true);
        }
      });
    }
  }

  @override
  void dispose() {
    g.removeListener(_onChange);
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
    builder: (_) => SimpleDialog(
      title: const Text('Promote to'),
      children: [
        for (final p in const {'q': 'Queen', 'r': 'Rook', 'b': 'Bishop', 'n': 'Knight'}.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, p.key), child: Text(p.value)),
      ],
    ),
  );

  Future<void> _confirm(String title, VoidCallback ok) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
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
    final taken = color == 'white' ? g.replay.byWhite : g.replay.byBlack;
    final lead = materialDiff(g.engine.fen) * (color == 'white' ? 1 : -1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: active ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (taken.isNotEmpty || lead > 0)
                  Text(
                    '${capturedGlyphs(taken)}${lead > 0 ? '  +$lead' : ''}',
                    style: const TextStyle(fontFamily: pieceFont, fontSize: 14, height: 1.2),
                  ),
              ],
            ),
          ),
          if (color != g.you && !g.opponentOnline)
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.wifi_off, size: 16)),
          Text(
            _clock(g.clockMs(color)),
            style: TextStyle(
              fontSize: 20,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: low ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playAgain() async {
    setState(() => _starting = true);
    try {
      final (seat, code) = await widget.again!();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            api: widget.api,
            seat: seat,
            shareCode: code,
            again: widget.again,
            canSearch: widget.canSearch,
          ),
        ),
      );
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Kids can only say a fixed set of friendly phrases.
  Widget _kidsChat() {
    _phrases ??= widget.api.phrases();
    return FutureBuilder<Map<String, String>>(
      future: _phrases,
      builder: (context, snap) {
        final phrases = snap.data;
        if (phrases == null) return const SizedBox();
        final at = g.opponentPhraseAt;
        final heard = at != null && DateTime.now().difference(at).inSeconds < 6 ? phrases[g.opponentPhrase] : null;
        return Column(
          children: [
            SizedBox(
              height: 24,
              child: Center(
                child: Text(heard == null ? '' : '💬 $heard', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            if (g.status != 'over')
              Wrap(
                spacing: 6,
                runSpacing: 0,
                alignment: WrapAlignment.center,
                children: [
                  for (final p in phrases.entries)
                    ActionChip(
                      label: Text(p.value),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => g.say(p.key),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _moveList() {
    final san = g.replay.san;
    if (san.isEmpty) return const SizedBox();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // newest move stays in view
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = san.length - 1; i >= 0; i--)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(child: Text('${i.isEven ? '${i ~/ 2 + 1}. ' : ''}${figurine(san[i])}')),
            ),
        ],
      ),
    );
  }

  ResultInfo get _info => describeResult(you: g.you, result: g.result, reason: g.reason, kids: g.kids);

  ResultActions _actions() => ResultActions(
    onReview: g.kids || g.moves.isEmpty
        ? null
        : () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReviewScreen(api: widget.api, gameId: widget.seat.gameId),
            ),
          ),
    onRematch: widget.again == null || _starting ? null : _playAgain,
    rematchLabel: g.vsBot ? 'Rematch' : 'New game',
    onNew: widget.canSearch ? () => Navigator.pop(context, 'search') : null,
    lobbyLabel: g.inTournament ? 'Back to arena' : 'Back to lobby',
    onLobby: () => Navigator.pop(context),
  );

  /// Leaving a game in progress counts as resigning, so ask first.
  Future<void> _confirmLeave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave this game?'),
        content: const Text('You will resign the game.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resign and leave')),
        ],
      ),
    );
    if (yes == true && mounted) {
      g.resign();
      Navigator.pop(context);
    }
  }

  Widget _resultOverlay() {
    final delta = g.ratingChange?[g.you];
    return ListenableBuilder(
      listenable: widget.api,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _cardOpen = false),
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Opacity(
                    opacity: v.clamp(0, 1),
                    child: Transform.translate(offset: Offset(0, (1 - v) * 40), child: child),
                  ),
                  child: ResultCard(
                    info: _info,
                    result: g.result ?? '',
                    players: g.players,
                    you: g.you,
                    ratingDelta: delta is num ? delta.toDouble() : null,
                    ratingNow: delta is num ? (widget.api.kid?.rating ?? widget.api.user?.rating) : null,
                    actions: _actions(),
                    onClose: () => setState(() => _cardOpen = false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: g,
    builder: (context, _) {
      final bottom = _flipped ? (g.you == 'white' ? 'black' : 'white') : g.you;
      final top = bottom == 'white' ? 'black' : 'white';
      final last = g.lastMove;
      return PopScope(
        canPop: g.status != 'active',
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(g.vsBot ? 'Vs computer' : 'Game ${g.seat.gameId}'),
            actions: [
              IconButton(
                tooltip: 'Flip board',
                icon: const Icon(Icons.swap_vert),
                onPressed: () => setState(() => _flipped = !_flipped),
              ),
            ],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (!g.connected && g.status != 'over')
                        Container(
                          width: double.infinity,
                          color: Colors.amber,
                          padding: const EdgeInsets.all(4),
                          child: Text(g.error ?? 'Connecting…', textAlign: TextAlign.center),
                        ),
                      _bar(top),
                      BoardView(
                        fen: g.engine.fen,
                        perspective: bottom,
                        selected: _selected,
                        targets: _targets.keys.toSet(),
                        lastFrom: last?.substring(0, 2),
                        lastTo: last?.substring(2, 4),
                        onTap: _tap,
                      ),
                      _bar(bottom),
                      _moveList(),
                      if (g.kids) _kidsChat(),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: () => _confirm('Offer a draw?', g.offerDraw),
                              child: const Text('Offer draw'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => _confirm('Resign this game?', g.resign),
                              child: const Text('Resign'),
                            ),
                          ],
                        ),
                      ],
                      if (g.status == 'over')
                        ResultBar(info: _info, actions: _actions(), onShowCard: () => setState(() => _cardOpen = true)),
                    ],
                  ),
                ),
              ),
              if (_cardOpen && g.status == 'over') _resultOverlay(),
            ],
          ),
        ),
      );
    },
  );
}
