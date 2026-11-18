import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/bot.dart';
import '../engine/host.dart';
import '../engine/rules.dart';

/// Quick chat: the phrases and emojis a player can send (nothing else is accepted).
const kQuickChatPhrases = ['BRB', 'Well Played!', 'Nice try!', 'WOW!'];
const kQuickChatEmojis = ['😂', '😭', '🧐', '🤯', '💢', '💯', '🔥', '❤️', '👀', '💡', '🫠', '😴'];
bool isQuickChat(String text) => kQuickChatPhrases.contains(text) || kQuickChatEmojis.contains(text);

/// One quick chat message from a seat.
class ChatMsg {
  final int seq;
  final String from;
  final String text;
  const ChatMsg(this.seq, this.from, this.text);
  bool get isEmoji => kQuickChatEmojis.contains(text);
}

/// What the game table talks to. Practice and Pass-and-play run the host
/// in-process; online games go through the network sessions.
abstract class GameSession extends ChangeNotifier {
  /// The view for the seat currently using this phone.
  PlayerView? get view;

  /// Pass-and-play: the name of the player who should take the phone, or
  /// null when no cover screen is needed.
  String? get coverFor => null;
  void dismissCover() {}

  /// Pass-and-play: tiles just drawn by the player handing the phone on, shown highlighted in
  /// their rack for a moment before the cover appears (empty otherwise). No input meanwhile.
  Set<int> get revealTiles => const {};

  /// True when this phone can start the next round.
  bool get controlsRounds;

  /// The in-process host, for Test tools (null on guest phones).
  GameHost? get localHost => null;
  bool get testMenu => false;

  /// Short status line, e.g. "Connecting…" for guests.
  String? get status => null;

  Future<ActionResult> act(GameAction a);
  void nextRound();

  /// Between rounds, this phone (the host) can change the players and house rules.
  bool get canChangeLineup => false;

  /// The players and rules now (for the setup screens).
  List<PlayerInfo> get lineup => const [];
  HouseRules? get lineupRules => null;

  /// Starts the next round with [players] and [rules]; running totals carry over.
  void changeLineup(List<PlayerInfo> players, HouseRules rules) {}

  /// Quick chat messages seen on this phone, oldest first (the table shows the new ones).
  final List<ChatMsg> chats = [];
  int _chatSeq = 0;

  /// Sends a quick chat message from this phone's player (only [isQuickChat] texts).
  void sendChat(String text) {}

  /// Records a chat message from seat [from] and tells the table.
  @protected
  void addChat(String from, String text) {
    if (!isQuickChat(text)) return;
    chats.add(ChatMsg(++_chatSeq, from, text));
    if (chats.length > 50) chats.removeAt(0);
    notifyListeners();
  }
  void pause() {}
  void resume() {}
  void leave();
}

class PassPlayTuning {
  /// How long a Pass-and-play player sees the tile(s) they drew before the cover.
  static int drawRevealMs = 2500;
}

/// Practice (1 human + bots) and Pass-and-play (several humans, one phone).
class LocalSession extends GameSession {
  final GameHost host;
  late final BotDriver bots;
  final bool hotSeat;
  final bool _testMenu;
  StreamSubscription<void>? _sub;
  String _seat;
  String? _cover;
  PlayerView? _view;
  Set<int> _reveal = const {};
  Timer? _revealTimer;
  int _seenDrawSeq = 0;

  LocalSession(this.host, {required this.hotSeat, bool testMenu = false})
      : _testMenu = testMenu,
        _seat = host.players.firstWhere((p) => p.kind == SeatKind.human).id {
    bots = BotDriver(host);
    _sub = host.changes.listen((_) => _refresh());
    host.startRound();
    _seenDrawSeq = host.drawSeq;
    if (hotSeat) {
      _seat = host.currentPlayer.id;
      _cover = host.currentPlayer.name;
    }
    _refresh();
    bots.start();
  }

  void _refresh() {
    final cur = host.currentPlayer;
    if (hotSeat && host.result == null && cur.kind == SeatKind.human && cur.id != _seat && _revealTimer == null) {
      // The player handing the phone on just drew (Draw or a timeout): show them the new
      // tile(s) in their rack first, then the cover.
      final drew = host.drawPlayer == _seat && host.drawSeq != _seenDrawSeq && _view != null;
      final before = _view?.rack.toSet() ?? const <int>{};
      final fresh = drew ? (host.racks[_seat] ?? const <int>[]).where((t) => !before.contains(t)).toSet() : const <int>{};
      if (fresh.isNotEmpty && PassPlayTuning.drawRevealMs > 0) {
        _reveal = fresh;
        _revealTimer = Timer(Duration(milliseconds: PassPlayTuning.drawRevealMs), () {
          _revealTimer = null;
          _reveal = const {};
          _refresh();
        });
      } else {
        _seat = cur.id;
        _cover = cur.name;
      }
    }
    _seenDrawSeq = host.drawSeq;
    _view = host.viewFor(_seat);
    notifyListeners();
  }

  @override
  PlayerView? get view => _view;
  @override
  String? get coverFor => _cover;
  @override
  Set<int> get revealTiles => _reveal;
  @override
  void dismissCover() {
    _cover = null;
    host.handle(_seat, const ReadyAction());
    _refresh();
  }

  @override
  bool get controlsRounds => true;
  @override
  GameHost? get localHost => host;
  @override
  bool get testMenu => _testMenu;

  @override
  Future<ActionResult> act(GameAction a) async => host.handle(_seat, a);

  @override
  void sendChat(String text) => addChat(_seat, text);

  @override
  bool get canChangeLineup => host.result != null;
  @override
  List<PlayerInfo> get lineup => List.of(host.players);
  @override
  HouseRules? get lineupRules => host.rules;
  @override
  void changeLineup(List<PlayerInfo> players, HouseRules rules) {
    host.reconfigure(players, rules);
    if (hotSeat) _seat = players.first.id;
    // Bots are driven by id: the driver picks up the new seats on the next turn.
    nextRound();
  }

  @override
  void nextRound() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _reveal = const {};
    host.startRound();
    _seenDrawSeq = host.drawSeq;
    if (hotSeat) {
      _seat = host.currentPlayer.id;
      _cover = host.currentPlayer.name;
    }
    _refresh();
  }

  @override
  void pause() {
    host.pauseClock();
    bots.paused = true;
  }

  @override
  void resume() {
    host.resumeClock();
    bots.paused = false;
  }

  @override
  void leave() {
    _revealTimer?.cancel();
    _sub?.cancel();
    bots.dispose();
    host.dispose();
  }
}
