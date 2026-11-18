import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/rack_sort.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int k(int n) => makeTile(TileColor.black, n);
int y(int n) => makeTile(TileColor.yellow, n);

Board boardOf(List<Block> blocks) {
  final bd = Board.empty();
  for (final x in blocks) {
    bd.writeBlock(x);
  }
  return bd;
}

int count(Board bd, int row) => bd.rows[row].where((t) => t >= 0).length;

void main() {
  group('item 4: bots put a new set in the row with tiles but the fewest', () {
    test('the emptier used row, not the first row', () {
      final bd = boardOf([
        Block(0, 2, [r(1), r(2), r(3), r(4), r(5)]),
        Block(0, 10, [b(1), b(2), b(3)]),
        Block(1, 5, [k(1), k(2), k(3)]),
      ]);
      final out = applyBotStep(bd, BotStep.newSet([y(7), y(8), y(9)]));
      expect(out.find(y(7))!.row, 1);
    });
    test('an empty table: the usual spot', () {
      final out = applyBotStep(Board.empty(), BotStep.newSet([y(7), y(8), y(9)]));
      expect(out.find(y(7))!.row, 0);
    });
  });

  group('item 5: end-of-turn row balancing', () {
    test('a crowded row gives one set to the emptiest of the first 3 rows', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3), r(4)]),
        Block(0, 5, [b(1), b(2), b(3), b(4)]),
        Block(0, 10, [k(1), k(2), k(3), k(4)]),
        Block(0, 15, [y(1), y(2), y(3), y(4)]),
        Block(1, 0, [r(9), r(10), r(11)]),
      ]);
      final t = Layout.tidy(bd);
      expect([count(t, 0), count(t, 1), count(t, 2)], [12, 3, 4], reason: 'one 4-run moved to the empty row 2');
      expect(t.usedRows, [0, 1, 2]);
    });
    test('never opens a new row below the first 3', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3), r(4)]),
        Block(0, 5, [b(1), b(2), b(3), b(4)]),
        Block(0, 10, [k(1), k(2), k(3), k(4)]),
        Block(0, 15, [y(1), y(2), y(3), y(4)]),
        Block(1, 0, [r(9), r(10), r(11)]),
        Block(1, 5, [b(9), b(10), b(11)]),
        Block(2, 0, [k(9), k(10), k(11)]),
        Block(2, 5, [y(9), y(10), y(11)]),
      ]);
      final t = Layout.tidy(bd);
      expect(t.usedRows, [0, 1, 2]);
      expect(count(t, 0), 12, reason: 'moved into row 1 or 2 (6 tiles), not a new row 3');
    });
    test('a small difference is left alone', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3), r(4), r(5)]),
        Block(0, 8, [b(1), b(2), b(3)]),
      ]);
      expect(count(Layout.tidy(bd), 0), 8);
    });
  });

  test('item 12: an empty top rack row: the bottom row moves up, same columns', () {
    final e = [for (var i = 0; i < 10; i++) -10 - i, 101, -1, 102, 103];
    expect(raiseRack(e), [101, -1, 102, 103]);
    expect(raiseRack([101, -1, 102]), [101, -1, 102]);
  });
}
