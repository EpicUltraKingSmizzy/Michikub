import 'dart:async';
import 'dart:math' as math;

import 'board.dart';
import 'host.dart';
import 'meld.dart';
import 'tiles.dart';

/// Tweakable numbers for the computer players.
class BotTuning {
  /// Most tiles a bot will put down in one turn (null = no limit).
  static const Map<BotLevel, int?> tileCap = {
    BotLevel.easy: 3,
    BotLevel.medium: 6,
    BotLevel.hard: null,
  };

  /// Chance that a bot overlooks each play it found.
  static const Map<BotLevel, double> missChance = {
    BotLevel.easy: 0.40,
    BotLevel.medium: 0.15,
    BotLevel.hard: 0.0,
  };

  /// Bots decide their whole turn instantly (no thinking delay), then carry
  /// it out one action at a time. Each action is shown, then followed by
  /// its pause before the next action (or the end of the turn).
  ///
  /// A single tile moved: a rack tile extending a table set, or a tile
  /// moved on the table.
  static const int singleTileMs = 500;

  /// A split, or a whole set moved on the table.
  static const int splitOrSetMoveMs = 1000;

  /// A new set put down from the rack.
  static const int newSetMs = 2000;

  /// Search budget for picking melds.
  static const int searchNodes = 6000;
}

/// One tile (or a whole new set's worth, one tile at a time) the bot will
/// put on the table.
class BotStep {
  /// Tiles of a new set, in order (empty for an extension).
  final List<int> tiles;

  /// For an extension: the tile to add, and a tile already in the target set.
  final int? tile;
  final int? extendSetTile;
  final bool atEnd;
  const BotStep.newSet(this.tiles)
      : tile = null,
        extendSetTile = null,
        atEnd = true;
  const BotStep.extend(int this.tile, int this.extendSetTile, this.atEnd) : tiles = const [];
  bool get isNewSet => extendSetTile == null;
}

/// A planned turn: either a list of steps, or draw.
class BotPlan {
  final List<BotStep> steps;
  const BotPlan(this.steps);
  bool get draws => steps.isEmpty;
  int get tileCount => steps.fold(0, (s, x) => s + (x.isNewSet ? x.tiles.length : 1));
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
      final chosen = [for (var i = 0; i < present.length; i++) if (mask & (1 << i) != 0) present[i]];
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

/// Plans a bot's turn from what it can see.
BotPlan planTurn({
  required Board board,
  required List<int> rack,
  required bool melded,
  required int firstMeld,
  required BotLevel level,
  required math.Random rng,
}) {
  final cap = BotTuning.tileCap[level];
  final miss = BotTuning.missChance[level]!;
  var cands = candidateMelds(rack);
  // Imperfect play: overlook some of the plays it could see.
  if (miss > 0) cands = cands.where((_) => rng.nextDouble() >= miss).toList();

  final steps = <BotStep>[];
  var used = <int>{};
  var placed = 0;
  final needFirst = !melded && firstMeld > 0;
  final combo = bestCombination(cands, minPoints: needFirst ? firstMeld : 0, cap: cap);
  if (needFirst && combo.isEmpty) return const BotPlan([]);
  for (final m in combo) {
    steps.add(BotStep.newSet(m));
    used.addAll(m);
    placed += m.length;
  }
  if (needFirst) return BotPlan(steps); // can't touch the table yet

  // Extend sets already on the table, one tile at a time.
  final sets = [for (final b in board.blocks) List<int>.of(b.tiles)];
  var progress = true;
  while (progress && (cap == null || placed < cap)) {
    progress = false;
    for (final t in rack) {
      if (used.contains(t)) continue;
      if (cap != null && placed >= cap) break;
      for (final s in sets) {
        final end = [...s, t];
        final front = [t, ...s];
        bool? atEnd;
        if (isValidMeld(end)) {
          atEnd = true;
        } else if (isValidMeld(front)) {
          atEnd = false;
        }
        if (atEnd == null) continue;
        if (miss > 0 && rng.nextDouble() < miss) continue;
        steps.add(BotStep.extend(t, s.first, atEnd));
        if (atEnd) {
          s.add(t);
        } else {
          s.insert(0, t);
        }
        used.add(t);
        placed++;
        progress = true;
        break;
      }
    }
  }
  return BotPlan(steps);
}

/// Applies one step of a plan to a board, the way a human would drop it: a
/// new set goes into the first free spot; an extension joins its set's end.
Board applyBotStep(Board board, BotStep step) {
  if (step.isNewSet) {
    final spot = Layout.findSpotForNewSet(board, step.tiles.length);
    return Layout.place(spot.board, step.tiles, spot.row, spot.col, merge: false);
  }
  final blk = board.blockOf(step.extendSetTile!)!;
  return Layout.insertInto(board, [step.tile!], step.extendSetTile!, step.atEnd ? blk.length : 0);
}

/// The pause that follows a step.
int stepPauseMs(BotStep step) => step.isNewSet ? BotTuning.newSetMs : BotTuning.singleTileMs;

/// Drives the bot seats of a [GameHost]: waits, plays tiles one at a time
/// as previews, then commits (or draws).
class BotDriver {
  final GameHost host;
  final math.Random rng;
  final double speed;
  StreamSubscription<void>? _sub;
  int _handledTurn = -1;
  bool _paused = false;
  bool _disposed = false;

  BotDriver(this.host, {int? seed, this.speed = 1.0}) : rng = math.Random(seed) {
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
    _play(p, host.turnSeq);
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: (ms / speed).round()));

  Future<void> _play(PlayerInfo p, int seq) async {
    // Decide the whole turn at once: no thinking delay.
    final plan = planTurn(
      board: host.board,
      rack: host.racks[p.id]!,
      melded: host.melded.contains(p.id),
      firstMeld: host.rules.firstMeld,
      level: p.level,
      rng: rng,
    );
    if (plan.draws) {
      host.handle(p.id, const DrawAction());
      return;
    }
    var b = host.board.copy();
    for (final step in plan.steps) {
      while (_paused && !_disposed) {
        await _wait(300);
      }
      if (_disposed || host.turnSeq != seq) return;
      b = applyBotStep(b, step);
      host.handle(p.id, PreviewAction(b));
      await _wait(stepPauseMs(step));
    }
    if (_disposed || host.turnSeq != seq) return;
    final r = host.handle(p.id, CommitAction(b));
    if (!r.ok) host.handle(p.id, const DrawAction());
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }
}
