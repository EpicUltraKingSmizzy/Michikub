import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/table_geo.dart';
import 'package:michikub/ui/avatar.dart';
import 'package:michikub/ui/theme.dart';
import 'package:michikub/ui/tiles_view.dart';

/// v0.1.8: side seats' face-down racks start below the whole name plate (a bot's
/// "Name (Level)" takes two lines), they still fit above the bottom corners, and the right
/// seat clears the pile count.
List<Rect> rectsOf(Finder f) => [
      for (final e in f.evaluate())
        if (e.renderObject case final RenderBox box when box.hasSize) box.localToGlobal(Offset.zero) & box.size,
    ];

void main() {
  const phones = [Size(667, 375), Size(740, 360), Size(800, 360), Size(844, 390), Size(915, 412), Size(932, 430)];

  for (final phone in phones) {
    testWidgets('side seats and the pile don\'t overlap at ${phone.width.toInt()}x${phone.height.toInt()}', (tester) async {
      AppPrefs.instance.highlightValid = false;
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The test font's wide glyphs overflow the button rows at phone widths; that's not what
      // this test is about (the app's font fits), so only RenderFlex overflows are ignored.
      final onError = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.exceptionAsString().contains('A RenderFlex overflowed')) onError?.call(d);
      };
      final host = GameHost(
        players: const [
          PlayerInfo('p0', 'Ann', SeatKind.human),
          PlayerInfo('p1', 'Mochi (Medium)', SeatKind.bot),
          PlayerInfo('p2', 'Bolt (Hard)', SeatKind.bot),
          PlayerInfo('p3', 'Pip (Medium)', SeatKind.bot),
        ],
        rules: const HouseRules(turnSeconds: 60, handSize: 24), // long racks: three squeezed columns
        seed: 3,
      );
      final s = LocalSession(host, hotSeat: false);
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));

      final w = phone.width;
      final backs = rectsOf(find.byType(GoldBack));
      final g = TableGeo(phone, boardRows: 3, rackEntries: const [1], seatCount: 4);
      final left = backs.where((r) => r.center.dx < g.sideW && r.top > g.topH).toList();
      final right = backs.where((r) => r.center.dx > w - g.sideW && r.top > g.topH).toList();
      expect([left.length, right.length], [24, 24]);

      for (final name in ['Mochi (Medium)', 'Pip (Medium)']) {
        final plate = tester.getRect(find.textContaining(name));
        final side = plate.center.dx < w / 2 ? left : right;
        final top = side.map((r) => r.top).reduce((a, b) => a < b ? a : b);
        expect(top, greaterThanOrEqualTo(plate.bottom), reason: '$name: rack starts below the name plate');
      }

      // Nothing on the screen overlaps a face-down tile: texts, buttons, avatars.
      final others = [
        ...rectsOf(find.byType(Text)),
        ...rectsOf(find.byType(GoldButton)),
        ...rectsOf(find.byType(PlayerAvatar)),
      ];
      for (final b in [...left, ...right]) {
        expect(b.bottom, lessThanOrEqualTo(phone.height));
        for (final o in others) {
          expect(b.deflate(.5).overlaps(o), false, reason: 'back $b overlaps $o');
        }
      }

      // The right seat's avatar (and its count badge, 6 px above it) clears the pile count.
      final pileText = tester.getRect(find.text('IN PILE'));
      final avatars = rectsOf(find.byType(PlayerAvatar));
      final rightAvatar = avatars.firstWhere((r) => r.center.dx > w - g.sideW && r.center.dy < phone.height / 2);
      expect(rightAvatar.top - 6, greaterThan(pileText.bottom), reason: 'right seat below the pile count');

      await tester.pumpWidget(const SizedBox());
      host.dispose();
      FlutterError.onError = onError;
    });
  }
}
