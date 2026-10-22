import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BoardColors {
  final String id, name;
  final Color light, dark;
  const BoardColors(this.id, this.name, this.light, this.dark);
}

/// The same square colours as the web app.
const boardThemes = [
  BoardColors('classic', 'Classic', Color(0xFFF0D9B5), Color(0xFFB58863)),
  BoardColors('green', 'Green', Color(0xFFEEEED2), Color(0xFF769656)),
  BoardColors('ocean', 'Ocean', Color(0xFFDEE3E6), Color(0xFF8CA2AD)),
  BoardColors('violet', 'Violet', Color(0xFFEFE6F5), Color(0xFF8877B7)),
  BoardColors('slate', 'Slate', Color(0xFFE3E3E3), Color(0xFF7D8796)),
  BoardColors('savanna', 'Savanna', Color(0xFFF6E7B8), Color(0xFFC47A2C)),
];

/// Display choices, saved on this device only.
class Prefs extends ChangeNotifier {
  Prefs._();
  static final instance = Prefs._();

  SharedPreferences? _p;
  String boardId = 'classic';
  bool hints = true, coords = true, lastMove = true;

  BoardColors get board => boardThemes.firstWhere((b) => b.id == boardId, orElse: () => boardThemes.first);

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    boardId = _p!.getString('board') ?? boardId;
    hints = _p!.getBool('hints') ?? hints;
    coords = _p!.getBool('coords') ?? coords;
    lastMove = _p!.getBool('lastMove') ?? lastMove;
  }

  void set({String? board, bool? hints, bool? coords, bool? lastMove}) {
    boardId = board ?? boardId;
    this.hints = hints ?? this.hints;
    this.coords = coords ?? this.coords;
    this.lastMove = lastMove ?? this.lastMove;
    _p?.setString('board', boardId);
    _p?.setBool('hints', this.hints);
    _p?.setBool('coords', this.coords);
    _p?.setBool('lastMove', this.lastMove);
    notifyListeners();
  }
}
