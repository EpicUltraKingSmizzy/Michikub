import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import 'sfx_format.dart';

/// Sounds in the browser, through the Web Audio API: each file is decoded once into a buffer
/// and every play starts a new (cheap) source, so plays overlap and start right away.
///
/// Browsers keep audio locked until the first tap or key press (iPhones strictly), so the
/// first one also unlocks it: the context is resumed and a silent sound started inside that
/// event. Sounds asked for before then are skipped, as there's no one to hear them yet.
class WebAudio {
  static web.AudioContext? _ctx;
  static final _buffers = <String, web.AudioBuffer>{};
  static String format = 'ogg';

  static bool get available {
    try {
      return (web.window as JSObject).has('AudioContext'); // Safari 14.1+ (iOS 14.5+), all current browsers
    } catch (_) {
      return false;
    }
  }

  static Future<void> init(Iterable<String> files) async {
    final ctx = _ctx ??= web.AudioContext();
    _hookUnlock();
    final nav = web.window.navigator;
    format = webSoundFormat(
      oggSupport: web.HTMLAudioElement().canPlayType('audio/ogg; codecs="vorbis"'),
      userAgent: nav.userAgent,
      maxTouchPoints: nav.maxTouchPoints,
    );
    for (final f in files) {
      if (_buffers.containsKey(f)) continue;
      for (final ext in [format, otherSoundFormat(format)]) {
        try {
          final data = await rootBundle.load('assets/sfx/$f.$ext');
          final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
          _buffers[f] = await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
          break;
        } catch (e) {
          debugPrint('sound $f.$ext: $e');
        }
      }
    }
  }

  static void play(String file) {
    final ctx = _ctx, buf = _buffers[file];
    if (ctx == null || buf == null) return;
    if (ctx.state != 'running') ctx.resume();
    final src = ctx.createBufferSource()..buffer = buf;
    src.connect(ctx.destination);
    src.start();
  }

  static bool _hooked = false;

  /// Unlocks audio inside the first taps / key presses (until it's running), and again after
  /// the browser suspends it (iPhone: the tab went to the background, a call came in).
  static void _hookUnlock() {
    if (_hooked) return;
    _hooked = true;
    final unlock = ((web.Event _) {
      final ctx = _ctx;
      if (ctx == null || ctx.state == 'running') return;
      ctx.resume();
      final silent = ctx.createBuffer(1, 1, 22050);
      final src = ctx.createBufferSource()..buffer = silent;
      src.connect(ctx.destination);
      src.start();
    }).toJS;
    for (final type in ['pointerdown', 'touchend', 'mousedown', 'keydown']) {
      web.document.addEventListener(type, unlock, true.toJS);
    }
  }
}
