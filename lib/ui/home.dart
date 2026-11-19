import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app/fullscreen.dart';
import 'fullscreen_button.dart';

import 'online_screens.dart';
import 'options_screen.dart';
import 'setup_screens.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.fitToScreen = kIsWeb, this.showFullscreen});

  /// Web only (by default): the menu scales down to fit the window. A phone browser in
  /// landscape loses height to its address bar. The apps keep the original layout.
  final bool fitToScreen;

  /// The browser full screen button in the top-right corner (web, where the browser offers
  /// full screen; null = ask the browser).
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
              if (!(showFullscreen ?? Fullscreen.supported)) return body;
              return Stack(children: [
                Positioned.fill(child: body),
                const Positioned(top: 6, right: 6, child: FullscreenButton()),
              ]);
            },
          ),
        ),
      ),
    );
  }

  /// Shortest height the menu scales down to before it scrolls instead.
  static const double _minFitHeight = 180;

  /// The original layout (the apps); the web build shrink-wraps the same children.
  Row _menu(void Function(Widget) go) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: MK.gold, width: 3),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Image.asset('assets/icon/michikub_icon_1024.png', width: 170, height: 170),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Michikub',
            style: MK
                .title(50)
                .copyWith(
                  color: MK.goldLight,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                ),
          ),
          Text('Play with friends. No ads, no subscription.', style: MK.body(14, color: MK.gold)),
        ],
      ),
      const SizedBox(width: 40),
      SizedBox(
        width: 300,
        child: MkPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoldButton('Practice vs bots', icon: Icons.smart_toy_outlined, onPressed: () => go(const PracticeSetupScreen())),
              const SizedBox(height: 10),
              GoldButton('Pass-and-play', icon: Icons.people_alt_outlined, onPressed: () => go(const HotSeatSetupScreen())),
              const SizedBox(height: 10),
              GoldButton('Host a game', icon: Icons.wifi_tethering, crimson: true, onPressed: () => go(const HostLobbyScreen())),
              const SizedBox(height: 10),
              GoldButton('Join a game', icon: Icons.login, crimson: true, onPressed: () => go(const JoinScreen())),
              const SizedBox(height: 10),
              GoldButton('Options & house rules', icon: Icons.tune, crimson: true, onPressed: () => go(const OptionsScreen())),
            ],
          ),
        ),
      ),
    ],
  );
}
