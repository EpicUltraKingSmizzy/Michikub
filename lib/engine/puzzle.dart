/// Puzzles: a rack and a table that can take every rack tile, but only if the player
/// rearranges the table. The checker, the two solvers, the generator and the difficulty score.
///
/// A puzzle uses each colour/number at most once (copy 0 ids), plus up to 2 jokers, so every
/// tile is unique and the solvers never chase duplicate copies. Everything here is pure Dart
/// that runs on the web too (no bit operations on more than 13 bits).
library;

import 'dart:math' as math;

import 'meld.dart';
import 'tiles.dart';

/// The rearranging techniques a puzzle must need (at least one in every solution).
enum Technique {
  /// A joker leaves a set on the table for a new set (its real tile takes its place).
  jokerToNewSet,

  /// A joker inside a run moves to another value in the same run.
  jokerShift,

  /// A run on the table is split into two smaller runs.
  splitRun,

  /// A tile is separated out of a group to build a new set.
  splitGroup,

  /// A tile comes out of a run to make a group.
  runToGroup,
}

const kTechniqueNames = {
  Technique.jokerToNewSet: 'Free a joker',
  Technique.jokerShift: 'Move a joker along its run',
  Technique.splitRun: 'Split a run',
  Technique.splitGroup: 'Take a tile from a group',
  Technique.runToGroup: 'Turn a run tile into a group',
};

/// Placeholder joker id in solver output (the solvers treat jokers as interchangeable).
const int kAnyJoker = -2;

enum PuzzleLevel { easy, medium, hard }

class Puzzle {
  /// The table at the start: each set's tiles in order (jokers sit where they stand).
  final List<List<int>> board;
  final List<int> rack;

  /// One way to finish (from the generator).
  final List<List<int>> solution;
  final Set<Technique> techniques;
  final double score;
  const Puzzle({
    required this.board,
    required this.rack,
    required this.solution,
    this.techniques = const {},
    this.score = 0,
  });

  List<int> get allTiles => [for (final s in board) ...s, ...rack];

  Map<String, dynamic> toJson() => {
        'b': [for (final s in board) s.map(encodeTile).join(' ')],
        'r': rack.map(encodeTile).join(' '),
        's': [for (final s in solution) s.map(encodeTile).join(' ')],
        't': [for (final t in techniques) t.index],
        'd': double.parse(score.toStringAsFixed(2)),
      };

  factory Puzzle.fromJson(Map<String, dynamic> j) {
    List<int> dec(String s) => s.isEmpty ? <int>[] : s.split(' ').map(decodeTile).toList();
    return Puzzle(
      board: [for (final s in j['b'] as List) dec(s as String)],
      rack: dec(j['r'] as String),
      solution: [for (final s in j['s'] as List) dec(s as String)],
      techniques: {for (final t in (j['t'] as List? ?? const [])) Technique.values[t as int]},
      score: (j['d'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  String toString() =>
      'board: ${board.map((s) => s.map(tileLabel).join(' ')).join(' | ')}\nrack: ${rack.map(tileLabel).join(' ')}';
}

/// Compact tile text for the puzzle file: r5, k13, J0, J1.
String encodeTile(int id) => isJoker(id) ? 'J${id - kJokerBase}' : tileLabel(id);

int decodeTile(String s) {
  if (s.startsWith('J')) return makeJoker(int.parse(s.substring(1)));
  const letters = ['r', 'b', 'y', 'k'];
  return makeTile(TileColor.values[letters.indexOf(s[0])], int.parse(s.substring(1)));
}

// --- the tile pile as the solvers see it ------------------------------------------------

/// The tiles left to place: a 13-bit mask per colour (bit n-1 = number n) and a joker count.
class _Pile {
  final List<int> m;
  int jokers;
  _Pile(this.m, this.jokers);
  factory _Pile.of(Iterable<int> tiles) {
    final p = _Pile([0, 0, 0, 0], 0);
    for (final t in tiles) {
      if (isJoker(t) || t == kAnyJoker) {
        p.jokers++;
      } else {
        p.m[tileColor(t).index] |= 1 << (tileNumber(t) - 1);
      }
    }
    return p;
  }
  bool has(int c, int n) => n >= 1 && n <= 13 && (m[c] >> (n - 1)) & 1 == 1;
  bool get empty => m[0] == 0 && m[1] == 0 && m[2] == 0 && m[3] == 0;
  String get key => '${m[0]},${m[1]},${m[2]},${m[3]},$jokers';
  void take(List<int> cells) {
    for (final t in cells) {
      if (t == kAnyJoker) {
        jokers--;
      } else {
        m[tileColor(t).index] &= ~(1 << (tileNumber(t) - 1));
      }
    }
  }

  void give(List<int> cells) {
    for (final t in cells) {
      if (t == kAnyJoker) {
        jokers++;
      } else {
        m[tileColor(t).index] |= 1 << (tileNumber(t) - 1);
      }
    }
  }

  /// The lowest tile left (by colour, then number), or null.
  (int, int)? lowest() {
    for (var c = 0; c < 4; c++) {
      if (m[c] == 0) continue;
      for (var n = 1; n <= 13; n++) {
        if (has(c, n)) return (c, n);
      }
    }
    return null;
  }
}

int _t(int c, int n) => makeTile(TileColor.values[c], n);

/// Every valid set that holds the tile (c, n) and otherwise only tiles in [p] (not counting
/// (c, n) itself, which the caller has taken out). (c, n) is the lowest tile left, so a run
/// only has jokers below it and a group only has later colours. Cells are ordered as they
/// would lie on the table; jokers are [kAnyJoker].
List<List<int>> _setsWith(_Pile p, int c, int n, {bool jokerForReal = true}) {
  final out = <List<int>>[];
  final me = _t(c, n);
  // Runs.
  for (var lead = 0; lead <= p.jokers && n - lead >= 1; lead++) {
    final cells = <int>[for (var i = 0; i < lead; i++) kAnyJoker, me];
    void ext(int v, int jokers) {
      if (cells.length >= 3) out.add(List.of(cells));
      if (v > 13 || cells.length >= 13) return;
      if (p.has(c, v)) {
        cells.add(_t(c, v));
        ext(v + 1, jokers);
        cells.removeLast();
      }
      if (jokers > 0 && (jokerForReal || !p.has(c, v))) {
        cells.add(kAnyJoker);
        ext(v + 1, jokers - 1);
        cells.removeLast();
      }
    }

    ext(n + 1, p.jokers - lead);
  }
  // Groups.
  final others = [for (var d = c + 1; d < 4; d++) if (p.has(d, n)) _t(d, n)];
  for (var mask = 0; mask < (1 << others.length); mask++) {
    final pick = [for (var i = 0; i < others.length; i++) if ((mask >> i) & 1 == 1) others[i]];
    for (var j = 0; j <= p.jokers && j <= 3; j++) {
      final size = 1 + pick.length + j;
      if (size < 3 || size > 4) continue;
      out.add([me, ...pick, for (var i = 0; i < j; i++) kAnyJoker]);
    }
  }
  return out;
}

/// The full solver: ways to split every tile in [tiles] into valid sets (jokers come back as
/// [kAnyJoker]). Stops after [limit] solutions. [shuffle] tries sets in a random order (the
/// generator uses it to build a different arrangement of the same tiles).
List<List<List<int>>> solveAll(Iterable<int> tiles, {int limit = 1 << 30, math.Random? shuffle}) {
  final pile = _Pile.of(tiles);
  final out = <List<List<int>>>[];
  final dead = <String>{};
  final cur = <List<int>>[];
  bool rec() {
    if (out.length >= limit) return true;
    final low = pile.lowest();
    if (low == null) {
      if (pile.jokers != 0) return false;
      out.add([for (final s in cur) List.of(s)]);
      return true;
    }
    final key = pile.key;
    if (dead.contains(key)) return false;
    final (c, n) = low;
    pile.take([_t(c, n)]);
    final cands = _setsWith(pile, c, n);
    pile.give([_t(c, n)]);
    if (shuffle != null) cands.shuffle(shuffle);
    var any = false;
    for (final s in cands) {
      pile.take(s);
      cur.add(s);
      if (rec()) any = true;
      cur.removeLast();
      pile.give(s);
      if (out.length >= limit) return true;
    }
    if (!any) dead.add(key);
    return any;
  }

  rec();
  return out;
}

bool solvable(Iterable<int> tiles) => solveAll(tiles, limit: 1).isNotEmpty;

/// The simple-moves solver: can every rack tile be placed without changing any set on the
/// table? Rack tiles may only go on the ends of runs, make a group of 3 into 4, or form new
/// sets made only of rack tiles.
bool simpleSolvable(List<List<int>> board, List<int> rack) {
  final infos = [for (final s in board) analyzeMeld(s)];
  if (infos.any((i) => i == null)) return false;
  final pile = _Pile.of(rack);
  final dead = <String>{};
  bool rec(int i) {
    if (i == board.length) return solvable(_tilesOf(pile));
    final key = '$i:${pile.key}';
    if (dead.contains(key)) return false;
    final info = infos[i]!;
    final set = board[i];
    final options = <List<int>>[[]];
    if (info.kind == MeldKind.run) {
      final c = tileColor(set.firstWhere((t) => !isJoker(t))).index;
      final lo = info.values.first, hi = info.values.last;
      // Left additions (values lo-1 down), right additions (hi+1 up), any mix.
      List<List<int>> side(int from, int step) {
        final res = <List<int>>[[]];
        final cells = <int>[];
        var j = pile.jokers;
        final m = List.of(pile.m);
        for (var v = from; v >= 1 && v <= 13; v += step) {
          if ((m[c] >> (v - 1)) & 1 == 1) {
            cells.add(_t(c, v));
            m[c] &= ~(1 << (v - 1));
          } else if (j > 0) {
            cells.add(kAnyJoker);
            j--;
          } else {
            break;
          }
          res.add(List.of(cells));
        }
        return res;
      }

      final left = side(lo - 1, -1), right = side(hi + 1, 1);
      options.clear();
      for (final l in left) {
        for (final r in right) {
          final both = [...l, ...r];
          final jokers = both.where((t) => t == kAnyJoker).length;
          if (jokers > pile.jokers) continue;
          if (set.length + both.length > 13) continue;
          options.add(both);
        }
      }
    } else if (set.length == 3) {
      final n = info.values.first;
      final have = {for (final t in set) if (!isJoker(t)) tileColor(t).index};
      for (var c = 0; c < 4; c++) {
        if (!have.contains(c) && pile.has(c, n)) options.add([_t(c, n)]);
      }
      if (pile.jokers > 0) options.add([kAnyJoker]);
    }
    for (final o in options) {
      pile.take(o);
      final ok = rec(i + 1);
      pile.give(o);
      if (ok) return true;
    }
    dead.add(key);
    return false;
  }

  return rec(0);
}

List<int> _tilesOf(_Pile p) => [
      for (var c = 0; c < 4; c++)
        for (var n = 1; n <= 13; n++)
          if (p.has(c, n)) _t(c, n),
      for (var j = 0; j < p.jokers; j++) kAnyJoker,
    ];

// --- techniques ------------------------------------------------------------------------

/// What one solution does to the table at the start.
class SolutionShape {
  final Set<Technique> techniques;

  /// Sets on the table at the start that don't survive whole (their tiles split up, or a
  /// joker leaves or moves).
  final int broken;
  const SolutionShape(this.techniques, this.broken);
}

/// The value each cell stands for (jokers included) and whether the set is a run.
({bool run, List<int> values})? _read(List<int> cells) {
  final ids = [for (final t in cells) t == kAnyJoker ? kJokerBase : t];
  final info = analyzeMeld(ids);
  if (info == null) return null;
  return (run: info.kind == MeldKind.run, values: info.values);
}

/// Compares the table at the start with [solution] and names the techniques it uses. With
/// two jokers either may be "the same" joker: the reading with fewer techniques counts (a
/// player wouldn't see a difference).
SolutionShape shapeOf(List<List<int>> start, List<List<int>> solution) {
  final startRead = [for (final s in start) _read(s)!];
  final solRead = [for (final s in solution) _read(s)!];
  final where = <int, int>{}; // real tile -> solution set
  for (var j = 0; j < solution.length; j++) {
    for (final t in solution[j]) {
      if (t != kAnyJoker && !isJoker(t)) where[t] = j;
    }
  }
  // Board jokers at the start: (set, value); solution jokers: (set, value).
  final startJ = <(int, int)>[];
  for (var i = 0; i < start.length; i++) {
    for (var k = 0; k < start[i].length; k++) {
      if (isJoker(start[i][k])) startJ.add((i, startRead[i].values[k]));
    }
  }
  final solJ = <(int, int)>[];
  for (var j = 0; j < solution.length; j++) {
    for (var k = 0; k < solution[j].length; k++) {
      final t = solution[j][k];
      if (t == kAnyJoker || isJoker(t)) solJ.add((j, solRead[j].values[k]));
    }
  }
  // Fixed part: tile moves.
  final fixed = <Technique>{};
  final brokenSets = <int>{};
  for (var i = 0; i < start.length; i++) {
    final real = [for (final t in start[i]) if (!isJoker(t)) t];
    final dest = <int, int>{};
    for (final t in real) {
      dest[where[t]!] = (dest[where[t]!] ?? 0) + 1;
    }
    if (dest.length > 1) brokenSets.add(i);
    if (startRead[i].run) {
      // Tiles out of a run into a group.
      for (final t in real) {
        if (!solRead[where[t]!].run && solution[where[t]!].length >= 3) {
          final grp = solution[where[t]!];
          if (grp.any((x) => x != kAnyJoker && !isJoker(x) && x != t && !real.contains(x)) ||
              grp.any((x) => x == kAnyJoker || isJoker(x))) {
            fixed.add(Technique.runToGroup);
          }
        }
      }
      // Split into two runs, each keeping 2 or more of its tiles.
      final runParts = dest.entries.where((e) => solRead[e.key].run && e.value >= 2).length;
      if (runParts >= 2) fixed.add(Technique.splitRun);
    } else {
      if (dest.length > 1) fixed.add(Technique.splitGroup);
    }
  }
  // Jokers: try every matching of start jokers to solution jokers (rack jokers fill the rest).
  Set<Technique>? best;
  var bestBroken = 0;
  void tryMatch(List<int> pick) {
    final t = <Technique>{...fixed};
    final br = {...brokenSets};
    for (var a = 0; a < startJ.length; a++) {
      final (si, sv) = startJ[a];
      final (dj, dv) = solJ[pick[a]];
      final realsOfStart = [for (final x in start[si]) if (!isJoker(x)) x];
      final sharesReal = realsOfStart.any((x) => where[x] == dj);
      if (!sharesReal) {
        t.add(Technique.jokerToNewSet);
        br.add(si);
      } else if (dv != sv) {
        if (startRead[si].run && solRead[dj].run) t.add(Technique.jokerShift);
        br.add(si);
      }
    }
    if (best == null || t.length < best!.length || (t.length == best!.length && br.length < bestBroken)) {
      best = t;
      bestBroken = br.length;
    }
  }

  void perm(List<int> pick, Set<int> used) {
    if (pick.length == startJ.length) {
      tryMatch(pick);
      return;
    }
    for (var k = 0; k < solJ.length; k++) {
      if (used.contains(k)) continue;
      pick.add(k);
      used.add(k);
      perm(pick, used);
      used.remove(k);
      pick.removeLast();
    }
  }

  if (startJ.length > solJ.length) return const SolutionShape({}, 0);
  perm([], {});
  return SolutionShape(best ?? fixed, best == null ? brokenSets.length : bestBroken);
}

/// The full check of a puzzle: solvable, not solvable with simple moves only, and every
/// solution (up to [limit]) uses at least one technique. Null when it fails.
class PuzzleCheck {
  final int solutions;

  /// Techniques every solution needs at least (the smallest set over all solutions).
  final Set<Technique> needs;
  final int minTechniques;
  final int minBroken;
  final List<List<int>> firstSolution;
  const PuzzleCheck(this.solutions, this.needs, this.minTechniques, this.minBroken, this.firstSolution);
}

PuzzleCheck? checkPuzzle(List<List<int>> board, List<int> rack, {int limit = 60}) {
  if (board.any((s) => !isValidMeld(s))) return null;
  final all = [for (final s in board) ...s, ...rack];
  if (all.toSet().length != all.length) return null;
  if (simpleSolvable(board, rack)) return null;
  final sols = solveAll(all, limit: limit + 1);
  if (sols.isEmpty || sols.length > limit) return null;
  Set<Technique>? fewest;
  var minBroken = 1 << 20;
  var simplest = sols.first;
  for (final s in sols) {
    final sh = shapeOf(board, s);
    if (sh.techniques.isEmpty) return null;
    if (fewest == null || sh.techniques.length < fewest.length) fewest = sh.techniques;
    if (sh.broken < minBroken) {
      minBroken = sh.broken;
      simplest = s;
    }
  }
  return PuzzleCheck(sols.length, fewest!, fewest.length, minBroken, simplest);
}

/// Difficulty score: more techniques, more broken sets, a bigger rack, jokers and fewer
/// solutions all make it harder.
double scorePuzzle(List<List<int>> board, List<int> rack, PuzzleCheck c) {
  final jokers = [for (final s in board) ...s, ...rack].any(isJoker);
  final tiles = board.fold<int>(0, (a, s) => a + s.length) + rack.length;
  return 2.5 * c.minTechniques +
      1.4 * c.minBroken +
      0.35 * rack.length +
      (jokers ? 1.5 : 0) +
      (c.solutions == 1 ? 2 : (c.solutions <= 3 ? 1 : 0)) +
      0.04 * tiles;
}

/// Score limits between Easy / Medium and Medium / Hard.
const kEasyMax = 7.0;
const kMediumMax = 10.0;

PuzzleLevel levelFor(double score) =>
    score < kEasyMax ? PuzzleLevel.easy : (score < kMediumMax ? PuzzleLevel.medium : PuzzleLevel.hard);

// --- the generator ---------------------------------------------------------------------

/// Counters for one generator run.
class GenStats {
  int attempts = 0;
  int accepted = 0;
  int simpleRejects = 0;
  int repairsTried = 0;
  int repairsWorked = 0;
  int otherRejects = 0;
  @override
  String toString() => 'attempts $attempts, accepted $accepted, simple-solvable $simpleRejects, '
      'repairs $repairsWorked/$repairsTried, other rejects $otherRejects';
}

/// Builds puzzles: a winning table (5 to 9 sets), a technique forced on purpose (one to three
/// "cores"), the rack pulled out, the rest of the table rebuilt into its "before" picture,
/// then checked by both solvers (small repairs first when it's too easy).
class PuzzleGenerator {
  final math.Random rng;
  final GenStats stats = GenStats();
  PuzzleGenerator(int seed) : rng = math.Random(seed);
  PuzzleGenerator.withRandom(this.rng);

  /// Accepted puzzles per technique, to keep the mix balanced: the core to force is usually
  /// one of the two techniques made least so far.
  final Map<Technique, int> _made = {};

  Technique _pickTechnique() {
    if (rng.nextDouble() < .35) return Technique.values[rng.nextInt(Technique.values.length)];
    final order = List.of(Technique.values)..sort((a, b) => (_made[a] ?? 0).compareTo(_made[b] ?? 0));
    return order[rng.nextInt(2)];
  }

  late Set<int> _used;
  late int _jokersLeft;
  late int _nextJoker;

  bool _free(int c, int n) => n >= 1 && n <= 13 && !_used.contains(_t(c, n));
  int _take(int c, int n) {
    final t = _t(c, n);
    _used.add(t);
    return t;
  }

  int _joker() {
    _jokersLeft--;
    return makeJoker(_nextJoker++);
  }

  List<int> _colors() => [0, 1, 2, 3]..shuffle(rng);

  /// One try at a puzzle aimed at [level]; null when it didn't pass.
  Puzzle? attempt(PuzzleLevel level) {
    stats.attempts++;
    _used = {};
    _jokersLeft = level == PuzzleLevel.easy ? (rng.nextDouble() < .3 ? 1 : 0) : (rng.nextDouble() < .6 ? 2 : 1);
    _nextJoker = 0;
    final board = <List<int>>[];
    final rack = <int>[];
    final solution = <List<int>>[];
    final cores = switch (level) {
      PuzzleLevel.easy => 1,
      PuzzleLevel.medium => 1 + rng.nextInt(2),
      PuzzleLevel.hard => 2 + rng.nextInt(2),
    };
    var made = 0;
    for (var tries = 0; made < cores && tries < cores * 6; tries++) {
      final tech = _pickTechnique();
      if (_core(tech, board, rack, solution)) made++;
    }
    if (made == 0) {
      stats.otherRejects++;
      return null;
    }
    // Filler: whole sets that stay put (some get a rack tile on an end as a decoy).
    final targetSets = 5 + rng.nextInt(level == PuzzleLevel.easy ? 2 : (level == PuzzleLevel.medium ? 3 : 5));
    _filler(board, rack, solution, targetSets, level);
    // Rebuild the table's "before" picture now and then (harder levels more often).
    var start = board;
    final scramble = switch (level) { PuzzleLevel.easy => .1, PuzzleLevel.medium => .35, PuzzleLevel.hard => .6 };
    if (rng.nextDouble() < scramble) {
      final re = _rebuild(board);
      if (re != null) start = re;
    }
    return _finish(start, rack, solution, level);
  }

  Puzzle? _finish(List<List<int>> start, List<int> rack, List<List<int>> solution, PuzzleLevel level) {
    if (rack.isEmpty || rack.length > 12) {
      stats.otherRejects++;
      return null;
    }
    var check = checkPuzzle(start, rack);
    var b = start, r = rack;
    if (check == null && simpleSolvable(start, rack)) {
      stats.simpleRejects++;
      stats.repairsTried++;
      final fixed = _repair(start, rack);
      if (fixed != null) {
        stats.repairsWorked++;
        (b, r, check) = fixed;
      }
    }
    if (check == null) {
      stats.otherRejects++;
      return null;
    }
    stats.accepted++;
    for (final t in check.needs) {
      _made[t] = (_made[t] ?? 0) + 1;
    }
    final p = Puzzle(
      board: [for (final s in b) List.of(s)],
      rack: List.of(r)..shuffle(rng),
      solution: _withJokerIds(check.firstSolution, [for (final s in b) ...s, ...r]),
      techniques: check.needs,
      score: scorePuzzle(b, r, check),
    );
    return p;
  }

  /// The solver's jokers get real joker ids back.
  List<List<int>> _withJokerIds(List<List<int>> sol, List<int> tiles) {
    final jokers = tiles.where(isJoker).toList()..sort();
    var k = 0;
    return [
      for (final s in sol) [for (final t in s) t == kAnyJoker ? jokers[k++] : t],
    ];
  }

  /// Small targeted repairs for a puzzle that turned out too easy: swap a joker into a table
  /// set (its tile goes to the rack), move a rack tile onto the table, drop a rack tile that
  /// simply goes on an end, or grow a group to 4. Each is checked with both solvers.
  (List<List<int>>, List<int>, PuzzleCheck)? _repair(List<List<int>> board, List<int> rack) {
    final tries = <(List<List<int>>, List<int>)>[];
    final usedJokers = [for (final s in board) ...s, ...rack].where(isJoker).toSet();
    final freeJoker = [for (var j = 0; j < 2; j++) makeJoker(j)].where((j) => !usedJokers.contains(j)).firstOrNull;
    // Swap a joker in.
    if (freeJoker != null) {
      for (var i = 0; i < board.length; i++) {
        for (var k = 0; k < board[i].length; k++) {
          final t = board[i][k];
          if (isJoker(t)) continue;
          final nb = [for (final s in board) List.of(s)];
          nb[i][k] = freeJoker;
          tries.add((nb, [...rack, t]));
        }
      }
    }
    // Drop a rack tile (the rest must still fit), or move it onto a set end.
    for (final t in rack) {
      final rest = [...rack]..remove(t);
      if (rest.isNotEmpty) tries.add((board, rest));
      for (var i = 0; i < board.length; i++) {
        for (final cand in [
          [t, ...board[i]],
          [...board[i], t]
        ]) {
          if (isValidMeld(cand) && rest.isNotEmpty) {
            final nb = [for (final s in board) List.of(s)];
            nb[i] = cand;
            tries.add((nb, rest));
          }
        }
      }
    }
    // Grow a group of 3 to 4 with an unused tile.
    final all = {for (final s in board) ...s, ...rack};
    for (var i = 0; i < board.length; i++) {
      final info = analyzeMeld(board[i]);
      if (info == null || info.kind != MeldKind.group || board[i].length != 3) continue;
      final have = {for (final t in board[i]) if (!isJoker(t)) tileColor(t).index};
      for (var c = 0; c < 4; c++) {
        final t = _t(c, info.values.first);
        if (have.contains(c) || all.contains(t)) continue;
        final nb = [for (final s in board) List.of(s)];
        nb[i] = [...nb[i], t];
        tries.add((nb, rack));
      }
    }
    tries.shuffle(rng);
    for (final (b, r) in tries.take(24)) {
      final c = checkPuzzle(b, r);
      if (c != null) return (b, r, c);
    }
    return null;
  }

  /// A different valid arrangement of the same table tiles (step 6). Tiles that don't fit
  /// aren't possible here (the winning table minus the rack always fits), so it never drops.
  List<List<int>>? _rebuild(List<List<int>> board) {
    final tiles = [for (final s in board) ...s];
    final sols = solveAll(tiles, limit: 6, shuffle: rng);
    if (sols.length < 2) return null;
    final key = _key(board);
    final other = sols.where((s) => _key(_withJokerIds(s, tiles)) != key).toList();
    if (other.isEmpty) return null;
    return _withJokerIds(other[rng.nextInt(other.length)], tiles);
  }

  String _key(List<List<int>> sets) => ([for (final s in sets) ([...s]..sort()).join(',')]..sort()).join('|');

  /// Forces [tech]: adds the "before" sets to [board], the tiles to [rack] and the "after"
  /// sets to [solution]. False (nothing added) when there's no room.
  bool _core(Technique tech, List<List<int>> board, List<int> rack, List<List<int>> solution) {
    final saved = Set.of(_used);
    final savedJ = (_jokersLeft, _nextJoker);
    final ok = switch (tech) {
      Technique.jokerToNewSet => _coreJokerToNew(board, rack, solution),
      Technique.jokerShift => _coreJokerShift(board, rack, solution),
      Technique.splitRun => _coreSplitRun(board, rack, solution),
      Technique.splitGroup => _coreSplitGroup(board, rack, solution),
      Technique.runToGroup => _coreRunToGroup(board, rack, solution),
    };
    if (!ok) {
      _used = saved;
      _jokersLeft = savedJ.$1;
      _nextJoker = savedJ.$2;
    }
    return ok;
  }

  /// A run of [len] free tiles in colour [c] starting at [s], or null.
  List<int>? _run(int c, int s, int len) {
    if (s < 1 || s + len - 1 > 13) return null;
    for (var v = s; v < s + len; v++) {
      if (!_free(c, v)) return null;
    }
    return [for (var v = s; v < s + len; v++) _take(c, v)];
  }

  /// Two free tiles that make a set with one more tile: for a joker (any) or a given tile.
  /// Returns them in table order, with [slot] where the extra tile goes.
  ({List<int> tiles, int slot})? _pairFor({int? number, int? avoidColor}) {
    for (var tries = 0; tries < 12; tries++) {
      if (rng.nextBool() || number != null) {
        final n = number ?? 1 + rng.nextInt(13);
        final cs = _colors().where((c) => c != avoidColor && _free(c, n)).take(2).toList();
        if (cs.length == 2) return (tiles: [_take(cs[0], n), _take(cs[1], n)], slot: 2);
      } else {
        final c = rng.nextInt(4);
        final shape = rng.nextInt(3); // xx_, _xx, x_x
        final s = 1 + rng.nextInt(11);
        final vals = [s, s + 1, s + 2];
        final hole = shape == 0 ? 2 : (shape == 1 ? 0 : 1);
        final real = [for (var i = 0; i < 3; i++) if (i != hole) vals[i]];
        if (real.every((v) => _free(c, v))) return (tiles: [for (final v in real) _take(c, v)], slot: hole);
      }
    }
    return null;
  }

  bool _coreJokerToNew(List<List<int>> board, List<int> rack, List<List<int>> solution) {
    if (_jokersLeft <= 0) return false;
    final c = rng.nextInt(4), len = 3 + rng.nextInt(3), s = 1 + rng.nextInt(14 - len);
    final run = _run(c, s, len);
    if (run == null) return false;
    final pair = _pairFor();
    if (pair == null) return false;
    final k = rng.nextInt(len);
    final j = _joker();
    final before = List.of(run)..[k] = j;
    final newSet = List.of(pair.tiles)..insert(pair.slot, j);
    board.add(before);
    rack.addAll([run[k], ...pair.tiles]);
    solution.addAll([run, newSet]);
    return true;
  }

  bool _coreJokerShift(List<List<int>> board, List<int> rack, List<List<int>> solution) {
    if (_jokersLeft <= 0) return false;
    final c = rng.nextInt(4), len = 3 + rng.nextInt(2), s = 1 + rng.nextInt(14 - len);
    // The joker moves to an end: room needed on one side.
    final up = s + len <= 13, down = s > 1;
    if (!up && !down) return false;
    final run = _run(c, s, len);
    if (run == null) return false;
    final k = 1 + rng.nextInt(len - 2); // inside the run
    final j = _joker();
    final before = List.of(run)..[k] = j;
    final after = (up && (!down || rng.nextBool())) ? [...run, j] : [j, ...run];
    // Sometimes a second rack tile goes past the joker (4-J-6 + 5 + 8: 4-5-6-J-8).
    final extra = <int>[];
    if (after.last == j && _free(c, s + len + 1) && rng.nextBool()) {
      extra.add(_take(c, s + len + 1));
      after.add(extra.first);
    }
    board.add(before);
    rack.addAll([run[k], ...extra]);
    solution.add(after);
    return true;
  }

  bool _coreSplitRun(List<List<int>> board, List<int> rack, List<List<int>> solution) {
    final c = rng.nextInt(4), len = 7 + rng.nextInt(3), s = 1 + rng.nextInt(14 - len);
    if (s + len - 1 > 13) return false;
    final m = 3 + rng.nextInt(len - 6); // the middle tile, 3 or more each side
    final mid = s + m;
    // Reserve the run first so its tiles aren't used by the pair.
    for (var v = s; v < s + len; v++) {
      if (!_free(c, v)) return false;
    }
    final run = [for (var v = s; v < s + len; v++) _take(c, v)];
    final useJoker = _jokersLeft > 0 && rng.nextDouble() < .25;
    List<int> rackPart;
    if (useJoker) {
      final other = _colors().where((d) => d != c && _free(d, mid)).firstOrNull;
      if (other == null) return false;
      rackPart = [_take(other, mid), _joker()];
    } else {
      final pair = _pairFor(number: mid, avoidColor: c);
      if (pair == null) return false;
      rackPart = pair.tiles;
    }
    board.add(run);
    rack.addAll(rackPart);
    solution.addAll([run.sublist(0, m), run.sublist(m + 1), [run[m], ...rackPart]]);
    return true;
  }

  bool _coreSplitGroup(List<List<int>> board, List<int> rack, List<List<int>> solution) {
    final n = 1 + rng.nextInt(13);
    if (![0, 1, 2, 3].every((c) => _free(c, n))) return false;
    final group = [for (final c in _colors()) _take(c, n)];
    final give = group[rng.nextInt(4)];
    final c = tileColor(give).index;
    final shape = rng.nextInt(3); // the new run: n n+1 n+2 / n-1 n n+1 / n-2 n-1 n
    final vals = [for (var i = 0; i < 3; i++) n - shape + i];
    if (vals.first < 1 || vals.last > 13) return false;
    final others = vals.where((v) => v != n).toList();
    if (!others.every((v) => _free(c, v))) return false;
    final rackPart = [for (final v in others) _take(c, v)];
    board.add(group);
    rack.addAll(rackPart);
    solution.addAll([
      group.where((t) => t != give).toList(),
      [for (final v in vals) _t(c, v)],
    ]);
    return true;
  }

  bool _coreRunToGroup(List<List<int>> board, List<int> rack, List<List<int>> solution) {
    final c = rng.nextInt(4), len = 4 + rng.nextInt(3), s = 1 + rng.nextInt(14 - len);
    final run = _run(c, s, len);
    if (run == null) return false;
    final atEnd = rng.nextBool();
    final give = atEnd ? run.last : run.first;
    final n = tileNumber(give);
    final pair = _pairFor(number: n, avoidColor: c);
    if (pair == null) return false;
    board.add(run);
    rack.addAll(pair.tiles);
    solution.addAll([
      atEnd ? run.sublist(0, len - 1) : run.sublist(1),
      [give, ...pair.tiles],
    ]);
    return true;
  }

  /// Fills the table up to [target] sets with sets that stay as they are. The tiles are a
  /// random pile; whatever doesn't make a set is dropped (only the leftovers, not the pile).
  /// Some filler sets lend the rack a tile to put on an end, or the rack holds a whole set.
  void _filler(List<List<int>> board, List<int> rack, List<List<int>> solution, int target, PuzzleLevel level) {
    var guard = 0;
    while (solution.length < target && guard++ < 30) {
      final set = rng.nextDouble() < .55 ? _fillRun() : _fillGroup();
      if (set == null) continue;
      final roll = rng.nextDouble();
      if (roll < .22 && _info(set).run && set.length >= 4) {
        // The rack gets an end tile of this run.
        final atEnd = rng.nextBool();
        final t = atEnd ? set.last : set.first;
        board.add(atEnd ? set.sublist(0, set.length - 1) : set.sublist(1));
        rack.add(t);
      } else if (roll < .3 && !_info(set).run && set.length == 4) {
        board.add(set.sublist(0, 3));
        rack.add(set[3]);
      } else if (roll < .36 && level != PuzzleLevel.easy && rack.length + set.length <= 10) {
        rack.addAll(set); // a whole new set from the rack
      } else {
        board.add(set);
      }
      solution.add(set);
    }
  }

  ({bool run, List<int> values}) _info(List<int> s) => _read(s)!;

  List<int>? _fillRun() {
    final c = rng.nextInt(4), len = 3 + rng.nextInt(3), s = 1 + rng.nextInt(14 - len);
    final pile = [for (var v = s; v < s + len; v++) if (_free(c, v)) v];
    // Keep the longest stretch of free numbers; drop the rest.
    var bestStart = 0, bestLen = 0, curStart = 0;
    for (var i = 0; i < pile.length; i++) {
      if (i > 0 && pile[i] != pile[i - 1] + 1) curStart = i;
      if (i - curStart + 1 > bestLen) {
        bestLen = i - curStart + 1;
        bestStart = curStart;
      }
    }
    if (bestLen < 3) return null;
    return [for (var i = bestStart; i < bestStart + bestLen; i++) _take(c, pile[i])];
  }

  List<int>? _fillGroup() {
    final n = 1 + rng.nextInt(13);
    final cs = _colors().where((c) => _free(c, n)).toList();
    final size = math.min(cs.length, 3 + rng.nextInt(2));
    if (size < 3) return null;
    return [for (final c in cs.take(size)) _take(c, n)];
  }
}

/// Same puzzle with the colours swapped (dedupe): the smallest text over all 24 colour
/// orders, joker ids ignored.
String canonicalKey(Puzzle p) {
  var best = '';
  for (final perm in _perms) {
    String enc(int t) => isJoker(t) ? 'J' : '${perm[tileColor(t).index]}${tileNumber(t).toString().padLeft(2, '0')}';
    final b = ([for (final s in p.board) s.map(enc).join('.')]..sort()).join('|');
    final r = (p.rack.map(enc).toList()..sort()).join('.');
    final k = '$b#$r';
    if (best.isEmpty || k.compareTo(best) < 0) best = k;
  }
  return best;
}

final List<List<int>> _perms = () {
  final out = <List<int>>[];
  void go(List<int> cur) {
    if (cur.length == 4) {
      out.add(List.of(cur));
      return;
    }
    for (var c = 0; c < 4; c++) {
      if (!cur.contains(c)) go([...cur, c]);
    }
  }

  go([]);
  return out;
}();

/// Endless mode: one new puzzle at [level] made on the phone (null after [maxTries]).
Puzzle? generateOne(PuzzleLevel level, {math.Random? rng, int maxTries = 400}) {
  final g = PuzzleGenerator.withRandom(rng ?? math.Random());
  for (var i = 0; i < maxTries; i++) {
    final p = g.attempt(level);
    if (p != null && levelFor(p.score) == level) return p;
  }
  return null;
}
