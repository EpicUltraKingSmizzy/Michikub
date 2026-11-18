import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/avatars.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/net/online.dart';
import 'package:michikub/ui/online_screens.dart';

void main() {
  test('the avatar set fills the picker: pictures first, then letter avatars', () {
    final c = avatarChoices;
    expect(c.length, kAvatarSlots);
    expect(c.toSet().length, c.length);
    expect(c.first, startsWith('assets/'));
    expect(c.last, startsWith('color:'));
    expect(isKnownAvatar('color:3'), true);
    expect(isKnownAvatar('http://evil'), false);
  });

  testWidgets('Join: tap the avatar, pick one in "Select your avatar", it is saved', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppPrefs.instance.avatar = null;
    await tester.pumpWidget(const MaterialApp(home: JoinScreen()));
    await tester.tap(find.byKey(const ValueKey('avatarButton')));
    await tester.pumpAndSettle();
    expect(find.text('Select your avatar'), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar:color:3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('avatar:color:3')));
    await tester.pumpAndSettle();
    expect(AppPrefs.instance.avatar, 'color:3');
    expect(find.text('Select your avatar'), findsNothing);
  });

  test('online: the host and guests carry their avatars; unknown ones are dropped', () {
    final net = NetHost('Ann', const HouseRules(), open: false, avatar: 'color:5');
    expect(net.seats.first.info.avatar, 'color:5');
    final j = jsonDecode(jsonEncode(net.seats.first.info.toJson())) as Map<String, dynamic>;
    expect(PlayerInfo.fromJson(j).avatar, 'color:5');
  });
}
