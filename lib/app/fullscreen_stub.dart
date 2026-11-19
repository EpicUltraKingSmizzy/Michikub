import 'package:flutter/foundation.dart';

/// Browser full screen (web only; the apps already fill the screen).
class Fullscreen {
  static bool get supported => false;
  static final ValueNotifier<bool> active = ValueNotifier(false);
  static Future<void> toggle() async {}

  /// iPhone/iPad browser tab (no Fullscreen API): show the Add to Home Screen hint.
  static bool get iosHomeScreenHint => false;
}
