import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rack_sort.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/theme.dart';

int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);

void main() {
  late GameHost host;
  late LocalSession s;

  /// Ann's phone (p0) against Bob (p1), both people, starting on Ann's turn.
  Future<void> setUpGame(WidgetTester tester, {List<int>? annRack, HouseRules rules = const HouseRules(turnSeconds: 0, firstMeld: 0)}) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: rules,
      seed: 5,
    );
    s = LocalSession(host, hotSeat: false);
    final fixed = {...?annRack};
    for (final id in host.racks.keys) {
      host.racks[id]!.removeWhere(fixed.contains);
    }
    host.pile.removeWhere(fixed.contains);
    if (annRack != null) host.racks['p0'] = [...annRack, ...host.racks['p0']!.take(14 - annRack.length)];
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

  String badge(WidgetTester tester, String id) =>
      tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('count-$id')), matching: find.byType(Text))).data!;

  testWidgets('item 13: the deal is sorted (777, then 789) and 789 is selected', (tester) async {
    await setUpGame(tester);
    expect(tester.widget<RingButton>(find.byKey(const ValueKey('sort789'))).selected, true);
    expect(tester.widget<RingButton>(find.byKey(const ValueKey('sort777'))).selected, false);
    final rack = s.view!.rack;
    final want = sortRackWithSets(
      sortRackWithSets(List.of(rack), runs: false).where((t) => !isRackGap(t)).toList(),
      runs: true,
    );
    expect(rackOnScreen(tester), keepSetsOnRows(want).where((t) => !isRackGap(t)).toList());
    await tearDownGame(tester);
  });

  testWidgets('item 9: no Add row button', (tester) async {
    await setUpGame(tester);
    expect(find.byIcon(Icons.unfold_more_double), findsNothing);
    await tearDownGame(tester);
  });

  testWidgets('item 6: tapping the rack with a table tile selected shows the hint and deselects it', (tester) async {
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    expect(host.handle('p0', CommitAction(Board.empty()..writeBlock(Block(0, 12, [y(1), y(2), y(3)])))).ok, true);
    host.handle('p1', const DrawAction()); // Ann's turn again
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final before = host.board.find(y(1));
    await tester.tap(find.byKey(ValueKey(y(1))));
    await tester.pump(const Duration(milliseconds: 400));
    // The rack background, right of the last tile.
    final last = rackOnScreen(tester).last;
    final r = tester.getRect(find.byKey(ValueKey(last)));
    await tester.tapAt(r.center + Offset(r.width * 2, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('can\'t go into a rack'), findsOneWidget);
    // Deselected: tapping an empty table spot doesn't move it there.
    final t0 = tester.getRect(find.byKey(ValueKey(y(3))));
    await tester.tapAt(t0.center + Offset(0, t0.height * 2.5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.view!.board.find(y(1)) ?? host.preview?.find(y(1)), before);
    expect(host.preview, isNull);
    await tearDownGame(tester);
  });

  testWidgets('item 7: the local turn clock pauses in the background and resumes', (tester) async {
    await setUpGame(tester, rules: const HouseRules(turnSeconds: 60, firstMeld: 0));
    expect(host.msLeft, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(host.msLeft, isNull, reason: 'paused');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.msLeft, isNotNull, reason: 'running again');
    await tearDownGame(tester);
  });

  testWidgets('item 10: a tile an opponent takes back flies to their rack and only then counts', (tester) async {
    await setUpGame(tester);
    host.handle('p0', const DrawAction()); // Bob's turn
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final t = host.racks['p1']!.first;
    expect(host.handle('p1', PreviewAction(Board.empty()..writeBlock(Block(0, 12, [t])))).ok, true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(badge(tester, 'p1'), '13');
    expect(host.handle('p1', PreviewAction(Board.empty())).ok, true); // takes it back
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('flyingFace')), findsOneWidget, reason: 'face up on its way');
    expect(badge(tester, 'p1'), '13', reason: 'not in their rack until it lands');
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('flyingFace')), findsNothing);
    expect(badge(tester, 'p1'), '14');
    await tearDownGame(tester);
  });

  testWidgets('item 11: quick chat from my avatar; bubbles beside the sender, then fade', (tester) async {
    await setUpGame(tester);
    await tester.tap(find.byKey(const ValueKey('myAvatar')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chatPicker')), findsOneWidget);
    // X closes; tapping outside closes.
    await tester.tap(find.byKey(const ValueKey('chatClose')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chatPicker')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('myAvatar')));
    await tester.pump();
    await tester.tapAt(const Offset(600, 60));
    await tester.pump();
    expect(find.byKey(const ValueKey('chatPicker')), findsNothing);
    // Send a phrase: it closes, and a bubble shows above my avatar for 3 s.
    await tester.tap(find.byKey(const ValueKey('myAvatar')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat:Well Played!')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chatPicker')), findsNothing);
    expect(s.chats.last.text, 'Well Played!');
    final bubble = tester.getRect(find.byKey(const ValueKey('chat-p0')));
    final me = tester.getRect(find.byKey(const ValueKey('myAvatar')));
    expect(bubble.bottom, lessThan(me.top), reason: 'above my avatar');
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.byKey(const ValueKey('chat-p0')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('chat-p0')), findsNothing, reason: 'gone after 3 s and the fade');
    // Bob's emoji shows below his avatar (top seat) for 2 s.
    (s as dynamic).addChat('p1', '🔥');
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-p1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byKey(const ValueKey('chat-p1')), findsNothing);
    await tearDownGame(tester);
  });
}
