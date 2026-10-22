import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import 'game.dart';
import 'puzzle.dart';
import 'settings.dart';

const _pals = [
  (1, 'Zuri the Gentle', 'Just learning'),
  (2, 'Simba the Brave', 'A fair fight'),
  (3, 'Mzee Kobe the Wise', 'A real test'),
];

/// The only screen a child sees: friendly computers, other kids, puzzles. Leaving needs the parent's PIN.
class KidLobbyScreen extends StatefulWidget {
  final Api api;
  const KidLobbyScreen({super.key, required this.api});
  @override
  State<KidLobbyScreen> createState() => _KidLobbyScreenState();
}

class _KidLobbyScreenState extends State<KidLobbyScreen> {
  Api get api => widget.api;
  bool _busy = false, _searching = false;
  Timer? _poll;
  Future<List<dynamic>>? _history;

  @override
  void initState() {
    super.initState();
    api.addListener(_changed);
    _refresh();
  }

  @override
  void dispose() {
    api.removeListener(_changed);
    _poll?.cancel();
    if (_searching) api.leaveKidQueue().catchError((_) {});
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      await api.refreshUser(); // fresh rating and time left
    } on ApiError catch (e) {
      if (e.status == 401) await api.logout(); // the session ended: back to the normal app
    }
    if (mounted) {
      setState(() {
        _history = api.kidGames();
      });
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(Seat seat, {Future<(Seat, String?)> Function()? again, bool canSearch = false}) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(api: api, seat: seat, again: again, canSearch: canSearch),
      ),
    );
    if (result == 'search' && mounted) {
      await _findKid(); // "New game" after a match: look for another kid straight away
      return;
    }
    if (mounted) await _refresh();
  }

  Future<void> _guard(Future<void> Function() f) async {
    setState(() {
      _busy = true;
    });
    try {
      await f();
    } on ApiError catch (e) {
      if (!mounted) return;
      _toast(e.message);
      if (e.status == 401) {
        await api.logout();
      } else {
        _refresh(); // e.g. "Time's up" changes what we show
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _playPal(int bot) => _guard(() async {
    Future<(Seat, String?)> start() async => (await api.newKidBotGame(bot: bot, color: 'random'), null);
    await _open((await start()).$1, again: start);
  });

  Future<void> _findKid() => _guard(() async {
    final seat = await api.joinKidQueue();
    if (seat != null) return _open(seat, canSearch: true);
    setState(() {
      _searching = true;
    });
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final s = await api.pollKidQueue();
        if (s != null) {
          _stopSearch(leave: false);
          if (mounted) _open(s, canSearch: true);
        }
      } on ApiError {
        _stopSearch(leave: false);
      }
    });
  });

  void _stopSearch({bool leave = true}) {
    _poll?.cancel();
    _poll = null;
    if (leave) api.leaveKidQueue().catchError((_) {});
    if (mounted) {
      setState(() {
        _searching = false;
      });
    }
  }

  Future<void> _grownUpExit() async {
    final c = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Grown-ups only'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the parent PIN to leave kids mode.'),
              TextField(
                controller: c,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
              ),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await api.exitKidsMode(c.text);
                  if (context.mounted) Navigator.pop(context);
                } on ApiError catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Leave'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = api.kid;
    if (k == null) return const SizedBox();
    final out = k.minutesLeft <= 0;
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: Text('${k.nickname} · ${k.rating}'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          IconButton(tooltip: 'Grown-ups', icon: const Icon(Icons.lock_outline), onPressed: _grownUpExit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: out ? Theme.of(context).colorScheme.errorContainer : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  out ? "Time's up for today! Come back tomorrow." : '${k.minutesLeft} minutes left today',
                  textAlign: TextAlign.center,
                  style: title,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Play a friendly computer', style: title),
            for (final p in _pals)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pets),
                  title: Text(p.$2),
                  subtitle: Text(p.$3),
                  trailing: const Icon(Icons.play_arrow),
                  enabled: !out && !_busy,
                  onTap: () => _playPal(p.$1),
                ),
              ),
            const SizedBox(height: 8),
            Text('Play another kid', style: title),
            const SizedBox(height: 8),
            if (_searching)
              Row(
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Looking for a friend…')),
                  TextButton(onPressed: _stopSearch, child: const Text('Cancel')),
                ],
              )
            else
              FilledButton.tonal(onPressed: out || _busy ? null : _findKid, child: const Text('Find a friend to play')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PuzzleScreen(api: api))),
              icon: const Icon(Icons.extension),
              label: const Text('Puzzles'),
            ),
            FutureBuilder<List<dynamic>>(
              future: _history,
              builder: (context, snap) {
                final games = snap.data ?? const [];
                if (games.isEmpty) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My games', style: title),
                      for (final g in games.take(8))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${_outcome(g)} vs ${g['opponent']}'),
                          subtitle: Text('${g['moves']} moves'),
                          trailing: g['rated'] == true ? Text('${g['delta'] >= 0 ? '+' : ''}${g['delta']}') : null,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _outcome(Map g) {
    if (g['result'] == '1/2-1/2') return 'Draw';
    return (g['result'] == '1-0') == (g['color'] == 'white') ? 'Won' : 'Lost';
  }
}
