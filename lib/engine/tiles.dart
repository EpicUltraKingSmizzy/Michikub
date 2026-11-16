/// Tile identities. Every tile is a small int so boards and racks are cheap
/// to copy, compare and send over the network.
///
/// Numbered tiles: id = copy * 52 + colour * 13 + (number - 1), ids 0..103.
/// Jokers: id = 104 + jokerIndex (0 red, 1 black, 2 yellow, 3 blue).
library;

enum TileColor { red, blue, yellow, black }

const int kNumberedTiles = 104;
const int kJokerBase = 104;
const int kJokerPenalty = 30;

/// Colour of each joker by index: classic play uses red and black, then a
/// third joker is yellow and a fourth is blue.
const List<TileColor> kJokerColors = [
  TileColor.red,
  TileColor.black,
  TileColor.yellow,
  TileColor.blue,
];

bool isJoker(int id) => id >= kJokerBase;

int tileNumber(int id) => isJoker(id) ? 0 : (id % 13) + 1;

TileColor tileColor(int id) =>
    isJoker(id) ? kJokerColors[id - kJokerBase] : TileColor.values[(id % 52) ~/ 13];

int makeTile(TileColor c, int number, {int copy = 0}) =>
    copy * 52 + c.index * 13 + (number - 1);

int makeJoker(int index) => kJokerBase + index;

/// Penalty value of a tile left in a rack at round end.
int tilePenalty(int id) => isJoker(id) ? kJokerPenalty : tileNumber(id);

String tileLabel(int id) {
  const letters = ['r', 'b', 'y', 'k'];
  if (isJoker(id)) return 'J${letters[tileColor(id).index]}';
  return '${letters[tileColor(id).index]}${tileNumber(id)}';
}

/// All tiles for a game with [jokers] jokers (0..4).
List<int> fullSet(int jokers) => [
      for (var i = 0; i < kNumberedTiles; i++) i,
      for (var j = 0; j < jokers; j++) makeJoker(j),
    ];

/// Sort key helpers for the rack sort buttons.
int runSortKey(int id) =>
    isJoker(id) ? 10000 + id : tileColor(id).index * 100 + tileNumber(id) * 2 + (id >= 52 ? 1 : 0);

int groupSortKey(int id) =>
    isJoker(id) ? 10000 + id : tileNumber(id) * 100 + tileColor(id).index * 2 + (id >= 52 ? 1 : 0);
