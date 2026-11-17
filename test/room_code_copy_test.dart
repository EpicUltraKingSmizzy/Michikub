import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/ui/online_screens.dart';

void main() {
  testWidgets('long-pressing the room code copies just the code, with a haptic and a snackbar', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: RoomCode('KTMQZP')))));
    await tester.longPress(find.text('KTMQZP'));
    await tester.pump();
    final copy = calls.where((c) => c.method == 'Clipboard.setData').toList();
    expect(copy, hasLength(1));
    expect((copy.single.arguments as Map)['text'], 'KTMQZP');
    expect(calls.any((c) => c.method == 'HapticFeedback.vibrate' && c.arguments == 'HapticFeedbackType.lightImpact'), true);
    expect(find.text('Code copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
