import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'api.dart';
import 'prefs.dart';
import 'screens/kid_lobby.dart';
import 'screens/lobby.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans Symbols 2 (chess piece glyphs)',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
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
    // While a child's session is active the whole app is the kids' lobby, so nothing else is reachable.
    home: ListenableBuilder(
      listenable: api,
      builder: (_, _) => api.kid != null ? KidLobbyScreen(api: api) : LobbyScreen(api: api),
    ),
  );
}
