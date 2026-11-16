import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/bot_roster.dart';

void main() {
  test('roster has 6 robots with unique ids, names and avatars', () {
    expect(robotRoster.length, 6);
    expect(robotRoster.map((r) => r.id).toSet().length, 6);
    expect(robotRoster.map((r) => r.name).toSet().length, 6);
    expect(robotRoster.map((r) => r.avatar).toSet().length, 6);
  });
  test('picks N distinct robots at random', () {
    final seen = <String>{};
    for (var s = 0; s < 50; s++) {
      final p = pickRobots(3, rng: math.Random(s));
      expect(p.length, 3);
      expect(p.map((r) => r.id).toSet().length, 3);
      seen.addAll(p.map((r) => r.id));
    }
    expect(seen.length, 6, reason: 'every robot gets picked sometimes');
    expect(pickRobots(2, exclude: {'bot_1', 'bot_2', 'bot_3', 'bot_4'}).map((r) => r.id).toSet(), {'bot_5', 'bot_6'});
  });
}
