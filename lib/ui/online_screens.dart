import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/bot_roster.dart';
import '../app/prefs.dart';
import '../engine/host.dart';
import '../net/invite_link.dart';
import '../net/online.dart';
import '../net/peer.dart';
import 'avatar.dart';
import 'game_screen.dart';
import 'rules_editor.dart';
import 'setup_screens.dart';
import 'theme.dart';

/// Long-press on a room code: copies just the code, with a light haptic and a short note.
void copyRoomCode(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  if (AppPrefs.instance.haptics) HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Code copied'), duration: Duration(milliseconds: 1500)));
}

/// A room code as shown in a lobby; long-press copies it.
class RoomCode extends StatelessWidget {
  final String code;
  final TextStyle? style;
  const RoomCode(this.code, {super.key, this.style});
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: code.isEmpty ? null : () => copyRoomCode(context, code),
        child: Text(code, style: style),
      );
}

class HostLobbyScreen extends StatefulWidget {
  /// A room that's already been made (tests); normally the screen opens its own.
  final NetHost? net;
  const HostLobbyScreen({super.key, this.net});
  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  final prefs = AppPrefs.instance;
  late final NetHost net = (widget.net ?? NetHost(prefs.name, prefs.rules))..addListener(_changed);
  bool _started = false;

  /// Back (app bar, Android back button or gesture, iOS swipe) asks first. Yes closes the room
  /// (dispose shuts it down, disconnecting anyone who joined) and goes back to Home.
  Future<void> _confirmExit() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Exit the room?', style: MK.title(20)),
        content: Text('The room closes and anyone who joined is disconnected.', style: MK.body(13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        ],
      ),
    );
    if (yes == true && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    net.removeListener(_changed);
    if (!_started) net.shutdown();
    super.dispose();
  }

  /// Copies "Come play Michikub with me!" + the room code + the join link, ready to paste in a message.
  void _copyInvite(String code) {
    Clipboard.setData(ClipboardData(text: inviteShareText(code)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied. Paste it in a message to your friends.')));
  }

  /// Opens the phone's share sheet with the invite (any chat app, SMS, email...).
  Future<void> _shareInvite(String code) async {
    try {
      await SharePlus.instance.share(ShareParams(text: inviteShareText(code), subject: 'Come play Michikub with me!'));
    } catch (_) {
      // No share sheet here (e.g. some desktop browsers): copy instead.
      if (mounted) _copyInvite(code);
    }
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
        return MkFormDialog(
          title: 'Invite by message',
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: MkScaffold(
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
                  RoomCode(net.code, style: MK.code(36, letterSpacing: 6)),
                if (net.error != null) Text(net.error!, style: MK.body(12, color: MK.danger)),
                Text('Tap Share to send friends a link that opens Michikub straight to this room, or they can tap Join a game and type the code (long-press it to copy). Only connection details pass through the free matchmaking service.',
                    style: MK.body(11, color: MK.gold)),
              ]),
            ),
            const SizedBox(width: 12),
            Column(children: [
              GoldButton('Share', icon: Icons.share, compact: true, onPressed: net.code.isEmpty ? null : () => _shareInvite(net.code)),
              const SizedBox(height: 8),
              GoldButton('Copy invite', icon: Icons.copy, compact: true, crimson: true, onPressed: net.code.isEmpty ? null : () => _copyInvite(net.code)),
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
                leading: PlayerAvatar(
                    size: 34,
                    name: s.info.name,
                    image: s.info.avatar,
                    color: seatColors[net.seats.indexOf(s) % seatColors.length]),
                title: Text(s.info.name + (s.info.id == 'host' ? ' (you, host)' : ''), style: MK.body(14)),
                subtitle: s.info.kind == SeatKind.bot
                    ? Text([levelName(s.info.level), if (robotByAvatar(s.info.avatar) case final r?) r.tagline].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: MK.body(11, color: MK.gold))
                    : null,
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
      ),
    );
  }
}

class JoinScreen extends StatefulWidget {
  /// A room code to fill in (from a michikub://join/CODE link).
  final String? initialCode;
  const JoinScreen({super.key, this.initialCode});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final prefs = AppPrefs.instance;
  late final nameCtl = TextEditingController(text: prefs.name);
  late final codeCtl = TextEditingController(text: widget.initialCode ?? '');
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
                  // Pasting a whole invite ("Come play Michikub with me! ... michikub://join/ABCD") keeps just the code.
                  inputFormatters: [
                    TextInputFormatter.withFunction((old, nu) {
                      if (nu.text.length <= 6) return nu;
                      final c = codeFromJoinLink(nu.text);
                      return c == null ? nu : TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
                    }),
                  ],
                  style: MK.code(22, letterSpacing: 4),
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
      onTitleLongPress: g.code.isEmpty ? null : () => copyRoomCode(context, g.code),
      titleWidget: g.code.isEmpty
          ? null
          : Text.rich(TextSpan(children: [
              TextSpan(text: 'Room ', style: MK.title(22)),
              TextSpan(text: g.code, style: MK.code(20, letterSpacing: 3)),
            ])),
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
