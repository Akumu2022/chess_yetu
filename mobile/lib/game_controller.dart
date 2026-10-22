import 'dart:async';
import 'dart:convert';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'board.dart';

const protocolVersion = 1;
const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// One live game: owns the websocket, mirrors the server's state and applies moves locally.
class GameController extends ChangeNotifier {
  final Api api;
  final Seat seat;
  GameController(this.api, this.seat) {
    _connect();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (status == 'active') notifyListeners();
      _pingCount++;
      if (_pingCount % 20 == 0) _send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch, 'rtt': _rtt});
    });
  }

  String get you => seat.color;
  String status = 'waiting'; // waiting | active | over
  ch.Chess engine = ch.Chess.fromFEN(startFen);
  List<String> moves = [];
  Map<String, Map<String, dynamic>> players = {};
  Map<String, int> _clocks = {'white': 0, 'black': 0};
  DateTime _clocksAt = DateTime.now();
  String? result, reason, drawOffer, error;
  Map<String, dynamic>? ratingChange;
  bool vsBot = false, connected = false, opponentOnline = true;
  bool drawDeclined = false;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _timer;
  bool _disposed = false;
  int _retries = 0, _pingCount = 0, _rtt = 0;

  String get turn => engine.turn == ch.Color.WHITE ? 'white' : 'black';
  bool get myTurn => status == 'active' && turn == you;

  /// Time left for [color] in ms, counting down live for the side to move.
  int clockMs(String color) {
    var ms = _clocks[color] ?? 0;
    if (status == 'active' && color == turn) ms -= DateTime.now().difference(_clocksAt).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  String? get lastMove => moves.isEmpty ? null : moves.last;

  Future<void> _connect() async {
    try {
      final c = WebSocketChannel.connect(api.wsUri(seat.gameId));
      await c.ready;
      if (_disposed) return c.sink.close();
      _ch = c;
      _sub = c.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
      _send({'type': 'hello', 'v': protocolVersion, 'token': seat.token});
    } catch (_) {
      _onClosed();
    }
  }

  void _onClosed() {
    connected = false;
    _sub?.cancel();
    _ch = null;
    notifyListeners();
    if (_disposed || status == 'over' || _retries >= 8) {
      if (!_disposed && status != 'over') error = 'Lost connection to the server';
      notifyListeners();
      return;
    }
    _retries++;
    Future.delayed(Duration(seconds: _retries.clamp(1, 4)), () {
      if (!_disposed) _connect();
    });
  }

  void _send(Map<String, dynamic> msg) => _ch?.sink.add(jsonEncode(msg));

  void _loadSnapshot(Map<String, dynamic> m) {
    status = m['status'];
    engine = ch.Chess.fromFEN(m['fen']);
    moves = List<String>.from(m['moves']);
    players = {for (final e in (m['players'] as Map).entries) e.key as String: Map<String, dynamic>.from(e.value)};
    _setClocks(m['clocks']);
    result = m['result'];
    reason = m['reason'];
    drawOffer = m['draw_offer'];
    vsBot = m['vs_bot'] ?? false;
  }

  void _setClocks(Map c) {
    _clocks = {'white': c['white'], 'black': c['black']};
    _clocksAt = DateTime.now();
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (m['type']) {
      case 'resync':
        _retries = 0;
        connected = true;
        error = null;
        _loadSnapshot(m);
      case 'game_started':
        _loadSnapshot(m);
      case 'move_made':
        if ((m['seq'] as int) > moves.length) _apply(m['move']);
        _setClocks(m['clocks']);
        drawOffer = null;
        drawDeclined = false;
      case 'game_over':
        status = 'over';
        result = m['result'];
        reason = m['reason'];
        ratingChange = m['rating_change'];
        api.refreshUser().catchError((_) {});
      case 'opponent_status':
        if (m['color'] != you) opponentOnline = m['connected'];
      case 'draw_offered':
        drawOffer = m['by'];
      case 'draw_declined':
        drawDeclined = true;
      case 'pong':
        _rtt = DateTime.now().millisecondsSinceEpoch - (m['t'] as int);
      case 'error':
        error = m['message'] ?? m['code'];
        // our optimistic move was rejected: reconnect to get the authoritative position
        _ch?.sink.close();
    }
    notifyListeners();
  }

  void _apply(String uci) {
    engine.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci.substring(4),
    });
    moves.add(uci);
  }

  /// Legal destination squares for the piece on [from], each mapped to whether it needs a promotion choice.
  Map<String, bool> legalFrom(String from) => legalTargets(engine, from);

  void playMove(String from, String to, [String? promotion]) {
    if (!myTurn) return;
    final uci = '$from$to${promotion ?? ''}';
    final seq = moves.length + 1;
    _apply(uci); // optimistic; the server echo is ignored by seq
    _send({'type': 'move', 'seq': seq, 'move': uci});
    notifyListeners();
  }

  void resign() => _send({'type': 'resign'});
  void offerDraw() {
    drawDeclined = false;
    _send({'type': 'draw'});
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    super.dispose();
  }
}
