# Changelog

Versions follow `pubspec.yaml` (`name+build`). Bump both parts for every release, add an entry here,
and tag the commit `mobile-v<version>`. The version is shown at the bottom of the lobby.

## 0.3.0+3
- Game review: step through any finished game from the recent-games list; run Stockfish analysis for per-move grades,
  best moves and accuracy.
- Settings: board colours, move dots, last-move highlight and coordinates, saved on the device.

## 0.2.0+2
- Daily mate puzzles with streak and daily progress (signed-in players).
- Leaderboard screen.
- App version shown in the lobby.

## 0.1.0+1
- First release: sign in / create account, guest play.
- Play the computer (5 levels), play a friend by game code, rated quick match.
- Live board over the game websocket: clocks, promotion, resign, draw offers, automatic reconnect.
