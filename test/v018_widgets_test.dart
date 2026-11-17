import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/engine/rack_sort.dart';
import 'package:michikub/ui/setup_screens.dart';
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
  List<int> rackOnScreen(WidgetTester tester) => [...s.view!.rack]..sort((a, b) {
      final ra = tester.getRect(find.byKey(ValueKey(a))), rb = tester.getRect(find.byKey(ValueKey(b)));
      return (ra.top - rb.top).abs() > 2 ? ra.top.compareTo(rb.top) : ra.left.compareTo(rb.left);
    });

  bool selected(WidgetTester tester, String key) => tester.widget<RingButton>(find.byKey(ValueKey(key))).selected;

  testWidgets('v0.1.8: 789 sorts and stays selected, new tiles re-sort, moving a tile by hand deselects', (tester) async {
    await setUpGame(tester);
    await tester.tap(find.byKey(const ValueKey('sort789')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(selected(tester, 'sort789'), true);
    expect(selected(tester, 'sort777'), false);
    host.handle('p0', const DrawAction()); // a tile enters the rack
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final rack = s.view!.rack;
    expect(rack.length, 15);
    final sorted = keepSetsOnRows(sortRackWithSets(List.of(rack), runs: true)).where((t) => !isRackGap(t)).toList();
    expect(rackOnScreen(tester), sorted, reason: 'the drawn tile was sorted in');
    // Move a tile by hand (on Bob's turn): the mode is deselected.
    final byPos = rackOnScreen(tester);
    final from = tester.getRect(find.byKey(ValueKey(byPos[0]))).center;
    final to = tester.getRect(find.byKey(ValueKey(byPos[12]))).center + const Offset(0, 2);
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(selected(tester, 'sort789'), false);
    expect(selected(tester, 'sort777'), false);
    await tearDownGame(tester);
  });

  testWidgets('v0.1.8: my turn starting pulses the rack', (tester) async {
    await setUpGame(tester);
    host.handle('p0', const DrawAction());
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('turnPulse')), findsNothing);
    host.handle('p1', const DrawAction()); // my turn again
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const ValueKey('turnPulse')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('turnPulse')), findsNothing, reason: 'brief');
    await tearDownGame(tester);
  });

  for (final (name, screen) in [('Practice', const PracticeSetupScreen()), ('Pass-and-play', const HotSeatSetupScreen())]) {
    testWidgets('v0.1.8: $name setup has Start at the top right', (tester) async {
      tester.view.physicalSize = const Size(1200, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      final r = tester.getRect(find.byKey(const ValueKey('start')));
      expect(r.top, lessThan(80));
      expect(r.right, greaterThan(1200 - 120));
    });
  }
}
