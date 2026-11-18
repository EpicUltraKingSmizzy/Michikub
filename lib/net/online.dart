import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app/avatars.dart';
import '../app/bot_roster.dart';
import '../app/keep_alive.dart';
import '../app/session.dart';
import '../engine/bot.dart';
import '../engine/host.dart';
import '../engine/rules.dart';
import 'peer.dart';

/// A seat in an online lobby.
class NetSeat {
  PlayerInfo info;
  PeerLink? link;
  NetSeat(this.info, [this.link]);
}

/// The host's side of an online game: opens a room, collects players,
/// then runs the authoritative [GameHost] and streams each guest only
/// their own view.
class NetHost extends ChangeNotifier {
  final String myName;
  HouseRules rules;
  String code = '';
  String? error;
  bool opening = true;
  BrokerNode? _node;
  final List<NetSeat> seats = [];
  GameHost? host;
  NetHostSession? session;
  int _bots = 0;
  int _guests = 0;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// [open] = false skips opening the room on the matchmaking service (tests).
  NetHost(this.myName, this.rules, {bool open = true, String? avatar}) {
    seats.add(NetSeat(PlayerInfo('host', myName, SeatKind.human, avatar: avatar)));
    if (open) {
      _open();
    } else {
      opening = false;
    }
  }

  bool _closing = false;

  /// The host's app is in the background without the keep-alive service (iOS, or Android
  /// refused it): the game is paused and guests see "Host away – game paused".
  bool away = false;

  void setAway(bool a) {
    if (a == away || _closing) return;
    away = a;
    final msg = jsonEncode({'t': a ? 'away' : 'back'});
    for (final s in seats) {
      s.link?.send(msg);
    }
    final h = host;
    if (h != null && h.result == null) {
      if (a) {
        h.pauseClock();
      } else {
        h.resumeClock();
      }
      session?.bots.paused = a;
    }
    if (!a) ensureBroker();
    notifyListeners();
  }

  /// Back from the background: if the matchmaking connection dropped meanwhile, reopen it
  /// under the same room code so guests can reconnect.
  void ensureBroker() {
    final n = _node;
    if (_closing || code.isEmpty || n == null || !n.isLost || _reopening) return;
    _reopenBroker();
  }

  bool _reopening = false;

  Future<void> _reopenBroker() async {
    _reopening = true;
    // The service may still hold the old registration for a little while: keep trying.
    for (final wait in const [0, 2, 4, 8, 15, 30, 30, 30, 60, 60]) {
      if (_closing) break;
      await Future<void>.delayed(Duration(seconds: wait));
      if (_closing) break;
      try {
        final n = await BrokerNode.open('$kPeerPrefix$code');
        _node = n;
        _subs.add(n.incoming.listen(_onLink));
        _watchBroker(n);
        netLog('room $code reopened');
        break;
      } catch (e) {
        netLog('reopen failed: $e');
      }
    }
    _reopening = false;
  }

  void _watchBroker(BrokerNode n) {
    n.lost.then((_) {
      if (!_closing && identical(n, _node) && !away) _reopenBroker();
    });
  }

  Future<void> _open() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      code = randomRoomCode();
      try {
        _node = await BrokerNode.open('$kPeerPrefix$code');
        _subs.add(_node!.incoming.listen(_onLink));
        _watchBroker(_node!);
        LinkKeepAlive.start('Hosting room $code: keeping your game connected');
        opening = false;
        error = null;
        debugPrint('Michikub room open: $code');
        notifyListeners();
        return;
      } catch (e) {
        error = '$e';
      }
    }
    opening = false;
    error ??= 'Could not open a room.';
    notifyListeners();
  }

  bool get canStart => seats.length >= 2 && (host == null || between);

  /// Between rounds the host is back in the lobby (players and rules can change; friends can
  /// join). The room, the connections and the running scores stay.
  bool between = false;

  void reopenLobby() {
    if (host?.result == null) return;
    between = true;
    _broadcastLobby();
    notifyListeners();
  }

  /// Leaves the lobby without changes (the results stay up).
  void closeLobby() {
    between = false;
    _broadcastLobby();
    notifyListeners();
  }

  /// Starts the next round with the lobby's players and rules.
  void continueGame() {
    final h = host;
    if (h == null) return;
    between = false;
    h.reconfigure([for (final s in seats) s.info], rules);
    _broadcastLobby();
    h.startRound();
    notifyListeners();
  }
  bool get full => seats.length >= 4;

  void addBot(BotLevel level) {
    if (full) return;
    _bots++;
    final used = {for (final s in seats) if (s.info.avatar != null) s.info.avatar!};
    final robot = pickRobots(1, exclude: {for (final r in robotRoster) if (used.contains(r.avatar)) r.id}).first;
    seats.add(NetSeat(PlayerInfo('bot$_bots', robot.name, SeatKind.bot, level: level, avatar: robot.avatar)));
    _broadcastLobby();
    notifyListeners();
  }

  void removeSeat(String id) {
    final s = seats.where((x) => x.info.id == id).firstOrNull;
    if (s == null || id == 'host') return;
    s.link?.send(jsonEncode({'t': 'bye', 'reason': 'The host removed you from the room.'}));
    s.link?.close();
    seats.remove(s);
    _broadcastLobby();
    notifyListeners();
  }

  void setRules(HouseRules r) {
    rules = r;
    _broadcastLobby();
    notifyListeners();
  }

  void _onLink(PeerLink link) {
    _subs.add(link.messages.listen((raw) => _onMessage(link, raw)));
    link.closed.then((_) => _onClosed(link));
  }

  void _onClosed(PeerLink link) {
    final s = seats.where((x) => x.link == link).firstOrNull;
    if (s == null) return;
    if (host == null) {
      seats.remove(s);
      _broadcastLobby();
    } else {
      s.link = null;
      host!.setConnected(s.info.id, false);
    }
    notifyListeners();
  }

  void _onMessage(PeerLink link, String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'hello':
        final name = (m['name'] as String? ?? 'Friend').trim();
        final want = m['seat'] as String?;
        // Rejoin: a dropped player gets their seat back.
        // A reconnecting phone names its seat; its old link may not have been noticed as dropped
        // yet, so the new link replaces it.
        final back = seats
            .where((x) => x.info.kind == SeatKind.remote && (x.info.id == want || x.link == null && x.info.name == name))
            .firstOrNull;
        if (back != null) {
          final old = back.link;
          back.link = link;
          if (old != null && old != link) old.close();
          host?.setConnected(back.info.id, true);
          link.send(jsonEncode({'t': 'welcome', 'id': back.info.id}));
          _broadcastLobby();
          session?.push();
          notifyListeners();
          return;
        }
        if (host != null && !between) {
          link.send(jsonEncode({'t': 'bye', 'reason': 'That game has already started.'}));
          return;
        }
        if (full) {
          link.send(jsonEncode({'t': 'bye', 'reason': 'That room is full.'}));
          return;
        }
        _guests++;
        final av = m['avatar'];
        final info = PlayerInfo('g$_guests', name.isEmpty ? 'Friend $_guests' : name, SeatKind.remote,
            avatar: av is String && isKnownAvatar(av) ? av : null);
        seats.add(NetSeat(info, link));
        link.send(jsonEncode({'t': 'welcome', 'id': info.id}));
        _broadcastLobby();
        notifyListeners();
      case 'act':
        final s = seats.where((x) => x.link == link).firstOrNull;
        final h = host;
        if (s == null || h == null) return;
        GameAction a;
        try {
          a = GameAction.fromJson((m['action'] as Map).cast<String, dynamic>());
        } catch (_) {
          return;
        }
        if (a is ReadyAction) return;
        final r = h.handle(s.info.id, a);
        link.send(jsonEncode({'t': 'result', 'req': m['req'], 'ok': r.ok, 'error': r.error}));
      case 'chat':
        final s = seats.where((x) => x.link == link).firstOrNull;
        final text = m['text'];
        if (s == null || text is! String || !isQuickChat(text)) return;
        chat(s.info.id, text, except: link);
    }
  }

  void _broadcastLobby() {
    final msg = jsonEncode({
      't': 'lobby',
      'players': [for (final s in seats) s.info.toJson()],
      'rules': rules.toJson(),
      'started': host != null,
    });
    for (final s in seats) {
      s.link?.send(msg);
    }
  }

  /// Shows a quick chat message from [from] on the host's table and every guest's (the sender's
  /// own phone, [except], already shows it).
  void chat(String from, String text, {PeerLink? except}) {
    final msg = jsonEncode({'t': 'chat', 'from': from, 'text': text});
    for (final s in seats) {
      if (s.link != null && s.link != except) s.link!.send(msg);
    }
    session?.showChat(from, text);
  }

  NetHostSession start() {
    final h = GameHost(players: [for (final s in seats) s.info], rules: rules);
    host = h;
    _broadcastLobby();
    session = NetHostSession(this, h);
    notifyListeners();
    return session!;
  }

  void sendView(NetSeat s, PlayerView v) =>
      s.link?.send(jsonEncode({'t': 'view', 'view': v.toJson()}));

  Future<void> shutdown() async {
    if (_closing) return;
    _closing = true;
    LinkKeepAlive.stop();
    for (final s in seats) {
      s.link?.send(jsonEncode({'t': 'bye', 'reason': 'The host closed the game.'}));
      await s.link?.close();
    }
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _node?.close();
  }
}

class NetHostSession extends GameSession {
  final NetHost net;
  final GameHost host;
  late final BotDriver bots;
  StreamSubscription<void>? _sub;
  PlayerView? _view;
  Timer? _skipTimer;
  int _skipTurn = -1;

  NetHostSession(this.net, this.host) {
    bots = BotDriver(host);
    _sub = host.changes.listen((_) => push());
    host.startRound();
    push();
    bots.start();
  }

  /// Sends every guest their own view and refreshes ours.
  void push() {
    for (final s in net.seats) {
      if (s.info.kind == SeatKind.remote) net.sendView(s, host.viewFor(s.info.id));
    }
    _view = host.viewFor('host');
    // A disconnected player's turn is passed after a few seconds.
    final cur = host.currentPlayer;
    if (host.result == null && host.disconnected.contains(cur.id) && _skipTurn != host.turnSeq) {
      _skipTurn = host.turnSeq;
      final seq = host.turnSeq;
      _skipTimer?.cancel();
      _skipTimer = Timer(const Duration(seconds: 5), () {
        if (host.turnSeq == seq && host.disconnected.contains(cur.id)) host.handle(cur.id, const DrawAction());
      });
    }
    notifyListeners();
  }

  @override
  PlayerView? get view => _view;
  @override
  bool get controlsRounds => true;
  @override
  bool get canChangeLineup => host.result != null;
  @override
  Future<ActionResult> act(GameAction a) async => host.handle('host', a);
  @override
  void sendChat(String text) => net.chat('host', text);
  void showChat(String from, String text) => addChat(from, text);
  @override
  void nextRound() => host.startRound();
  @override
  void leave() {
    _skipTimer?.cancel();
    _sub?.cancel();
    bots.dispose();
    host.dispose();
    net.shutdown();
  }
}

/// A friend's phone: joins a room and mirrors what the host sends.
class NetGuest extends ChangeNotifier {
  final String myName;
  final String code;
  BrokerNode? _node;
  PeerLink? link;
  String? seatId;
  String? error;
  String status = 'Connecting…';
  List<PlayerInfo> players = [];
  HouseRules rules = HouseRules.classic;
  bool started = false;
  NetGuestSession? session;
  StreamSubscription<String>? _sub;

  /// Your avatar id, sent to the host when joining.
  final String? avatar;

  NetGuest.code(this.myName, this.code, {this.avatar}) {
    LinkKeepAlive.start('Playing in room $code: keeping your game connected');
    _connectCode();
  }

  bool _closed = false;

  /// The host said goodbye (or removed us): don't reconnect.
  bool _ended = false;

  /// The host's app is in the background (and couldn't keep the game running).
  bool hostAway = false;
  bool reconnecting = false;

  static const hostAwayText = 'Host away – game paused';

  /// The link dropped: keep trying to get back in (same seat) for a few minutes. Meanwhile the
  /// table shows "Host away – game paused. Reconnecting…".
  Future<void> _reconnect() async {
    if (reconnecting || _closed || _ended) return;
    reconnecting = true;
    session?.setStatus('$hostAwayText. Reconnecting…');
    notifyListeners();
    final until = DateTime.now().add(const Duration(minutes: 5));
    while (!_closed && !_ended && DateTime.now().isBefore(until)) {
      try {
        if (_node == null || _node!.isLost) {
          await _node?.close();
          _node = await BrokerNode.open('$kPeerPrefix${code}_${randomToken(8)}');
        }
        final l = await _node!.connect('$kPeerPrefix$code', timeout: const Duration(seconds: 12));
        if (_closed) {
          await l.close();
          break;
        }
        reconnecting = false;
        _attach(l);
        session?.setStatus(hostAway ? hostAwayText : null);
        notifyListeners();
        return;
      } catch (e) {
        netLog('reconnect failed: $e');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    reconnecting = false;
    if (!_closed && !_ended) {
      error ??= 'Lost the connection to the host.';
      session?.setStatus('Connection lost. Ask the host to keep the game open and rejoin with the same name.');
      notifyListeners();
    }
  }

  Future<void> _connectCode() async {
    try {
      _node = await BrokerNode.open('$kPeerPrefix${code}_${randomToken(8)}');
      status = 'Finding room $code…';
      notifyListeners();
      final l = await _node!.connect('$kPeerPrefix$code');
      _attach(l);
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  void _attach(PeerLink l) {
    link = l;
    status = 'Connected. Waiting for the host to start…';
    _sub?.cancel();
    _sub = l.messages.listen(_onMessage);
    l.send(jsonEncode({'t': 'hello', 'name': myName, 'seat': seatId, 'avatar': avatar}));
    l.closed.then((_) {
      if (!identical(link, l) || _closed || _ended) return;
      if (seatId != null) {
        // We had a seat: try to get back in.
        _reconnect();
        return;
      }
      error ??= 'Lost the connection to the host.';
      session?.setStatus('Connection lost. Ask the host to keep the game open and rejoin with the same name.');
      notifyListeners();
    });
    notifyListeners();
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'welcome':
        seatId = m['id'] as String;
      case 'lobby':
        players = [for (final p in m['players'] as List) PlayerInfo.fromJson((p as Map).cast<String, dynamic>())];
        rules = HouseRules.fromJson((m['rules'] as Map).cast<String, dynamic>());
        started = m['started'] as bool? ?? false;
      case 'view':
        final v = PlayerView.fromJson((m['view'] as Map).cast<String, dynamic>());
        started = true;
        session ??= NetGuestSession(this);
        session!.setView(v);
      case 'result':
        session?.complete(m['req'] as int?, m['ok'] as bool? ?? false, m['error'] as String?);
      case 'chat':
        final from = m['from'], text = m['text'];
        if (from is String && text is String) session?.showChat(from, text);
      case 'bye':
        _ended = true;
        error = m['reason'] as String? ?? 'The host ended the game.';
        session?.setStatus(error);
      case 'away':
        hostAway = true;
        session?.setStatus(hostAwayText);
      case 'back':
        hostAway = false;
        session?.setStatus(null);
    }
    notifyListeners();
  }

  int _req = 0;
  int send(GameAction a) {
    _req++;
    link?.send(jsonEncode({'t': 'act', 'req': _req, 'action': a.toJson()}));
    return _req;
  }

  void sendChat(String text) => link?.send(jsonEncode({'t': 'chat', 'text': text}));

  void close() {
    _closed = true;
    LinkKeepAlive.stop();
    _sub?.cancel();
    link?.close();
    _node?.close();
  }
}

class NetGuestSession extends GameSession {
  final NetGuest guest;
  PlayerView? _view;
  String? _status;
  final Map<int, Completer<ActionResult>> _pending = {};
  NetGuestSession(this.guest);

  void setView(PlayerView v) {
    _view = v;
    notifyListeners();
  }

  void setStatus(String? s) {
    _status = s;
    notifyListeners();
  }

  void complete(int? req, bool ok, String? err) {
    final c = _pending.remove(req);
    c?.complete(ok ? const ActionResult.ok() : ActionResult.fail(err));
  }

  @override
  PlayerView? get view => _view;
  @override
  String? get status => _status;
  @override
  bool get controlsRounds => false;

  @override
  Future<ActionResult> act(GameAction a) {
    final req = guest.send(a);
    if (a is PreviewAction) return Future.value(const ActionResult.ok());
    final c = Completer<ActionResult>();
    _pending[req] = c;
    return c.future.timeout(const Duration(seconds: 10),
        onTimeout: () => const ActionResult.fail('The host did not answer.'));
  }

  @override
  void nextRound() {}
  @override
  void leave() => guest.close();

  @override
  void sendChat(String text) {
    if (!isQuickChat(text)) return;
    guest.sendChat(text);
    if (guest.seatId != null) addChat(guest.seatId!, text);
  }

  void showChat(String from, String text) => addChat(from, text);
}
