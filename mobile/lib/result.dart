enum Outcome { win, loss, draw }

/// How a finished game reads from one player's point of view.
class ResultInfo {
  final Outcome outcome;
  final String headline, detail;
  const ResultInfo(this.outcome, this.headline, this.detail);
}

/// Words for the end-of-game reasons the server reports.
String reasonText(String? reason) => switch (reason) {
      'checkmate' => 'by checkmate',
      'timeout' => 'on time',
      'resignation' => 'by resignation',
      'agreement' => 'by agreement',
      'stalemate' => 'by stalemate',
      'insufficient_material' => 'by insufficient material',
      'repetition' => 'by repetition',
      'fifty_moves' => 'by the 50-move rule',
      'abandoned' => 'game abandoned',
      null || '' => '',
      final other => other.replaceAll('_', ' '),
    };

/// [result] is "1-0", "0-1" or "1/2-1/2"; [you] is "white" or "black".
ResultInfo describeResult({required String you, required String? result, required String? reason, bool kids = false}) {
  final Outcome outcome;
  if (result == '1/2-1/2') {
    outcome = Outcome.draw;
  } else {
    outcome = (result == '1-0') == (you == 'white') ? Outcome.win : Outcome.loss;
  }
  final String headline;
  if (kids) {
    headline = switch (outcome) {
      Outcome.win => 'You won! 🎉',
      Outcome.loss => 'Good game!',
      Outcome.draw => "It's a draw!",
    };
  } else {
    headline = switch (outcome) {
      Outcome.win => 'You won!',
      Outcome.loss => 'You lost',
      Outcome.draw => 'Draw',
    };
  }
  return ResultInfo(outcome, headline, reasonText(reason));
}
