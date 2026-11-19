import 'package:web/web.dart' as web;

/// The browser's user agent.
String get browserUserAgent => web.window.navigator.userAgent;

/// Sends the browser to [url].
void browserNavigate(String url) => web.window.location.href = url;
