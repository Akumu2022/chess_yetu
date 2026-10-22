import 'package:flutter/material.dart';

import '../api.dart';
import 'login.dart';

/// Where a parent manages their children's profiles and hands over the device.
class ParentPortalScreen extends StatefulWidget {
  final Api api;
  const ParentPortalScreen({super.key, required this.api});
  @override
  State<ParentPortalScreen> createState() => _ParentPortalScreenState();
}

class _ParentPortalScreenState extends State<ParentPortalScreen> {
  Api get api => widget.api;
  List<Child>? _children;
  bool? _pinSet;
  String? _error;

  @override
  void initState() {
    super.initState();
    api.addListener(_onApi);
    _load();
  }

  @override
  void dispose() {
    api.removeListener(_onApi);
    super.dispose();
  }

  void _onApi() {
    if (api.kid != null && mounted) {
      // the device has been handed over: the app root now shows the kids' lobby
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else if (mounted) {
      setState(() {});
      _load();
    }
  }

  Future<void> _load() async {
    if (api.user == null) return;
    try {
      final results = await Future.wait([api.children(), api.pinIsSet()]);
      if (!mounted) return;
      setState(() {
        _children = results[0] as List<Child>;
        _pinSet = results[1] as bool;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _askText(String title, {String? hint, bool pin = true}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: pin,
          keyboardType: TextInputType.number,
          maxLength: pin ? 6 : 4,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      await _load();
    } on ApiError catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _setPin() async {
    String? current;
    if (_pinSet == true) {
      current = await _askText('Enter your current PIN');
      if (current == null || !mounted) return;
    }
    final pin = await _askText(_pinSet == true ? 'New PIN (4 to 6 digits)' : 'Choose a PIN (4 to 6 digits)');
    if (pin == null) return;
    await _run(() async {
      await api.setPin(pin, current: current);
      if (mounted) _toast('PIN saved');
    });
  }

  Future<void> _addChild() async {
    final year = DateTime.now().year;
    final text = await _askText('Birth year of your child', hint: 'e.g. ${year - 8}', pin: false);
    final birth = int.tryParse(text ?? '');
    if (birth == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Parent or guardian consent'),
        content: const Text(
          'I am this child\'s parent or guardian and I agree to create a profile for them. '
          'It uses a generated nickname and their birth year only. I can delete it at any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I agree')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => api.createChild(birth));
  }

  Future<void> _handOver(Child c) async {
    if (_pinSet != true) {
      _toast('Set a parent PIN first. It is needed to leave kids mode.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hand the device to ${c.nickname}?'),
        content: const Text('The app will show only kids\' features until you enter your PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => api.startKidSession(c.id));
  }

  Future<void> _delete(Child c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${c.nickname}?'),
        content: const Text('This erases the profile and all of their games and puzzle progress. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete everything')),
        ],
      ),
    );
    if (ok == true) await _run(() => api.deleteChild(c.id));
  }

  Future<void> _games(Child c) async {
    try {
      final games = await api.childGames(c.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (_) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('${c.nickname}\'s games', style: Theme.of(context).textTheme.titleMedium),
          if (games.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No games yet.')),
          for (final g in games)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_outcome(g)} vs ${g['opponent']}'),
              subtitle: Text('${g['moves']} moves, ${g['minutes']} min'),
            ),
        ]),
      );
    } on ApiError catch (e) {
      _toast(e.message);
    }
  }

  String _outcome(Map g) {
    if (g['result'] == '1/2-1/2') return 'Draw';
    return (g['result'] == '1-0') == (g['color'] == 'white') ? 'Won' : 'Lost';
  }

  Widget _childCard(Child c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.nickname, style: Theme.of(context).textTheme.titleMedium),
            Text('Rating ${c.rating}  ·  ${c.games} games  ·  ${c.minutesToday} of ${c.dailyLimitMin} min used today'),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Daily limit'),
              IconButton(
                tooltip: 'Less time',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: c.dailyLimitMin <= 10 ? null : () => _run(() => api.setDailyLimit(c.id, c.dailyLimitMin - 10)),
              ),
              Text('${c.dailyLimitMin} min'),
              IconButton(
                tooltip: 'More time',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: c.dailyLimitMin >= 240 ? null : () => _run(() => api.setDailyLimit(c.id, c.dailyLimitMin + 10)),
              ),
            ]),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: () => _handOver(c), child: const Text('Hand over device')),
              OutlinedButton(onPressed: () => _games(c), child: const Text('Games')),
              TextButton(onPressed: () => _delete(c), child: const Text('Delete')),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final signedIn = api.user != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Chess for kids')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('For parents and schools', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• You create the profile and stay in control. Children get a generated nickname, never a real name.'),
              Text('• Kids only play other kids and friendly computers. The only chat is preset messages like "Good game!".'),
              Text('• Set a daily time limit, see every game, and delete everything at any time.'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (!signedIn)
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(api: api))),
            child: const Text('Sign in or create a parent account'),
          )
        else ...[
          Text('Signed in as ${api.user!.username}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _setPin,
            icon: const Icon(Icons.lock_outline),
            label: Text(_pinSet == true ? 'Change parent PIN' : 'Set a parent PIN (required)'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _addChild, icon: const Icon(Icons.child_care), label: const Text('Add a child')),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          const SizedBox(height: 8),
          if (_children == null && _error == null) const Center(child: CircularProgressIndicator()),
          for (final c in _children ?? const <Child>[]) _childCard(c),
        ],
      ]),
    );
  }
}
