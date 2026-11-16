import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/prefs.dart';
import '../engine/host.dart';
import '../net/online.dart';
import '../net/peer.dart';
import 'game_screen.dart';
import 'rules_editor.dart';
import 'setup_screens.dart';
import 'theme.dart';

class HostLobbyScreen extends StatefulWidget {
  const HostLobbyScreen({super.key});
  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  final prefs = AppPrefs.instance;
  late final NetHost net = NetHost(prefs.name, prefs.rules)..addListener(_changed);
  bool _started = false;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    net.removeListener(_changed);
    if (!_started) net.shutdown();
    super.dispose();
  }

  Future<void> _manualInvite() async {
    String? invite;
    String? err;
    final replyCtl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        if (invite == null && err == null) {
          net.createManualInvite().then((t) => setD(() => invite = t)).catchError((Object e) {
            setD(() => err = '$e');
          });
        }
        return AlertDialog(
          title: Text('Invite by message', style: MK.title(20)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('1. Copy this invite and send it to one friend in any chat app.', style: MK.body(13)),
                const SizedBox(height: 6),
                if (err != null) Text(err!, style: MK.body(12, color: MK.danger)),
                if (invite == null && err == null) const LinearProgressIndicator(),
                if (invite != null)
                  GoldButton('Copy invite', icon: Icons.copy, compact: true, onPressed: () {
                    Clipboard.setData(ClipboardData(text: invite!));
                  }),
                const SizedBox(height: 12),
                Text('2. Paste the reply they send back:', style: MK.body(13)),
                const SizedBox(height: 6),
                TextField(controller: replyCtl, maxLines: 3, decoration: const InputDecoration(hintText: 'MICHIKUB-REPLY:…')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            TextButton(
              onPressed: () async {
                try {
                  await net.acceptManualReply(replyCtl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setD(() => err = '$e');
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: 'Host a game',
      actions: [
        Text(net.canStart ? '' : 'Need 2+ players  ', style: MK.body(12, color: MK.gold)),
        GoldButton('Start game', icon: Icons.play_arrow, compact: true, onPressed: net.canStart
              ? () {
                  _started = true;
                  final session = net.start();
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
                }
              : null),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Room code', style: MK.body(13, color: MK.gold)),
                if (net.opening)
                  Text('Opening…', style: MK.title(30))
                else if (net.error != null && net.code.isEmpty || net.error != null && net.seats.length == 1 && net.opening)
                  Text('—', style: MK.title(30))
                else
                  SelectableText(net.code, style: MK.title(40).copyWith(color: MK.goldLight, letterSpacing: 6)),
                if (net.error != null) Text(net.error!, style: MK.body(12, color: MK.danger)),
                Text('Friends tap Join a game and type this code. Only connection details pass through the free matchmaking service.',
                    style: MK.body(11, color: MK.gold)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(children: [
              GoldButton('Copy code', icon: Icons.copy, compact: true, onPressed: net.code.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: net.code))),
              const SizedBox(height: 8),
              GoldButton('Invite by message', icon: Icons.message_outlined, compact: true, crimson: true, onPressed: net.full ? null : _manualInvite),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Players (${net.seats.length}/4)', style: MK.body(15, weight: FontWeight.w700)),
            for (final s in net.seats)
              ListTile(
                dense: true,
                leading: Icon(
                    s.info.kind == SeatKind.bot ? Icons.smart_toy_outlined : (s.info.id == 'host' ? Icons.star : Icons.person),
                    color: MK.goldLight),
                title: Text(s.info.name + (s.info.id == 'host' ? ' (you, host)' : ''), style: MK.body(14)),
                subtitle: s.info.kind == SeatKind.bot ? Text(levelName(s.info.level), style: MK.body(11, color: MK.gold)) : null,
                trailing: s.info.id == 'host'
                    ? null
                    : IconButton(icon: const Icon(Icons.close, color: MK.gold), onPressed: () => net.removeSeat(s.info.id)),
              ),
            Wrap(spacing: 8, children: [
              for (final l in BotLevel.values)
                TextButton.icon(
                  onPressed: net.full ? null : () => net.addBot(l),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Add ${levelName(l)} bot'),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        MkPanel(
          child: RulesEditor(
            rules: net.rules,
            onChanged: (r) {
              net.setRules(r);
              prefs.rules = r;
              prefs.save();
            },
          ),
        ),
      ]),
    );
  }
}

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final prefs = AppPrefs.instance;
  late final nameCtl = TextEditingController(text: prefs.name);
  final codeCtl = TextEditingController();
  final inviteCtl = TextEditingController();
  String? reply;
  String? err;
  bool busy = false;

  void _saveName() {
    if (nameCtl.text.trim().isNotEmpty) {
      prefs.name = nameCtl.text.trim();
      prefs.save();
    }
  }

  void _joinCode() {
    final code = codeCtl.text.trim().toUpperCase();
    if (code.length < 4) return;
    _saveName();
    final g = NetGuest.code(prefs.name, code);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GuestLobbyScreen(guest: g)));
  }

  Future<void> _answerInvite() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      _saveName();
      final (text, link) = await ManualSignal.answerInvite(inviteCtl.text);
      setState(() => reply = text);
      final g = NetGuest.manual(prefs.name, link);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Send this reply to the host', style: MK.title(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Copy it, send it back in the same chat, then tap Continue.', style: MK.body(13)),
            const SizedBox(height: 10),
            GoldButton('Copy reply', icon: Icons.copy, compact: true, onPressed: () => Clipboard.setData(ClipboardData(text: text))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue'))],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GuestLobbyScreen(guest: g)));
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: 'Join a game',
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 200, child: TextField(controller: nameCtl, maxLength: 16, decoration: const InputDecoration(labelText: 'Your name', counterText: ''))),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: codeCtl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: MK.title(22).copyWith(letterSpacing: 4),
                  decoration: const InputDecoration(labelText: 'Room code', counterText: ''),
                  onSubmitted: (_) => _joinCode(),
                ),
              ),
              const SizedBox(width: 12),
              GoldButton('Join', icon: Icons.login, onPressed: _joinCode),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Got an invite message instead?', style: MK.body(15, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(controller: inviteCtl, maxLines: 2, decoration: const InputDecoration(hintText: 'Paste MICHIKUB-INVITE:…')),
            const SizedBox(height: 8),
            Row(children: [
              GoldButton('Make my reply', icon: Icons.reply, compact: true, crimson: true, onPressed: busy ? null : _answerInvite),
              const SizedBox(width: 10),
              if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              if (err != null) Expanded(child: Text(err!, style: MK.body(12, color: MK.danger))),
              if (reply != null) Text('Reply ready', style: MK.body(12, color: MK.goldLight)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class GuestLobbyScreen extends StatefulWidget {
  final NetGuest guest;
  const GuestLobbyScreen({super.key, required this.guest});
  @override
  State<GuestLobbyScreen> createState() => _GuestLobbyScreenState();
}

class _GuestLobbyScreenState extends State<GuestLobbyScreen> {
  NetGuest get g => widget.guest;
  bool _inGame = false;

  @override
  void initState() {
    super.initState();
    g.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (g.session != null && !_inGame) {
      _inGame = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(session: g.session!)));
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    g.removeListener(_changed);
    if (!_inGame) g.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: g.code.isEmpty ? 'Joining by invite' : 'Room ${g.code}',
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(g.error ?? g.status, style: MK.body(15, color: g.error != null ? MK.danger : MK.creamText)),
            if (g.error == null && g.link == null) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (g.players.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Players', style: MK.body(13, color: MK.gold)),
              for (final p in g.players)
                Text('• ${p.name}${p.kind == SeatKind.bot ? ' (bot)' : ''}${p.id == 'host' ? ' (host)' : ''}', style: MK.body(14)),
              const SizedBox(height: 10),
              Text('House rules', style: MK.body(13, color: MK.gold)),
              Text(g.rules.summary(), style: MK.body(13)),
            ],
          ]),
        ),
      ]),
    );
  }
}
