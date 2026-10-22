import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a board's squares are drawn.
enum Surface { solid, wood, marble }

class BoardColors {
  final String id, name, group;
  final Color light, dark;
  final Surface surface;
  const BoardColors(this.id, this.name, this.group, this.light, this.dark, [this.surface = Surface.solid]);
}

/// Board styles, grouped for the picker. The first six keep the ids the web app uses.
const boardThemes = [
  // Classic colours
  BoardColors('classic', 'Classic', 'Colours', Color(0xFFF0D9B5), Color(0xFFB58863)),
  BoardColors('green', 'Green', 'Colours', Color(0xFFEEEED2), Color(0xFF769656)),
  BoardColors('ocean', 'Ocean', 'Colours', Color(0xFFDEE3E6), Color(0xFF8CA2AD)),
  BoardColors('violet', 'Violet', 'Colours', Color(0xFFEFE6F5), Color(0xFF8877B7)),
  BoardColors('slate', 'Slate', 'Colours', Color(0xFFE3E3E3), Color(0xFF7D8796)),
  BoardColors('savanna', 'Savanna', 'Colours', Color(0xFFF6E7B8), Color(0xFFC47A2C)),
  BoardColors('blue', 'Blue', 'Colours', Color(0xFFEAF0F6), Color(0xFF4F7CAC)),
  BoardColors('coral', 'Coral', 'Colours', Color(0xFFFCE8E0), Color(0xFFE07A5F)),
  BoardColors('rose', 'Rose', 'Colours', Color(0xFFF8E5EA), Color(0xFFC9718A)),
  BoardColors('sand', 'Sand', 'Colours', Color(0xFFF5EFE0), Color(0xFFBFAE8B)),
  BoardColors('newspaper', 'Newspaper', 'Colours', Color(0xFFFFFFFF), Color(0xFFA9A9A9)),
  BoardColors('midnight', 'Midnight', 'Colours', Color(0xFF6E86A8), Color(0xFF1E2F4D)),
  // Stark and tournament styles
  BoardColors('contrast', 'Black & white', 'Bold', Color(0xFFFFFFFF), Color(0xFF111111)),
  BoardColors('gold', 'Gold & black', 'Bold', Color(0xFFF2C14E), Color(0xFF1B1B1B)),
  BoardColors('tournament', 'Tournament', 'Bold', Color(0xFFEBECD0), Color(0xFF739552)),
  BoardColors('crimson', 'Crimson', 'Bold', Color(0xFFF3E1DA), Color(0xFF9B2D30)),
  // Textured
  BoardColors('maple', 'Maple wood', 'Wood', Color(0xFFEBCFA0), Color(0xFFB07A45), Surface.wood),
  BoardColors('walnut', 'Walnut wood', 'Wood', Color(0xFFD2A877), Color(0xFF5B3A29), Surface.wood),
  BoardColors('ebony', 'Ebony wood', 'Wood', Color(0xFFC9A57A), Color(0xFF2E2118), Surface.wood),
  BoardColors('marble', 'Marble', 'Marble', Color(0xFFEDEDED), Color(0xFF8B8F96), Surface.marble),
  BoardColors('onyx', 'Onyx marble', 'Marble', Color(0xFFD8D5CF), Color(0xFF2B2B30), Surface.marble),
  BoardColors('jade', 'Jade marble', 'Marble', Color(0xFFDCE8DA), Color(0xFF5E8C6A), Surface.marble),
];

class PieceColors {
  final String id, name;
  final Color white, black;
  const PieceColors(this.id, this.name, this.white, this.black);
}

/// Piece colours (white side, black side); same ids as the web app.
const pieceStyles = [
  PieceColors('classic', 'Classic', Color(0xFFFFFFFF), Color(0xFF1C1C1C)),
  PieceColors('ivory', 'Ivory & ebony', Color(0xFFFFF6D8), Color(0xFF3B2416)),
  PieceColors('gold', 'Gold & navy', Color(0xFFF5C542), Color(0xFF1D2D5C)),
  PieceColors('contrast', 'High contrast', Color(0xFFFFFFFF), Color(0xFF000000)),
];

/// Display choices, saved on this device only.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final instance = Prefs._();

  SharedPreferences? _p;
  String boardId = 'classic', piecesId = 'classic';
  bool hints = true, coords = true, lastMove = true, sound = true, haptics = true;

  /// Draw the board inside a frame with the coordinates around the outside.
  bool frame = false;

  BoardColors get board => boardThemes.firstWhere((b) => b.id == boardId, orElse: () => boardThemes.first);
  PieceColors get pieces => pieceStyles.firstWhere((p) => p.id == piecesId, orElse: () => pieceStyles.first);

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    boardId = _p!.getString('board') ?? boardId;
    piecesId = _p!.getString('pieces') ?? piecesId;
    hints = _p!.getBool('hints') ?? hints;
    coords = _p!.getBool('coords') ?? coords;
    lastMove = _p!.getBool('lastMove') ?? lastMove;
    sound = _p!.getBool('sound') ?? sound;
    haptics = _p!.getBool('haptics') ?? haptics;
    frame = _p!.getBool('frame') ?? frame;
  }

  void set({
    String? board,
    String? pieces,
    bool? hints,
    bool? coords,
    bool? lastMove,
    bool? sound,
    bool? haptics,
    bool? frame,
  }) {
    boardId = board ?? boardId;
    piecesId = pieces ?? piecesId;
    this.hints = hints ?? this.hints;
    this.coords = coords ?? this.coords;
    this.lastMove = lastMove ?? this.lastMove;
    this.sound = sound ?? this.sound;
    this.haptics = haptics ?? this.haptics;
    this.frame = frame ?? this.frame;
    _p?.setString('board', boardId);
    _p?.setString('pieces', piecesId);
    _p?.setBool('hints', this.hints);
    _p?.setBool('coords', this.coords);
    _p?.setBool('lastMove', this.lastMove);
    _p?.setBool('sound', this.sound);
    _p?.setBool('haptics', this.haptics);
    _p?.setBool('frame', this.frame);
    notifyListeners();
  }
}
