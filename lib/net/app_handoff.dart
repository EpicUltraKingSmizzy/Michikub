/// Opening a web join link (`…/Michikub/?join=ABCD`, from a QR code or a shared invite) in
/// the Android app when it's installed.
///
/// The automatic attempt happens in web/index.html, before the game loads: an Android browser
/// is sent to [androidIntentUrl]. With the app installed, Android opens it on Join a game
/// (the michikub://join intent filter in AndroidManifest.xml); without it, the browser goes
/// to the fallback, the same link plus `web=1`, which never hands off again (no loop). If the
/// browser ignores the attempt (some block app launches that don't come from a tap), the
/// page just loads and the Join screen offers an "Open in the app" button.
library;

import 'invite_link.dart';

/// The Android app's id (applicationId in android/app/build.gradle.kts).
const kAndroidPackage = 'com.michikub.michikub';

/// The query flag that keeps a link in the browser.
const kStayOnWeb = 'web';

/// The browser link the hand-off falls back to (stays on the web).
String webFallbackLink(String code) => '${webJoinLink(code)}&$kStayOnWeb=1';

/// An Android intent link opening michikub://join/CODE in the app, falling back to the web.
String androidIntentUrl(String code) {
  final c = code.trim().toUpperCase();
  return 'intent://join/$c#Intent;scheme=michikub;package=$kAndroidPackage;'
      'S.browser_fallback_url=${Uri.encodeComponent(webFallbackLink(c))};end';
}

bool isAndroidBrowser(String userAgent) => RegExp('Android', caseSensitive: false).hasMatch(userAgent);

/// Whether the web page at [uri] should offer (or try) the hand-off: a join link, opened in
/// an Android browser, not already sent back from a hand-off.
bool offersAppHandoff(Uri uri, String userAgent) =>
    codeFromAppLink(uri) != null && !uri.queryParameters.containsKey(kStayOnWeb) && isAndroidBrowser(userAgent);
