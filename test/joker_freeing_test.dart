import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
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

/// The sets on [bd], each sorted (order on the table aside), for easy comparing.
Set<String> setsOf(Board bd) => {for (final s in bd.sets) ([...s]..sort()).join(',')};
String setOf(List<int> tiles) => ([...tiles]..sort()).join(',');

BotPlan plan(Board bd, List<int> rack, {BotLevel level = BotLevel.hard, int seed = 1}) =>
    planTurn(board: bd, rack: rack, melded: true, firstMeld: 30, level: level, rng: math.Random(seed));

Board played(Board bd, BotPlan p) {
  var out = bd;
  for (final play in p.plays) {
    out = applyBotPlay(out, play);
    expect(out.isValid, true);
    expect(out.allTiles.toSet().containsAll(bd.allTiles), true, reason: 'no table tile goes back to a rack');
  }
  return out;
}

void main() {
  group('free tiles', () {
    test('the ends of a run of 4+, not its middle', () {
      final bd = boardWith([(0, 0, [y(4), y(5), y(6), y(7)])]);
      expect(freeTableTiles(bd), unorderedEquals([y(4), y(7)]));
    });

    test('a run of 7: the ends and the middle 6 (3-4-5 and 7-8-9 stay valid)', () {
      final bd = boardWith([(0, 0, [y(3), y(4), y(5), y(6), y(7), y(8), y(9)])]);
      expect(freeTableTiles(bd), unorderedEquals([y(3), y(6), y(9)]));
    });

    test('every tile of a group of 4; none of a group of 3 or a run of 3', () {
      final bd = boardWith([
        (0, 0, [r(4), b(4), k(4), y(4)]),
        (1, 0, [r(9), b(9), k(9)]),
        (2, 0, [y(1), y(2), y(3)]),
      ]);
      expect(freeTableTiles(bd), unorderedEquals([r(4), b(4), k(4), y(4)]));
    });

    test('a joker is never listed as a free tile', () {
      final bd = boardWith([(0, 0, [y(4), y(5), y(6), j])]);
      expect(freeTableTiles(bd), [y(4)]);
    });
  });

  group("freeing a table joker with a free table tile (the user's example)", () {
    // Yellow 4-5-6-7, and blue 4, black 4, joker.
    final bd = boardWith([
      (0, 0, [y(4), y(5), y(6), y(7)]),
      (1, 0, [b(4), k(4), j]),
    ]);

    test('the yellow 4 takes the joker\'s place; the joker makes a new set with two rack tiles', () {
      final p = plan(bd, [r(9), r(10)]);
      expect(p.plays, hasLength(1));
      final steps = p.plays.single.steps;
      expect(steps.first.type, BotStepType.jokerSwap);
      expect(steps.first.tile, y(4));
      expect(steps.first.tableTile, true);
      expect(p.tileCount, 2, reason: 'only rack tiles count');
      final end = played(bd, p);
      expect(setsOf(end), {setOf([y(5), y(6), y(7)]), setOf([b(4), k(4), y(4)]), setOf([r(9), r(10), j])});
    });

    test('easy bots don\'t free a joker with a table tile (they draw here)', () {
      for (var seed = 0; seed < 10; seed++) {
        expect(plan(bd, [r(9), r(10)], level: BotLevel.easy, seed: seed).draws, true);
      }
      expect(findPlays(bd, [r(9), r(10)], freeJokers: false).where((p) => p.reclaimedJokers.isNotEmpty), isEmpty);
    });

    test('medium bots do', () {
      final p = plan(bd, [r(9), r(10)], level: BotLevel.medium);
      expect(p.plays.single.reclaimedJokers, {j});
    });

    test('no swap just to move the joker: without a use for it, the bot draws', () {
      expect(plan(bd, [r(9), b(1)]).draws, true);
    });
  });

  test('the middle 6 of a run of 7 frees a joker in a group of 6s', () {
    final bd = boardWith([
      (0, 0, [y(3), y(4), y(5), y(6), y(7), y(8), y(9)]),
      (1, 0, [b(6), k(6), j]),
    ]);
    final end = played(bd, plan(bd, [r(11), r(12)]));
    expect(setsOf(end), {
      setOf([y(3), y(4), y(5)]),
      setOf([y(7), y(8), y(9)]),
      setOf([b(6), k(6), y(6)]),
      setOf([r(11), r(12), j]),
    });
  });

  test('a tile from a group of 4 frees a joker in a group', () {
    final bd = boardWith([
      (0, 0, [r(8), b(8), k(8), y(8)]),
      (1, 0, [b(8, 1), k(8, 1), j]),
    ]);
    final end = played(bd, plan(bd, [y(1), y(2)]));
    expect(end.sets.where((s) => s.length == 3 && s.every((t) => tileNumber(t) == 8)), hasLength(2));
    expect(end.blockOf(j)!.tiles.toSet(), {y(1), y(2), j});
  });

  group('a joker at the end of a run counts as either end', () {
    // Red 4-5-joker: the joker is a 6 where it lies, but red 3-4-5 is just as good.
    final run = [r(4), r(5), j];

    test('a free 3 from a group of 4 goes on the low end, freeing the joker', () {
      final bd = boardWith([
        (0, 0, run),
        (1, 0, [r(3), b(3), k(3), y(3)]),
      ]);
      final end = played(bd, plan(bd, [b(10), b(11)]));
      expect(setsOf(end), {setOf([r(3), r(4), r(5)]), setOf([b(3), k(3), y(3)]), setOf([b(10), b(11), j])});
    });

    test('a free 6 takes the joker\'s own place', () {
      final bd = boardWith([
        (0, 0, run),
        (1, 0, [r(6), b(6), k(6), y(6)]),
      ]);
      final end = played(bd, plan(bd, [b(10), b(11)]));
      expect(setsOf(end), {setOf([r(4), r(5), r(6)]), setOf([b(6), k(6), y(6)]), setOf([b(10), b(11), j])});
    });

    test('a rack 3 works too (and is played)', () {
      final bd = boardWith([(0, 0, run)]);
      final p = plan(bd, [r(3), b(10), b(11)]);
      final end = played(bd, p);
      expect(setsOf(end), {setOf([r(3), r(4), r(5)]), setOf([b(10), b(11), j])});
      expect(p.tileCount, 3);
    });
  });

  group('bridging a gap with a joker: 3-4-5 + joker + 7', () {
    test('a rack joker and a rack 7', () {
      final bd = boardWith([(0, 0, [y(3), y(4), y(5)])]);
      final plays = findPlays(bd, [j, y(7)]);
      expect(plays.where((p) => p.tileCount == 2 && p.moveCount == 2), isNotEmpty);
      final end = played(bd, plan(bd, [j, y(7)]));
      expect(end.blockOf(y(3))!.tiles, [y(3), y(4), y(5), j, y(7)]);
    });

    test('and in front: joker + 3-4-5 with a rack 1', () {
      final bd = boardWith([(0, 2, [y(3), y(4), y(5)])]);
      final end = played(bd, plan(bd, [y(1), j]));
      expect(end.blockOf(y(3))!.tiles, [y(1), j, y(3), y(4), y(5)]);
    });

    test('a joker freed from the table, then a rack 7', () {
      final bd = boardWith([
        (0, 0, [y(3), y(4), y(5)]),
        (1, 0, [b(9), k(9), j]),
        (2, 0, [r(9), y(9), k(9, 1), b(9, 1)]),
      ]);
      final p = plan(bd, [y(7)]);
      final end = played(bd, p);
      expect(end.blockOf(y(3))!.tiles, [y(3), y(4), y(5), j, y(7)]);
      expect(end.sets.where((s) => s.length == 3 && s.every((t) => tileNumber(t) == 9)), hasLength(2));
      expect(p.tileCount, 1);
    });
  });

  test('no valid swap: nothing can stand in for the joker, so the bot draws', () {
    final bd = boardWith([
      (0, 0, [b(4), k(4), j]),
      (1, 0, [y(5), y(6), y(7)]), // a run of 3: no free tile
      (2, 0, [r(10), r(11), r(12), r(13)]), // free tiles, but no 4s
    ]);
    expect(jokerFreeingPlays(bd, [b(1), k(2)]), isEmpty);
    expect(plan(bd, [b(1), k(2)]).draws, true);
  });

  test('time: a crowded table with 4 jokers and a full rack, all levels', () {
    // 18 sets (many free tiles), 4 table jokers, a 20-tile rack.
    final bd = boardWith([
      (0, 0, [r(1), r(2), r(3), r(4), r(5), r(6), r(7)]),
      (0, 9, [b(1), b(2), b(3), b(4), b(5), b(6), b(7)]),
      (1, 0, [y(1), y(2), y(3), y(4), y(5), y(6), y(7)]),
      (1, 9, [k(1), k(2), k(3), k(4), k(5), k(6), k(7)]),
      (2, 0, [r(8), b(8), k(8), y(8)]),
      (2, 6, [r(9), b(9), k(9), y(9)]),
      (2, 12, [r(10), b(10), k(10), y(10)]),
      (3, 0, [r(11), b(11), j]),
      (3, 5, [k(11), y(11), j + 1]),
      (3, 10, [j + 2, r(12), r(13)]),
      (4, 0, [j + 3, b(12), b(13)]),
      (4, 5, [r(1, 1), b(1, 1), k(1, 1), y(1, 1)]),
      (4, 11, [r(5, 1), r(6, 1), r(7, 1), r(8, 1)]),
      (5, 0, [b(5, 1), b(6, 1), b(7, 1), b(8, 1), b(9, 1)]),
      (5, 7, [y(9, 1), y(10, 1), y(11, 1), y(12, 1)]),
    ], 8);
    final rack = [r(2, 1), r(3, 1), b(2, 1), b(3, 1), y(2, 1), y(3, 1), k(2, 1), k(3, 1), r(10, 1), b(10, 1), y(5, 1), y(6, 1),
      k(12), k(13), y(13), r(4, 1), b(4, 1), k(5, 1), k(6, 1), y(7, 1)];
    expect(bd.invalidBlocks.map((x) => x.tiles.map(tileLabel).join(' ')).toList(), isEmpty);
    expect(bd.allTiles.toSet().length, bd.allTiles.length);
    for (final level in BotLevel.values) {
      final sw = Stopwatch()..start();
      final p = planTurn(board: bd, rack: rack, melded: true, firstMeld: 30, level: level, rng: math.Random(3));
      sw.stop();
      final once = Stopwatch()..start();
      findPlays(bd, rack);
      once.stop();
      // ignore: avoid_print
      print('${level.name}: plan ${sw.elapsedMilliseconds} ms for ${p.plays.length} plays, ${p.tileCount} tiles; one search ${once.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds, lessThan(4000));
      played(bd, p);
    }
  });
}
