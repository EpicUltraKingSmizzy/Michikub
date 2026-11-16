import 'package:flutter/material.dart';

import '../app/prefs.dart';
import 'rules_editor.dart';
import 'theme.dart';

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});
  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  final prefs = AppPrefs.instance;
  late final nameCtl = TextEditingController(text: prefs.name);
  late final seedCtl = TextEditingController(text: prefs.test.seed?.toString() ?? '');

  void _save() {
    prefs.name = nameCtl.text.trim().isEmpty ? 'Player' : nameCtl.text.trim();
    prefs.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = prefs.test;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: MkScaffold(
        title: 'Options & house rules',
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          MkPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('You', style: MK.body(15, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: nameCtl,
                  maxLength: 16,
                  decoration: const InputDecoration(labelText: 'Your name', counterText: ''),
                  onSubmitted: (_) => _save(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Vibration', style: MK.body(14)),
                subtitle: Text('Small taps when you pick up and place tiles', style: MK.body(11, color: MK.gold)),
                value: prefs.haptics,
                onChanged: (v) {
                  prefs.haptics = v;
                  _save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tile highlighting', style: MK.body(14)),
                subtitle: Text('Gold shine on valid sets, red outline on sets that aren\'t valid yet', style: MK.body(11, color: MK.gold)),
                value: prefs.highlightValid,
                onChanged: (v) {
                  prefs.highlightValid = v;
                  _save();
                },
              ),
              Text('Sound: none in this version.', style: MK.body(11, color: MK.gold)),
            ]),
          ),
          const SizedBox(height: 12),
          MkPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Default house rules', style: MK.body(15, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              RulesEditor(
                rules: prefs.rules,
                onChanged: (r) {
                  prefs.rules = r;
                  _save();
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          MkPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('Test tools', style: MK.body(15, weight: FontWeight.w700)),
                const Spacer(),
                Switch(
                  value: t.enabled,
                  onChanged: (v) {
                    prefs.test = t.copyWith(enabled: v);
                    _save();
                  },
                ),
              ]),
              Text('For trying things out alone. Only affects Practice and Pass-and-play.', style: MK.body(11, color: MK.gold)),
              if (t.enabled) ...[
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: seedCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Fixed deal (seed)', hintText: 'blank = random'),
                      onChanged: (s) {
                        prefs.test = t.copyWith(seed: () => int.tryParse(s.trim()));
                        prefs.save();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('The same number deals the same tiles every time.', style: MK.body(11, color: MK.gold))),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Deal me a joker', style: MK.body(14)),
                  value: t.giveJoker,
                  onChanged: (v) {
                    prefs.test = t.copyWith(giveJoker: v);
                    _save();
                  },
                ),
                _choice('Draw pile size', t.pileLimit, const [null, 20, 8, 2, 0], (v) => v == null ? 'Full' : '$v',
                    (v) => prefs.test = t.copyWith(pileLimit: () => v)),
                _choice('Turn timer override', t.timerOverride, const [null, 10, 20], (v) => v == null ? 'Use rules' : '$v s',
                    (v) => prefs.test = t.copyWith(timerOverride: () => v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Test buttons in the game menu', style: MK.body(14)),
                  subtitle: Text('Win now, draw 5, give me a joker, empty the pile, timer to 3 s', style: MK.body(11, color: MK.gold)),
                  value: t.cheatMenu,
                  onChanged: (v) {
                    prefs.test = t.copyWith(cheatMenu: v);
                    _save();
                  },
                ),
                Text('Tip: set the starting hand to 20 in the house rules to see the rack\'s second row right away.',
                    style: MK.body(11, color: MK.gold)),
              ],
            ]),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showLicensePage(context: context, applicationName: 'Michikub'),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Open-source licences'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _choice(String label, int? value, List<int?> options, String Function(int?) name, void Function(int?) set) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 170, child: Text(label, style: MK.body(14))),
          Expanded(
            child: Wrap(spacing: 8, children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(name(o)),
                  selected: value == o,
                  selectedColor: MK.crimson,
                  backgroundColor: const Color(0xFF2A1208),
                  onSelected: (_) {
                    set(o);
                    _save();
                  },
                ),
            ]),
          ),
        ]),
      );
}
