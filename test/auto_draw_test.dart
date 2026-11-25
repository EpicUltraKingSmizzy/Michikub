import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);

/// A rack with no set at all.
final weak = [r(1), b(3), y(5), k(7), r(9), b(11), y(13), k(2), r(4), b(6)];

const ann = PlayerInfo('me', 'Ann', SeatKind.human);
const bob = PlayerInfo('p2', 'Bob', SeatKind.human);
const bot = PlayerInfo('bot', 'Bolt', SeatKind.bot);

GameHost makeHost({List<PlayerInfo> players = const [ann, bob], HouseRules rules = const HouseRules(turnSeconds: 0), int seed = 1}) {
  final h = GameHost(players: players, rules: rules, seed: seed);
  h.firstStarter = 0;
  return h;
}

void main() {
  setUp(() => GameHost.openingAutoDraw = true);
  tearDown(() => GameHost.openingAutoDraw = false);

  group('the first play check', () {
    test('sets worth the minimum together', () {
      expect(hasOpeningPlay(weak, 30), false);
      expect(hasOpeningPlay([...weak, r(10), r(11), r(12)], 30), true); // 33
      expect(hasOpeningPlay([r(5), r(6), r(7), b(5), y(5), k(5)], 33), true, reason: '18 + 15');
      expect(hasOpeningPlay([r(5), r(6), r(7), b(5), y(5), k(5)], 34), false);
      expect(hasOpeningPlay([r(5), r(6), r(7), b(4), y(4), k(4)], 30), true, reason: '18 + 12');
      expect(hasOpeningPlay([r(3), r(4), makeJoker(0)], 9), true);
      expect(hasOpeningPlay([r(12), r(13), makeJoker(0)], 36), true, reason: 'J-12-13');
      expect(hasOpeningPlay([r(5), r(6), r(7), r(5, 1), r(6, 1), r(7, 1)], 36), true, reason: 'both copies');
      expect(hasOpeningPlay(weak, 0), true);
    });
  });

  group('host', () {
    test('everyone starts in auto-draw unless their rack already has a first play; bots never', () {
      for (var seed = 1; seed < 30; seed++) {
        final h = makeHost(players: const [ann, bob, bot], seed: seed)..startRound();
        for (final p in [ann, bob]) {
          expect(h.autoDraw.contains(p.id), !hasOpeningPlay(h.racks[p.id]!, 30), reason: 'seed $seed ${p.id}');
        }
        expect(h.autoDraw.contains('bot'), false);
        h.dispose();
      }
    });

    test('no first-meld minimum: auto-draw is off and can\'t be turned on', () {
      final h = makeHost(rules: const HouseRules(turnSeconds: 0, firstMeld: 0))..startRound();
      expect(h.autoDraw, isEmpty);
      expect(h.handle('me', const AutoDrawAction(true)).ok, false);
      expect(h.viewFor('me').autoDrawAllowed, false);
      h.dispose();
    });

    test('draws and passes on its own, and stops once the rack has a first play', () {
      fakeAsync((fa) {
        final h = makeHost()..startRound();
        h.racks['me'] = List.of(weak);
        h.autoDraw.clear();
        expect(h.handle('me', const AutoDrawAction(true)).ok, true);
        expect(h.viewFor('me').autoDraw, true);
        fa.elapse(Duration(milliseconds: GameHost.autoDrawDelayMs + 10));
        expect(h.racks['me']!.length, weak.length + 1);
        expect(h.currentPlayer.id, 'p2');
        // Bob plays nothing and draws; meanwhile Ann's rack now has 33 points.
        h.autoDraw.remove('p2');
        h.racks['me']!.addAll([r(10), r(11), r(12)]);
        h.handle('p2', const DrawAction());
        expect(h.currentPlayer.id, 'me');
        expect(h.autoDraw.contains('me'), false, reason: 'a first play: auto-draw ends');
        final n = h.racks['me']!.length;
        fa.elapse(const Duration(seconds: 5));
        expect(h.racks['me']!.length, n, reason: 'no draw: Ann plays herself');
        h.dispose();
      });
    });

    test('a tap turns it off (no draw), a long press turns it back on', () {
      fakeAsync((fa) {
        final h = makeHost()..startRound();
        h.racks['me'] = List.of(weak);
        h.autoDraw.clear();
        h.handle('me', const AutoDrawAction(true));
        expect(h.handle('me', const AutoDrawAction(false)).ok, true);
        fa.elapse(const Duration(seconds: 5));
        expect(h.racks['me']!.length, weak.length);
        expect(h.currentPlayer.id, 'me');
        expect(h.viewFor('me').autoDrawAllowed, true);
        expect(h.handle('me', const AutoDrawAction(true)).ok, true);
        fa.elapse(Duration(milliseconds: GameHost.autoDrawDelayMs + 10));
        expect(h.racks['me']!.length, weak.length + 1);
        h.dispose();
      });
    });

    test('it can be toggled when it isn\'t your turn', () {
      final h = makeHost()..startRound();
      h.racks['p2'] = List.of(weak);
      h.autoDraw.clear();
      expect(h.currentPlayer.id, 'me');
      expect(h.handle('p2', const AutoDrawAction(true)).ok, true);
      expect(h.autoDraw, {'p2'});
      expect(h.handle('p2', const AutoDrawAction(false)).ok, true);
      expect(h.autoDraw, isEmpty);
      h.dispose();
    });

    test('never again after the first play', () {
      final h = makeHost()..startRound();
      h.racks['me'] = [...weak, r(10), r(11), r(12)];
      h.autoDraw.clear();
      final board = h.board.copy();
      board.rows[0].setAll(0, [r(10), r(11), r(12)]);
      expect(h.handle('me', CommitAction(board)).ok, true);
      expect(h.melded.contains('me'), true);
      expect(h.viewFor('me').autoDrawAllowed, false);
      expect(h.handle('me', const AutoDrawAction(true)).ok, false);
      h.dispose();
    });

    test('a first play in the rack already: turning it on is refused', () {
      final h = makeHost()..startRound();
      h.racks['me'] = [...weak, r(10), r(11), r(12)];
      h.autoDraw.clear();
      expect(h.handle('me', const AutoDrawAction(true)).ok, false);
      h.dispose();
    });

    test('the pile running out ends it for everyone, for good', () {
      final h = makeHost()..startRound();
      h.racks['me'] = List.of(weak);
      h.racks['p2'] = List.of(weak.map((t) => t + 52));
      h.autoDraw
        ..clear()
        ..addAll(['me', 'p2']);
      h.pile = h.pile.sublist(0, 1);
      h.handle('me', const DrawAction()); // takes the last tile
      expect(h.pile, isEmpty);
      expect(h.autoDraw, isEmpty);
      expect(h.handle('p2', const AutoDrawAction(true)).ok, false);
      expect(h.viewFor('p2').autoDrawAllowed, false);
      h.dispose();
    });

    test('the view and the action travel to guests', () {
      final h = makeHost()..startRound();
      h.racks['me'] = List.of(weak);
      h.autoDraw
        ..clear()
        ..add('me');
      final v = PlayerView.fromJson(h.viewFor('me').toJson());
      expect(v.autoDraw, true);
      expect(v.autoDrawAllowed, true);
      expect(PlayerView.fromJson(h.viewFor('p2').toJson()).autoDraw, false);
      final a = GameAction.fromJson(const AutoDrawAction(false).toJson());
      expect(a, isA<AutoDrawAction>());
      expect((a as AutoDrawAction).on, false);
      h.dispose();
    });
  });

  test('Pass-and-play: the phone skips a player in auto-draw', () {
    fakeAsync((fa) {
      // Find a deal where the starter is in auto-draw and the other player isn't.
      for (var seed = 1; seed < 400; seed++) {
        final h = GameHost(players: const [ann, bob], rules: const HouseRules(turnSeconds: 60), waitForReady: true, seed: seed);
        final s = LocalSession(h, hotSeat: true);
        final starter = h.currentPlayer;
        final other = h.players.firstWhere((p) => p.id != starter.id);
        if (!(h.isAutoDrawing(starter.id) && !h.isAutoDrawing(other.id))) {
          s.leave();
          continue;
        }
        expect(s.coverFor, other.name, reason: 'the phone goes to the one who will play');
        s.dismissCover();
        expect(s.view!.me, other.id);
        fa.elapse(Duration(milliseconds: GameHost.autoDrawAfterDealMs + 10));
        expect(h.currentPlayer.id, other.id, reason: 'the starter drew automatically');
        expect(s.coverFor, isNull, reason: 'the same person still has the phone');
        fa.flushMicrotasks();
        expect(h.msLeft, isNotNull, reason: 'their clock started without another cover');
        s.leave();
        return;
      }
      fail('no suitable seed');
    });
  });

  testWidgets('the Draw button glows in auto-draw; a tap turns it off, a long press back on', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    // The test font's wide glyphs overflow the bot's name plate once its turn starts (as in
    // the other bot table tests); only RenderFlex overflows are ignored.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('A RenderFlex overflowed')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    final h = GameHost(players: const [ann, bot], rules: const HouseRules(turnSeconds: 0), seed: 2);
    final s = LocalSession(h, hotSeat: false);
    h.racks['me'] = List.of(weak);
    h.autoDraw.clear();
    expect(h.currentPlayer.id, 'me');
    expect(h.handle('me', const AutoDrawAction(true)).ok, true);
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('autoDrawGlow')), findsOneWidget);
    expect(find.text('Auto-draw'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawButton')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.autoDraw, isEmpty);
    expect(find.byKey(const ValueKey('autoDrawGlow')), findsNothing);
    expect(find.text('Draw'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(h.racks['me']!.length, weak.length, reason: 'the tap only turned auto-draw off');
    await tester.longPress(find.byKey(const ValueKey('drawButton')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.autoDraw, {'me'});
    expect(find.byKey(const ValueKey('autoDrawGlow')), findsOneWidget);
    await tester.pump(Duration(milliseconds: GameHost.autoDrawDelayMs + 100));
    expect(h.racks['me']!.length, weak.length + 1, reason: 'drew by itself');
    await tester.pumpWidget(const SizedBox());
    s.leave();
    await tester.pump(const Duration(seconds: 5));
    tester.view.reset();
  });
}
