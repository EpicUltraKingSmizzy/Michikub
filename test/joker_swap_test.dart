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
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
const j = kJokerBase;

Board boardWith(List<(int, int, List<int>)> sets, [int rows = 5]) {
  final bd = Board.empty(rows);
  for (final (row, col, ts) in sets) {
    bd.writeBlock(Block(row, col, ts));
  }
  return bd;
}

void main() {
  group('joker swap shortcut (engine)', () {
    test('run, joker in the middle: the tile takes its place, the joker moves to the high end', () {
      final bd = boardWith([
        (0, 2, [r(7), r(8), j, r(10)]),
      ]);
      final res = Layout.jokerShortcut(bd, r(9), j)!;
      expect(res.detached, false);
      expect(res.board.blockOf(r(7))!.tiles, [r(7), r(8), r(9), r(10), j]);
      expect(res.board.isValid, true);
    });
    test('run, joker at the end: same, joker stays at the high end', () {
      final bd = boardWith([
        (0, 2, [r(7), r(8), r(9), j]),
      ]);
      final res = Layout.jokerShortcut(bd, r(10), j)!;
      expect(res.board.blockOf(r(7))!.tiles, [r(7), r(8), r(9), r(10), j]);
    });
    test('run ending at 13: the joker goes to the low end instead', () {
      final bd = boardWith([
        (0, 4, [r(11), j, r(13)]),
      ]);
      final res = Layout.jokerShortcut(bd, r(12), j)!;
      expect(res.detached, false);
      expect(res.board.blockOf(r(11))!.tiles, [j, r(11), r(12), r(13)]);
    });
    test('a full 1-13 run: the joker is detached to the nearest empty space', () {
      final full = [for (var n = 1; n <= 13; n++) n == 6 ? j : r(n)];
      final bd = boardWith([
        (1, 2, full),
      ]);
      final res = Layout.jokerShortcut(bd, r(6), j)!;
      expect(res.detached, true);
      expect(res.board.blockOf(r(1))!.tiles, [for (var n = 1; n <= 13; n++) r(n)]);
      final p = res.board.find(j)!;
      expect(res.board.blockOf(j)!.tiles, [j], reason: 'alone');
      expect((p.row - 1).abs() <= 1, true, reason: 'near where it was (row ${p.row}, col ${p.col})');
    });
    test('group of 3 (with the joker): the tile is added, the joker sits at the edge', () {
      final bd = boardWith([
        (0, 2, [r(6), j, b(6)]),
      ]);
      final res = Layout.jokerShortcut(bd, y(6), j)!;
      expect(res.detached, false);
      expect(res.board.blockOf(r(6))!.tiles, [r(6), y(6), b(6), j]);
      expect(res.board.isValid, true);
    });
    test('group of 4 (with the joker): the tile replaces it and the joker is detached', () {
      final bd = boardWith([
        (0, 2, [r(6), b(6), j, y(6)]),
      ]);
      final res = Layout.jokerShortcut(bd, k(6), j)!;
      expect(res.detached, true);
      expect(res.board.blockOf(r(6))!.tiles, [r(6), b(6), k(6), y(6)]);
      expect(res.board.blockOf(j)!.tiles, [j]);
    });
    test('an incompatible tile: no shortcut', () {
      final bd = boardWith([
        (0, 2, [r(7), r(8), j, r(10)]),
        (1, 2, [r(6), j + 1, b(6)]),
      ]);
      expect(Layout.jokerShortcut(bd, r(11), j), isNull);
      expect(Layout.jokerShortcut(bd, b(9), j), isNull);
      expect(Layout.jokerShortcut(bd, r(6, 1), j + 1), isNull, reason: 'same colour twice');
      expect(Layout.jokerShortcut(bd, y(7), j + 1), isNull);
    });
    test('a tile taken from elsewhere on the board (stays on the table)', () {
      final bd = boardWith([
        (0, 2, [r(7), r(8), j, r(10)]),
        (2, 2, [r(9), b(9), k(9), y(9)]),
      ]);
      final res = Layout.jokerShortcut(bd, r(9), j)!;
      expect(res.board.blockOf(r(7))!.tiles, [r(7), r(8), r(9), r(10), j]);
      expect(res.board.blockOf(b(9))!.tiles, [b(9), k(9), y(9)], reason: 'the group closes up too');
      expect(res.board.blockOf(b(9))!.start, 2);
      expect(tableTilesSentToRack(bd.allTiles.toSet(), res.board), isEmpty);
    });
    test('bots: the swap counts as 1 move', () {
      final bd = boardWith([
        (0, 2, [r(7), r(8), j, r(10)]),
      ]);
      final p = findPlays(bd, [r(9)]).firstWhere((p) => p.steps.first.type == BotStepType.jokerSwap);
      expect(p.moveCount, 1);
      expect(p.tileCount, 1);
    });
  });

  group('group gap closing', () {
    test('taking the middle 7 of 7-7-7-7 leaves 7-7-7, anchored left', () {
      final bd = boardWith([
        (0, 3, [r(7), b(7), y(7), k(7)]),
      ]);
      final out = bd.copy()..removeTiles([b(7)]);
      final blk = out.blockOf(r(7))!;
      expect(blk.tiles, [r(7), y(7), k(7)]);
      expect(blk.start, 3);
      final out2 = bd.copy()..removeTiles([r(7)]);
      expect(out2.blockOf(b(7))!.start, 3, reason: 'left-most position kept');
    });
    test('moving a group tile elsewhere (drag/tap/bot paths) closes the group', () {
      final bd = boardWith([
        (0, 3, [r(7), b(7), y(7), k(7)]),
        (2, 3, [r(4), r(5), r(6)]),
      ]);
      final out = Layout.insertInto(bd, [r(7)], r(4), 3);
      expect(out.blockOf(r(4))!.tiles, [r(4), r(5), r(6), r(7)]);
      expect(out.blockOf(b(7))!.tiles, [b(7), y(7), k(7)]);
      expect(out.blockOf(b(7))!.start, 3);
      final moved = applyBotStep(bd, BotStep.moveTile(y(7), toSetTile: r(4), index: 3));
      expect(moved.blockOf(r(7))!.tiles, [r(7), b(7), k(7)]);
    });
    test('runs are not closed: taking the middle of a run still splits it', () {
      final bd = boardWith([
        (0, 3, [r(4), r(5), r(6), r(7), r(8)]),
      ]);
      final out = bd.copy()..removeTiles([r(6)]);
      expect(out.blockOf(r(4))!.tiles, [r(4), r(5)]);
      expect(out.blockOf(r(7))!.tiles, [r(7), r(8)]);
    });
  });

  group('gestures', () {
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

    Future<void> tapTile(WidgetTester tester, int t) async {
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey(t))));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('tap a rack tile, then tap any tile of the run with the joker', (tester) async {
      await setUpTable(tester, boardWith([
        (0, 2, [r(7), r(8), j, r(10)]),
      ]), [r(9), k(13)]);
      await tapTile(tester, r(9));
      await tapTile(tester, r(7));
      expect(table().blockOf(r(7))?.tiles, [r(7), r(8), r(9), r(10), j]);
      await tearDownTable(tester);
    });

    testWidgets('an incompatible tile falls back to normal attach (invalid here: nothing changes)', (tester) async {
      await setUpTable(tester, boardWith([
        (0, 2, [r(6), b(6), j, y(6)]),
        (2, 2, [k(4), k(5), k(6), k(7)]),
      ]), [k(13)]);
      await tapTile(tester, k(7));
      await tapTile(tester, j);
      expect(table().blockOf(r(6))?.tiles, [r(6), b(6), j, y(6)]);
      expect(table().blockOf(k(4))?.tiles, [k(4), k(5), k(6), k(7)]);
      await tearDownTable(tester);
    });

    testWidgets('board-sourced tile + group of 4 detaches the joker, which stays selected', (tester) async {
      await setUpTable(tester, boardWith([
        (0, 2, [r(6), b(6), j, y(6)]),
        (2, 2, [k(6), k(7), k(8), k(9)]),
      ]), [k(13)]);
      await tapTile(tester, k(6));
      await tapTile(tester, r(6));
      expect(table().blockOf(r(6))?.tiles, [r(6), b(6), k(6), y(6)]);
      expect(table().blockOf(k(7))?.tiles, [k(7), k(8), k(9)]);
      expect(table().blockOf(j)?.tiles, [j], reason: 'detached alone');
      // Still selected: tap the black run's end to attach it there.
      await tapTile(tester, k(9));
      expect(table().blockOf(k(7))?.tiles, [k(7), k(8), k(9), j]);
      expect(table().isValid, true);
      await tearDownTable(tester);
    });

    testWidgets('dragging the middle tile out of a group closes it up', (tester) async {
      await setUpTable(tester, boardWith([
        (0, 3, [r(7), b(7), y(7), k(7)]),
      ]), [k(13)]);
      final from = tester.getCenter(find.byKey(ValueKey(b(7))));
      final g = await tester.startGesture(from);
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(from, const Offset(560, 150), i / 12)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(table().blockOf(r(7))?.tiles, [r(7), y(7), k(7)]);
      expect(table().blockOf(r(7))?.start, 3);
      await tearDownTable(tester);
    });
  });
}
