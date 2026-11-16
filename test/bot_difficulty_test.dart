import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/meld.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

Board boardWith(List<(int, int, List<int>)> sets, [int rows = 6]) {
  final bd = Board.empty(rows);
  for (final (row, col, ts) in sets) {
    bd.writeBlock(Block(row, col, ts));
  }
  return bd;
}

BotPlan plan(Board board, List<int> rack, BotLevel level, int seed) =>
    planTurn(board: board, rack: rack, melded: true, firstMeld: 30, level: level, rng: math.Random(seed));

/// Plays every step of [p] and checks the board is valid after every play.
Board playOut(Board board, BotPlan p) {
  var bd = board;
  for (final play in p.plays) {
    bd = applyBotPlay(bd, play);
    expect(bd.isValid, true, reason: 'each play ends with a valid board');
  }
  return bd;
}

/// Eight 3-tile runs on the table (two copies each of red 4-6, blue 8-10, yellow 1-3 and
/// black 10-12) and a rack of 14 tiles that can only go on one at a time (no new sets or
/// groups are possible from the rack): 14 one-move plays, more than Medium's 12.
final manyBoard = boardWith([
  (0, 0, [r(4), r(5), r(6)]),
  (0, 8, [r(4, 1), r(5, 1), r(6, 1)]),
  (1, 0, [b(8), b(9), b(10)]),
  (1, 8, [b(8, 1), b(9, 1), b(10, 1)]),
  (2, 0, [y(1), y(2), y(3)]),
  (2, 8, [y(1, 1), y(2, 1), y(3, 1)]),
  (3, 0, [k(10), k(11), k(12)]),
  (3, 8, [k(10, 1), k(11, 1), k(12, 1)]),
]);
final manyRack = [
  for (final c in [0, 1]) ...[r(3, c), r(7, c), b(7, c), b(11, c), y(4, c), k(9, c), k(13, c)],
];

typedef PlanFn = BotPlan Function();

void main() {
  group('moves', () {
    test('every move type counts as exactly 1 move, with its pacing', () {
      final steps = {
        const BotStep.newSet([1, 2, 3]): BotTuning.newSetMs, // a set from the rack
        const BotStep.extend(4, 1, true): BotTuning.singleTileMs, // a rack tile attached to a set
        const BotStep.tileAt(4, 0, 0): BotTuning.singleTileMs, // a rack tile placed alone
        const BotStep.moveTile(4, toSetTile: 1, index: 0): BotTuning.singleTileMs, // a table tile attached elsewhere
        const BotStep.moveSet(1, toSetTile: 20): BotTuning.splitOrSetMoveMs, // a table set attached / relocated
        const BotStep.split(2): BotTuning.splitOrSetMoveMs, // a split
        const BotStep.removeTile(2): BotTuning.singleTileMs, // a tile removed from a set
      };
      expect(steps.keys.map((s) => s.type).toSet(), BotStepType.values.toSet(), reason: 'all move types covered');
      for (final e in steps.entries) {
        expect(e.key.moveCount, 1, reason: e.key.type.name);
        expect(stepPauseMs(e.key), e.value, reason: e.key.type.name);
      }
      final p = BotPlay([
        const BotStep.newSet([1, 2]),
        const BotStep.moveTile(4, toSetTile: 1, index: 2),
      ]);
      expect(p.moveCount, 2);
      expect(
        BotPlan([
          p,
          BotPlay([const BotStep.split(9), const BotStep.extend(5, 9, false)]),
        ]).moveCount,
        4,
      );
    });

    test('table moves do what they say', () {
      final bd = boardWith([
        (0, 0, [k(1), k(2), k(3), k(4)]),
        (1, 0, [r(7), b(7), y(7)]),
      ]);
      // Move a table tile onto another set.
      final a = applyBotStep(bd, BotStep.moveTile(k(4), toSetTile: r(7), index: 3));
      expect(a.blockOf(k(1))!.tiles, [k(1), k(2), k(3)]);
      expect(a.blockOf(r(7))!.tiles, [r(7), b(7), y(7), k(4)]);
      expect(a.isValid, false, reason: 'k4 does not fit a group of 7s');
      // Remove a tile and set it down alone.
      final c = applyBotStep(bd, BotStep.removeTile(k(4)));
      expect(c.blockOf(k(4))!.tiles, [k(4)]);
      expect(c.blockOf(k(1))!.tiles, [k(1), k(2), k(3)]);
      // Split.
      final d = applyBotStep(bd, BotStep.split(k(3)));
      expect(d.blockOf(k(1))!.tiles, [k(1), k(2)]);
      expect(d.blockOf(k(3))!.tiles, [k(3), k(4)]);
      // Move a whole set to a free spot, keeping its tiles together.
      final e = applyBotStep(bd, BotStep.moveSet(r(7)));
      expect(e.blockOf(r(7))!.tiles, [r(7), b(7), y(7)]);
      expect(e.allTiles.toSet(), bd.allTiles.toSet());
    });
  });

  group('plays', () {
    test('a play can take a spare tile from the table (2 moves)', () {
      final bd = boardWith([
        (0, 0, [k(1), k(2), k(3), k(4)]),
      ]);
      final p = plan(bd, [r(4), b(4)], BotLevel.hard, 1);
      expect(p.plays.length, 1);
      expect(p.moveCount, 2);
      final out = playOut(bd, p);
      expect(
        out.sets.map((s) => s.toSet()).toList(),
        containsAll([
          {k(1), k(2), k(3)},
          {r(4), b(4), k(4)},
        ]),
      );
    });

    test('a play can split a run to fit a rack tile (2 moves)', () {
      final bd = boardWith([
        (0, 0, [r(4), r(5), r(6), r(7), r(8)]),
      ]);
      final p = plan(bd, [r(6, 1)], BotLevel.hard, 1);
      expect(p.moveCount, 2);
      expect(p.steps.first.type, BotStepType.split);
      final out = playOut(bd, p);
      expect(
        out.sets,
        containsAll([
          [r(4), r(5), r(6)],
          [r(6, 1), r(7), r(8)],
        ]),
      );
    });
  });

  group('difficulty', () {
    test('Hard makes every play it finds (no cap, no overlooking)', () {
      for (var seed = 0; seed < 10; seed++) {
        final p = plan(manyBoard, manyRack, BotLevel.hard, seed);
        final out = playOut(manyBoard, p);
        expect(p.tileCount, 14, reason: 'every tile, one play each');
        expect(p.moveCount, greaterThan(12), reason: 'more than Medium may do');
        expect(out.isValid, true);
      }
    });

    test('move caps: Easy at most 6 moves, Medium at most 12', () {
      for (var seed = 0; seed < 40; seed++) {
        final e = plan(manyBoard, manyRack, BotLevel.easy, seed);
        final m = plan(manyBoard, manyRack, BotLevel.medium, seed);
        expect(e.moveCount, lessThanOrEqualTo(BotTuning.moveCap[BotLevel.easy]!));
        expect(m.moveCount, lessThanOrEqualTo(BotTuning.moveCap[BotLevel.medium]!));
        playOut(manyBoard, e);
        playOut(manyBoard, m);
      }
    });

    test('a play that would go over the cap is not started; a smaller one that fits is', () {
      // The best play (most tiles) takes the spare k4 for r4 b4: 2 moves. y8 extends a run: 1 move.
      final bd = boardWith([
        (0, 0, [k(1), k(2), k(3), k(4)]),
        (1, 0, [y(5), y(6), y(7)]),
      ]);
      final rack = [r(4), b(4), y(8)];
      PlanFn capped(int cap) =>
          () => planTurn(board: bd, rack: rack, melded: true, firstMeld: 30, level: BotLevel.hard, rng: math.Random(1), moveCap: cap);
      final one = capped(1)();
      expect(one.moveCount, 1);
      expect(one.steps.single.type, BotStepType.extend, reason: 'the 2-move play does not fit; the 1-move one does');
      final three = capped(3)();
      expect(three.moveCount, 3);
      expect(three.plays.first.moveCount, 2, reason: 'with room, the bigger play goes first');
      final two = capped(2)();
      expect(two.moveCount, 2);
      expect(two.plays.length, 1, reason: 'after the 2-move play no moves are left for y8');
      // Real levels never exceed their caps on a busy table (checked above).
    });

    test('Easy: overlooks plays, but always makes at least 1 when one exists', () {
      final bd = boardWith([
        (0, 0, [k(5), k(6), k(7)]),
      ]);
      for (var seed = 0; seed < 60; seed++) {
        final p = plan(bd, [k(8), r(1), y(12)], BotLevel.easy, seed);
        expect(p.plays.length, greaterThanOrEqualTo(1), reason: 'seed $seed');
      }
      // With many plays it sometimes overlooks some (not always the maximum).
      final made = {for (var seed = 0; seed < 60; seed++) plan(manyBoard, manyRack, BotLevel.easy, seed).plays.length};
      expect(made.every((n) => n >= 1), true);
      expect(made.length, greaterThan(1), reason: 'overlooking varies the number of plays');
    });

    test('Medium: always makes at least min(available, 2) plays', () {
      final two = boardWith([
        (0, 0, [k(5), k(6), k(7)]),
        (1, 0, [r(2), r(3), r(4)]),
      ]);
      for (var seed = 0; seed < 60; seed++) {
        expect(plan(two, [k(8), r(1), y(12)], BotLevel.medium, seed).plays.length, greaterThanOrEqualTo(2), reason: 'seed $seed');
        // Only one play exists: it is made.
        expect(plan(two, [k(8), y(12)], BotLevel.medium, seed).plays.length, 1, reason: 'seed $seed');
        expect(plan(manyBoard, manyRack, BotLevel.medium, seed).plays.length, greaterThanOrEqualTo(2));
      }
      // No play: draw.
      expect(plan(two, [y(12)], BotLevel.medium, 1).draws, true);
    });

    test('same seed, same plan (deterministic with a seeded RNG)', () {
      for (final level in BotLevel.values) {
        final a = plan(manyBoard, manyRack, level, 7), c = plan(manyBoard, manyRack, level, 7);
        expect(a.steps.map((s) => '${s.type}${s.tiles}${s.tile}').toList(), c.steps.map((s) => '${s.type}${s.tiles}${s.tile}').toList());
      }
    });

    test('first meld: one play of rack sets reaching the minimum, within the cap', () {
      for (var seed = 0; seed < 20; seed++) {
        final p = planTurn(
          board: Board.empty(),
          rack: [r(10), r(11), r(12), b(1), b(2), b(3), k(13), y(5)],
          melded: false,
          firstMeld: 30,
          level: BotLevel.easy,
          rng: math.Random(seed),
        );
        expect(p.plays.length, 1, reason: 'Easy still makes its first meld (the floor)');
        expect(p.steps.every((s) => s.isNewSet), true);
        expect(p.steps.fold(0, (n, s) => n + meldPoints(s.tiles)), greaterThanOrEqualTo(30));
      }
    });
  });
}
