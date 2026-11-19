import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Browser full screen through the Fullscreen API, so the page gets the whole screen without
/// the address bar and tabs. iPhone Safari (and so every iPhone browser) doesn't offer it for
/// web pages: [supported] is false there and the button is hidden; Add to Home Screen is the
/// way to lose the bars on an iPhone (the manifest asks for full screen).
class Fullscreen {
  static bool? _supported;
  static bool get supported => _supported ??= _check();

  static bool _check() {
    try {
      final doc = web.document as JSObject;
      final enabled = doc['fullscreenEnabled']?.dartify() == true;
      final can = (web.document.documentElement as JSObject?)?.has('requestFullscreen') ?? false;
      if (enabled && can) _listen();
      return enabled && can;
    } catch (_) {
      return false;
    }
  }

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static void _listen() {
    web.document.addEventListener(
        'fullscreenchange', ((web.Event _) => active.value = web.document.fullscreenElement != null).toJS);
  }

  /// Enters or leaves full screen. Must run inside a tap (browsers only allow it then).
  static Future<void> toggle() async {
    if (!supported) return;
    try {
      if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      } else {
        await web.document.documentElement!.requestFullscreen().toDart;
      }
    } catch (e) {
      debugPrint('full screen: $e');
    }
    active.value = web.document.fullscreenElement != null;
  }
}
