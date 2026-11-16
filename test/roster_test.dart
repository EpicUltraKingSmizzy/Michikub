import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/bot_roster.dart';

void main() {
  test('roster has the 12 final robots with unique ids, names, taglines and avatars', () {
    expect(robotRoster.map((r) => r.name).toList(),
        ['Bolt', 'Cogsworth', 'Pixel', 'Rusty', 'Nova', 'Clank', 'Echo', 'Gizmo', 'Sparky', 'Tank', 'Lumi', 'Duke']);
    for (final f in <Object Function(RobotProfile)>[(r) => r.id, (r) => r.name, (r) => r.tagline, (r) => r.avatar]) {
      expect(robotRoster.map(f).toSet().length, 12);
    }
    for (final r in robotRoster) {
      expect(r.tagline, isNotEmpty);
      expect(File(r.avatar).existsSync(), isTrue, reason: '${r.avatar} is missing');
      expect(robotByAvatar(r.avatar), same(r));
    }
    expect(robotByAvatar(null), isNull);
  });
  test('picks N distinct robots at random', () {
    final seen = <String>{};
    for (var s = 0; s < 100; s++) {
      for (final n in [1, 2, 3]) {
        final p = pickRobots(n, rng: math.Random(s * 7 + n));
        expect(p.length, n);
        expect(p.map((r) => r.id).toSet().length, n);
        seen.addAll(p.map((r) => r.id));
      }
    }
    expect(seen.length, 12, reason: 'every robot gets picked sometimes');
    final rest = robotRoster.skip(10).map((r) => r.id).toSet();
    final excluded = robotRoster.take(10).map((r) => r.id).toSet();
    expect(pickRobots(3, exclude: excluded).map((r) => r.id).toSet(), rest);
  });
}
