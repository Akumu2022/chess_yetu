# Changelog

Versions follow `pubspec.yaml` (`name+build`). Bump both parts for every release, add an entry here,
and tag the commit `mobile-v<version>`. The version is shown at the bottom of the lobby.

## 0.8.0+8
- Game over: a result card in the style of the big chess apps. Big "You won!" / "You lost" / "Draw" with the reason
  (checkmate, on time, resignation, agreement, stalemate...), both players with the score, rating change, and buttons
  for Game Review, Rematch or New game, and Back to lobby. Close it to look at the final board; a bar keeps the same options.
- Rated quick match: "New game" goes straight back into the queue. Friend games: both players can start a new game.
- Leaving a game in progress now asks first, since it counts as a resignation.
- 22 board styles in a visual picker: colours, bold, wood-grain (maple, walnut, ebony) and marble (white, onyx, jade),
  an optional framed board with coordinates outside, and 4 piece colour sets.
- Chess pieces now use a bundled font (Noto Sans Symbols 2, SIL OFL) so the pawn never turns into an emoji.

## 0.7.0+7
- Kids and parent portal. Parents: set a PIN, add children (birth year and consent), set daily limits,
  see each child's games, delete a profile, and hand over the device.
- Kids mode replaces the whole app with the kids' lobby (friendly computers, other kids, puzzles, preset phrases
  in games) and survives restarts, even offline. Leaving needs the parent's PIN.
- Fix: the app no longer signs an adult out when the server is merely unreachable at launch.
- Fix: PUT and PATCH requests were sent as POST.
- Fix: the arenas list refresh passed a Future to setState, which Flutter rejects in debug builds.

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
