import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';

void main() {
  test('default reveal is 2.5 s', () {
    expect(PassPlayTuning.drawRevealMs, 2500);
  });

  test('Pass-and-play: after a draw the drawn tile shows in the rack before the cover', () async {
    final keep = PassPlayTuning.drawRevealMs;
    PassPlayTuning.drawRevealMs = 80;
    addTearDown(() => PassPlayTuning.drawRevealMs = keep);
    final host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0),
      waitForReady: true,
      seed: 3,
    );
    final s = LocalSession(host, hotSeat: true);
    addTearDown(s.leave);
    final first = host.currentPlayer;
    final other = host.players.firstWhere((p) => p.id != first.id);
    expect(s.coverFor, first.name);
    s.dismissCover();
    final before = s.view!.rack.toSet();
    expect((await s.act(const DrawAction())).ok, true);

    // The turn is over, but the phone still shows the drawer's rack with the new tile marked.
    expect(host.currentPlayer.id, other.id);
    expect(s.coverFor, isNull);
    expect(s.view!.me, first.id);
    expect(s.view!.myTurn, false);
    expect(s.revealTiles, hasLength(1));
    expect(before.contains(s.revealTiles.first), false);
    expect(s.view!.rack, contains(s.revealTiles.first));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.revealTiles, isEmpty);
    expect(s.coverFor, other.name);
    expect(s.view!.me, other.id);
  });

  test("another seat's draw doesn't start a reveal", () async {
    final host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
      waitForReady: true,
      test: const TestTools(enabled: true, seed: 5),
    );
    final s = LocalSession(host, hotSeat: true);
    addTearDown(s.leave);
    s.dismissCover();
    final other = host.players.firstWhere((p) => p.id != host.currentPlayer.id);
    host.debugDraw(other.id, 1);
    expect(s.revealTiles, isEmpty);
  });
}
