import 'package:chess_yetu/board.dart';
import 'package:chess_yetu/game_controller.dart' show startFen;
import 'package:chess_yetu/prefs.dart';
import 'package:chess_yetu/result.dart';
import 'package:chess_yetu/screens/result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('describeResult', () {
    test('wins, losses and draws from either colour', () {
      final w = describeResult(you: 'white', result: '1-0', reason: 'checkmate');
      expect((w.outcome, w.headline, w.detail), (Outcome.win, 'You won!', 'by checkmate'));
      final l = describeResult(you: 'white', result: '0-1', reason: 'resignation');
      expect((l.outcome, l.headline, l.detail), (Outcome.loss, 'You lost', 'by resignation'));
      final b = describeResult(you: 'black', result: '0-1', reason: 'timeout');
      expect((b.outcome, b.detail), (Outcome.win, 'on time'));
      final d = describeResult(you: 'black', result: '1/2-1/2', reason: 'stalemate');
      expect((d.outcome, d.headline, d.detail), (Outcome.draw, 'Draw', 'by stalemate'));
    });

    test('every reason the server can send has readable words', () {
      for (final r in [
        'checkmate',
        'timeout',
        'resignation',
        'agreement',
        'stalemate',
        'insufficient_material',
        'repetition',
        'fifty_moves',
      ]) {
        expect(reasonText(r), isNotEmpty);
        expect(reasonText(r), isNot(contains('_')));
      }
      expect(reasonText(null), '');
    });

    test('kids get friendlier words and never "You lost"', () {
      expect(describeResult(you: 'white', result: '0-1', reason: 'checkmate', kids: true).headline, 'Good game!');
      expect(describeResult(you: 'white', result: '1-0', reason: 'checkmate', kids: true).headline, contains('won'));
    });
  });

  group('ResultCard', () {
    Future<void> pump(WidgetTester tester, ResultInfo info, ResultActions actions, {double? delta, int? now}) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResultCard(
                info: info,
                result: '1-0',
                players: const {
                  'white': {'name': 'amina', 'rating': 1500},
                  'black': {'name': 'Stockfish', 'rating': 800},
                },
                you: 'white',
                ratingDelta: delta,
                ratingNow: now,
                actions: actions,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('shows the result, both players, rating change and the action buttons', (tester) async {
      var reviewed = false, rematched = false, left = false;
      await pump(
        tester,
        describeResult(you: 'white', result: '1-0', reason: 'checkmate'),
        ResultActions(onReview: () => reviewed = true, onRematch: () => rematched = true, onLobby: () => left = true),
        delta: 8.4,
        now: 1508,
      );
      expect(find.text('You won!'), findsOneWidget);
      expect(find.text('by checkmate'), findsOneWidget);
      expect(find.text('amina'), findsOneWidget);
      expect(find.text('Stockfish'), findsOneWidget);
      expect(find.text('1-0'), findsOneWidget);
      expect(find.text('1508'), findsOneWidget);
      expect(find.text('8.4'), findsOneWidget);

      await tester.tap(find.text('Game Review'));
      await tester.tap(find.text('Rematch'));
      await tester.tap(find.text('Back to lobby'));
      expect((reviewed, rematched, left), (true, true, true));
    });

    testWidgets('buttons without an action are hidden, and an unrated game shows no rating', (tester) async {
      await pump(tester, describeResult(you: 'white', result: '0-1', reason: 'timeout'), ResultActions(onLobby: () {}));
      expect(find.text('You lost'), findsOneWidget);
      expect(find.text('on time'), findsOneWidget);
      expect(find.text('Game Review'), findsNothing);
      expect(find.text('Rematch'), findsNothing);
      expect(find.text('Rating'), findsNothing);
    });
  });

  group('board styles', () {
    testWidgets('every board style and piece set renders the full position', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.instance.load();
      addTearDown(() => Prefs.instance.set(board: 'classic', pieces: 'classic', frame: false));
      for (final b in boardThemes) {
        Prefs.instance.set(board: b.id, pieces: pieceStyles[boardThemes.indexOf(b) % pieceStyles.length].id);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: BoardView(fen: startFen, perspective: 'white', onTap: (_) {}),
              ),
            ),
          ),
        );
        final pieces = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').endsWith('︎'));
        expect(pieces, findsNWidgets(32), reason: b.id);
        expect(tester.takeException(), isNull, reason: b.id);
      }
    });

    testWidgets('a framed board keeps coordinates outside and still reports taps', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.instance.load();
      Prefs.instance.set(frame: true, coords: true);
      addTearDown(() => Prefs.instance.set(frame: false));
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BoardView(fen: startFen, perspective: 'white', onTap: (s) => tapped = s),
            ),
          ),
        ),
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      final rect = tester.getRect(find.byType(BoardView));
      final pad = rect.width * .055, sq = (rect.width - pad * 2) / 8;
      await tester.tapAt(rect.topLeft + Offset(pad + sq * 4.5, pad + sq * 6.5));
      expect(tapped, 'e2');
    });

    test('board ids are unique, grouped, and unknown ids fall back safely', () {
      expect({for (final b in boardThemes) b.id}.length, boardThemes.length);
      expect(boardThemes.length, greaterThanOrEqualTo(20));
      expect(boardThemes.map((b) => b.surface).toSet(), containsAll([Surface.solid, Surface.wood, Surface.marble]));
      final p = Prefs.instance..set(board: 'nope', pieces: 'nope');
      expect(p.board.id, 'classic');
      expect(p.pieces.id, 'classic');
    });
  });
}
