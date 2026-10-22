import 'package:flutter/material.dart';

import 'api.dart';
import 'prefs.dart';
import 'screens/lobby.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.init();
  await Prefs.instance.load();
  runApp(ChessYetuApp(api: api));
}

class ChessYetuApp extends StatelessWidget {
  final Api api;
  const ChessYetuApp({super.key, required this.api});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Chess Yetu',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF8B5E3C),
          scaffoldBackgroundColor: const Color(0xFFF6F1E9),
          useMaterial3: true,
        ),
        home: LobbyScreen(api: api),
      );
}
