import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/online_screens.dart';
import 'package:michikub/ui/theme.dart';

int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);

void main() {
  late GameHost host;
  late LocalSession s;

  /// Ann's phone (p0) against Bob (p1), both people, starting on Ann's turn.
  Future<void> setUpGame(WidgetTester tester, {List<int>? annRack, List<int>? bobRack}) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560); // wide enough for "Waiting..." in the test font
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
      seed: 5,
    );
    s = LocalSession(host, hotSeat: false);
    final fixed = {...?annRack, ...?bobRack};
    for (final id in host.racks.keys) {
      host.racks[id]!.removeWhere(fixed.contains);
    }
    host.pile.removeWhere(fixed.contains);
    if (annRack != null) host.racks['p0'] = [...annRack, ...host.racks['p0']!.take(14 - annRack.length)];
    if (bobRack != null) host.racks['p1'] = List.of(bobRack);
    if (host.currentPlayer.id != 'p0') host.handle('p1', const DrawAction());
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> tearDownGame(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  }

  bool glows(WidgetTester tester, int t) =>
      find.descendant(of: find.byKey(ValueKey(t)), matching: find.byKey(const ValueKey('newGlow'))).evaluate().isNotEmpty;

  testWidgets('item 7: tiles others added since my last turn glow white until I play', (tester) async {
    await setUpGame(tester, bobRack: [y(1), y(2), y(3), r(13), r(12)]);
    final mine = host.racks['p0']!.first;
    host.handle('p0', const DrawAction()); // my turn ends
    await tester.pump(const Duration(seconds: 2));
    final bd = Board.empty()..writeBlock(Block(0, 10, [y(1), y(2), y(3)]));
    expect(host.handle('p1', CommitAction(bd)).ok, true);
    await tester.pump(const Duration(seconds: 2));
    expect(host.currentPlayer.id, 'p0');
    for (final t in [y(1), y(2), y(3)]) {
      expect(glows(tester, t), true, reason: 'Bob added it since my last turn');
    }
    // I play a tile: the glow fades out.
    final from = tester.getCenter(find.byKey(ValueKey(mine)));
    final to = tester.getCenter(find.byKey(ValueKey(y(1)))) + const Offset(0, 120);
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(host.preview?.find(mine), isNotNull, reason: 'played to the table');
    for (final t in [y(1), y(2), y(3)]) {
      expect(glows(tester, t), false);
    }
    expect(glows(tester, mine), false, reason: 'my own tiles never glow during my turn');
    await tearDownGame(tester);
  });

  testWidgets('item 8: the results panel minimises to show the table; the winner\'s last tiles glow (mine too)', (tester) async {
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    host.racks['p0'] = [y(1), y(2), y(3)];
    host.handle('p0', PreviewAction(Board.empty()..writeBlock(Block(0, 10, [y(1), y(2), y(3)]))));
    await tester.pump(const Duration(seconds: 1));
    expect(host.result?.winnerId, 'p0');
    expect(find.text('See the table'), findsOneWidget);
    for (final t in [y(1), y(2), y(3)]) {
      expect(glows(tester, t), true);
    }
    await tester.tap(find.text('See the table'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Show results'), findsOneWidget);
    expect(find.textContaining('win'), findsNothing);
    await tester.tap(find.text('Show results'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('See the table'), findsOneWidget);
    await tearDownGame(tester);
  });

  testWidgets('item 9: rack tiles move on others\' turns and can leave blank slots', (tester) async {
    await setUpGame(tester);
    host.handle('p0', const DrawAction()); // Bob's turn now: 15 tiles, two rows
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // the drawn tile has landed
    expect(host.currentPlayer.id, 'p1');
    final rack = s.view!.rack;
    // Rack order on screen: read it from the sprites' positions.
    final byPos = [...rack]..sort((a, b) {
        final ra = tester.getRect(find.byKey(ValueKey(a))), rb = tester.getRect(find.byKey(ValueKey(b)));
        return ra.top != rb.top ? ra.top.compareTo(rb.top) : ra.left.compareTo(rb.left);
      });
    final s0 = tester.getRect(find.byKey(ValueKey(byPos[0]))), s1 = tester.getRect(find.byKey(ValueKey(byPos[1])));
    final s10 = tester.getRect(find.byKey(ValueKey(byPos[10])));
    final step = s1.left - s0.left;
    final target = s10.center + Offset(8 * step, 0); // second row, slot 9 (past the last tile)
    final from = s0.center;
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, target, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final moved = tester.getRect(find.byKey(ValueKey(byPos[0])));
    // It lands in the slot under the dragged tile (which trails the finger by the touch slop),
    // in the second row past the last tile, with blank slots left between.
    expect(moved.center.dy, closeTo(s10.center.dy, 2));
    expect(moved.left, greaterThanOrEqualTo(s10.left + 6 * step - 1), reason: 'at least one blank after the last tile');
    expect(((moved.left - s10.left) / step - ((moved.left - s10.left) / step).round()).abs(), lessThan(.01), reason: 'on the slot grid');
    expect(tester.getRect(find.byKey(ValueKey(byPos[1]))).left, closeTo(s1.left, .5), reason: 'the rack did not pack: slot 0 is blank');
    await tearDownGame(tester);
  });

  testWidgets('items 3 and 10: no turn text under my name; a tile count on my avatar', (tester) async {
    await setUpGame(tester);
    expect(find.text('YOUR TURN'), findsNothing);
    expect(find.text('Waiting…'), findsNothing);
    final badge = find.descendant(of: find.byKey(const ValueKey('myCount')), matching: find.byType(Text));
    expect(tester.widget<Text>(badge).data, '${host.racks['p0']!.length}');
    await tearDownGame(tester);
  });

  group('items 1 and 2: Join a game remembers the last room code', () {
    Future<void> pumpJoin(WidgetTester tester, {String? initial}) async {
      tester.view.physicalSize = const Size(1200, 560);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(theme: MK.theme(), home: JoinScreen(initialCode: initial)));
    }

    TextField codeField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField).at(1));

    testWidgets('prefilled with the last code; the first tap clears it', (tester) async {
      lastRoomCode = 'K7MQ2P';
      await pumpJoin(tester);
      expect(codeField(tester).controller!.text, 'K7MQ2P');
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      expect(codeField(tester).controller!.text, '');
      await tester.enterText(find.byType(TextField).at(1), 'ABCD');
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      expect(codeField(tester).controller!.text, 'ABCD', reason: 'only the old code is cleared');
      lastRoomCode = null;
      tester.view.reset();
    });

    testWidgets('a code from an invite link is not cleared by a tap', (tester) async {
      lastRoomCode = 'K7MQ2P';
      await pumpJoin(tester, initial: 'WXYZ');
      expect(codeField(tester).controller!.text, 'WXYZ');
      await tester.tap(find.byType(TextField).at(1));
      await tester.pump();
      expect(codeField(tester).controller!.text, 'WXYZ');
      lastRoomCode = null;
      tester.view.reset();
    });
  });
}
