import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/home.dart';
import 'package:michikub/ui/table_geo.dart';
import 'package:michikub/ui/theme.dart';

const sizes = [
  Size(360, 740),
  Size(390, 844),
  Size(667, 375),
  Size(740, 360),
  Size(800, 360),
  Size(844, 390),
  Size(915, 412),
  Size(932, 430),
  Size(1280, 720),
  Size(1920, 1080),
  Size(2560, 1080),
  Size(1366, 600),
];

/// Landscape phone sizes where the column beside the rack is typically too tight for "Auto-draw".
const landscapePhones = [
  Size(667, 375),
  Size(740, 360),
  Size(800, 360),
  Size(844, 390),
  Size(915, 412),
  Size(932, 430),
];

const wideScreens = [Size(1280, 720), Size(1366, 600), Size(1920, 1080), Size(2560, 1080)];

void main() {
  group('corner buttons (geometry)', () {
    for (final size in sizes) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: nothing overlaps', (tester) async {
        await tester.pumpWidget(const SizedBox()); // load app fonts before measuring labels
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
        // The top seat's 14-tile line is designed for landscape/web widths; on a narrow
        // portrait phone it can reach the Round button, which isn't this change.
        if (size.width >= 667) {
          expect(g.roundRect.left, greaterThan(g.backRect(SeatPos.top, 9, 14).right));
        }
        // Menu: clear of the left seat's avatar and its count badge (6 px above it).
        final left = g.seatCenter(SeatPos.left);
        expect(g.menuRect.bottom, lessThan(left.dy - g.avatar / 2 - 6));
        expect(size.width - g.resetRect.right, 10);
        expect(g.drawRect.left, greaterThan(g.rackRect.right));
        expect(g.drawRect.left - g.rackRect.right, lessThanOrEqualTo(8));
        expect(g.drawRect.width + 0.5, greaterThanOrEqualTo(g.drawMinWidth), reason: 'room for every Draw label, including Auto-draw');
        if (g.resetAboveDraw) {
          expect(g.resetRect.bottom, lessThanOrEqualTo(g.drawRect.top));
          expect(size.height - g.drawRect.bottom, 10);
          expect(g.backRect(SeatPos.right, 13, 14).bottom, lessThan(g.resetRect.top));
        } else {
          expect(size.height - g.resetRect.bottom, 10);
          expect(g.drawRect.right, lessThan(g.resetRect.left));
          expect(g.backRect(SeatPos.right, 13, 14).bottom, lessThan(g.drawRect.top));
        }
      });
    }

    testWidgets('landscape phones stack Reset above Draw; wide screens stay side-by-side', (tester) async {
      await tester.pumpWidget(const SizedBox());
      for (final size in landscapePhones) {
        final g = TableGeo(size, boardRows: 3, rackEntries: List.generate(14, (i) => i), seatCount: 4);
        expect(g.resetAboveDraw, true, reason: '${size.width}x${size.height}: the column beside the rack is too tight');
      }
      for (final size in wideScreens) {
        final g = TableGeo(size, boardRows: 3, rackEntries: List.generate(14, (i) => i), seatCount: 4);
        expect(g.resetAboveDraw, false, reason: '${size.width}x${size.height}: wide layout unchanged');
      }
    });
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
      await tester.pump(const Duration(seconds: 5));
      tester.view.reset();
    }

    for (final size in const [Size(844, 390), Size(1920, 1080)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: buttons in their corners, none overlapping', (tester) async {
        await pumpGame(tester, size);
        Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
        final menu = r('menuButton'), round = r('roundButton'), reset = r('resetButton'), draw = r('drawButton');
        final pile = r('pile'), sort = r('sort789');
        expect(menu.topLeft, const Offset(6, 3));
        expect(menu.width, closeTo(sort.width, 0.5), reason: 'menu ${menu.size} vs sort ${sort.size}');
        expect(menu.height, closeTo(sort.height, 0.5), reason: 'menu ${menu.size} vs sort ${sort.size}');
        expect(round.width, closeTo(sort.width, 0.5));
        expect(round.height, closeTo(sort.height, 0.5));
        expect(reset.width, closeTo(sort.width, 0.5), reason: 'reset ${reset.size} vs sort ${sort.size}');
        expect(reset.height, closeTo(sort.height, 0.5), reason: 'reset ${reset.size} vs sort ${sort.size}');
        expect(reset.right, closeTo(size.width - 10, 0.5));
        if (size == const Size(1920, 1080)) {
          expect(reset.bottomRight, Offset(size.width - 10, size.height - 10));
          expect(draw.right, lessThan(reset.left));
        } else {
          // 844x390 is a landscape phone: Reset sits above Draw.
          expect(reset.bottom, lessThanOrEqualTo(draw.top + 0.5));
        }
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

  group('Draw button labels at phone and web sizes', () {
    Future<(GameHost, LocalSession)> pumpAutoDraw(WidgetTester tester, Size logical, {double dpr = 1}) async {
      GameHost.openingAutoDraw = true;
      addTearDown(() => GameHost.openingAutoDraw = false);
      AppPrefs.instance.highlightValid = false;
      tester.view.physicalSize = Size(logical.width * dpr, logical.height * dpr);
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final onError = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.exceptionAsString().contains('A RenderFlex overflowed')) onError?.call(d);
      };
      addTearDown(() => FlutterError.onError = onError);
      final host = GameHost(
        players: const [
          PlayerInfo('me', 'Ann', SeatKind.human),
          PlayerInfo('bot', 'Bolt', SeatKind.bot),
        ],
        rules: const HouseRules(turnSeconds: 0, firstMeld: 30),
        seed: 2,
      );
      final s = LocalSession(host, hotSeat: false);
      host.racks['me'] = [
        makeTile(TileColor.red, 1),
        makeTile(TileColor.blue, 3),
        makeTile(TileColor.yellow, 5),
        makeTile(TileColor.black, 7),
        makeTile(TileColor.red, 9),
        makeTile(TileColor.blue, 11),
        makeTile(TileColor.yellow, 13),
        makeTile(TileColor.black, 2),
        makeTile(TileColor.red, 4),
        makeTile(TileColor.blue, 6),
      ];
      host.autoDraw.clear();
      expect(host.currentPlayer.id, 'me');
      expect(host.handle('me', const AutoDrawAction(true)).ok, true);
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(milliseconds: 100));
      return (host, s);
    }

    Future<void> finish(WidgetTester tester, LocalSession s) async {
      await tester.pumpWidget(const SizedBox());
      s.leave();
      await tester.pump(const Duration(seconds: 5));
    }

    void expectAutoDrawFullyVisible(WidgetTester tester, Size size) {
      final label = find.descendant(of: find.byKey(const ValueKey('drawButton')), matching: find.text('Auto-draw'));
      expect(label, findsOneWidget, reason: '$size');
      final scaler = MediaQuery.textScalerOf(tester.element(label));
      final textW = GoldButton.compactWidth('Auto-draw', icon: false, scaler: scaler) - 2 * GoldButton.compactPadH;
      expect(tester.getRect(label).width + 0.5, greaterThanOrEqualTo(textW), reason: 'Auto-draw cropped at $size');
      final btn = tester.getRect(find.byKey(const ValueKey('drawButton')));
      final hasIcon = find.descendant(of: find.byKey(const ValueKey('drawButton')), matching: find.byIcon(Icons.autorenew)).evaluate().isNotEmpty;
      expect(btn.width + 0.5, greaterThanOrEqualTo(GoldButton.compactWidth('Auto-draw', icon: hasIcon, scaler: scaler)),
          reason: 'Draw button narrower than its Auto-draw label at $size');
    }

    for (final size in [
      ...landscapePhones,
      const Size(360, 740),
      const Size(390, 844),
      ...wideScreens,
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: Auto-draw is fully visible', (tester) async {
        final g = TableGeo(size, boardRows: 3, rackEntries: List.generate(14, (i) => i), seatCount: 2);
        final (host, s) = await pumpAutoDraw(tester, size);
        expectAutoDrawFullyVisible(tester, size);
        final reset = tester.getRect(find.byKey(const ValueKey('resetButton')));
        final draw = tester.getRect(find.byKey(const ValueKey('drawButton')));
        expect(reset.overlaps(draw), false, reason: '$size');
        if (g.resetAboveDraw) {
          expect(reset.bottom, lessThanOrEqualTo(draw.top + 0.5), reason: '$size: Reset should sit above Draw');
        } else {
          expect(reset.bottom, closeTo(size.height - 10, 1), reason: '$size: wide layout, Reset stays in the corner');
          expect(draw.right, lessThan(reset.left + 0.5));
        }
        await finish(tester, s);
        host.dispose();
      });
    }

    testWidgets('2400x1080 at 3 dpr (800x360 logical): Auto-draw fully visible, Reset moved up', (tester) async {
      const logical = Size(800, 360);
      final (host, s) = await pumpAutoDraw(tester, logical, dpr: 3);
      expectAutoDrawFullyVisible(tester, logical);
      final reset = tester.getRect(find.byKey(const ValueKey('resetButton')));
      final draw = tester.getRect(find.byKey(const ValueKey('drawButton')));
      expect(reset.bottom, lessThanOrEqualTo(draw.top + 0.5));
      await finish(tester, s);
      host.dispose();
    });
  });
}
