import 'dart:async';
import 'dart:math' as math;

import 'board.dart';
import 'host.dart';
import 'meld.dart';
import 'tiles.dart';

/// Tweakable numbers for the computer players.
class BotTuning {
  /// Most MOVES a bot may make in one turn (null = no limit). A move is one action on the
  /// table: a tile or set from the rack to the board (alone or attached to a set), a tile or
  /// set already on the board moved to attach to another or relocated, a split, or a tile
  /// removed from a set. A play whose moves would go over what's left can't be started.
  static const Map<BotLevel, int?> moveCap = {BotLevel.easy: 6, BotLevel.medium: 12, BotLevel.hard: null};

  /// Chance that a bot overlooks each play it finds (decided once per play per turn).
  static const Map<BotLevel, double> missChance = {BotLevel.easy: 0.40, BotLevel.medium: 0.15, BotLevel.hard: 0.0};

  /// Overlooking never takes a bot below this many plays in a turn: it makes at least
  /// min(plays available, minPlays) plays (Easy 1, Medium 2; Hard makes every play anyway).
  static const Map<BotLevel, int> minPlays = {BotLevel.easy: 1, BotLevel.medium: 2, BotLevel.hard: 0};

  /// Bots decide their whole turn instantly (no thinking delay), then carry
  /// it out one action at a time. Each action is shown, then followed by
  /// its pause before the next action (or the end of the turn).
  ///
  /// At the start of every bot turn the bot does nothing for this long, before any move or draw,
  /// so players see the turn pass to it. It counts against the bot's turn timer like any other time.
  static const int turnStartMs = 1000;

  /// A single tile moved: a rack tile extending a table set, or a tile
  /// moved on the table.
  static const int singleTileMs = 500;

  /// A split, or a whole set moved on the table.
  static const int splitOrSetMoveMs = 1000;

  /// A new set put down from the rack.
  static const int newSetMs = 2000;

  /// With less than this much turn time left (and a valid board), a bot
  /// only starts plays whose every move keeps the board valid; otherwise it
  /// ends its turn.
  static const int safeZoneMs = 5000;

  /// Search budget for picking melds.
  static const int searchNodes = 6000;
}

enum BotActionKind { singleTile, splitOrSetMove, newSet }

enum BotStepType {
  /// A set (or a partial set) from the rack placed on the board as a unit.
  newSet,

  /// A rack tile attached to an end of a set on the board.
  extend,

  /// A rack tile placed alone at a spot.
  tileAt,

  /// A tile already on the board moved to attach to another set (at an index) or placed alone.
  moveTile,

  /// A whole set on the board moved to attach to another set, or relocated to a free spot.
  moveSet,

  /// A set split before a tile.
  split,

  /// A tile taken out of a set on the board and set down alone.
  removeTile,

  /// Joker reclaim: a rack tile put exactly where a table joker sits (the tile the joker
  /// stood for); the joker is taken in hand and must be played again this turn.
  swapJoker,
}

/// One MOVE: a single visible action on the table. Every step counts as exactly 1 move.
class BotStep {
  final BotStepType type;

  /// Tiles of a new set, in order (empty otherwise).
  final List<int> tiles;

  /// The tile moved (extend, tileAt, moveTile, removeTile), the tile a split happens before,
  /// or any tile of the set being moved (moveSet).
  final int? tile;

  /// A tile of the set this step attaches to (extend, moveTile, moveSet), if any.
  final int? targetSetTile;

  /// For extend and moveSet: attach after the target's last tile (true) or before its first.
  final bool atEnd;

  /// For moveTile: the position in the target set (after the moved tile leaves its set).
  final int? index;

  /// For tileAt: where the tile goes.
  final int? row, col;

  const BotStep._(this.type, {this.tiles = const [], this.tile, this.targetSetTile, this.atEnd = true, this.index, this.row, this.col});
  const BotStep.newSet(List<int> tiles) : this._(BotStepType.newSet, tiles: tiles);
  const BotStep.extend(int tile, int setTile, bool atEnd) : this._(BotStepType.extend, tile: tile, targetSetTile: setTile, atEnd: atEnd);
  const BotStep.tileAt(int tile, int row, int col) : this._(BotStepType.tileAt, tile: tile, row: row, col: col);
  const BotStep.moveTile(int tile, {int? toSetTile, int index = 0})
    : this._(BotStepType.moveTile, tile: tile, targetSetTile: toSetTile, index: index);
  const BotStep.moveSet(int setTile, {int? toSetTile, bool atEnd = true})
    : this._(BotStepType.moveSet, tile: setTile, targetSetTile: toSetTile, atEnd: atEnd);
  const BotStep.split(int beforeTile) : this._(BotStepType.split, tile: beforeTile);
  const BotStep.removeTile(int tile) : this._(BotStepType.removeTile, tile: tile);
  const BotStep.swapJoker(int tile, int joker) : this._(BotStepType.swapJoker, tile: tile, targetSetTile: joker);

  bool get isNewSet => type == BotStepType.newSet;
  bool get isExtension => type == BotStepType.extend;

  /// True when the step brings tiles from the rack (rather than moving table tiles).
  bool get fromRack =>
      type == BotStepType.newSet || type == BotStepType.extend || type == BotStepType.tileAt || type == BotStepType.swapJoker;

  /// Every step is one move.
  int get moveCount => 1;

  /// Rack tiles this step puts on the board.
  int get tileCount => switch (type) {
    BotStepType.newSet => tiles.length,
    BotStepType.extend || BotStepType.tileAt || BotStepType.swapJoker => 1,
    _ => 0,
  };

  /// Pacing: a new set from the rack (2 s), a split or whole-set move (1 s), or a single tile (0.5 s).
  BotActionKind get kind => switch (type) {
    BotStepType.newSet => BotActionKind.newSet,
    BotStepType.split || BotStepType.moveSet => BotActionKind.splitOrSetMove,
    _ => BotActionKind.singleTile,
  };
}

/// A PLAY: a series of moves that takes at least one tile from the rack onto the board and
/// ends with a valid board. Moves inside a play may pass through invalid states; the board is
/// only promised valid between plays.
class BotPlay {
  final List<BotStep> steps;
  const BotPlay(this.steps);
  /// Rack tiles this play puts on the board (a reclaimed joker played again doesn't count).
  int get tileCount => rackTiles.difference(reclaimedJokers).length;
  int get moveCount => steps.length;

  /// Table jokers this play takes back (and plays again).
  Set<int> get reclaimedJokers => {
    for (final s in steps)
      if (s.type == BotStepType.swapJoker) s.targetSetTile!,
  };

  /// Rack tiles used, for telling plays apart.
  Set<int> get rackTiles => {
    for (final s in steps)
      if (s.fromRack) ...(s.isNewSet ? s.tiles : [s.tile!]),
  };

  /// Identifies "the same play" across re-evaluations within a turn (for overlooking).
  String get signature =>
      steps.map((s) => '${s.type.index}:${s.tiles.join(',')}:${s.tile}:${s.targetSetTile}:${s.atEnd}:${s.index}').join('|');
}

/// A planned turn: a list of plays, or (if empty) draw.
class BotPlan {
  final List<BotPlay> plays;
  const BotPlan(this.plays);
  factory BotPlan.ofSteps(List<BotStep> steps) => BotPlan([
    for (final s in steps) BotPlay([s]),
  ]);
  bool get draws => plays.isEmpty;
  List<BotStep> get steps => [for (final m in plays) ...m.steps];
  int get tileCount => plays.fold(0, (s, x) => s + x.tileCount);
  int get moveCount => plays.fold(0, (s, x) => s + x.moveCount);
}

/// All runs and groups that can be made from [rack], jokers included.
List<List<int>> candidateMelds(List<int> rack) {
  final jokers = rack.where(isJoker).toList();
  final byColorNum = <int, int>{}; // colour*13+n -> one tile id
  for (final t in rack) {
    if (isJoker(t)) continue;
    byColorNum.putIfAbsent(tileColor(t).index * 13 + tileNumber(t) - 1, () => t);
  }
  final out = <List<int>>[];
  // Runs.
  for (final c in TileColor.values) {
    for (var s = 1; s <= 11; s++) {
      for (var e = s + 2; e <= 13; e++) {
        final tiles = <int>[];
        var jUsed = 0;
        var real = 0;
        var ok = true;
        for (var n = s; n <= e; n++) {
          final t = byColorNum[c.index * 13 + n - 1];
          if (t != null) {
            tiles.add(t);
            real++;
          } else if (jUsed < jokers.length) {
            tiles.add(jokers[jUsed++]);
          } else {
            ok = false;
            break;
          }
        }
        if (!ok) break;
        if (real == 0 || jUsed > 1 && real < 2) continue;
        out.add(tiles);
      }
    }
  }
  // Groups.
  for (var n = 1; n <= 13; n++) {
    final present = <int>[];
    for (final c in TileColor.values) {
      final t = byColorNum[c.index * 13 + n - 1];
      if (t != null) present.add(t);
    }
    if (present.isEmpty) continue;
    for (var mask = 1; mask < (1 << present.length); mask++) {
      final chosen = [
        for (var i = 0; i < present.length; i++)
          if (mask & (1 << i) != 0) present[i],
      ];
      for (var j = 0; j <= jokers.length && chosen.length + j <= 4; j++) {
        if (chosen.length + j < 3) continue;
        if (j > 1 && chosen.length < 2) continue;
        out.add([...chosen, ...jokers.take(j)]);
      }
    }
  }
  return out.where(isValidMeld).toList();
}

/// Picks disjoint melds. With [minPoints] > 0 the combination must reach
/// that many points; otherwise it maximises tiles played (then points).
List<List<int>> bestCombination(List<List<int>> cands, {int minPoints = 0, int? cap}) {
  cands = List.of(cands)..sort((a, b) => b.length - a.length);
  var best = <List<int>>[];
  var bestTiles = 0;
  var bestPts = 0;
  var nodes = 0;
  void dfs(int i, Set<int> used, List<List<int>> chosen, int tiles, int pts) {
    if (++nodes > BotTuning.searchNodes) return;
    if (pts >= minPoints && (tiles > bestTiles || tiles == bestTiles && pts > bestPts)) {
      best = List.of(chosen);
      bestTiles = tiles;
      bestPts = pts;
    }
    for (var k = i; k < cands.length; k++) {
      final m = cands[k];
      if (cap != null && tiles + m.length > cap) continue;
      if (m.any(used.contains)) continue;
      used.addAll(m);
      chosen.add(m);
      dfs(k + 1, used, chosen, tiles + m.length, pts + meldPoints(m));
      chosen.removeLast();
      used.removeAll(m);
    }
  }

  dfs(0, {}, [], 0, 0);
  return bestTiles == 0 ? [] : best;
}

/// Every play the bot can see from [board] and [rack], each ending with a valid board:
///  * a new set from the rack (1 move);
///  * a rack tile added to an end of a table set (1 move);
///  * two rack tiles put down together, plus a spare tile moved over from a table set that
///    stays valid without it (2 moves);
///  * a table run split so that a rack tile can start the second half (2 moves);
///  * a joker reclaim: a rack tile swapped in for a table joker, then the joker played
///    again at the end of a set or in a new set with two rack tiles (2 moves).
List<BotPlay> findPlays(Board board, List<int> rack, {bool rackOnly = false}) {
  final out = <BotPlay>[];
  for (final m in candidateMelds(rack)) {
    out.add(BotPlay([BotStep.newSet(m)]));
  }
  if (rackOnly) return out;
  final blocks = board.blocks.where((b) => isValidMeld(b.tiles)).toList();
  final distinctRack = <int>[];
  for (final t in rack) {
    if (!distinctRack.any((u) => !isJoker(u) && !isJoker(t) && tileColor(u) == tileColor(t) && tileNumber(u) == tileNumber(t))) {
      distinctRack.add(t);
    }
  }
  // Extend an end.
  for (final blk in blocks) {
    for (final t in distinctRack) {
      if (isValidMeld([...blk.tiles, t])) {
        out.add(BotPlay([BotStep.extend(t, blk.tiles.first, true)]));
      } else if (isValidMeld([t, ...blk.tiles])) {
        out.add(BotPlay([BotStep.extend(t, blk.tiles.first, false)]));
      }
    }
  }
  // Two rack tiles + a spare table tile.
  final spares = <({int tile, Block from})>[];
  for (final blk in blocks) {
    if (blk.length < 4) continue;
    for (var i = 0; i < blk.length; i++) {
      final rest = [...blk.tiles]..removeAt(i);
      if (isValidMeld(rest)) spares.add((tile: blk.tiles[i], from: blk));
    }
  }
  if (spares.isNotEmpty) {
    final real = distinctRack.where((t) => !isJoker(t)).toList();
    for (var a = 0; a < real.length; a++) {
      for (var b = a + 1; b < real.length; b++) {
        final pair = [real[a], real[b]]..sort((x, y) => runSortKey(x) - runSortKey(y));
        if (!isCompatible(pair)) continue;
        for (final sp in spares) {
          for (var at = 0; at <= 2; at++) {
            final trio = [...pair]..insert(at, sp.tile);
            if (!isValidMeld(trio)) continue;
            out.add(BotPlay([BotStep.newSet(pair), BotStep.moveTile(sp.tile, toSetTile: pair.first, index: at)]));
            break;
          }
        }
      }
    }
  }
  // Split a run so a rack tile starts its second half: 4 5 6 7 8 + 6 -> 4 5 6 | 6 7 8.
  for (final blk in blocks) {
    if (blk.length < 5) continue;
    for (var i = 2; i <= blk.length - 3; i++) {
      final left = blk.tiles.sublist(0, i + 1), right = blk.tiles.sublist(i + 1);
      for (final t in distinctRack) {
        if (isValidMeld(left) && isValidMeld([t, ...right]) && !isValidMeld(right)) {
          out.add(BotPlay([BotStep.split(right.first), BotStep.extend(t, right.first, false)]));
        }
      }
    }
  }
  // Joker reclaim.
  final real = distinctRack.where((t) => !isJoker(t)).toList();
  for (final blk in blocks) {
    for (final j in blk.tiles.where(isJoker)) {
      for (final t in real) {
        final after = Layout.swapJoker(board, t, j);
        if (after == null) continue;
        final swap = BotStep.swapJoker(t, j);
        for (final tb in after.blocks.where((b) => isValidMeld(b.tiles))) {
          if (isValidMeld([...tb.tiles, j])) {
            out.add(BotPlay([swap, BotStep.moveTile(j, toSetTile: tb.tiles.first, index: tb.length)]));
          } else if (isValidMeld([j, ...tb.tiles])) {
            out.add(BotPlay([swap, BotStep.moveTile(j, toSetTile: tb.tiles.first, index: 0)]));
          }
        }
        final rest = [...rack]..remove(t);
        for (final m in candidateMelds([...rest, j])) {
          if (m.length == 3 && m.contains(j) && m.where(isJoker).length == 1) {
            out.add(BotPlay([swap, BotStep.newSet(m)]));
          }
        }
      }
    }
  }
  // Keep only plays that really end valid (and use each rack tile once).
  return out.where((p) {
    final tiles = <int>[
      for (final s in p.steps)
        if (s.fromRack) ...(s.isNewSet ? s.tiles : [s.tile!]),
    ];
    if (tiles.toSet().length != tiles.length) return false;
    final end = applyBotPlay(board, p);
    // Every table tile (reclaimed jokers included) must be back on the board.
    if (!end.allTiles.toSet().containsAll(board.allTiles)) return false;
    return end.isValid;
  }).toList();
}

/// Applies every step of [play].
Board applyBotPlay(Board board, BotPlay play) {
  var b = board;
  for (final st in play.steps) {
    b = applyBotStep(b, st);
  }
  return b;
}

/// Better plays first: more rack tiles, then fewer moves, then more points.
int _comparePlays(BotPlay a, BotPlay b) {
  if (a.tileCount != b.tileCount) return b.tileCount - a.tileCount;
  if (a.moveCount != b.moveCount) return a.moveCount - b.moveCount;
  int pts(BotPlay p) => p.steps.where((s) => s.isNewSet).fold(0, (n, s) => n + meldPoints(s.tiles));
  return pts(b) - pts(a);
}

/// Plans a bot's turn from what it can see. Plays are found, then (one at a time, re-found
/// after each since the board changes) made or overlooked:
///  * a play whose moves would go over the move cap ([BotTuning.moveCap]) can't be started;
///  * each play found is overlooked with [BotTuning.missChance], decided once per turn;
///  * but overlooking never leaves the bot under min(plays available, [BotTuning.minPlays]).
/// Before its first meld a bot may only put down sets from its rack, as one play that
/// reaches the minimum.
BotPlan planTurn({
  required Board board,
  required List<int> rack,
  required bool melded,
  required int firstMeld,
  required BotLevel level,
  required math.Random rng,
  // Tests can override the level's move cap.
  int? moveCap,
}) {
  final cap = moveCap ?? BotTuning.moveCap[level];
  final miss = BotTuning.missChance[level]!;
  final floor = BotTuning.minPlays[level]!;
  bool overlook() => miss > 0 && rng.nextDouble() < miss;

  if (!melded && firstMeld > 0) {
    // The first meld is one play: rack sets only, together reaching the minimum, each set one move.
    final all = candidateMelds(rack);
    final seen = all.where((_) => !overlook()).toList();
    var combo = bestCombination(seen, minPoints: firstMeld, cap: null);
    if (combo.isEmpty) combo = bestCombination(all, minPoints: firstMeld); // the floor: at least 1 play
    if (cap != null && combo.length > cap) {
      // Too many moves: keep the biggest sets that still reach the minimum within the cap.
      combo.sort((a, b) => meldPoints(b) - meldPoints(a));
      combo = combo.take(cap).toList();
      if (combo.fold(0, (n, m) => n + meldPoints(m)) < firstMeld) combo = [];
    }
    if (combo.isEmpty) return const BotPlan([]);
    return BotPlan([
      BotPlay([for (final m in combo) BotStep.newSet(m)]),
    ]);
  }

  var b = board;
  final hand = List.of(rack);
  final plays = <BotPlay>[];
  var movesLeft = cap;
  final overlooked = <String>{};
  final decided = <String>{};
  while (true) {
    final found = findPlays(b, hand).where((p) => movesLeft == null || p.moveCount <= movesLeft).toList()..sort(_comparePlays);
    if (found.isEmpty) break;
    for (final p in found) {
      final sig = p.signature;
      if (decided.add(sig) && overlook()) overlooked.add(sig);
    }
    var pick = found.where((p) => !overlooked.contains(p.signature)).firstOrNull;
    if (pick == null) {
      if (plays.length >= floor) break;
      pick = found.first; // the floor: still make this play
    }
    plays.add(pick);
    b = applyBotPlay(b, pick);
    hand.removeWhere(pick.rackTiles.contains);
    if (movesLeft != null) movesLeft -= pick.moveCount;
  }
  return BotPlan(plays);
}

/// Applies one step of a plan to a board, the way a human would drop it.
Board applyBotStep(Board board, BotStep step) {
  switch (step.type) {
    case BotStepType.newSet:
      final spot = Layout.findSpotForNewSet(board, step.tiles.length);
      return Layout.place(spot.board, step.tiles, spot.row, spot.col, merge: false);
    case BotStepType.extend:
      final blk = board.blockOf(step.targetSetTile!)!;
      return Layout.insertInto(board, [step.tile!], step.targetSetTile!, step.atEnd ? blk.length : 0);
    case BotStepType.tileAt:
      return Layout.place(board, [step.tile!], step.row!, step.col!);
    case BotStepType.moveTile:
      if (step.targetSetTile == null) return _alone(board, [step.tile!]);
      return Layout.insertInto(board, [step.tile!], step.targetSetTile!, step.index ?? 0);
    case BotStepType.moveSet:
      final set = board.blockOf(step.tile!)!.tiles;
      if (step.targetSetTile == null) return _alone(board, set);
      final tmp = board.copy()..removeTiles(set);
      final target = tmp.blockOf(step.targetSetTile!)!;
      return Layout.insertInto(tmp, set, step.targetSetTile!, step.atEnd ? target.length : 0);
    case BotStepType.split:
      return Layout.split(board, step.tile!);
    case BotStepType.removeTile:
      return _alone(board, [step.tile!]);
    case BotStepType.swapJoker:
      return Layout.swapJoker(board, step.tile!, step.targetSetTile!) ?? board;
  }
}

/// Takes [tiles] off the board and sets them down together in the first free spot.
Board _alone(Board board, List<int> tiles) {
  final tmp = board.copy()..removeTiles(tiles);
  final spot = Layout.findSpotForNewSet(tmp, tiles.length);
  return Layout.place(spot.board, tiles, spot.row, spot.col, merge: false);
}

/// The pause that follows a step.
int stepPauseMs(BotStep step) => switch (step.kind) {
  BotActionKind.newSet => BotTuning.newSetMs,
  BotActionKind.splitOrSetMove => BotTuning.splitOrSetMoveMs,
  BotActionKind.singleTile => BotTuning.singleTileMs,
};

/// True when every step of [play], applied to [board], leaves a valid table.
bool playStaysValid(Board board, BotPlay play) {
  var b = board;
  final tableTiles = board.allTiles.toSet();
  for (final st in play.steps) {
    b = applyBotStep(b, st);
    // A reclaimed joker still in hand can't be committed either.
    if (!b.isValid || !b.allTiles.toSet().containsAll(tableTiles)) return false;
  }
  return true;
}

/// Drives the bot seats of a [GameHost]: waits, plays tiles one at a time
/// as previews, then commits (or draws).
class BotDriver {
  final GameHost host;
  final math.Random rng;
  final double speed;

  /// Tests can replace the planner to run a scripted turn.
  final BotPlan Function(GameHost host, PlayerInfo bot)? planOverride;
  StreamSubscription<void>? _sub;
  int _handledTurn = -1;
  bool _paused = false;
  bool _disposed = false;

  BotDriver(this.host, {int? seed, this.speed = 1.0, this.planOverride}) : rng = math.Random(seed) {
    _sub = host.changes.listen((_) => _check());
  }

  void start() => _check();

  set paused(bool p) {
    _paused = p;
    if (!p) _check();
  }

  void _check() {
    if (_disposed || _paused || host.result != null) return;
    final p = host.currentPlayer;
    if (p.kind != SeatKind.bot || _handledTurn == host.turnSeq) return;
    _handledTurn = host.turnSeq;
    final seq = host.turnSeq;
    // Run outside the host's change notification (it's a sync stream).
    Timer.run(() => _play(p, seq));
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: (ms / speed).round()));

  /// The turn this driver started is over (timeout, round end, or quit):
  /// stop at once and touch nothing.
  bool _stale(int seq) => _disposed || host.turnSeq != seq || host.result != null;

  Future<void> _waitWhilePaused(int seq) async {
    while (_paused && !_stale(seq)) {
      await _wait(200);
    }
  }

  Future<void> _play(PlayerInfo p, int seq) async {
    if (_stale(seq)) return;
    // Decide the whole turn at once: no thinking delay.
    final plan =
        planOverride?.call(host, p) ??
        planTurn(
          board: host.board,
          rack: host.racks[p.id]!,
          melded: host.melded.contains(p.id),
          firstMeld: host.rules.firstMeld,
          level: p.level,
          rng: rng,
        );
    // Take no action for a moment at the start of the turn (counts against the turn clock).
    await _wait(BotTuning.turnStartMs);
    await _waitWhilePaused(seq);
    if (_stale(seq)) return;
    if (plan.draws) {
      host.handle(p.id, const DrawAction());
      return;
    }
    final start = host.board.copy();
    var b = start;
    for (final play in plan.plays) {
      await _waitWhilePaused(seq);
      if (_stale(seq)) return;
      // Short on time with a valid table: only start plays that keep it
      // valid at every step; otherwise end the turn now.
      final left = host.msLeft;
      if (left != null && left < BotTuning.safeZoneMs && b.isValid && !playStaysValid(b, play)) break;
      for (final step in play.steps) {
        await _waitWhilePaused(seq);
        if (_stale(seq)) return;
        b = applyBotStep(b, step);
        host.handle(p.id, PreviewAction(b));
        await _wait(stepPauseMs(step));
        if (_stale(seq)) return;
      }
    }
    if (_stale(seq)) return;
    final played = b.allTiles.length > start.allTiles.length;
    if (played && host.handle(p.id, CommitAction(b)).ok) return;
    if (_stale(seq)) return;
    host.handle(p.id, const DrawAction());
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }
}
