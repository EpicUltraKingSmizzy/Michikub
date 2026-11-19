/// The apps play sounds through audioplayers (see sfx.dart); this Web Audio player is web only.
class WebAudio {
  static bool get available => false;
  static Future<void> init(Iterable<String> files) async {}
  static void play(String file) {}
}
