import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/web_nav.dart';
import '../net/app_handoff.dart';
import '../app/sfx.dart';
import '../app/bot_roster.dart';
import '../app/prefs.dart';
import '../engine/host.dart';
import '../net/invite_link.dart';
import '../net/online.dart';
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

  /// Between rounds: back in the lobby of a running game (Next round continues it; Back
  /// returns to the results).
  final bool betweenRounds;
  const HostLobbyScreen({super.key, this.net, this.betweenRounds = false});
  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  final prefs = AppPrefs.instance;
  late final NetHost net = (widget.net ?? NetHost(prefs.name, prefs.rules, avatar: prefs.avatar))..addListener(_changed);
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
    if (!_started && !widget.betweenRounds) net.shutdown();
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.betweenRounds,
      onPopInvokedWithResult: (didPop, _) {
        if (widget.betweenRounds) {
          if (didPop && net.between) net.closeLobby();
          return;
        }
        if (!didPop) _confirmExit();
      },
      child: MkScaffold(
      title: 'Host a game',
      actions: [
        Text(net.canStart ? '' : 'Need 2+ players  ', style: MK.body(12, color: MK.gold)),
        GoldButton(widget.betweenRounds ? 'Next round' : 'Start game', key: const ValueKey('start'), icon: Icons.play_arrow, compact: true, onPressed: net.canStart
              ? () {
                  _started = true;
                  if (widget.betweenRounds) {
                    net.continueGame();
                    Navigator.of(context).pop();
                    return;
                  }
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
                Text('Friends scan the code or open the link to join your room (long-press to copy the code).',
                    style: MK.body(11, color: MK.gold)),
              ]),
            ),
            const SizedBox(width: 12),
            // Scan to join: the web join link (opens the app on Android phones that have it).
            if (net.code.isNotEmpty && !net.opening) ...[
              InviteQr(code: net.code),
              const SizedBox(width: 12),
            ],
            // Share and Copy invite, the same width, stacked.
            IntrinsicWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GoldButton('Share', icon: Icons.share, compact: true, onPressed: net.code.isEmpty ? null : () => _shareInvite(net.code)),
              const SizedBox(height: 8),
              GoldButton('Copy invite', icon: Icons.copy, compact: true, crimson: true, onPressed: net.code.isEmpty ? null : () => _copyInvite(net.code)),
              ]),
            ),
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
                    : IconButton(
                        key: ValueKey('remove-${s.info.id}'),
                        icon: const Icon(Icons.close, color: MK.gold),
                        onPressed: () {
                          playSfx(Sfx.click);
                          net.removeSeat(s.info.id);
                        },
                      ),
              ),
            Wrap(spacing: 8, children: [
              for (final l in BotLevel.values)
                TextButton.icon(
                  key: ValueKey('addBot-${l.name}'),
                  onPressed: net.full
                      ? null
                      : () {
                          playSfx(Sfx.click);
                          net.addBot(l);
                        },
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

/// The last room code this phone joined, kept in memory until the app is closed (not saved
/// to disk), so a player who backs out by accident can rejoin quickly.
String? lastRoomCode;

class JoinScreen extends StatefulWidget {
  /// A room code to fill in (from a michikub://join/CODE link).
  final String? initialCode;
  const JoinScreen({super.key, this.initialCode, this.offerApp});

  /// Show "Open in the app" (null: web, Android, opened from a join link).
  final bool? offerApp;
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final prefs = AppPrefs.instance;
  late final nameCtl = TextEditingController(text: prefs.name);
  late final codeCtl = TextEditingController(text: widget.initialCode ?? lastRoomCode ?? '');

  /// The box holds the last room's code (not one from a link): the first tap clears it.
  /// Web on an Android phone, opened from a join link: offer the app (if the automatic
  /// hand-off in index.html didn't happen; see app_handoff.dart).
  late final bool _offerApp =
      widget.initialCode != null && (widget.offerApp ?? (kIsWeb && offersAppHandoff(Uri.base, browserUserAgent)));

  late bool _clearOnTap = widget.initialCode == null && (lastRoomCode ?? '').isNotEmpty;

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
    lastRoomCode = code;
    final g = NetGuest.code(prefs.name, code, avatar: prefs.avatar);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => GuestLobbyScreen(guest: g)));
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: 'Join a game',
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const MyAvatarButton(),
              const SizedBox(width: 10),
              SizedBox(width: 200, child: TextField(controller: nameCtl, maxLength: 16, decoration: const InputDecoration(labelText: 'Your name', counterText: ''))),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: codeCtl,
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 6,
                  // Pasting a whole invite ("Come play Michikub with me! ... michikub://join/ABCD") keeps just the code.
                  inputFormatters: [
                    TextInputFormatter.withFunction((old, nu) {
                      if (nu.text.length <= 6) return nu;
                      final c = codeFromJoinLink(nu.text);
                      return c == null ? nu : TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
                    }),
                    // Codes are letters only: anything else typed is dropped (after a pasted invite is reduced to its code).
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                  ],
                  style: MK.code(22, letterSpacing: 4),
                  onTap: () {
                    if (!_clearOnTap) return;
                    _clearOnTap = false;
                    codeCtl.clear();
                  },
                  onChanged: (_) => _clearOnTap = false,
                  decoration: const InputDecoration(labelText: 'Room code', counterText: ''),
                  onSubmitted: (_) => _joinCode(),
                ),
              ),
              const SizedBox(width: 12),
              GoldButton('Join', icon: Icons.login, onPressed: _joinCode),
            ]),
            if (_offerApp) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('openInApp'),
                  onPressed: () => browserNavigate(androidIntentUrl(widget.initialCode!)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Have the Android app? Open in the app'),
                ),
              ),
            ],
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
      title: 'Room ${g.code}',
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

/// A QR code of a room's web join link, dark on white, for a friend's phone camera.
class InviteQr extends StatelessWidget {
  final String code;
  final double size;
  const InviteQr({super.key, required this.code, this.size = 116});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Scan to join',
        child: Container(
          key: const ValueKey('inviteQr'),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: QrImageView(
            data: webJoinLink(code),
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          ),
        ),
      );
}
