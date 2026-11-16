import 'dart:math' as math;

/// One of the robot computer players.
class RobotProfile {
  final String id;
  final String name;

  /// Avatar image (asset path).
  final String avatar;
  const RobotProfile(this.id, this.name, this.avatar);
}

/// The robot roster. Placeholder names and art for now: swap in the final
/// names and images here (keep the list at 6 or more).
const List<RobotProfile> robotRoster = [
  RobotProfile('bot_1', 'Bolt', 'assets/bots/bot_1.png'),
  RobotProfile('bot_2', 'Pixel', 'assets/bots/bot_2.png'),
  RobotProfile('bot_3', 'Rivet', 'assets/bots/bot_3.png'),
  RobotProfile('bot_4', 'Sprocket', 'assets/bots/bot_4.png'),
  RobotProfile('bot_5', 'Tinker', 'assets/bots/bot_5.png'),
  RobotProfile('bot_6', 'Cog', 'assets/bots/bot_6.png'),
];

/// Picks [n] different robots at random, skipping any ids in [exclude].
List<RobotProfile> pickRobots(int n, {Set<String> exclude = const {}, math.Random? rng}) {
  final pool = robotRoster.where((r) => !exclude.contains(r.id)).toList()..shuffle(rng ?? math.Random());
  return pool.take(n).toList();
}
