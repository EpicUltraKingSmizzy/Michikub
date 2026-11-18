import 'package:flutter/material.dart';

import '../app/session.dart';
import '../engine/host.dart';
import 'theme.dart';
import 'tiles_view.dart';

/// Round results: who won, round scores, running totals, leftover tiles.
class ResultsOverlay extends StatelessWidget {
  final GameSession session;
  final PlayerView view;
  final VoidCallback onLeave;

  /// Hides the panel so the final table shows (a Show results button brings it back).
  final VoidCallback? onMinimize;

  /// The host: change the players and house rules before the next round.
  final VoidCallback? onChangeLineup;
  const ResultsOverlay({super.key, required this.session, required this.view, required this.onLeave, this.onMinimize, this.onChangeLineup});

  @override
  Widget build(BuildContext context) {
    final r = view.result!;
    final winner = view.seats.firstWhere((s) => s.info.id == r.winnerId).info;
    final rows = [...view.seats]..sort((a, b) => (r.totals[b.info.id] ?? 0) - (r.totals[a.info.id] ?? 0));
    final iWon = r.winnerId == view.me;
    return Container(
      color: const Color(0xCC0B0705),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: MkPanel(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(alignment: Alignment.center, children: [
                Icon(Icons.emoji_events, color: MK.goldLight, size: 34),
                if (onMinimize != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onMinimize,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: const Text('See the table'),
                    ),
                  ),
              ]),
              Text(iWon ? 'You win round ${view.round}!' : '${winner.name} wins round ${view.round}', style: MK.title(24)),
              Text(r.reason == 'out' ? '${winner.name} played every tile.' : 'The pile ran out; the lowest rack wins.',
                  style: MK.body(12, color: MK.gold)),
              const SizedBox(height: 10),
              Table(
                columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(4), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1.2)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(children: [
                    _h('Player'),
                    _h('Left in rack'),
                    _h('Round', right: true),
                    _h('Total', right: true),
                  ]),
                  for (final s in rows)
                    TableRow(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(s.info.name + (s.info.id == view.me ? ' (you)' : ''),
                            style: MK.body(14, weight: s.info.id == r.winnerId ? FontWeight.w800 : FontWeight.w500,
                                color: s.info.id == r.winnerId ? MK.goldLight : MK.creamText)),
                      ),
                      Wrap(spacing: 2, runSpacing: 2, children: [
                        for (final t in (r.racks[s.info.id] ?? const <int>[]).take(16)) TileFace(tile: t, width: 16, height: 22),
                        if ((r.racks[s.info.id]?.length ?? 0) > 16) Text(' +${r.racks[s.info.id]!.length - 16}', style: MK.body(11)),
                      ]),
                      Text(_signed(r.roundScores[s.info.id] ?? 0), textAlign: TextAlign.right, style: MK.body(14, weight: FontWeight.w700)),
                      Text('${r.totals[s.info.id] ?? 0}', textAlign: TextAlign.right, style: MK.body(14, weight: FontWeight.w700, color: MK.goldLight)),
                    ]),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
                if (session.controlsRounds) ...[
                  GoldButton('Next round', icon: Icons.replay, onPressed: session.nextRound),
                  if (onChangeLineup != null)
                    GoldButton('Players & rules', key: const ValueKey('changeLineup'), icon: Icons.tune, onPressed: onChangeLineup),
                ] else
                  Text('Waiting for the host to start the next round…', style: MK.body(13, color: MK.gold)),
                GoldButton('Home', icon: Icons.home, crimson: true, onPressed: onLeave),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  static String _signed(int n) => n > 0 ? '+$n' : '$n';

  Widget _h(String t, {bool right = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left, style: MK.body(11, color: MK.gold, weight: FontWeight.w700)),
      );
}
