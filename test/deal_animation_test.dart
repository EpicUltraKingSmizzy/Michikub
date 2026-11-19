import 'dart:io';
import 'dart:typed_data';

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

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

/// Length of an Ogg Vorbis file in ms: the last page's granule position over the sample rate.
double oggMs(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final id = String.fromCharCodes([1, ...'vorbis'.codeUnits]);
  final text = String.fromCharCodes(bytes);
  final rate = data.getUint32(text.indexOf(id) + 7 + 4 + 1, Endian.little);
  final last = text.lastIndexOf('OggS');
  final granule = data.getUint64(last + 6, Endian.little);
  return granule / rate * 1000;
}

void main() {
  setUp(() => TableTuning.dealAnimation = true);
  tearDown(() => TableTuning.dealAnimation = false);

  test('the deal ends inside the start sound (assets/sfx/start.ogg), and the chime comes after it', () {
    final wash = oggMs('assets/sfx/start.ogg');
    expect(wash, closeTo(1870, 30));
    expect(TableTuning.dealSpanMs, lessThanOrEqualTo(wash));
    expect(TableTuning.dealFlyMs, lessThan(TableTuning.dealSpanMs));
    expect(TableTuning.chimeAfterDealMs, greaterThanOrEqualTo(wash));
  });

  late GameHost host;
  late LocalSession s;

  Future<void> start(WidgetTester tester, {bool hotSeat = false, int hand = 14}) async {
    AppPrefs.instance.highlightValid = false;
    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    host = GameHost(
      players: const [PlayerInfo('p0', 'Ann', SeatKind.human), PlayerInfo('p1', 'Bob', SeatKind.human), PlayerInfo('p2', 'Cy', SeatKind.human)],
      rules: HouseRules(turnSeconds: 0, firstMeld: 0, handSize: hand),
      seed: 3,
    );
    SoundBoard.instance.log.clear();
    s = LocalSession(host, hotSeat: hotSeat);
    await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    s.leave();
    tester.view.reset();
  }

  String badge(WidgetTester tester, String id) =>
      tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('count-$id')), matching: find.byType(Text))).data!;

  Future<void> frames(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('every seat is dealt its hand from the pile, in turn, inside the wash; no draw sound', (tester) async {
    await start(tester, hand: 10);
    final me = s.view!.me;
    final others = [for (final sv in s.view!.seats) if (sv.info.id != me) sv.info.id];
    final pile = tester.getRect(find.byKey(const ValueKey('pile')));
    await tester.pump(const Duration(milliseconds: 16));
    // Early: opponents' racks are still filling, my tiles aren't all home, input is blocked.
    for (final id in others) {
      expect(int.parse(badge(tester, id)), lessThan(10), reason: '$id still being dealt');
    }
    expect(find.byKey(const ValueKey('dealBlock')), findsOneWidget);
    await frames(tester, 900);
    // Halfway: some tiles have landed everywhere, not all.
    for (final id in others) {
      expect(int.parse(badge(tester, id)), inInclusiveRange(1, 9), reason: '$id halfway');
    }
    await frames(tester, 950); // 1.85 s: the deal is done
    for (final id in others) {
      expect(badge(tester, id), '10');
    }
    final rack = s.view!.rack;
    expect(rack.length, 10);
    for (final t in rack) {
      final rect = tester.getRect(find.byKey(ValueKey(t)));
      expect((rect.center - pile.center).distance, greaterThan(50), reason: '${tileLabel(t)} reached the rack');
    }
    expect(find.byKey(const ValueKey('dealBlock')), findsNothing);
    final log = SoundBoard.instance.log;
    expect(log.contains(Sfx.draw), false, reason: 'the wash covers the deal');
    expect(log.first, Sfx.gameStart);
    await finish(tester);
  });

  testWidgets('the starting hand size from the settings is what gets dealt', (tester) async {
    await start(tester, hand: 7);
    await frames(tester, 1900);
    for (final sv in s.view!.seats.where((x) => x.info.id != s.view!.me)) {
      expect(badge(tester, sv.info.id), '7');
    }
    await finish(tester);
  });

  testWidgets('pass-and-play: the deal waits for the cover, then plays with the wash; chime after', (tester) async {
    await start(tester, hotSeat: true);
    await frames(tester, 2500);
    expect(s.coverFor, isNotNull);
    expect(SoundBoard.instance.log, isEmpty);
    s.dismissCover();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('dealBlock')), findsOneWidget);
    expect(SoundBoard.instance.log, [Sfx.gameStart]);
    await frames(tester, 2000);
    expect(find.byKey(const ValueKey('dealBlock')), findsNothing);
    expect(SoundBoard.instance.log, [Sfx.gameStart, Sfx.turnStart]);
    await finish(tester);
  });

  group('long-press pick sound', () {
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
      final start = Board.empty(5)..writeBlock(Block(0, 2, [b(4), b(5), b(6)]))..writeBlock(Block(1, 2, [k(8), k(9)]));
      host.board = start.copy();
      host.turnStart = start.copy();
      host.racks[me] = rack;
      host.handle(me, PreviewAction(start.copy()));
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
      SoundBoard.instance.log.clear();
    }

    Future<void> longPress(WidgetTester tester, int tile) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(tile))));
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a rack run of 3 picked up by long-press: one of the pick bursts', (tester) async {
      await table(tester, [r(1), r(2), r(3), k(13)]);
      await longPress(tester, r(2));
      expect(SoundBoard.instance.log, [Sfx.pick]);
      await finish(tester);
    });

    testWidgets('a table set of 3: the pick sound; a set of 2: none', (tester) async {
      await table(tester, [k(13)]);
      await longPress(tester, b(5));
      expect(SoundBoard.instance.log, [Sfx.pick]);
      // Put it down again (tap the selection to deselect), then a set of 2.
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey(b(5)))));
      await tester.pump(const Duration(milliseconds: 400));
      SoundBoard.instance.log.clear();
      await longPress(tester, k(8));
      expect(SoundBoard.instance.log, isEmpty);
      await finish(tester);
    });

    testWidgets('a rack pair (2 tiles) makes no pick sound', (tester) async {
      await table(tester, [r(1), r(2), k(13)]);
      await longPress(tester, r(1));
      expect(SoundBoard.instance.log, isEmpty);
      await finish(tester);
    });

    test('three pick files, picked at random', () {
      expect(Sfx.pick.files, ['pick_A', 'pick_B', 'pick_C']);
      for (final f in Sfx.pick.files) {
        expect(File('assets/sfx/$f.ogg').existsSync(), true);
        expect(oggMs('assets/sfx/$f.ogg'), inInclusiveRange(250, 500));
      }
    });
  });
}
