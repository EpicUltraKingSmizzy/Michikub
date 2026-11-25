import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/board.dart';
import '../engine/host.dart';
import '../engine/meld.dart';
import '../engine/puzzle.dart';
import '../engine/rules.dart';
import '../engine/tiles.dart';
import 'prefs.dart';
import 'session.dart';

/// The prepackaged puzzles (assets/puzzles/puzzles.json, made by tool/gen_puzzles.dart).
class PuzzlePack {
  final Map<PuzzleLevel, List<Puzzle>> levels;
  const PuzzlePack(this.levels);

  static PuzzlePack? _loaded;

  /// Tests: use this pack instead of the asset.
  @visibleForTesting
  static set debugPack(PuzzlePack? p) => _loaded = p;

  static Future<PuzzlePack> load() async {
    if (_loaded != null) return _loaded!;
    final text = await rootBundle.loadString('assets/puzzles/puzzles.json');
    return _loaded = parse(text);
  }

  static PuzzlePack parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return PuzzlePack({
      for (final l in PuzzleLevel.values)
        l: [for (final p in (j[l.name] as List? ?? const [])) Puzzle.fromJson((p as Map).cast<String, dynamic>())],
    });
  }

  int count(PuzzleLevel l) => levels[l]?.length ?? 0;
}

/// Which puzzles this phone has solved, per difficulty (saved on the phone). Endless puzzles
/// (made on the phone after the star) are kept so they can be replayed from the list.
class PuzzleProgress extends ChangeNotifier {
  static final PuzzleProgress instance = PuzzleProgress();
  static const _key = 'puzzleProgress';
  static const maxEndlessKept = 500;

  final Map<PuzzleLevel, Set<int>> solved = {for (final l in PuzzleLevel.values) l: <int>{}};
  final Map<PuzzleLevel, List<Puzzle>> endless = {for (final l in PuzzleLevel.values) l: <Puzzle>[]};

  /// Endless numbers continue after the pack (#401, #402 ...): how many have been solved.
  final Map<PuzzleLevel, int> endlessSolved = {for (final l in PuzzleLevel.values) l: 0};

  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final s = _p!.getString(_key);
    if (s == null) return;
    try {
      fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {}
    notifyListeners();
  }

  void fromJson(Map<String, dynamic> j) {
    for (final l in PuzzleLevel.values) {
      final m = (j[l.name] as Map?)?.cast<String, dynamic>();
      if (m == null) continue;
      solved[l] = {for (final i in (m['solved'] as List? ?? const [])) i as int};
      endless[l] = [for (final p in (m['endless'] as List? ?? const [])) Puzzle.fromJson((p as Map).cast<String, dynamic>())];
      endlessSolved[l] = m['endlessSolved'] as int? ?? endless[l]!.length;
    }
  }

  Map<String, dynamic> toJson() => {
        for (final l in PuzzleLevel.values)
          l.name: {
            'solved': (solved[l]!.toList()..sort()),
            'endless': [for (final p in endless[l]!) p.toJson()],
            'endlessSolved': endlessSolved[l],
          },
      };

  Future<void> save() async {
    notifyListeners();
    await _p?.setString(_key, jsonEncode(toJson()));
  }

  bool complete(PuzzleLevel l, int total) => total > 0 && solved[l]!.length >= total;

  /// The lowest puzzle not solved yet, or null when every one is (endless from then on).
  int? nextUnsolved(PuzzleLevel l, int total) {
    for (var i = 0; i < total; i++) {
      if (!solved[l]!.contains(i)) return i;
    }
    return null;
  }

  @visibleForTesting
  void reset() {
    for (final l in PuzzleLevel.values) {
      solved[l]!.clear();
      endless[l]!.clear();
      endlessSolved[l] = 0;
    }
  }
}

/// One entry in the "beaten puzzles" list: its number and how to open it again.
class BeatenPuzzle {
  final int number;
  final int? packIndex;
  final int? endlessIndex;
  const BeatenPuzzle(this.number, {this.packIndex, this.endlessIndex});
}

enum PuzzlePhase { playing, solved, clearing }

/// A puzzle at the table: one seat (you), no pile to draw from, no clock, no opponents. The
/// table and rack come from the puzzle; it's solved when every rack tile is on a valid table.
class PuzzleSession extends GameSession {
  final PuzzleLevel level;
  final PuzzlePack pack;
  final PuzzleProgress progress;
  final math.Random _rng;

  late Puzzle puzzle;

  /// Shown as #number: pack puzzles are 1..400, endless ones carry on from there.
  late int number;
  int? _packIndex;
  int? _endlessIndex;
  PuzzlePhase phase = PuzzlePhase.playing;

  int _round = 0;
  int _turnSeq = 0;
  late Board _start;
  Board _board = Board.empty();
  List<int> _rack = [];
  PlayerView? _view;

  /// Endless mode couldn't make a puzzle (shouldn't happen; shown as a message).
  String? error;

  PuzzleSession({required this.level, required this.pack, PuzzleProgress? progress, int? openIndex, math.Random? rng})
      : progress = progress ?? PuzzleProgress.instance,
        _rng = rng ?? math.Random() {
    if (openIndex != null) {
      _openPack(openIndex);
    } else {
      _openNext();
    }
  }

  static const me = 'you';

  int get total => pack.count(level);
  bool get isEndless => _packIndex == null;

  /// Puzzles beaten in this difficulty, in number order (the list behind the # button).
  List<BeatenPuzzle> get beaten => [
        for (final i in (progress.solved[level]!.toList()..sort())) BeatenPuzzle(i + 1, packIndex: i),
        for (var k = 0; k < progress.endless[level]!.length; k++) BeatenPuzzle(total + k + 1, endlessIndex: k),
      ];

  void _openNext() {
    final i = progress.nextUnsolved(level, total);
    if (i != null) {
      _openPack(i);
      return;
    }
    // Star earned: a new puzzle made here, by the same rules.
    final p = generateOne(level, rng: _rng);
    if (p == null) {
      error = 'Couldn\'t make a new puzzle. Try again.';
      // Fall back to a random pack puzzle so the table isn't empty.
      _openPack(_rng.nextInt(math.max(1, total)));
      return;
    }
    _packIndex = null;
    _endlessIndex = null;
    number = total + progress.endlessSolved[level]! + 1;
    _load(p);
  }

  void _openPack(int i) {
    _packIndex = i;
    _endlessIndex = null;
    number = i + 1;
    _load(pack.levels[level]![i]);
  }

  void _openEndless(int k) {
    _packIndex = null;
    _endlessIndex = k;
    number = total + k + 1;
    _load(progress.endless[level]![k]);
  }

  /// Replays a beaten puzzle from the list.
  void open(BeatenPuzzle b) {
    if (b.packIndex != null) {
      _openPack(b.packIndex!);
    } else if (b.endlessIndex != null) {
      _openEndless(b.endlessIndex!);
    }
    _refresh();
  }

  void _load(Puzzle p) {
    puzzle = p;
    phase = PuzzlePhase.playing;
    _round++;
    _turnSeq++;
    _start = layoutPuzzleBoard(p.board);
    _board = _start.copy();
    _rack = List.of(p.rack);
  }

  void _refresh() {
    _view = PlayerView(
      me: me,
      seats: [SeatView(PlayerInfo(me, AppPrefs.instance.name, SeatKind.human, avatar: AppPrefs.instance.avatar), _rack.length, true, 0, true)],
      current: 0,
      turnSeq: _turnSeq,
      board: _board,
      turnStartBoard: _start,
      rack: List.of(_rack),
      pile: 106,
      msLeft: null,
      clockRunning: false,
      rules: const HouseRules(firstMeld: 0, turnSeconds: 0),
      result: null,
      round: _round,
      drawSeq: 0,
      drawPlayer: null,
      drawCount: 0,
      notice: null,
      noticeSeq: 0,
    );
    notifyListeners();
  }

  @override
  PlayerView? get view {
    if (_view == null) _refresh();
    return _view;
  }

  @override
  bool get controlsRounds => false;

  /// Is [b] the puzzle finished: every rack tile on the table and every set valid?
  bool isSolvedBy(Board b) {
    final tiles = b.allTiles;
    final need = {..._start.allTiles, ..._rack};
    if (tiles.length != need.length || !need.containsAll(tiles)) return false;
    return b.blocks.every((x) => isValidMeld(x.tiles));
  }

  @override
  Future<ActionResult> act(GameAction a) async {
    if (phase != PuzzlePhase.playing) return const ActionResult.fail('Solved!');
    switch (a) {
      case PreviewAction(:final board):
      case CommitAction(:final board):
        if (isSolvedBy(board)) {
          _board = board.copy();
          _solved();
          return const ActionResult.ok();
        }
        if (a is CommitAction) return const ActionResult.fail('Put every rack tile on the table in valid sets.');
        return const ActionResult.ok();
      default:
        return const ActionResult.fail('Puzzles have no draws.');
    }
  }

  void _solved() {
    phase = PuzzlePhase.solved;
    if (_packIndex != null) {
      progress.solved[level]!.add(_packIndex!);
    } else if (_endlessIndex == null) {
      final list = progress.endless[level]!;
      list.add(puzzle);
      if (list.length > PuzzleProgress.maxEndlessKept) list.removeAt(0);
      progress.endlessSolved[level] = progress.endlessSolved[level]! + 1;
    }
    unawaited(progress.save());
    _refresh();
  }

  /// The tidy-up: the table and rack empty (the tiles are flying back to the deck).
  void clearTable() {
    phase = PuzzlePhase.clearing;
    _board = Board.empty();
    _rack = [];
    _turnSeq++;
    _refresh();
  }

  /// The next unsolved puzzle (dealt out with the deal animation).
  void nextPuzzle() {
    error = null;
    _openNext();
    _refresh();
  }

  @override
  void nextRound() => nextPuzzle();

  @override
  void leave() {}
}

/// Lays the puzzle's sets out on the table: rows filled left to right up to
/// [LayoutTuning.balanceWidth] columns (so tiles start large), then centred (the end-of-turn
/// tidy).
Board layoutPuzzleBoard(List<List<int>> sets) {
  final b = Board.empty();
  var row = 0, col = 0;
  for (final s in sets) {
    if (col > 0 && col + s.length > LayoutTuning.balanceWidth) {
      row++;
      col = 0;
    }
    b.ensureRows(row + 1);
    for (var i = 0; i < s.length; i++) {
      b.rows[row][col + i] = s[i];
    }
    col += s.length + 1;
  }
  return Layout.tidy(b);
}

/// Opens the right puzzle for the difficulty button (keeps the tile ids honest: pack files
/// only hold one copy of each tile and jokers 0 and 1).
bool puzzleTilesOk(Puzzle p) {
  final all = p.allTiles;
  return all.toSet().length == all.length && all.every((t) => t >= 0 && (t < kNumberedTiles || isJoker(t)));
}

String puzzleLevelName(PuzzleLevel l) => switch (l) {
      PuzzleLevel.easy => 'Easy',
      PuzzleLevel.medium => 'Medium',
      PuzzleLevel.hard => 'Hard',
    };
