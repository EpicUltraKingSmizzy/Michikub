import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'fullscreen_button.dart';

import 'online_screens.dart';
import 'options_screen.dart';
import 'puzzles_screen.dart';
import 'setup_screens.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.fitToScreen = kIsWeb, this.showFullscreen});

  /// Web only (by default): the menu scales down to fit the window. A phone browser in
  /// landscape loses height to its address bar. The apps keep the original layout.
  final bool fitToScreen;

  /// The browser full screen button (or the iPhone Add to Home Screen hint) in the top-right
  /// corner (web; null = ask the browser).
  final bool? showFullscreen;

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final menu = _menu(go);
    if (!fitToScreen) {
      return Scaffold(
        body: WoodBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: menu),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: WoodBackground(
        child: SafeArea(
          // The menu keeps its layout and scales down to fit short or narrow windows (a phone
          // browser in landscape loses height to its address bar). Below [_minFitHeight] it
          // stops shrinking and scrolls instead.
          child: LayoutBuilder(
            builder: (context, box) {
              final fitted = Padding(
                padding: EdgeInsets.all(box.maxHeight < 400 ? 8 : 16),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: menu.children),
                  ),
                ),
              );
              final body = box.maxHeight >= _minFitHeight
                  ? fitted
                  : SingleChildScrollView(child: SizedBox(height: _minFitHeight, width: box.maxWidth, child: fitted));
              if (!(showFullscreen ?? FullscreenButton.anything)) return body;
              return Stack(children: [
                Positioned.fill(child: body),
                Positioned(top: 6, right: 6, child: FullscreenButton(showButton: showFullscreen, compact: true)),
              ]);
            },
          ),
        ),
      ),
    );
  }

  /// Shortest height the menu scales down to before it scrolls instead.
  static const double _minFitHeight = 180;

  /// The menu (the same on the apps and the web): Host and Join on top in gold, then Puzzles,
  /// Play vs bots, Pass-and-play and Options. The web build shrink-wraps the same children.
  Row _menu(void Function(Widget) go) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const BrandBlock(),
      const SizedBox(width: 40),
      SizedBox(
        width: 300,
        child: MkPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoldButton('Host a game', icon: Icons.wifi_tethering, onPressed: () => go(const HostLobbyScreen())),
              const SizedBox(height: 10),
              GoldButton('Join a game', icon: Icons.login, onPressed: () => go(const JoinScreen())),
              const SizedBox(height: 10),
              GoldButton('Puzzles', icon: Icons.extension_outlined, crimson: true, onPressed: () => go(const PuzzlesScreen())),
              const SizedBox(height: 10),
              GoldButton('Play vs bots', icon: Icons.smart_toy_outlined, crimson: true, onPressed: () => go(const PracticeSetupScreen())),
              const SizedBox(height: 10),
              GoldButton('Pass-and-play', icon: Icons.people_alt_outlined, crimson: true, onPressed: () => go(const HotSeatSetupScreen())),
              const SizedBox(height: 10),
              GoldButton('Options', icon: Icons.tune, crimson: true, onPressed: () => go(const OptionsScreen())),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The logo, the title and the tagline, as on the home screen; [scale] shrinks it (the Join
/// screen shows a smaller one).
class BrandBlock extends StatelessWidget {
  final double scale;
  const BrandBlock({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(32 * scale),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: MK.gold, width: 3 * scale.clamp(.5, 1)),
                borderRadius: BorderRadius.circular(32 * scale),
              ),
              child: Image.asset('assets/icon/michikub_icon_1024.png', width: 170 * scale, height: 170 * scale),
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            'Michikub',
            style: MK
                .title(50 * scale)
                .copyWith(
                  color: MK.goldLight,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                ),
          ),
          Text('Play with friends. No ads, no subscription.',
              textAlign: TextAlign.center, style: MK.body(14 * math.max(scale, .85), color: MK.gold)),
        ],
      );
}
