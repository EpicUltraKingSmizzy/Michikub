import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/bot_roster.dart';
import 'app/prefs.dart';
import 'engine/host.dart';
import 'engine/rules.dart';
import 'ui/setup_screens.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await AppPrefs.instance.load();
  runApp(const MichikubApp());
}

class MichikubApp extends StatelessWidget {
  const MichikubApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Michikub',
        debugShowCheckedModeBanner: false,
        theme: MK.theme(),
        home: const _Start(),
      );
}

/// Opens Home. For screenshots on the web build, `?demo=practice` (or
/// `?demo=hotseat`) jumps straight into a seeded game.
class _Start extends StatefulWidget {
  const _Start();
  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  @override
  void initState() {
    super.initState();
    final demo = Uri.base.queryParameters['demo'];
    if (kIsWeb && demo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final p = AppPrefs.instance;
        final seed = int.tryParse(Uri.base.queryParameters['seed'] ?? '') ?? 7;
        final hand = int.tryParse(Uri.base.queryParameters['hand'] ?? '') ?? 14;
        final bots = int.tryParse(Uri.base.queryParameters['bots'] ?? '') ?? 3;
        p.test = TestTools(enabled: true, seed: seed, giveJoker: true);
        final rules = HouseRules(handSize: hand, turnSeconds: 0, firstMeld: Uri.base.queryParameters['meld'] == '0' ? 0 : 30);
        if (demo == 'hotseat') {
          startLocalGame(context, const [PlayerInfo('p0', 'Michi', SeatKind.human), PlayerInfo('p1', 'Sam', SeatKind.human)], rules, hotSeat: true);
        } else {
          startLocalGame(context, [
            const PlayerInfo('me', 'Michi', SeatKind.human),
            for (final (i, r) in robotRoster.take(bots).indexed)
              PlayerInfo('bot$i', r.name, SeatKind.bot, level: BotLevel.hard, avatar: r.avatar),
          ], rules, hotSeat: false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
