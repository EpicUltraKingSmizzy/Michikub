import 'package:flutter/material.dart';

import '../app/fullscreen.dart';
import '../app/prefs.dart';
import '../app/sfx.dart';
import 'theme.dart';

/// Web only: the browser full screen button, or on iPhones and iPads (no full screen for web
/// pages there, in any browser) a small hint to Add to Home Screen, which opens the game
/// without browser bars. Nothing in the apps, nor once opened from the home screen.
class FullscreenButton extends StatefulWidget {
  /// Tests: force the button / the iOS hint (null = ask the browser).
  final bool? showButton, showIosHint;

  /// The iOS hint as a round button the size of the full screen one (Home's corner), instead
  /// of a labelled pill with a close X (title bars).
  final bool compact;
  const FullscreenButton({super.key, this.showButton, this.showIosHint, this.compact = false});

  /// Whether there's anything to show (layouts leave room only then).
  static bool get anything => Fullscreen.supported || (Fullscreen.iosHomeScreenHint && !AppPrefs.instance.iosHintDismissed);

  @override
  State<FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<FullscreenButton> {
  @override
  Widget build(BuildContext context) {
    if (widget.showButton ?? Fullscreen.supported) {
      return ValueListenableBuilder<bool>(
        valueListenable: Fullscreen.active,
        builder: (_, on, _) => Tooltip(
          message: on ? 'Exit full screen' : 'Full screen',
          child: RingButton(
            key: const ValueKey('fullscreen'),
            size: 46,
            icon: on ? Icons.fullscreen_exit : Icons.fullscreen,
            onPressed: () {
              playSfx(Sfx.click);
              Fullscreen.toggle();
            },
          ),
        ),
      );
    }
    final prefs = AppPrefs.instance;
    if (!(widget.showIosHint ?? Fullscreen.iosHomeScreenHint) || prefs.iosHintDismissed) return const SizedBox.shrink();
    void hide() {
      prefs.iosHintDismissed = true;
      prefs.save();
      if (mounted) setState(() {});
    }

    Future<void> help() async {
      playSfx(Sfx.click);
      if (await showIosFullscreenHelp(context) == true) hide();
    }

    if (widget.compact) {
      return Tooltip(
        message: 'Full screen: Add to Home Screen',
        child: RingButton(key: const ValueKey('iosFullscreenHint'), size: 46, icon: Icons.ios_share, onPressed: help),
      );
    }
    return Container(
      key: const ValueKey('iosFullscreenHint'),
      decoration: BoxDecoration(
        color: const Color(0xEE1A0805),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MK.gold, width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: help,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.ios_share, size: 18, color: MK.goldLight),
              const SizedBox(width: 6),
              Text('Full screen', style: MK.body(13, color: MK.goldLight, weight: FontWeight.w700)),
            ]),
          ),
        ),
        IconButton(
          key: const ValueKey('iosHintClose'),
          tooltip: 'Hide',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: hide,
          icon: const Icon(Icons.close, color: MK.gold),
        ),
      ]),
    );
  }
}

/// How to play full screen on an iPhone or iPad: Add to Home Screen. True: "Hide this tip".
Future<bool?> showIosFullscreenHelp(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: MkPanel(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Play full screen', style: MK.title(22), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('iPhones and iPads don\'t let web pages go full screen. Add Michikub to your Home Screen and it opens without the browser bars:',
                    style: MK.body(13)),
                const SizedBox(height: 10),
                _step('1', Icons.ios_share, 'Tap Share (Safari: bottom bar; Chrome: next to the address bar).'),
                _step('2', Icons.add_box_outlined, 'Choose "Add to Home Screen", then Add.'),
                _step('3', Icons.touch_app_outlined, 'Open Michikub from your Home Screen.'),
                const SizedBox(height: 12),
                GoldButton('Got it', onPressed: () => Navigator.pop(ctx)),
                const SizedBox(height: 4),
                TextButton(key: const ValueKey('iosHintHide'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Hide this tip')),
              ]),
            ),
          ),
        ),
      ),
    );

Widget _step(String n, IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n.', style: MK.body(14, weight: FontWeight.w700, color: MK.goldLight)),
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: MK.goldLight),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: MK.body(13))),
      ]),
    );
