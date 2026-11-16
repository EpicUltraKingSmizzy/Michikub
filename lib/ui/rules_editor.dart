import 'package:flutter/material.dart';

import '../app/prefs.dart';
import '../engine/rules.dart';
import 'theme.dart';

/// House rules editor with saved presets. Used by Practice, Pass-and-play
/// and the online lobby.
class RulesEditor extends StatefulWidget {
  final HouseRules rules;
  final ValueChanged<HouseRules> onChanged;
  final bool enabled;
  const RulesEditor({super.key, required this.rules, required this.onChanged, this.enabled = true});
  @override
  State<RulesEditor> createState() => _RulesEditorState();
}

class _RulesEditorState extends State<RulesEditor> {
  final prefs = AppPrefs.instance;
  HouseRules get r => widget.rules;

  void _set(HouseRules n) {
    if (!widget.enabled) return;
    widget.onChanged(n.normalized());
  }

  Future<void> _savePreset() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      // No title (your call): just the name field and the buttons.
      builder: (ctx) => MkFormDialog(
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          // The keyboard's Done saves.
          onSubmitted: (_) => Navigator.pop(ctx, ctl.text.trim()),
          decoration: const InputDecoration(hintText: 'Preset name', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    prefs.presets[name] = r;
    await prefs.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final presetNames = ['Classic', ...prefs.presets.keys];
    String? current;
    if (r == HouseRules.classic) current = 'Classic';
    for (final e in prefs.presets.entries) {
      if (e.value == r) current = e.key;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Presets', style: MK.body(13, color: MK.gold, weight: FontWeight.w700)),
        for (final n in presetNames)
          InputChip(
            label: Text(n),
            selected: current == n,
            selectedColor: MK.crimson,
            backgroundColor: const Color(0xFF2A1208),
            side: BorderSide(color: MK.gold.withValues(alpha: .6)),
            onPressed: widget.enabled ? () => _set(n == 'Classic' ? HouseRules.classic : prefs.presets[n]!) : null,
            onDeleted: n == 'Classic' || !widget.enabled
                ? null
                : () async {
                    prefs.presets.remove(n);
                    await prefs.save();
                    setState(() {});
                  },
          ),
        // Only once the rules differ from Classic and from every saved preset: there's
        // something new to save.
        if (widget.enabled && current == null)
          TextButton.icon(onPressed: _savePreset, icon: const Icon(Icons.bookmark_add_outlined, size: 18), label: const Text('Save as preset')),
      ]),
      const SizedBox(height: 6),
      _row(
        'First meld minimum',
        r.firstMeld == 0 ? 'Off' : '${r.firstMeld} points',
        Row(children: [
          Switch(value: r.firstMeld > 0, onChanged: widget.enabled ? (on) => _set(r.copyWith(firstMeld: on ? 30 : 0)) : null),
          Expanded(
            child: Slider(
              min: 3,
              max: 50,
              divisions: 47,
              value: (r.firstMeld == 0 ? 30 : r.firstMeld).toDouble(),
              onChanged: r.firstMeld > 0 && widget.enabled ? (x) => _set(r.copyWith(firstMeld: x.round())) : null,
            ),
          ),
        ]),
      ),
      _row('Starting hand', '${r.handSize} tiles',
          Slider(min: 7, max: 20, divisions: 13, value: r.handSize.toDouble(), onChanged: widget.enabled ? (x) => _set(r.copyWith(handSize: x.round())) : null)),
      _row(
        'Jokers',
        r.jokers == 0 ? 'None' : '${r.jokers} (${['red', 'black', 'yellow', 'blue'].take(r.jokers).join(', ')})',
        Slider(min: 0, max: 4, divisions: 4, value: r.jokers.toDouble(), onChanged: widget.enabled ? (x) => _set(r.copyWith(jokers: x.round())) : null),
      ),
      _row(
        'Turn timer',
        r.turnSeconds == 0 ? 'Off' : '${r.turnSeconds} s',
        Wrap(spacing: 8, children: [
          for (final t in HouseRules.timerOptions)
            ChoiceChip(
              label: Text(t == 0 ? 'Off' : '$t s'),
              selected: r.turnSeconds == t,
              selectedColor: MK.crimson,
              backgroundColor: const Color(0xFF2A1208),
              onSelected: widget.enabled ? (_) => _set(r.copyWith(turnSeconds: t)) : null,
            ),
        ]),
      ),
      _row(
        'Tiles drawn when you pass',
        '${r.passDraw}',
        Wrap(spacing: 8, children: [
          for (final n in [1, 2, 3])
            ChoiceChip(
              label: Text('$n'),
              selected: r.passDraw == n,
              selectedColor: MK.crimson,
              backgroundColor: const Color(0xFF2A1208),
              onSelected: widget.enabled ? (_) => _set(r.copyWith(passDraw: n)) : null,
            ),
        ]),
      ),
    ]);
  }

  Widget _row(String label, String value, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
            width: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: MK.body(13, weight: FontWeight.w600)),
              Text(value, style: MK.body(12, color: MK.goldLight)),
            ]),
          ),
          Expanded(child: control),
        ]),
      );
}
