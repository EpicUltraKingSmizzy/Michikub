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
///
/// Each file gets a few players, loaded once at start-up (Android: SoundPool, "low latency"),
/// used in turn so quick repeats overlap. (audioplayers' AudioPool doesn't reuse low-latency
/// players: it made and loaded a new player for nearly every play, which was slow.)
class SoundBoard {
  static final instance = SoundBoard._();
  SoundBoard._();

  static const _voices = 3;
  final _players = <String, List<AudioPlayer>>{};
  final _next = <String, int>{};
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
          if (_players.containsKey(f)) continue;
          final list = <AudioPlayer>[];
          for (var i = 0; i < _voices; i++) {
            final p = AudioPlayer();
            try {
              await p.setPlayerMode(PlayerMode.lowLatency);
            } catch (_) {} // Not on every platform: the normal player still works.
            await p.setAudioContext(ctx);
            await p.setReleaseMode(ReleaseMode.stop);
            await p.setSource(AssetSource('sfx/$f.ogg'));
            list.add(p);
          }
          _players[f] = list;
        }
      }
    } catch (e) {
      debugPrint('sound off: $e');
    }
  }

  void play(Sfx s) {
    log.add(s);
    if (!AppPrefs.instance.sound || s.files.isEmpty) return;
    final f = s.files[_rng.nextInt(s.files.length)];
    final list = _players[f];
    if (list == null || list.isEmpty) return;
    final i = _next[f] ?? 0;
    _next[f] = (i + 1) % list.length;
    final p = list[i];
    // One restart at a time per voice, so quick repeats aren't lost.
    _queue[p] = (_queue[p] ?? Future<void>.value()).then((_) => _restart(p));
  }

  final _queue = <AudioPlayer, Future<void>>{};

  /// Plays a voice again from the top. The stop must finish before the resume: AudioPlayer
  /// skips a stop when a resume was asked for in the meantime, and the native player, which
  /// never reports the end of a low-latency sound, then thinks it's still playing and ignores
  /// the resume. (That's how each voice used to play only once, so sounds died after a few
  /// clicks.)
  static Future<void> _restart(AudioPlayer p) async {
    try {
      await p.stop();
      await p.resume();
    } catch (_) {}
  }

  /// Tests: use [voices] for [file] instead of loading it.
  @visibleForTesting
  void debugSetVoices(String file, List<AudioPlayer> voices) {
    _players[file] = voices;
    _next.remove(file);
  }
}

void playSfx(Sfx s) => SoundBoard.instance.play(s);
