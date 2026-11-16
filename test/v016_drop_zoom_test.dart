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

void main() {
  late GameHost host;
  late LocalSession s;
  late String me;
  Board table() => host.preview ?? host.board;

  Future<void> setUpTable(WidgetTester tester, Board start, List<int> rack) async {
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
    host.board = start.copy();
    host.turnStart = start.copy();
    host.racks[me] = rack;
    host.handle(me, PreviewAction(start.copy()));
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> tearDownTable(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  }

  Rect rectOf(WidgetTester tester, int t) => tester.getRect(find.byKey(ValueKey(t)));

  Future<TestGesture> dragTo(WidgetTester tester, int t, Offset to, {bool release = true}) async {
    final from = tester.getCenter(find.byKey(ValueKey(t)));
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (release) {
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    return g;
  }

  testWidgets('dragging a yellow 4 into the middle of 5-6-7-8 makes 4-5-6-7-8', (tester) async {
    final start = Board.empty()..writeBlock(Block(0, 9, [y(5), y(6), y(7), y(8)]));
    await setUpTable(tester, start, [y(4), r(1), r(13)]);
    final mid = rectOf(tester, y(6));
    await dragTo(tester, y(4), Offset(mid.right, mid.center.dy)); // between the 6 and the 7
    expect(table().blockOf(y(5))!.tiles, [y(4), y(5), y(6), y(7), y(8)]);
    await tearDownTable(tester);
  });

  testWidgets('the zoom holds still during a drag and zooms in when the bottom row empties', (tester) async {
    final start = Board.empty()
      ..writeBlock(Block(0, 9, [r(1), r(2), r(3)]))
      ..writeBlock(Block(1, 9, [b(1), b(2), b(3)]))
      ..writeBlock(Block(2, 9, [y(1), y(2), y(3)]))
      ..writeBlock(Block(3, 10, [r(9), r(10), r(11)]));
    await setUpTable(tester, start, [b(13), r(13)]);
    final before = rectOf(tester, r(1));
    final row0 = before.top, pitch = rectOf(tester, b(1)).top - before.top;
    expect(pitch, greaterThan(0));
    // Long-press the lone set in row 3 to drag it whole, up to the right end of row 0.
    final cell = before.width / .92;
    final target = Offset(before.left + 6 * cell, row0 + before.height / 2);
    final from = tester.getCenter(find.byKey(ValueKey(r(9))));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, target, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Mid-drag: nothing rescales.
    expect(rectOf(tester, r(1)).size, before.size);
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(table().usedRows, [0, 1, 2]);
    // Rows 0-2 hold everything now: the view is back to 3 rows and the tiles are bigger.
    expect(rectOf(tester, r(1)).width, greaterThan(before.width * 1.1));
    expect(rectOf(tester, r(9)).size, rectOf(tester, r(1)).size);
    await tearDownTable(tester);
  });
}
