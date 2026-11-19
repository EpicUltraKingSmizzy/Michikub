import 'package:flutter/material.dart';

import '../app/fullscreen.dart';
import '../app/sfx.dart';
import 'theme.dart';

/// Browser full screen on / off (web only: shown where the browser offers full screen).
class FullscreenButton extends StatelessWidget {
  const FullscreenButton({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
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
