import 'package:flutter/material.dart';

const _glyph = {'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};
const _light = Color(0xFFF0D9B5), _dark = Color(0xFFB58863);

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
  Widget build(BuildContext context) {
    final pieces = piecesFromFen(fen);
    final flip = perspective == 'black';
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = box.maxWidth / 8;
        return Column(children: [
          for (var r = 0; r < 8; r++)
            Expanded(
              child: Row(children: [
                for (var c = 0; c < 8; c++)
                  Expanded(child: _square(pieces, flip ? 7 - c : c, flip ? r + 1 : 8 - r, r, c, size)),
              ]),
            ),
        ]);
      }),
    );
  }

  Widget _square(Map<String, String> pieces, int file, int rank, int row, int col, double size) {
    final name = '${'abcdefgh'[file]}$rank';
    final isLight = (file + rank) % 2 == 1;
    final piece = pieces[name];
    final isWhite = piece != null && piece == piece.toUpperCase();
    Color bg = isLight ? _light : _dark;
    if (name == lastFrom || name == lastTo) bg = Color.alphaBlend(const Color(0x66FFEB3B), bg);
    if (name == selected) bg = Color.alphaBlend(const Color(0x8800C853), bg);
    final fg = isLight ? _dark : _light;
    return Semantics(
      label: name,
      child: GestureDetector(
        onTap: () => onTap(name),
        child: Container(
          color: bg,
          child: Stack(alignment: Alignment.center, children: [
            if (col == 0) Positioned(left: 2, top: 1, child: Text('$rank', style: TextStyle(fontSize: size * .2, color: fg))),
            if (row == 7) Positioned(right: 2, bottom: 0, child: Text('abcdefgh'[file], style: TextStyle(fontSize: size * .2, color: fg))),
            if (piece != null)
              Text(
                '${_glyph[piece.toLowerCase()]}︎',
                style: TextStyle(
                  fontSize: size * .8,
                  height: 1,
                  color: isWhite ? Colors.white : const Color(0xFF1C1C1C),
                  shadows: isWhite
                      ? const [Shadow(color: Colors.black, blurRadius: 1), Shadow(color: Colors.black, offset: Offset(0, 0), blurRadius: 3)]
                      : null,
                ),
              ),
            if (targets.contains(name))
              Container(
                width: piece == null ? size * .3 : size * .9,
                height: piece == null ? size * .3 : size * .9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: piece == null ? const Color(0x55000000) : null,
                  border: piece == null ? null : Border.all(color: const Color(0x66000000), width: size * .08),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
