import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/meld.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n, [int copy = 0]) => makeTile(TileColor.red, n, copy: copy);
int b(int n, [int copy = 0]) => makeTile(TileColor.blue, n, copy: copy);
int y(int n, [int copy = 0]) => makeTile(TileColor.yellow, n, copy: copy);
int k(int n, [int copy = 0]) => makeTile(TileColor.black, n, copy: copy);

Board boardOf(List<Block> blocks, [int rows = 5]) {
  final bd = Board.empty(rows);
  for (final x in blocks) {
    bd.writeBlock(x);
  }
  return bd;
}

/// Row contents as "start:tiles" per set, for readable expectations.
List<List<String>> layout(Board bd) => [
      for (var row = 0; row < bd.rowCount; row++) [for (final x in bd.blocksInRow(row)) '${x.start}:${x.tiles.length}'],
    ];

GameHost hostFor(List<PlayerInfo> players, {int firstMeld = 0, Board? board}) {
  final h = GameHost(players: players, rules: HouseRules(turnSeconds: 0, firstMeld: firstMeld), seed: 1);
  for (final p in players) {
    h.racks[p.id] = [k(13, 1)];
  }
  h.pile = [k(1, 1), k(2, 1), k(3, 1)];
  final bd = board ?? Board.empty();
  h.board = bd.copy();
  h.turnStart = bd.copy();
  return h;
}

void main() {
  group('1. out of tiles with a valid table ends the round at once', () {
    const ann = PlayerInfo('a', 'Ann', SeatKind.human), bob = PlayerInfo('b', 'Bob', SeatKind.human);

    test('human: the preview that empties the rack ends the round (no End turn needed)', () {
      final h = hostFor([ann, bob]);
      h.racks['a'] = [r(5), r(6), r(7)];
      expect(h.handle('a', PreviewAction(boardOf([Block(0, 2, [r(5), r(6)])]))).ok, true);
      expect(h.result, isNull, reason: 'still holding a tile');
      expect(h.handle('a', PreviewAction(boardOf([Block(0, 2, [r(5), r(6), r(7)])]))).ok, true);
      expect(h.result, isNotNull);
      expect(h.result!.winnerId, 'a');
      expect(h.result!.reason, 'out');
      expect(h.board.sets.single, [r(5), r(6), r(7)]);
    });

    test('an invalid table, or a first meld below the minimum, does not end it', () {
      final h = hostFor([ann, bob]);
      h.racks['a'] = [r(5), r(6), b(9)];
      expect(h.handle('a', PreviewAction(boardOf([Block(0, 2, [r(5), r(6), b(9)])]))).ok, true);
      expect(h.result, isNull);
      final h2 = hostFor([ann, bob], firstMeld: 30);
      h2.racks['a'] = [r(5), r(6), r(7)];
      expect(h2.handle('a', PreviewAction(boardOf([Block(0, 2, [r(5), r(6), r(7)])]))).ok, true);
      expect(h2.result, isNull, reason: '18 points is below the 30-point first meld');
    });

    test('online guest: the host ends the round from the guest\'s preview (JSON action)', () {
      final h = hostFor([ann, bob]);
      h.current = 1;
      h.racks['b'] = [y(1), y(2), y(3)];
      final a = GameAction.fromJson(PreviewAction(boardOf([Block(1, 4, [y(1), y(2), y(3)])])).toJson());
      expect(h.handle('b', a).ok, true);
      expect(h.result?.winnerId, 'b');
      // Every player sees the same final table.
      expect(h.viewFor('a').board.toJson(), h.viewFor('b').board.toJson());
    });

    test('bot: the round ends as soon as its last tile is down', () async {
      const bot = PlayerInfo('b', 'Bolt', SeatKind.bot, level: BotLevel.hard);
      final h = hostFor([ann, bot]);
      h.current = 1;
      h.racks['b'] = [y(4), y(5), y(6)];
      final d = BotDriver(h, speed: 200, planOverride: (_, _) => BotPlan.ofSteps([BotStep.newSet([y(4), y(5), y(6)])]));
      d.start();
      for (var i = 0; i < 100 && h.result == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(h.result?.winnerId, 'b');
      d.dispose();
      h.dispose();
    });
  });

  group('2. dropping onto a set goes to a valid end', () {
    test('yellow 4 into the middle of 5-6-7-8 makes 4-5-6-7-8 (user example)', () {
      final bd = boardOf([Block(0, 6, [y(5), y(6), y(7), y(8)])]);
      final out = Layout.dropInto(bd, [y(4)], y(5), 2);
      expect(out.sets.single, [y(4), y(5), y(6), y(7), y(8)]);
    });

    test('1-2-3-4 onto 5-6-7-8 makes 1-2-3-4-5-6-7-8 (user example)', () {
      final bd = boardOf([Block(0, 2, [b(1), b(2), b(3), b(4)]), Block(1, 6, [b(5), b(6), b(7), b(8)])]);
      final out = Layout.dropInto(bd, [b(1), b(2), b(3), b(4)], b(5), 2);
      expect(out.sets.single, [for (var n = 1; n <= 8; n++) b(n)]);
    });

    test('a tile that fits at the high end goes there; both ends: the nearer one', () {
      final bd = boardOf([Block(0, 6, [y(5), y(6), y(7)])]);
      expect(Layout.dropInto(bd, [y(8)], y(5), 1).sets.single, [y(5), y(6), y(7), y(8)]);
      final j = makeJoker(0);
      expect(Layout.dropInto(bd, [j], y(5), 1).sets.single, [j, y(5), y(6), y(7)]);
    });

    test('groups: a fitting tile is added; no valid placement drops where dragged', () {
      final g = boardOf([Block(0, 6, [r(7), b(7), y(7)])]);
      final added = Layout.dropInto(g, [k(7)], r(7), 1).sets.single;
      expect(added.toSet(), {r(7), b(7), y(7), k(7)});
      expect(isValidMeld(added), true);
      final run = boardOf([Block(0, 6, [y(5), y(6), y(7), y(8)])]);
      expect(Layout.dropInto(run, [r(2)], y(5), 2).sets.single, [y(5), y(6), r(2), y(7), y(8)]);
    });

    test('a set at the board edge slides over to take the tile at its front', () {
      final bd = boardOf([Block(0, 0, [y(5), y(6), y(7), y(8)])]);
      final out = Layout.dropInto(bd, [y(4)], y(5), 2);
      expect(out.sets.single, [y(4), y(5), y(6), y(7), y(8)]);
      expect(out.blocksInRow(0).single.start, 0);
    });
  });

  group('2b. tiles that don\'t fit shunt the set aside', () {
    Block rowSet(Board bd, int t) => bd.blockOf(t)!;

    test('blue 4 onto yellow 5-6-7-8: the 4 stays where dropped, the run moves over (user example)', () {
      final bd = boardOf([Block(0, 10, [y(5), y(6), y(7), y(8)])]);
      // Dropped on the 7 (right half): the run moves left.
      final out = Layout.dropInto(bd, [b(4)], y(5), 2, col: 12);
      expect(out.find(b(4)), (row: 0, col: 12));
      expect(rowSet(out, b(4)).tiles, [b(4)]);
      final run = rowSet(out, y(5));
      expect(run.tiles, [y(5), y(6), y(7), y(8)]);
      expect(run.row, 0);
      expect(run.end, 11, reason: 'left of the 4 with a 1-space gap');
      // Dropped on the 5 (left half): the run moves right.
      final out2 = Layout.dropInto(bd, [b(4)], y(5), 0, col: 10);
      expect(out2.find(b(4)), (row: 0, col: 10));
      expect(rowSet(out2, y(5)).start, 12);
    });

    test('no room on the preferred side: the set goes the other way', () {
      final bd = boardOf([Block(0, 0, [y(5), y(6), y(7), y(8)])]);
      final out = Layout.dropInto(bd, [b(4)], y(5), 3, col: 3); // right half, but no room left
      expect(out.find(b(4)), (row: 0, col: 3));
      expect(rowSet(out, y(5)).start, 5);
    });

    test('neighbours are pushed with 1-space gaps', () {
      final bd = boardOf([Block(0, 10, [y(5), y(6), y(7), y(8)]), Block(0, 5, [r(1), r(2), r(3)])]);
      final out = Layout.dropInto(bd, [b(4)], y(5), 2, col: 12);
      expect(out.find(b(4)), (row: 0, col: 12));
      final runs = out.blocksInRow(0).map((x) => '${x.start}-${x.end - 1}').toList();
      expect(runs, ['3-5', '7-10', '12-12']);
    });

    test('several tiles that don\'t fit stay together where dropped', () {
      final bd = boardOf([Block(0, 10, [y(5), y(6), y(7), y(8)])]);
      final out = Layout.dropInto(bd, [r(1), r(2), r(3)], y(5), 1, col: 11);
      expect(rowSet(out, r(1)).tiles, [r(1), r(2), r(3)]);
      expect(out.find(r(1)), (row: 0, col: 11));
      expect(rowSet(out, y(5)).start, 15);
    });

    test('groups are shunted too', () {
      final bd = boardOf([Block(0, 10, [r(7), b(7), y(7)])]);
      final out = Layout.dropInto(bd, [b(3)], r(7), 1, col: 11);
      expect(rowSet(out, b(3)).tiles, [b(3)]);
      expect(rowSet(out, r(7)).tiles, [r(7), b(7), y(7)]);
    });

    test('a set still being built takes compatible tiles (no shunt)', () {
      final bd = boardOf([Block(0, 10, [y(5)])]);
      expect(rowSet(Layout.dropInto(bd, [y(6)], y(5), 0, col: 10), y(5)).tiles, [y(6), y(5)].reversed.toList());
      final pair = boardOf([Block(0, 10, [r(9), b(9)])]);
      expect(rowSet(Layout.dropInto(pair, [k(9)], r(9), 1, col: 11), r(9)).tiles.toSet(), {r(9), b(9), k(9)});
    });

    test('a valid fit still wins over shunting (joker, ends)', () {
      final bd = boardOf([Block(0, 10, [y(5), y(6), y(7), y(8)])]);
      expect(rowSet(Layout.dropInto(bd, [y(9)], y(5), 1, col: 11), y(5)).tiles, [y(5), y(6), y(7), y(8), y(9)]);
    });
  });

  group('3. end-of-turn compacting', () {
    test('sets move toward the middle with 1-space gaps, in the same order', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3)]),
        Block(0, 10, [b(4), b(5), b(6)]),
        Block(0, 22, [k(9), k(10), k(11), k(12)]),
      ]);
      final t = Layout.tidy(bd);
      // 3 + 1 + 3 + 1 + 4 = 12 wide, centred in 27: starts at 7.
      expect(t.blocksInRow(0).map((x) => '${x.start}:${x.tiles.first}').toList(), ['7:${r(1)}', '11:${b(4)}', '15:${k(9)}']);
    });

    test('the host tidies every played turn', () {
      final h = hostFor([const PlayerInfo('a', 'Ann', SeatKind.human), const PlayerInfo('b', 'Bob', SeatKind.human)]);
      h.racks['a'] = [r(5), r(6), r(7), k(1)];
      expect(h.handle('a', CommitAction(boardOf([Block(0, 0, [r(5), r(6), r(7)])]))).ok, true);
      expect(h.board.blocksInRow(0).single.start, 12);
    });
  });

  group('4. row collapse', () {
    test('more than 3 rows: a lone set moves into an adjacent row (same columns or 1 over)', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3)]),
        Block(1, 0, [b(1), b(2), b(3)]),
        Block(2, 0, [k(1), k(2), k(3)]),
        Block(3, 1, [y(1), y(2), y(3)]),
        Block(3, 20, [y(9), y(10), y(11)]),
        Block(4, 14, [r(9), r(10), r(11)]), // alone; row 3 has room at 14-16
      ]);
      final t = Layout.tidy(bd);
      expect(t.usedRows.length, 4, reason: 'the lone set in row 4 joined row 3');
      expect(t.blocksInRow(3).map((x) => x.tiles.first).toList(), [y(1), r(9), y(9)]);
    });

    test('a lone set that would have to move 2 columns stays in its row', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3)]),
        Block(1, 0, [b(1), b(2), b(3)]),
        Block(2, 0, [k(1), k(2), k(3), k(4), k(5), k(6)]),
        Block(2, 13, [y(9), y(10), y(11)]),
        Block(3, 5, [r(9), r(10), r(11)]), // fits in row 2 only at column 7: 2 over
      ]);
      final t = Layout.tidy(bd);
      expect(t.usedRows.length, 4);
      expect(t.blocksInRow(3).single.tiles, [r(9), r(10), r(11)]);
    });

    test('lone set moves 1 column over into the row above', () {
      final bd = boardOf([
        Block(0, 0, [r(1), r(2), r(3)]),
        Block(1, 0, [b(1), b(2), b(3)]),
        Block(2, 0, [k(1), k(2), k(3)]),
        Block(3, 3, [y(1), y(2), y(3)]), // row 2 has k at 0-2: no gap at columns 3-5, but 4-6 fits
      ]);
      final t = Layout.tidy(bd);
      expect(t.usedRows, [0, 1, 2]);
      expect(t.blocksInRow(2).map((x) => x.tiles.first).toList(), [k(1), y(1)]);
    });

    test('rows 1, 3, 4 used and row 2 empty: row 1 moves down to row 2 (user example)', () {
      final bd = boardOf([
        Block(0, 2, [r(1), r(2), r(3)]),
        Block(2, 2, [b(1), b(2), b(3)]),
        Block(2, 10, [b(9), b(10), b(11)]),
        Block(3, 2, [k(1), k(2), k(3)]),
        Block(3, 10, [k(9), k(10), k(11)]),
      ]);
      final t = Layout.tidy(bd);
      // Then the empty top row goes, so the table starts at the top and the view zooms in.
      expect(t.usedRows, [0, 1, 2]);
      expect(t.blocksInRow(0).single.tiles, [r(1), r(2), r(3)]);
      expect(t.blocksInRow(1).first.tiles, [b(1), b(2), b(3)]);
      expect(t.blocksInRow(2).first.tiles, [k(1), k(2), k(3)]);
      expect(t.rowCount, 5);
    });

    test('3 rows or fewer in use are left alone (apart from compacting)', () {
      final bd = boardOf([Block(0, 0, [r(1), r(2), r(3)]), Block(2, 0, [b(1), b(2), b(3)])]);
      expect(Layout.tidy(bd).usedRows, [0, 2]);
    });
  });

  group('5. empty outer rows', () {
    test('empty rows above the top set are removed at the end of the turn', () {
      final bd = boardOf([Block(2, 0, [r(1), r(2), r(3)]), Block(3, 0, [b(1), b(2), b(3)])]);
      final t = Layout.tidy(bd);
      expect(t.usedRows, [0, 1]);
      expect(t.rowCount, 5);
    });
  });
}
