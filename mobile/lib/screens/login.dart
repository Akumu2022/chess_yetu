import 'package:flutter/material.dart';

import '../api.dart';

class LoginScreen extends StatefulWidget {
  final Api api;
  const LoginScreen({super.key, required this.api});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController(), _pw = TextEditingController();
  bool _create = false, _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final f = _create ? widget.api.register : widget.api.login;
      await f(_name.text.trim(), _pw.text);
      if (mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_create ? 'Create an account' : 'Sign in')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Username'), autocorrect: false),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            decoration: InputDecoration(labelText: 'Password', helperText: _create ? 'At least 8 characters' : null),
            obscureText: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_create ? 'Create account' : 'Sign in')),
          TextButton(
            onPressed: () => setState(() => _create = !_create),
            child: Text(_create ? 'I already have an account' : 'Create an account'),
          ),
        ]),
      );
}
