import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
const j = kJokerBase;

Board boardWith(List<(int, int, List<int>)> sets, [int rows = 5]) {
  final bd = Board.empty(rows);
  for (final (row, col, ts) in sets) {
    bd.writeBlock(Block(row, col, ts));
  }
  return bd;
}

final start = boardWith([
  (0, 2, [b(4), b(5), b(6)]),
]);

/// A two-human game where it's [me]'s turn, with [table] on the table and [rack] in hand.
(GameHost, String) game(Board table, List<int> rack) {
  final h = GameHost(
    players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('g1', 'Guest', SeatKind.remote)],
    rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
    seed: 1,
  )
    ..firstStarter = 0
    ..startRound();
  final me = h.currentPlayer.id;
  h.board = table.copy();
  h.turnStart = table.copy();
  h.racks[me] = rack;
  return (h, me);
}

void main() {
  group('the check: "was this tile on the table at the start of the turn?"', () {
    test('snapshot taken at turn start', () {
      final (h, _) = game(start, [r(1)]);
      expect(h.turnStartTiles, {b(4), b(5), b(6)});
      expect(wasOnTableAtTurnStart(h.turnStartTiles, b(5)), true);
      expect(wasOnTableAtTurnStart(h.turnStartTiles, r(1)), false);
      h.dispose();
    });
    test('a table tile missing from the board is caught', () {
      final out = start.copy()..removeTiles([b(6)]);
      expect(tableTilesSentToRack(start.allTiles.toSet(), out), {b(6)});
      expect(tableTilesSentToRack(start.allTiles.toSet(), start), isEmpty);
    });
  });

  group('host (every seat: local, pass-and-play, online guests, bots)', () {
    test('moving a table tile into the rack is rejected, preview and commit', () {
      final (h, me) = game(start, [r(1), r(2), r(3)]);
      final taken = start.copy()..removeTiles([b(6)]);
      final withRun = Layout.place(taken, [r(1), r(2), r(3)], 2, 0, merge: false);
      expect(h.handle(me, PreviewAction(withRun)).error, kTableTileToRack);
      expect(h.handle(me, CommitAction(withRun)).error, kTableTileToRack);
      expect(h.board.allTiles.toSet(), start.allTiles.toSet());
      h.dispose();
    });
    test('a tile placed from the rack this turn can come back', () {
      final (h, me) = game(start, [r(1), r(2), r(3)]);
      final placed = Layout.place(start, [r(1)], 2, 0);
      expect(h.handle(me, PreviewAction(placed)).ok, true);
      expect(h.handle(me, PreviewAction(start.copy())).ok, true, reason: 'r1 back to the rack');
      h.dispose();
    });
    test('online: a guest move received as JSON is validated the same way', () {
      final h = GameHost(
        players: const [PlayerInfo('p0', 'Host', SeatKind.human), PlayerInfo('g1', 'Guest', SeatKind.remote)],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
        seed: 1,
      )
        ..firstStarter = 1
        ..startRound();
      expect(h.currentPlayer.id, 'g1');
      h.board = start.copy();
      h.turnStart = start.copy();
      h.racks['g1'] = [r(1)];
      final taken = start.copy()..removeTiles([b(4)]);
      // What NetHost does with a guest's 'act' message.
      final wire = jsonDecode(jsonEncode(PreviewAction(taken).toJson())) as Map<String, dynamic>;
      expect(h.handle('g1', GameAction.fromJson(wire)).error, kTableTileToRack);
      final wire2 = jsonDecode(jsonEncode(CommitAction(taken).toJson())) as Map<String, dynamic>;
      expect(h.handle('g1', GameAction.fromJson(wire2)).ok, false);
      h.dispose();
    });
    test('pass-and-play: the session refuses it too', () async {
      final h = GameHost(
        players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
        waitForReady: true,
        seed: 2,
      );
      final s = LocalSession(h, hotSeat: true);
      s.dismissCover();
      final me = h.currentPlayer.id;
      h.board = start.copy();
      h.turnStart = start.copy();
      h.racks[me] = [r(1)];
      final taken = start.copy()..removeTiles([b(5)]);
      expect((await s.act(PreviewAction(taken))).error, kTableTileToRack);
      expect((await s.act(CommitAction(taken))).ok, false);
      s.leave();
    });
  });

  group('bots', () {
    test('the planner never produces a move that puts a table tile into a rack (fuzz)', () {
      var steps = 0;
      for (var seed = 0; seed < 20; seed++) {
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
        while (h.result == null && turns < 600) {
          final p = h.currentPlayer;
          final plan = planTurn(
            board: h.board,
            rack: h.racks[p.id]!,
            melded: h.melded.contains(p.id),
            firstMeld: h.rules.firstMeld,
            level: p.level,
            rng: rng,
          );
          if (plan.draws) {
            h.handle(p.id, const DrawAction());
          } else {
            var bd = h.board.copy();
            for (final st in plan.steps) {
              bd = applyBotStep(bd, st);
              steps++;
              expect(tableTilesSentToRack(h.turnStartTiles, bd), isEmpty, reason: 'seed $seed: ${st.type}');
              expect(h.handle(p.id, PreviewAction(bd)).ok, true);
            }
            expect(h.handle(p.id, CommitAction(bd)).ok, true);
          }
          turns++;
        }
        h.dispose();
      }
      expect(steps, greaterThan(100));
    });

    test('joker reclaims keep the joker on the table at every step', () {
      final bd = boardWith([
        (0, 0, [r(7), r(8), j, r(10)]),
        (1, 0, [r(6), b(6), j + 1]),
      ]);
      final plays = findPlays(bd, [r(9), makeTile(TileColor.yellow, 6), b(3), b(4), k(10), k(11)])
          .where((p) => p.reclaimedJokers.isNotEmpty)
          .toList();
      expect(plays, isNotEmpty);
      for (final p in plays) {
        var x = bd;
        for (final st in p.steps) {
          x = applyBotStep(x, st);
          expect(tableTilesSentToRack(bd.allTiles.toSet(), x), isEmpty);
        }
      }
    });
  });

  group('human gestures', () {
    late GameHost host;
    late LocalSession s;
    late String me;
    Board table() => host.preview ?? host.board;

    Future<void> setUpTable(WidgetTester tester, Board bd, List<int> rack) async {
      AppPrefs.instance.highlightValid = false;
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      host = GameHost(
        players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
        waitForReady: true,
        seed: 1,
      );
      s = LocalSession(host, hotSeat: true);
      me = host.currentPlayer.id;
      s.dismissCover();
      host.board = bd.copy();
      host.turnStart = bd.copy();
      host.racks[me] = rack;
      host.handle(me, PreviewAction(bd.copy()));
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> tearDownTable(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      s.leave();
      tester.view.reset();
    }

    Offset at(WidgetTester tester, int t) => tester.getCenter(find.byKey(ValueKey(t)));
    const rackSpot = Offset(560, 345);
    const emptyBoard = Offset(560, 150);

    Future<void> drag(WidgetTester tester, Offset from, Offset to, {bool longPress = false}) async {
      final g = await tester.startGesture(from);
      if (longPress) await tester.pump(const Duration(milliseconds: 700));
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 12)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('dragging a table tile to the rack is rejected', (tester) async {
      await setUpTable(tester, start, [r(1), k(13)]);
      await drag(tester, at(tester, b(6)), rackSpot);
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6)]);
      expect(host.racks[me], isNot(contains(b(6))));
      await tearDownTable(tester);
    });

    testWidgets('long-press dragging a whole table set to the rack is rejected', (tester) async {
      await setUpTable(tester, start, [r(1), k(13)]);
      await drag(tester, at(tester, b(5)), rackSpot, longPress: true);
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6)]);
      await tearDownTable(tester);
    });

    testWidgets('a tile placed from the rack this turn can be dragged back', (tester) async {
      await setUpTable(tester, start, [r(1), k(13)]);
      await drag(tester, at(tester, k(13)), emptyBoard);
      expect(table().find(k(13)), isNotNull);
      await drag(tester, at(tester, k(13)), rackSpot);
      expect(table().find(k(13)), isNull);
      await tearDownTable(tester);
    });

    testWidgets('joker shortcut: the joker never goes to the rack', (tester) async {
      final bd = boardWith([
        (0, 2, [r(4), j, r(6)]),
      ]);
      await setUpTable(tester, bd, [r(5), k(13)]);
      await drag(tester, at(tester, r(5)), at(tester, j));
      expect(table().blockOf(r(4))?.tiles, [r(4), r(5), r(6), j]);
      expect(host.racks[me], isNot(contains(j)));
      await tearDownTable(tester);
    });

    testWidgets('the long way: move the joker, then the tile into the gap', (tester) async {
      final bd = boardWith([
        (0, 2, [r(4), j, r(6)]),
      ]);
      await setUpTable(tester, bd, [r(5), k(13)]);
      final gap = at(tester, j);
      await drag(tester, gap, emptyBoard);
      expect(table().find(j), isNotNull);
      await drag(tester, at(tester, r(5)), gap);
      expect(table().blockOf(r(4))?.tiles, [r(4), r(5), r(6)]);
      await tearDownTable(tester);
    });
  });
}
