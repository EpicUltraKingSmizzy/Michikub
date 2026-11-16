import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);

/// A 2-player game where the bot moves first with a [seconds] turn timer
/// and holds exactly [rack].
GameHost botGame(int seconds, List<int> rack) {
  final h = GameHost(
    players: const [
      PlayerInfo('bot', 'Bot', SeatKind.bot, level: BotLevel.hard),
      PlayerInfo('me', 'Me', SeatKind.human),
    ],
    rules: const HouseRules(firstMeld: 0, turnSeconds: 0),
    test: TestTools(enabled: true, timerOverride: seconds, seed: 1),
  )
    ..firstStarter = 0 // the bot moves first in these tests
    ..startRound();
  final s = rack.toSet();
  h.racks['me']!.removeWhere(s.contains);
  h.pile.removeWhere(s.contains);
  h.racks['bot'] = List.of(rack);
  return h;
}

/// A driver that runs [plan] on the bot's first turn and draws after that.
BotDriver scripted(GameHost h, BotPlan plan) {
  var used = false;
  return BotDriver(h, planOverride: (_, _) {
    if (used) return const BotPlan([]);
    used = true;
    return plan;
  })
    ..start();
}

void main() {
  group('bot vs the turn timer', () {
    test('timer expires mid-plan with a valid table: turn ends with what was played, no draw', () {
      fakeAsync((async) {
        final rack = [r(1), r(2), r(3), b(1), b(2), b(3), y(1), y(2), y(3), k(1), k(2), k(3), r(13), b(13)];
        final h = botGame(6, rack);
        final d = scripted(
            h,
            BotPlan.ofSteps([
              BotStep.newSet([r(1), r(2), r(3)]),
              BotStep.newSet([b(1), b(2), b(3)]),
              BotStep.newSet([y(1), y(2), y(3)]),
              BotStep.newSet([k(1), k(2), k(3)]), // 1 s start delay + 3 sets x 2 s: would start at 7 s, too late
            ]));
        async.elapse(const Duration(milliseconds: 6500));
        expect(h.currentPlayer.id, 'me');
        expect(h.board.allTiles.toSet(), {r(1), r(2), r(3), b(1), b(2), b(3), y(1), y(2), y(3)});
        expect(h.board.isValid, true);
        expect(h.racks['bot']!.toSet(), {k(1), k(2), k(3), r(13), b(13)}, reason: 'nothing drawn');
        // No stray actions after the timeout.
        final boardAfter = h.board.toJson().toString();
        async.elapse(const Duration(milliseconds: 4000));
        expect(h.currentPlayer.id, 'me');
        expect(h.preview, isNull);
        expect(h.board.toJson().toString(), boardAfter);
        expect(h.racks['bot']!.length, 5);
        d.dispose();
        h.dispose();
      });
    });

    test('timer expires mid-move with an invalid table: reset, tiles back, draw', () {
      fakeAsync((async) {
        final rack = [for (var n = 1; n <= 12; n++) r(n), b(13)];
        final h = botGame(6, rack);
        final pileBefore = h.pile.length;
        // After the 1 s start delay, one move that lays 12 lone tiles (each an
        // invalid set) at 0.5 s each: 7 s in total, longer than the 6 s timer.
        final d = scripted(h, BotPlan([
          BotMove([for (var i = 0; i < 12; i++) BotStep.tileAt(r(i + 1), i % 5, (i ~/ 5) * 4)]),
        ]));
        async.elapse(const Duration(milliseconds: 2600));
        expect(h.preview, isNotNull, reason: 'the bot is mid-move');
        expect(h.preview!.isValid, false);
        async.elapse(const Duration(milliseconds: 3600)); // past 6 s
        expect(h.currentPlayer.id, 'me');
        expect(h.board.allTiles, isEmpty, reason: 'table reset to the start of the turn');
        expect(h.racks['bot']!.length, rack.length + 1, reason: 'tiles returned and one drawn');
        expect(h.racks['bot']!.toSet().containsAll(rack), true);
        expect(h.pile.length, pileBefore - 1);
        async.elapse(const Duration(milliseconds: 4000));
        expect(h.board.allTiles, isEmpty, reason: 'no stray placements after the timeout');
        expect(h.preview, isNull);
        expect(h.racks['bot']!.length, rack.length + 1);
        d.dispose();
        h.dispose();
      });
    });

    test('under 5 s with a valid table, a move that passes through invalid states is not started', () {
      fakeAsync((async) {
        final rack = [r(1), r(2), r(3), b(1), b(2), b(3), r(13), y(13)];
        final h = botGame(7, rack);
        final d = scripted(h, BotPlan([
          BotMove([BotStep.newSet([r(1), r(2), r(3)])]),
          BotMove([BotStep.tileAt(b(1), 2, 0), BotStep.tileAt(b(2), 2, 1), BotStep.tileAt(b(3), 2, 2)]),
        ]));
        // After the 1 s start delay the first set lands at 1 s; at 3 s only
        // 4 s remain, so the tile-by-tile move is skipped and the turn ends at once.
        async.elapse(const Duration(milliseconds: 3100));
        expect(h.currentPlayer.id, 'me');
        expect(h.board.allTiles.toSet(), {r(1), r(2), r(3)});
        expect(h.racks['bot']!.toSet(), {b(1), b(2), b(3), r(13), y(13)}, reason: 'kept, and no draw');
        d.dispose();
        h.dispose();
      });
    });

    test('with plenty of time the same multi-step move is played in full', () {
      fakeAsync((async) {
        final rack = [r(1), r(2), r(3), b(1), b(2), b(3), r(13), y(13)];
        final h = botGame(60, rack);
        final d = scripted(h, BotPlan([
          BotMove([BotStep.newSet([r(1), r(2), r(3)])]),
          BotMove([BotStep.tileAt(b(1), 2, 0), BotStep.tileAt(b(2), 2, 1), BotStep.tileAt(b(3), 2, 2)]),
        ]));
        async.elapse(const Duration(milliseconds: 2000));
        expect(h.preview!.allTiles.length, 3, reason: 'new set shown first (after the 1 s start delay)');
        async.elapse(const Duration(milliseconds: 1600)); // 3.6 s: 2 tiles of the second move so far
        expect(h.preview!.isValid, false);
        async.elapse(const Duration(milliseconds: 1000)); // 4.6 s: done and committed
        expect(h.currentPlayer.id, 'me');
        expect(h.board.isValid, true);
        expect(h.board.allTiles.length, 6);
        expect(h.racks['bot']!.toSet(), {r(13), y(13)});
        d.dispose();
        h.dispose();
      });
    });

    test('a bot takes no action for turnStartMs at the start of its turn, then moves', () {
      fakeAsync((async) {
        final rack = [r(1), r(2), r(3), r(13), y(13)];
        final h = botGame(60, rack);
        final d = scripted(h, BotPlan([BotMove([BotStep.newSet([r(1), r(2), r(3)])])]));
        async.elapse(const Duration(milliseconds: BotTuning.turnStartMs - 10));
        expect(h.preview, isNull, reason: 'nothing yet');
        expect(h.currentPlayer.id, 'bot');
        async.elapse(const Duration(milliseconds: 20));
        expect(h.preview!.allTiles.length, 3);
        d.dispose();
        h.dispose();
      });
    });

    test('a bot that draws waits turnStartMs first, and the wait counts against its timer', () {
      fakeAsync((async) {
        final rack = [r(1), b(5), y(9), k(13)];
        final h = botGame(60, rack);
        final pile = h.pile.length;
        final d = BotDriver(h, planOverride: (_, _) => const BotPlan([]))..start();
        async.flushMicrotasks();
        expect(h.pile.length, pile, reason: 'no instant draw');
        async.elapse(const Duration(milliseconds: 500));
        expect(h.currentPlayer.id, 'bot');
        expect(h.msLeft, lessThanOrEqualTo(59500), reason: 'the turn clock runs during the delay');
        async.elapse(const Duration(milliseconds: BotTuning.turnStartMs));
        expect(h.pile.length, pile - 1);
        expect(h.currentPlayer.id, 'me');
        d.dispose();
        h.dispose();
      });
    });

    test('pause timing per action follows BotTuning', () {
      expect(stepPauseMs(const BotStep.newSet([1, 2, 3])), BotTuning.newSetMs);
      expect(stepPauseMs(const BotStep.extend(4, 1, true)), BotTuning.singleTileMs);
      expect(stepPauseMs(const BotStep.tileAt(4, 0, 0)), BotTuning.singleTileMs);
      expect(moveStaysValid(Board.empty(), BotMove([BotStep.newSet([r(1), r(2), r(3)])])), true);
      expect(moveStaysValid(Board.empty(), BotMove([BotStep.tileAt(r(1), 0, 0), BotStep.tileAt(r(2), 0, 1)])), false);
    });
  });

  group('Draw button', () {
    test('Draw draws for the drawer only, ends the turn at once, and the bot draws only after its delay', () {
      fakeAsync((async) {
        final h = GameHost(
          players: const [
            PlayerInfo('me', 'Me', SeatKind.human),
            PlayerInfo('bot', 'Bot', SeatKind.bot),
          ],
          rules: const HouseRules(firstMeld: 30, turnSeconds: 0),
          test: const TestTools(enabled: true, seed: 3),
        )..startRound();
        final d = BotDriver(h, planOverride: (_, _) => const BotPlan([]))..start();
        final views = <PlayerView>[];
        final sub = h.changes.listen((_) => views.add(h.viewFor('me')));
        final myRack = h.racks['me']!.length, botRack = h.racks['bot']!.length, pile = h.pile.length;
        final seq = h.drawSeq;
        expect(h.currentPlayer.id, 'me');

        expect(h.handle('me', const DrawAction()).ok, true);
        // The turn has ended immediately: it's the bot's turn, I drew exactly one tile.
        expect(h.currentPlayer.id, 'bot');
        expect(h.racks['me']!.length, myRack + 1);
        expect(h.racks['bot']!.length, botRack);
        expect(h.pile.length, pile - 1);
        expect(h.drawSeq, seq + 1);
        expect(h.drawPlayer, 'me', reason: 'the draw animation targets my rack');
        expect(h.drawCount, 1);
        expect(views.last.myTurn, false);

        // Nothing else happens straight away: no second (bot) draw in the same moment.
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: BotTuning.turnStartMs - 50));
        expect(h.drawSeq, seq + 1);
        expect(h.racks['bot']!.length, botRack);
        expect(views.where((v) => v.drawSeq == seq + 1).every((v) => v.drawPlayer == 'me'), true);

        // After its start delay the bot draws (its own animation), and the turn comes back to me.
        async.elapse(const Duration(milliseconds: 100));
        expect(h.drawSeq, seq + 2);
        expect(h.drawPlayer, 'bot');
        expect(h.racks['bot']!.length, botRack + 1);
        expect(h.racks['me']!.length, myRack + 1);
        expect(h.currentPlayer.id, 'me');
        sub.cancel();
        d.dispose();
        h.dispose();
      });
    });
  });
}
