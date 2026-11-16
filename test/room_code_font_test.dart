import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/main.dart';
import 'package:michikub/net/online.dart';
import 'package:michikub/ui/online_screens.dart';

void main() {
  test('Space Grotesk OFL licence is registered', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final sg = entries.where((e) => e.packages.contains('Space Grotesk')).toList();
    expect(sg, isNotEmpty);
    final text = sg.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License, Version 1.1'));
    expect(text, contains('The Space Grotesk Project Authors'));
  });

  testWidgets('host lobby shows the room code in Space Grotesk Bold, gold', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final net = NetHost('Ann', const HouseRules(), open: false)..code = 'K7MQ2P';
    await tester.pumpWidget(MaterialApp(home: HostLobbyScreen(net: net)));
    final style = tester.widget<Text>(find.text('K7MQ2P')).style!;
    expect(style.fontFamily, 'SpaceGrotesk');
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, const Color(0xFFFBE08A));
    expect(style.letterSpacing, 6);
  });

  testWidgets('Join screen: the code field uses it too', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: JoinScreen(initialCode: 'ABCD')));
    final field = tester.widgetList<TextField>(find.byType(TextField)).firstWhere((f) => f.controller?.text == 'ABCD');
    expect(field.style!.fontFamily, 'SpaceGrotesk');
  });
}
