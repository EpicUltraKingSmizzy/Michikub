import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/ui/rules_editor.dart';
import 'package:michikub/ui/theme.dart';

/// A landscape phone (844 x 390) with the keyboard up, taking 60% of the height.
void landscapeWithKeyboard(WidgetTester tester) {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = const FakeViewPadding(bottom: 390 * .6);
  addTearDown(tester.view.reset);
}

void expectStacked(WidgetTester tester, Finder field, List<Finder> buttons, [Finder? title]) {
  final f = tester.getRect(field);
  expect(f.height, greaterThanOrEqualTo(40), reason: 'the field keeps its natural height (was $f)');
  if (title != null) expect(tester.getRect(title).bottom, lessThanOrEqualTo(f.top + 0.5), reason: 'title above the field');
  for (final b in buttons) {
    final r = tester.getRect(b);
    expect(r.overlaps(f), false, reason: 'button $r overlaps the field $f');
    expect(r.top, greaterThanOrEqualTo(f.bottom - 0.5), reason: 'buttons below the field');
  }
}

void main() {
  testWidgets('Save as preset: usable in landscape with the keyboard up', (tester) async {
    landscapeWithKeyboard(tester);
    AppPrefs.instance.presets.clear();
    var rules = HouseRules.classic;
    await tester.pumpWidget(MaterialApp(
      theme: MK.theme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => ListView(children: [
            RulesEditor(rules: rules, onChanged: (r) => set(() => rules = r)),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('Save as preset'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Preset name'), findsOneWidget, reason: 'the hint');
    final field = find.byType(TextField);
    await tester.enterText(field, 'test');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('Save these rules'), findsNothing, reason: 'no title');
    expectStacked(tester, field, [find.text('Cancel'), find.text('Save')]);
    // The keyboard's Done saves.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'dialog closed');
    expect(AppPrefs.instance.presets.containsKey('test'), true);
  });

  testWidgets('the shared form dialog scrolls instead of overflowing, even with tall content', (tester) async {
    landscapeWithKeyboard(tester);
    await tester.pumpWidget(MaterialApp(
      theme: MK.theme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => MkFormDialog(
                  title: 'Invite by message',
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('1. Copy this invite and send it to one friend in any chat app.'),
                    const SizedBox(height: 40),
                    const Text('2. Paste the reply they send back:'),
                    const TextField(maxLines: 3, autofocus: true),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                    TextButton(onPressed: () {}, child: const Text('Connect')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    // Scroll to the buttons; they sit below the field and stay tappable.
    await tester.ensureVisible(find.text('Connect'));
    await tester.pumpAndSettle();
    expectStacked(tester, find.byType(TextField), [find.text('Close'), find.text('Connect')], find.text('Invite by message'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Invite by message'), findsNothing);
  });
}
