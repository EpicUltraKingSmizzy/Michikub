/// Text and link for inviting friends to a hosted room.
library;

/// The app's join link for a room code, e.g. `michikub://join/ABCD`.
String joinLink(String code) => 'michikub://join/${code.trim().toUpperCase()}';

/// The message shared with friends:
///
///     Come play Michikub with me!
///     Room code: ABCD
///     michikub://join/ABCD
String inviteShareText(String code) {
  final c = code.trim().toUpperCase();
  return 'Come play Michikub with me!\nRoom code: $c\n${joinLink(c)}';
}

/// The room code from a link that opened the app (`michikub://join/ABCD`), or null when the
/// link isn't a join link.
String? codeFromAppLink(Uri uri) {
  if (uri.scheme.toLowerCase() != 'michikub' || uri.host.toLowerCase() != 'join') return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
  if (seg == null || !RegExp(r'^[A-Za-z0-9]{4,8}$').hasMatch(seg)) return null;
  return seg.toUpperCase();
}

/// The room code in a join link (or a bare code), or null if there isn't one.
String? codeFromJoinLink(String text) {
  final m = RegExp(r'michikub://join/([A-Za-z0-9]+)').firstMatch(text);
  if (m != null) return m.group(1)!.toUpperCase();
  final bare = text.trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(bare) ? bare : null;
}
