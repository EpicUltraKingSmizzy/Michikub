import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/bot_roster.dart';
import '../app/fullscreen.dart';
import '../app/keep_alive.dart';
import '../app/sfx.dart';
import '../app/prefs.dart';
import '../app/session.dart';
import '../engine/board.dart';
import '../engine/host.dart';
import '../engine/meld.dart';
import '../engine/rack_sort.dart';
import '../engine/tiles.dart';
import '../net/online.dart';
import 'avatar.dart';
import 'online_screens.dart';
import 'results.dart';
import 'setup_screens.dart';
import 'table_geo.dart';
import 'theme.dart';
import 'tiles_view.dart';

/// Tunable feel constants for the table.
class TableTuning {
  static const moveMs = 240;
  static const flyMs = 1100;

  /// The draw sound waits for the drawn tile to land in the rack (a hair early, so the
  /// sound's attack meets the landing).
  static const drawSoundDelayMs = flyMs - 30;

  /// How long the white "new on the table" glow takes to fade in or out.
  static const newGlowFadeMs = 700;

  /// The Add row (make space) button beside the rack. Off since v0.1.8; the code stays.
  static const showAddRow = false;

  /// The bright pulse around your rack when your turn starts.
  static const turnPulseMs = 650;

  /// Quick chat: how long a phrase bubble and an emoji stay up before fading out.
  static const chatTextMs = 3000;
  static const chatEmojiMs = 2000;
  static const chatFadeMs = 400;

  /// The turn-start chime waits for the deal's wash (about 1.9 s) on a round's first turn,
  /// and comes just after an opponent's draw sound when their draw starts my turn.
  static const chimeAfterDealMs = 1900;

  /// The deal at the start of a round: every seat's starting tiles fly from the pile, one at a
  /// time round the table, each flight [dealFlyMs] long, all landed within [dealSpanMs]. That
  /// is inside the deal's wash (assets/sfx/start.ogg, 1.87 s), so the chime still comes after.
  static const dealFlyMs = 420;

  /// Tests: the deal animation is off for widget tests that aren't about it
  /// (test/flutter_test_config.dart); the deal tests turn it back on.
  @visibleForTesting
  static bool dealAnimation = true;
  static const dealSpanMs = 1800;
  static const chimeAfterDrawMs = drawSoundDelayMs + 250; // After the opponent's drawn tile lands.
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

  /// The deal: the flight waits [delayMs] (the tile stays hidden), then takes [ms].
  final int delayMs;
  final int ms;
  const _Spawn(this.src, [this.seat, this.delayMs = 0, this.ms = TableTuning.flyMs]);
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

  /// A tile going back from the table to an opponent's rack (shown face up, turning face
  /// down as it lands); null for a face-down draw from the pile.
  final int? tile;

  /// The deal: the flight waits [delayMs] (not shown), then takes [ms].
  final int delayMs;
  final int ms;
  _BackFlight(this.who, this.from, this.to, [this.tile, this.delayMs = 0, this.ms = TableTuning.flyMs]);
}

class GameScreen extends StatefulWidget {
  final GameSession session;
  const GameScreen({super.key, required this.session});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
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

  /// The selected sort mode per seat (true = 789 runs, false = 777 groups): while selected,
  /// tiles entering the rack (draws, tiles taken back) re-sort it. Moving tiles by hand
  /// deselects it.
  final Map<String, bool> _sortModes = {};
  bool? get _sortMode => _sortModes[v?.me ?? ''];

  /// The round each seat's rack was last dealt and sorted for (see [_onSession]).
  final Map<String, int> _dealtRound = {};

  /// The round whose deal sound has played (once per round, even in Pass-and-play).
  int _washRound = -1;

  /// Pass-and-play: a round dealt while the "Pass to…" cover is up. Its wash and deal
  /// animation wait until the cover is tapped away.
  int? _dealPending;

  /// The deal animation is running: the table ignores input meanwhile.
  bool _dealing = false;
  Timer? _dealTimer;

  /// My turn started and its chime hasn't played yet (it waits for the pass-and-play cover).
  int? _chimeSeq;

  /// Each player's rack when their turn started (to tell a turn ended by playing tiles).
  final Map<String, Set<int>> _turnStartRacks = {};
  int _chimeDelayMs = 0;

  /// Bumped when my turn starts, to play the rack pulse.
  int _turnPulseSeq = 0;
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

  /// Quick chat: the picker is open; the latest message per seat (shown, then faded out);
  /// the last chat seq handled.
  bool _chatOpen = false;
  final Map<String, ChatMsg> _bubbles = {};
  int _chatSeen = 0;

  /// Practice / Pass-and-play paused because the app went to the background.
  bool _bgPaused = false;

  /// Practice and Pass-and-play: the turn clock (and the bots) pause while the app is in the
  /// background (or inactive, e.g. the notification shade), and carry on when it's back.
  /// Online games keep running: other phones are waiting.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ss = s;
    if (ss is NetHostSession) {
      // Hosting: with the keep-alive service (Android) the game carries on in the background.
      // Without it (iOS, or refused) it pauses and guests see "Host away – game paused".
      if (state == AppLifecycleState.resumed) {
        ss.net.setAway(false);
        ss.net.ensureBroker();
      } else if (state == AppLifecycleState.paused && !LinkKeepAlive.active) {
        ss.net.setAway(true);
      }
      return;
    }
    if (s is! LocalSession) return;
    if (state == AppLifecycleState.resumed) {
      if (_bgPaused) {
        _bgPaused = false;
        if (!_menuOpen) s.resume();
      }
    } else if (!_bgPaused) {
      _bgPaused = true;
      s.pause();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onSession);
    _onSession();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_deadline != null && _clockRunning && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_onSession);
    _ticker?.cancel();
    _toastTimer?.cancel();
    _bannerTimer?.cancel();
    _dealTimer?.cancel();
    super.dispose();
  }

  List<int> get _order => _rackOrders.putIfAbsent(v?.me ?? '', () => []);

  /// Turn sounds, from this phone's point of view:
  /// - my turn ends after I played tiles (End turn, a timeout with a valid table, or my last
  ///   tile): the bell. A turn ended by drawing only plays the draw sound (played elsewhere).
  /// - my turn starts: the chime, once the pass-and-play cover is gone. After a deal it waits
  ///   for the wash; after an opponent's draw it comes just after the draw sound.
  /// Opponents' turns make no sound of their own (only their draws do).
  void _turnSounds(PlayerView? old, PlayerView nv, bool turnChanged, bool dealtNow) {
    final drewNow = nv.drawSeq != _drawSeq && nv.drawPlayer != null;
    if (old != null && old.myTurn && turnChanged && old.round == nv.round) {
      final iDrew = drewNow && nv.drawPlayer == old.me;
      final onTable = nv.board.allTiles.toSet();
      final had = {...?_turnStartRacks[old.me], ...old.rack};
      if (!iDrew && had.any(onTable.contains)) playSfx(Sfx.turnEnd);
    }
    if (nv.myTurn && turnChanged) _turnStartRacks[nv.me] = nv.rack.toSet();
    if (nv.myTurn && turnChanged && nv.result == null) {
      _chimeSeq = nv.turnSeq;
      _chimeDelayMs = dealtNow
          ? TableTuning.chimeAfterDealMs
          : (drewNow && nv.drawPlayer != nv.me ? TableTuning.chimeAfterDrawMs : 0);
      if (s.coverFor != null) _chimeDelayMs = 0; // Played when the next player taps through.
    }
    if (_chimeSeq != null && _chimeSeq == nv.turnSeq && nv.myTurn && s.coverFor == null) {
      _chimeSeq = null;
      final seq = nv.turnSeq, me = nv.me;
      void chime() {
        final cv = v;
        if (mounted && cv != null && cv.turnSeq == seq && cv.me == me && cv.myTurn) playSfx(Sfx.turnStart);
      }
      if (_chimeDelayMs <= 0) {
        playSfx(Sfx.turnStart);
      } else {
        Timer(Duration(milliseconds: _chimeDelayMs), chime);
      }
    }
  }

  /// Tests: puts [b] on my working table (as if placed by hand).
  @visibleForTesting
  void debugSetWorking(Board b) => _setWorking(b);

  /// Tests: the table as I've arranged it this turn.
  @visibleForTesting
  Board get debugWorking => working;

  /// Tests: my rack's slots (tiles and blanks).
  @visibleForTesting
  List<int> get debugRackOrder => List.of(_order);

  void _onSession() {
    final nv = s.view;
    if (nv == null) {
      if (mounted) setState(() {});
      return;
    }
    final old = v;
    if (nv.result != null) _roundScores[nv.round] = Map.of(nv.result!.roundScores);
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
      _detached.clear();
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
    var dealtNow = false;
    if (nv.round > 0 && nv.result == null && _dealtRound[nv.me] != nv.round) {
      // A fresh deal: sorted 777 then 789, with 789 selected.
      _dealtRound[nv.me] = nv.round;
      if (_washRound != nv.round) {
        _washRound = nv.round;
        if (s.coverFor != null) {
          _dealPending = nv.round;
        } else {
          playSfx(Sfx.gameStart);
          dealtNow = true;
        }
      }
      packed = _sortedEntries(_sortedEntries(packed, false, const {}), true, const {});
      _sortModes[nv.me] = true;
    }
    var dealLate = false;
    if (_dealPending != null && s.coverFor == null) {
      // Pass-and-play: the first player tapped through the cover. The wash and the deal now.
      if (_dealPending == nv.round && nv.result == null) {
        playSfx(Sfx.gameStart);
        dealLate = true;
      }
      _dealPending = null;
    }
    final mode = _sortModes[nv.me];
    // My turn just ended (a draw, or a play): with a sort mode on, the rack is sorted (silently;
    // the shuffle sound is only for tapping 789 / 777).
    final myTurnEnded = !seatChanged && old.myTurn && turnChanged && nv.result == null;
    if ((fresh.isNotEmpty || myTurnEnded) && mode != null) {
      packed = _sortedEntries(packed, mode, nv.myTurn ? working.allTiles.toSet() : const {});
    }
    if (seatChanged && old != null && old.myTurn && nv.result == null) {
      // Pass-and-play: the previous player's turn ended and the phone moves on; sort their rack
      // now for when it's back.
      final prevMode = _sortModes[old.me];
      final prev = _rackOrders[old.me];
      if (prevMode != null && prev != null) {
        final gone = nv.board.allTiles.toSet();
        final kept = [for (final t in prev) if (!isRackGap(t) && !gone.contains(t)) t];
        prev
          ..clear()
          ..addAll(_sortedEntries(kept, prevMode, const {}));
      }
    }
    if (mode == null) packed = raiseRack(packed);
    order
      ..clear()
      ..addAll(packed);
    if (nv.myTurn && turnChanged) {
      _turnStartOrder = List.of(order);
      _turnPulseSeq++;
    }
    // Pass-and-play: the chime due as the cover goes waits for the wash this time.
    if (dealLate) _chimeDelayMs = TableTuning.chimeAfterDealMs;
    _turnSounds(old, nv, turnChanged, dealtNow);
    if (dealtNow || dealLate) _deal(nv, order);

    if (!seatChanged && !old.myTurn && old.result == null && nv.result == null && nv.round == old.round) {
      // An opponent took tiles back from the table (or reset, or drew after trying): they fly
      // from the table into their face-down rack, after any tiles they draw now.
      final who = old.currentId;
      final now = nv.board.allTiles.toSet();
      final back = [for (final t in old.board.allTiles) if (!now.contains(t) && !nv.rack.contains(t)) t];
      if (back.isNotEmpty && who != nv.me) {
        final drawing = nv.drawSeq != _drawSeq && nv.drawPlayer == who ? nv.drawCount : 0;
        _flyTilesBack(nv, who, old.board, back, drawing);
      }
    }
    if (!seatChanged) {
      if (nv.drawSeq != _drawSeq && nv.drawPlayer != null) {
        Timer(const Duration(milliseconds: TableTuning.drawSoundDelayMs), () {
          if (mounted) playSfx(Sfx.draw);
        });
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
    for (final c in s.chats.where((c) => c.seq > _chatSeen)) {
      _chatSeen = c.seq;
      _bubbles[c.from] = c;
      final ms = (c.isEmoji ? TableTuning.chatEmojiMs : TableTuning.chatTextMs) + TableTuning.chatFadeMs;
      Timer(Duration(milliseconds: ms), () {
        if (mounted && _bubbles[c.from]?.seq == c.seq) setState(() => _bubbles.remove(c.from));
      });
    }
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

  /// The deal animation: each seat's starting tiles fly from the pile, one tile per seat in
  /// turn (round the table), within [TableTuning.dealSpanMs]. My tiles fly face down and turn
  /// over into their rack slots (left to right); opponents' land in their face-down racks.
  /// No draw sound (the wash covers it). Skipped when the system asks for less motion.
  void _deal(PlayerView nv, List<int> rack) {
    if (!TableTuning.dealAnimation) return;
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) return;
    final mine = [for (final t in rack) if (!isRackGap(t)) t];
    final seats = nv.seats;
    final counts = [for (final sv in seats) sv.info.id == nv.me ? mine.length : sv.count];
    final n = seats.length;
    final most = counts.fold<int>(0, math.max);
    if (most == 0) return;
    final steps = most * n;
    final step = steps <= 1 ? 0 : (TableTuning.dealSpanMs - TableTuning.dealFlyMs) / (steps - 1);
    int delay(int seat, int i) => ((i * n + seat) * step).round();
    final meIdx = seats.indexWhere((x) => x.info.id == nv.me);
    for (var i = 0; i < mine.length; i++) {
      _spawns[mine[i]] = _Spawn(_Src.pile, null, delay(meIdx, i), TableTuning.dealFlyMs);
    }
    void backs() {
      final g = _geo;
      if (g == null || !mounted) return;
      final pos = _seatPositions(nv);
      for (var j = 0; j < n; j++) {
        final sv = seats[j];
        final p = pos[sv.info.id];
        if (sv.info.id == nv.me || p == null) continue;
        for (var i = 0; i < sv.count; i++) {
          _flights.add(_BackFlight(sv.info.id, g.pileRect, g.backRect(p, i, sv.count), null, delay(j, i), TableTuning.dealFlyMs));
        }
      }
    }

    if (_geo != null) {
      backs();
    } else {
      // The very first deal comes before the table has been laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        backs();
        if (mounted) setState(() {});
      });
    }
    _dealing = true;
    _dealTimer?.cancel();
    _dealTimer = Timer(const Duration(milliseconds: TableTuning.dealSpanMs), () {
      if (mounted) setState(() => _dealing = false);
    });
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

  /// Tiles [back] leaving the table ([from] is the table they were on) for [who]'s rack. They
  /// land in the face-down slots just before the last [after] (tiles drawn at the same time).
  void _flyTilesBack(PlayerView nv, String who, Board from, List<int> back, int after) {
    final g = _geo;
    if (g == null) return;
    final pos = _seatPositions(nv)[who];
    if (pos == null) return;
    final count = nv.seats.firstWhere((x) => x.info.id == who).count;
    final n = back.length;
    for (var i = 0; i < n; i++) {
      final at = from.find(back[i]);
      if (at == null) continue;
      final to = g.backRect(pos, count - after - n + i, count);
      _flights.add(_BackFlight(who, g.cellRect(at.row, at.col), to, back[i]));
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
  /// No reattaching: a tile taken out of a set on the table won't be joined back to that set
  /// by the assists (touching, wrong side, bridging, stranded tiles), only by a drop or tap
  /// right onto it. Each such tile maps to the tiles left in its set when it came out.
  final Map<int, Set<int>> _detached = {};

  /// The assists' check for moving [moved] now: tiles [a] may not be joined to set [b] when
  /// one holds a tile taken out of the set the other holds, earlier this turn ([_detached]) or
  /// by this very move (a tile now in a set with others, being moved out of it).
  JoinCheck _joinCheck(List<int> moved) {
    final ex = {for (final e in _detached.entries) e.key: e.value};
    final ms = moved.toSet();
    for (final t in moved) {
      final blk = working.blockOf(t);
      final mates = blk?.tiles.where((x) => !ms.contains(x)).toSet() ?? const <int>{};
      if (mates.isNotEmpty) ex[t] = mates;
    }
    bool parted(List<int> p, List<int> q) => p.any((t) => ex[t]?.any(q.contains) ?? false);
    return (a, b) => !parted(a, b) && !parted(b, a);
  }

  /// Keeps [_detached] up to date after [moved] went from [before] to [after]:
  ///  * taken out of a set of several tiles: exempt from that set (its remaining tiles);
  ///  * moved again while on its own (or with only the tiles it moved with): still exempt;
  ///  * joined to any set (including, by a direct drop or tap, its old one), or back in the
  ///    rack: no longer exempt.
  /// The turn ending or Reset clears it all.
  void _noteDetached(Board before, Board after, List<int> moved) {
    final ms = moved.toSet();
    for (final t in moved) {
      final from = before.blockOf(t);
      if (from == null) {
        _detached.remove(t);
        continue;
      }
      final mates = from.tiles.where((x) => !ms.contains(x)).toSet();
      if (mates.isNotEmpty) _detached[t] = mates;
    }
    final blk = after.blockOf(moved.first);
    if (blk == null || blk.tiles.any((x) => !ms.contains(x))) _detached.removeWhere((t, _) => ms.contains(t));
  }

  /// Tests: tiles exempt from rejoining the set they came out of.
  @visibleForTesting
  Map<int, Set<int>> get debugDetached => {for (final e in _detached.entries) e.key: {...e.value}};

  bool _setWorking(Board b, {List<int>? moved}) {
    final sent = tableTilesSentToRack(_startTiles, b);
    if (sent.isNotEmpty) {
      _flashRed([...?moved, ...sent], kTableTileToRack);
      return false;
    }
    _history.add(working);
    if (moved != null && moved.isNotEmpty) _noteDetached(working, b, moved);
    working = b;
    if (moved != null && moved.isNotEmpty) {
      // Attached to tiles already there, or set down on its own (a new set).
      final blk = b.blockOf(moved.first);
      playSfx(blk != null && blk.tiles.any((t) => !moved.contains(t)) ? Sfx.attach : Sfx.place);
    }
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
      var placed = placeInRack(_order, tiles, slot, free: onBoard);
      if (back.isEmpty) {
        // Rearranged by hand: the sort mode is deselected.
        _sortModes.remove(v?.me);
      } else if (_sortMode != null) {
        placed = _sortedEntries(placed, _sortMode!, onBoard);
      }
      if (_sortMode == null) placed = raiseRack(placed);
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
    final mayJoin = _joinCheck(tiles);
    final tmp = working.copy()..removeTiles(tiles);
    if (row < tmp.rowCount && tmp.rows[row][col] >= 0) {
      final blk = tmp.blockOf(tmp.rows[row][col])!;
      final idx = (col - blk.start) + (frac > .5 ? 1 : 0);
      return Layout.bridge(tmp, Layout.dropInto(tmp, tiles, blk.tiles.first, idx, col: col), tiles, mayJoin: mayJoin);
    }
    // Dropped right beside a set on the side it doesn't fit: it goes to the end where it does.
    final beside = row < tmp.rowCount ? Layout.dropBeside(tmp, tiles, row, col, mayJoin: mayJoin) : null;
    var placed = beside ?? Layout.place(tmp, tiles, row, col);
    // Touching a set joins it, except the set these tiles were just taken out of.
    final blk = placed.blockOf(tiles.first);
    if (blk != null && !mayJoin(tiles, blk.tiles.where((t) => !tiles.contains(t)).toList())) {
      placed = Layout.place(tmp, tiles, row, col, merge: false);
    }
    return Layout.bridge(tmp, placed, tiles, mayJoin: mayJoin);
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
    final mayJoin = _joinCheck(sel);
    final tmp = working.copy()..removeTiles(sel);
    final blk = tmp.blockOf(target);
    if (blk == null) return;
    // The end nearer the tap when both ends work.
    final at = Layout.attachEnd(blk.tiles, sel, blk.tiles.indexOf(target), allowPartial: true);
    if (at != null) {
      _groupSel = false;
      _setWorking(Layout.bridge(tmp, Layout.insertInto(tmp, sel, blk.tiles.first, at), sel, mayJoin: mayJoin), moved: sel);
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
      final mayJoin = _joinCheck(sel);
      final tmp = working.copy()..removeTiles(sel);
      _setWorking(Layout.bridge(tmp, Layout.place(working, sel, c.row, c.col, merge: false), sel, mayJoin: mayJoin), moved: sel);
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
      setState(() {
        _selected.clear();
        _groupSel = false;
      });
      return;
    }
    var order = [for (final e in _order) back.contains(e) ? newRackBlank() : e];
    for (final t in back) {
      order = addToRack(order, t);
    }
    if (_sortMode != null) order = _sortedEntries(order, _sortMode!, working.allTiles.toSet().difference(back.toSet()));
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
    // Picking up a whole set (3+ tiles) by long-press: a burst of clicks.
    if (_longPressing && tiles.length >= 3) playSfx(Sfx.pick);
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
    _detached.clear();
    _selected.clear();
    final rack = v!.rack.toSet();
    var restored = [for (final t in _turnStartOrder) isRackGap(t) || rack.contains(t) ? t : newRackBlank()];
    final returned = v!.rack.where((t) => !restored.contains(t)).toList();
    for (final t in returned) {
      restored = addToRack(restored, t);
    }
    if (returned.isNotEmpty && _sortMode != null) restored = _sortedEntries(restored, _sortMode!, const {});
    _order
      ..clear()
      ..addAll(trimRack(restored));
    s.act(PreviewAction(working));
    _haptic();
    setState(() {});
  }

  /// 789 / 777: valid sets of 3+ to the top left (each followed by a blank slot), then the rest
  /// sorted. This packs the rack (no other blanks); a set doesn't straddle the row break.
  /// Sorts now and selects that mode (see [_sortModes]).
  /// The 789 / 777 buttons: sorts with the shuffle sound (automatic sorts are silent).
  void _sortByHand(bool runs) {
    playSfx(Sfx.sort);
    _sort(runs);
  }

  void _sort(bool runs) {
    final sorted = _sortedEntries(_order, runs, _myTurn ? working.allTiles.toSet() : const {});
    _sortModes[v?.me ?? ''] = runs;
    _order
      ..clear()
      ..addAll(sorted);
    _haptic();
    setState(() {});
  }

  /// [entries] sorted (789 when [runs], else 777); tiles out on the table this turn
  /// ([onBoard]) keep slots after the sorted ones (for Reset).
  static List<int> _sortedEntries(List<int> entries, bool runs, Set<int> onBoard) {
    final rack = keepSetsOnRows(sortRackWithSets(entries.where((t) => !isRackGap(t) && !onBoard.contains(t)).toList(), runs: runs));
    return [...rack, ...entries.where(onBoard.contains)];
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
                if (Fullscreen.supported) ...[
                  const SizedBox(height: 10),
                  ValueListenableBuilder<bool>(
                    valueListenable: Fullscreen.active,
                    builder: (_, on, _) => GoldButton(on ? 'Exit full screen' : 'Full screen',
                        key: const ValueKey('menuFullscreen'),
                        icon: on ? Icons.fullscreen_exit : Icons.fullscreen,
                        crimson: true,
                        onPressed: Fullscreen.toggle),
                  ),
                ],
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
    if (mounted && !_bgPaused) s.resume();
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
              // Measured the way Text lays them out: the ambient style (its line height) and text scale.
              final scaler = MediaQuery.textScalerOf(ctx);
              final base = DefaultTextStyle.of(ctx).style;
              final sideW = TableGeo.sideWFor(cons.biggest.width);
              final g = TableGeo(cons.biggest,
                  sidePlateH: _sidePlateHeights(pv, sideW, base, scaler),
                  pileLabelH: _pileLabelHeight(base, scaler),
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
                  if (_turnPulseSeq > 0) _turnPulse(g),
                  ..._seats(g, pv),
                  ..._cornerButtons(g),
                  ..._myCorner(g, pv),
                  _pile(g, pv),
                  ..._controls(g, pv),
                  ..._sprites(g, pv, rack),
                  for (final f in _flights)
                    _FlyingBack(
                      key: f.key,
                      from: f.from,
                      to: f.to,
                      tile: f.tile,
                      delayMs: f.delayMs,
                      ms: f.ms,
                      onDone: () => setState(() => _flights.remove(f)),
                    ),
                  // The deal: the table ignores input until every tile has landed.
                  if (_dealing) const Positioned.fill(child: AbsorbPointer(key: ValueKey('dealBlock'), child: SizedBox.expand())),
                  ..._chatBubbles(g, pv),
                  if (_chatOpen) ..._chatPicker(g),
                  if (_toast != null) _toastWidget(g),
                  if (_starterBanner != null && pv.result == null && s.coverFor == null) _starterBannerWidget(g, _starterBanner!),
                  if (s.status != null) _statusBanner(g, s.status!),
                  if (pv.result != null && !_resultsHidden)
                    Positioned.fill(
                        child: ResultsOverlay(
                            session: s,
                            view: pv,
                            onLeave: _leave,
                            onMinimize: () => setState(() => _resultsHidden = true),
                            onChangeLineup: s.canChangeLineup ? _changeLineup : null)),
                  if (pv.result != null && _resultsHidden)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: GoldButton('Show results', icon: Icons.emoji_events, onPressed: () => setState(() => _resultsHidden = false)),
                    ),
                  // Pass-and-play: the drawn tiles are on show; the turn is over, so no input.
                  if (s.revealTiles.isNotEmpty) const Positioned.fill(child: AbsorbPointer()),
                  if (_scoresOpen && s.coverFor == null) _scoresOverlay(pv),
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
      // Left of the rack, top down: Add row (Make space, hidden: TableTuning.showAddRow), then
      // the 789 and 777 sort buttons.
      Positioned(
        left: g.rackRect.left - 58,
        top: math.min(g.rackRect.top + 2, g.size.height - (TableTuning.showAddRow ? 3 : 2) * 52 - 6),
        width: 46,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (TableTuning.showAddRow) ...[
            Tooltip(
              message: 'Add a row (make space)',
              child: RingButton(
                size: 46,
                onPressed: _myTurn ? _makeSpace : null,
                child: const Icon(Icons.unfold_more_double, color: MK.goldLight, size: 38),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Tooltip(
            message: 'Sort: sets first, then runs order',
            child: RingButton(
                key: const ValueKey('sort789'), size: 46, selected: _sortMode == true, onPressed: () => _sortByHand(true), child: _sortLabel('789', _sortMode == true)),
          ),
          const SizedBox(height: 6),
          Tooltip(
            message: 'Sort: sets first, then groups order',
            child: RingButton(
                key: const ValueKey('sort777'), size: 46, selected: _sortMode == false, onPressed: () => _sortByHand(false), child: _sortLabel('777', _sortMode == false)),
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
    // A person may pick a robot's picture; only bots show a robot's profile.
    final robot = sv.info.kind == SeatKind.bot ? robotByAvatar(sv.info.avatar) : null;
    return PlayerAvatar(
      size: size,
      name: sv.info.name,
      image: sv.info.avatar,
      color: seatColors[idx % seatColors.length],
      current: current,
      onLongPress: robot == null ? null : () => _showRobot(sv, robot),
    );
  }

  /// Between rounds, the host goes back to the players and rules screen: the lobby online, or
  /// the Practice / Pass-and-play setup. Its Next round button continues this game (same room,
  /// same connections, running totals kept).
  void _changeLineup() {
    final ss = s;
    final Widget screen;
    if (ss is NetHostSession) {
      ss.net.reopenLobby();
      screen = HostLobbyScreen(net: ss.net, betweenRounds: true);
    } else if (ss is LocalSession) {
      screen = ss.hotSeat ? HotSeatSetupScreen(resume: ss) : PracticeSetupScreen(resume: ss);
    } else {
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Where my own avatar is (bottom-left corner), matching [_myCorner].
  Rect _myAvatarRect(TableGeo g) {
    final a = g.avatar * 1.1;
    return Rect.fromLTWH(10, g.size.height - 8 - a, a, a);
  }

  /// Quick chat picker: across my rack area (covering as little of the table as it can), with
  /// the phrases, the emojis and a close button. Tapping outside closes it; sending closes it.
  List<Widget> _chatPicker(TableGeo g) {
    final w = g.size.width;
    final left = math.max(8.0, g.rackRect.left - 60);
    final right = math.min(w - 8, g.rackRect.right + 60);
    final h = math.max(g.rackRect.height + 6, 92.0);
    void close() => setState(() => _chatOpen = false);
    void send(String t) {
      s.sendChat(t);
      close();
    }

    Widget chip(String t, {bool emoji = false}) => Padding(
          padding: const EdgeInsets.all(2),
          child: Material(
            color: emoji ? Colors.transparent : const Color(0xFF3A160C),
            shape: emoji ? const CircleBorder() : StadiumBorder(side: BorderSide(color: MK.gold.withValues(alpha: .8))),
            child: InkWell(
              key: ValueKey('chat:$t'),
              customBorder: emoji ? const CircleBorder() : const StadiumBorder(),
              onTap: () => send(t),
              child: Padding(
                padding: emoji ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(t, style: emoji ? const TextStyle(fontSize: 24, height: 1.1) : MK.body(14, weight: FontWeight.w700, color: MK.goldLight)),
              ),
            ),
          ),
        );

    return [
      Positioned.fill(
        child: GestureDetector(key: const ValueKey('chatBarrier'), behavior: HitTestBehavior.opaque, onTap: close),
      ),
      Positioned(
        left: left,
        width: right - left,
        bottom: 2,
        height: h,
        child: Container(
          key: const ValueKey('chatPicker'),
          decoration: BoxDecoration(
            color: const Color(0xF21A0805),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MK.gold, width: 1.2),
            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 14)],
          ),
          padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Wrap(children: [for (final t in kQuickChatPhrases) chip(t)]),
                  Wrap(children: [for (final t in kQuickChatEmojis) chip(t, emoji: true)]),
                ]),
              ),
            ),
            IconButton(key: const ValueKey('chatClose'), onPressed: close, icon: const Icon(Icons.close, color: MK.goldLight)),
          ]),
        ),
      ),
    ];
  }

  /// Chat messages beside each player's avatar: phrases in a speech bubble (3 s), emojis on
  /// their own (2 s), then a short fade. Right seat: to the left of the avatar; left seat: to
  /// the right; top seat: below; me: above my avatar.
  List<Widget> _chatBubbles(TableGeo g, PlayerView pv) {
    final out = <Widget>[];
    final pos = _seatPositions(pv);
    for (final c in _bubbles.values) {
      final Rect av;
      final SeatPos? p = pos[c.from];
      if (c.from == pv.me) {
        av = _myAvatarRect(g);
      } else if (p != null) {
        av = Rect.fromCenter(center: g.seatCenter(p), width: g.avatar, height: g.avatar);
      } else {
        continue;
      }
      final body = c.isEmoji
          ? Text(c.text, style: const TextStyle(fontSize: 30, height: 1.1))
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6DC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MK.gold, width: 1.2),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Text(c.text, maxLines: 1, style: MK.body(14, weight: FontWeight.w800, color: const Color(0xFF2A1404))),
            );
      final total = (c.isEmoji ? TableTuning.chatEmojiMs : TableTuning.chatTextMs) + TableTuning.chatFadeMs;
      final faded = TweenAnimationBuilder<double>(
        key: ValueKey('chatAnim${c.seq}'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: total),
        builder: (_, t, child) {
          final fadeFrom = 1 - TableTuning.chatFadeMs / total;
          return Opacity(opacity: t < fadeFrom ? 1 : ((1 - t) / (1 - fadeFrom)).clamp(0.0, 1.0), child: child);
        },
        child: IgnorePointer(child: KeyedSubtree(key: ValueKey('chat-${c.from}'), child: body)),
      );
      const gap = 6.0;
      final w = g.size.width, h = g.size.height;
      if (c.from == pv.me) {
        out.add(Positioned(left: av.left, bottom: h - av.top + 46, child: faded));
      } else if (p == SeatPos.right) {
        out.add(Positioned(right: w - av.left + gap + 8, top: av.center.dy - 16, child: faded));
      } else if (p == SeatPos.left) {
        out.add(Positioned(left: av.right + gap + 8, top: av.center.dy - 16, child: faded));
      } else {
        out.add(Positioned(left: av.left - 10, top: av.bottom + gap + 4, child: faded));
      }
    }
    return out;
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
          _countBadge(shown, key: ValueKey('count-${sv.info.id}')),
        ]),
      ));
      // The name plate: the name, then the turn clock on its own line (kept even when it's not
      // their turn, so nothing moves), so a long name can't push the clock out of view.
      final label = _seatLabel(sv);
      final timed = _timed(pv);
      final clock = current ? _clockText() : '';
      if (p == SeatPos.top) {
        out.add(Positioned(
          left: c.dx - a / 2 - 120,
          width: 112,
          top: c.dy - (timed ? 17 : 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(label, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: MK.body(12, weight: FontWeight.w600)),
            if (timed) Text(clock.isEmpty ? ' ' : clock, key: ValueKey('clock-${sv.info.id}'), maxLines: 1, style: MK.body(12, weight: FontWeight.w700)),
          ]),
        ));
      } else {
        out.add(Positioned(
          left: c.dx - g.sideW / 2,
          width: g.sideW,
          top: g.plateTop(p),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sidePlateStyle),
            if (timed)
              Text(clock.isEmpty ? ' ' : clock, key: ValueKey('clock-${sv.info.id}'), textAlign: TextAlign.center, maxLines: 1, style: _sideClockStyle),
          ]),
        ));
      }
      for (var i = 0; i < shown; i++) {
        final r = g.backRect(p, i, sv.count);
        out.add(Positioned.fromRect(rect: r, child: GoldBack(width: r.width, height: r.height)));
      }
    }
    return out;
  }

  /// A seat's name plate: name, offline mark, and the turn clock ([clock]) when it's their turn.
  static String _seatLabel(SeatView sv) => '${sv.info.name}${sv.connected ? '' : ' (offline)'}';

  /// Whether turns have a clock (its line is kept on every opponent's name plate).
  bool _timed(PlayerView pv) => pv.rules.turnSeconds > 0 || _deadline != null;

  static final _sidePlateStyle = MK.body(11, weight: FontWeight.w600);
  static final _sideClockStyle = MK.body(11, weight: FontWeight.w700);

  /// Height of each side seat's name plate (the name, up to 2 lines, then the clock line when
  /// turns are timed), so its face-down rack starts below all of it.
  Map<SeatPos, double> _sidePlateHeights(PlayerView pv, double width, TextStyle base, TextScaler scaler) {
    final out = <SeatPos, double>{};
    final pos = _seatPositions(pv);
    final timed = _timed(pv);
    var clockH = 0.0;
    if (timed) {
      final cp = TextPainter(text: TextSpan(text: '0:00', style: base.merge(_sideClockStyle)), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout();
      clockH = cp.height;
      cp.dispose();
    }
    for (final sv in pv.seats) {
      final p = pos[sv.info.id];
      if (p == null || p == SeatPos.top) continue;
      final tp = TextPainter(
        text: TextSpan(text: _seatLabel(sv), style: base.merge(_sidePlateStyle)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: width);
      out[p] = tp.height + clockH;
      tp.dispose();
    }
    return out;
  }

  /// Height of the pile's count text ("48" over "IN PILE").
  static double _pileLabelHeight(TextStyle base, TextScaler scaler) {
    var h = 0.0;
    for (final (t, st) in [('88', MK.body(17, weight: FontWeight.w700)), ('IN PILE', MK.body(8, color: MK.gold, weight: FontWeight.w700))]) {
      final tp = TextPainter(text: TextSpan(text: t, style: base.merge(st)), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
      h += tp.height;
      tp.dispose();
    }
    return h;
  }

  /// Menu (top-left corner) and the Round button (left of the pile, opens the scores), the
  /// size of the 777/789 sort buttons.
  List<Widget> _cornerButtons(TableGeo g) => [
        Positioned.fromRect(
          rect: g.menuRect,
          child: Tooltip(
            message: 'Menu',
            child: RingButton(key: const ValueKey('menuButton'), size: TableGeo.cornerBtn, icon: Icons.menu, onPressed: _openMenu),
          ),
        ),
        Positioned.fromRect(
          rect: g.roundRect,
          child: Tooltip(
            message: 'Scores',
            child: RingButton(
              key: const ValueKey('roundButton'),
              size: TableGeo.cornerBtn,
              selected: _scoresOpen,
              onPressed: () => setState(() => _scoresOpen = !_scoresOpen),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('ROUND', style: MK.body(7.5, color: _scoresOpen ? Colors.black : MK.gold, weight: FontWeight.w700).copyWith(height: 1.0)),
                Text('${v!.round}', style: MK.body(17, color: _scoresOpen ? Colors.black : MK.goldLight, weight: FontWeight.w800).copyWith(height: 1.05)),
              ]),
            ),
          ),
        ),
      ];

  /// The scores overlay (from the Round button): each player's score per round (rounds seen
  /// on this device) and running total. A tap anywhere closes it.
  bool _scoresOpen = false;
  final Map<int, Map<String, int>> _roundScores = {};

  Widget _scoresOverlay(PlayerView pv) {
    final rounds = (_roundScores.keys.toList()..sort());
    final shown = rounds.length > 6 ? rounds.sublist(rounds.length - 6) : rounds;
    final rows = [...pv.seats]..sort((a, b) => b.total - a.total);
    Widget cell(String t, {bool head = false, bool right = true, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Text(t,
              textAlign: right ? TextAlign.right : TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: head ? MK.body(11, color: MK.gold, weight: FontWeight.w700) : MK.body(14, weight: FontWeight.w700, color: color ?? MK.creamText)),
        );
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey('scoresOverlay'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _scoresOpen = false),
        child: Container(
          color: const Color(0x990B0705),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: MkPanel(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Scores after ${pv.result != null ? 'round ${pv.round}' : '${pv.round - 1} round${pv.round == 2 ? '' : 's'}'}',
                      style: MK.title(20)),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: {0: const FlexColumnWidth(3), for (var i = 1; i <= shown.length + 1; i++) i: const FlexColumnWidth(1.3)},
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(children: [cell('Player', head: true, right: false), for (final r in shown) cell('R$r', head: true), cell('Total', head: true)]),
                      for (final s in rows)
                        TableRow(children: [
                          cell(s.info.name + (s.info.id == pv.me ? ' (you)' : ''), right: false),
                          for (final r in shown) cell(_signedScore(_roundScores[r]![s.info.id])),
                          cell('${s.total}', color: MK.goldLight),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Tap anywhere to close', style: MK.body(11, color: MK.gold)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _signedScore(int? n) => n == null ? '–' : (n > 0 ? '+$n' : '$n');

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
              GestureDetector(
                key: const ValueKey('myAvatar'),
                onTap: () => setState(() => _chatOpen = true),
                child: _avatar(me, a, current: my),
              ),
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
          key: const ValueKey('pile'),
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
    return [
      // Reset in the bottom-right corner; Draw / End turn stretched from the rack to it.
      Positioned.fromRect(
        rect: g.resetRect,
        child: Tooltip(
          message: 'Reset: take back this turn',
          child: RingButton(
              key: const ValueKey('resetButton'),
              size: TableGeo.cornerBtn,
              icon: Icons.restart_alt,
              caption: 'RESET',
              onPressed: _canReset ? _resetTurn : null),
        ),
      ),
      Positioned.fromRect(
        rect: g.drawRect,
        child: GoldButton(
            my ? (played ? 'End turn' : (pv.pile > 0 ? 'Draw' : 'Pass')) : 'Waiting...',
            // Narrow phones (under 115 px between the rack and Reset): the label alone.
            icon: g.drawRect.width < 115 ? null : (my ? (played ? Icons.check_circle_outline : Icons.add_box_outlined) : Icons.hourglass_empty),
            compact: true,
            onPressed: my ? _drawOrEnd : null,
            // No click: drawing plays the draw sound and ending a turn the bell (see _turnSounds).
            sound: false,
            key: const ValueKey('drawButton'),
          ),
      ),
    ];
  }

  Widget _sortLabel(String text, bool selected) =>
      Text(text, style: MK.body(15, color: selected ? Colors.black : MK.goldLight, weight: FontWeight.w800).copyWith(height: 1.0));

  /// A brief bright pulse around the rack when my turn starts.
  /// Keyed so it keeps its animation when the widgets before it change (drop hints appear
  /// while dragging): unkeyed, it was rebuilt and the pulse played again.
  Widget _turnPulse(TableGeo g) => Positioned.fromRect(
        key: ValueKey('turnPulseBox$_turnPulseSeq'),
        rect: g.rackRect.inflate(8),
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('turnPulse$_turnPulseSeq'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: TableTuning.turnPulseMs),
            builder: (_, t, _) {
              // Quick rise, softer fade.
              final a = t < .2 ? t / .2 : math.pow(1 - (t - .2) / .8, 1.6).toDouble();
              if (a <= 0) return const SizedBox.shrink();
              return DecoratedBox(
                key: const ValueKey('turnPulse'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withValues(alpha: .22 * a),
                  boxShadow: [BoxShadow(color: const Color(0xFFFFF3C4).withValues(alpha: .85 * a), blurRadius: 34, spreadRadius: 8)],
                ),
              );
            },
          ),
        ),
      );

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
      out.add(_sprite(t, g.rackSlot(i), spawnRect(t), glow(t), board: false, spawn: _spawns[t]));
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

  Widget _sprite(int t, Rect rect, Rect? from, TileGlow glow,
      {required bool board, bool instant = false, bool lifted = false, bool newGlow = false, _Spawn? spawn}) {
    return _TileSprite(
      key: ValueKey(t),
      tile: t,
      newGlow: newGlow,
      rect: rect,
      spawnFrom: from,
      spawnDelayMs: spawn?.delayMs ?? 0,
      spawnMs: spawn?.ms ?? TableTuning.flyMs,
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

  /// Messages sit in the strip above the board, their bottom edge just above the top board
  /// row, so they never cover a table tile (they may cover the top seat's avatar and backs).
  /// A long message wraps upward.
  Widget _toastWidget(TableGeo g) => Positioned(
        bottom: g.size.height - math.min(g.boardRect.top, g.boardOrigin.dy) + 2,
        // Centred, clear of the Round button (left of the pile) and the Menu button.
        left: math.max(g.boardRect.left, g.size.width - g.roundRect.left + 6),
        right: math.max(g.boardRect.left, g.size.width - g.roundRect.left + 6),
        child: IgnorePointer(
          child: Center(
            child: Container(
              key: const ValueKey('toast'),
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

  /// A spawn flight's wait (the tile is hidden meanwhile) and length (the deal's are short).
  final int spawnDelayMs;
  final int spawnMs;
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
    this.spawnDelayMs = 0,
    this.spawnMs = TableTuning.flyMs,
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
    _from = widget.rect;
    if (widget.spawnFrom != null) _spawn();
  }

  /// Flies in from [_TileSprite.spawnFrom], after [_TileSprite.spawnDelayMs] (hidden until then).
  bool _waiting = false;
  Timer? _wait;
  void _spawn() {
    final from = widget.spawnFrom!;
    void go() {
      if (!mounted) return;
      void apply() {
        _waiting = false;
        _from = from;
        _to = widget.rect;
        _flying = true;
      }

      if (_waiting) {
        setState(apply);
      } else {
        apply();
      }
      _c.duration = Duration(milliseconds: widget.spawnMs);
      _c.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _flying = false);
      });
    }

    _wait?.cancel();
    if (widget.spawnDelayMs > 0) {
      _waiting = true;
      _wait = Timer(Duration(milliseconds: widget.spawnDelayMs), go);
    } else {
      go();
    }
  }

  @override
  void didUpdateWidget(covariant _TileSprite old) {
    super.didUpdateWidget(old);
    if (widget.spawnFrom != null && old.spawnFrom == null) {
      // A tile already on screen dealt again (a new round): it flies in from the pile.
      _to = widget.rect;
      _spawn();
      return;
    }
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
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_waiting) return Positioned.fromRect(rect: widget.rect, child: const SizedBox.shrink());
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
  final int? tile;
  final VoidCallback onDone;
  final int delayMs, ms;
  const _FlyingBack(
      {super.key, required this.from, required this.to, required this.onDone, this.tile, this.delayMs = 0, this.ms = TableTuning.flyMs});
  @override
  State<_FlyingBack> createState() => _FlyingBackState();
}

class _FlyingBackState extends State<_FlyingBack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));
  Timer? _wait;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    void go() {
      if (!mounted) return;
      if (_waiting) setState(() => _waiting = false);
      _c.forward().whenComplete(widget.onDone);
    }

    if (widget.delayMs > 0) {
      _waiting = true;
      _wait = Timer(Duration(milliseconds: widget.delayMs), go);
    } else {
      go();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _waiting
      ? const Positioned(left: 0, top: 0, child: SizedBox.shrink())
      : AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeInOutCubic.transform(_c.value);
          final r = Rect.lerp(widget.from, widget.to, t)!.shift(Offset(0, -math.sin(math.pi * t) * 30));
          return Positioned.fromRect(
            rect: r,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.14 * math.sin(math.pi * t),
                // A tile from the table shows its face until it's nearly home.
                child: widget.tile != null && t < .75
                    ? TileFace(key: const ValueKey('flyingFace'), tile: widget.tile!, width: r.width, height: r.height)
                    : GoldBack(width: r.width, height: r.height),
              ),
            ),
          );
        },
      );
}
