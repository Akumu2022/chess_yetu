import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Seat {
  final String gameId, color, token;
  Seat(this.gameId, this.color, this.token);
  factory Seat.fromJson(Map<String, dynamic> j) => Seat(j['game_id'], j['color'], j['token']);
}

class User {
  final String username;
  final int rating;
  User(this.username, this.rating);
  factory User.fromJson(Map<String, dynamic> j) => User(j['username'], j['rating']);
}

/// Talks to the Chess Yetu API. One instance for the whole app.
class Api extends ChangeNotifier {
  /// [client] is injectable so tests can answer requests without a server.
  Api({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  static const _kUrl = 'server_url', _kToken = 'token';

  late SharedPreferences _prefs;
  String baseUrl = '';
  String? token;
  User? user;

  /// The Android emulator reaches the host machine at 10.0.2.2; the Docker API is on 8780.
  static String get defaultUrl =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8780' : 'http://localhost:8780';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString(_kUrl) ?? defaultUrl;
    token = _prefs.getString(_kToken);
    if (token != null) {
      try {
        user = User.fromJson(await _req('GET', '/me'));
      } on ApiError {
        // server unreachable or token expired: carry on as a guest
        token = null;
        _prefs.remove(_kToken);
      }
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(_kUrl, baseUrl);
    notifyListeners();
  }

  Uri wsUri(String gameId) {
    final u = Uri.parse(baseUrl);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws/games/$gameId');
  }

  Future<dynamic> _req(String method, String path, {Map<String, dynamic>? body}) async {
    final headers = {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
    final uri = Uri.parse('$baseUrl$path');
    try {
      final send = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'DELETE' => _http.delete(uri, headers: headers),
        _ => _http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      };
      final r = await send.timeout(const Duration(seconds: 10));
      final data = r.body.isEmpty ? null : jsonDecode(r.body);
      if (r.statusCode >= 400) {
        final d = data is Map ? data['detail'] : null;
        throw ApiError(d is String ? d : 'Something went wrong (${r.statusCode})');
      }
      return data;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError("Can't reach the server at $baseUrl");
    }
  }

  Future<void> _signedIn(Map<String, dynamic> r) async {
    token = r['token'];
    user = User.fromJson(r['user']);
    await _prefs.setString(_kToken, token!);
    notifyListeners();
  }

  Future<void> login(String name, String pw) async =>
      _signedIn(await _req('POST', '/auth/login', body: {'username': name, 'password': pw}));

  Future<void> register(String name, String pw) async =>
      _signedIn(await _req('POST', '/auth/register', body: {'username': name, 'password': pw}));

  Future<void> logout() async {
    token = null;
    user = null;
    await _prefs.remove(_kToken);
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (token == null) return;
    user = User.fromJson(await _req('GET', '/me'));
    notifyListeners();
  }

  Future<Seat> newBotGame({required int level, required String color, required int minutes, required int increment}) async =>
      Seat.fromJson(await _req('POST', '/games/ai',
          body: {'level': level, 'color': color, 'minutes': minutes, 'increment': increment}));

  Future<Seat> newFriendGame({required int minutes, required int increment}) async =>
      Seat.fromJson(await _req('POST', '/games', body: {'minutes': minutes, 'increment': increment}));

  Future<Seat> joinGame(String id) async => Seat.fromJson(await _req('POST', '/games/${id.trim()}/join'));

  /// Enters the queue; returns the seat if paired at once, otherwise null (then poll [pollQueue]).
  Future<Seat?> joinQueue(int minutes, int increment) async {
    final r = await _req('POST', '/queue', body: {'minutes': minutes, 'increment': increment});
    return r['status'] == 'matched' ? Seat.fromJson(r['seat']) : null;
  }

  Future<Seat?> pollQueue() async {
    final r = await _req('GET', '/queue');
    return r['status'] == 'matched' ? Seat.fromJson(r['seat']) : null;
  }

  Future<void> leaveQueue() async => _req('DELETE', '/queue');

  Future<List<dynamic>> myGames() async => await _req('GET', '/me/games');

  Future<List<dynamic>> leaderboard() async => (await _req('GET', '/leaderboard'))['players'];

  /// Next puzzle plus today's progress, or a map with `limit_reached` once the day's puzzles are done.
  Future<Map<String, dynamic>> nextPuzzle() async => Map<String, dynamic>.from(await _req('GET', '/puzzles/next'));

  /// `status` is wrong | continue (with the opponent's `reply`) | solved.
  Future<Map<String, dynamic>> puzzleMove(int id, List<String> played) async =>
      Map<String, dynamic>.from(await _req('POST', '/puzzles/$id/move', body: {'played': played}));

  Future<Map<String, dynamic>> review(String id) async => Map<String, dynamic>.from(await _req('GET', '/review/$id'));

  /// Runs Stockfish over the finished game (cached server-side after the first time).
  Future<Map<String, dynamic>> analyze(String id) async =>
      Map<String, dynamic>.from(await _req('POST', '/review/$id/analyze'));

  Future<Map<String, dynamic>> profile(String username) async =>
      Map<String, dynamic>.from(await _req('GET', '/players/${Uri.encodeComponent(username)}'));

  Future<List<dynamic>> tournaments() async => await _req('GET', '/tournaments');

  Future<Map<String, dynamic>> tournament(int id) async => Map<String, dynamic>.from(await _req('GET', '/tournaments/$id'));

  Future<void> joinTournament(int id) async => _req('POST', '/tournaments/$id/join');

  Future<void> leaveTournament(int id) async => _req('DELETE', '/tournaments/$id/join');

  /// Heartbeat plus pickup: returns the seat once the tournament has paired us, otherwise null.
  Future<Seat?> tournamentPoll(int id) async {
    final r = await _req('GET', '/tournaments/$id/me');
    return r['status'] == 'matched' ? Seat.fromJson(r['seat']) : null;
  }

  Future<int> createTournament({
    required String name,
    required int minutes,
    required int increment,
    required int startsInMin,
    required int durationMin,
  }) async {
    final r = await _req('POST', '/tournaments', body: {
      'name': name,
      'minutes': minutes,
      'increment': increment,
      'starts_in_min': startsInMin,
      'duration_min': durationMin,
    });
    return r['id'];
  }
}
