import 'package:chess_yetu/api.dart';
import 'package:chess_yetu/game_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _snapshot({String status = 'active', List<String> moves = const [], String fen = startFen}) => {
      'status': status,
      'fen': fen,
      'moves': moves,
      'seq': moves.length,
      'turn': moves.length.isEven ? 'white' : 'black',
      'clocks': {'white': 300000, 'black': 300000},
      'players': {
        'white': {'name': 'amina', 'rating': 1500},
        'black': {'name': 'Stockfish', 'rating': 800},
      },
      'result': null,
      'reason': null,
      'draw_offer': null,
      'vs_bot': true,
    };

Future<GameController> _controller(String color) async {
  SharedPreferences.setMockInitialValues({});
  final api = Api();
  await api.init();
  return GameController(api, Seat('g1', color, 'tok'), connect: false);
}

void main() {
  test('resync loads the position, players and clocks', () async {
    final g = await _controller('white');
    g.handleMessage({'type': 'resync', 'you': 'white', ..._snapshot(moves: ['e2e4'], fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1')});
    expect(g.connected, true);
    expect(g.status, 'active');
    expect(g.moves, ['e2e4']);
    expect(g.turn, 'black');
    expect(g.myTurn, false);
    expect(g.players['white']?['name'], 'amina');
    expect(g.clockMs('white'), 300000); // not the side to move, so frozen
    expect(g.clockMs('black'), lessThanOrEqualTo(300000));
    g.dispose();
  });

  test('move_made applies once even if the echo of our own move arrives', () async {
    final g = await _controller('white');
    g.handleMessage({'type': 'resync', 'you': 'white', ..._snapshot()});
    expect(g.legalFrom('e2').keys, containsAll(['e3', 'e4']));
    g.playMove('e2', 'e4'); // optimistic
    expect(g.moves, ['e2e4']);
    g.handleMessage({'type': 'move_made', 'seq': 1, 'move': 'e2e4', 'clocks': {'white': 299000, 'black': 300000}});
    expect(g.moves, ['e2e4']); // the echo is ignored
    g.handleMessage({'type': 'move_made', 'seq': 2, 'move': 'e7e5', 'clocks': {'white': 299000, 'black': 299000}});
    expect(g.moves, ['e2e4', 'e7e5']);
    expect(g.myTurn, true);
    expect(g.replay.san, ['e4', 'e5']);
    g.dispose();
  });

  test('moves are refused when it is not our turn', () async {
    final g = await _controller('black');
    g.handleMessage({'type': 'resync', 'you': 'black', ..._snapshot()});
    g.playMove('e7', 'e5');
    expect(g.moves, isEmpty);
    g.dispose();
  });

  test('game_over ends the game and records the rating change', () async {
    final g = await _controller('white');
    g.handleMessage({'type': 'resync', 'you': 'white', ..._snapshot()});
    g.handleMessage({
      'type': 'game_over',
      'result': '1-0',
      'reason': 'resignation',
      'rating_change': {'white': 8.0, 'black': -8.0},
    });
    expect(g.status, 'over');
    expect(g.result, '1-0');
    expect(g.ratingChange?['white'], 8.0);
    g.dispose();
  });

  test('draw offers, opponent status and errors are tracked', () async {
    final g = await _controller('white');
    g.handleMessage({'type': 'resync', 'you': 'white', ..._snapshot()});
    g.handleMessage({'type': 'draw_offered', 'by': 'black'});
    expect(g.drawOffer, 'black');
    g.handleMessage({'type': 'opponent_status', 'color': 'black', 'connected': false});
    expect(g.opponentOnline, false);
    g.handleMessage({'type': 'error', 'code': 'illegal_move', 'message': 'nope'});
    expect(g.error, 'nope');
    g.dispose();
  });

  test('kids games flag the chat and show only the other side preset phrase', () async {
    final g = await _controller('white');
    g.handleMessage({'type': 'resync', 'you': 'white', ..._snapshot(), 'kids': true});
    expect(g.kids, true);
    g.handleMessage({'type': 'said', 'by': 'white', 'id': 'gl'}); // our own echo
    expect(g.opponentPhrase, isNull);
    g.handleMessage({'type': 'said', 'by': 'black', 'id': 'gg'});
    expect(g.opponentPhrase, 'gg');
    expect(g.opponentPhraseAt, isNotNull);
    g.dispose();
  });
}
