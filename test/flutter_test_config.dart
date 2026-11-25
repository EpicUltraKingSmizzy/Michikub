import 'dart:async';

import 'package:michikub/engine/host.dart';
import 'package:michikub/ui/game_screen.dart';

/// Runs before every test file: widget tests skip the start-of-round deal animation unless
/// they turn it on (test/deal_animation_test.dart), and opening auto-draw likewise.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TableTuning.dealAnimation = false;
  // Opening auto-draw is off unless a test is about it (test/auto_draw_test.dart).
  GameHost.openingAutoDraw = false;
  await testMain();
}
