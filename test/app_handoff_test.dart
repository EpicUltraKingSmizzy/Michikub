import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/sfx_format.dart';
import 'package:michikub/net/app_handoff.dart';
import 'package:michikub/net/invite_link.dart';
import 'package:michikub/ui/online_screens.dart';
import 'package:qr_flutter/qr_flutter.dart';

const android = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0 Mobile/15E148 Safari/604.1';
const desktop = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

void main() {
  group('app hand-off', () {
    test('the intent link opens michikub://join/CODE in the app and falls back to the web, flagged', () {
      final url = androidIntentUrl('abcd');
      expect(url, startsWith('intent://join/ABCD#Intent;scheme=michikub;package=com.michikub.michikub;'));
      expect(url, endsWith(';end'));
      final fb = Uri.decodeComponent(RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url)!.group(1)!);
      expect(fb, 'https://epicultrakingsmizzy.github.io/Michikub/?join=ABCD&web=1');
      expect(codeFromAppLink(Uri.parse(fb)), 'ABCD', reason: 'the fallback still joins the room');
    });

    test('offered only for join links in an Android browser, never after a fallback (no loop)', () {
      final link = Uri.parse(webJoinLink('ABCD'));
      expect(offersAppHandoff(link, android), true);
      expect(offersAppHandoff(Uri.parse(webFallbackLink('ABCD')), android), false, reason: 'web=1: stay');
      expect(offersAppHandoff(link, iphone), false, reason: 'no iPhone app');
      expect(offersAppHandoff(link, desktop), false);
      expect(offersAppHandoff(Uri.parse(kWebAppUrl), android), false, reason: 'not a join link');
      expect(offersAppHandoff(Uri.parse('$kWebAppUrl?join=AB12'), android), false);
    });

    test('index.html tries the same hand-off before loading, and the Android manifest takes it', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains("'intent://join/' + code + '#Intent;scheme=michikub;package=$kAndroidPackage;'"));
      expect(html, contains("q.has('$kStayOnWeb')"), reason: 'the fallback (web=1) stays on the web');
      expect(html, contains("'?join=' + code + '&$kStayOnWeb=1'"));
      expect(html, contains('/Android/i.test(navigator.userAgent)'));
      expect(html.indexOf('intent://'), lessThan(html.indexOf('flutter_bootstrap.js')), reason: 'before the game loads');
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('<data android:scheme="michikub" android:host="join"/>'));
      expect(manifest, contains('android.intent.category.BROWSABLE'));
      expect(File('android/app/build.gradle.kts').readAsStringSync(), contains('applicationId = "$kAndroidPackage"'));
    });

    testWidgets('Join screen: "Open in the app" when offered, not otherwise', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: JoinScreen(initialCode: 'ABCD', offerApp: true)));
      expect(find.byKey(const ValueKey('openInApp')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MaterialApp(home: JoinScreen(initialCode: 'WXYZ')));
      expect(find.byKey(const ValueKey('openInApp')), findsNothing, reason: 'not the web build');
    });
  });

  group('QR code', () {
    test('encodes the web join link', () {
      final v = QrValidator.validate(data: webJoinLink('abcd'), version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.L);
      expect(v.isValid, true);
      expect(webJoinLink('abcd'), 'https://epicultrakingsmizzy.github.io/Michikub/?join=ABCD');
    });

    testWidgets('dark on white, a scannable size', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: InviteQr(code: 'ABCD')))));
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(tester.widget<InviteQr>(find.byType(InviteQr)).code, 'ABCD');
      expect(qr.backgroundColor, Colors.white);
      expect(qr.eyeStyle.color, Colors.black);
      expect(qr.dataModuleStyle.color, Colors.black);
      expect(tester.getSize(find.byKey(const ValueKey('inviteQr'))).width, greaterThanOrEqualTo(120));
    });
  });

  group('web sound format', () {
    test('iPhones and iPads (every browser there is WebKit) get .m4a; others .ogg if they play it', () {
      expect(webSoundFormat(oggSupport: 'probably', userAgent: iphone), 'm4a', reason: 'Chrome on iPhone too');
      expect(webSoundFormat(oggSupport: '', userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15', maxTouchPoints: 5), 'm4a',
          reason: 'iPad asking for the desktop site');
      expect(webSoundFormat(oggSupport: 'probably', userAgent: android), 'ogg');
      expect(webSoundFormat(oggSupport: 'maybe', userAgent: desktop), 'ogg');
      expect(webSoundFormat(oggSupport: '', userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/16.0 Safari/605.1.15'), 'm4a',
          reason: 'older desktop Safari without Ogg');
    });

    test('every sound has an .m4a copy next to its .ogg', () {
      final oggs = Directory('assets/sfx').listSync().map((f) => f.path).where((p) => p.endsWith('.ogg')).toList();
      expect(oggs, isNotEmpty);
      for (final o in oggs) {
        expect(File(o.replaceAll('.ogg', '.m4a')).existsSync(), true, reason: o);
      }
    });
  });
}
