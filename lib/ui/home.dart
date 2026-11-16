import 'package:flutter/material.dart';

import 'online_screens.dart';
import 'options_screen.dart';
import 'setup_screens.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      body: WoodBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: MK.gold, width: 3), borderRadius: BorderRadius.circular(32)),
                      child: Image.asset('assets/icon/michikub_icon_1024.png', width: 170, height: 170),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Michikub', style: MK.title(50).copyWith(color: MK.goldLight, shadows: const [Shadow(color: Colors.black, blurRadius: 8)])),
                  Text('Play with friends. No ads, no subscription.', style: MK.body(14, color: MK.gold)),
                ]),
                const SizedBox(width: 40),
                SizedBox(
                  width: 300,
                  child: MkPanel(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      GoldButton('Practice vs bots', icon: Icons.smart_toy_outlined, onPressed: () => go(const PracticeSetupScreen())),
                      const SizedBox(height: 10),
                      GoldButton('Pass-and-play', icon: Icons.people_alt_outlined, onPressed: () => go(const HotSeatSetupScreen())),
                      const SizedBox(height: 10),
                      GoldButton('Host a game', icon: Icons.wifi_tethering, crimson: true, onPressed: () => go(const HostLobbyScreen())),
                      const SizedBox(height: 10),
                      GoldButton('Join a game', icon: Icons.login, crimson: true, onPressed: () => go(const JoinScreen())),
                      const SizedBox(height: 10),
                      GoldButton('Options & house rules', icon: Icons.tune, crimson: true, onPressed: () => go(const OptionsScreen())),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
