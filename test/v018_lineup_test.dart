import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/net/online.dart';
import 'package:michikub/ui/game_screen.dart';

void main() {
  test('between rounds: new players and rules, totals kept by id', () {
    final h = GameHost(
      players: const [PlayerInfo('a', 'Ann', SeatKind.human), PlayerInfo('b', 'Bob', SeatKind.bot)],
      rules: const HouseRules(turnSeconds: 0),
      seed: 1,
    );
    h.startRound();
    h.debugWin('a');
    final ann = h.totals['a']!, bob = h.totals['b']!;
    expect(ann, greaterThan(0));
    h.reconfigure(const [PlayerInfo('a', 'Ann', SeatKind.human), PlayerInfo('c', 'Cy', SeatKind.bot)], const HouseRules(turnSeconds: 0, handSize: 10));
    h.startRound();
    expect(h.players.map((p) => p.id), ['a', 'c']);
    expect(h.totals, {'a': ann, 'c': 0});
    expect(h.racks['a']!.length, 10);
    expect(bob, lessThan(0));
    h.dispose();
  });

  test('online: the host reopens the lobby between rounds, adds a bot and carries on', () {
    final net = NetHost('Ann', const HouseRules(turnSeconds: 0), open: false);
    net.addBot(BotLevel.easy);
    final session = net.start();
    net.host!.debugWin('host');
    final total = net.host!.totals['host'];
    expect(session.canChangeLineup, true);
    net.reopenLobby();
    expect(net.between, true);
    expect(net.canStart, true);
    net.addBot(BotLevel.hard);
    net.setRules(const HouseRules(turnSeconds: 0, handSize: 12));
    net.continueGame();
    expect(net.between, false);
    expect(net.host!.players.length, 3);
    expect(net.host!.result, isNull);
    expect(net.host!.totals['host'], total);
    expect(net.host!.racks['host']!.length, 12);
    session.leave();
  });

  testWidgets('practice: Players & rules on the results goes to the setup and continues the game', (tester) async {
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppPrefs.instance.highlightValid = false;
    final host = GameHost(
      players: const [PlayerInfo('me', 'Ann', SeatKind.human), PlayerInfo('bot0', 'Bolt', SeatKind.bot, avatar: 'assets/bots/robot_bolt.png')],
      rules: const HouseRules(turnSeconds: 0),
      seed: 2,
    );
    final s = LocalSession(host, hotSeat: false);
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 2));
    host.debugWin('me');
    await tester.pump(const Duration(seconds: 2));
    final total = host.totals['me'];
    await tester.tap(find.byKey(const ValueKey('changeLineup')));
    await tester.pumpAndSettle();
    expect(find.text('Next round'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(host.players.length, 3);
    expect(host.players[1].id, 'bot0');
    expect(host.result, isNull);
    expect(host.totals['me'], total);
    expect(find.byType(GameScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.leave();
    await tester.pump(const Duration(seconds: 10));
  });
}
