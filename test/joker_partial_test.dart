import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/prefs.dart';
import 'package:michikub/app/session.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
const j = kJokerBase;

/// An unfinished set with a joker (1-J, J-1, 5-J, ...) stays open to being a run or a group:
/// a tile that makes a run with it moves the joker where the run needs it.
void main() {
  group('engine', () {
    Board pair(List<int> tiles) => Board.empty(3)..writeBlock(Block(1, 8, tiles));
    List<int>? setOf(Board bd, int t) => bd.blockOf(t)?.tiles;

    test("J-1 + 3 (the user's case): 1-J-3, the joker is the 2", () {
      expect(Layout.jokerRearranged([j, y(1)], [y(3)]), [y(1), j, y(3)]);
    });

    test('the joker moves into the gap, whichever side it was on', () {
      expect(Layout.jokerRearranged([y(3), j], [y(1)]), [y(1), j, y(3)]);
      expect(Layout.jokerRearranged([j, y(5)], [y(7)]), [y(5), j, y(7)]);
      expect(Layout.jokerRearranged([y(5), j], [y(3)]), [y(3), j, y(5)]);
      expect(Layout.jokerRearranged([y(13), j], [y(11)]), [y(11), j, y(13)]);
    });

    test('1-J + 2: the joker goes to the high end (1-2-J); past 13 it goes to the low end', () {
      expect(Layout.jokerRearranged([y(1), j], [y(2)]), [y(1), y(2), j]);
      expect(Layout.jokerRearranged([y(12), j], [y(13)]), [j, y(12), y(13)]);
    });

    test('no run possible: null (a different colour, too far apart, a complete set, no joker)', () {
      expect(Layout.jokerRearranged([r(1), j], [y(3)]), isNull);
      expect(Layout.jokerRearranged([y(1), j], [y(4)]), isNull);
      expect(Layout.jokerRearranged([y(1), j, y(3)], [y(5)]), isNull);
      expect(Layout.jokerRearranged([y(1), y(2)], [y(4)]), isNull);
      expect(Layout.jokerRearranged([y(4), j], [r(4)]), isNull, reason: 'a group: fits at an end already');
    });

    for (final index in [0, 1, 2]) {
      test('dropped onto J-1 at index $index: 1-J-3', () {
        final out = Layout.dropInto(pair([j, y(1)]), [y(3)], j, index);
        expect(setOf(out, y(3)), [y(1), j, y(3)]);
        expect(out.isValid, true);
      });
    }

    test('dropped right beside J-1, on either side: 1-J-3', () {
      final bd = pair([j, y(1)]);
      expect(setOf(Layout.dropBeside(bd, [y(3)], 1, 10)!, y(3)), [y(1), j, y(3)]);
      expect(setOf(Layout.dropBeside(bd, [y(3)], 1, 7)!, y(3)), [y(1), j, y(3)]);
    });

    test('the set grows left when the new tile goes in front (5-J + 3 stays put otherwise)', () {
      final out = Layout.dropInto(pair([y(5), j]), [y(3)], y(5), 0);
      final blk = out.blockOf(y(3))!;
      expect(blk.tiles, [y(3), j, y(5)]);
      expect(blk.start, 7);
    });

    test('groups still build as before: 4-J + a red 4', () {
      expect(setOf(Layout.dropInto(pair([y(4), j]), [r(4)], y(4), 2), r(4)), [y(4), j, r(4)]);
    });

    test('a complete set with a joker keeps the joker swap: 2-3-J + 4 is not rearranged here', () {
      expect(Layout.jokerRearranged([y(2), y(3), j], [y(4)]), isNull);
    });
  });

  group('on the table (drag and tap)', () {
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
      final start = Board.empty(5)..writeBlock(Block(0, 2, [b(4), b(5), b(6)]));
      host.board = start.copy();
      host.turnStart = start.copy();
      host.racks[me] = rack;
      host.handle(me, PreviewAction(start.copy()));
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
    }

    Board shown(WidgetTester tester) => (tester.state(find.byType(GameScreen)) as dynamic).debugWorking as Board;
    Offset at(WidgetTester tester, int t) => tester.getCenter(find.byKey(ValueKey(t)));
    double tileW(WidgetTester tester) => tester.getSize(find.byKey(ValueKey(b(4)))).width;

    Future<void> drag(WidgetTester tester, int tile, Offset to) async {
      final from = at(tester, tile);
      final g = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Builds the unfinished [partial] on the table by dragging its tiles from the rack.
    Future<void> build(WidgetTester tester, List<int> partial) async {
      final w = tileW(tester);
      await drag(tester, partial[0], at(tester, b(4)) + Offset(w * 4, w * 2.6));
      await drag(tester, partial[1], at(tester, partial[0]) + Offset(w * .3, 0));
      expect(shown(tester).blockOf(partial[0])!.tiles, partial);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    final cases = <(String, List<int>, int, List<int>?)>[
      ("J-1 + 3 (the user's case)", [j, y(1)], y(3), [y(1), j, y(3)]),
      ('1-J + 3', [y(1), j], y(3), [y(1), j, y(3)]),
      ('3-J + 1', [y(3), j], y(1), [y(1), j, y(3)]),
      ('1-J + 2', [y(1), j], y(2), [y(1), y(2), j]),
      ('J-5 + 7', [j, y(5)], y(7), [y(5), j, y(7)]),
      ('5-J + 3', [y(5), j], y(3), [y(3), j, y(5)]),
      ('red 1-J + yellow 3: refused', [r(1), j], y(3), null),
    ];
    const ways = ['onto the 1st tile', 'onto the 2nd tile', 'beside, on the left', 'beside, on the right', 'tap, then tap the 1st tile', 'tap, then tap the 2nd tile'];
    for (final (name, partial, t, want) in cases) {
      for (final how in ways) {
        testWidgets('$name: $how', (tester) async {
          await table(tester, [...partial, t, k(13)]);
          await build(tester, partial);
          final w = tileW(tester);
          final first = at(tester, partial[0]), second = at(tester, partial[1]);
          switch (how) {
            case 'onto the 1st tile':
              await drag(tester, t, first);
            case 'onto the 2nd tile':
              await drag(tester, t, second);
            case 'beside, on the left':
              await drag(tester, t, first - Offset(w, 0));
            case 'beside, on the right':
              await drag(tester, t, second + Offset(w, 0));
            default:
              await tester.tapAt(at(tester, t));
              await tester.pump(const Duration(milliseconds: 400));
              await tester.tapAt(how.endsWith('1st tile') ? first : second);
              await tester.pump(const Duration(milliseconds: 600));
          }
          final set = shown(tester).blockOf(partial[0])!.tiles;
          if (want != null) {
            expect(set, want);
          } else {
            expect(set, partial, reason: "the yellow 3 doesn't join the red pair");
          }
          await finish(tester);
        });
      }
    }

    testWidgets("a group still builds: J-4 + another colour's 4", (tester) async {
      await table(tester, [j, y(4), r(4), k(13)]);
      await build(tester, [j, y(4)]);
      await drag(tester, r(4), at(tester, y(4)) + Offset(tileW(tester), 0));
      final set = shown(tester).blockOf(y(4))!.tiles;
      expect(set.toSet(), {j, y(4), r(4)});
      await finish(tester);
    });
  });
}
