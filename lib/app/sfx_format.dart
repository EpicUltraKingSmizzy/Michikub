/// Which sound files a browser gets. Every iPhone and iPad browser (Chrome included) is Safari's
/// WebKit underneath, which doesn't play Ogg Vorbis, so those get the AAC copies (.m4a). So does
/// any browser that says it can't play Ogg Vorbis. Everything else keeps the .ogg files the
/// apps use.
///
/// [oggSupport] is the browser's `canPlayType('audio/ogg; codecs="vorbis"')` answer ('' for no),
/// [userAgent] and [maxTouchPoints] come from `navigator` (iPads report a Mac user agent, so
/// they're told apart by their touch screen).
String webSoundFormat({required String oggSupport, required String userAgent, int maxTouchPoints = 0}) {
  final ios = RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent) || (userAgent.contains('Macintosh') && maxTouchPoints > 1);
  if (ios || oggSupport.isEmpty) return 'm4a';
  return 'ogg';
}

/// The other format, tried when a file won't decode in the first one.
String otherSoundFormat(String ext) => ext == 'ogg' ? 'm4a' : 'ogg';
