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

  /// Minimum rearrangement cost over every solution: board sets that must change, and board
  /// tiles that must move to a different set.
  final int setsChanged;
  final int tilesMoved;
  final int solutions;

  /// The difficulty this puzzle shipped at, if it was generated.
  final PuzzleLevel? band;
  const Puzzle({
    required this.board,
    required this.rack,
    required this.solution,
    this.techniques = const {},
    this.score = 0,
    this.setsChanged = 0,
    this.tilesMoved = 0,
    this.solutions = 0,
    this.band,
  });

  List<int> get allTiles => [for (final s in board) ...s, ...rack];

  Map<String, dynamic> toJson() => {
        'b': [for (final s in board) s.map(encodeTile).join(' ')],
        'r': rack.map(encodeTile).join(' '),
        's': [for (final s in solution) s.map(encodeTile).join(' ')],
        't': [for (final t in techniques) t.index],
        'd': double.parse(score.toStringAsFixed(2)),
        'sc': setsChanged,
        'tm': tilesMoved,
        'n': solutions,
        if (band != null) 'l': band!.index,
      };

  factory Puzzle.fromJson(Map<String, dynamic> j) {
    List<int> dec(String s) => s.isEmpty ? <int>[] : s.split(' ').map(decodeTile).toList();
    return Puzzle(
      board: [for (final s in j['b'] as List) dec(s as String)],
      rack: dec(j['r'] as String),
      solution: [for (final s in j['s'] as List) dec(s as String)],
      techniques: {for (final t in (j['t'] as List? ?? const [])) Technique.values[t as int]},
      score: (j['d'] as num?)?.toDouble() ?? 0,
      setsChanged: j['sc'] as int? ?? 0,
      tilesMoved: j['tm'] as int? ?? 0,
      solutions: j['n'] as int? ?? 0,
      band: j['l'] is int ? PuzzleLevel.values[j['l'] as int] : null,
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

/// One search for a split of every tile into valid sets.
class SolveOutcome {
  final List<List<List<int>>> solutions;

  /// False when the node budget ran out before every branch was tried (the list may miss a
  /// cheaper solution, so the puzzle should be rejected).
  final bool exhausted;
  final int nodes;
  const SolveOutcome(this.solutions, {required this.exhausted, required this.nodes});
}

/// The full solver: ways to split every tile in [tiles] into valid sets (jokers come back as
/// [kAnyJoker]). Stops after [limit] solutions. [shuffle] tries sets in a random order (the
/// generator uses it to build a different arrangement of the same tiles).
List<List<List<int>>> solveAll(Iterable<int> tiles, {int limit = 1 << 30, math.Random? shuffle, int nodeLimit = 100000}) =>
    solveSearch(tiles, limit: limit, shuffle: shuffle, nodeLimit: nodeLimit).solutions;

SolveOutcome solveSearch(Iterable<int> tiles, {int limit = 1 << 30, math.Random? shuffle, int nodeLimit = 100000}) {
  final pile = _Pile.of(tiles);
  final out = <List<List<int>>>[];
  final dead = <String>{};
  final cur = <List<int>>[];
  var nodes = 0;
  var cap = false;
  bool rec() {
    if (out.length >= limit) return true;
    if (++nodes > nodeLimit) {
      cap = true;
      return true;
    }
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
      if (out.length >= limit || cap) return true;
    }
    if (!any) dead.add(key);
    return any;
  }

  rec();
  return SolveOutcome(out, exhausted: !cap, nodes: nodes);
}

bool solvable(Iterable<int> tiles) => solveSearch(tiles, limit: 1, nodeLimit: 30000).solutions.isNotEmpty;

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
  int get setsChanged => broken;

  /// Board tiles (numbered, plus a joker that leaves its set) that move to a different set.
  final int tilesMoved;
  bool get singleDetach => setsChanged <= 1 && tilesMoved <= 1;
  const SolutionShape(this.techniques, this.broken, [this.tilesMoved = 0]);
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
  var bestMoved = 0;
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
    var moved = 0;
    for (var i = 0; i < start.length; i++) {
      final real = [for (final x in start[i]) if (!isJoker(x)) x];
      final dest = <int, int>{};
      for (final x in real) {
        dest[where[x]!] = (dest[where[x]!] ?? 0) + 1;
      }
      int? home;
      var homeCount = -1;
      for (final e in dest.entries) {
        if (e.value > homeCount) {
          home = e.key;
          homeCount = e.value;
        }
      }
      for (var a = 0; a < startJ.length; a++) {
        if (startJ[a].$1 != i) continue;
        final dj = solJ[pick[a]].$1;
        home ??= dj;
        if (dj != home) moved++;
      }
      for (final x in real) {
        if (where[x] != home) moved++;
      }
    }
    final better = best == null ||
        br.length < bestBroken ||
        (br.length == bestBroken && moved < bestMoved) ||
        (br.length == bestBroken && moved == bestMoved && t.length < best!.length);
    if (better) {
      best = t;
      bestBroken = br.length;
      bestMoved = moved;
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

  if (startJ.length > solJ.length) return const SolutionShape({}, 0, 0);
  perm([], {});
  return SolutionShape(best ?? fixed, best == null ? brokenSets.length : bestBroken, bestMoved);
}

/// The full check of a puzzle: solvable, not solvable with simple moves only, and every
/// solution (up to [limit]) uses at least one technique. Costs are the minimum over every
/// solution. Null when it fails or the solver couldn't finish.
class PuzzleCheck {
  final int solutions;

  /// Techniques of the cheapest solution (fewest sets changed, then fewest tiles moved).
  final Set<Technique> needs;
  final int minTechniques;
  final int minBroken;
  int get minSetsChanged => minBroken;
  final int minTilesMoved;

  /// True when any solution only pulls one tile off one board set (plus ends / new rack sets).
  final bool anySingleDetach;
  final int rackSets;
  final List<List<int>> firstSolution;
  const PuzzleCheck({
    required this.solutions,
    required this.needs,
    required this.minTechniques,
    required this.minBroken,
    required this.minTilesMoved,
    required this.anySingleDetach,
    required this.rackSets,
    required this.firstSolution,
  });
}

PuzzleCheck? checkPuzzle(List<List<int>> board, List<int> rack, {int limit = 40, int nodeLimit = 80000}) {
  if (board.any((s) => !isValidMeld(s))) return null;
  final all = [for (final s in board) ...s, ...rack];
  if (all.toSet().length != all.length) return null;
  if (simpleSolvable(board, rack)) return null;
  final found = solveSearch(all, limit: limit + 1, nodeLimit: nodeLimit);
  if (!found.exhausted) return null;
  if (found.solutions.isEmpty || found.solutions.length > limit) return null;
  var minBroken = 1 << 20;
  var minMoved = 1 << 20;
  var anySingle = false;
  SolutionShape? cheapest;
  var simplest = found.solutions.first;
  for (final s in found.solutions) {
    final sh = shapeOf(board, s);
    if (sh.techniques.isEmpty) return null;
    if (sh.singleDetach) anySingle = true;
    final better = sh.broken < minBroken || (sh.broken == minBroken && sh.tilesMoved < minMoved);
    if (better) {
      minBroken = sh.broken;
      minMoved = sh.tilesMoved;
      cheapest = sh;
      simplest = s;
    }
  }
  return PuzzleCheck(
    solutions: found.solutions.length,
    needs: cheapest!.techniques,
    minTechniques: cheapest.techniques.length,
    minBroken: minBroken,
    minTilesMoved: minMoved,
    anySingleDetach: anySingle,
    rackSets: rackOnlySetCount(rack),
    firstSolution: simplest,
  );
}

/// How many disjoint complete sets can be made from [rack] alone (tiles left over don't count).
int rackOnlySetCount(List<int> rack) {
  if (rack.length < 3) return 0;
  final pile = _Pile.of(rack);
  var best = 0, nodes = 0;
  void rec(int n) {
    if (n > best) best = n;
    if (++nodes > 4000) return;
    final low = pile.lowest();
    if (low == null) return;
    final (c, num) = low;
    final me = _t(c, num);
    pile.take([me]);
    final sets = _setsWith(pile, c, num);
    pile.give([me]);
    for (final s in sets) {
      pile.take(s);
      rec(n + 1);
      pile.give(s);
    }
    pile.take([me]);
    rec(n);
    pile.give([me]);
  }

  rec(0);
  return best;
}

/// Whether a checked puzzle is hard enough for [level]. Costs are the minimum over every
/// solution. A "single detach" (only one tile leaves one board set) never ships, even as Easy.
bool qualifiesFor(PuzzleLevel level, List<List<int>> board, List<int> rack, PuzzleCheck c) {
  if (c.anySingleDetach || c.minSetsChanged < 2) return false;
  switch (level) {
    case PuzzleLevel.easy:
      return c.minSetsChanged >= 2 && c.rackSets <= 1 && rack.length <= 8;
    case PuzzleLevel.medium:
      return c.minSetsChanged >= 3 && c.minTilesMoved >= 2 && c.minTechniques >= 2 && c.rackSets == 0;
    case PuzzleLevel.hard:
      return c.minSetsChanged >= 4 && c.minTilesMoved >= 4 && c.minTechniques >= 2 && c.rackSets == 0 && c.solutions <= 16;
  }
}

/// Highest difficulty this puzzle qualifies for, or null if it isn't hard enough to ship.
PuzzleLevel? levelOf(List<List<int>> board, List<int> rack, PuzzleCheck c) {
  if (qualifiesFor(PuzzleLevel.hard, board, rack, c)) return PuzzleLevel.hard;
  if (qualifiesFor(PuzzleLevel.medium, board, rack, c)) return PuzzleLevel.medium;
  if (qualifiesFor(PuzzleLevel.easy, board, rack, c)) return PuzzleLevel.easy;
  return null;
}

/// Ordering score within a difficulty: more rearrangement, fewer solutions, a bigger rack.
double scorePuzzle(List<List<int>> board, List<int> rack, PuzzleCheck c) {
  return 3.0 * c.minSetsChanged +
      1.6 * c.minTilesMoved +
      1.2 * c.minTechniques +
      0.25 * rack.length +
      (c.solutions == 1 ? 2 : (c.solutions <= 3 ? 1 : 0));
}

const kPuzzlePackVersion = 2;

// --- the generator ---------------------------------------------------------------------

/// Counters for one generator run.
class GenStats {
  int attempts = 0;
  int accepted = 0;
  int simpleRejects = 0;
  int repairsTried = 0;
  int repairsWorked = 0;
  int otherRejects = 0;
  int scrambleFails = 0;
  int pullFails = 0;
  int qualifyRejects = 0;
  int solverCaps = 0;
  @override
  String toString() => 'attempts $attempts, accepted $accepted, simple-solvable $simpleRejects, '
      'scramble-fail $scrambleFails, pull-fail $pullFails, qualify-fail $qualifyRejects, '
      'solver-cap $solverCaps, other rejects $otherRejects';
}

/// Builds puzzles: a winning table of interlocking sets, then several valid inverse
/// rearrangements (the "before" picture), then rack tiles pulled so they have to be woven
/// back into the table. Both solvers and the min-cost measure decide whether it ships.
class PuzzleGenerator {
  final math.Random rng;
  final GenStats stats = GenStats();
  PuzzleGenerator(int seed) : rng = math.Random(seed);
  PuzzleGenerator.withRandom(this.rng);

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

  /// One try. May qualify at a different level than [aim]; the packer files it by [levelOf].
  Puzzle? attempt(PuzzleLevel aim) {
    stats.attempts++;
    _used = {};
    _jokersLeft = switch (aim) {
      PuzzleLevel.easy => rng.nextDouble() < .35 ? 1 : 0,
      PuzzleLevel.medium => rng.nextDouble() < .55 ? 1 : (rng.nextDouble() < .3 ? 2 : 0),
      PuzzleLevel.hard => rng.nextDouble() < .5 ? 2 : 1,
    };
    _nextJoker = 0;
    final target = switch (aim) {
      PuzzleLevel.easy => 5 + rng.nextInt(3),
      PuzzleLevel.medium => 6 + rng.nextInt(3),
      PuzzleLevel.hard => 7 + rng.nextInt(3),
    };
    final solution = _buildInterlocking(target, aim);
    if (solution == null || solution.length < 5) {
      stats.otherRejects++;
      return null;
    }
    var board = [for (final s in solution) List.of(s)];
    final wantScrambles = switch (aim) {
      PuzzleLevel.easy => 2 + rng.nextInt(2),
      PuzzleLevel.medium => 4 + rng.nextInt(3),
      PuzzleLevel.hard => 6 + rng.nextInt(4),
    };
    var applied = 0;
    for (var i = 0; i < wantScrambles * 4 && applied < wantScrambles; i++) {
      final next = _scrambleOnce(board);
      if (next != null) {
        board = next;
        applied++;
      }
    }
    final minScrambles = switch (aim) {
      PuzzleLevel.easy => 2,
      PuzzleLevel.medium => 3,
      PuzzleLevel.hard => 4,
    };
    if (applied < minScrambles) {
      stats.scrambleFails++;
      return null;
    }
    for (var t = 0; t < 8; t++) {
      final pulled = _pullRack(board, solution, aim);
      if (pulled == null) continue;
      final p = _finish(pulled.$1, pulled.$2, solution);
      if (p != null) return p;
    }
    stats.pullFails++;
    return null;
  }

  Puzzle? _finish(List<List<int>> start, List<int> rack, List<List<int>> solution) {
    if (rack.isEmpty || rack.length > 14) {
      stats.otherRejects++;
      return null;
    }
    final check = checkPuzzle(start, rack);
    if (check == null) {
      // simple-solvable vs unsolvable vs solver cap: checkPuzzle doesn't distinguish;
      // a second simple check is cheap.
      if (simpleSolvable(start, rack)) {
        stats.simpleRejects++;
      } else {
        stats.otherRejects++;
      }
      return null;
    }
    final lvl = levelOf(start, rack, check);
    if (lvl == null) {
      stats.qualifyRejects++;
      return null;
    }
    stats.accepted++;
    return Puzzle(
      board: [for (final s in start) List.of(s)],
      rack: List.of(rack)..shuffle(rng),
      solution: _withJokerIds(check.firstSolution, [for (final s in start) ...s, ...rack]),
      techniques: check.needs,
      score: scorePuzzle(start, rack, check),
      setsChanged: check.minSetsChanged,
      tilesMoved: check.minTilesMoved,
      solutions: check.solutions,
      band: lvl,
    );
  }

  List<List<int>> _withJokerIds(List<List<int>> sol, List<int> tiles) {
    final jokers = tiles.where(isJoker).toList()..sort();
    var k = 0;
    return [
      for (final s in sol) [for (final t in s) t == kAnyJoker ? jokers[k++] : t],
    ];
  }

  List<List<int>>? _buildInterlocking(int target, PuzzleLevel aim) {
    final sets = <List<int>>[];
    final clusters = [_clusterTranspose, _clusterBridge, _clusterStealChain, _clusterJokerWeave];
    clusters.shuffle(rng);
    final want = switch (aim) {
      PuzzleLevel.easy => 1,
      PuzzleLevel.medium => 2,
      PuzzleLevel.hard => 2 + rng.nextInt(2),
    };
    var made = 0;
    for (final fn in [...clusters, ...clusters]) {
      if (made >= want || sets.length >= target) break;
      if (_tryCluster(fn, sets)) made++;
    }
    if (made == 0) return null;
    var guard = 0;
    while (sets.length < target && guard++ < 24) {
      final fn = clusters[rng.nextInt(clusters.length)];
      if (!_tryCluster(fn, sets)) _addFiller(sets);
    }
    return sets.length >= 5 ? sets : null;
  }

  bool _tryCluster(bool Function(List<List<int>>) fn, List<List<int>> sets) {
    final saved = Set.of(_used);
    final savedJ = (_jokersLeft, _nextJoker);
    final n = sets.length;
    if (fn(sets)) return true;
    _used = saved;
    _jokersLeft = savedJ.$1;
    _nextJoker = savedJ.$2;
    if (sets.length > n) sets.removeRange(n, sets.length);
    return false;
  }

  /// 3 numbers × 3 colours, laid out as 3 runs or 3 groups so a scramble can transpose them.
  bool _clusterTranspose(List<List<int>> sets) {
    final colors = _colors().take(3).toList();
    final n0 = 1 + rng.nextInt(11);
    for (final c in colors) {
      for (final n in [n0, n0 + 1, n0 + 2]) {
        if (!_free(c, n)) return false;
      }
    }
    if (rng.nextBool()) {
      for (final c in colors) {
        sets.add([for (final n in [n0, n0 + 1, n0 + 2]) _take(c, n)]);
      }
    } else {
      for (final n in [n0, n0 + 1, n0 + 2]) {
        sets.add([for (final c in colors) _take(c, n)]);
      }
    }
    return true;
  }

  /// A long run that the solution splits, with the middle tile in a group.
  bool _clusterBridge(List<List<int>> sets) {
    final c = rng.nextInt(4);
    final len = 7 + rng.nextInt(3);
    final s = 1 + rng.nextInt(14 - len);
    if (s + len - 1 > 13) return false;
    final mid = s + 3 + rng.nextInt(len - 6);
    for (var v = s; v < s + len; v++) {
      if (!_free(c, v)) return false;
    }
    final others = _colors().where((d) => d != c && _free(d, mid)).take(2).toList();
    if (others.length < 2) return false;
    final run = [for (var v = s; v < s + len; v++) _take(c, v)];
    final m = mid - s;
    sets.add(run.sublist(0, m));
    sets.add(run.sublist(m + 1));
    sets.add([run[m], _take(others[0], mid), _take(others[1], mid)]);
    return true;
  }

  /// A group of 4 in the making: one tile belongs to a run in the solution.
  bool _clusterStealChain(List<List<int>> sets) {
    final n = 2 + rng.nextInt(11);
    if (![0, 1, 2, 3].every((c) => _free(c, n))) return false;
    final giveC = rng.nextInt(4);
    final runLen = 3 + rng.nextInt(2);
    final up = n + runLen - 1 <= 13, down = n - runLen + 1 >= 1;
    if (!up && !down) return false;
    final start = (up && (!down || rng.nextBool())) ? n : n - runLen + 1;
    for (var v = start; v < start + runLen; v++) {
      if (v != n && !_free(giveC, v)) return false;
    }
    final group = [for (final c in _colors()) _take(c, n)];
    final give = group.firstWhere((t) => tileColor(t).index == giveC);
    final run = [for (var v = start; v < start + runLen; v++) v == n ? give : _take(giveC, v)];
    sets.add(group.where((t) => t != give).toList());
    sets.add(run);
    return true;
  }

  /// A joker sits in a new set in the solution; its real tile is back in a run.
  bool _clusterJokerWeave(List<List<int>> sets) {
    if (_jokersLeft <= 0) return false;
    final c = rng.nextInt(4);
    final len = 3 + rng.nextInt(2);
    final s = 1 + rng.nextInt(14 - len);
    if (s + len - 1 > 13) return false;
    for (var v = s; v < s + len; v++) {
      if (!_free(c, v)) return false;
    }
    final pair = <int>[];
    if (rng.nextBool()) {
      final n = 1 + rng.nextInt(13);
      final cs = _colors().where((d) => _free(d, n)).take(2).toList();
      if (cs.length < 2) return false;
      pair.addAll([for (final d in cs) _take(d, n)]);
    } else {
      final d = rng.nextInt(4);
      final t = 1 + rng.nextInt(11);
      if (!_free(d, t) || !_free(d, t + 1)) return false;
      pair.addAll([_take(d, t), _take(d, t + 1)]);
    }
    final run = [for (var v = s; v < s + len; v++) _take(c, v)];
    final j = _joker();
    // Solution keeps the real run and a new set that holds the joker.
    sets.add(run);
    final neu = List.of(pair)..insert(rng.nextInt(3), j);
    sets.add(neu);
    return true;
  }

  void _addFiller(List<List<int>> sets) {
    if (rng.nextBool()) {
      final c = rng.nextInt(4), len = 3 + rng.nextInt(3), s = 1 + rng.nextInt(14 - len);
      if (s + len - 1 > 13) return;
      final pile = [for (var v = s; v < s + len; v++) if (_free(c, v)) v];
      var bestStart = 0, bestLen = 0, cur = 0;
      for (var i = 0; i < pile.length; i++) {
        if (i > 0 && pile[i] != pile[i - 1] + 1) cur = i;
        if (i - cur + 1 > bestLen) {
          bestLen = i - cur + 1;
          bestStart = cur;
        }
      }
      if (bestLen >= 3) {
        sets.add([for (var i = bestStart; i < bestStart + bestLen; i++) _take(c, pile[i])]);
      }
    } else {
      final n = 1 + rng.nextInt(13);
      final cs = _colors().where((c) => _free(c, n)).toList();
      final size = math.min(cs.length, 3 + rng.nextInt(2));
      if (size >= 3) sets.add([for (final c in cs.take(size)) _take(c, n)]);
    }
  }

  List<List<int>>? _scrambleOnce(List<List<int>> board) {
    final ops = [_scrTranspose, _scrMergeRuns, _scrSplitRun, _scrGroupToRun, _scrRunToGroup, _scrMoveJoker];
    ops.shuffle(rng);
    for (final op in ops) {
      final r = op(board);
      if (r != null && _allValid(r) && _sameTiles(r, board) && _key(r) != _key(board)) return r;
    }
    return null;
  }

  bool _allValid(List<List<int>> sets) => sets.every((s) => isValidMeld(s));

  bool _sameTiles(List<List<int>> a, List<List<int>> b) {
    final ta = [for (final s in a) ...s]..sort();
    final tb = [for (final s in b) ...s]..sort();
    if (ta.length != tb.length) return false;
    for (var i = 0; i < ta.length; i++) {
      if (ta[i] != tb[i]) return false;
    }
    return true;
  }

  String _key(List<List<int>> sets) => ([for (final s in sets) ([...s]..sort()).join(',')]..sort()).join('|');

  ({bool run, List<int> values, TileColor? color})? _info(List<int> s) {
    final r = _read(s);
    if (r == null) return null;
    final real = s.where((t) => !isJoker(t) && t != kAnyJoker);
    return (run: r.run, values: r.values, color: real.isEmpty ? null : tileColor(real.first));
  }

  List<List<int>> _replace(List<List<int>> board, Iterable<int> remove, List<List<int>> add) {
    final drop = remove.toSet();
    return [for (var i = 0; i < board.length; i++) if (!drop.contains(i)) List.of(board[i]), ...add];
  }

  /// 3 same-value runs of 3 become 3 groups, or 3 consecutive groups of 3 become 3 runs.
  List<List<int>>? _scrTranspose(List<List<int>> board) {
    final runs = <({int i, int color, int start, List<int> tiles})>[];
    final groups = <({int i, int number, Set<int> colors, List<int> tiles})>[];
    for (var i = 0; i < board.length; i++) {
      final info = _info(board[i]);
      if (info == null || board[i].any(isJoker) || board[i].length != 3) continue;
      if (info.run) {
        runs.add((i: i, color: info.color!.index, start: info.values.first, tiles: board[i]));
      } else {
        groups.add((i: i, number: info.values.first, colors: {for (final t in board[i]) tileColor(t).index}, tiles: board[i]));
      }
    }
    // Three runs, same start, three colours.
    for (final a in runs) {
      final mates = [for (final r in runs) if (r.start == a.start && r.color != a.color) r];
      final colors = {a.color, ...mates.map((m) => m.color)};
      if (mates.length >= 2 && colors.length >= 3) {
        final pick = [a, ...mates.take(2)];
        final byColor = {for (final r in pick) r.color: r.tiles};
        final next = [
          for (var k = 0; k < 3; k++) [for (final r in pick) byColor[r.color]![k]],
        ];
        // groups should be one number each
        return _replace(board, pick.map((p) => p.i), next);
      }
    }
    // Three groups of consecutive numbers with the same three colours.
    groups.sort((a, b) => a.number - b.number);
    for (var i = 0; i + 2 < groups.length; i++) {
      final a = groups[i], b = groups[i + 1], c = groups[i + 2];
      if (b.number != a.number + 1 || c.number != a.number + 2) continue;
      if (a.colors.length != 3 || a.colors.difference(b.colors).isNotEmpty || a.colors.difference(c.colors).isNotEmpty) {
        continue;
      }
      final byNum = {a.number: a, b.number: b, c.number: c};
      final next = [
        for (final col in a.colors)
          [
            for (final n in [a.number, b.number, c.number])
              byNum[n]!.tiles.firstWhere((t) => tileColor(t).index == col),
          ],
      ];
      return _replace(board, [a.i, b.i, c.i], next);
    }
    return null;
  }

  List<List<int>>? _scrMergeRuns(List<List<int>> board) {
    final runs = <({int i, int color, int lo, int hi, List<int> tiles})>[];
    for (var i = 0; i < board.length; i++) {
      final info = _info(board[i]);
      if (info == null || !info.run) continue;
      runs.add((i: i, color: info.color!.index, lo: info.values.first, hi: info.values.last, tiles: board[i]));
    }
    runs.shuffle(rng);
    for (final a in runs) {
      for (final b in runs) {
        if (a.i >= b.i || a.color != b.color) continue;
        if (a.hi + 1 == b.lo) {
          return _replace(board, [a.i, b.i], [
            [...a.tiles, ...b.tiles]
          ]);
        }
        if (b.hi + 1 == a.lo) {
          return _replace(board, [a.i, b.i], [
            [...b.tiles, ...a.tiles]
          ]);
        }
      }
    }
    return null;
  }

  List<List<int>>? _scrSplitRun(List<List<int>> board) {
    final opts = <(int, int)>[]; // set index, split after this many tiles
    for (var i = 0; i < board.length; i++) {
      final info = _info(board[i]);
      if (info == null || !info.run || board[i].length < 6) continue;
      for (var k = 3; k <= board[i].length - 3; k++) {
        opts.add((i, k));
      }
    }
    if (opts.isEmpty) return null;
    final (i, k) = opts[rng.nextInt(opts.length)];
    return _replace(board, [i], [board[i].sublist(0, k), board[i].sublist(k)]);
  }

  List<List<int>>? _scrGroupToRun(List<List<int>> board) {
    final opts = <(int, int, int)>[]; // group i, tile k, run j
    for (var i = 0; i < board.length; i++) {
      final g = _info(board[i]);
      if (g == null || g.run || board[i].length != 4) continue;
      for (var k = 0; k < 4; k++) {
        final t = board[i][k];
        if (isJoker(t)) continue;
        for (var j = 0; j < board.length; j++) {
          if (j == i) continue;
          final r = _info(board[j]);
          if (r == null || !r.run || r.color != tileColor(t) || board[j].length >= 13) continue;
          if (tileNumber(t) == r.values.first - 1 || tileNumber(t) == r.values.last + 1) {
            opts.add((i, k, j));
          }
        }
      }
    }
    if (opts.isEmpty) return null;
    final (i, k, j) = opts[rng.nextInt(opts.length)];
    final t = board[i][k];
    final group = [for (final x in board[i]) if (x != t) x];
    final r = _info(board[j])!;
    final run = tileNumber(t) == r.values.first - 1 ? [t, ...board[j]] : [...board[j], t];
    return _replace(board, [i, j], [group, run]);
  }

  List<List<int>>? _scrRunToGroup(List<List<int>> board) {
    final opts = <(int, bool, int)>[]; // run i, fromEnd, group j
    for (var i = 0; i < board.length; i++) {
      final r = _info(board[i]);
      if (r == null || !r.run || board[i].length < 4) continue;
      for (final end in [true, false]) {
        final t = end ? board[i].last : board[i].first;
        if (isJoker(t)) continue;
        for (var j = 0; j < board.length; j++) {
          if (j == i) continue;
          final g = _info(board[j]);
          if (g == null || g.run || board[j].length != 3 || g.values.first != tileNumber(t)) continue;
          final have = {for (final x in board[j]) if (!isJoker(x)) tileColor(x).index};
          if (!have.contains(tileColor(t).index)) opts.add((i, end, j));
        }
      }
    }
    if (opts.isEmpty) return null;
    final (i, end, j) = opts[rng.nextInt(opts.length)];
    final t = end ? board[i].last : board[i].first;
    final run = end ? board[i].sublist(0, board[i].length - 1) : board[i].sublist(1);
    return _replace(board, [i, j], [run, [...board[j], t]]);
  }

  List<List<int>>? _scrMoveJoker(List<List<int>> board) {
    final from = <(int, int)>[];
    for (var i = 0; i < board.length; i++) {
      if (board[i].length < 4) continue;
      for (var k = 0; k < board[i].length; k++) {
        if (!isJoker(board[i][k])) continue;
        final rest = [for (var x = 0; x < board[i].length; x++) if (x != k) board[i][x]];
        if (isValidMeld(rest)) from.add((i, k));
      }
    }
    if (from.isEmpty) return null;
    from.shuffle(rng);
    for (final (i, k) in from) {
      final joker = board[i][k];
      final rest = [for (var x = 0; x < board[i].length; x++) if (x != k) board[i][x]];
      final dests = <(int, List<int>)>[];
      for (var j = 0; j < board.length; j++) {
        if (j == i || board[j].length >= 13) continue;
        for (final cand in [
          [joker, ...board[j]],
          [...board[j], joker],
          if (board[j].length >= 2)
            for (var at = 1; at < board[j].length; at++) [...board[j].sublist(0, at), joker, ...board[j].sublist(at)],
        ]) {
          if (isValidMeld(cand)) dests.add((j, cand));
        }
      }
      if (dests.isEmpty) continue;
      final (j, cand) = dests[rng.nextInt(dests.length)];
      return _replace(board, [i, j], [rest, cand]);
    }
    return null;
  }

  /// Pull rack tiles from the scrambled board and rebuild the remainder into a valid start.
  (List<List<int>>, List<int>)? _pullRack(List<List<int>> board, List<List<int>> solution, PuzzleLevel aim) {
    final boardTiles = [for (final s in board) ...s];
    final whereB = <int, int>{};
    final whereS = <int, int>{};
    for (var i = 0; i < board.length; i++) {
      for (final t in board[i]) {
        if (!isJoker(t)) whereB[t] = i;
      }
    }
    for (var i = 0; i < solution.length; i++) {
      for (final t in solution[i]) {
        if (!isJoker(t)) whereS[t] = i;
      }
    }
    final changed = [for (final t in boardTiles) if (!isJoker(t) && whereB[t] != null && whereS[t] != null && whereB[t] != whereS[t]) t];
    final want = switch (aim) {
      PuzzleLevel.easy => 3 + rng.nextInt(3),
      PuzzleLevel.medium => 5 + rng.nextInt(4),
      PuzzleLevel.hard => 6 + rng.nextInt(5),
    };
    final minSets = aim == PuzzleLevel.easy ? 2 : 3;
    final pool = [...changed, ...boardTiles.where((t) => !changed.contains(t))]..shuffle(rng);
    // Prefer changed tiles first (they're already at the front, just don't overshuffle them away).
    final ranked = [...changed..shuffle(rng), ...boardTiles.where((t) => !changed.contains(t)).toList()..shuffle(rng)];
    for (var attempt = 0; attempt < 10; attempt++) {
      final pick = <int>[];
      final fromSet = <int>{};
      final src = attempt == 0 ? ranked : (List.of(pool)..shuffle(rng));
      for (final t in src) {
        if (pick.length >= want) break;
        if (isJoker(t) && pick.where(isJoker).isNotEmpty && aim == PuzzleLevel.easy) continue;
        pick.add(t);
        if (whereB[t] != null) fromSet.add(whereB[t]!);
      }
      if (pick.length < 3 || fromSet.length < minSets) continue;
      if (aim == PuzzleLevel.easy && rackOnlySetCount(pick) > 1) {
        _dropOneRackSet(pick);
      }
      if (aim != PuzzleLevel.easy) {
        var guard = 0;
        while (rackOnlySetCount(pick) > 0 && pick.length > 3 && guard++ < 6) {
          _dropOneRackSet(pick);
        }
        if (rackOnlySetCount(pick) > 0) continue;
      }
      if (pick.length < 3) continue;
      final remain = [for (final t in boardTiles) if (!pick.contains(t)) t];
      if (remain.length < 9) continue;
      final found = solveSearch(remain, limit: 8, nodeLimit: 30000, shuffle: rng);
      if (found.solutions.isEmpty) continue;
      final start = _withJokerIds(found.solutions[rng.nextInt(found.solutions.length)], remain);
      if (!_allValid(start)) continue;
      return (start, List.of(pick));
    }
    return null;
  }

  void _dropOneRackSet(List<int> pick) {
    // Remove one tile from a complete rack-only set so the rest aren't a free play.
    final pile = _Pile.of(pick);
    // Find any valid set and drop its first numbered tile.
    final low = pile.lowest();
    if (low == null) {
      if (pick.isNotEmpty) pick.removeLast();
      return;
    }
    final (c, n) = low;
    pile.take([_t(c, n)]);
    final sets = _setsWith(pile, c, n);
    pile.give([_t(c, n)]);
    if (sets.isEmpty) {
      pick.remove(_t(c, n));
      return;
    }
    final s = sets.first;
    final real = s.firstWhere((t) => t != kAnyJoker, orElse: () => s.first);
    // Map kAnyJoker back to a real joker in pick.
    if (real == kAnyJoker) {
      pick.remove(pick.firstWhere(isJoker));
    } else {
      pick.remove(real);
    }
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
    if (p != null) {
      final c = checkPuzzle(p.board, p.rack);
      if (c != null && levelOf(p.board, p.rack, c) == level) return p;
    }
  }
  return null;
}
