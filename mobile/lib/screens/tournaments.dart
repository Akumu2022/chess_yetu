import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import 'game.dart';
import 'new_arena.dart';
import 'profile.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(String iso) {
  final t = DateTime.parse(iso).toLocal();
  return '${t.day} ${_months[t.month - 1]}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(String s) => switch (s) {
      'upcoming' => 'Starts soon',
      'running' => 'Running',
      'finishing' => 'Finishing',
      _ => 'Finished',
    };

class TournamentsScreen extends StatefulWidget {
  final Api api;
  const TournamentsScreen({super.key, required this.api});
  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  late Future<List<dynamic>> _future = widget.api.tournaments();

  Future<void> _create() async {
    final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => NewArenaScreen(api: widget.api)));
    if (!mounted || id == null) return;
    setState(() => _future = widget.api.tournaments());
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(api: widget.api, id: id)));
    if (mounted) setState(() => _future = widget.api.tournaments());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Arenas'), actions: [
          if (widget.api.user != null)
            IconButton(
              tooltip: 'Create an arena',
              icon: const Icon(Icons.add),
              onPressed: _create,
            ),
        ]),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = widget.api.tournaments());
            await _future.catchError((_) => <dynamic>[]);
          },
          child: FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}'))]);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final items = snap.data!;
              if (items.isEmpty) {
                return ListView(children: const [
                  Padding(padding: EdgeInsets.all(24), child: Text('No arenas yet. Tap + to create one.')),
                ]);
              }
              return ListView(children: [
                for (final t in items)
                  ListTile(
                    title: Text(t['name']),
                    subtitle: Text(
                      '${t['minutes']}+${t['increment']}  ·  ${t['duration_min']} min  ·  ${t['players']} players\n'
                      '${_statusLabel(t['status'])}, ${_when(t['starts_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: t['joined'] == true ? const Chip(label: Text('Joined')) : const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentScreen(api: widget.api, id: t['id'])));
                      if (mounted) setState(() => _future = widget.api.tournaments());
                    },
                  ),
              ]);
            },
          ),
        ),
      );
}

class TournamentScreen extends StatefulWidget {
  final Api api;
  final int id;
  const TournamentScreen({super.key, required this.api, required this.id});
  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  Map<String, dynamic>? _t;
  String? _error;
  Timer? _timer;
  bool _busy = false, _inGame = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final t = await widget.api.tournament(widget.id);
      if (!mounted) return;
      setState(() {
        _t = t;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Every 2s while joined: the heartbeat that keeps us in the pool and picks up our next game.
  Future<void> _poll() async {
    if (_inGame || _t == null) return;
    if (++_tick % 5 == 0) _refresh();
    final t = _t!;
    if (t['joined'] != true || (t['status'] != 'running' && t['status'] != 'finishing')) return;
    try {
      final seat = await widget.api.tournamentPoll(widget.id);
      if (seat == null || !mounted || _inGame) return;
      _inGame = true;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(api: widget.api, seat: seat)));
      _inGame = false;
      if (mounted) _refresh();
    } on ApiError {
      // transient: try again on the next tick
    }
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_t!['joined'] == true) {
        await widget.api.leaveTournament(widget.id);
      } else {
        await widget.api.joinTournament(widget.id);
      }
      await _refresh();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: Text(t?['name'] ?? 'Arena')),
      body: t == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                '${t['minutes']}+${t['increment']}  ·  ${t['duration_min']} min  ·  ${_statusLabel(t['status'])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Starts ${_when(t['starts_at'])}  ·  ends ${_when(t['ends_at'])}'),
              if (t['creator'] != null) Text('Created by ${t['creator']}'),
              if (t['winner'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Winner: ${t['winner']}')),
              const SizedBox(height: 12),
              if (widget.api.user == null)
                const Text('Sign in to join.')
              else if (t['status'] != 'finished')
                FilledButton(
                  onPressed: _busy ? null : _toggle,
                  child: Text(t['joined'] == true ? 'Leave arena' : 'Join arena'),
                ),
              if (t['joined'] == true && (t['status'] == 'running' || t['status'] == 'finishing'))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Stay on this screen: you are paired automatically and your game opens by itself.'),
                ),
              const SizedBox(height: 16),
              Text('Standings', style: Theme.of(context).textTheme.titleMedium),
              for (final s in t['standings'] as List)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(width: 28, child: Text('${s['rank']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  title: Text(s['username']),
                  subtitle: Text('${s['wins']}W ${s['draws']}D ${s['losses']}L'),
                  trailing: Text('${s['points']}', style: Theme.of(context).textTheme.titleMedium),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(api: widget.api, username: s['username']))),
                ),
              if ((t['standings'] as List).isEmpty) const Text('Nobody has joined yet.'),
            ]),
    );
  }
}
