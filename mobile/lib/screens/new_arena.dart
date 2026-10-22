import 'package:flutter/material.dart';

import '../api.dart';

const _timeControls = [(1, 0), (3, 0), (3, 2), (5, 0), (10, 0)];
const _startsIn = [0, 5, 15, 60];
const _durations = [10, 30, 60, 120];

/// Creates an arena and returns its id to the caller.
class NewArenaScreen extends StatefulWidget {
  final Api api;
  const NewArenaScreen({super.key, required this.api});
  @override
  State<NewArenaScreen> createState() => _NewArenaScreenState();
}

class _NewArenaScreenState extends State<NewArenaScreen> {
  final _name = TextEditingController();
  int _tc = 2, _start = 1, _duration = 1;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Give the arena a name of at least 3 letters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.api.createTournament(
        name: name,
        minutes: _timeControls[_tc].$1,
        increment: _timeControls[_tc].$2,
        startsInMin: _startsIn[_start],
        durationMin: _durations[_duration],
      );
      if (mounted) Navigator.pop(context, id);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _choice<T>(String title, List<T> options, int selected, String Function(T) label, ValueChanged<int> onPick) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < options.length; i++)
              ChoiceChip(label: Text(label(options[i])), selected: selected == i, onSelected: (_) => setState(() => onPick(i))),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New arena')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Friday blitz'),
          ),
          _choice('Time control', _timeControls, _tc, (t) => '${t.$1}+${t.$2}', (i) => _tc = i),
          _choice('Starts', _startsIn, _start, (m) => m == 0 ? 'Now' : m < 60 ? 'in $m min' : 'in 1 hour', (i) => _start = i),
          _choice('Lasts', _durations, _duration, (m) => m < 60 ? '$m min' : '${m ~/ 60} h', (i) => _duration = i),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _create, child: const Text('Create arena')),
        ]),
      );
}
