import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/meld.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
final j0 = makeJoker(0), j1 = makeJoker(1);

Board boardWith(List<(int, int, List<int>)> sets, [int rows = 6]) {
  final bd = Board.empty(rows);
  for (final (row, col, ts) in sets) {
    bd.writeBlock(Block(row, col, ts));
  }
  return bd;
}

void main() {
  group('tiles', () {
    test('ids round-trip', () {
      for (final c in TileColor.values) {
        for (var n = 1; n <= 13; n++) {
          for (var cp = 0; cp < 2; cp++) {
            final t = makeTile(c, n, copy: cp);
            expect(tileColor(t), c);
            expect(tileNumber(t), n);
            expect(isJoker(t), false);
          }
        }
      }
      expect(fullSet(2).length, 106);
      expect(fullSet(4).length, 108);
      expect(tileColor(makeJoker(2)), TileColor.yellow);
      expect(tileColor(makeJoker(3)), TileColor.blue);
    });
  });

  group('melds', () {
    test('runs', () {
      expect(isValidMeld([r(3), r(4), r(5)]), true);
      expect(meldPoints([r(3), r(4), r(5)]), 12);
      expect(isValidMeld([r(3), r(5), r(4)]), false, reason: 'must ascend');
      expect(isValidMeld([r(3), b(4), r(5)]), false);
      expect(isValidMeld([r(12), r(13), j0]), false, reason: 'no 14');
      expect(isValidMeld([r(1), r(2)]), false, reason: 'too short');
      expect(isValidMeld([for (var n = 1; n <= 13; n++) r(n)]), true);
    });
    test('runs with jokers', () {
      expect(isValidMeld([r(3), j0, r(5)]), true);
      expect(meldPoints([r(3), j0, r(5)]), 12);
      expect(meldPoints([j0, r(5), r(6)]), 15);
      expect(isValidMeld([j0, r(1), r(2)]), false, reason: 'no 0');
    });
    test('groups', () {
      expect(isValidMeld([r(7), b(7), k(7)]), true);
      expect(meldPoints([r(7), b(7), k(7), y(7)]), 28);
      expect(isValidMeld([r(7), r(7, 1), k(7)]), false, reason: 'duplicate colour');
      expect(isValidMeld([r(7), b(7), k(7), y(7), j0]), false, reason: 'max 4');
      expect(isValidMeld([r(7), j0, k(7)]), true);
    });
    test('joker-only sets are not allowed', () {
      expect(isValidMeld([j0, j1, makeJoker(2)]), false);
    });
    test('ambiguous joker set takes the higher reading', () {
      expect(meldPoints([r(5), j0, j1]), 18); // run 5-6-7 beats group 15
    });
    test('compatibility', () {
      expect(isCompatible([r(5), r(6)]), true);
      expect(isCompatible([r(5), b(5)]), true);
      expect(isCompatible([r(5), r(7)]), false);
      expect(isCompatible([r(5), j0, r(7)]), true);
      expect(isCompatible([r(13), r(1)]), false);
    });
  });

  group('layout', () {
    test('dropping beside a compatible set joins it', () {
      final bd = boardWith([(0, 2, [r(3), r(4), r(5)])]);
      final out = Layout.place(bd, [r(6)], 0, 5);
      expect(out.blocksInRow(0).single.tiles, [r(3), r(4), r(5), r(6)]);
    });
    test('dropping beside an incompatible set pushes it 1 space aside', () {
      final bd = boardWith([(0, 5, [r(3), r(4), r(5)])]);
      final out = Layout.place(bd, [b(9)], 0, 4);
      final bl = out.blocksInRow(0);
      expect(bl.length, 2);
      expect(bl[0].tiles, [b(9)]);
      expect(bl[0].start, 4, reason: 'tile lands where dropped');
      expect(bl[1].start, 6, reason: 'set moved 1 aside to keep a gap');
    });
    test('dropping onto a set inserts into it', () {
      final bd = boardWith([(1, 0, [r(3), r(5), r(6)])]);
      final out = Layout.place(bd, [r(4)], 1, 1);
      expect(out.blocksInRow(1).single.tiles, [r(3), r(4), r(5), r(6)]);
    });
    test('insertInto at the right edge slides the set left', () {
      final bd = boardWith([(0, 24, [r(3), r(4), r(5)])]);
      final out = Layout.insertInto(bd, [r(6)], r(3), 3);
      final bl = out.blocksInRow(0).single;
      expect(bl.tiles, [r(3), r(4), r(5), r(6)]);
      expect(bl.end, 27);
    });
    test('split leaves a 1-space gap', () {
      final bd = boardWith([(0, 0, [r(1), r(2), r(3), r(4), r(5), r(6)])]);
      final out = Layout.split(bd, r(4));
      final bl = out.blocksInRow(0);
      expect(bl.map((x) => x.tiles), [
        [r(1), r(2), r(3)],
        [r(4), r(5), r(6)]
      ]);
      expect(bl[1].start - bl[0].end, 1);
    });
    test('sets never touch after any placement', () {
      final rng = math.Random(3);
      var bd = Board.empty();
      final tiles = fullSet(2)..shuffle(rng);
      for (var i = 0; i < 80; i++) {
        bd = Layout.place(bd, [tiles[i]], rng.nextInt(6), rng.nextInt(27), merge: rng.nextBool());
        expect(bd.allTiles.length, i + 1);
        for (var row = 0; row < bd.rowCount; row++) {
          expect(bd.rows[row].length, 27);
        }
      }
    });
    test('full row: the smaller neighbour moves out', () {
      // Row 0 uses 20 of 27 spaces; drop a 13-run between two sets.
      final run13 = [for (var n = 1; n <= 13; n++) b(n, 1)];
      final bd = boardWith([
        (0, 0, [r(1), r(2), r(3), r(4), r(5), r(6)]), // 6 long
        (0, 7, [k(1), k(2), k(3)]), // 3 long
        (0, 11, [y(1), y(2), y(3), y(4), y(5), y(6), y(7), y(8), y(9)]), // 9 long, ends at 20
        (1, 0, [r(9), b(9), k(9)]),
        (2, 0, [r(10), b(10), k(10)]),
      ]);
      final out = Layout.place(bd, run13, 0, 10, merge: false);
      final row0 = out.blocksInRow(0);
      final total = row0.fold<int>(0, (s, x) => s + x.length) + row0.length - 1;
      expect(total <= 27, true);
      expect(row0.any((x) => x.tiles.length == 13), true);
      expect(out.allTiles.toSet(), bd.allTiles.toSet()..addAll(run13));
      expect(out.isValid, true, reason: '\n$out\n${out.blocks.map((x)=>x.tiles.map(tileLabel).join(" ")).join("\n")}');
    });
    test('never blocked: a full board grows a row', () {
      final bd = Board.empty(1);
      bd.writeBlock(Block(0, 0, [for (var n = 1; n <= 13; n++) r(n)]));
      bd.writeBlock(Block(0, 14, [for (var n = 1; n <= 13; n++) b(n)]));
      final out = Layout.place(bd, [k(1), k(2), k(3)], 0, 13, merge: false);
      expect(out.rowCount, 2);
      expect(out.allTiles.length, 29);
    });
    test('make space opens a row and refuses when one already exists', () {
      final bd = boardWith([
        (0, 0, [r(1), r(2), r(3)]),
        (1, 0, [b(1), b(2), b(3)]),
        (2, 0, [k(1), k(2), k(3)]),
      ]);
      final out = Layout.makeSpace(bd)!;
      expect(out.rowCount, 7, reason: 'top row was at the edge: zoom out');
      expect(out.isEmptyRow(2), true);
      expect(Layout.makeSpace(out), isNull);
      final bd2 = boardWith([
        (2, 0, [r(1), r(2), r(3)]),
        (3, 0, [b(1), b(2), b(3)]),
        (4, 0, [k(1), k(2), k(3)]),
        (5, 0, [y(1), y(2), y(3)]),
      ]);
      final out2 = Layout.makeSpace(bd2)!;
      expect(out2.rowCount, 6);
      expect(out2.blocksInRow(1).single.tiles, [r(1), r(2), r(3)]);
      expect(out2.blocksInRow(2).single.tiles, [b(1), b(2), b(3)]);
      expect(out2.isEmptyRow(3), true);
      expect(out2.blocksInRow(4).single.tiles, [k(1), k(2), k(3)]);
    });
  });

  group('turn checks', () {
    const rules = HouseRules();
    test('first meld needs 30 points from the rack', () {
      final start = Board.empty();
      final rack = [r(10), r(11), r(12), b(1), b(2), b(3)];
      final low = boardWith([(0, 0, [b(1), b(2), b(3)])]);
      expect(checkTurn(start: start, proposed: low, rack: rack, melded: false, rules: rules), contains('30'));
      final ok = boardWith([(0, 0, [r(10), r(11), r(12)])]);
      expect(checkTurn(start: start, proposed: ok, rack: rack, melded: false, rules: rules), isNull);
      expect(checkTurn(start: start, proposed: low, rack: rack, melded: true, rules: rules), isNull);
      expect(
          checkTurn(start: start, proposed: low, rack: rack, melded: false, rules: rules.copyWith(firstMeld: 0)),
          isNull);
    });
    test('cannot touch the table before the first meld', () {
      final start = boardWith([(0, 0, [k(5), k(6), k(7)])]);
      final rack = [k(8), r(10), b(10), y(10)];
      final extended = boardWith([(0, 0, [k(5), k(6), k(7), k(8)]), (1, 0, [r(10), b(10), y(10)])]);
      expect(checkTurn(start: start, proposed: extended, rack: rack, melded: false, rules: rules), isNotNull);
      expect(checkTurn(start: start, proposed: extended, rack: rack, melded: true, rules: rules), isNull);
    });
    test('table tiles cannot be taken back', () {
      final start = boardWith([(0, 0, [k(5), k(6), k(7), k(8)])]);
      final proposed = boardWith([(0, 0, [k(5), k(6), k(7)])]);
      expect(checkTurn(start: start, proposed: proposed, rack: [r(1)], melded: true, rules: rules), contains('stay'));
    });
    test('invalid sets are refused', () {
      final proposed = boardWith([(0, 0, [r(1), r(2)])]);
      expect(checkTurn(start: Board.empty(), proposed: proposed, rack: [r(1), r(2)], melded: true, rules: rules),
          contains('valid'));
    });
  });

  group('host', () {
    List<PlayerInfo> players() => const [
          PlayerInfo('a', 'Ann', SeatKind.human),
          PlayerInfo('b', 'Bob', SeatKind.human),
        ];
    test('deals and draws', () {
      final h = GameHost(players: players(), rules: const HouseRules(turnSeconds: 0), seed: 1)..startRound();
      expect(h.racks['a']!.length, 14);
      expect(h.racks['b']!.length, 14);
      expect(h.pile.length, 106 - 28);
      expect(h.handle('b', const DrawAction()).ok, false);
      expect(h.handle('a', const DrawAction()).ok, true);
      expect(h.racks['a']!.length, 15);
      expect(h.currentPlayer.id, 'b');
      h.dispose();
    });
    test('timeout with invalid board resets and draws', () {
      final h = GameHost(players: players(), rules: const HouseRules(turnSeconds: 0), seed: 2)..startRound();
      final t = h.racks['a']!.first;
      final pv = Layout.place(h.board, [t], 0, 0);
      expect(h.handle('a', PreviewAction(pv)).ok, true);
      h.timeout();
      expect(h.board.allTiles, isEmpty);
      expect(h.racks['a']!.length, 15);
      expect(h.racks['a']!.contains(t), true);
      h.dispose();
    });
    test('empty pile and everyone passes ends the round', () {
      final h = GameHost(
          players: players(),
          rules: const HouseRules(turnSeconds: 0),
          test: const TestTools(enabled: true, pileLimit: 0),
          seed: 3)
        ..startRound();
      h.handle('a', const DrawAction());
      expect(h.result, isNull);
      h.handle('b', const DrawAction());
      expect(h.result, isNotNull);
      expect(h.result!.reason, 'pile');
      h.dispose();
    });
    test('scores: losers lose rack value, winner gains the sum', () {
      final h = GameHost(players: players(), rules: const HouseRules(turnSeconds: 0), seed: 4)..startRound();
      final bValue = h.racks['b']!.fold<int>(0, (s, t) => s + tilePenalty(t));
      h.debugWin('a');
      expect(h.result!.roundScores['a'], bValue);
      expect(h.result!.roundScores['b'], -bValue);
      h.dispose();
    });
    test('view hides other racks', () {
      final h = GameHost(players: players(), rules: const HouseRules(turnSeconds: 0), seed: 5)..startRound();
      final v = h.viewFor('b');
      expect(v.rack, h.racks['b']);
      final json = PlayerView.fromJson(v.toJson());
      expect(json.rack, h.racks['b']);
      expect(json.seats.length, 2);
      h.dispose();
    });
  });

  group('bots', () {
    test('finds melds with a joker', () {
      final c = candidateMelds([r(3), r(4), j0, b(9), k(9)]);
      expect(c.any((m) => m.length == 3 && m.contains(j0) && m.contains(r(3))), true);
      expect(c.any((m) => m.contains(b(9)) && m.contains(k(9)) && m.contains(j0)), true);
    });
    test('first meld respects the minimum', () {
      final plan = planTurn(
        board: Board.empty(),
        rack: [r(1), r(2), r(3), b(5)],
        melded: false,
        firstMeld: 30,
        level: BotLevel.hard,
        rng: math.Random(1),
      );
      expect(plan.draws, true);
      final plan2 = planTurn(
        board: Board.empty(),
        rack: [r(10), r(11), r(12), b(5)],
        melded: false,
        firstMeld: 30,
        level: BotLevel.hard,
        rng: math.Random(1),
      );
      expect(plan2.tileCount, 3);
    });
    test('easy bot plays at most 3 tiles', () {
      for (var s = 0; s < 20; s++) {
        final plan = planTurn(
          board: Board.empty(),
          rack: [for (var n = 1; n <= 9; n++) r(n)],
          melded: true,
          firstMeld: 30,
          level: BotLevel.easy,
          rng: math.Random(s),
        );
        expect(plan.tileCount <= 3, true);
      }
    });
    test('hard bot extends table sets', () {
      final bd = boardWith([(0, 0, [k(5), k(6), k(7)])]);
      final plan = planTurn(
          board: bd, rack: [k(8), r(1)], melded: true, firstMeld: 30, level: BotLevel.hard, rng: math.Random(1));
      expect(plan.tileCount, 1);
      var out = bd;
      out = applyBotTile(out, plan.steps.single, 0);
      expect(out.blocksInRow(0).single.tiles, [k(5), k(6), k(7), k(8)]);
    });
    test('bot-only games always finish with legal turns', () async {
      for (var seed = 0; seed < 25; seed++) {
        final h = GameHost(
          players: const [
            PlayerInfo('a', 'A', SeatKind.bot, level: BotLevel.hard),
            PlayerInfo('b', 'B', SeatKind.bot, level: BotLevel.medium),
            PlayerInfo('c', 'C', SeatKind.bot, level: BotLevel.easy),
          ],
          rules: const HouseRules(turnSeconds: 0),
          seed: seed,
        )..startRound();
        final rng = math.Random(seed);
        var turns = 0;
        while (h.result == null && turns < 2000) {
          final p = h.currentPlayer;
          final plan = planTurn(
              board: h.board,
              rack: h.racks[p.id]!,
              melded: h.melded.contains(p.id),
              firstMeld: h.rules.firstMeld,
              level: p.level,
              rng: rng);
          if (plan.draws) {
            h.handle(p.id, const DrawAction());
          } else {
            var bd = h.board.copy();
            for (final st in plan.steps) {
              for (var i = 0; i < (st.isNewSet ? st.tiles.length : 1); i++) {
                bd = applyBotTile(bd, st, i);
              }
            }
            final res = h.handle(p.id, CommitAction(bd));
            expect(res.ok, true, reason: 'seed $seed turn $turns: ${res.error}\n$bd');
          }
          turns++;
        }
        expect(h.result, isNotNull, reason: 'seed $seed');
        h.dispose();
      }
    });
  });
}
