import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/app/sfx.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);

void main() {
  late GameHost host;
  late LocalSession s;

  /// Ann (p0, this phone) against Bob (p1), a 30 s turn timer, Ann to play.
  Future<dynamic> setUpGame(WidgetTester tester, List<int> annRack, {bool hotSeat = false}) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 30, firstMeld: 0),
      seed: 5,
    );
    s = LocalSession(host, hotSeat: hotSeat);
    for (final id in host.racks.keys) {
      host.racks[id]!.removeWhere(annRack.contains);
    }
    host.pile.removeWhere(annRack.contains);
    host.racks['p0'] = [...annRack, ...host.racks['p0']!.take(14 - annRack.length)];
    if (host.currentPlayer.id != 'p0') host.handle('p1', const DrawAction());
    if (hotSeat) s.dismissCover();
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
    return tester.state(find.byType(GameScreen));
  }

  Future<void> tearDownGame(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  }

  Future<void> runOut(WidgetTester tester) async {
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('time runs out with a valid table and tiles played: they stay, and the bell rings', (tester) async {
    final st = await setUpGame(tester, [y(1), y(2), y(3)]);
    st.debugSetWorking(Board.empty()..writeBlock(Block(0, 0, [y(1), y(2), y(3)])));
    await tester.pump(const Duration(milliseconds: 300));
    final log = SoundBoard.instance.log..clear();
    await runOut(tester);
    expect(host.board.allTiles.toSet(), {y(1), y(2), y(3)}, reason: 'the play was kept');
    expect(log.where((x) => x == Sfx.turnEnd).length, 1);
    expect(log.contains(Sfx.draw), false);
    await tearDownGame(tester);
  });

  testWidgets('time runs out with an unfinished set: tiles go back, a draw, no bell', (tester) async {
    final st = await setUpGame(tester, [y(1), y(2), y(3)]);
    st.debugSetWorking(Board.empty()..writeBlock(Block(0, 0, [y(1), y(2)])));
    await tester.pump(const Duration(milliseconds: 300));
    final log = SoundBoard.instance.log..clear();
    await runOut(tester);
    expect(host.board.allTiles, isEmpty);
    expect(log.contains(Sfx.turnEnd), false);
    expect(log.contains(Sfx.draw), true);
    await tearDownGame(tester);
  });

  testWidgets('time runs out having played nothing: a draw, no bell', (tester) async {
    await setUpGame(tester, [y(1), y(2), y(3)]);
    final log = SoundBoard.instance.log..clear();
    await runOut(tester);
    expect(log.contains(Sfx.turnEnd), false);
    expect(log.contains(Sfx.draw), true);
    await tearDownGame(tester);
  });

  testWidgets('pass-and-play: time runs out on a valid play: the bell, then the cover', (tester) async {
    final st = await setUpGame(tester, [y(1), y(2), y(3)], hotSeat: true);
    expect(s.view!.me, 'p0');
    st.debugSetWorking(Board.empty()..writeBlock(Block(0, 0, [y(1), y(2), y(3)])));
    await tester.pump(const Duration(milliseconds: 300));
    final log = SoundBoard.instance.log..clear();
    await runOut(tester);
    expect(host.board.allTiles.toSet(), {y(1), y(2), y(3)});
    expect(log.where((x) => x == Sfx.turnEnd).length, 1);
    await tearDownGame(tester);
  });
}
