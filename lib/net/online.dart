import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

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
  PeerLink? _pendingManual;

  NetHost(this.myName, this.rules) {
    seats.add(NetSeat(PlayerInfo('host', myName, SeatKind.human)));
    _open();
  }

  Future<void> _open() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      code = randomRoomCode();
      try {
        _node = await BrokerNode.open('$kPeerPrefix$code');
        _subs.add(_node!.incoming.listen(_onLink));
        opening = false;
        error = null;
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

  bool get canStart => seats.length >= 2 && host == null;
  bool get full => seats.length >= 4;

  void addBot(BotLevel level) {
    if (full) return;
    _bots++;
    seats.add(NetSeat(PlayerInfo('bot$_bots', 'Bot $_bots', SeatKind.bot, level: level)));
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
        final back = seats.where((x) => x.link == null && x.info.kind == SeatKind.remote && (x.info.id == want || x.info.name == name)).firstOrNull;
        if (back != null) {
          back.link = link;
          host?.setConnected(back.info.id, true);
          link.send(jsonEncode({'t': 'welcome', 'id': back.info.id}));
          _broadcastLobby();
          session?.push();
          notifyListeners();
          return;
        }
        if (host != null) {
          link.send(jsonEncode({'t': 'bye', 'reason': 'That game has already started.'}));
          return;
        }
        if (full) {
          link.send(jsonEncode({'t': 'bye', 'reason': 'That room is full.'}));
          return;
        }
        _guests++;
        final info = PlayerInfo('g$_guests', name.isEmpty ? 'Friend $_guests' : name, SeatKind.remote);
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

  /// Copy-and-paste invite for one friend (no matchmaking service).
  Future<String> createManualInvite() async {
    final (text, link) = await ManualSignal.createInvite();
    _pendingManual = link;
    return text;
  }

  Future<void> acceptManualReply(String reply) async {
    final link = _pendingManual;
    if (link == null) throw 'Make an invite first.';
    await ManualSignal.acceptReply(link, reply);
    _pendingManual = null;
    await link.opened.timeout(const Duration(seconds: 20), onTimeout: () => throw 'The connection did not open.');
    _onLink(link);
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
  Future<ActionResult> act(GameAction a) async => host.handle('host', a);
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

  NetGuest.code(this.myName, this.code) {
    _connectCode();
  }

  NetGuest.manual(this.myName, PeerLink l) : code = '' {
    status = 'Waiting for the host to paste your reply…';
    l.opened.then((_) => _attach(l));
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
    _sub = l.messages.listen(_onMessage);
    l.send(jsonEncode({'t': 'hello', 'name': myName, 'seat': seatId}));
    l.closed.then((_) {
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
      case 'bye':
        error = m['reason'] as String? ?? 'The host ended the game.';
        session?.setStatus(error);
    }
    notifyListeners();
  }

  int _req = 0;
  int send(GameAction a) {
    _req++;
    link?.send(jsonEncode({'t': 'act', 'req': _req, 'action': a.toJson()}));
    return _req;
  }

  void close() {
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
}
