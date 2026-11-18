import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/bot.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/rules.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);

/// A real bot turn (planner, driver, host commit and end-of-turn tidy) on [table], with the
/// bot holding [rack]. Returns the table after it.
Board botTurn(List<Block> table, List<int> rack) {
  late Board out;
  fakeAsync((async) {
    final h = GameHost(
      players: const [
        PlayerInfo('bot', 'Bot', SeatKind.bot, level: BotLevel.hard),
        PlayerInfo('me', 'Me', SeatKind.human),
      ],
      rules: const HouseRules(firstMeld: 0, turnSeconds: 0),
      seed: 3,
    )
      ..firstStarter = 0
      ..startRound();
    final bd = Board.empty();
    for (final x in table) {
      bd.writeBlock(x);
    }
    final used = {...bd.allTiles, ...rack};
    for (final id in h.racks.keys) {
      h.racks[id]!.removeWhere(used.contains);
    }
    h.pile.removeWhere(used.contains);
    h.racks['bot'] = List.of(rack);
    h.melded.add('bot');
    h.board = bd;
    h.turnStart = bd.copy();
    final d = BotDriver(h, seed: 1)..start();
    async.elapse(const Duration(seconds: 30));
    expect(h.currentPlayer.id, 'me', reason: 'the bot finished its turn');
    out = h.board.copy();
    d.dispose();
    h.dispose();
  });
  return out;
}

int count(Board bd, int row) => bd.rows[row].where((t) => t >= 0).length;

void main() {
  // Nothing in the rack fits the table's sets; only black 5-6-7 makes a new set.
  final rack = [k(5), k(6), k(7), r(9), b(12), y(5), r(13)];

  test('real bot turn: the new set goes into the empty third starting row', () {
    final t = botTurn([
      Block(0, 0, [r(1), r(2), r(3), r(4)]),
      Block(0, 6, [b(1), b(2), b(3), b(4)]),
      Block(1, 0, [y(10), y(11), y(12)]),
    ], rack);
    final at = t.find(k(5))!.row;
    expect(t.blocksInRow(at).map((x) => x.tiles), [[k(5), k(6), k(7)]], reason: 'alone in a row that was empty');
    expect(t.find(r(1))!.row, isNot(at));
    expect(t.find(y(10))!.row, isNot(at));
    expect(t.usedRows.length, 3);
  });

  test('real bot turn: the starting rows are used: the row with the fewest tiles', () {
    final t = botTurn([
      Block(0, 0, [r(1), r(2), r(3), r(4)]),
      Block(0, 6, [b(1), b(2), b(3), b(4)]),
      Block(1, 0, [y(10), y(11), y(12)]),
      Block(2, 0, [b(7), b(8), b(9), b(10), b(11)]),
    ], rack);
    expect(t.find(k(5))!.row, t.find(y(10))!.row);
    expect(t.usedRows.length, 3, reason: 'no new row');
  });
}
