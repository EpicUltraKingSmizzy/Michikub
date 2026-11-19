import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/app/sfx.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

import 'deal_animation_test.dart' show oggMs;

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

/// Tapping a tile to select it plays the tile tap (Sfx.select): a fresh single-tile selection
/// only, not a deselect, a long-press set pick-up, or a tap that places the selection.
/// A tile set down alone on the table, in no set, plays the single tile sound (Sfx.placeSingle).
void main() {
  late GameHost host;
  late LocalSession s;

  Future<void> table(WidgetTester tester, List<int> rack) async {
    TableTuning.dealAnimation = false;
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human)],
      rules: const HouseRules(turnSeconds: 0, firstMeld: 0),
      waitForReady: true,
      seed: 1,
    );
    s = LocalSession(host, hotSeat: true);
    final me = host.currentPlayer.id;
    s.dismissCover();
    final start = Board.empty(5)
      ..writeBlock(Block(0, 2, [b(4), b(5), b(6)]))
      ..writeBlock(Block(1, 2, [k(8), k(9)]));
    host.board = start.copy();
    host.turnStart = start.copy();
    host.racks[me] = rack;
    host.handle(me, PreviewAction(start.copy()));
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
    await tester.pump(const Duration(seconds: 3));
    SoundBoard.instance.log.clear();
  }

  Future<void> tap(WidgetTester tester, int tile) async {
    await tester.tapAt(tester.getCenter(find.byKey(ValueKey(tile))));
    await tester.pump(const Duration(milliseconds: 400)); // past the double-tap wait on table tiles
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  List<Sfx> log() => SoundBoard.instance.log;

  /// The table as arranged on screen this turn.
  Board shown(WidgetTester tester) => (tester.state(find.byType(GameScreen)) as dynamic).debugWorking as Board;

  testWidgets('tapping a rack tile selects it with the tile tap; tapping it again deselects silently', (tester) async {
    await table(tester, [r(1), r(5), k(13)]);
    await tap(tester, r(1));
    expect(log(), [Sfx.select]);
    await tap(tester, r(1));
    expect(log(), [Sfx.select], reason: 'deselect: no sound');
    await finish(tester);
  });

  testWidgets('selecting another tile instead plays it again; a table tile can be selected too', (tester) async {
    await table(tester, [r(1), r(5), k(13)]);
    await tap(tester, r(1));
    await tap(tester, r(5));
    expect(log(), [Sfx.select, Sfx.select]);
    log().clear();
    await tap(tester, r(5)); // deselect
    await tap(tester, b(5));
    expect(log(), [Sfx.select]);
    await finish(tester);
  });

  testWidgets('a tap that places the selection on a set plays the attach sound, not the tile tap', (tester) async {
    await table(tester, [b(7), k(13)]);
    await tap(tester, b(7));
    expect(log(), [Sfx.select]);
    log().clear();
    await tap(tester, b(6));
    expect(log(), isNot(contains(Sfx.select)));
    expect(log(), contains(Sfx.attach));
    await finish(tester);
  });

  testWidgets('a tap that cannot place the selection (flashes red) makes no tile tap', (tester) async {
    await table(tester, [r(1), k(13)]);
    await tap(tester, r(1));
    log().clear();
    await tap(tester, b(5));
    expect(log(), isNot(contains(Sfx.select)));
    await finish(tester);
  });

  testWidgets('a long-press set pick-up plays the pick burst only', (tester) async {
    await table(tester, [r(1), r(2), r(3), k(13)]);
    final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(r(2)))));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(log(), [Sfx.pick]);
    await finish(tester);
  });

  /// A spot of empty table: [rows] rows below and [cols] tiles right of tile [from].
  Offset emptyBelow(WidgetTester tester, int from, {double rows = 2, double cols = 5}) {
    final f = find.byKey(ValueKey(from));
    final size = tester.getSize(f);
    return tester.getCenter(f) + Offset(size.width * cols, size.height * 1.15 * rows);
  }

  Future<void> drag(WidgetTester tester, int tile, Offset to) async {
    final from = tester.getCenter(find.byKey(ValueKey(tile)));
    final g = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('single tile set down on its own', () {
    testWidgets('dragged from the rack to empty table space: the single tile sound', (tester) async {
      await table(tester, [r(1), k(13)]);
      await drag(tester, r(1), emptyBelow(tester, b(4)));
      expect(shown(tester).blockOf(r(1))?.tiles, [r(1)], reason: 'a lone tile on the table');
      expect(log(), [Sfx.placeSingle]);
      await finish(tester);
    });

    testWidgets('dragged out of a set to empty table space: the single tile sound', (tester) async {
      await table(tester, [k(13)]);
      await drag(tester, b(6), emptyBelow(tester, b(4)));
      expect(shown(tester).blockOf(b(6))?.tiles, [b(6)]);
      expect(shown(tester).blockOf(b(4))?.tiles, [b(4), b(5)]);
      expect(log(), [Sfx.placeSingle]);
      await finish(tester);
    });

    testWidgets('selected by tap, then a tap on empty table: the tile tap, then the single tile sound', (tester) async {
      await table(tester, [r(1), k(13)]);
      await tap(tester, r(1));
      await tester.tapAt(emptyBelow(tester, b(4)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown(tester).blockOf(r(1))?.tiles, [r(1)]);
      expect(log(), [Sfx.select, Sfx.placeSingle]);
      await finish(tester);
    });

    testWidgets('dragged onto the end of a set: attach, not the single tile sound', (tester) async {
      await table(tester, [b(7), k(13)]);
      final six = find.byKey(ValueKey(b(6)));
      await drag(tester, b(7), tester.getCenter(six) + Offset(tester.getSize(six).width, 0));
      expect(shown(tester).blockOf(b(7))?.tiles, [b(4), b(5), b(6), b(7)]);
      expect(log(), [Sfx.attach]);
      await finish(tester);
    });

    testWidgets('a pair set down on empty table: the place sound, not the single tile sound', (tester) async {
      await table(tester, [r(1), r(2), k(13)]);
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(r(1)))));
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(emptyBelow(tester, b(4)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(shown(tester).blockOf(r(1))?.tiles, [r(1), r(2)]);
      expect(log(), [Sfx.place]);
      await finish(tester);
    });
  });

  test('the single tile file: .ogg and .m4a, short', () {
    expect(Sfx.placeSingle.files, ['tile_single']);
    expect(File('assets/sfx/tile_single.ogg').existsSync(), true);
    expect(File('assets/sfx/tile_single.m4a').existsSync(), true);
    expect(oggMs('assets/sfx/tile_single.ogg'), inInclusiveRange(60, 160));
  });

  test('the tile tap file: .ogg and .m4a, short', () {
    expect(Sfx.select.files, ['tile_tap']);
    expect(File('assets/sfx/tile_tap.ogg').existsSync(), true);
    expect(File('assets/sfx/tile_tap.m4a').existsSync(), true);
    expect(oggMs('assets/sfx/tile_tap.ogg'), inInclusiveRange(60, 150));
  });
}
