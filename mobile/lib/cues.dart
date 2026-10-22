import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';

enum Cue { move, capture, check, end }

/// Move sounds and vibration, each switchable in Settings. Never throws: a device without audio just stays quiet.
class Cues {
  Cues._();
  static final instance = Cues._();

  final Map<Cue, AudioPlayer> _players = {};

  /// Which cue a move in standard notation deserves.
  static Cue forSan(String san) => san.contains('+') || san.contains('#')
      ? Cue.check
      : san.contains('x')
          ? Cue.capture
          : Cue.move;

  Future<void> play(Cue cue) async {
    final p = Prefs.instance;
    try {
      if (p.haptics) {
        switch (cue) {
          case Cue.move:
            await HapticFeedback.selectionClick();
          case Cue.capture:
            await HapticFeedback.lightImpact();
          case Cue.check:
            await HapticFeedback.mediumImpact();
          case Cue.end:
            await HapticFeedback.heavyImpact();
        }
      }
      if (p.sound) {
        final player = _players.putIfAbsent(cue, () => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
        await player.stop();
        await player.play(AssetSource('sounds/${cue.name}.wav'));
      }
    } catch (_) {
      // no audio or vibration hardware: carry on silently
    }
  }
}
