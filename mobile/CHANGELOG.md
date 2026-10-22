# Changelog

Versions follow `pubspec.yaml` (`name+build`). Bump both parts for every release, add an entry here,
and tag the commit `mobile-v<version>`. The version is shown at the bottom of the lobby.

## 0.6.0+6
- Create arenas from the app (name, time control, start time, duration).
- Move sounds (move, capture, check, game end) and vibration, each switchable in Settings.
- Test suite grown from 5 to 20 tests: API client, game controller, board, settings and lobby.

## 0.5.0+5
- Arenas (tournaments): list, join or leave, live standings, and automatic pairing that opens your game.
- Player profiles (from the leaderboard or arena standings): rating, rank, record and recent rated games.

## 0.4.0+4
- In-game: move list in standard notation, captured pieces with the material lead, flip-board button.
- "Play again" after a game against the computer or a friend game (same settings).

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
