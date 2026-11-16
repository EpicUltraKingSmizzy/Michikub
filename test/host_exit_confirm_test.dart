import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/net/online.dart';
import 'package:michikub/ui/online_screens.dart';

class _SpyHost extends NetHost {
  int shutdowns = 0;
  _SpyHost() : super('Ann', const HouseRules(), open: false) {
    code = 'ABCD';
  }
  @override
  Future<void> shutdown() async => shutdowns++;
}

void main() {
  Future<_SpyHost> openLobby(WidgetTester tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spy = _SpyHost();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostLobbyScreen(net: spy))),
              child: const Text('HOME'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.text('Host a game'), findsOneWidget);
    return spy;
  }

  testWidgets('app bar back asks "Exit the room?"; No keeps the room', (tester) async {
    final spy = await openLobby(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.text('Exit the room?'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Exit the room?'), findsNothing);
    expect(find.text('Host a game'), findsOneWidget);
    expect(find.text('ABCD'), findsOneWidget);
    expect(spy.shutdowns, 0);
  });

  testWidgets('tapping outside the dialog counts as No', (tester) async {
    final spy = await openLobby(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Host a game'), findsOneWidget);
    expect(spy.shutdowns, 0);
  });

  testWidgets('system back (Android button / gesture) asks too; Yes closes the room and goes home', (tester) async {
    final spy = await openLobby(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Exit the room?'), findsOneWidget);
    expect(find.text('Host a game'), findsOneWidget, reason: 'not popped yet');
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Host a game'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    expect(spy.shutdowns, 1, reason: 'room closed, guests disconnected');
  });
}
