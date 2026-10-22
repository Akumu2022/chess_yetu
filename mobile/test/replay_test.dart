import 'package:chess_yetu/game_controller.dart' show startFen;
import 'package:chess_yetu/replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notation and captures, most valuable first', () {
    final r = replay(['e2e4', 'd7d5', 'e4d5', 'd8d5', 'b1c3', 'd5a5']);
    expect(r.san, ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5']);
    expect(r.byWhite, ['p']);
    expect(r.byBlack, ['p']);
  });

  test('castling, en passant and promotion', () {
    final ep = replay(['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6']);
    expect(ep.san.last, 'exd6');
    expect(ep.byWhite, ['p']);

    final promo = replay(['h2h4', 'g7g5', 'h4g5', 'h7h6', 'g5h6', 'g8f6', 'h6h7', 'f6g8', 'h7g8q']);
    expect(promo.san.last, 'hxg8=Q');
    expect(promo.byWhite, containsAll(['p', 'n']));
  });

  test('materialDiff and figurine', () {
    expect(materialDiff(startFen), 0);
    expect(materialDiff('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w KQkq - 0 1'), -1);
    expect(figurine('Nf3'), '♘f3');
    expect(figurine('exd8=Q+'), 'exd8=♕+');
    expect(figurine('e4'), 'e4');
  });
}
