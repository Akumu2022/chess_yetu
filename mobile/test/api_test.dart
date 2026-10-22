import 'dart:convert';

import 'package:chess_yetu/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<(Api, List<http.Request>)> _api(http.Response Function(http.Request) handler) async {
  SharedPreferences.setMockInitialValues({});
  final seen = <http.Request>[];
  final api = Api(client: MockClient((r) async {
    seen.add(r);
    return handler(r);
  }));
  await api.init();
  await api.setBaseUrl('http://test/');
  return (api, seen);
}

void main() {
  test('login stores the token and user, then sends it on later requests', () async {
    final (api, seen) = await _api((r) => r.url.path == '/auth/login'
        ? _json({'token': 'abc', 'user': {'username': 'amina', 'rating': 1500}})
        : _json([]));
    expect(api.baseUrl, 'http://test'); // trailing slash trimmed
    await api.login('amina', 'password123');
    expect(api.user?.username, 'amina');
    await api.myGames();
    expect(seen.last.headers['Authorization'], 'Bearer abc');
    expect((await SharedPreferences.getInstance()).getString('token'), 'abc');
    await api.logout();
    expect(api.user, isNull);
  });

  test('server errors surface the detail message', () async {
    final (api, _) = await _api((_) => _json({'detail': 'Wrong username or password'}, 401));
    expect(
      () => api.login('a', 'b'),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Wrong username or password')),
    );
  });

  test('an unreachable server gives a friendly message', () async {
    SharedPreferences.setMockInitialValues({});
    final api = Api(client: MockClient((_) async => throw Exception('socket')));
    await api.init();
    await api.setBaseUrl('http://nowhere');
    expect(
      () => api.nextPuzzle(),
      throwsA(isA<ApiError>().having((e) => e.message, 'message', contains('reach the server'))),
    );
  });

  test('queue: waiting returns null, matched returns the seat', () async {
    var matched = false;
    final (api, _) = await _api((r) => _json(matched
        ? {'status': 'matched', 'seat': {'game_id': 'g1', 'color': 'black', 'token': 't'}}
        : {'status': 'waiting'}));
    expect(await api.joinQueue(5, 0), isNull);
    matched = true;
    final seat = await api.pollQueue();
    expect(seat?.gameId, 'g1');
    expect(seat?.color, 'black');
  });

  test('new games and arenas send the chosen settings', () async {
    final (api, seen) = await _api((_) => _json({'game_id': 'x', 'color': 'white', 'token': 't', 'id': 7}));
    await api.newBotGame(level: 3, color: 'white', minutes: 10, increment: 5);
    expect(jsonDecode(seen.last.body), {'level': 3, 'color': 'white', 'minutes': 10, 'increment': 5});
    final id = await api.createTournament(name: 'Friday', minutes: 3, increment: 2, startsInMin: 5, durationMin: 30);
    expect(id, 7);
    expect(seen.last.url.path, '/tournaments');
    expect(jsonDecode(seen.last.body)['starts_in_min'], 5);
  });

  test('websocket address follows the server scheme', () async {
    final (api, _) = await _api((_) => _json({}));
    expect(api.wsUri('abc').toString(), 'ws://test/ws/games/abc');
    await api.setBaseUrl('https://chess.example');
    expect(api.wsUri('abc').toString(), 'wss://chess.example/ws/games/abc');
  });

  test('PIN and daily limit use PUT and PATCH', () async {
    final (api, seen) = await _api((_) => _json({'set': true}));
    await api.setPin('4321', current: '1111');
    expect(seen.last.method, 'PUT');
    expect(jsonDecode(seen.last.body), {'pin': '4321', 'current': '1111'});
    await api.setDailyLimit(3, 40);
    expect(seen.last.method, 'PATCH');
    expect(seen.last.url.path, '/kids/children/3');
  });

  group('kids mode', () {
    final child = {
      'id': 3,
      'nickname': 'BraveSimba',
      'rating': 1500,
      'games': 0,
      'birth_year': 2017,
      'daily_limit_min': 60,
      'minutes_today': 5,
      'minutes_left': 55,
    };

    test('handing over the device switches to the child and survives a restart, even offline', () async {
      final (api, _) = await _api((r) => r.url.path.endsWith('/session') ? _json({'token': 'kidtok', 'child': child}) : _json({}));
      await api.startKidSession(3);
      expect(api.kid?.nickname, 'BraveSimba');
      expect(api.user, isNull);

      // restart with the server unreachable: the child's session must stay locked
      final offline = Api(client: MockClient((_) async => throw Exception('no network')));
      await offline.init();
      expect(offline.kid?.nickname, 'BraveSimba');
      expect(offline.kid?.minutesLeft, 55);
    });

    test('restart recognises the session from whoami', () async {
      SharedPreferences.setMockInitialValues({'token': 'kidtok'});
      final api = Api(client: MockClient((_) async => _json({'kind': 'kid', 'child': child})));
      await api.init();
      expect(api.kid?.id, 3);
    });

    test('an expired session drops back to a guest, but being offline does not sign an adult out', () async {
      SharedPreferences.setMockInitialValues({'token': 'old'});
      final expired = Api(client: MockClient((_) async => _json({'detail': 'Sign in required'}, 401)));
      await expired.init();
      expect(expired.token, isNull);

      SharedPreferences.setMockInitialValues({'token': 'adult'});
      final offline = Api(client: MockClient((_) async => throw Exception('no network')));
      await offline.init();
      expect(offline.token, 'adult');
    });

    test('leaving kids mode needs the PIN and returns the parent', () async {
      final (api, _) = await _api((r) {
        if (r.url.path.endsWith('/session')) return _json({'token': 'kidtok', 'child': child});
        final body = jsonDecode(r.body);
        return body['pin'] == '4321'
            ? _json({'token': 'parenttok', 'user': {'username': 'mama', 'rating': 1500}})
            : _json({'detail': 'Wrong PIN'}, 403);
      });
      await api.startKidSession(3);
      await expectLater(api.exitKidsMode('0000'), throwsA(isA<ApiError>()));
      expect(api.kid, isNotNull);
      await api.exitKidsMode('4321');
      expect(api.kid, isNull);
      expect(api.user?.username, 'mama');
      expect(api.token, 'parenttok');
    });
  });
}
