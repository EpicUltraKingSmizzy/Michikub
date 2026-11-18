import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// The game's sound effects (assets/sfx, see CREDITS.md there).
enum Sfx {
  /// A tile drawn from the pile, by you or an opponent.
  draw(['draw']),

  /// Tiles you add to a set already on the table.
  attach(['attach']),

  /// Tiles you set down on the table on their own (a new set, not touching another). Its own
  /// sound is still being chosen: until then it's the attach sound. Swap the file name here.
  place(['attach']),

  /// Menu buttons.
  click(['click']),

  /// Tapping 789 / 777 by hand (not the automatic sorts): one of three bursts at random.
  sort(['sort_A', 'sort_B', 'sort_C']),

  /// A round's deal (the start of every round, including the first).
  gameStart(['start']);

  final List<String> files;
  const Sfx(this.files);
}

/// Plays [Sfx]: short, preloaded, low-latency, overlapping. Silent until [init] succeeds (tests,
/// platforms without audio) and when Sound is off in Options.
class SoundBoard {
  static final instance = SoundBoard._();
  SoundBoard._();

  final _pools = <String, AudioPool>{};
  final _rng = math.Random();

  /// Tests: every sound asked for, played or not.
  @visibleForTesting
  final List<Sfx> log = [];

  Future<void> init() async {
    try {
      // Game sounds mix with the user's music and don't take audio focus. On iPhone, "ambient"
      // follows the silent switch; Android has no silent switch for app sounds, so the media
      // volume (and the Sound option) controls them.
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {AVAudioSessionOptions.mixWithOthers}),
      );
      await AudioPlayer.global.setAudioContext(ctx);
      for (final s in Sfx.values) {
        for (final f in s.files.toSet()) {
          if (_pools.containsKey(f)) continue;
          _pools[f] = await AudioPool.create(
            source: AssetSource('sfx/$f.ogg'),
            maxPlayers: 4,
            playerMode: PlayerMode.lowLatency,
            audioContext: ctx,
          );
        }
      }
    } catch (e) {
      debugPrint('sound off: $e');
    }
  }

  void play(Sfx s) {
    log.add(s);
    if (!AppPrefs.instance.sound || s.files.isEmpty) return;
    final pool = _pools[s.files[_rng.nextInt(s.files.length)]];
    pool?.start().catchError((_) => () async {});
  }
}

void playSfx(Sfx s) => SoundBoard.instance.play(s);
