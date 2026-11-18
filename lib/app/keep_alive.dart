import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android: a foreground service (with an ongoing notification) that keeps an online game's
/// connection alive while the app is in the background. Elsewhere (iOS, web, tests) it does
/// nothing and [active] stays false, so the game falls back to "Host away – game paused".
class LinkKeepAlive {
  static const _ch = MethodChannel('michikub/keepalive');
  static bool active = false;
  static int _users = 0;

  /// Starts (or keeps) the service; [text] is the notification line.
  static Future<void> start(String text) async {
    _users++;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      active = await _ch.invokeMethod<bool>('start', {'text': text}) ?? false;
    } catch (_) {
      active = false;
    }
  }

  /// Stops it once nothing needs it.
  static Future<void> stop() async {
    if (_users > 0) _users--;
    if (_users > 0) return;
    final was = active;
    active = false;
    if (!was) return;
    try {
      await _ch.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
