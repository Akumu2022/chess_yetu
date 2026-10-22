import 'package:chess_yetu/board.dart';
import 'package:chess_yetu/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('piecesFromFen places the starting position', () {
    final p = piecesFromFen(startFen);
    expect(p.length, 32);
    expect(p['e1'], 'K');
    expect(p['d8'], 'q');
    expect(p['e4'], isNull);
  });
}
