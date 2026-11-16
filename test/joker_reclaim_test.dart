import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
const j = kJokerBase;

Board boardWith(List<(int, int, List<int>)> sets, [int rows = 6]) {
  final bd = Board.empty(rows);
  for (final (row, col, ts) in sets) {
    bd.writeBlock(Block(row, col, ts));
  }
  return bd;
}

void main() {
  // Red 4, joker (as red 5), red 6 on the table.
  final start = boardWith([
    (0, 0, [r(4), j, r(6)]),
  ]);

  group('swap', () {
    test('the tile the joker stands for takes its exact spot', () {
      final out = Layout.swapJoker(start, r(5), j)!;
      expect(out.rows[0].sublist(0, 3), [r(4), r(5), r(6)]);
      expect(out.find(j), isNull);
    });
    test('a tile that would not fit is refused', () {
      expect(Layout.swapJoker(start, r(7), j), isNull);
      expect(Layout.swapJoker(start, b(5), j), isNull);
    });
    test('in a group of 3 with a joker, either missing colour works', () {
      final g = boardWith([
        (0, 0, [r(9), b(9), j]),
      ]);
      expect(Layout.swapJoker(g, y(9), j), isNotNull);
      expect(Layout.swapJoker(g, k(9), j), isNotNull);
      expect(Layout.swapJoker(g, r(9, 1), j), isNull);
    });
  });

  group('rules', () {
    const rules = HouseRules();
    test('a reclaimed joker must be played again the same turn', () {
      final swapped = Layout.swapJoker(start, r(5), j)!;
      final err = checkTurn(start: start, proposed: swapped, rack: [r(5)], melded: true, rules: rules);
      expect(err, 'Play the joker you took back before ending your turn.');
    });
    test('swap + joker played elsewhere is a legal turn', () {
      var bd = Layout.swapJoker(start, r(5), j)!;
      bd = Layout.place(bd, [b(1), b(2), j], 2, 0, merge: false);
      expect(checkTurn(start: start, proposed: bd, rack: [r(5), b(1), b(2)], melded: true, rules: rules), isNull);
    });
    test('not before the first meld', () {
      var bd = Layout.swapJoker(start, r(5), j)!;
      bd = Layout.place(bd, [b(10), b(11), b(12), j], 2, 0, merge: false);
      expect(checkTurn(start: start, proposed: bd, rack: [r(5), b(10), b(11), b(12)], melded: false, rules: rules), isNotNull);
    });
    test('the host accepts a preview with the joker in hand, but not the commit', () {
      final h =
          GameHost(
              players: const [PlayerInfo('a', 'Ann', SeatKind.human), PlayerInfo('b', 'Bob', SeatKind.human)],
              rules: const HouseRules(turnSeconds: 0),
              seed: 1,
            )
            ..firstStarter = 0
            ..startRound();
      h.board = start.copy();
      h.turnStart = start.copy();
      h.racks['a'] = [r(5), b(1), b(2), k(13)];
      h.melded.add('a');
      final swapped = Layout.swapJoker(start, r(5), j)!;
      expect(h.handle('a', PreviewAction(swapped)).ok, true);
      expect(h.handle('a', CommitAction(swapped)).ok, false);
      // A missing non-joker table tile is still refused.
      final lost = start.copy()..removeTiles([r(4)]);
      expect(h.handle('a', PreviewAction(lost)).ok, false);
      final done = Layout.place(swapped, [b(1), b(2), j], 2, 0, merge: false);
      expect(h.handle('a', CommitAction(done)).ok, true);
      expect(h.racks['a'], [k(13)]);
      h.dispose();
    });
  });

  group('bots', () {
    test('bots find a joker reclaim (2 moves) and play the joker again', () {
      final plays = findPlays(start, [r(5), b(1), b(2)]);
      final reclaim = plays.where((p) => p.reclaimedJokers.contains(j)).toList();
      expect(reclaim, isNotEmpty);
      for (final p in reclaim) {
        expect(p.moveCount, 2);
        final end = applyBotPlay(start, p);
        expect(end.isValid, true);
        expect(end.allTiles.toSet().containsAll(start.allTiles), true);
      }
      // r5 + (b1 b2 joker): 3 rack tiles; the joker doesn't count as a rack tile.
      final best = reclaim.reduce((a, c) => a.tileCount >= c.tileCount ? a : c);
      expect(best.tileCount, 3);
    });
    test('a Hard bot uses it, and every play ends with every table tile on the table', () {
      final p = planTurn(
        board: start,
        rack: [r(5), b(1), b(2), k(13)],
        melded: true,
        firstMeld: 30,
        level: BotLevel.hard,
        rng: math.Random(1),
      );
      expect(p.plays.any((x) => x.reclaimedJokers.isNotEmpty), true);
      var bd = start;
      for (final play in p.plays) {
        expect(playStaysValid(bd, play) || play.reclaimedJokers.isNotEmpty, true);
        bd = applyBotPlay(bd, play);
        expect(bd.isValid, true);
        expect(bd.allTiles.toSet().containsAll(start.allTiles), true);
      }
    });
    test('the safe-zone check treats a joker in hand as not committable', () {
      const play = BotPlay([]);
      expect(playStaysValid(start, play), true);
      final reclaim = findPlays(start, [r(5), b(1), b(2)]).firstWhere((p) => p.reclaimedJokers.isNotEmpty);
      expect(playStaysValid(start, reclaim), false);
    });
    test('no reclaim before the first meld', () {
      final p = planTurn(
        board: start,
        rack: [r(5), b(10), b(11), b(12)],
        melded: false,
        firstMeld: 30,
        level: BotLevel.hard,
        rng: math.Random(1),
      );
      expect(p.plays.any((x) => x.reclaimedJokers.isNotEmpty), false);
    });
  });
}
