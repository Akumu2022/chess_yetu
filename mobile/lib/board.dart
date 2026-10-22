import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import 'prefs.dart';

/// Bundled so the pieces look the same on every device. (Without it the pawn can fall back to an emoji font.)
const pieceFont = 'ChessPieces';

const _glyph = {'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};

/// Squares from a FEN's placement field, keyed by name ("e4" -> "P" for a white pawn, "p" for black).
Map<String, String> piecesFromFen(String fen) {
  final out = <String, String>{};
  final rows = fen.split(' ').first.split('/');
  for (var r = 0; r < 8; r++) {
    var f = 0;
    for (final c in rows[r].split('')) {
      final n = int.tryParse(c);
      if (n != null) {
        f += n;
      } else {
        out['${'abcdefgh'[f]}${8 - r}'] = c;
        f++;
      }
    }
  }
  return out;
}

/// Legal destinations for the piece on [from], each mapped to whether the move is a promotion.
Map<String, bool> legalTargets(ch.Chess engine, String from) {
  final out = <String, bool>{};
  for (final mv in engine.moves({'verbose': true})) {
    if (mv['from'] == from) out[mv['to'] as String] = (mv['san'] as String).contains('=');
  }
  return out;
}

/// Paints one square: a flat colour, or wood grain / marble veins that differ from square to square.
class SquarePainter extends CustomPainter {
  final Surface surface;
  final Color base;
  final int seed;
  const SquarePainter(this.surface, this.base, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    if (surface == Surface.solid) return;
    canvas.save();
    canvas.clipRect(rect);
    final rnd = math.Random(seed);
    final w = size.width, h = size.height;
    if (surface == Surface.wood) {
      // a gentle light-to-dark sweep, then wavy grain lines
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withAlpha(rnd.nextInt(18) + 6), Colors.black.withAlpha(rnd.nextInt(24) + 8)],
          ).createShader(rect),
      );
      final lines = 9;
      for (var i = 0; i < lines; i++) {
        final y = (i + rnd.nextDouble()) / lines * h;
        final bend = (rnd.nextDouble() - .5) * h * .35;
        final dark = rnd.nextBool();
        final path = Path()
          ..moveTo(-2, y)
          ..cubicTo(w * .3, y + bend, w * .65, y - bend, w + 2, y + bend * .4);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5 + rnd.nextDouble() * 1.4
            ..color = (dark ? Colors.black : Colors.white).withAlpha(
              dark ? 20 + rnd.nextInt(34) : 14 + rnd.nextInt(22),
            ),
        );
      }
    } else {
      // soft cloudiness plus a few thin veins
      final cx = rnd.nextDouble() * w, cy = rnd.nextDouble() * h;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withAlpha(46), Colors.transparent],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: w * .9)),
      );
      final veins = 2 + rnd.nextInt(2);
      for (var i = 0; i < veins; i++) {
        final path = Path()
          ..moveTo(rnd.nextDouble() * w, -2)
          ..cubicTo(rnd.nextDouble() * w, h * .3, rnd.nextDouble() * w, h * .65, rnd.nextDouble() * w, h + 2);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .4 + rnd.nextDouble() * 1.1
            ..color = (rnd.nextBool() ? Colors.black : Colors.white).withAlpha(24 + rnd.nextInt(40)),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SquarePainter old) => old.surface != surface || old.base != base || old.seed != seed;
}

class BoardView extends StatelessWidget {
  final String fen;
  final String perspective; // 'white' or 'black' at the bottom
  final String? selected, lastFrom, lastTo;
  final Set<String> targets;
  final ValueChanged<String> onTap;

  const BoardView({
    super.key,
    required this.fen,
    required this.perspective,
    required this.onTap,
    this.selected,
    this.lastFrom,
    this.lastTo,
    this.targets = const {},
  });

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Prefs.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final prefs = Prefs.instance;
    final pieces = piecesFromFen(fen);
    final flip = perspective == 'black';
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final pad = prefs.frame ? box.maxWidth * .055 : 0.0;
          final size = (box.maxWidth - pad * 2) / 8;
          final grid = Column(
            children: [
              for (var r = 0; r < 8; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < 8; c++)
                        Expanded(child: _square(prefs, pieces, flip ? 7 - c : c, flip ? r + 1 : 8 - r, r, c, size)),
                    ],
                  ),
                ),
            ],
          );
          if (!prefs.frame) return grid;
          final frameColor = Color.alphaBlend(Colors.black.withAlpha(110), prefs.board.dark);
          final label = TextStyle(fontSize: pad * .62, color: Colors.white70, fontWeight: FontWeight.w600);
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: frameColor)),
              Positioned(left: pad, top: pad, right: pad, bottom: pad, child: grid),
              if (prefs.coords)
                for (var i = 0; i < 8; i++) ...[
                  Positioned(
                    left: pad + i * size,
                    bottom: 0,
                    width: size,
                    height: pad,
                    child: Center(child: Text('abcdefgh'[flip ? 7 - i : i], style: label)),
                  ),
                  Positioned(
                    left: 0,
                    top: pad + i * size,
                    width: pad,
                    height: size,
                    child: Center(child: Text('${flip ? i + 1 : 8 - i}', style: label)),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _square(Prefs prefs, Map<String, String> pieces, int file, int rank, int row, int col, double size) {
    final name = '${'abcdefgh'[file]}$rank';
    final isLight = (file + rank) % 2 == 1;
    final piece = pieces[name];
    final isWhite = piece != null && piece == piece.toUpperCase();
    final theme = prefs.board;
    final highlight = name == selected
        ? const Color(0x8800C853)
        : (prefs.lastMove && (name == lastFrom || name == lastTo))
        ? const Color(0x66FFEB3B)
        : null;
    final fg = isLight ? theme.dark : theme.light;
    final colors = prefs.pieces;
    return Semantics(
      label: name,
      child: GestureDetector(
        onTap: () => onTap(name),
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: SquarePainter(theme.surface, isLight ? theme.light : theme.dark, file * 8 + rank)),
            if (highlight != null) ColoredBox(color: highlight),
            if (prefs.coords && !prefs.frame && col == 0)
              Positioned(
                left: 2,
                top: 1,
                child: Text(
                  '$rank',
                  style: TextStyle(fontSize: size * .2, color: fg),
                ),
              ),
            if (prefs.coords && !prefs.frame && row == 7)
              Positioned(
                right: 2,
                bottom: 0,
                child: Text(
                  'abcdefgh'[file],
                  style: TextStyle(fontSize: size * .2, color: fg),
                ),
              ),
            if (piece != null)
              Center(
                child: Text(
                  '${_glyph[piece.toLowerCase()]}︎',
                  style: TextStyle(
                    fontFamily: pieceFont,
                    fontSize: size * .8,
                    height: 1,
                    color: isWhite ? colors.white : colors.black,
                    shadows: isWhite
                        ? const [Shadow(color: Colors.black, blurRadius: 1), Shadow(color: Colors.black, blurRadius: 3)]
                        : const [Shadow(color: Color(0x66FFFFFF), blurRadius: 2)],
                  ),
                ),
              ),
            if (prefs.hints && targets.contains(name))
              Center(
                child: Container(
                  width: piece == null ? size * .3 : size * .9,
                  height: piece == null ? size * .3 : size * .9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: piece == null ? const Color(0x55000000) : null,
                    border: piece == null ? null : Border.all(color: const Color(0x66000000), width: size * .08),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small 4x4 preview of a board style, for the picker.
class BoardSwatch extends StatelessWidget {
  final BoardColors theme;
  final double size;
  const BoardSwatch(this.theme, {super.key, this.size = 72});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: size,
      height: size,
      child: Column(
        children: [
          for (var r = 0; r < 4; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 4; c++)
                    Expanded(
                      child: CustomPaint(
                        painter: SquarePainter(
                          theme.surface,
                          (r + c).isEven ? theme.light : theme.dark,
                          r * 4 + c + theme.id.length,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
