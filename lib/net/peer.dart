import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Public STUN servers. No relay (TURN) server is used, by design.
const List<Map<String, dynamic>> kIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
];

/// Free public PeerJS broker. It only passes connection details between
/// phones; no game data goes through it.
const String kBrokerHost = '0.peerjs.com';
const String kBrokerKey = 'peerjs';
const String kPeerPrefix = 'michikub-v1-';

/// One open data channel to another phone.
class PeerLink {
  final String peerId;
  final RTCPeerConnection pc;
  RTCDataChannel? _dc;
  final _messages = StreamController<String>.broadcast();
  final _open = Completer<void>();
  final _closed = Completer<void>();

  PeerLink(this.peerId, this.pc) {
    pc.onIceConnectionState = (s) => netLog('ice $s');
    pc.onConnectionState = (s) {
      netLog('pc $s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _markClosed();
      }
    };
  }

  void attach(RTCDataChannel dc) {
    _dc = dc;
    dc.onMessage = (m) => _messages.add(m.text);
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !_open.isCompleted) _open.complete();
      if (s == RTCDataChannelState.RTCDataChannelClosed) _markClosed();
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen && !_open.isCompleted) _open.complete();
  }

  void _markClosed() {
    if (!_closed.isCompleted) _closed.complete();
  }

  Stream<String> get messages => _messages.stream;
  Future<void> get opened => _open.future;
  Future<void> get closed => _closed.future;
  bool get isOpen => _dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  void send(String s) {
    final dc = _dc;
    if (dc == null || !isOpen) return;
    dc.send(RTCDataChannelMessage(s));
  }

  Future<void> close() async {
    _markClosed();
    try {
      await _dc?.close();
      await pc.close();
    } catch (_) {}
  }
}

String randomToken([int n = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = math.Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Room codes are letters only, without the look-alikes I, L and O.
String randomRoomCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ';
  final r = math.Random.secure();
  return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
}

/// A connection to the PeerJS broker, speaking its small JSON protocol
/// (OPEN, OFFER, ANSWER, CANDIDATE, HEARTBEAT). Both ends are Michikub, so
/// only the broker's relay behaviour matters.
class BrokerNode {
  final String id;
  final WebSocketChannel _ws;
  Timer? _heartbeat;
  final Map<String, PeerLink> _byConn = {};
  final Map<String, List<RTCIceCandidate>> _early = {};
  final Set<String> _remoteSet = {};
  Future<void> _queue = Future.value();
  final _incoming = StreamController<PeerLink>.broadcast();
  final _errors = StreamController<String>.broadcast();

  BrokerNode._(this.id, this._ws);

  Stream<PeerLink> get incoming => _incoming.stream;
  Stream<String> get errors => _errors.stream;

  static Future<BrokerNode> open(String id) async {
    final uri = Uri.parse(
        'wss://$kBrokerHost/peerjs?key=$kBrokerKey&id=$id&token=${randomToken()}&version=1.5.4');
    final ws = WebSocketChannel.connect(uri);
    final node = BrokerNode._(id, ws);
    final ready = Completer<void>();
    ws.stream.listen(
      (raw) {
        Map<String, dynamic> m;
        try {
          m = jsonDecode(raw as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final type = m['type'];
        if (type == 'OPEN' && !ready.isCompleted) {
          ready.complete();
        } else if (type == 'ID-TAKEN' || type == 'INVALID-KEY' || type == 'ERROR') {
          final msg = type == 'ID-TAKEN' ? 'That room code is already in use.' : 'Matchmaking error: ${m['payload']}';
          if (!ready.isCompleted) ready.completeError(msg);
          node._errors.add(msg);
        } else {
          // Handle broker messages strictly in order: a candidate must never
          // be applied before its offer or answer.
          node._queue = node._queue.then((_) => node._handle(m)).catchError((Object e) {
            netLog('broker message failed: $e');
          });
        }
      },
      onError: (e) {
        if (!ready.isCompleted) ready.completeError('Could not reach the matchmaking service.');
        node._errors.add('Matchmaking connection lost.');
      },
      onDone: () {
        if (!ready.isCompleted) ready.completeError('Could not reach the matchmaking service.');
      },
    );
    await ready.future.timeout(const Duration(seconds: 12),
        onTimeout: () => throw 'The matchmaking service did not answer.');
    node._heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => node._send({'type': 'HEARTBEAT'}));
    return node;
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  Future<void> _handle(Map<String, dynamic> m) async {
    final type = m['type'] as String?;
    final src = m['src'] as String?;
    netLog('broker $type from $src');
    final payload = (m['payload'] as Map?)?.cast<String, dynamic>();
    if (payload == null || src == null) return;
    final connId = payload['connectionId'] as String?;
    if (connId == null) return;
    switch (type) {
      case 'OFFER':
        final pc = await createPeerConnection({'iceServers': kIceServers});
        final link = PeerLink(src, pc);
        _byConn[connId] = link;
        pc.onDataChannel = link.attach;
        pc.onIceCandidate = (c) => _sendCandidate(src, connId, c);
        final sdp = (payload['sdp'] as Map).cast<String, dynamic>();
        await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String));
        await _remoteReady(connId, pc);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _send({
          'type': 'ANSWER',
          'dst': src,
          'payload': {
            'sdp': {'type': answer.type, 'sdp': answer.sdp},
            'type': 'data',
            'connectionId': connId,
            'browser': 'michikub',
          },
        });
        link.opened.then((_) => _incoming.add(link));
      case 'ANSWER':
        final link = _byConn[connId];
        if (link == null) return;
        final sdp = (payload['sdp'] as Map).cast<String, dynamic>();
        await link.pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String));
        await _remoteReady(connId, link.pc);
      case 'CANDIDATE':
        final c = (payload['candidate'] as Map?)?.cast<String, dynamic>();
        if (c == null) return;
        final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?);
        final link = _byConn[connId];
        if (link == null || !_remoteSet.contains(connId)) {
          (_early[connId] ??= []).add(cand);
          return;
        }
        await link.pc.addCandidate(cand);
    }
  }

  /// The remote description is set: apply candidates that arrived early.
  Future<void> _remoteReady(String connId, RTCPeerConnection pc) async {
    _remoteSet.add(connId);
    for (final c in _early.remove(connId) ?? const <RTCIceCandidate>[]) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        netLog('candidate failed: $e');
      }
    }
  }

  void _sendCandidate(String dst, String connId, RTCIceCandidate c) {
    if (c.candidate == null) return;
    _send({
      'type': 'CANDIDATE',
      'dst': dst,
      'payload': {
        'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
        'type': 'data',
        'connectionId': connId,
      },
    });
  }

  /// Opens a data channel to [peerId] through the broker.
  Future<PeerLink> connect(String peerId, {Duration timeout = const Duration(seconds: 20)}) async {
    final connId = 'dc_${randomToken()}';
    final pc = await createPeerConnection({'iceServers': kIceServers});
    final link = PeerLink(peerId, pc);
    _byConn[connId] = link;
    pc.onIceCandidate = (c) => _sendCandidate(peerId, connId, c);
    final dc = await pc.createDataChannel('michikub', RTCDataChannelInit()..ordered = true);
    link.attach(dc);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({
      'type': 'OFFER',
      'dst': peerId,
      'payload': {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'type': 'data',
        'connectionId': connId,
        'label': 'michikub',
        'reliable': true,
        'serialization': 'raw',
        'metadata': null,
        'browser': 'michikub',
      },
    });
    await link.opened.timeout(timeout,
        onTimeout: () => throw 'Could not connect to the host. Check the code, or try the invite-by-message option.');
    return link;
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    try {
      _ws.sink.close();
    } catch (_) {}
  }
}

void netLog(Object o) {
  if (!kReleaseMode) debugPrint('[net] $o');
}
