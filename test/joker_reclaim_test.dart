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

  group('bots (honest moves; the joker never leaves the table)', () {
    /// The best reclaim play the bot finds, checked: ends valid, every table tile still on the
    /// table, the joker in a valid set, and only rack tiles (never the joker) counted.
    BotPlay bestReclaim(Board board, List<int> rack, int joker) {
      final plays = findPlays(board, rack).where((p) => p.reclaimedJokers.contains(joker)).toList();
      expect(plays, isNotEmpty, reason: 'a reclaim is found');
      for (final p in plays) {
        var bd = board;
        for (final st in p.steps) {
          bd = applyBotStep(bd, st);
          expect(bd.find(joker), isNotNull, reason: 'the joker stays on the table at every move');
        }
        expect(bd.isValid, true);
        expect(bd.allTiles.toSet().containsAll(board.allTiles), true);
        expect(p.rackTiles.any(isJoker), false);
      }
      plays.sort((x, y) => x.tileCount != y.tileCount ? y.tileCount - x.tileCount : x.moveCount - y.moveCount);
      return plays.first;
    }

    test('(a) group 6-6-J + the missing-colour 6 and 10-11 in the rack: 6 added, J-10-11 played (3 moves)', () {
      final bd = boardWith([
        (0, 0, [r(6), b(6), j]),
      ]);
      final p = bestReclaim(bd, [y(6), k(10), k(11)], j);
      expect(p.moveCount, 3);
      expect(p.tileCount, 3);
      expect(p.steps.map((s) => s.type).toList(), [BotStepType.newSet, BotStepType.moveTile, BotStepType.extend]);
      final end = applyBotPlay(bd, p);
      final sets = end.sets.map((s) => s.toSet()).toList();
      expect(sets.any((s) => s.length == 3 && s.containsAll([r(6), b(6), y(6)])), true);
      expect(sets.any((s) => s.containsAll([k(10), k(11), j]) && s.length == 3), true);
    });

    test('(b) run 7-8-J-10 + the matching 9: J taken out, 9 put in its place, J completes a rack set (3 moves)', () {
      final bd = boardWith([
        (0, 0, [r(7), r(8), j, r(10)]),
      ]);
      final p = bestReclaim(bd, [r(9), b(3), b(4), k(13)], j);
      expect(p.moveCount, 3);
      expect(p.tileCount, 3);
      final end = applyBotPlay(bd, p);
      expect(end.blockOf(r(7))!.tiles, [r(7), r(8), r(9), r(10)], reason: 'the run is rejoined in place');
      expect(end.blockOf(j)!.tiles.toSet(), {b(3), b(4), j});
    });

    test('(b) with a spare table set the joker can join instead: 2 moves', () {
      final bd = boardWith([
        (0, 0, [r(7), r(8), j, r(10)]),
        (2, 0, [k(1), k(2), k(3)]),
      ]);
      final p = bestReclaim(bd, [r(9)], j);
      expect(p.moveCount, 2);
      final end = applyBotPlay(bd, p);
      expect(end.blockOf(r(7))!.tiles, [r(7), r(8), r(9), r(10)]);
      expect(end.blockOf(j)!.tiles, [k(1), k(2), k(3), j]);
    });

    test('(c) a joker at either end of a run works the same way', () {
      for (final (tiles, t) in [
        ([r(7), r(8), r(9), j], r(10)),
        ([j, r(8), r(9), r(10)], r(7)),
      ]) {
        final bd = boardWith([
          (0, 2, tiles),
        ]);
        final p = bestReclaim(bd, [t, b(3), b(4)], j);
        expect(p.moveCount, 3);
        final end = applyBotPlay(bd, p);
        expect(end.blockOf(r(8))!.tiles, [r(7), r(8), r(9), r(10)]);
      }
    });

    test('planned turns use it within every move cap, never leaving the joker in a rack', () {
      final bd = boardWith([
        (0, 0, [r(6), b(6), j]),
        (1, 0, [r(7, 1), r(8, 1), j + 1, r(10, 1)]),
      ]);
      final rack = [y(6), k(10), k(11), r(9, 1), b(3), b(4)];
      for (final level in BotLevel.values) {
        for (var seed = 0; seed < 30; seed++) {
          final p = planTurn(board: bd, rack: rack, melded: true, firstMeld: 30, level: level, rng: math.Random(seed));
          final cap = BotTuning.moveCap[level];
          if (cap != null) expect(p.moveCount, lessThanOrEqualTo(cap));
          var b2 = bd;
          for (final play in p.plays) {
            b2 = applyBotPlay(b2, play);
            expect(b2.isValid, true);
            expect(b2.allTiles.toSet().containsAll(bd.allTiles), true);
          }
          if (level == BotLevel.hard) expect(p.plays.where((x) => x.reclaimedJokers.isNotEmpty).length, 2);
        }
      }
    });

    test('the safe-zone check: a reclaim passes through an invalid table, so it is not started late', () {
      final bd = boardWith([
        (0, 0, [r(7), r(8), j, r(10)]),
      ]);
      final p = findPlays(bd, [r(9), b(3), b(4)]).firstWhere((p) => p.reclaimedJokers.isNotEmpty);
      expect(playStaysValid(bd, p), false);
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
