import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/bot_roster.dart';
import '../app/prefs.dart';
import '../app/session.dart';
import '../engine/board.dart';
import '../engine/host.dart';
import '../engine/meld.dart';
import '../engine/rack_sort.dart';
import '../engine/tiles.dart';
import 'avatar.dart';
import 'results.dart';
import 'table_geo.dart';
import 'theme.dart';
import 'tiles_view.dart';

/// Tunable feel constants for the table.
class TableTuning {
  static const moveMs = 240;
  static const flyMs = 1100;

  /// How long the white "new on the table" glow takes to fade in or out.
  static const newGlowFadeMs = 700;
  static const flashMs = 650;
  static const shineMs = 750;
  static const toastMs = 2600;

  /// How long the "`Name` starts" banner shows at the start of each round.
  static const starterBannerMs = 2200;

}

enum _Src { pile, seat }

class _Spawn {
  final _Src src;
  final String? seat;
  const _Spawn(this.src, [this.seat]);
}

class _Drag {
  final List<int> tiles;
  Offset grab; // pointer minus top-left of the first tile, in tile units
  Offset pointer;
  final Offset start;
  _Drag(this.tiles, this.grab, this.pointer) : start = pointer;
  bool get moved => (pointer - start).distance > 6;
}

/// A face-down tile flying from the pile to an opponent's face-down rack ([who]).
class _BackFlight {
  final Key key = UniqueKey();
  final String who;
  final Rect from, to;
  _BackFlight(this.who, this.from, this.to);
}

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameSession get s => widget.session;
  final prefs = AppPrefs.instance;
  final _stackKey = GlobalKey();

  PlayerView? v;
  int _turnSeq = -1;
  Board working = Board.empty();
  final List<Board> _history = [];
  final Map<String, List<int>> _rackOrders = {};

  /// My rack order (with gaps) when my turn started, for Reset.
  List<int> _turnStartOrder = const [];
  final Set<int> _selected = {};
  /// The selection came from a long-press that was released without moving (several tiles,
  /// or a whole board set): tap a spot or a set to move it there.
  bool _groupSel = false;
  bool _longPressing = false;
  final Set<int> _flash = {};
  final Set<int> _shine = {};
  final Map<int, _Spawn> _spawns = {};
  final List<_BackFlight> _flights = [];
  _Drag? _drag;
  int _drawSeq = -1, _noticeSeq = -1;
  String? _toast;

  /// The "`Name` starts" banner text, shown briefly when a round begins.
  String? _starterBanner;
  int _bannerRound = 0;
  Timer? _bannerTimer;
  Timer? _toastTimer, _ticker;
  DateTime? _deadline;
  bool _clockRunning = false;
  bool _menuOpen = false;
  TableGeo? _geo;

  /// Per seat (pass-and-play has several on one phone): the table's tiles when that player's
  /// turn last ended, this round. Tiles on the table now that aren't in it get the white
  /// "new since your last turn" glow.
  final Map<String, ({int round, Set<int> tiles})> _tilesAtMyTurnEnd = {};

  /// The turn (turnSeq) in which I drew or played, which ends the white glow for that turn.
  int _glowDoneSeq = -1;

  /// The results panel is minimised to show the final table.
  bool _resultsHidden = false;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _onSession();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_deadline != null && _clockRunning && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _ticker?.cancel();
    _toastTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  List<int> get _order => _rackOrders.putIfAbsent(v?.me ?? '', () => []);

  void _onSession() {
    final nv = s.view;
    if (nv == null) {
      if (mounted) setState(() {});
      return;
    }
    final old = v;
    final seatChanged = old == null || nv.me != old.me;
    // Every tile this phone could already see, so only truly new tiles fly in.
    final seen = <int>{
      if (old != null) ...(old.myTurn ? working.allTiles : old.board.allTiles),
      if (old != null) ...old.rack,
    };
    final turnChanged = seatChanged || nv.turnSeq != _turnSeq;
    if (turnChanged) {
      _turnSeq = nv.turnSeq;
      working = nv.board.copy();
      _history.clear();
      _selected.removeWhere((t) => !nv.rack.contains(t));
      _drag = null;
    }
    final order = _rackOrders.putIfAbsent(nv.me, () => []);
    // Tiles that left the rack (played) leave their slot blank: the rack isn't packed.
    for (var i = 0; i < order.length; i++) {
      if (!isRackGap(order[i]) && !nv.rack.contains(order[i])) order[i] = newRackBlank();
    }
    final fresh = nv.rack.where((t) => !order.contains(t)).toList();
    var packed = trimRack(order);
    for (final t in fresh) {
      packed = addToRack(packed, t);
    }
    order
      ..clear()
      ..addAll(packed);
    if (nv.myTurn && turnChanged) {
      _turnStartOrder = List.of(order);
    }

    if (!seatChanged) {
      if (nv.drawSeq != _drawSeq && nv.drawPlayer != null) {
        if (nv.drawPlayer == nv.me) {
          for (final t in fresh) {
            _spawns[t] = const _Spawn(_Src.pile);
          }
        } else {
          _flyBacks(nv, nv.drawPlayer!, nv.drawCount);
        }
      }
      if (!nv.myTurn) {
        for (final t in nv.board.allTiles) {
          if (!seen.contains(t) && !order.contains(t)) _spawns[t] = _Spawn(_Src.seat, nv.currentId);
        }
      }
    }
    _drawSeq = nv.drawSeq;
    if (nv.noticeSeq != _noticeSeq) {
      if (_noticeSeq >= 0 && nv.notice != null) _showToast(nv.notice!);
      _noticeSeq = nv.noticeSeq;
    }
    if (nv.round != _bannerRound && nv.result == null && nv.starter != null) {
      _bannerRound = nv.round;
      final who = nv.seats.where((x) => x.info.id == nv.starter).firstOrNull;
      if (who != null) {
        _starterBanner = '${who.info.name} starts';
        _bannerTimer?.cancel();
        _bannerTimer = null;
      }
    }
    // Pass-and-play: the banner waits until the cover screen is dismissed, then shows on the table.
    if (_starterBanner != null && _bannerTimer == null && s.coverFor == null) {
      _bannerTimer = Timer(const Duration(milliseconds: TableTuning.starterBannerMs), () {
        if (mounted) setState(() => _starterBanner = null);
      });
    }
    // My turn just ended (or the phone passed to the next player): remember the table, so
    // what others add from now on glows white when I next look.
    if (old != null && old.myTurn && (nv.me != old.me || !nv.myTurn || nv.turnSeq != old.turnSeq)) {
      _tilesAtMyTurnEnd[old.me] = (round: nv.round, tiles: nv.board.allTiles.toSet());
    }
    if (nv.result == null) _resultsHidden = false;
    _deadline = nv.msLeft == null ? null : DateTime.now().add(Duration(milliseconds: nv.msLeft!));
    _clockRunning = nv.clockRunning;
    v = nv;
    if (mounted) setState(() {});
  }

  void _flyBacks(PlayerView nv, String who, int n) {
    final g = _geo;
    if (g == null) return;
    final pos = _seatPositions(nv)[who];
    if (pos == null) return;
    final count = nv.seats.firstWhere((x) => x.info.id == who).count;
    for (var i = 0; i < n; i++) {
      final to = g.backRect(pos, count - n + i, count);
      _flights.add(_BackFlight(who, g.pileRect, to));
    }
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(milliseconds: TableTuning.toastMs), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _haptic() {
    if (prefs.haptics) HapticFeedback.selectionClick();
  }

  // --- rules for what may move -----------------------------------------

  bool get _myTurn => v?.myTurn ?? false;
  Board get _shown => _myTurn ? working : (v?.board ?? working);
  Set<int> get _startTiles => v!.turnStartBoard.allTiles.toSet();
  bool get _melded => v!.mySeat.melded || v!.rules.firstMeld == 0;
  /// Rack entries as shown: tiles not on the table this turn, plus the gaps between sorted sets.
  List<int> get _rackShown {
    final onBoard = _myTurn ? working.allTiles.toSet() : <int>{};
    // A tile out on the table this turn leaves its slot blank (it returns there on Reset).
    return trimRack([for (final t in _order) onBoard.contains(t) ? -1000 - t : t]);
  }

  bool _onBoard(int t) => _shown.find(t) != null;

  /// Tiles with the white glow: the tiles other players added to the table since my last
  /// turn, until I draw or play a tile on my turn. After a round: the winner's final turn
  /// (mine too).
  Set<int> get _newGlow {
    final pv = v;
    if (pv == null) return const {};
    if (pv.result != null) return pv.board.allTiles.toSet().difference(pv.turnStartBoard.allTiles.toSet());
    if (pv.myTurn) {
      if (_playedThisTurn.isNotEmpty) _glowDoneSeq = pv.turnSeq;
      if (_glowDoneSeq == pv.turnSeq) return const {};
    }
    final base = _tilesAtMyTurnEnd[pv.me];
    final seen = base != null && base.round == pv.round ? base.tiles : const <int>{};
    final out = _shown.allTiles.toSet().difference(seen);
    if (pv.myTurn) out.removeAll(_playedThisTurn);
    return out;
  }

  /// Can these tiles be put on (or moved around) the table right now?
  String? _boardBlock(List<int> tiles) {
    if (!_myTurn) return 'Wait for your turn to play on the table.';
    if (!_melded && tiles.any(_startTiles.contains)) {
      return 'Before your first meld you can only use tiles from your rack.';
    }
    return null;
  }

  /// Applies a table change. Returns false (and flashes red) if it would put a tile that was
  /// on the table at the start of the turn into the rack; that is never allowed.
  bool _setWorking(Board b, {List<int>? moved}) {
    final sent = tableTilesSentToRack(_startTiles, b);
    if (sent.isNotEmpty) {
      _flashRed([...?moved, ...sent], kTableTileToRack);
      return false;
    }
    _history.add(working);
    working = b;
    _selected.clear();
    _groupSel = false;
    if (moved != null && moved.isNotEmpty) {
      final blk = b.blockOf(moved.first);
      if (blk != null && isValidMeld(blk.tiles) && prefs.highlightValid) {
        _shine
          ..clear()
          ..addAll(blk.tiles);
        Timer(const Duration(milliseconds: TableTuning.shineMs), () {
          if (mounted) setState(_shine.clear);
        });
      }
    }
    _haptic();
    s.act(PreviewAction(working));
    setState(() {});
    return true;
  }

  void _flashRed(Iterable<int> tiles, [String? why]) {
    _flash.addAll(tiles);
    if (why != null) _showToast(why);
    if (prefs.haptics) HapticFeedback.mediumImpact();
    setState(() {});
    Timer(const Duration(milliseconds: TableTuning.flashMs), () {
      if (mounted) setState(_flash.clear);
    });
  }

  // --- gestures ----------------------------------------------------------

  Offset _local(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  Rect _rectOf(int t) {
    final g = _geo!;
    final p = _shown.find(t);
    if (p != null) return g.cellRect(p.row, p.col);
    final i = _rackShown.indexOf(t);
    return g.rackSlot(math.max(0, i));
  }

  void _startDrag(List<int> tiles, Offset global) {
    if (_drag != null || tiles.isEmpty) return;
    final fromBoard = tiles.any(_onBoard);
    if (fromBoard) {
      final why = _boardBlock(tiles);
      if (why != null) {
        _flashRed(tiles, why);
        return;
      }
    }
    final p = _local(global);
    final r = _rectOf(tiles.first);
    // Grab offset in units of the tile, so it scales between rack and board.
    final grab = Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height);
    _selected.clear();
    _drag = _Drag(tiles, grab, p);
    _haptic();
    setState(() {});
  }

  void _moveDrag(Offset global) {
    final d = _drag;
    if (d == null) return;
    d.pointer = _local(global);
    setState(() {});
  }

  /// Size of dragged tiles: board size over the board, rack size elsewhere.
  Size _dragTileSize() {
    final g = _geo!;
    final d = _drag!;
    if (g.inRack(d.pointer)) return Size(g.rackTileW * .94, g.rackTileH);
    return Size(g.cellW * .92, g.tileH);
  }

  Offset _dragTopLeft() {
    final d = _drag!;
    final sz = _dragTileSize();
    return d.pointer - Offset(d.grab.dx * sz.width, d.grab.dy * sz.height);
  }

  /// Where a drop would land on the board, if over it.
  ({int row, int col, double frac})? _dropCell() {
    final g = _geo!;
    final d = _drag!;
    if (g.inRack(d.pointer)) return null;
    final tl = _dragTopLeft();
    final c = tl + Offset(g.cellW / 2, g.tileH / 2);
    return g.cellAt(c, loose: true);
  }

  void _endDrag() {
    final d = _drag;
    if (d == null) return;
    final g = _geo!;
    final cell = _dropCell();
    final sz = _dragTileSize();
    final firstCenter = _dragTopLeft() + Offset(sz.width / 2, sz.height / 2);
    _drag = null;
    final tiles = d.tiles;
    final fromLongPress = _longPressing;
    _longPressing = false;
    if (!d.moved) {
      // Long-press released in place: keep the grabbed tiles selected.
      if (fromLongPress) {
        _selected
          ..clear()
          ..addAll(tiles);
        _groupSel = true;
        _haptic();
      }
      setState(() {});
      return;
    }
    if (g.inRack(d.pointer)) {
      final back = tiles.where(_onBoard).toList();
      if (back.isNotEmpty) {
        if (!_myTurn || back.any((t) => wasOnTableAtTurnStart(_startTiles, t))) {
          _flashRed(tiles, kTableTileToRack);
          return;
        }
      }
      // Into the slot under the first dragged tile (any time, even on others' turns), leaving
      // blanks where the player wants them (and returning this turn's tiles from the table).
      final slot = g.rackSlotAt(firstCenter);
      final onBoard = _myTurn ? working.allTiles.toSet().difference(back.toSet()) : <int>{};
      final placed = placeInRack(_order, tiles, slot, free: onBoard);
      _order
        ..clear()
        ..addAll(placed);
      if (back.isNotEmpty) {
        final b = working.copy()..removeTiles(back);
        _setWorking(b);
      } else {
        _haptic();
        setState(() {});
      }
      return;
    }
    if (cell == null) {
      setState(() {});
      return;
    }
    if (cell.row < working.rowCount && _tryReclaim(tiles, working.rows[cell.row][cell.col], jokerOnly: true)) return;
    final why = _boardBlock(tiles);
    if (why != null) {
      _flashRed(tiles, why);
      return;
    }
    // Added to a set holding a joker with no valid place for the tile: the joker swap shortcut
    // repositions the joker (2-3-J + 4 makes 2-3-4-J) or sets it free (4-4-4-J + 4).
    final into = _dropTarget(tiles, cell.row, cell.col, cell.frac);
    if (into != null && !Layout.hasValidFit(working, tiles, into.set, into.index) && _tryReclaim(tiles, into.set)) return;
    _setWorking(_placeAt(tiles, cell.row, cell.col, cell.frac), moved: tiles);
  }

  /// The joker swap shortcut (see Layout.jokerShortcut): one selected tile, from the rack or
  /// the table, tapped onto a set that holds a joker (or dropped onto the joker) takes the
  /// joker's place if it's a compatible replacement; the joker moves to the set's end or edge,
  /// or is set down alone nearby, selected, for the player to place. Returns true when handled.
  bool _tryReclaim(List<int> tiles, int target, {bool jokerOnly = false}) {
    if (tiles.length != 1 || target < 0 || !_myTurn) return false;
    final t = tiles.first;
    if (isJoker(t) || (jokerOnly && !isJoker(target))) return false;
    final blk = working.blockOf(target);
    if (blk == null || blk.tiles.contains(t)) return false;
    final ti = blk.tiles.indexOf(target);
    final jokers = blk.tiles.where(isJoker).toList()
      ..sort((a, b) => (blk.tiles.indexOf(a) - ti).abs() - (blk.tiles.indexOf(b) - ti).abs());
    for (final j in jokers) {
      final res = Layout.jokerShortcut(working, t, j);
      if (res == null) continue;
      if (!_melded) {
        _flashRed([t, j], 'Make your first meld before changing sets on the table.');
        return true;
      }
      final why = _boardBlock([t]);
      if (why != null) {
        _flashRed([t], why);
        return true;
      }
      if (!_setWorking(res.board, moved: [t])) return true;
      if (res.detached) {
        setState(() {
          _selected
            ..clear()
            ..add(j);
          _groupSel = false;
        });
        _showToast('Joker set aside: tap a set or a spot to place it.');
      }
      return true;
    }
    return false;
  }

  /// The set a drop at ([row], [col]) adds [tiles] to, and where: a set under the drop point,
  /// or one the dropped tiles would touch end-on.
  ({int set, int index})? _dropTarget(List<int> tiles, int row, int col, double frac) {
    final tmp = working.copy()..removeTiles(tiles);
    if (row >= tmp.rowCount) return null;
    final c = col.clamp(0, Board.width - tiles.length);
    final at = tmp.rows[row][c];
    if (at >= 0) {
      final blk = tmp.blockOf(at)!;
      return (set: at, index: (c - blk.start) + (frac > .5 ? 1 : 0));
    }
    if (c > 0 && tmp.rows[row][c - 1] >= 0) {
      final blk = tmp.blockOf(tmp.rows[row][c - 1])!;
      return (set: blk.tiles.first, index: blk.length);
    }
    final after = c + tiles.length;
    if (after < Board.width && tmp.rows[row][after] >= 0) return (set: tmp.rows[row][after], index: 0);
    return null;
  }

  Board _placeAt(List<int> tiles, int row, int col, double frac) {
    final tmp = working.copy()..removeTiles(tiles);
    if (row < tmp.rowCount && tmp.rows[row][col] >= 0) {
      final blk = tmp.blockOf(tmp.rows[row][col])!;
      final idx = (col - blk.start) + (frac > .5 ? 1 : 0);
      return Layout.dropInto(tmp, tiles, blk.tiles.first, idx, col: col);
    }
    return Layout.place(tmp, tiles, row, col);
  }

  void _onTap(int t) {
    if (_drag != null) return;
    if (_selected.contains(t)) {
      // Tapping the selection again deselects it (all of it).
      setState(() {
        _selected.clear();
        _groupSel = false;
      });
      return;
    }
    if (_selected.isNotEmpty && _onBoard(t) && _myTurn && !_selected.contains(t)) {
      _autoPlace(_selected.toList(), t);
      return;
    }
    if (_onBoard(t) && !_myTurn) return;
    setState(() {
      _selected
        ..clear()
        ..add(t);
      _groupSel = false;
    });
    _haptic();
  }

  /// Tap a tile (or long-press a run/group/set and let go), then tap a set: the tiles join
  /// the set if that makes a valid set, at the end nearer the tap when both ends work.
  /// Otherwise the selection flashes red and stays selected.
  void _autoPlace(List<int> sel, int target) {
    final why = _boardBlock(sel);
    if (why != null) {
      if (!_tryReclaim(sel, target)) _flashRed(sel, why);
      return;
    }
    final tmp = working.copy()..removeTiles(sel);
    final blk = tmp.blockOf(target);
    if (blk == null) return;
    // The end nearer the tap when both ends work.
    final at = Layout.attachEnd(blk.tiles, sel, blk.tiles.indexOf(target), allowPartial: true);
    if (at != null) {
      _groupSel = false;
      _setWorking(Layout.insertInto(tmp, sel, blk.tiles.first, at), moved: sel);
      return;
    }
    // No valid end: the joker swap shortcut, then the split for a number the run already has.
    if (_tryReclaim(sel, target)) return;
    final split = Layout.splitDuplicate(tmp, sel, target);
    if (split != null) {
      _groupSel = false;
      _setWorking(split, moved: sel);
      return;
    }
    // Not valid there: flash red, keep the selection.
    _flashRed(sel);
  }

  void _onBoardTapUp(TapUpDetails d) {
    if (_selected.isEmpty || !_myTurn) {
      if (_selected.isNotEmpty) setState(_selected.clear);
      return;
    }
    final g = _geo!;
    final p = _local(d.globalPosition);
    final c = g.cellAt(p);
    if (c == null) return;
    final sel = _rackShown.where(_selected.contains).toList()..addAll(_selected.where(_onBoard));
    final why = _boardBlock(sel);
    if (why != null) {
      _flashRed(sel, why);
      return;
    }
    if (_groupSel) {
      // A long-press selection lands as a new set at the tapped spot (snap and layout rules apply).
      _groupSel = false;
      _setWorking(Layout.place(working, sel, c.row, c.col, merge: false), moved: sel);
      return;
    }
    _setWorking(_placeAt(sel, c.row, c.col, 0), moved: sel);
  }

  void _onRackTapUp(TapUpDetails d) {
    final back = _selected.where(_onBoard).toList();
    // Rack background: a long-press selection (or any rack selection) is deselected.
    if (_selected.isNotEmpty && (_groupSel || back.isEmpty)) {
      setState(() {
        _selected.clear();
        _groupSel = false;
      });
      return;
    }
    if (back.isEmpty || !_myTurn) return;
    if (back.any((t) => wasOnTableAtTurnStart(_startTiles, t))) {
      _flashRed(back, kTableTileToRack);
      return;
    }
    var order = [for (final e in _order) back.contains(e) ? newRackBlank() : e];
    for (final t in back) {
      order = addToRack(order, t);
    }
    _order
      ..clear()
      ..addAll(order);
    _setWorking(working.copy()..removeTiles(back));
  }

  void _onDoubleTap(int t) {
    if (!_myTurn) return;
    final blk = working.blockOf(t);
    if (blk == null) return;
    final why = _boardBlock(blk.tiles);
    if (why != null) {
      _flashRed(blk.tiles, why);
      return;
    }
    if (blk.tiles.first == t) return;
    _setWorking(Layout.split(working, t));
  }

  void _onLongPress(int t, Offset global) {
    if (_onBoard(t)) {
      final blk = _shown.blockOf(t);
      if (blk != null) _startLongDrag(blk.tiles, global);
      return;
    }
    // Rack: pick up the neighbouring tiles that form a run or group.
    final shown = _rackShown;
    final i = shown.indexOf(t);
    var a = i, b = i;
    while (a > 0 && !isRackGap(shown[a - 1]) && isCompatible(shown.sublist(a - 1, b + 1))) {
      a--;
    }
    while (b < shown.length - 1 && !isRackGap(shown[b + 1]) && isCompatible(shown.sublist(a, b + 2))) {
      b++;
    }
    if (b > a) {
      _startLongDrag(shown.sublist(a, b + 1), global);
    } else {
      _onTap(t);
    }
  }

  /// A long-press grab: drag it, or release without moving to keep it selected.
  void _startLongDrag(List<int> tiles, Offset global) {
    final had = _drag != null;
    _startDrag(tiles, global);
    _longPressing = !had && _drag != null;
  }

  // --- buttons -------------------------------------------------------------

  List<int> get _playedThisTurn {
    if (!_myTurn) return const [];
    final start = _startTiles;
    return working.allTiles.where((t) => !start.contains(t)).toList();
  }

  Future<void> _drawOrEnd() async {
    if (!_myTurn) return;
    final played = _playedThisTurn;
    if (played.isEmpty) {
      _selected.clear();
      await s.act(const DrawAction());
      return;
    }
    final err = checkTurn(start: v!.turnStartBoard, proposed: working, rack: v!.rack, melded: v!.mySeat.melded, rules: v!.rules);
    if (err != null) {
      _flashRed(working.invalidBlocks.expand((b) => b.tiles).toList(), err);
      return;
    }
    final r = await s.act(CommitAction(working));
    if (!r.ok && mounted) _showToast(r.error ?? 'The host refused that move.');
  }

  /// Anything to reset: tiles moved on the table or the rack rearranged since the turn began.
  bool get _canReset {
    if (!_myTurn || v == null) return false;
    if (_history.isNotEmpty) return true;
    final start = _turnStartOrder;
    final now = _order;
    if (start.length != now.length) return true;
    for (var i = 0; i < start.length; i++) {
      if (start[i] != now[i]) return true;
    }
    return false;
  }

  /// Reset: every tile goes back to where it was when the turn began, on the table and in the
  /// rack. The turn timer keeps running (it is not restarted).
  void _resetTurn() {
    if (!_myTurn || v == null) return;
    working = v!.turnStartBoard.copy();
    _history.clear();
    _selected.clear();
    final rack = v!.rack.toSet();
    var restored = [for (final t in _turnStartOrder) isRackGap(t) || rack.contains(t) ? t : newRackBlank()];
    for (final t in v!.rack.where((t) => !restored.contains(t)).toList()) {
      restored = addToRack(restored, t);
    }
    _order
      ..clear()
      ..addAll(trimRack(restored));
    s.act(PreviewAction(working));
    _haptic();
    setState(() {});
  }

  /// 789 / 777: valid sets of 3+ to the top left (each followed by a blank slot), then the rest
  /// sorted. This packs the rack (no other blanks); a set doesn't straddle the row break.
  void _sort(bool runs) {
    final onBoard = _myTurn ? working.allTiles.toSet() : <int>{};
    final rack = keepSetsOnRows(sortRackWithSets(_order.where((t) => !isRackGap(t) && !onBoard.contains(t)).toList(), runs: runs));
    // Tiles out on the table this turn keep slots after the sorted ones (for Reset).
    final rest = _order.where(onBoard.contains).toList();
    _order
      ..clear()
      ..addAll(rack)
      ..addAll(rest);
    _haptic();
    setState(() {});
  }

  void _makeSpace() {
    if (!_myTurn) return;
    final b = Layout.makeSpace(working);
    if (b == null) {
      _showToast(working.usedRows.isEmpty ? 'The table is empty.' : 'There\'s already an empty row.');
      return;
    }
    _setWorking(b);
  }

  Future<void> _openMenu() async {
    _menuOpen = true;
    s.pause();
    final host = s.localHost;
    final me = v?.me;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: MkPanel(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Menu', style: MK.title(22), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(v?.rules.summary() ?? '', style: MK.body(12, color: MK.gold), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                GoldButton('Resume', icon: Icons.play_arrow, onPressed: () => Navigator.pop(ctx)),
                if (s.testMenu && host != null && me != null) ...[
                  const SizedBox(height: 14),
                  Text('Test tools', style: MK.body(14, color: MK.goldLight, weight: FontWeight.w700), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    GoldButton('Win now', compact: true, crimson: true, onPressed: () {
                      Navigator.pop(ctx);
                      host.debugWin(me);
                    }),
                    GoldButton('Draw 5', compact: true, crimson: true, onPressed: () {
                      Navigator.pop(ctx);
                      host.debugDraw(me, 5);
                    }),
                    GoldButton('Give me a joker', compact: true, crimson: true, onPressed: () {
                      Navigator.pop(ctx);
                      host.debugGiveJoker(me);
                    }),
                    GoldButton('Empty the pile', compact: true, crimson: true, onPressed: () {
                      Navigator.pop(ctx);
                      host.debugEmptyPile();
                    }),
                    GoldButton('Timer to 3 s', compact: true, crimson: true, onPressed: () {
                      Navigator.pop(ctx);
                      host.debugShortClock();
                    }),
                  ]),
                ],
                const SizedBox(height: 14),
                GoldButton('Leave game', icon: Icons.logout, crimson: true, onPressed: () {
                  Navigator.pop(ctx);
                  _leave();
                }),
              ]),
            ),
          ),
        ),
      ),
    );
    _menuOpen = false;
    if (mounted) s.resume();
  }

  bool _leaving = false;
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    s.leave();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // --- layout ----------------------------------------------------------------

  Map<String, SeatPos> _seatPositions(PlayerView pv) {
    final n = pv.seats.length;
    final me = pv.seats.indexWhere((x) => x.info.id == pv.me);
    final others = [for (var k = 1; k < n; k++) pv.seats[(me + k) % n].info.id];
    final pos = switch (n) {
      2 => [SeatPos.top],
      3 => [SeatPos.left, SeatPos.right],
      _ => [SeatPos.left, SeatPos.top, SeatPos.right],
    };
    return {for (var i = 0; i < others.length; i++) others[i]: pos[i]};
  }

  @override
  Widget build(BuildContext context) {
    final pv = v;
    if (pv == null) {
      return Scaffold(
        body: WoodBackground(
          child: Center(child: Text(s.status ?? 'Starting…', style: MK.body(16))),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_menuOpen) _openMenu();
      },
      child: Scaffold(
        body: WoodBackground(
          child: SafeArea(
            child: LayoutBuilder(builder: (ctx, cons) {
              final rack = _rackShown;
              final view = _boardView(_shown);
              final g = TableGeo(cons.biggest,
                  boardRows: _shown.rowCount,
                  rackEntries: rack,
                  seatCount: pv.seats.length,
                  viewRows: view.rows,
                  viewCols: view.cols,
                  contentFrom: view.from,
                  contentTo: view.to);
              _geo = g;
              return Stack(
                key: _stackKey,
                clipBehavior: Clip.none,
                children: [
                  // Board tap target (place a selected tile in an empty spot).
                  Positioned.fromRect(
                    rect: g.boardRect,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: _onBoardTapUp),
                  ),
                  ..._dropHint(g),
                  ..._rackFrame(g, rack.length),
                  ..._seats(g, pv),
                  _brand(g),
                  ..._myCorner(g, pv),
                  _pile(g, pv),
                  ..._controls(g, pv),
                  ..._sprites(g, pv, rack),
                  for (final f in _flights)
                    _FlyingBack(
                      key: f.key,
                      from: f.from,
                      to: f.to,
                      onDone: () => setState(() => _flights.remove(f)),
                    ),
                  if (_toast != null) _toastWidget(g),
                  if (_starterBanner != null && pv.result == null && s.coverFor == null) _starterBannerWidget(g, _starterBanner!),
                  if (s.status != null) _statusBanner(g, s.status!),
                  if (pv.result != null && !_resultsHidden)
                    Positioned.fill(
                        child: ResultsOverlay(
                            session: s, view: pv, onLeave: _leave, onMinimize: () => setState(() => _resultsHidden = true))),
                  if (pv.result != null && _resultsHidden)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GoldButton('Show results', icon: Icons.emoji_events, onPressed: () => setState(() => _resultsHidden = false)),
                    ),
                  // Pass-and-play: the drawn tiles are on show; the turn is over, so no input.
                  if (s.revealTiles.isNotEmpty) const Positioned.fill(child: AbsorbPointer()),
                  if (s.coverFor != null) Positioned.fill(child: _cover(s.coverFor!)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// How much of the board to show: 3 rows and a narrow, centred width to start, growing (rows
  /// and columns independently) as sets spread down or across, so tiles start large. Rows grow
  /// only when a set sits below the rows in view (Add row, auto-placement), never just
  /// because a tile landed in the last visible row: every row keeps the same cell size. When
  /// the bottom rows empty the view zooms back in; end-of-turn tidying removes empty rows at
  /// the top. Columns zoom out only when the sets themselves don't fit across: no spare
  /// columns are kept (dropping a tile on a set's end tile extends it at its valid end), and
  /// the window of columns shifts rather than zooms when sets sit off-centre. The view never
  /// changes during a drag.
  ({double rows, double cols, int? from, int? to}) _boardView(Board b) {
    final frozen = _view;
    if (_drag != null && frozen != null) return frozen;
    final used = b.usedRows;
    var minCol = Board.width, maxCol = -1;
    for (final r in used) {
      for (final blk in b.blocksInRow(r)) {
        minCol = math.min(minCol, blk.start);
        maxCol = math.max(maxCol, blk.end - 1);
      }
    }
    final rows = math.max(TableGeo.minViewRows, (used.isEmpty ? 0 : used.last + 1).toDouble());
    final cols = maxCol < 0 ? TableGeo.minViewCols : TableGeo.colsToShow(minCol, maxCol).toDouble();
    return _view = (rows: rows, cols: cols, from: maxCol < 0 ? null : minCol, to: maxCol < 0 ? null : maxCol);
  }

  ({double rows, double cols, int? from, int? to})? _view;

  Widget _starterBannerWidget(TableGeo g, String text) => Positioned(
        left: 0,
        right: 0,
        top: g.boardRect.top + g.boardRect.height * .3,
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: .85 + .15 * t, child: child)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xEE2A1208),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: MK.goldLight, width: 1.6),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
                    BoxShadow(color: Color(0x66FFD36B), blurRadius: 18),
                  ],
                ),
                child: Text(text, style: MK.title(24).copyWith(color: MK.goldLight)),
              ),
            ),
          ),
        ),
      );

  List<Widget> _dropHint(TableGeo g) {
    if (_drag == null) return const [];
    final c = _dropCell();
    if (c == null) return const [];
    final n = _drag!.tiles.length;
    final col = c.col.clamp(0, 27 - n);
    final r = g.cellRect(c.row, col);
    return [
      Positioned(
        left: r.left - 2,
        top: r.top - 2,
        width: n * g.cellW,
        height: r.height + 4,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x22FFD36B),
              border: Border.all(color: const Color(0x88FFD36B), width: 1.2),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _rackFrame(TableGeo g, int count) {
    final rr = g.rackRect;
    return [
      AnimatedPositioned(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        left: rr.left - 8,
        top: rr.top - 6,
        width: rr.width + 16,
        height: rr.height + 12,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onRackTapUp,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              image: const DecorationImage(image: AssetImage('assets/textures/rackwood.jpg'), fit: BoxFit.cover),
              border: Border.all(color: _myTurn ? MK.goldLight : MK.gold.withValues(alpha: .7), width: _myTurn ? 1.6 : 1),
              boxShadow: [
                const BoxShadow(color: Colors.black87, blurRadius: 24, offset: Offset(0, -6)),
                // On my turn the rack glows gold, like my avatar (painted over the dark shadow).
                if (_myTurn) const BoxShadow(color: Color(0xCCFFD36B), blurRadius: 22, spreadRadius: 3),
              ],
            ),
            padding: EdgeInsets.fromLTRB(6, g.rackPadTop + 2, 6, 0),
            child: Column(
              children: [
                for (var r = 0; r < g.rackRows; r++)
                  SizedBox(
                    height: g.rackRowH,
                    child: Column(children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(gradient: MK.velvetGradient, borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      Container(
                        height: g.rackRowH - g.rackTileH * .92,
                        decoration: BoxDecoration(
                          gradient: MK.lipGradient,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 4))],
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ),
      // Left of the rack, top down: Add row (Make space), then the 789 and 777 sort buttons.
      Positioned(
        left: g.rackRect.left - 58,
        top: math.min(g.rackRect.top + 2, g.size.height - 3 * 46 - 2 * 6 - 6),
        width: 46,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(
            message: 'Add a row (make space)',
            child: RingButton(
              size: 46,
              onPressed: _myTurn ? _makeSpace : null,
              child: const Icon(Icons.unfold_more_double, color: MK.goldLight, size: 38),
            ),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: 'Sort: sets first, then runs order',
            child: RingButton(size: 46, onPressed: () => _sort(true), child: _sortLabel('789')),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: 'Sort: sets first, then groups order',
            child: RingButton(size: 46, onPressed: () => _sort(false), child: _sortLabel('777')),
          ),
        ]),
      ),
    ];
  }

  /// The tile-count badge on a player's avatar (opponents and you).
  Widget _countBadge(int n, {Key? key}) => Positioned(
        key: key,
        right: -10,
        top: -6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(gradient: MK.goldGradient, borderRadius: BorderRadius.circular(9)),
          child: Text('$n', style: MK.body(11, color: const Color(0xFF2A1404), weight: FontWeight.w800)),
        ),
      );

  Widget _avatar(SeatView sv, double size, {bool current = false}) {
    final idx = v!.seats.indexOf(sv);
    final robot = robotByAvatar(sv.info.avatar);
    return PlayerAvatar(
      size: size,
      name: sv.info.name,
      image: sv.info.avatar,
      color: seatColors[idx % seatColors.length],
      current: current,
      onLongPress: robot == null ? null : () => _showRobot(sv, robot),
    );
  }

  void _showRobot(SeatView sv, RobotProfile robot) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: MkPanel(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PlayerAvatar(size: 72, name: robot.name, image: robot.avatar),
              const SizedBox(width: 14),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sv.info.name, style: MK.title(20)),
                  const SizedBox(height: 4),
                  Text('"${robot.tagline}"', style: MK.body(14, color: MK.goldLight)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _clockText() {
    final d = _deadline;
    if (d == null) return '';
    final ms = _clockRunning ? d.difference(DateTime.now()).inMilliseconds : (v?.msLeft ?? 0);
    final sec = (math.max(0, ms) / 1000).ceil();
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  List<Widget> _seats(TableGeo g, PlayerView pv) {
    final out = <Widget>[];
    final pos = _seatPositions(pv);
    for (final sv in pv.seats) {
      final p = pos[sv.info.id];
      if (p == null) continue;
      final c = g.seatCenter(p);
      final current = pv.currentId == sv.info.id && pv.result == null;
      final a = g.avatar;
      // Tiles still flying in from the pile aren't in the face-down rack (or the count) until
      // they land. The rest keep the final layout, so a tile appears exactly where it landed.
      final flying = _flights.where((f) => f.who == sv.info.id).length;
      final shown = math.max(0, sv.count - flying);
      out.add(Positioned(
        left: c.dx - a / 2,
        top: c.dy - a / 2,
        child: Stack(clipBehavior: Clip.none, children: [
          _avatar(sv, a, current: current),
          _countBadge(shown),
        ]),
      ));
      final label = '${sv.info.name}${sv.connected ? '' : ' (offline)'}${current ? '  ${_clockText()}' : ''}';
      if (p == SeatPos.top) {
        out.add(Positioned(
          left: c.dx - a / 2 - 120,
          width: 112,
          top: c.dy - 8,
          child: Text(label, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: MK.body(12, weight: FontWeight.w600)),
        ));
      } else {
        out.add(Positioned(
          left: c.dx - g.sideW / 2,
          width: g.sideW,
          top: c.dy + a / 2 + 3,
          child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: MK.body(11, weight: FontWeight.w600)),
        ));
      }
      for (var i = 0; i < shown; i++) {
        out.add(Positioned.fromRect(rect: g.backRect(p, i, sv.count), child: GoldBack(width: g.backW, height: g.backH)));
      }
    }
    return out;
  }

  Widget _brand(TableGeo g) => Positioned(
        left: 8,
        top: 6,
        child: Row(children: [
          Text('Round ${v!.round}', style: MK.body(11, color: MK.gold)),
        ]),
      );

  List<Widget> _myCorner(TableGeo g, PlayerView pv) {
    final me = pv.mySeat;
    final a = g.avatar * 1.1;
    final my = pv.myTurn;
    final infoW = math.max(70.0, g.rackRect.left - 70);
    return [
      Positioned(
        left: 10,
        bottom: 8,
        width: infoW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${me.info.name} (you)', maxLines: 1, overflow: TextOverflow.ellipsis, style: MK.body(12, weight: FontWeight.w700)),
          if (!me.melded && pv.rules.firstMeld > 0)
            Text('First meld: ${pv.rules.firstMeld}+ pts', style: MK.body(10, color: MK.gold)),
          const SizedBox(height: 4),
          Row(children: [
            // Your tile count, like the opponents' (tiles you've put on the table this turn don't count).
            Stack(clipBehavior: Clip.none, children: [
              _avatar(me, a, current: my),
              _countBadge(_rackShown.where((t) => !isRackGap(t)).length, key: const ValueKey('myCount')),
            ]),
            const SizedBox(width: 14),
            if (my && _deadline != null) Text(_clockText(), style: MK.body(18, weight: FontWeight.w700)),
          ]),
        ]),
      ),
    ];
  }

  Widget _pile(TableGeo g, PlayerView pv) {
    final r = g.pileRect;
    return Positioned(
      left: r.left,
      top: r.top,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: r.width + 4,
          height: r.height + 4,
          child: Stack(children: [
            if (pv.pile > 1) Positioned(left: 4, top: 4, child: GoldBack(width: r.width, height: r.height)),
            if (pv.pile > 0) GoldBack(width: r.width, height: r.height),
            if (pv.pile == 0)
              Container(
                width: r.width,
                height: r.height,
                decoration: BoxDecoration(border: Border.all(color: MK.gold.withValues(alpha: .4)), borderRadius: BorderRadius.circular(5)),
              ),
          ]),
        ),
        const SizedBox(width: 6),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${pv.pile}', style: MK.body(17, weight: FontWeight.w700)),
          Text('IN PILE', style: MK.body(8, color: MK.gold, weight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  List<Widget> _controls(TableGeo g, PlayerView pv) {
    final my = pv.myTurn;
    final played = _playedThisTurn.isNotEmpty;
    final bs = (g.size.height * .11).clamp(36.0, 46.0);
    return [
      Positioned(
        right: 10,
        bottom: 10,
        width: g.ctrlW - 16,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            RingButton(size: bs, icon: Icons.restart_alt, caption: 'RESET', onPressed: _canReset ? _resetTurn : null),
            const SizedBox(width: 10),
            RingButton(size: bs, icon: Icons.menu, caption: 'MENU', onPressed: _openMenu),
          ]),
          const SizedBox(height: 8),
          GoldButton(
            my ? (played ? 'End turn' : (pv.pile > 0 ? 'Draw' : 'Pass')) : 'Waiting...',
            icon: my ? (played ? Icons.check_circle_outline : Icons.add_box_outlined) : Icons.hourglass_empty,
            compact: true,
            onPressed: my ? _drawOrEnd : null,
          ),
        ]),
      ),
    ];
  }

  Widget _sortLabel(String text) =>
      Text(text, style: MK.body(15, color: MK.goldLight, weight: FontWeight.w800).copyWith(height: 1.0));

  List<Widget> _sprites(TableGeo g, PlayerView pv, List<int> rack) {
    final out = <Widget>[];
    final board = _shown;
    final invalid = _myTurn && prefs.highlightValid ? board.invalidBlocks.expand((b) => b.tiles).toSet() : <int>{};
    final dragging = _drag?.tiles.toSet() ?? <int>{};
    final pos = _seatPositions(pv);
    Rect? spawnRect(int t) {
      final sp = _spawns[t];
      if (sp == null) return null;
      if (sp.src == _Src.pile) return g.pileRect;
      final p = pos[sp.seat];
      if (p == null) return g.pileRect;
      final sv = pv.seats.firstWhere((x) => x.info.id == sp.seat);
      return g.backRect(p, sv.count, sv.count + 1);
    }

    TileGlow glow(int t) {
      if (_flash.contains(t)) return TileGlow.flashRed;
      if (s.revealTiles.contains(t)) return TileGlow.selected;
      if (_selected.contains(t)) return TileGlow.selected;
      if (_shine.contains(t)) return TileGlow.shine;
      if (invalid.contains(t)) return TileGlow.invalid;
      return TileGlow.none;
    }

    final newGlow = _newGlow;
    for (var r = 0; r < board.rowCount; r++) {
      for (var c = 0; c < Board.width; c++) {
        final t = board.rows[r][c];
        if (t < 0 || dragging.contains(t)) continue;
        out.add(_sprite(t, g.cellRect(r, c), spawnRect(t), glow(t), board: true, newGlow: newGlow.contains(t)));
      }
    }
    for (var i = 0; i < rack.length; i++) {
      final t = rack[i];
      if (isRackGap(t)) continue;
      if (dragging.contains(t)) continue;
      out.add(_sprite(t, g.rackSlot(i), spawnRect(t), glow(t), board: false));
    }
    if (_drag != null) {
      final sz = _dragTileSize();
      final tl = _dragTopLeft();
      for (var i = 0; i < _drag!.tiles.length; i++) {
        final t = _drag!.tiles[i];
        out.add(_sprite(t, Rect.fromLTWH(tl.dx + i * sz.width / .92, tl.dy, sz.width, sz.height), null, TileGlow.selected,
            board: false, instant: true, lifted: true));
      }
    }
    if (_spawns.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _spawns.clear());
    }
    return out;
  }

  Widget _sprite(int t, Rect rect, Rect? spawn, TileGlow glow,
      {required bool board, bool instant = false, bool lifted = false, bool newGlow = false}) {
    return _TileSprite(
      key: ValueKey(t),
      tile: t,
      newGlow: newGlow,
      rect: rect,
      spawnFrom: spawn,
      glow: glow,
      instant: instant,
      lifted: lifted,
      onTap: () => _onTap(t),
      onDoubleTap: board && _myTurn ? () => _onDoubleTap(t) : null,
      onLongPress: (p) => _onLongPress(t, p),
      onDragStart: (p) => _startDrag([t], p),
      onDragUpdate: _moveDrag,
      onDragEnd: _endDrag,
    );
  }

  Widget _toastWidget(TableGeo g) => Positioned(
        top: g.topH + 6,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xEE1A0805),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: MK.gold),
              ),
              child: Text(_toast!, style: MK.body(13, weight: FontWeight.w600)),
            ),
          ),
        ),
      );

  Widget _statusBanner(TableGeo g, String text) => Positioned(
        top: g.topH + 40,
        left: 40,
        right: 40,
        child: Center(
          child: MkPanel(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, style: MK.body(14), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              GoldButton('Leave', compact: true, onPressed: _leave),
            ]),
          ),
        ),
      );

  Widget _cover(String name) => WoodBackground(
        child: Center(
          child: MkPanel(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Pass the phone to', style: MK.body(16, color: MK.gold)),
              const SizedBox(height: 6),
              Text(name, style: MK.title(34).copyWith(color: MK.goldLight)),
              const SizedBox(height: 18),
              GoldButton('I\'m $name, start my turn', icon: Icons.play_arrow, onPressed: () {
                s.dismissCover();
              }),
              const SizedBox(height: 10),
              TextButton(onPressed: _openMenu, child: Text('Menu', style: MK.body(13, color: MK.gold))),
            ]),
          ),
        ),
      );
}

/// One tile on the table or rack. It glides to its new spot whenever its
/// target changes, and can fly in (flipping from its gold back) from the
/// pile or an opponent's indicator.
class _TileSprite extends StatefulWidget {
  final int tile;
  final Rect rect;
  final Rect? spawnFrom;
  final TileGlow glow;

  /// The white "new on the table" glow (fades in and out).
  final bool newGlow;
  final bool instant;
  final bool lifted;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset global) onLongPress;
  final void Function(Offset global) onDragStart;
  final void Function(Offset global) onDragUpdate;
  final VoidCallback onDragEnd;

  const _TileSprite({
    super.key,
    required this.tile,
    required this.rect,
    required this.spawnFrom,
    required this.glow,
    this.newGlow = false,
    required this.instant,
    required this.lifted,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_TileSprite> createState() => _TileSpriteState();
}

class _TileSpriteState extends State<_TileSprite> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Rect _from, _to;
  bool _flying = false;
  bool _longDragging = false;
  bool _longStarted = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, value: 1);
    _to = widget.rect;
    if (widget.spawnFrom != null) {
      _from = widget.spawnFrom!;
      _flying = true;
      _c.duration = const Duration(milliseconds: TableTuning.flyMs);
      _c.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _flying = false);
      });
    } else {
      _from = widget.rect;
    }
  }

  @override
  void didUpdateWidget(covariant _TileSprite old) {
    super.didUpdateWidget(old);
    if (widget.rect != _to) {
      if (widget.instant) {
        _from = _to = widget.rect;
        _c.value = 1;
        _flying = false;
      } else if (!_flying) {
        _from = _current;
        _to = widget.rect;
        _c.duration = const Duration(milliseconds: TableTuning.moveMs);
        _c.forward(from: 0);
      } else {
        _to = widget.rect;
      }
    }
  }

  Rect get _current {
    final t = _flying ? Curves.easeInOutCubic.transform(_c.value) : Curves.easeOutCubic.transform(_c.value);
    var r = Rect.lerp(_from, _to, t)!;
    if (_flying) r = r.shift(Offset(0, -math.sin(math.pi * t) * 40));
    return r;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (ctx, _) {
        final r = _current;
        Widget face = TileFace(tile: widget.tile, width: r.width, height: r.height, glow: widget.glow);
        if (_flying) {
          final angle = math.pi * (1 - Curves.easeInOut.transform(_c.value));
          face = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(angle),
            child: angle > math.pi / 2
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: GoldBack(width: r.width, height: r.height))
                : face,
          );
        }
        face = TweenAnimationBuilder<double>(
          tween: Tween(end: widget.newGlow ? 1 : 0),
          duration: const Duration(milliseconds: TableTuning.newGlowFadeMs),
          builder: (_, a, child) => a <= 0
              ? child!
              : DecoratedBox(
                  key: const ValueKey('newGlow'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(r.width * .14),
                    boxShadow: [
                      BoxShadow(color: Colors.white.withValues(alpha: .95 * a), spreadRadius: 1.5),
                      BoxShadow(color: Colors.white.withValues(alpha: .7 * a), blurRadius: r.width * .35, spreadRadius: r.width * .05),
                    ],
                  ),
                  child: child,
                ),
          child: face,
        );
        if (widget.lifted) face = Transform.scale(scale: 1.06, child: face);
        return Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            onLongPressStart: (d) {
              _longDragging = true;
              _longStarted = false;
              widget.onLongPress(d.globalPosition);
            },
            onLongPressMoveUpdate: (d) {
              if (!_longStarted) {
                _longStarted = true;
                widget.onDragStart(d.globalPosition); // no-op if a drag is running
              }
              widget.onDragUpdate(d.globalPosition);
            },
            onLongPressEnd: (_) {
              if (_longDragging) widget.onDragEnd();
              _longDragging = false;
            },
            onPanStart: (d) => widget.onDragStart(d.globalPosition),
            onPanUpdate: (d) => widget.onDragUpdate(d.globalPosition),
            onPanEnd: (_) => widget.onDragEnd(),
            onPanCancel: widget.onDragEnd,
            child: face,
          ),
        );
      },
    );
  }
}

class _FlyingBack extends StatefulWidget {
  final Rect from, to;
  final VoidCallback onDone;
  const _FlyingBack({super.key, required this.from, required this.to, required this.onDone});
  @override
  State<_FlyingBack> createState() => _FlyingBackState();
}

class _FlyingBackState extends State<_FlyingBack> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: TableTuning.flyMs))
        ..forward().whenComplete(widget.onDone);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeInOutCubic.transform(_c.value);
          final r = Rect.lerp(widget.from, widget.to, t)!.shift(Offset(0, -math.sin(math.pi * t) * 30));
          return Positioned.fromRect(
            rect: r,
            child: IgnorePointer(
              child: Transform.rotate(angle: -0.14 * math.sin(math.pi * t), child: GoldBack(width: r.width, height: r.height)),
            ),
          );
        },
      );
}
