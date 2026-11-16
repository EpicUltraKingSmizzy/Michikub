import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';

const rules = HouseRules(firstMeld: 30, turnSeconds: 0);

GameHost game(List<PlayerInfo> players, {int? seed}) => GameHost(players: players, rules: rules, seed: seed);

PlayerInfo human(String id) => PlayerInfo(id, id.toUpperCase(), SeatKind.human);
PlayerInfo bot(String id) => PlayerInfo(id, id.toUpperCase(), SeatKind.bot);

/// Who starts rounds 1..n.
List<String> starters(GameHost h, int n) {
  final out = <String>[];
  for (var i = 0; i < n; i++) {
    h.startRound();
    expect(h.currentPlayer.id, h.roundStarter.id);
    out.add(h.currentPlayer.id);
  }
  return out;
}

void main() {
  group('who starts', () {
    test('Practice: the human starts round 1, wherever they sit, then it rotates', () {
      for (var seed = 0; seed < 20; seed++) {
        final h = game([human('me'), bot('b1'), bot('b2'), bot('b3')], seed: seed);
        expect(starters(h, 6), ['me', 'b1', 'b2', 'b3', 'me', 'b1']);
      }
      final h = game([bot('b1'), bot('b2'), human('me')], seed: 3);
      expect(starters(h, 4), ['me', 'b1', 'b2', 'me']);
    });

    test('between humans the host engine picks a random human for round 1 (not always the host)', () {
      final firsts = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        final h = game([human('host'), human('p2'), human('p3')], seed: seed)..startRound();
        firsts.add(h.currentPlayer.id);
      }
      expect(firsts, {'host', 'p2', 'p3'}, reason: 'every human gets to start sometimes');

      // Humans plus bots (an online table with a bot seat): only humans are picked to start round 1.
      final mixed = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        final h = game([human('host'), bot('b1'), human('p2')], seed: seed)..startRound();
        mixed.add(h.currentPlayer.id);
      }
      expect(mixed, {'host', 'p2'});
    });

    test('the starting player rotates to the next seat each round', () {
      for (var seed = 0; seed < 20; seed++) {
        final h = game([human('a'), human('b'), human('c')], seed: seed);
        final s = starters(h, 7);
        final ids = ['a', 'b', 'c'];
        final first = ids.indexOf(s.first);
        expect(s, [for (var r = 0; r < 7; r++) ids[(first + r) % 3]]);
      }
    });

    test('the view says who started the round (for the banner), and it survives JSON', () {
      final h = game([human('a'), human('b')], seed: 5)..startRound();
      final v = h.viewFor('a');
      expect(v.starter, h.roundStarter.id);
      expect(PlayerView.fromJson(v.toJson()).starter, v.starter);
      // Still the round's starter after the turn moves on.
      h.handle(h.currentPlayer.id, const DrawAction());
      expect(h.viewFor('b').starter, v.starter);
    });
  });
}
