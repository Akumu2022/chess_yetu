import 'package:chess/chess.dart' as ch;

const _value = {'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9};
const _order = ['q', 'r', 'b', 'n', 'p'];
const _figurine = {'K': '♔', 'Q': '♕', 'R': '♖', 'B': '♗', 'N': '♘'};
const _glyph = {'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};

int _byValue(String a, String b) => _order.indexOf(a) - _order.indexOf(b);

class Replay {
  /// Moves in standard notation (Nf3, exd5, O-O, e8=Q+).
  final List<String> san;

  /// Piece types taken BY white (black pieces) and BY black (white pieces), most valuable first.
  final List<String> byWhite, byBlack;
  const Replay(this.san, this.byWhite, this.byBlack);
}

/// Replays UCI moves from the start position, collecting notation and captures (en passant included).
Replay replay(List<String> moves) {
  final engine = ch.Chess();
  final san = <String>[], byWhite = <String>[], byBlack = <String>[];
  for (final uci in moves) {
    final from = uci.substring(0, 2), to = uci.substring(2, 4);
    final promo = uci.length > 4 ? uci[4] : null;
    Map? found;
    for (final mv in engine.moves({'verbose': true})) {
      if (mv['from'] != from || mv['to'] != to) continue;
      if (promo == null || (mv['san'] as String).contains('=${promo.toUpperCase()}')) {
        found = mv;
        break;
      }
    }
    if (found == null) break; // the server only sends legal moves, so this should never happen
    san.add(found['san'] as String);
    final captured = found['captured'];
    if (captured != null) (engine.turn == ch.Color.WHITE ? byWhite : byBlack).add(captured.toString());
    engine.move({'from': from, 'to': to, 'promotion': ?promo});
  }
  return Replay(san, byWhite..sort(_byValue), byBlack..sort(_byValue));
}

/// Material on the board, white minus black, in pawns. Positive means white is ahead.
int materialDiff(String fen) {
  var diff = 0;
  for (final c in fen.split(' ').first.split('')) {
    final v = _value[c.toLowerCase()];
    if (v != null) diff += c == c.toUpperCase() ? v : -v;
  }
  return diff;
}

/// Standard notation with the piece letter shown as the piece itself: Nf3 becomes ♘f3.
String figurine(String san) => san
    .replaceFirstMapped(RegExp(r'^[KQRBN]'), (m) => _figurine[m[0]]!)
    .replaceFirstMapped(RegExp(r'=([QRBN])'), (m) => '=${_figurine[m[1]]}');

/// Captured pieces as glyphs, e.g. "♛♜♟♟".
String capturedGlyphs(List<String> pieces) => pieces.map((p) => '${_glyph[p]}︎').join();
