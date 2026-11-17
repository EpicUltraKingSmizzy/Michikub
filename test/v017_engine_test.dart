import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);
final j = makeJoker(0);

Board boardOf(List<Block> blocks) {
  final bd = Board.empty();
  for (final x in blocks) {
    bd.writeBlock(x);
  }
  return bd;
}

void main() {
  group('item 4: a number the run already has splits the run', () {
    test('yellow 4 into yellow 3-4-5-6 makes 3-4 and 4-5-6 (user example)', () {
      final bd = boardOf([Block(0, 8, [y(3), y(4), y(5), y(6)])]);
      final out = Layout.dropInto(bd, [y(4, 1)], y(3), 2, col: 10);
      final sets = out.blocksInRow(0).map((x) => x.tiles).toList();
      expect(sets, [
        [y(3), y(4)],
        [y(4, 1), y(5), y(6)],
      ]);
      expect(out.blocksInRow(0)[1].start, out.blocksInRow(0)[0].end + 1, reason: 'one space apart');
    });

    test('splitDuplicate: only for a real tile of that number and colour in a valid run', () {
      final run = boardOf([Block(0, 8, [y(3), y(4), y(5), y(6)])]);
      expect(Layout.splitDuplicate(run, [r(4)], y(3)), isNull, reason: 'other colour');
      expect(Layout.splitDuplicate(run, [y(9)], y(3)), isNull, reason: 'number not in the run');
      expect(Layout.splitDuplicate(run, [j], y(3)), isNull);
      final group = boardOf([Block(0, 8, [r(4), b(4), y(4)])]);
      expect(Layout.splitDuplicate(group, [y(4, 1)], r(4)), isNull, reason: 'groups are not split');
      // At the end: 3-4-5-6 + 6 makes 3-4-5-6 and 6.
      final end = Layout.splitDuplicate(run, [y(6, 1)], y(3))!;
      expect(end.blocksInRow(0).map((x) => x.tiles).toList(), [
        [y(3), y(4), y(5), y(6)],
        [y(6, 1)],
      ]);
    });

    test('a run at the right edge still splits (the parts slide left)', () {
      final bd = boardOf([Block(0, 23, [y(3), y(4), y(5), y(6)])]);
      final out = Layout.splitDuplicate(bd, [y(5, 1)], y(3))!;
      expect(out.blocksInRow(0).map((x) => x.tiles).toList(), [
        [y(3), y(4), y(5)],
        [y(5, 1), y(6)],
      ]);
      expect(out.blocksInRow(0).last.end, lessThanOrEqualTo(Board.width));
    });
  });

  group('items 5 and 11: the joker makes room (joker swap shortcut)', () {
    test('2-3-J + yellow 4: no valid place for the 4, the joker moves: 2-3-4-J (user example)', () {
      final bd = boardOf([Block(0, 8, [y(2), y(3), j])]);
      expect(Layout.hasValidFit(bd, [y(4)], y(2), 1), false);
      final res = Layout.jokerShortcut(bd, y(4), j)!;
      expect(res.board.blockOf(y(2))!.tiles, [y(2), y(3), y(4), j]);
      expect(res.detached, false);
    });

    test('4-4-4-J + the missing 4: 4-4-4-4 and the joker set apart (user example)', () {
      final bd = boardOf([Block(0, 8, [r(4), b(4), y(4), j])]);
      expect(Layout.hasValidFit(bd, [k(4)], r(4), 1), false);
      final res = Layout.jokerShortcut(bd, k(4), j)!;
      expect(res.board.blockOf(r(4))!.tiles.toSet(), {r(4), b(4), y(4), k(4)});
      expect(res.detached, true);
      expect(res.board.blockOf(j)!.tiles, [j], reason: 'the joker stays on the table, alone');
    });

    test('a valid place comes first: 5-J-7 + 8 just extends the run', () {
      final bd = boardOf([Block(0, 8, [y(5), j, y(7)])]);
      expect(Layout.hasValidFit(bd, [y(8)], y(5), 1), true);
      expect(Layout.dropInto(bd, [y(8)], y(5), 1, col: 9).blockOf(y(5))!.tiles, [y(5), j, y(7), y(8)]);
    });
  });
}
