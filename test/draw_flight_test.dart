import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/tiles_view.dart';

/// v0.1.7: an opponent's drawn tile must not show in their face-down rack (or count) until
/// the pile-to-rack animation lands; the local player's drawn tile is never shown twice.
void main() {
  testWidgets('opponent draw: the face-down tile appears only when the flight lands', (tester) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560); // wide enough for "Waiting..." in the test font
    tester.view.devicePixelRatio = 1;
    final host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0),
      seed: 3,
    );
    final s = LocalSession(host, hotSeat: false); // Ann's phone; Bob is the opponent
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
    if (host.currentPlayer.id != 'p0') {
      host.handle('p1', const DrawAction());
      await tester.pump(const Duration(seconds: 2));
    }
    expect(host.currentPlayer.id, 'p0');

    // My own draw: the new tile is one sprite flying from the pile, never also sitting in the rack.
    final before = host.racks['p0']!.toSet();
    host.handle('p0', const DrawAction());
    await tester.pump();
    final mine = host.racks['p0']!.firstWhere((t) => !before.contains(t));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(ValueKey(mine)), findsOneWidget);
    final mid = tester.getRect(find.byKey(ValueKey(mine)));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getRect(find.byKey(ValueKey(mine))), isNot(mid), reason: 'it was still flying');

    // Bob draws.
    final bob = host.racks['p1']!.length;
    final backs = find.byType(GoldBack);
    final base = backs.evaluate().length;
    expect(find.text('$bob'), findsWidgets);
    host.handle('p1', const DrawAction());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Mid-flight: Bob's rack still shows the old tiles and count; the only extra back is the flying one.
    expect(backs.evaluate().length, base + 1);
    expect(find.text('${bob + 1}'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    // Landed: the tile is in Bob's rack now, and the count shows it.
    expect(backs.evaluate().length, base + 1);
    expect(find.text('${bob + 1}'), findsWidgets);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  });
}
