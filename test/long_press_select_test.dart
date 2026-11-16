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
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

void main() {
  group('attachEnd (tap a set to attach a selection)', () {
    test('only the valid end is used', () {
      expect(Layout.attachEnd([b(4), b(5), b(6)], [b(7), b(8)], 0), 3);
      expect(Layout.attachEnd([b(4), b(5), b(6)], [b(2), b(3)], 2), 0);
    });
    test('both ends valid: the end nearer the tap', () {
      const j = kJokerBase;
      expect(Layout.attachEnd([b(4), b(5), b(6)], [j], 0), 0);
      expect(Layout.attachEnd([b(4), b(5), b(6)], [j], 2), 3);
    });
    test('invalid either way: null', () {
      expect(Layout.attachEnd([b(4), b(5), b(6)], [r(1), r(2), r(3)], 1), isNull);
    });
  });

  group('long-press, release, tap a destination', () {
    late GameHost host;
    late LocalSession s;
    late String me;
    // What the table shows this turn (moves are previews until End turn).
    Board table() => host.preview ?? host.board;
    final start = Board.empty(5)..writeBlock(Block(0, 2, [b(4), b(5), b(6)]));

    Future<void> setUpTable(WidgetTester tester, List<int> rack) async {
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
      await tester.pump(const Duration(seconds: 3)); // starter banner etc.
    }

    Future<void> tearDownTable(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
      s.leave();
      tester.view.reset();
    }

    Future<void> longPressRelease(WidgetTester tester, int tile) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(tile))));
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> tapTile(WidgetTester tester, int tile) async {
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey(tile))));
      await tester.pump(const Duration(milliseconds: 400)); // past the double-tap window
    }

    testWidgets('rack run -> tap empty board: placed there as a new set', (tester) async {
      await setUpTable(tester, [r(1), r(2), r(3), k(13)]);
      await longPressRelease(tester, r(2));
      expect(table().find(r(1)), isNull, reason: 'nothing moved yet');
      // Empty table space, well right of the blue set.
      await tester.tapAt(const Offset(560, 150));
      await tester.pump(const Duration(milliseconds: 400));
      expect(table().blockOf(r(1))?.tiles, [r(1), r(2), r(3)]);
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6)]);
      await tearDownTable(tester);
    });

    testWidgets('rack run -> tap a set: attached when valid', (tester) async {
      await setUpTable(tester, [b(7), b(8), k(13)]);
      await longPressRelease(tester, b(7));
      await tapTile(tester, b(6));
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6), b(7), b(8)]);
      await tearDownTable(tester);
    });

    testWidgets('invalid attach: nothing moves and it stays selected; tap it again to deselect', (tester) async {
      await setUpTable(tester, [r(1), r(2), r(3), k(13)]);
      await longPressRelease(tester, r(2));
      await tapTile(tester, b(5));
      expect(table().find(r(1)), isNull);
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6)]);
      // Still selected: tapping empty board now places it.
      await tester.tapAt(const Offset(560, 150));
      await tester.pump(const Duration(milliseconds: 400));
      expect(table().blockOf(r(1))?.tiles, [r(1), r(2), r(3)]);
      await tearDownTable(tester);
    });

    testWidgets('tapping the selection again deselects', (tester) async {
      await setUpTable(tester, [r(1), r(2), r(3), k(13)]);
      await longPressRelease(tester, r(2));
      await tapTile(tester, r(3));
      await tester.tapAt(const Offset(560, 150));
      await tester.pump(const Duration(milliseconds: 400));
      expect(table().find(r(1)), isNull, reason: 'deselected, so the tap did nothing');
      await tearDownTable(tester);
    });

    testWidgets('board set -> long-press, release, tap empty space: the whole set moves', (tester) async {
      await setUpTable(tester, [k(13)]);
      final before = table().find(b(4))!;
      await longPressRelease(tester, b(5));
      await tester.tapAt(const Offset(560, 150));
      await tester.pump(const Duration(milliseconds: 400));
      final after = table().find(b(4))!;
      expect(table().blockOf(b(4))?.tiles, [b(4), b(5), b(6)]);
      expect(after == before, false);
      await tearDownTable(tester);
    });
  });
}
