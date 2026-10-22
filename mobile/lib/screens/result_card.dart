import 'package:flutter/material.dart';

import '../result.dart';

const _winGreen = Color(0xFF5E8F32), _lossRed = Color(0xFFB23A3A), _drawGrey = Color(0xFF6B7280);

Color outcomeColor(Outcome o) => switch (o) {
      Outcome.win => _winGreen,
      Outcome.loss => _lossRed,
      Outcome.draw => _drawGrey,
    };

IconData _outcomeIcon(Outcome o) => switch (o) {
      Outcome.win => Icons.emoji_events,
      Outcome.loss => Icons.sentiment_dissatisfied,
      Outcome.draw => Icons.handshake_outlined,
    };

/// What the player can do once the game is over. A null callback hides that button.
class ResultActions {
  final VoidCallback? onReview, onRematch, onNew, onLobby;
  final String rematchLabel, newLabel, lobbyLabel;
  const ResultActions({
    this.onReview,
    this.onRematch,
    this.onNew,
    this.onLobby,
    this.rematchLabel = 'Rematch',
    this.newLabel = 'New game',
    this.lobbyLabel = 'Back to lobby',
  });
}

class _Player extends StatelessWidget {
  final String name;
  final int? rating;
  final bool you;
  const _Player({required this.name, this.rating, this.you = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: you ? Theme.of(context).colorScheme.primaryContainer : Colors.grey.shade300,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (rating != null) Text('$rating', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

/// The end-of-game card: big result, reason, both players, rating change and what to do next.
class ResultCard extends StatelessWidget {
  final ResultInfo info;
  final String result;
  final Map<String, dynamic> players;
  final String you;
  final double? ratingDelta;
  final int? ratingNow;
  final ResultActions actions;
  final VoidCallback onClose;

  const ResultCard({
    super.key,
    required this.info,
    required this.result,
    required this.players,
    required this.you,
    required this.actions,
    required this.onClose,
    this.ratingDelta,
    this.ratingNow,
  });

  @override
  Widget build(BuildContext context) {
    final color = outcomeColor(info.outcome);
    final opp = you == 'white' ? 'black' : 'white';
    String name(String c) => (players[c]?['name'] as String?) ?? (c == you ? 'You' : 'Opponent');
    int? rating(String c) => players[c]?['rating'] as int?;
    final a = actions;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .4, end: 1),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Icon(_outcomeIcon(info.outcome), size: 54, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  info.headline,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                if (info.detail.isNotEmpty)
                  Text(info.detail, style: const TextStyle(fontSize: 15, color: Colors.white70)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Player(name: name(you), rating: rating(you), you: true),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(result, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                _Player(name: name(opp), rating: rating(opp)),
              ],
            ),
          ),
          if (ratingDelta != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  Text('Rating', style: Theme.of(context).textTheme.bodySmall),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (ratingNow != null)
                        Text('$ratingNow', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Icon(
                        ratingDelta! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 18,
                        color: ratingDelta! >= 0 ? _winGreen : _lossRed,
                      ),
                      Text(
                        ratingDelta!.abs().toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ratingDelta! >= 0 ? _winGreen : _lossRed,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (a.onReview != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _winGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      onPressed: a.onReview,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Game Review'),
                    ),
                  ),
                if (a.onRematch != null || a.onNew != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (a.onRematch != null)
                        Expanded(child: FilledButton.tonal(onPressed: a.onRematch, child: Text(a.rematchLabel))),
                      if (a.onRematch != null && a.onNew != null) const SizedBox(width: 10),
                      if (a.onNew != null) Expanded(child: FilledButton.tonal(onPressed: a.onNew, child: Text(a.newLabel))),
                    ],
                  ),
                ],
                if (a.onLobby != null) TextButton(onPressed: a.onLobby, child: Text(a.lobbyLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What stays on screen after the card is closed, so the player can still choose what to do next.
class ResultBar extends StatelessWidget {
  final ResultInfo info;
  final ResultActions actions;
  final VoidCallback onShowCard;
  const ResultBar({super.key, required this.info, required this.actions, required this.onShowCard});

  @override
  Widget build(BuildContext context) {
    final a = actions;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          InkWell(
            onTap: onShowCard,
            borderRadius: BorderRadius.circular(20),
            child: Chip(
              avatar: Icon(_outcomeIcon(info.outcome), size: 18, color: Colors.white),
              backgroundColor: outcomeColor(info.outcome),
              label: Text(
                '${info.headline} ${info.detail}'.trim(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (a.onReview != null)
                FilledButton.icon(onPressed: a.onReview, icon: const Icon(Icons.analytics_outlined), label: const Text('Review')),
              if (a.onRematch != null) FilledButton.tonal(onPressed: a.onRematch, child: Text(a.rematchLabel)),
              if (a.onNew != null) FilledButton.tonal(onPressed: a.onNew, child: Text(a.newLabel)),
              if (a.onLobby != null) OutlinedButton(onPressed: a.onLobby, child: Text(a.lobbyLabel)),
            ],
          ),
        ],
      ),
    );
  }
}
