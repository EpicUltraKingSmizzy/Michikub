import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);

/// v0.1.6 bug: on a landscape phone with an empty table, a single tile dragged into
/// the third row looked smaller and shifted, because the view zoomed out to keep an
/// empty row below it. Every visible row must use the same cell size and columns.
void main() {
  late GameHost host;
  late LocalSession s;
  late String me;
  Board table() => host.preview ?? host.board;
  final two = b(2);
  const col = 6;

  Future<void> setUpWith(WidgetTester tester, int row, {List<Block> extra = const []}) async {
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
    final bd = Board.empty(5)..writeBlock(Block(row, col, [two]));
    for (final x in extra) {
      bd.writeBlock(x);
    }
    host.board = bd.copy();
    host.turnStart = bd.copy();
    host.racks[me] = [b(9), b(11), b(13)];
    host.handle(me, PreviewAction(bd.copy()));
    await tester.pumpWidget(MaterialApp(home: GameScreen(key: UniqueKey(), session: s)));
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> tearDown(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  }

  /// Where the tile renders with the table holding just it at [row].
  Future<Rect> placeAt(WidgetTester tester, int row) async {
    await setUpWith(tester, row);
    expect(table().find(two)?.row, row);
    final r = tester.getRect(find.byKey(ValueKey(two)));
    await tearDown(tester);
    return r;
  }

  testWidgets('the same tile in each visible row: same size, same x', (tester) async {
    final rects = [for (var row = 0; row < 3; row++) await placeAt(tester, row)];
    for (final r in rects.skip(1)) {
      expect(r.width, moreOrLessEquals(rects[0].width, epsilon: .01));
      expect(r.height, moreOrLessEquals(rects[0].height, epsilon: .01));
      expect(r.left, moreOrLessEquals(rects[0].left, epsilon: .01));
    }
    // Evenly spaced rows: one pitch apart.
    final pitch = rects[1].top - rects[0].top;
    expect(pitch, greaterThan(rects[0].height));
    expect(rects[2].top - rects[1].top, moreOrLessEquals(pitch, epsilon: .01));
  });

  testWidgets('dragging a tile down into the last visible row keeps its size and column', (tester) async {
    final r0 = await placeAt(tester, 0);
    final r1 = await placeAt(tester, 1);
    final pitch = r1.top - r0.top;
    await setUpWith(tester, 1);
    expect(tester.getRect(find.byKey(ValueKey(two))), r1);
    final g = await tester.startGesture(r1.center);
    for (var i = 0; i < 6; i++) {
      await g.moveBy(Offset(0, pitch / 6));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final pos = table().find(two)!;
    expect(pos.row, 2);
    expect(pos.col, col);
    final r2 = tester.getRect(find.byKey(ValueKey(two)));
    expect(r2.size.width, moreOrLessEquals(r0.width, epsilon: .01));
    expect(r2.size.height, moreOrLessEquals(r0.height, epsilon: .01));
    expect(r2.left, moreOrLessEquals(r0.left, epsilon: .01));
    expect(r2.top - r1.top, moreOrLessEquals(pitch, epsilon: .01));
    await tearDown(tester);
  });

  testWidgets('a set below the rows in view zooms out, and every tile rescales together', (tester) async {
    final big = await placeAt(tester, 0);
    // A set in the 4th row (as after Add row) needs more room: the view zooms out.
    await setUpWith(tester, 0, extra: [Block(3, col, [b(5)])]);
    final top = tester.getRect(find.byKey(ValueKey(two)));
    final low = tester.getRect(find.byKey(ValueKey(b(5))));
    expect(top.width, lessThan(big.width));
    expect(low.width, moreOrLessEquals(top.width, epsilon: .01));
    expect(low.height, moreOrLessEquals(top.height, epsilon: .01));
    expect(low.left, moreOrLessEquals(top.left, epsilon: .01));
    await tearDown(tester);
  });
}
