import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/app/sfx.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rack_sort.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/setup_screens.dart';
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

  testWidgets('sounds: start, draw, place, and the shuffle only for a hand sort', (tester) async {
    SoundBoard.instance.log.clear();
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    final log = SoundBoard.instance.log;
    // The deal: the start sound.
    expect(log, contains(Sfx.gameStart));
    log.clear();
    // A hand sort: the shuffle.
    await tester.tap(find.byKey(const ValueKey('sort777')));
    await tester.pump();
    expect(log, [Sfx.sort]);
    log.clear();
    // Placing a tile on the table: attach.
    final tile = s.view!.rack.firstWhere((t) => find.byKey(ValueKey(t)).evaluate().isNotEmpty);
    await tester.tap(find.byKey(ValueKey(tile)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(600, 180));
    await tester.pump(const Duration(milliseconds: 600));
    // A tile set down on its own (a new set): the place sound.
    expect(log, [Sfx.place]);
    log.clear();
    // Opponent and own draws: the draw sound, and the automatic sort is silent.
    host.handle('p0', const DrawAction());
    await tester.pump(const Duration(seconds: 2));
    host.handle('p1', const DrawAction());
    await tester.pump(const Duration(seconds: 2));
    expect(log, [Sfx.draw, Sfx.draw, Sfx.turnStart], reason: "Bob's draw starts my turn: the chime");
    log.clear();
    await tearDownGame(tester);
  });

  testWidgets('sounds: menu buttons click', (tester) async {
    final log = SoundBoard.instance.log..clear();
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: GoldButton('Go', onPressed: () => tapped = true)))));
    await tester.tap(find.text('Go'));
    expect(tapped, true);
    expect(log, [Sfx.click]);
  });

  testWidgets('bug: the turn-start pulse plays once, not again when a tile is played', (tester) async {
    await setUpGame(tester);
    host.handle('p0', const DrawAction()); // Bob's turn
    await tester.pump(const Duration(seconds: 2));
    host.handle('p1', const DrawAction()); // Ann's turn: the pulse
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('turnPulse')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('turnPulse')), findsNothing);
    // Play tiles from the rack to the table, one by one: no pulse.
    for (var i = 0; i < 3; i++) {
      final tile = s.view!.rack.firstWhere((t) => find.byKey(ValueKey(t)).evaluate().isNotEmpty && !(host.preview?.allTiles.contains(t) ?? false));
      if (i == 0) {
        await tester.tap(find.byKey(ValueKey(tile)));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tapAt(const Offset(300, 120));
      } else {
        // Dragged (drop hints show while dragging).
        final from = tester.getCenter(find.byKey(ValueKey(tile)));
        final g = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 50));
        final to = Offset(300 + i * 250.0, 120 + i * 60.0);
        for (var k = 1; k <= 8; k++) {
          await g.moveTo(Offset.lerp(from, to, k / 8)!);
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.byKey(const ValueKey('turnPulse')), findsNothing);
        }
        await g.up();
      }
      for (var f = 0; f < 10; f++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byKey(const ValueKey('turnPulse')), findsNothing);
      }
    }
    expect(host.preview?.allTiles.length ?? 0, 3);
    await tearDownGame(tester);
  });

  testWidgets('sounds: Add bot on the Practice setup clicks', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PracticeSetupScreen()));
    final log = SoundBoard.instance.log..clear();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(log, [Sfx.click]);
  });

  testWidgets('drawing plays only the draw sound (no button click)', (tester) async {
    await setUpGame(tester);
    final log = SoundBoard.instance.log..clear();
    await tester.tap(find.text('Draw'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(log, [Sfx.draw]);
    // The opponent's draw too.
    log.clear();
    host.handle('p1', const DrawAction());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(log, [Sfx.draw, Sfx.turnStart], reason: 'then my turn starts');
    await tearDownGame(tester);
  });

  testWidgets('a sort mode sorts the rack at the end of my turn, silently', (tester) async {
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    List<int> order() => (tester.state(find.byType(GameScreen)) as dynamic).debugRackOrder as List<int>;
    final log = SoundBoard.instance.log..clear();
    final b = Board.empty()..writeBlock(Block(0, 0, [y(1), y(2), y(3)]));
    expect(host.handle('p0', CommitAction(b)).ok, true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final rack = host.racks['p0']!;
    expect(order().where((t) => !isRackGap(t)).toSet(), rack.toSet());
    List<int> norm(List<int> e) => [for (final t in e) isRackGap(t) ? -1 : t];
    expect(norm(order()), norm(keepSetsOnRows(sortRackWithSets(rack, runs: true))), reason: 'packed and sorted 789, no blanks where the set was');
    expect(log, isNot(contains(Sfx.sort)));
    await tearDownGame(tester);
  });

  testWidgets('turn sounds: bell after playing, draw only after drawing, chime when my turn starts', (tester) async {
    SoundBoard.instance.log.clear();
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    final log = SoundBoard.instance.log;
    // The deal's wash, then (after it) my turn's chime.
    expect(log, [Sfx.gameStart, Sfx.turnStart]);
    log.clear();
    // I end my turn after playing a set: only the bell.
    (tester.state(find.byType(GameScreen)) as dynamic).debugSetWorking(Board.empty()..writeBlock(Block(0, 0, [y(1), y(2), y(3)])));
    await tester.pump(const Duration(milliseconds: 300));
    log.clear();
    await tester.tap(find.text('End turn'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(log, [Sfx.turnEnd]);
    log.clear();
    // Bob plays and ends his turn: no sound for his turn end; my turn starts: the chime.
    final bobSet = [for (var n = 7; n <= 9; n++) makeTile(TileColor.blue, n, copy: 1)];
    host.racks['p0']!.removeWhere(bobSet.contains);
    host.pile.removeWhere(bobSet.contains);
    host.racks['p1']!
      ..removeWhere(bobSet.contains)
      ..addAll(bobSet);
    final b2 = host.board.copy()..writeBlock(Block(2, 0, bobSet));
    expect(host.handle('p1', CommitAction(b2)).ok, true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(log.where((x) => x == Sfx.turnEnd), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(log.last, Sfx.turnStart);
    expect(log.where((x) => x == Sfx.turnStart).length, 1);
    log.clear();
    // I draw: only the draw sound.
    await tester.tap(find.text('Draw'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(log, [Sfx.draw]);
    await tearDownGame(tester);
  });

  testWidgets('turn sounds: the End turn button rings the bell, no click', (tester) async {
    await setUpGame(tester, annRack: [y(1), y(2), y(3)]);
    final log = SoundBoard.instance.log..clear();
    // Ann's working table holds a valid set (as if placed by hand), then End turn.
    final st = tester.state(find.byType(GameScreen)) as dynamic;
    st.debugSetWorking(Board.empty()..writeBlock(Block(0, 0, [y(1), y(2), y(3)])));
    await tester.pump(const Duration(milliseconds: 300));
    log.clear();
    await tester.tap(find.text('End turn'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(log, [Sfx.turnEnd]);
    await tearDownGame(tester);
  });

  testWidgets('turn sounds, pass-and-play: the chime plays when the next player taps through the cover', (tester) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
      seed: 5,
    );
    s = LocalSession(host, hotSeat: true);
    final log = SoundBoard.instance.log..clear();
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
    expect(s.coverFor, isNotNull);
    expect(log, isEmpty, reason: 'the deal (wash and animation) waits for the cover, and no chime under it');
    s.dismissCover();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(log, [Sfx.gameStart], reason: 'tapping through: the wash and the deal');
    await tester.pump(const Duration(seconds: 2));
    expect(log, [Sfx.gameStart, Sfx.turnStart], reason: 'then the chime, after the wash');
    await tearDownGame(tester);
  });
}
