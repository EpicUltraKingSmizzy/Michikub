import 'package:flutter/material.dart';

import '../app/sfx.dart';
import '../app/bot_roster.dart';
import '../app/prefs.dart';
import '../app/session.dart';
import '../engine/host.dart';
import '../engine/rules.dart';
import 'avatar.dart';
import 'game_screen.dart';
import 'rules_editor.dart';
import 'theme.dart';

String levelName(BotLevel l) => switch (l) {
      BotLevel.easy => 'Easy',
      BotLevel.medium => 'Medium',
      BotLevel.hard => 'Hard',
    };

void startLocalGame(BuildContext context, List<PlayerInfo> players, HouseRules rules, {required bool hotSeat}) {
  final prefs = AppPrefs.instance;
  final test = prefs.test.enabled ? prefs.test : TestTools.off;
  final host = GameHost(players: players, rules: rules, test: test, waitForReady: hotSeat);
  final session = LocalSession(host, hotSeat: hotSeat, testMenu: test.enabled && test.cheatMenu);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
}

class _TestBadge extends StatelessWidget {
  const _TestBadge();
  @override
  Widget build(BuildContext context) => AppPrefs.instance.test.enabled
      ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: MK.crimson, borderRadius: BorderRadius.circular(12), border: Border.all(color: MK.gold)),
          child: Text('Test tools on', style: MK.body(12, weight: FontWeight.w700)),
        )
      : const SizedBox.shrink();
}

class PracticeSetupScreen extends StatefulWidget {
  /// Between rounds: the game whose players and rules are being changed (Start continues it).
  final GameSession? resume;
  const PracticeSetupScreen({super.key, this.resume});
  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final prefs = AppPrefs.instance;
  late final List<PlayerInfo>? _was = widget.resume?.lineup.where((p) => p.kind == SeatKind.bot).toList();
  late List<BotLevel> bots = _was != null ? [for (final p in _was) p.level] : List.of(prefs.practiceBots);

  /// The robots for this game, picked at random when the screen opens (Shuffle picks again).
  /// Between rounds, the robots already playing.
  late List<RobotProfile> robots = _was != null
      ? [for (final p in _was) robotByAvatar(p.avatar) ?? pickRobots(1, exclude: _mine).first]
      : pickRobots(bots.length, exclude: _mine);

  /// A robot whose picture you picked as your avatar sits out.
  Set<String> get _mine => {for (final r in robotRoster) if (r.avatar == prefs.avatar) r.id};

  void _addBot() => setState(() {
        bots.add(BotLevel.medium);
        robots.addAll(pickRobots(1, exclude: {for (final r in robots) r.id, ..._mine}));
      });

  void _removeBot() => setState(() {
        bots.removeLast();
        robots.removeLast();
      });
  late HouseRules rules = widget.resume?.lineupRules ?? prefs.rules;

  void _start() {
    prefs.practiceBots = List.of(bots);
    prefs.rules = rules;
    prefs.save();
    final players = [
      PlayerInfo('me', prefs.name, SeatKind.human, avatar: prefs.avatar),
      for (final (i, robot) in robots.indexed)
        PlayerInfo('bot$i', '${robot.name} (${levelName(bots[i])})', SeatKind.bot, level: bots[i], avatar: robot.avatar),
    ];
    if (widget.resume != null) {
      widget.resume!.changeLineup(players, rules);
      Navigator.of(context).pop();
      return;
    }
    startLocalGame(context, players, rules, hotSeat: false);
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: 'Play vs bots',
      actions: [
        const _TestBadge(),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: GoldButton(widget.resume != null ? 'Next round' : 'Start practice',
              key: const ValueKey('start'), icon: Icons.play_arrow, compact: true, onPressed: _start),
        ),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Computer players', style: MK.body(15, weight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: bots.length > 1 ? _clicked(_removeBot) : null,
                icon: const Icon(Icons.remove_circle_outline, color: MK.goldLight),
              ),
              Text('${bots.length}', style: MK.body(18, weight: FontWeight.w700)),
              IconButton(
                onPressed: bots.length < 3 ? _clicked(_addBot) : null,
                icon: const Icon(Icons.add_circle_outline, color: MK.goldLight),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => robots = pickRobots(bots.length)),
                icon: const Icon(Icons.shuffle, size: 18, color: MK.goldLight),
                label: Text('Shuffle robots', style: MK.body(13, color: MK.goldLight)),
              ),
            ]),
            for (var i = 0; i < bots.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  PlayerAvatar(size: 44, name: robots[i].name, image: robots[i].avatar),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(robots[i].name, style: MK.body(15, weight: FontWeight.w700)),
                      Text(robots[i].tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: MK.body(11, color: MK.gold)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: SegmentedButton<BotLevel>(
                      segments: [for (final l in BotLevel.values) ButtonSegment(value: l, label: Text(levelName(l)))],
                      selected: {bots[i]},
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: MK.crimson,
                        selectedForegroundColor: MK.goldLight,
                        side: BorderSide(color: MK.gold.withValues(alpha: .6)),
                      ),
                      onSelectionChanged: (s) => setState(() => bots[i] = s.first),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        MkPanel(child: RulesEditor(rules: rules, onChanged: (r) => setState(() => rules = r))),
      ]),
    );
  }
}

class HotSeatSetupScreen extends StatefulWidget {
  /// Between rounds: the game whose players and rules are being changed (Start continues it).
  final GameSession? resume;
  const HotSeatSetupScreen({super.key, this.resume});
  @override
  State<HotSeatSetupScreen> createState() => _HotSeatSetupScreenState();
}

class _HotSeatSetupScreenState extends State<HotSeatSetupScreen> {
  final prefs = AppPrefs.instance;
  // Player 1 starts as the name saved in Options (still editable here).
  late final List<TextEditingController> names = widget.resume != null
      ? [for (final p in widget.resume!.lineup) TextEditingController(text: p.name)]
      : [
          for (final (i, n) in prefs.hotSeatNames.indexed)
            TextEditingController(text: i == 0 && prefs.name.trim().isNotEmpty ? prefs.name.trim() : n),
        ];
  late HouseRules rules = widget.resume?.lineupRules ?? prefs.rules;

  void _start() {
    final ns = [for (var i = 0; i < names.length; i++) names[i].text.trim().isEmpty ? 'Player ${i + 1}' : names[i].text.trim()];
    prefs.hotSeatNames = ns;
    prefs.rules = rules;
    prefs.save();
    final players = [for (var i = 0; i < ns.length; i++) PlayerInfo('p$i', ns[i], SeatKind.human)];
    if (widget.resume != null) {
      widget.resume!.changeLineup(players, rules);
      Navigator.of(context).pop();
      return;
    }
    startLocalGame(context, players, rules, hotSeat: true);
  }

  @override
  Widget build(BuildContext context) {
    return MkScaffold(
      title: 'Pass-and-play',
      actions: [
        const _TestBadge(),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: GoldButton(widget.resume != null ? 'Next round' : 'Start',
              key: const ValueKey('start'), icon: Icons.play_arrow, compact: true, onPressed: _start),
        ),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        MkPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Players on this phone', style: MK.body(15, weight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                onPressed: names.length > 2 ? _clicked(() => setState(() => names.removeLast())) : null,
                icon: const Icon(Icons.remove_circle_outline, color: MK.goldLight),
              ),
              Text('${names.length}', style: MK.body(18, weight: FontWeight.w700)),
              IconButton(
                onPressed: names.length < 4
                    ? _clicked(() => setState(() => names.add(TextEditingController(text: 'Player ${names.length + 1}'))))
                    : null,
                icon: const Icon(Icons.add_circle_outline, color: MK.goldLight),
              ),
            ]),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < names.length; i++)
                SizedBox(width: 180, child: TextField(controller: names[i], maxLength: 16, decoration: InputDecoration(labelText: 'Player ${i + 1}', counterText: ''))),
            ]),
            const SizedBox(height: 6),
            Text('Between turns a cover screen says who to pass the phone to, so nobody sees another rack.',
                style: MK.body(11, color: MK.gold)),
          ]),
        ),
        const SizedBox(height: 12),
        MkPanel(child: RulesEditor(rules: rules, onChanged: (r) => setState(() => rules = r))),
      ]),
    );
  }
}

/// [f] with the menu click sound first (the add/remove player buttons).
VoidCallback _clicked(VoidCallback f) => () {
      playSfx(Sfx.click);
      f();
    };
