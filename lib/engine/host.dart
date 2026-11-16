import 'dart:async';
import 'dart:math' as math;

import 'board.dart';
import 'meld.dart';
import 'rules.dart';
import 'tiles.dart';

enum SeatKind { human, bot, remote }

enum BotLevel { easy, medium, hard }

class PlayerInfo {
  final String id;
  final String name;
  final SeatKind kind;
  final BotLevel level;
  const PlayerInfo(this.id, this.name, this.kind, {this.level = BotLevel.medium});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'level': level.name};
  factory PlayerInfo.fromJson(Map<String, dynamic> j) => PlayerInfo(
        j['id'] as String,
        j['name'] as String,
        SeatKind.values.byName(j['kind'] as String),
        level: BotLevel.values.byName(j['level'] as String? ?? 'medium'),
      );
}

/// Things a player can ask the host to do.
sealed class GameAction {
  const GameAction();
  Map<String, dynamic> toJson();
  static GameAction fromJson(Map<String, dynamic> j) => switch (j['a']) {
        'preview' => PreviewAction(Board.fromJson(j['board'] as List)),
        'commit' => CommitAction(Board.fromJson(j['board'] as List)),
        'draw' => const DrawAction(),
        'ready' => const ReadyAction(),
        _ => throw FormatException('unknown action ${j['a']}'),
      };
}

/// The current player's work-in-progress board, so others can watch and so
/// the host can judge it if the timer runs out.
class PreviewAction extends GameAction {
  final Board board;
  const PreviewAction(this.board);
  @override
  Map<String, dynamic> toJson() => {'a': 'preview', 'board': board.toJson()};
}

/// End the turn with this board.
class CommitAction extends GameAction {
  final Board board;
  const CommitAction(this.board);
  @override
  Map<String, dynamic> toJson() => {'a': 'commit', 'board': board.toJson()};
}

/// Pass: reset the board and draw.
class DrawAction extends GameAction {
  const DrawAction();
  @override
  Map<String, dynamic> toJson() => {'a': 'draw'};
}

/// Pass-and-play: the next player has taken the phone; start their clock.
class ReadyAction extends GameAction {
  const ReadyAction();
  @override
  Map<String, dynamic> toJson() => {'a': 'ready'};
}

class ActionResult {
  final bool ok;
  final String? error;
  const ActionResult.ok()
      : ok = true,
        error = null;
  const ActionResult.fail(this.error) : ok = false;
}

class RoundResult {
  final String winnerId;

  /// Why the round ended: 'out' (a rack emptied) or 'pile' (no tiles left
  /// and everyone passed).
  final String reason;
  final Map<String, int> rackValues;
  final Map<String, int> roundScores;
  final Map<String, int> totals;
  final Map<String, List<int>> racks;
  const RoundResult(this.winnerId, this.reason, this.rackValues, this.roundScores, this.totals, this.racks);

  Map<String, dynamic> toJson() => {
        'winner': winnerId,
        'reason': reason,
        'rackValues': rackValues,
        'roundScores': roundScores,
        'totals': totals,
        'racks': racks,
      };
  factory RoundResult.fromJson(Map<String, dynamic> j) => RoundResult(
        j['winner'] as String,
        j['reason'] as String,
        (j['rackValues'] as Map).cast<String, int>(),
        (j['roundScores'] as Map).cast<String, int>(),
        (j['totals'] as Map).cast<String, int>(),
        {for (final e in (j['racks'] as Map).entries) e.key as String: (e.value as List).cast<int>()},
      );
}

class SeatView {
  final PlayerInfo info;

  /// Tiles shown in the face-down indicator (rack minus tiles already put on
  /// the board in the current preview).
  final int count;
  final bool melded;
  final int total;
  final bool connected;
  const SeatView(this.info, this.count, this.melded, this.total, this.connected);

  Map<String, dynamic> toJson() =>
      {'info': info.toJson(), 'count': count, 'melded': melded, 'total': total, 'connected': connected};
  factory SeatView.fromJson(Map<String, dynamic> j) => SeatView(
        PlayerInfo.fromJson((j['info'] as Map).cast<String, dynamic>()),
        j['count'] as int,
        j['melded'] as bool,
        j['total'] as int,
        j['connected'] as bool? ?? true,
      );
}

/// Everything one player is allowed to see. A guest phone only ever gets
/// its own rack.
class PlayerView {
  final String me;
  final List<SeatView> seats;
  final int current;
  final int turnSeq;
  final Board board;
  final Board turnStartBoard;
  final List<int> rack;
  final int pile;

  /// Milliseconds left on the turn clock when this view was made, or null.
  final int? msLeft;
  final bool clockRunning;
  final HouseRules rules;
  final RoundResult? result;
  final int round;

  /// Last draw, for the pile-to-rack animation: seq, player and count.
  final int drawSeq;
  final String? drawPlayer;
  final int drawCount;
  final String? notice;
  final int noticeSeq;

  const PlayerView({
    required this.me,
    required this.seats,
    required this.current,
    required this.turnSeq,
    required this.board,
    required this.turnStartBoard,
    required this.rack,
    required this.pile,
    required this.msLeft,
    required this.clockRunning,
    required this.rules,
    required this.result,
    required this.round,
    required this.drawSeq,
    required this.drawPlayer,
    required this.drawCount,
    required this.notice,
    required this.noticeSeq,
  });

  String get currentId => seats[current].info.id;
  bool get myTurn => currentId == me && result == null;
  SeatView get mySeat => seats.firstWhere((s) => s.info.id == me);

  Map<String, dynamic> toJson() => {
        'me': me,
        'seats': [for (final s in seats) s.toJson()],
        'current': current,
        'turnSeq': turnSeq,
        'board': board.toJson(),
        'turnStartBoard': turnStartBoard.toJson(),
        'rack': rack,
        'pile': pile,
        'msLeft': msLeft,
        'clockRunning': clockRunning,
        'rules': rules.toJson(),
        'result': result?.toJson(),
        'round': round,
        'drawSeq': drawSeq,
        'drawPlayer': drawPlayer,
        'drawCount': drawCount,
        'notice': notice,
        'noticeSeq': noticeSeq,
      };

  factory PlayerView.fromJson(Map<String, dynamic> j) => PlayerView(
        me: j['me'] as String,
        seats: [for (final s in j['seats'] as List) SeatView.fromJson((s as Map).cast<String, dynamic>())],
        current: j['current'] as int,
        turnSeq: j['turnSeq'] as int,
        board: Board.fromJson(j['board'] as List),
        turnStartBoard: Board.fromJson(j['turnStartBoard'] as List),
        rack: (j['rack'] as List).cast<int>(),
        pile: j['pile'] as int,
        msLeft: j['msLeft'] as int?,
        clockRunning: j['clockRunning'] as bool? ?? false,
        rules: HouseRules.fromJson((j['rules'] as Map).cast<String, dynamic>()),
        result: j['result'] == null ? null : RoundResult.fromJson((j['result'] as Map).cast<String, dynamic>()),
        round: j['round'] as int,
        drawSeq: j['drawSeq'] as int,
        drawPlayer: j['drawPlayer'] as String?,
        drawCount: j['drawCount'] as int,
        notice: j['notice'] as String?,
        noticeSeq: j['noticeSeq'] as int? ?? 0,
      );
}

/// Checks a proposed end-of-turn board. Pure function, shared by the host
/// and by the client (to show the player what's wrong before sending).
String? checkTurn({
  required Board start,
  required Board proposed,
  required List<int> rack,
  required bool melded,
  required HouseRules rules,
}) {
  final startTiles = start.allTiles;
  final newTiles = proposed.allTiles;
  if (newTiles.toSet().length != newTiles.length) return 'A tile appears twice.';
  final startSet = startTiles.toSet();
  final newSet = newTiles.toSet();
  if (!newSet.containsAll(startSet)) return 'Tiles already on the table must stay on the table.';
  final played = newSet.difference(startSet);
  final rackSet = rack.toSet();
  if (!rackSet.containsAll(played)) return 'Those tiles are not in your rack.';
  if (played.isEmpty) return 'Play at least one tile, or draw.';
  final bad = proposed.invalidBlocks;
  if (bad.isNotEmpty) {
    return bad.length == 1 ? 'One set on the table is not a valid run or group.' : '${bad.length} sets on the table are not valid.';
  }
  if (!melded && rules.firstMeld > 0) {
    final startSets = start.sets.map((s) => s.join(',')).toList();
    final newSets = proposed.sets.map((s) => s.join(',')).toList();
    final remaining = List<String>.of(newSets);
    for (final s in startSets) {
      if (!remaining.remove(s)) return 'Before your first meld you can\'t change sets already on the table.';
    }
    var points = 0;
    for (final s in proposed.sets) {
      final key = s.join(',');
      if (remaining.remove(key)) {
        if (!s.every(played.contains)) return 'Your first meld must use only tiles from your rack.';
        points += meldPoints(s);
      }
    }
    if (points < rules.firstMeld) return 'Your first meld needs ${rules.firstMeld} points (you have $points).';
  }
  return null;
}

/// The authoritative game. Runs on the host's phone (or in-process for
/// Practice and Pass-and-play). Every move goes through [handle].
class GameHost {
  final List<PlayerInfo> players;
  HouseRules rules;
  final TestTools test;
  final bool waitForReady;
  final math.Random _rng;

  final Map<String, List<int>> racks = {};
  final Set<String> melded = {};
  final Map<String, int> totals = {};
  final Set<String> disconnected = {};
  List<int> pile = [];
  Board board = Board.empty();
  Board turnStart = Board.empty();
  Board? preview;
  int current = 0;
  int turnSeq = 0;
  int round = 0;
  int _passesWithEmptyPile = 0;
  RoundResult? result;
  int drawSeq = 0;
  String? drawPlayer;
  int drawCount = 0;
  String? notice;
  int noticeSeq = 0;

  DateTime? _deadline;
  Timer? _timer;
  int? _pausedMsLeft;
  final _changes = StreamController<void>.broadcast(sync: true);

  GameHost({
    required this.players,
    required this.rules,
    this.test = TestTools.off,
    this.waitForReady = false,
    int? seed,
  }) : _rng = math.Random(seed ?? (test.enabled ? test.seed : null) ?? DateTime.now().microsecondsSinceEpoch) {
    for (final p in players) {
      totals[p.id] = 0;
    }
  }

  Stream<void> get changes => _changes.stream;
  PlayerInfo get currentPlayer => players[current];

  int get turnSeconds => test.enabled && test.timerOverride != null ? test.timerOverride! : rules.turnSeconds;

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Deals a new round. The first player rotates each round.
  void startRound() {
    round++;
    result = null;
    melded.clear();
    _passesWithEmptyPile = 0;
    board = Board.empty();
    final tiles = fullSet(rules.jokers)..shuffle(_rng);
    if (test.enabled && test.giveJoker && rules.jokers > 0) {
      final human = players.indexWhere((p) => p.kind == SeatKind.human);
      final ji = tiles.indexWhere(isJoker);
      final slot = math.max(0, human) * rules.handSize;
      if (ji >= 0 && slot < tiles.length) {
        final t = tiles[slot];
        tiles[slot] = tiles[ji];
        tiles[ji] = t;
      }
    }
    var k = 0;
    for (final p in players) {
      racks[p.id] = tiles.sublist(k, k + rules.handSize);
      k += rules.handSize;
    }
    pile = tiles.sublist(k);
    if (test.enabled && test.pileLimit != null && test.pileLimit! < pile.length) {
      pile = pile.sublist(0, test.pileLimit!);
    }
    current = (round - 1) % players.length;
    _beginTurn();
  }

  void _beginTurn() {
    turnSeq++;
    turnStart = board.copy();
    preview = null;
    _timer?.cancel();
    _deadline = null;
    if (!waitForReady || currentPlayer.kind != SeatKind.human) _startClock();
    _emit();
  }

  void _startClock() {
    _timer?.cancel();
    if (turnSeconds <= 0) return;
    _deadline = DateTime.now().add(Duration(seconds: turnSeconds));
    final seq = turnSeq;
    _timer = Timer(Duration(seconds: turnSeconds), () {
      if (seq == turnSeq && result == null) timeout();
    });
  }

  /// Pauses the turn clock (practice and pass-and-play menus).
  void pauseClock() {
    if (_deadline == null || _timer == null) return;
    _pausedMsLeft = _deadline!.difference(DateTime.now()).inMilliseconds;
    _timer?.cancel();
    _timer = null;
    _emit();
  }

  void resumeClock() {
    final left = _pausedMsLeft;
    if (left == null) return;
    _pausedMsLeft = null;
    _deadline = DateTime.now().add(Duration(milliseconds: left));
    final seq = turnSeq;
    _timer = Timer(Duration(milliseconds: math.max(0, left)), () {
      if (seq == turnSeq && result == null) timeout();
    });
    _emit();
  }

  void dispose() {
    _timer?.cancel();
    _changes.close();
  }

  /// Time ran out: a valid board ends the turn normally; otherwise the
  /// board resets, attempted tiles return, and the player draws as if
  /// passing.
  void timeout() {
    final p = currentPlayer.id;
    final pv = preview;
    if (pv != null) {
      final err = checkTurn(start: turnStart, proposed: pv, rack: racks[p]!, melded: melded.contains(p), rules: rules);
      if (err == null) {
        _commit(p, pv);
        return;
      }
    }
    _note('${currentPlayer.name} ran out of time.');
    _draw(p);
  }

  void _note(String s) {
    notice = s;
    noticeSeq++;
  }

  ActionResult handle(String playerId, GameAction a) {
    if (result != null) return const ActionResult.fail('The round is over.');
    if (playerId != currentPlayer.id) return const ActionResult.fail('It is not your turn.');
    switch (a) {
      case PreviewAction(:final board):
        // Only accept previews that keep table tiles and use the player's rack.
        final tiles = board.allTiles.toSet();
        if (!tiles.containsAll(turnStart.allTiles)) return const ActionResult.fail('bad preview');
        final rack = racks[playerId]!.toSet();
        final startSet = turnStart.allTiles.toSet();
        if (!tiles.every((t) => startSet.contains(t) || rack.contains(t))) return const ActionResult.fail('bad preview');
        preview = board.copy();
        _emit();
        return const ActionResult.ok();
      case CommitAction(:final board):
        final err = checkTurn(
            start: turnStart, proposed: board, rack: racks[playerId]!, melded: melded.contains(playerId), rules: rules);
        if (err != null) return ActionResult.fail(err);
        _commit(playerId, board);
        return const ActionResult.ok();
      case DrawAction():
        _draw(playerId);
        return const ActionResult.ok();
      case ReadyAction():
        if (_deadline == null) _startClock();
        _emit();
        return const ActionResult.ok();
    }
  }

  void _commit(String p, Board proposed) {
    final played = proposed.allTiles.toSet().difference(turnStart.allTiles.toSet());
    racks[p]!.removeWhere(played.contains);
    board = proposed.copy()..trim();
    melded.add(p);
    _passesWithEmptyPile = 0;
    if (racks[p]!.isEmpty) {
      _endRound(p, 'out');
      return;
    }
    _next();
  }

  void _draw(String p) {
    board = turnStart.copy();
    final n = math.min(rules.passDraw, pile.length);
    if (n > 0) {
      racks[p]!.addAll(pile.sublist(0, n));
      pile = pile.sublist(n);
      drawSeq++;
      drawPlayer = p;
      drawCount = n;
      _passesWithEmptyPile = 0;
    } else {
      _passesWithEmptyPile++;
      if (_passesWithEmptyPile >= players.length) {
        // Nobody can draw and everyone has passed: lowest rack wins.
        String best = players.first.id;
        for (final pl in players) {
          if (_rackValue(pl.id) < _rackValue(best)) best = pl.id;
        }
        _endRound(best, 'pile');
        return;
      }
    }
    _next();
  }

  int _rackValue(String id) => racks[id]!.fold(0, (s, t) => s + tilePenalty(t));

  void _next() {
    current = (current + 1) % players.length;
    _beginTurn();
  }

  /// Scoring: each other player loses the value of the tiles left in their
  /// rack (jokers 30) and the winner gains the sum. When the pile ran out,
  /// the winner (lowest rack) gains the others' values minus their own.
  void _endRound(String winner, String reason) {
    _timer?.cancel();
    _deadline = null;
    final values = {for (final p in players) p.id: _rackValue(p.id)};
    final scores = <String, int>{};
    var gain = 0;
    for (final p in players) {
      if (p.id == winner) continue;
      final v = reason == 'pile' ? values[p.id]! - values[winner]! : values[p.id]!;
      scores[p.id] = -v;
      gain += v;
    }
    scores[winner] = gain;
    for (final e in scores.entries) {
      totals[e.key] = (totals[e.key] ?? 0) + e.value;
    }
    result = RoundResult(winner, reason, values, scores, Map.of(totals),
        {for (final p in players) p.id: List.of(racks[p.id]!)});
    turnSeq++;
    _emit();
  }

  // --- test tools (practice / pass-and-play only) -------------------------

  /// Empties the player's rack and ends the round with them as winner.
  void debugWin(String p) {
    if (result != null) return;
    racks[p]!.clear();
    board = turnStart.copy();
    _endRound(p, 'out');
  }

  /// Moves [n] tiles from the pile to the player's rack immediately.
  void debugDraw(String p, int n) {
    final k = math.min(n, pile.length);
    if (k == 0) return;
    racks[p]!.addAll(pile.sublist(0, k));
    pile = pile.sublist(k);
    drawSeq++;
    drawPlayer = p;
    drawCount = k;
    _emit();
  }

  /// Swaps a rack tile for a joker from the pile (if one is left there).
  void debugGiveJoker(String p) {
    final ji = pile.indexWhere(isJoker);
    if (ji < 0 || racks[p]!.isEmpty) return;
    final j = pile[ji];
    pile[ji] = racks[p]!.removeLast();
    racks[p]!.add(j);
    _emit();
  }

  /// Empties the pile.
  void debugEmptyPile() {
    pile = [];
    _emit();
  }

  /// Ends the clock in 3 seconds.
  void debugShortClock() {
    final seq = turnSeq;
    _timer?.cancel();
    _deadline = DateTime.now().add(const Duration(seconds: 3));
    _timer = Timer(const Duration(seconds: 3), () {
      if (seq == turnSeq && result == null) timeout();
    });
    _emit();
  }

  void setConnected(String id, bool c) {
    if (c) {
      disconnected.remove(id);
    } else {
      disconnected.add(id);
    }
    _emit();
  }

  PlayerView viewFor(String me) {
    final shown = preview ?? board;
    final previewTiles = preview == null ? <int>{} : preview!.allTiles.toSet().difference(turnStart.allTiles.toSet());
    int? msLeft;
    if (_pausedMsLeft != null) {
      msLeft = _pausedMsLeft;
    } else if (_deadline != null) {
      msLeft = math.max(0, _deadline!.difference(DateTime.now()).inMilliseconds);
    }
    return PlayerView(
      me: me,
      seats: [
        for (final p in players)
          SeatView(
            p,
            racks[p.id]!.length - (p.id == currentPlayer.id ? previewTiles.length : 0),
            melded.contains(p.id),
            totals[p.id] ?? 0,
            !disconnected.contains(p.id),
          ),
      ],
      current: current,
      turnSeq: turnSeq,
      board: me == currentPlayer.id ? board : shown,
      turnStartBoard: turnStart,
      rack: List.of(racks[me] ?? const []),
      pile: pile.length,
      msLeft: msLeft,
      clockRunning: _timer != null && _deadline != null,
      rules: rules,
      result: result,
      round: round,
      drawSeq: drawSeq,
      drawPlayer: drawPlayer,
      drawCount: drawCount,
      notice: notice,
      noticeSeq: noticeSeq,
    );
  }
}
