import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/meld.dart';
import 'package:michikub/engine/puzzle.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);
final j0 = makeJoker(0);

void main() {
  group('solvers', () {
    test('full solver splits a pile into sets, and counts the ways', () {
      expect(solvable([r(3), r(4), r(5)]), true);
      expect(solvable([r(3), r(4)]), false);
      expect(solvable([r(3), r(4), j0]), true);
      // r3 r4 r5 b5 y5: only r3-r4 + ... no: r5 b5 y5 leaves r3 r4.
      expect(solvable([r(3), r(4), r(5), b(5), y(5)]), false);
      expect(solveAll([r(5), b(5), y(5), k(5)]).length, 1);
    });

    test('simple moves: run ends, a group of 3 to 4, new sets from the rack', () {
      expect(simpleSolvable([[r(3), r(4), r(5)]], [r(6)]), true);
      expect(simpleSolvable([[r(3), r(4), r(5)]], [r(2), r(1)]), true);
      expect(simpleSolvable([[r(7), b(7), y(7)]], [k(7)]), true);
      expect(simpleSolvable([[r(7), b(7), y(7)]], [b(1), b(2), b(3)]), true);
      // Needs a tile out of the group of 4.
      expect(simpleSolvable([[r(7), b(7), y(7), k(7)]], [r(8), r(9)]), false);
    });

    test('the five techniques are recognised', () {
      // Take a tile from a group.
      var c = checkPuzzle([[r(7), b(7), y(7), k(7)]], [r(8), r(9)])!;
      expect(c.needs, {Technique.splitGroup});
      // A run tile into a group.
      c = checkPuzzle([[r(4), r(5), r(6), r(7)]], [b(7), y(7)])!;
      expect(c.needs, {Technique.runToGroup});
      // Split a run (its middle tile joins a group).
      c = checkPuzzle([[r(3), r(4), r(5), r(6), r(7), r(8), r(9)]], [b(6), y(6)])!;
      expect(c.needs, containsAll([Technique.splitRun, Technique.runToGroup]));
      // Move a joker along its run: 4-J-6 + 5 makes 4-5-6-J (or J-4-5-6).
      c = checkPuzzle([[r(4), j0, r(6)]], [r(5)])!;
      expect(c.needs, {Technique.jokerShift});
      // Free a joker for a new set.
      c = checkPuzzle([[r(4), r(5), j0]], [r(6), b(9), y(9)])!;
      expect(c.needs, {Technique.jokerToNewSet});
    });

    test('too easy or unsolvable puzzles are refused', () {
      expect(checkPuzzle([[r(3), r(4), r(5)]], [r(6)]), isNull, reason: 'simple');
      expect(checkPuzzle([[r(3), r(4), r(5)]], [b(9)]), isNull, reason: 'unsolvable');
    });

    test('rearrangement cost is the minimum over every solution', () {
      // Single detach: one tile leaves a group of 4 to finish a run. Cheap, must not ship.
      final c = checkPuzzle([[r(7), b(7), y(7), k(7)]], [r(8), r(9)])!;
      expect(c.minSetsChanged, 1);
      expect(c.minTilesMoved, 1);
      expect(c.anySingleDetach, true);
      expect(qualifiesFor(PuzzleLevel.easy, [[r(7), b(7), y(7), k(7)]], [r(8), r(9)], c), false);
      expect(levelOf([[r(7), b(7), y(7), k(7)]], [r(8), r(9)], c), isNull);
    });

    test('a multi-set regrouping needs several board sets changed', () {
      // Starting as three colour runs plus k5-k6-k7 in the rack is *not* a counterexample:
      // the rack is already a set, so the board can stay put. This board has no complete
      // rack set; the cheapest solution still breaks three starting sets.
      final board = [
        [r(6), b(6), y(6)],
        [r(7), r(8), r(9)],
        [r(11), k(11), j0],
        [b(2), b(3), b(4)],
        [b(5), y(5), k(5)],
        [b(7), b(8), b(9)],
        [y(7), y(8), y(9), y(10)],
      ];
      final rack = [y(12), k(9), y(11)];
      final c = checkPuzzle(board, rack);
      expect(c, isNotNull);
      expect(c!.minSetsChanged, greaterThanOrEqualTo(3));
      expect(c.minTilesMoved, greaterThanOrEqualTo(2));
      expect(c.anySingleDetach, false);
      expect(c.rackSets, 0);
      expect(qualifiesFor(PuzzleLevel.medium, board, rack, c) || qualifiesFor(PuzzleLevel.hard, board, rack, c), true);
    });
  });

  group('generator', () {
    test('a fixed seed gives the same puzzles', () {
      String run(int seed) {
        final g = PuzzleGenerator(seed);
        return [for (var i = 0; i < 20; i++) g.attempt(PuzzleLevel.medium)?.toString()].join('\n');
      }

      expect(run(7), run(7));
    });

    test('every accepted puzzle passes the check and its stored solution is right', () {
      final g = PuzzleGenerator(11);
      var made = 0;
      for (var i = 0; i < 250; i++) {
        final p = g.attempt(PuzzleLevel.values[i % 3]);
        if (p == null) continue;
        made++;
        _expectGood(p);
      }
      expect(made, greaterThan(15), reason: 'generator should produce some puzzles in 250 tries');
    });

    test('endless mode makes a puzzle of the asked difficulty on the phone, quickly', () {
      for (final l in PuzzleLevel.values) {
        final sw = Stopwatch()..start();
        final p = generateOne(l, rng: math.Random(l.index + 1), maxTries: 2000)!;
        expect(p.band, l);
        _expectGood(p);
        expect(sw.elapsedMilliseconds, lessThan(8000), reason: l.name);
      }
    });

    test('colour-swapped copies have the same key', () {
      final a = Puzzle(board: [[r(7), b(7), y(7), k(7)]], rack: [r(8), r(9)], solution: const []);
      final c = Puzzle(board: [[b(7), r(7), y(7), k(7)]], rack: [b(8), b(9)], solution: const []);
      final d = Puzzle(board: [[b(7), r(7), y(7), k(7)]], rack: [b(8), b(10)], solution: const []);
      expect(canonicalKey(a), canonicalKey(c));
      expect(canonicalKey(a) == canonicalKey(d), false);
    });
  });

  test('the shipped pack: 400 per difficulty, every one checked, no duplicates', () {
    final j = jsonDecode(File('assets/puzzles/puzzles.json').readAsStringSync()) as Map<String, dynamic>;
    expect(j['version'], kPuzzlePackVersion);
    final keys = <String>{};
    for (final l in PuzzleLevel.values) {
      final list = [for (final p in j[l.name] as List) Puzzle.fromJson((p as Map).cast<String, dynamic>())];
      expect(list.length, 400, reason: l.name);
      for (final p in list) {
        final c = checkPuzzle(p.board, p.rack);
        expect(c, isNotNull, reason: '$p');
        expect(qualifiesFor(l, p.board, p.rack, c!), true, reason: '$p sc=${c.minSetsChanged} tm=${c.minTilesMoved}');
        expect(c.minSetsChanged, greaterThanOrEqualTo(l == PuzzleLevel.easy ? 2 : (l == PuzzleLevel.medium ? 3 : 4)));
        expect(p.techniques, isNotEmpty);
        expect(simpleSolvable(p.board, p.rack), false, reason: '$p');
        _expectSolutionRight(p);
        expect(keys.add(canonicalKey(p)), true, reason: 'duplicate $p');
      }
    }
  });
}

void _expectSolutionRight(Puzzle p) {
  final all = p.allTiles;
  expect(all.toSet().length, all.length);
  for (final s in p.board) {
    expect(isValidMeld(s), true, reason: '$p');
  }
  final sol = [for (final s in p.solution) ...s];
  expect(sol.toSet(), all.toSet(), reason: '$p');
  expect(sol.length, all.length);
  for (final s in p.solution) {
    expect(isValidMeld(s), true, reason: '$p');
  }
}

void _expectGood(Puzzle p) {
  _expectSolutionRight(p);
  expect(checkPuzzle(p.board, p.rack), isNotNull, reason: '$p');
}
