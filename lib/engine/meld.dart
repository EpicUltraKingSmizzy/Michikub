import 'tiles.dart';

enum MeldKind { run, group }

class MeldInfo {
  final MeldKind kind;
  final int points;

  /// The value each tile stands for, joker values included.
  final List<int> values;
  const MeldInfo(this.kind, this.points, this.values);
}

/// Checks an ordered set of tiles as it lies on the board.
///
/// Runs must ascend left to right in one colour (jokers fill gaps, and
/// their position decides their value). Groups are 3 or 4 tiles of one
/// number in different colours. A set must hold at least one numbered tile.
/// When both readings are valid (for example `5r J J`) the higher-scoring
/// one is used.
MeldInfo? analyzeMeld(List<int> tiles) {
  if (tiles.length < 3) return null;
  final run = _asRun(tiles);
  final group = _asGroup(tiles);
  if (run != null && group != null) return run.points >= group.points ? run : group;
  return run ?? group;
}

bool isValidMeld(List<int> tiles) => analyzeMeld(tiles) != null;

int meldPoints(List<int> tiles) => analyzeMeld(tiles)?.points ?? 0;

MeldInfo? _asRun(List<int> tiles) {
  if (tiles.length > 13) return null;
  TileColor? color;
  int? start;
  for (var i = 0; i < tiles.length; i++) {
    final t = tiles[i];
    if (isJoker(t)) continue;
    final c = tileColor(t);
    if (color != null && c != color) return null;
    color = c;
    final s = tileNumber(t) - i;
    if (start != null && s != start) return null;
    start = s;
  }
  if (start == null) return null; // all jokers
  if (start < 1 || start + tiles.length - 1 > 13) return null;
  final values = [for (var i = 0; i < tiles.length; i++) start + i];
  return MeldInfo(MeldKind.run, values.fold(0, (a, b) => a + b), values);
}

MeldInfo? _asGroup(List<int> tiles) {
  if (tiles.length > 4) return null;
  int? number;
  final colors = <TileColor>{};
  for (final t in tiles) {
    if (isJoker(t)) continue;
    if (number != null && tileNumber(t) != number) return null;
    number = tileNumber(t);
    if (!colors.add(tileColor(t))) return null;
  }
  if (number == null) return null;
  final values = List<int>.filled(tiles.length, number);
  return MeldInfo(MeldKind.group, number * tiles.length, values);
}

/// True when [tiles] (in order) could still grow into a valid run or group:
/// the same test as [analyzeMeld] without the 3-tile minimum. Used to decide
/// whether a dropped tile joins a neighbouring set or pushes it aside, and
/// which rack neighbours a long-press picks up.
bool isCompatible(List<int> tiles) {
  if (tiles.length <= 1) return true;
  return _runCompatible(tiles) || _groupCompatible(tiles);
}

bool _runCompatible(List<int> tiles) {
  if (tiles.length > 13) return false;
  TileColor? color;
  int? start;
  for (var i = 0; i < tiles.length; i++) {
    final t = tiles[i];
    if (isJoker(t)) continue;
    if (color != null && tileColor(t) != color) return false;
    color = tileColor(t);
    final s = tileNumber(t) - i;
    if (start != null && s != start) return false;
    start = s;
  }
  if (start == null) return true;
  return start >= 1 && start + tiles.length - 1 <= 13;
}

bool _groupCompatible(List<int> tiles) {
  if (tiles.length > 4) return false;
  int? number;
  final colors = <TileColor>{};
  for (final t in tiles) {
    if (isJoker(t)) continue;
    if (number != null && tileNumber(t) != number) return false;
    number = tileNumber(t);
    if (!colors.add(tileColor(t))) return false;
  }
  return true;
}
