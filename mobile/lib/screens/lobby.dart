import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'game.dart';
import 'leaderboard.dart';
import 'login.dart';
import 'puzzle.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _levels = ['Beginner', 'Easy', 'Medium', 'Hard', 'Master'];
const _clocks = [(3, 2), (5, 0), (10, 0), (10, 5), (15, 10)];

class LobbyScreen extends StatefulWidget {
  final Api api;
  const LobbyScreen({super.key, required this.api});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Api get api => widget.api;
  int _level = 1, _clock = 2;
  String _color = 'random';
  bool _busy = false, _searching = false;
  Timer? _poll;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    api.addListener(_changed);
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    _poll?.cancel();
    if (_searching) api.leaveQueue().catchError((_) {});
    super.dispose();
  }

  void _changed() => setState(() {});

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _guard(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Seat seat, {String? shareCode}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(api: api, seat: seat, shareCode: shareCode)));
    if (mounted) {
      api.refreshUser().catchError((_) {});
      setState(() {}); // refresh the recent-games list
    }
  }

  (int, int) get _tc => _clocks[_clock];

  Future<void> _playBot() => _guard(() async {
        final s = await api.newBotGame(level: _level + 1, color: _color, minutes: _tc.$1, increment: _tc.$2);
        await _open(s);
      });

  Future<void> _friend() => _guard(() async {
        final s = await api.newFriendGame(minutes: _tc.$1, increment: _tc.$2);
        await _open(s, shareCode: s.gameId);
      });

  Future<void> _join() => _guard(() async {
        if (_code.text.trim().isEmpty) return;
        await _open(await api.joinGame(_code.text));
      });

  Future<void> _findMatch() => _guard(() async {
        final seat = await api.joinQueue(_tc.$1, _tc.$2);
        if (seat != null) return _open(seat);
        setState(() => _searching = true);
        _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
          try {
            final s = await api.pollQueue();
            if (s != null) {
              _stopSearch(leave: false);
              if (mounted) _open(s);
            }
          } on ApiError {
            _stopSearch(leave: false);
          }
        });
      });

  void _stopSearch({bool leave = true}) {
    _poll?.cancel();
    _poll = null;
    if (leave) api.leaveQueue().catchError((_) {});
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _server() async {
    final c = TextEditingController(text: api.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://10.0.2.2:8780'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, Api.defaultUrl), child: const Text('Reset')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null) await api.setBaseUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final u = api.user;
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Yetu'),
        actions: [
          IconButton(tooltip: 'Server address', icon: const Icon(Icons.settings_ethernet), onPressed: _server),
          if (u == null)
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(api: api))),
              child: const Text('Sign in'),
            )
          else
            PopupMenuButton<String>(
              onSelected: (_) => api.logout(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text('${u.username} · ${u.rating}')),
              ),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Time control (minutes + increment)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < _clocks.length; i++)
            ChoiceChip(
              label: Text('${_clocks[i].$1}+${_clocks[i].$2}'),
              selected: _clock == i,
              onSelected: (_) => setState(() => _clock = i),
            ),
        ]),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Play the computer', style: title),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < _levels.length; i++)
                  ChoiceChip(label: Text(_levels[i]), selected: _level == i, onSelected: (_) => setState(() => _level = i)),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'white', label: Text('White')),
                  ButtonSegment(value: 'random', label: Text('Random')),
                  ButtonSegment(value: 'black', label: Text('Black')),
                ],
                selected: {_color},
                onSelectionChanged: (s) => setState(() => _color = s.first),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _playBot, child: const Text('Play vs computer')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Play online (rated)', style: title),
              const SizedBox(height: 8),
              if (u == null)
                const Text('Sign in to be paired with another player.')
              else if (_searching)
                Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Searching for an opponent…')),
                  TextButton(onPressed: _stopSearch, child: const Text('Cancel')),
                ])
              else
                FilledButton.tonal(onPressed: _busy ? null : _findMatch, child: const Text('Find an opponent')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Play a friend', style: title),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _busy ? null : _friend, child: const Text('Create a game and share the code')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: 'Game code', isDense: true),
                    autocorrect: false,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : _join, child: const Text('Join')),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (u != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PuzzleScreen(api: api))),
                icon: const Icon(Icons.extension),
                label: const Text('Puzzles'),
              ),
            ),
          if (u != null) const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaderboardScreen(api: api))),
              icon: const Icon(Icons.leaderboard),
              label: const Text('Leaderboard'),
            ),
          ),
        ]),
        if (u != null) _History(api: api, key: ValueKey(u.rating)),
        const SizedBox(height: 24),
        const _VersionLabel(),
      ]),
    );
  }
}

class _History extends StatelessWidget {
  final Api api;
  const _History({super.key, required this.api});

  String _outcome(Map g) {
    final r = g['result'];
    if (r == '1/2-1/2') return 'Draw';
    return (r == '1-0') == (g['color'] == 'white') ? 'Won' : 'Lost';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: api.myGames(),
        builder: (context, snap) {
          final games = snap.data ?? const [];
          if (games.isEmpty) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recent games', style: Theme.of(context).textTheme.titleMedium),
              for (final g in games.take(8))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_outcome(g)} · ${(g['reason'] as String).replaceAll('_', ' ')}'),
                  subtitle: Text('${g['moves']} moves as ${g['color']}'),
                  trailing: g['rated'] == true ? Text('${g['delta'] >= 0 ? '+' : ''}${g['delta']}') : null,
                ),
            ]),
          );
        },
      );
}

/// Copies [text] to the clipboard and tells the user.
void copyCode(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
}

/// "Chess Yetu v0.2.0 (2)", read from pubspec.yaml so it always matches the installed build.
class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) => snap.hasData
            ? Center(
                child: Text(
                  'Chess Yetu v${snap.data!.version} (${snap.data!.buildNumber})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : const SizedBox(),
      );
}
