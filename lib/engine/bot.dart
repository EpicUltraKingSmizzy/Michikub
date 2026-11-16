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

  /// With less than this much turn time left (and a valid board), a bot
  /// only starts moves whose every step keeps the board valid; otherwise it
  /// ends its turn.
  static const int safeZoneMs = 5000;

  /// Search budget for picking melds.
  static const int searchNodes = 6000;
}

enum BotActionKind { singleTile, splitOrSetMove, newSet }

/// One visible action: a new set from the rack, a rack tile extending a
/// set, or a single tile put at a spot on the table.
class BotStep {
  /// Tiles of a new set, in order (empty otherwise).
  final List<int> tiles;

  /// The tile moved (extension or tileAt).
  final int? tile;

  /// For an extension: a tile already in the target set.
  final int? extendSetTile;
  final bool atEnd;

  /// For tileAt: where the tile goes.
  final int? row, col;

  const BotStep.newSet(this.tiles)
      : tile = null,
        extendSetTile = null,
        atEnd = true,
        row = null,
        col = null;
  const BotStep.extend(int this.tile, int this.extendSetTile, this.atEnd)
      : tiles = const [],
        row = null,
        col = null;
  const BotStep.tileAt(int this.tile, int this.row, int this.col)
      : tiles = const [],
        extendSetTile = null,
        atEnd = true;

  bool get isNewSet => tiles.isNotEmpty;
  bool get isExtension => extendSetTile != null;
  BotActionKind get kind => isNewSet ? BotActionKind.newSet : BotActionKind.singleTile;
  int get tileCount => isNewSet ? tiles.length : 1;
}

/// A group of steps that, taken together, ends with a valid table. Steps
/// inside a move may pass through invalid states (for example building a
/// set one tile at a time); the table is only promised valid between moves.
class BotMove {
  final List<BotStep> steps;
  const BotMove(this.steps);
  int get tileCount => steps.fold(0, (s, x) => s + x.tileCount);
}

/// A planned turn: a list of moves, or (if empty) draw.
class BotPlan {
  final List<BotMove> moves;
  const BotPlan(this.moves);
  factory BotPlan.ofSteps(List<BotStep> steps) => BotPlan([for (final s in steps) BotMove([s])]);
  bool get draws => moves.isEmpty;
  List<BotStep> get steps => [for (final m in moves) ...m.steps];
  int get tileCount => moves.fold(0, (s, x) => s + x.tileCount);
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
  if (needFirst) return BotPlan.ofSteps(steps); // can't touch the table yet

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
  return BotPlan.ofSteps(steps);
}

/// Applies one step of a plan to a board, the way a human would drop it: a
/// new set goes into the first free spot; an extension joins its set's end.
Board applyBotStep(Board board, BotStep step) {
  if (step.isNewSet) {
    final spot = Layout.findSpotForNewSet(board, step.tiles.length);
    return Layout.place(spot.board, step.tiles, spot.row, spot.col, merge: false);
  }
  if (step.isExtension) {
    final blk = board.blockOf(step.extendSetTile!)!;
    return Layout.insertInto(board, [step.tile!], step.extendSetTile!, step.atEnd ? blk.length : 0);
  }
  return Layout.place(board, [step.tile!], step.row!, step.col!);
}

/// The pause that follows a step.
int stepPauseMs(BotStep step) => switch (step.kind) {
      BotActionKind.newSet => BotTuning.newSetMs,
      BotActionKind.splitOrSetMove => BotTuning.splitOrSetMoveMs,
      BotActionKind.singleTile => BotTuning.singleTileMs,
    };

/// True when every step of [move], applied to [board], leaves a valid table.
bool moveStaysValid(Board board, BotMove move) {
  var b = board;
  for (final st in move.steps) {
    b = applyBotStep(b, st);
    if (!b.isValid) return false;
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
    final plan = planOverride?.call(host, p) ??
        planTurn(
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
    final start = host.board.copy();
    var b = start;
    for (final move in plan.moves) {
      await _waitWhilePaused(seq);
      if (_stale(seq)) return;
      // Short on time with a valid table: only start moves that keep it
      // valid at every step; otherwise end the turn now.
      final left = host.msLeft;
      if (left != null && left < BotTuning.safeZoneMs && b.isValid && !moveStaysValid(b, move)) break;
      for (final step in move.steps) {
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
