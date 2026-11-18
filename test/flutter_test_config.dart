import 'dart:async';

import 'package:michikub/ui/game_screen.dart';

/// Runs before every test file: widget tests skip the start-of-round deal animation unless
/// they turn it on (test/deal_animation_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TableTuning.dealAnimation = false;
  await testMain();
}
