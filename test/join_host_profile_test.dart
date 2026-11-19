import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/net/online.dart';
import 'package:michikub/net/peer.dart';
import 'package:michikub/ui/fullscreen_button.dart';
import 'package:michikub/ui/home.dart';
import 'package:michikub/ui/online_screens.dart';

/// A guest's connection that records what the host sends.
class _FakeLink implements PeerLink {
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> close() async {}
  @override
  void send(String text) => sent.add(jsonDecode(text) as Map<String, dynamic>);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Pumps [w] at [size]; any layout error (overflow included) fails the test.
Future<void> pumpAt(WidgetTester tester, Size size, Widget w) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: w));
  await tester.pump();
}

void main() {
  setUp(() {
    final p = AppPrefs.instance;
    p.name = 'Ann';
    p.avatar = null;
    p.iosHintDismissed = false;
  });

  group('Join a game layout', () {
    for (final size in const [Size(360, 740), Size(390, 844), Size(430, 932)]) {
      testWidgets('portrait ${size.width.toInt()}x${size.height.toInt()}: logo, title, tagline over the form, centred, no overflow',
          (tester) async {
        await pumpAt(tester, size, const JoinScreen(initialCode: 'ABCDEF', offerApp: true, showFullscreen: true));
        expect(tester.takeException(), isNull);
        final brand = tester.getRect(find.byType(BrandBlock));
        final form = tester.getRect(find.byKey(const ValueKey('joinForm')));
        expect(find.text('Michikub'), findsOneWidget);
        expect(find.text('Play with friends. No ads, no subscription.'), findsOneWidget);
        expect(brand.bottom, lessThanOrEqualTo(form.top), reason: 'brand above the form');
        expect((brand.center.dx - size.width / 2).abs(), lessThan(1));
        expect((form.center.dx - size.width / 2).abs(), lessThan(1));
        expect(form.left, greaterThanOrEqualTo(16));
        expect(form.right, lessThanOrEqualTo(size.width - 16));
        expect(form.bottom, lessThanOrEqualTo(size.height), reason: 'everything fits without scrolling');
        expect(tester.getSize(find.byType(Image).first).width, lessThan(170), reason: 'a smaller logo than Home');
        for (final k in ['joinName', 'joinCode', 'joinButton', 'openInApp', 'avatarButton']) {
          final r = tester.getRect(find.byKey(ValueKey(k)));
          expect(r.left >= 0 && r.right <= size.width, true, reason: '$k at $r');
        }
        expect(tester.getRect(find.byKey(const ValueKey('fullscreen'))).right, lessThanOrEqualTo(size.width));
      });
    }

    for (final size in const [Size(844, 390), Size(1280, 720), Size(667, 375)]) {
      testWidgets('landscape ${size.width.toInt()}x${size.height.toInt()}: side by side, no overflow', (tester) async {
        await pumpAt(tester, size, const JoinScreen(initialCode: 'ABCDEF'));
        expect(tester.takeException(), isNull);
        final brand = tester.getRect(find.byType(BrandBlock));
        final form = tester.getRect(find.byKey(const ValueKey('joinForm')));
        expect(brand.right, lessThanOrEqualTo(form.left));
        expect(form.right, lessThanOrEqualTo(size.width));
        expect(find.byKey(const ValueKey('fullscreen')), findsNothing, reason: 'not the web build');
      });
    }

    testWidgets('a very short window scrolls instead of overflowing', (tester) async {
      await pumpAt(tester, const Size(360, 300), const JoinScreen());
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('joinButton'))).bottom, lessThanOrEqualTo(300));
    });

    testWidgets('home keeps its full-size logo and title (same widgets)', (tester) async {
      await pumpAt(tester, const Size(1280, 720), const HomeScreen(fitToScreen: false));
      expect(tester.getSize(find.byType(Image).first), const Size(170, 170));
    });
  });

  group('iPhone full screen hint', () {
    testWidgets('shows instead of the button; tapping explains Add to Home Screen; closing hides it for good', (tester) async {
      await pumpAt(tester, const Size(390, 844), const Scaffold(body: Center(child: FullscreenButton(showButton: false, showIosHint: true))));
      expect(find.byKey(const ValueKey('fullscreen')), findsNothing);
      expect(find.byKey(const ValueKey('iosFullscreenHint')), findsOneWidget);
      await tester.tap(find.text('Full screen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to Home Screen'), findsWidgets);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('iosHintClose')));
      await tester.pump();
      expect(find.byKey(const ValueKey('iosFullscreenHint')), findsNothing);
      expect(AppPrefs.instance.iosHintDismissed, true);
    });

    testWidgets('compact (Home): a round share button; its help can hide it for good', (tester) async {
      await pumpAt(tester, const Size(844, 390), const Scaffold(body: Center(child: FullscreenButton(showButton: false, showIosHint: true, compact: true))));
      expect(tester.getSize(find.byKey(const ValueKey('iosFullscreenHint'))), const Size(46, 46));
      await tester.tap(find.byKey(const ValueKey('iosFullscreenHint')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('iosHintHide')));
      await tester.tap(find.byKey(const ValueKey('iosHintHide')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('iosFullscreenHint')), findsNothing);
      expect(AppPrefs.instance.iosHintDismissed, true);
    });

    testWidgets('nothing outside the web build / when already full screen from the home screen', (tester) async {
      await pumpAt(tester, const Size(390, 844), const Scaffold(body: Center(child: FullscreenButton())));
      expect(find.byKey(const ValueKey('fullscreen')), findsNothing);
      expect(find.byKey(const ValueKey('iosFullscreenHint')), findsNothing);
    });
  });

  group('Host a game: your avatar and name', () {
    late NetHost net;
    late _FakeLink guest;

    Future<void> openLobby(WidgetTester tester, Size size) async {
      net = NetHost('Ann', const HouseRules(), open: false)..code = 'ABCDEF';
      guest = _FakeLink();
      net.seats.add(NetSeat(const PlayerInfo('g1', 'Bob', SeatKind.human), guest));
      await pumpAt(tester, size, HostLobbyScreen(net: net));
    }

    List<Map<String, dynamic>> hostInLobbies() => [
          for (final m in guest.sent)
            if (m['t'] == 'lobby') ((m['players'] as List).first as Map).cast<String, dynamic>(),
        ];

    testWidgets('tap your avatar to pick one: saved, shown and sent to the guests', (tester) async {
      await openLobby(tester, const Size(844, 390));
      await tester.tap(find.byKey(const ValueKey('hostAvatar')));
      await tester.pumpAndSettle();
      final first = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('avatar:')).first;
      final id = (tester.widget(first).key as ValueKey<String>).value.substring('avatar:'.length);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(AppPrefs.instance.avatar, id);
      expect(net.seats.first.info.avatar, id);
      expect(hostInLobbies().last['avatar'], id);
      expect(net.seats.first.info.name, 'Ann');
      await tester.pumpWidget(const SizedBox());
    });

    for (final size in const [Size(844, 390), Size(390, 844)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}: edit your name inline: guests see it, it is saved, empty goes back', (tester) async {
        await openLobby(tester, size);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(const ValueKey('hostName')), 'Annie');
        await tester.pump();
        expect(net.seats.first.info.name, 'Annie');
        expect(net.myName, 'Annie');
        expect(hostInLobbies().last['name'], 'Annie');
        await tester.pump(const Duration(seconds: 1));
        expect(AppPrefs.instance.name, 'Annie');
        await tester.enterText(find.byKey(const ValueKey('hostName')), '');
        await tester.pump();
        expect(net.seats.first.info.name, 'Annie', reason: 'never empty');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(tester.widget<TextField>(find.byKey(const ValueKey('hostName'))).controller!.text, 'Annie');
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
