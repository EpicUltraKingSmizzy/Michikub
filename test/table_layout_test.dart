import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/home.dart';
import 'package:michikub/ui/table_geo.dart';

const sizes = [Size(844, 390), Size(667, 375), Size(932, 430), Size(1280, 720), Size(1920, 1080), Size(2560, 1080), Size(1366, 600)];

void main() {
  group('corner buttons (geometry)', () {
    for (final size in sizes) {
      test('${size.width.toInt()}x${size.height.toInt()}: nothing overlaps', () {
        final g = TableGeo(size, boardRows: 3, rackEntries: List.generate(14, (i) => i), seatCount: 4);
        final screen = Offset.zero & size;
        for (final r in [g.menuRect, g.roundRect, g.resetRect, g.drawRect]) {
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(.1, .1)), true, reason: '$r on screen');
        }
        // Same size as the 777/789 sort buttons (46).
        for (final r in [g.menuRect, g.roundRect, g.resetRect]) {
          expect(r.size, const Size(46, 46));
        }
        // Top strip: Menu and Round sit above the board.
        expect(g.menuRect.bottom, lessThanOrEqualTo(g.boardRect.top));
        expect(g.roundRect.bottom, lessThanOrEqualTo(g.boardRect.top));
        // Round: just left of the pile, clear of the top seat's face-down line.
        expect(g.roundRect.right, lessThan(g.pileRect.left));
        expect(g.pileRect.left - g.roundRect.right, lessThanOrEqualTo(10));
        expect(g.roundRect.left, greaterThan(g.backRect(SeatPos.top, 9, 14).right));
        // Menu: clear of the left seat's avatar and its count badge (6 px above it).
        final left = g.seatCenter(SeatPos.left);
        expect(g.menuRect.bottom, lessThan(left.dy - g.avatar / 2 - 6));
        // Reset in the bottom-right corner; Draw from the rack to Reset, clear of both.
        expect(size.width - g.resetRect.right, 10);
        expect(size.height - g.resetRect.bottom, 10);
        expect(g.drawRect.left, greaterThan(g.rackRect.right));
        expect(g.drawRect.left - g.rackRect.right, lessThanOrEqualTo(8));
        expect(g.drawRect.right, lessThan(g.resetRect.left));
        expect(g.drawRect.width, greaterThanOrEqualTo(85), reason: 'room for "End turn" (no icon under 115)');
        // The right seat's face-down tiles end above them.
        expect(g.backRect(SeatPos.right, 13, 14).bottom, lessThan(g.drawRect.top));
      });
    }
  });

  group('game screen', () {
    late GameHost host;
    late LocalSession s;

    Future<void> pumpGame(WidgetTester tester, Size size) async {
      AppPrefs.instance.highlightValid = false;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      host = GameHost(
        players: const [
          PlayerInfo('p0', 'Ann', SeatKind.human),
          PlayerInfo('p1', 'Bob', SeatKind.human),
          PlayerInfo('p2', 'Cy', SeatKind.human),
          PlayerInfo('p3', 'Di', SeatKind.human),
        ],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
        seed: 3,
      );
      s = LocalSession(host, hotSeat: false);
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      s.leave();
      tester.view.reset();
    }

    for (final size in const [Size(844, 390), Size(1920, 1080)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: buttons in their corners, none overlapping', (tester) async {
        await pumpGame(tester, size);
        Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
        final menu = r('menuButton'), round = r('roundButton'), reset = r('resetButton'), draw = r('drawButton');
        final pile = r('pile'), sort = r('sort789');
        expect(menu.topLeft, const Offset(6, 3));
        expect(menu.size, sort.size, reason: 'the size of the 777/789 buttons');
        expect(round.size, sort.size);
        expect(reset.size, sort.size);
        expect(reset.bottomRight, Offset(size.width - 10, size.height - 10));
        expect(round.right < pile.left && round.top < pile.bottom, true);
        final all = {'menu': menu, 'round': round, 'reset': reset, 'draw': draw, 'pile': pile, 'sort': sort, 'sort777': r('sort777'), 'me': r('myAvatar')};
        for (final a in all.entries) {
          for (final b in all.entries) {
            if (a.key.compareTo(b.key) < 0) expect(a.value.overlaps(b.value), false, reason: '${a.key} ${a.value} / ${b.key} ${b.value}');
          }
        }
        await done(tester);
      });
    }

    testWidgets('the Round button shows the round and opens the scores; a tap anywhere closes them', (tester) async {
      await pumpGame(tester, const Size(1200, 560));
      expect(find.descendant(of: find.byKey(const ValueKey('roundButton')), matching: find.text('ROUND')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('roundButton')), matching: find.text('1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('roundButton')));
      await tester.pump();
      expect(find.byKey(const ValueKey('scoresOverlay')), findsOneWidget);
      for (final n in ['Ann (you)', 'Bob', 'Cy', 'Di', 'Total']) {
        expect(find.descendant(of: find.byKey(const ValueKey('scoresOverlay')), matching: find.text(n)), findsOneWidget, reason: n);
      }
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      expect(find.byKey(const ValueKey('scoresOverlay')), findsNothing);
      await done(tester);
    });

    testWidgets('Menu opens from the top-left button (no full screen item outside the web)', (tester) async {
      await pumpGame(tester, const Size(1200, 560));
      await tester.tap(find.byKey(const ValueKey('menuButton')));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      expect(find.byKey(const ValueKey('menuFullscreen')), findsNothing);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      await done(tester);
    });
  });

  testWidgets('web home: the full screen button sits in the top-right corner, clear of the menu', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('RenderFlex overflowed')) old?.call(d);
    };
    await tester.pumpWidget(const MaterialApp(home: HomeScreen(fitToScreen: true, showFullscreen: true)));
    final fs = tester.getRect(find.byKey(const ValueKey('fullscreen')));
    expect(fs.right, 844 - 6);
    expect(fs.top, 6);
    for (final t in ['Play vs bots', 'Options', 'Michikub']) {
      expect(tester.getRect(find.text(t)).overlaps(fs), false, reason: t);
    }
    await tester.pumpWidget(const MaterialApp(home: HomeScreen(fitToScreen: false)));
    FlutterError.onError = old;
    expect(find.byKey(const ValueKey('fullscreen')), findsNothing, reason: 'the apps: unchanged');
    tester.view.reset();
  });
}
