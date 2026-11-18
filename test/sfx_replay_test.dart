import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/sfx.dart';

/// Acts like Android's low-latency (SoundPool) player: it never reports that a sound ended, so
/// a play only starts again after a stop.
class FakeSoundPool extends AudioplayersPlatformInterface {
  final playing = <String, bool>{};
  int starts = 0;

  @override
  Future<void> create(String playerId) async => playing[playerId] = false;
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();
  @override
  Future<void> stop(String playerId) async => playing[playerId] = false;
  @override
  Future<void> resume(String playerId) async {
    if (playing[playerId] == true) return;
    playing[playerId] = true;
    starts++;
  }

  @override
  Future<void> pause(String playerId) async => playing[playerId] = false;
  @override
  Future<void> release(String playerId) async => playing[playerId] = false;
  @override
  Future<void> dispose(String playerId) async {}
  @override
  Future<int?> getCurrentPosition(String playerId) async => null;
  @override
  Future<int?> getDuration(String playerId) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class FakeGlobal extends GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sound keeps playing every time, not just once per voice (menu clicks went silent)', () async {
    GlobalAudioplayersPlatformInterface.instance = FakeGlobal();
    final fake = FakeSoundPool();
    AudioplayersPlatformInterface.instance = fake;
    AppPrefs.instance.sound = true;
    final voices = [for (var i = 0; i < 3; i++) AudioPlayer()];
    SoundBoard.instance.debugSetVoices('click', voices);
    for (var i = 0; i < 10; i++) {
      playSfx(Sfx.click);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.starts, 10);
    SoundBoard.instance.debugSetVoices('click', []);
  });

  test('several attaches in a row each play (and quick repeats overlap on the voices)', () async {
    GlobalAudioplayersPlatformInterface.instance = FakeGlobal();
    final fake = FakeSoundPool();
    AudioplayersPlatformInterface.instance = fake;
    AppPrefs.instance.sound = true;
    SoundBoard.instance.debugSetVoices('attach', [for (var i = 0; i < 3; i++) AudioPlayer()]);
    // Rapid: no waiting between them.
    for (var i = 0; i < 8; i++) {
      playSfx(i.isEven ? Sfx.attach : Sfx.place);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.starts, 8);
    SoundBoard.instance.debugSetVoices('attach', []);
  });
}
