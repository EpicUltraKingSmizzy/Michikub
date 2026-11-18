import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/ui/home.dart';

const labels = ['Practice vs bots', 'Pass-and-play', 'Host a game', 'Join a game', 'Options & house rules'];
const tagline = 'Play with friends. No ads, no subscription.';

/// The test font is wider than the app's, so the button labels overflow their rows here (on
/// any layout). Those overflow reports are dropped; anything else still fails the test.
Future<void> pumpHome(WidgetTester tester, Size size, {required bool fit}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final old = FlutterError.onError;
  final other = <FlutterErrorDetails>[];
  FlutterError.onError = (d) {
    if (!d.exceptionAsString().contains('RenderFlex overflowed')) other.add(d);
  };
  await tester.pumpWidget(MaterialApp(home: HomeScreen(fitToScreen: fit)));
  await tester.pump();
  FlutterError.onError = old;
  expect(other, isEmpty);
}

void main() {
  for (final size in const [Size(1280, 720), Size(915, 330), Size(844, 340), Size(740, 300), Size(640, 300), Size(390, 844)]) {
    testWidgets('web: home menu fits ${size.width.toInt()}x${size.height.toInt()} without scrolling', (tester) async {
      await pumpHome(tester, size, fit: true);
      for (final t in [...labels, tagline, 'Michikub']) {
        final r = tester.getRect(find.text(t));
        expect(r.top >= 0 && r.bottom <= size.height, true, reason: '$t at $r');
      }
      final panel = tester.getRect(find.ancestor(of: find.text('Practice vs bots'), matching: find.byType(SizedBox)).last);
      expect(panel.left >= 0 && panel.right <= size.width && panel.bottom <= size.height, true, reason: 'menu panel at $panel');
      expect(find.byType(SingleChildScrollView), findsNothing);
      tester.view.reset();
    });
  }

  testWidgets('web: at 1280x720 nothing is scaled (same size as the apps)', (tester) async {
    await pumpHome(tester, const Size(1280, 720), fit: true);
    final web = tester.getRect(find.byType(Image).first);
    await pumpHome(tester, const Size(1280, 720), fit: false);
    expect(tester.getRect(find.byType(Image).first).size, web.size);
    tester.view.reset();
  });

  testWidgets('web: a very short window scrolls rather than shrinking further', (tester) async {
    await pumpHome(tester, const Size(640, 150), fit: true);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    tester.view.reset();
  });

  testWidgets('apps: the original layout (scrolling, no scaling) is unchanged', (tester) async {
    await pumpHome(tester, const Size(640, 300), fit: false);
    expect(const HomeScreen().fitToScreen, false, reason: 'off by default outside the web build');
    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(LayoutBuilder), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.getSize(find.byType(Image).first), const Size(170, 170));
    tester.view.reset();
  });
}
