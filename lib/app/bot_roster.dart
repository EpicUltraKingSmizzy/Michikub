import 'dart:math' as math;

/// One of the robot computer players.
class RobotProfile {
  final String id;
  final String name;

  /// One-line personality, shown in Practice setup and on a long-press of the avatar.
  final String tagline;

  /// Avatar art (asset path): a square picture, drawn clipped to a circle inside the shared gold avatar frame.
  final String avatar;
  const RobotProfile(this.id, this.name, this.tagline, this.avatar);
}

/// The robot roster. Difficulty is picked separately, so any robot can play at any level.
const List<RobotProfile> robotRoster = [
  RobotProfile('bolt', 'Bolt', 'Plays fast, thinks later.', 'assets/bots/robot_bolt.png'),
  RobotProfile('cogsworth', 'Cogsworth', 'Sorts every rack, judges yours.', 'assets/bots/robot_cogsworth.png'),
  RobotProfile('rusty', 'Rusty', 'Been playing since tiles were wood.', 'assets/bots/robot_rusty.png'),
  RobotProfile('nova', 'Nova', 'Dreams of the perfect 13-run.', 'assets/bots/robot_nova.png'),
  RobotProfile('echo', 'Echo', 'Watches what you play, then copies it.', 'assets/bots/robot_echo.png'),
  RobotProfile('gizmo', 'Gizmo', 'Always rearranging something.', 'assets/bots/robot_gizmo.png'),
];

/// Picks [n] different robots at random, skipping any ids in [exclude].
List<RobotProfile> pickRobots(int n, {Set<String> exclude = const {}, math.Random? rng}) {
  final pool = robotRoster.where((r) => !exclude.contains(r.id)).toList()..shuffle(rng ?? math.Random());
  return pool.take(n).toList();
}

/// The robot whose avatar is [avatar], if any (players only carry the avatar path).
RobotProfile? robotByAvatar(String? avatar) {
  for (final r in robotRoster) {
    if (r.avatar == avatar) return r;
  }
  return null;
}
