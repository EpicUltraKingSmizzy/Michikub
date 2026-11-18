import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

Board boardOf(List<Block> blocks) {
  final bd = Board.empty();
  for (final x in blocks) {
    bd.writeBlock(x);
  }
  return bd;
}

List<List<int>> row0(Board bd) => bd.blocksInRow(0).map((x) => x.tiles).toList();

/// Tap-to-move, as the game screen does it: [sel] tapped onto the set holding [target].
Board tapOnto(Board bd, List<int> sel, int target) {
  final tmp = bd.copy()..removeTiles(sel);
  final blk = tmp.blockOf(target)!;
  final at = Layout.attachEnd(blk.tiles, sel, blk.tiles.indexOf(target), allowPartial: true);
  if (at != null) return Layout.bridge(tmp, Layout.insertInto(tmp, sel, blk.tiles.first, at), sel);
  return Layout.splitDuplicate(tmp, sel, target)!;
}

/// Drag-and-drop (or a tap on an empty cell), as the game screen does it: [sel] at [row], [col].
Board dropAt(Board bd, List<int> sel, int row, int col) {
  final tmp = bd.copy()..removeTiles(sel);
  if (tmp.rows[row][col] >= 0) {
    final blk = tmp.blockOf(tmp.rows[row][col])!;
    return Layout.bridge(tmp, Layout.dropInto(tmp, sel, blk.tiles.first, col - blk.start, col: col), sel);
  }
  return Layout.bridge(tmp, Layout.place(tmp, sel, row, col), sel);
}

void main() {
  group('item 2: a run piece added to a run with those numbers splits it', () {
    test('yellow 7-8 into yellow 5-6-7-8-9 makes 5-6-7-8 and 7-8-9 (user example)', () {
      final bd = boardOf([Block(0, 8, [y(5), y(6), y(7), y(8), y(9)])]);
      expect(row0(tapOnto(bd, [y(7, 1), y(8, 1)], y(6))), [
        [y(5), y(6), y(7), y(8)],
        [y(7, 1), y(8, 1), y(9)],
      ]);
      // Dragging it onto the run does the same.
      expect(row0(dropAt(bd, [y(7, 1), y(8, 1)], 0, 10)), [
        [y(5), y(6), y(7), y(8)],
        [y(7, 1), y(8, 1), y(9)],
      ]);
    });

    test('a piece overhanging the run end: 8-9-10 into 5-6-7-8-9 makes 5-6-7-8-9 and 8-9-10', () {
      final bd = boardOf([Block(0, 8, [y(5), y(6), y(7), y(8), y(9)])]);
      expect(row0(Layout.splitDuplicate(bd, [y(8, 1), y(9, 1), y(10)], y(5))!), [
        [y(5), y(6), y(7), y(8), y(9)],
        [y(8, 1), y(9, 1), y(10)],
      ]);
    });

    test('no split for another colour, a gap in the piece, or a first number the run lacks', () {
      final bd = boardOf([Block(0, 8, [y(5), y(6), y(7), y(8), y(9)])]);
      expect(Layout.splitDuplicate(bd, [r(7), r(8)], y(5)), isNull);
      expect(Layout.splitDuplicate(bd, [y(6, 1), y(8, 1)], y(5)), isNull);
      expect(Layout.splitDuplicate(bd, [y(3), y(4), y(5, 1)], y(5)), isNull);
    });
  });

  group('item 3: bridging runs in the same row', () {
    final gap = boardOf([Block(0, 8, [y(5)]), Block(0, 12, [y(7)])]);

    test('5 _ _ _ 7: tapping the 6 onto the 5 joins the 7 (user example)', () {
      expect(row0(tapOnto(gap, [y(6)], y(5))), [
        [y(5), y(6), y(7)],
      ]);
    });

    test('5 _ _ _ 7: tapping the 6 onto the 7 joins the 5', () {
      expect(row0(tapOnto(gap, [y(6)], y(7))), [
        [y(5), y(6), y(7)],
      ]);
    });

    test('3-4-5 _ _ 7-8: the 6 onto either side makes 3-4-5-6-7-8 (user example)', () {
      final bd = boardOf([Block(0, 4, [y(3), y(4), y(5)]), Block(0, 10, [y(7), y(8)])]);
      final want = [
        [y(3), y(4), y(5), y(6), y(7), y(8)],
      ];
      expect(row0(tapOnto(bd, [y(6)], y(4))), want);
      expect(row0(tapOnto(bd, [y(6)], y(8))), want);
    });

    test('multi-tile piece: 3-4 _ _ _ 7 + 5-6 tapped onto either side makes 3-4-5-6-7 (user example)', () {
      final bd = boardOf([Block(0, 4, [y(3), y(4)]), Block(0, 10, [y(7)])]);
      final want = [
        [y(3), y(4), y(5), y(6), y(7)],
      ];
      expect(row0(tapOnto(bd, [y(5), y(6)], y(3))), want);
      expect(row0(tapOnto(bd, [y(5), y(6)], y(7))), want);
    });

    test('multi-tile piece dropped into the gap between them joins both', () {
      final bd = boardOf([Block(0, 4, [y(3), y(4)]), Block(0, 12, [y(7)])]);
      expect(row0(dropAt(bd, [y(5), y(6)], 0, 8)), [
        [y(3), y(4), y(5), y(6), y(7)],
      ]);
    });

    test('dragging the 6 onto the 5 also bridges', () {
      expect(row0(dropAt(gap, [y(6)], 0, 8)), [
        [y(5), y(6), y(7)],
      ]);
    });

    test('only the same row, and nothing in between', () {
      final other = boardOf([Block(0, 8, [y(5)]), Block(1, 12, [y(7)])]);
      final out = tapOnto(other, [y(6)], y(5));
      expect(out.blockOf(y(5))!.tiles, [y(5), y(6)]);
      expect(out.blockOf(y(7))!.tiles, [y(7)]);
      final between = boardOf([Block(0, 4, [y(5)]), Block(0, 8, [r(1), r(2), r(3)]), Block(0, 14, [y(7)])]);
      final out2 = tapOnto(between, [y(6)], y(5));
      expect(out2.blockOf(y(5))!.tiles, [y(5), y(6)]);
      expect(out2.blockOf(y(7))!.tiles, [y(7)]);
    });

    test('only whole pieces that fit: 5 _ 7-8-9 _ + 6 is fine, 5 _ 8 is not bridged', () {
      final no = boardOf([Block(0, 8, [y(5)]), Block(0, 12, [y(8)])]);
      final out = tapOnto(no, [y(6)], y(5));
      expect(out.blockOf(y(5))!.tiles, [y(5), y(6)]);
      expect(out.blockOf(y(8))!.tiles, [y(8)]);
    });

    test('the far side of the set is not pulled in: 2 _ 3-4 + 5 on the 3-4 leaves the 2', () {
      final bd = boardOf([Block(0, 4, [y(2)]), Block(0, 8, [y(3), y(4)])]);
      final out = tapOnto(bd, [y(5)], y(4));
      expect(out.blockOf(y(3))!.tiles, [y(3), y(4), y(5)]);
      expect(out.blockOf(y(2))!.tiles, [y(2)]);
    });
  });

  group('item 4: groups take stranded tiles in the same row', () {
    test('6-6 _ 6 + a 6 on the 6-6 makes a group of 4 (user example)', () {
      final bd = boardOf([Block(0, 6, [r(6), b(6)]), Block(0, 11, [y(6)])]);
      final out = tapOnto(bd, [k(6)], r(6));
      expect(row0(out).single.toSet(), {r(6), b(6), y(6), k(6)});
    });

    test('6-6 _ 6-7-8 + a 6 makes 6-6-6 and never takes the run\'s 6 (user example)', () {
      final bd = boardOf([Block(0, 4, [r(6), b(6)]), Block(0, 9, [y(6), y(7), y(8)])]);
      final out = tapOnto(bd, [k(6)], r(6));
      expect(out.blockOf(r(6))!.tiles.toSet(), {r(6), b(6), k(6)});
      expect(out.blockOf(y(6))!.tiles, [y(6), y(7), y(8)]);
    });

    test('a stranded 6 of a colour already in the group stays put', () {
      final bd = boardOf([Block(0, 6, [r(6), b(6)]), Block(0, 11, [r(6, 1)])]);
      final out = tapOnto(bd, [k(6)], r(6));
      expect(out.blockOf(r(6))!.tiles.toSet(), {r(6), b(6), k(6)});
      expect(out.blockOf(r(6, 1))!.tiles, [r(6, 1)]);
    });

    test('lone 6 on both sides: the nearer joins first, then the other if it still fits', () {
      final bd = boardOf([Block(0, 2, [y(6)]), Block(0, 8, [r(6)]), Block(0, 11, [b(6)])]);
      final out = tapOnto(bd, [k(6)], r(6));
      expect(row0(out).single.toSet(), {r(6), b(6), y(6), k(6)});
    });

    test('multi-tile piece: 6 _ _ _ 6 + 6-6 dropped in the gap makes a group of 4 (user example)', () {
      final bd = boardOf([Block(0, 4, [r(6)]), Block(0, 12, [b(6)])]);
      final out = dropAt(bd, [y(6), k(6)], 0, 8);
      expect(row0(out).single.toSet(), {r(6), b(6), y(6), k(6)});
    });

    test('multi-tile piece tapped onto a lone 6 also takes the other lone 6', () {
      final bd = boardOf([Block(0, 4, [r(6)]), Block(0, 12, [b(6)])]);
      final out = tapOnto(bd, [y(6), k(6)], r(6));
      expect(row0(out).single.toSet(), {r(6), b(6), y(6), k(6)});
    });

    test('never past 4: a full group is not made bigger', () {
      final bd = boardOf([Block(0, 4, [r(6), b(6)]), Block(0, 10, [y(6)]), Block(0, 14, [y(6, 1)])]);
      final out = tapOnto(bd, [k(6)], r(6));
      expect(out.blockOf(r(6))!.length, 4);
      expect(out.blockOf(y(6, 1))!.tiles, [y(6, 1)]);
    });
  });

  group('game screen', () {
    late GameHost host;
    late LocalSession s;

    Future<dynamic> setUp(WidgetTester tester, List<int> annRack) async {
      AppPrefs.instance.highlightValid = false;
      tester.view.physicalSize = const Size(1200, 560);
      tester.view.devicePixelRatio = 1;
      host = GameHost(
        players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
        seed: 5,
      );
      s = LocalSession(host, hotSeat: false);
      for (final id in host.racks.keys) {
        host.racks[id]!.removeWhere(annRack.contains);
      }
      host.pile.removeWhere(annRack.contains);
      host.racks['p0'] = [...annRack, ...host.racks['p0']!.take(14 - annRack.length)];
      if (host.currentPlayer.id != 'p0') host.handle('p1', const DrawAction());
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
      return tester.state(find.byType(GameScreen));
    }

    Future<void> tearDown(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      s.leave();
      tester.view.reset();
    }

    testWidgets('tap the 6, tap the 5: the 7 across the gap joins (and tapping the 7 works too)', (tester) async {
      for (final target in [y(5), y(7)]) {
        final st = await setUp(tester, [y(5), y(6), y(7)]);
        st.debugSetWorking(boardOf([Block(0, 8, [y(5)]), Block(0, 12, [y(7)])]));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(ValueKey(y(6))));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(ValueKey(target)));
        await tester.pump(const Duration(milliseconds: 400));
        final w = st.debugWorking as Board;
        expect(w.blockOf(y(5))!.tiles, [y(5), y(6), y(7)], reason: 'target ${tileLabel(target)}');
        await tearDown(tester);
      }
    });

    testWidgets('item 1: an invalid-move message sits above the board, clear of every table tile', (tester) async {
      final st = await setUp(tester, [y(5), y(9)]);
      // A top row full of tiles, then End turn with an unfinished set: the message shows.
      st.debugSetWorking(boardOf([Block(0, 0, [y(5)]), Block(0, 6, [y(9)])]));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('End turn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final toast = find.byKey(const ValueKey('toast'));
      expect(toast, findsOneWidget);
      final tr = tester.getRect(toast);
      expect(tr.top, greaterThanOrEqualTo(0));
      for (final t in [y(5), y(9)]) {
        expect(tr.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(ValueKey(t))).top), reason: 'tile ${tileLabel(t)} uncovered');
      }
      await tearDown(tester);
    });
  });
}
