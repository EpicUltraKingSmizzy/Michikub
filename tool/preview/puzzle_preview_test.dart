// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders preview images with the app's real fonts (not a test; run on demand):
//   flutter test tool/preview/puzzle_preview_test.dart
// Writes /workspace/michikub-preview/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/puzzles.dart';
import 'package:michikub/engine/puzzle.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/puzzles_screen.dart';
import 'package:michikub/ui/theme.dart';

Future<void> loadFonts() async {
  for (final (family, file) in [('Rubik', 'assets/fonts/Rubik.ttf'), ('Playfair', 'assets/fonts/Playfair.ttf')]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('/workspace/michikub-preview').createSync(recursive: true);
    File('/workspace/michikub-preview/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      final w = e.widget as Image;
      await precacheImage(w.image, e);
    }
    for (final e in find.byType(DecoratedBox).evaluate()) {
      final d = (e.widget as DecoratedBox).decoration;
      if (d is BoxDecoration && d.image != null) await precacheImage(d.image!.image, e);
    }
  });
  await tester.pump();
}

void main() {
  testWidgets('difficulty buttons preview', (tester) async {
    await loadFonts();
    tester.view.physicalSize = const Size(560, 420);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(
          body: WoodBackground(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Puzzle buttons: empty, half, full (with the star)', style: MK.body(14, color: MK.gold)),
                const SizedBox(height: 18),
                const PuzzleLevelButton(label: 'Easy', solved: 0, total: 400),
                const SizedBox(height: 14),
                const PuzzleLevelButton(label: 'Medium', solved: 200, total: 400),
                const SizedBox(height: 14),
                const PuzzleLevelButton(label: 'Hard', solved: 400, total: 400),
                const SizedBox(height: 22),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const GoldStar(size: 72),
                  const SizedBox(width: 12),
                  Text('The star, close up', style: MK.body(14, color: MK.creamText)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ));
    await precache(tester);
    await shoot(tester, key, 'puzzle_buttons_preview');
  });

  testWidgets('puzzle table (for checking the layout)', (tester) async {
    await loadFonts();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    TableTuning.dealAnimation = false;
    final pack = PuzzlePack.parse(File('assets/puzzles/puzzles.json').readAsStringSync());
    for (final (l, i) in [(PuzzleLevel.easy, 0), (PuzzleLevel.hard, 399)]) {
      final key = GlobalKey();
      final s = PuzzleSession(level: l, pack: pack, openIndex: i);
      await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: RepaintBoundary(key: key, child: GameScreen(session: s))));
      await tester.pump(const Duration(seconds: 3));
      await precache(tester);
      await shoot(tester, key, 'puzzle_table_${l.name}');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
