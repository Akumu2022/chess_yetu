import 'dart:convert';

import 'package:chess_yetu/api.dart';
import 'package:chess_yetu/board.dart';
import 'package:chess_yetu/game_controller.dart' show startFen;
import 'package:chess_yetu/prefs.dart';
import 'package:chess_yetu/screens/lobby.dart';
import 'package:chess_yetu/screens/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Api> _api({bool signedIn = false}) async {
  SharedPreferences.setMockInitialValues({if (signedIn) 'token': 't'});
  final api = Api(client: MockClient((r) async {
    final body = r.url.path == '/me' ? {'username': 'amina', 'rating': 1612, 'id': 1} : [];
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  }));
  await api.init();
  return api;
}

void main() {
  testWidgets('the board draws 32 pieces and reports which square was tapped', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.load();
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: BoardView(fen: startFen, perspective: 'white', onTap: (s) => tapped = s))),
    ));
    final pieces = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').endsWith('︎'));
    expect(pieces, findsNWidgets(32));

    final rect = tester.getRect(find.byType(BoardView));
    final sq = rect.width / 8;
    await tester.tapAt(rect.topLeft + Offset(sq * 4.5, sq * 6.5)); // e2 with white at the bottom
    expect(tapped, 'e2');
    await tester.tapAt(rect.topLeft + Offset(sq * 0.5, sq * 0.5)); // a8
    expect(tapped, 'a8');
  });

  testWidgets('a flipped board puts black at the bottom', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.load();
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: BoardView(fen: startFen, perspective: 'black', onTap: (s) => tapped = s))),
    ));
    final rect = tester.getRect(find.byType(BoardView));
    final sq = rect.width / 8;
    await tester.tapAt(rect.topLeft + Offset(sq * 0.5, sq * 0.5));
    expect(tapped, 'h1');
  });

  testWidgets('settings switches are saved in Prefs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.load();
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(Prefs.instance.sound, true);
    await tester.tap(find.text('Move sounds'));
    await tester.pump();
    expect(Prefs.instance.sound, false);

    await tester.tap(find.text('Green'));
    await tester.pump();
    expect(Prefs.instance.boardId, 'green');
    expect((await SharedPreferences.getInstance()).getString('board'), 'green');
    Prefs.instance.set(board: 'classic', sound: true);
  });

  testWidgets('the lobby offers sign in to guests and puzzles to signed-in players', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: LobbyScreen(api: await _api())));
    await tester.pump();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Play vs computer'), findsOneWidget);
    expect(find.text('Puzzles'), findsNothing);
    expect(find.text('Sign in to be paired with another player.'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: LobbyScreen(api: await _api(signedIn: true))));
    await tester.pump();
    expect(find.text('amina · 1612'), findsOneWidget);
    expect(find.text('Puzzles'), findsOneWidget);
    expect(find.text('Find an opponent'), findsOneWidget);
  });
}
