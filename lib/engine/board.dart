import 'dart:math' as math;

import 'meld.dart';
import 'tiles.dart';

/// Tunable layout constants.
class LayoutTuning {
  /// Spaces per board row, gaps included.
  static const int rowWidth = 27;

  /// Rows a fresh board starts with.
  static const int startRows = 5;

  /// A set that must move stays in its row if it moves this far or less.
  static const int stayInRowMax = 3;
}

/// A run of adjacent tiles in one row: one set on the table.
class Block {
  final int row;
  final int start;
  final List<int> tiles;
  const Block(this.row, this.start, this.tiles);
  int get end => start + tiles.length; // exclusive
  int get length => tiles.length;
  Block at(int row, int start) => Block(row, start, tiles);
  @override
  String toString() => 'Block(r$row c$start ${tiles.length})';
}

/// The shared table: an invisible grid of rows, [LayoutTuning.rowWidth]
/// spaces wide. -1 marks an empty space. Tiles that touch belong to the same
/// set, so sets are always separated by at least one empty space.
class Board {
  final List<List<int>> rows;
  Board(this.rows);

  factory Board.empty([int rows = LayoutTuning.startRows]) =>
      Board([for (var i = 0; i < rows; i++) List<int>.filled(LayoutTuning.rowWidth, -1)]);

  static int get width => LayoutTuning.rowWidth;

  Board copy() => Board([for (final r in rows) List<int>.of(r)]);

  int get rowCount => rows.length;

  void addRow({int? at}) {
    final r = List<int>.filled(width, -1);
    if (at == null) {
      rows.add(r);
    } else {
      rows.insert(at, r);
    }
  }

  void ensureRows(int n) {
    while (rows.length < n) {
      addRow();
    }
  }

  bool isEmptyRow(int r) => rows[r].every((t) => t < 0);

  List<Block> blocksInRow(int r) {
    final out = <Block>[];
    final row = rows[r];
    var c = 0;
    while (c < width) {
      if (row[c] < 0) {
        c++;
        continue;
      }
      final s = c;
      final ts = <int>[];
      while (c < width && row[c] >= 0) {
        ts.add(row[c]);
        c++;
      }
      out.add(Block(r, s, ts));
    }
    return out;
  }

  List<Block> get blocks => [for (var r = 0; r < rows.length; r++) ...blocksInRow(r)];

  List<int> get allTiles => [for (final r in rows) ...r.where((t) => t >= 0)];

  ({int row, int col})? find(int tile) {
    for (var r = 0; r < rows.length; r++) {
      final c = rows[r].indexOf(tile);
      if (c >= 0) return (row: r, col: c);
    }
    return null;
  }

  Block? blockOf(int tile) {
    final p = find(tile);
    if (p == null) return null;
    return blocksInRow(p.row).firstWhere((b) => p.col >= b.start && p.col < b.end);
  }

  bool get isValid => blocks.every((b) => isValidMeld(b.tiles));

  List<Block> get invalidBlocks => blocks.where((b) => !isValidMeld(b.tiles)).toList();

  /// Takes [tiles] off the board. A group (same number, different colours) that loses tiles
  /// closes up, anchored at its left-most cell: taking the middle 7 of 7-7-7-7 leaves 7-7-7,
  /// not 7-7 _ 7. Runs are left as they are (a gap in a run is a split).
  void removeTiles(Iterable<int> tiles) {
    final s = tiles.toSet();
    final closing = [
      for (final blk in blocks)
        if (blk.tiles.any(s.contains) && !blk.tiles.every(s.contains) && isGroupLike(blk.tiles)) blk,
    ];
    for (final r in rows) {
      for (var c = 0; c < r.length; c++) {
        if (s.contains(r[c])) r[c] = -1;
      }
    }
    for (final g in closing) {
      final rest = g.tiles.where((t) => !s.contains(t)).toList();
      for (var c = g.start; c < g.end; c++) {
        rows[g.row][c] = -1;
      }
      for (var i = 0; i < rest.length; i++) {
        rows[g.row][g.start + i] = rest[i];
      }
    }
  }

  /// A group or partial group: at least two numbered tiles, all with the same number.
  static bool isGroupLike(List<int> tiles) {
    final real = tiles.where((t) => !isJoker(t)).toList();
    return real.length >= 2 && real.every((t) => tileNumber(t) == tileNumber(real.first));
  }

  void writeBlock(Block b) {
    ensureRows(b.row + 1);
    for (var i = 0; i < b.length; i++) {
      rows[b.row][b.start + i] = b.tiles[i];
    }
  }

  void clearBlock(Block b) {
    for (var i = 0; i < b.length; i++) {
      rows[b.row][b.start + i] = -1;
    }
  }

  /// True when [len] tiles fit at [start] in [row] with an empty space (or
  /// the edge) on both sides.
  bool fits(int row, int start, int len) {
    if (row < 0 || row >= rows.length) return false;
    if (start < 0 || start + len > width) return false;
    for (var c = math.max(0, start - 1); c < math.min(width, start + len + 1); c++) {
      if (rows[row][c] >= 0) return false;
    }
    return true;
  }

  /// Nearest start column in [row] where [len] tiles fit, or null.
  int? nearestFit(int row, int len, int prefer) {
    int? best;
    for (var s = 0; s + len <= width; s++) {
      if (fits(row, s, len) && (best == null || (s - prefer).abs() < (best - prefer).abs())) best = s;
    }
    return best;
  }

  /// Rows that hold at least one tile, top to bottom.
  List<int> get usedRows => [for (var r = 0; r < rows.length; r++) if (!isEmptyRow(r)) r];

  /// Drops trailing empty rows beyond the starting row count.
  void trim() {
    while (rows.length > LayoutTuning.startRows && isEmptyRow(rows.length - 1)) {
      rows.removeLast();
    }
  }

  List<List<int>> toJson() => [for (final r in rows) List<int>.of(r)];
  factory Board.fromJson(List<dynamic> j) =>
      Board([for (final r in j) [for (final t in (r as List)) t as int]]);

  /// The sets as tile lists, ignoring where they sit.
  List<List<int>> get sets => [for (final b in blocks) b.tiles];

  @override
  String toString() => rows
      .map((r) => r.map((t) => t < 0 ? '.' : '#').join())
      .join('\n');
}

/// Board layout operations. All return a new board; the input is untouched.
class Layout {
  /// Puts [tiles] (in order) at [row], [col], applying the table's layout
  /// rules:
  ///  * dropping onto a set inserts the tiles into it at that point;
  ///  * dropping right beside a set joins it when the result could still
  ///    become a valid set, otherwise that set is pushed 1 space aside;
  ///  * sets keep at least 1 empty space between them;
  ///  * an over-full row moves sets out (the smaller neighbour first);
  ///  * a set pushed more than 3 spaces prefers a free spot directly above
  ///    or below;
  ///  * a move is never refused: if no row has room, a row is added.
  static Board place(Board board, List<int> tiles, int row, int col, {bool merge = true}) {
    final b = board.copy();
    b.removeTiles(tiles);
    if (tiles.isEmpty) return b;
    row = math.max(0, row);
    b.ensureRows(row + 1);
    final w = Board.width;
    final len = tiles.length;
    col = col.clamp(0, w - len);

    final others = b.blocksInRow(row);
    Block anchor;
    final hit = merge ? _firstOrNull(others, (x) => col >= x.start && col < x.end) : null;
    if (hit != null) {
      final i = col - hit.start;
      anchor = Block(row, hit.start, [...hit.tiles.sublist(0, i), ...tiles, ...hit.tiles.sublist(i)]);
      others.remove(hit);
    } else {
      anchor = Block(row, col, tiles);
      if (merge) {
        final left = _firstOrNull(others, (x) => x.end == col);
        final right = _firstOrNull(others, (x) => x.start > col && x.start <= col + len);
        if (left != null && right != null && isCompatible([...left.tiles, ...tiles, ...right.tiles])) {
          anchor = Block(row, left.start, [...left.tiles, ...tiles, ...right.tiles]);
          others..remove(left)..remove(right);
        } else if (left != null && isCompatible([...left.tiles, ...tiles])) {
          anchor = Block(row, left.start, [...left.tiles, ...tiles]);
          others.remove(left);
        } else if (right != null && isCompatible([...tiles, ...right.tiles])) {
          anchor = Block(row, col, [...tiles, ...right.tiles]);
          others.remove(right);
        }
      }
    }
    _resolveRow(b, row, others, anchor);
    return b;
  }

  /// Inserts [tiles] into the set holding [setTile], before index [index]
  /// (0 = front, set length = end). The set grows from where it sits and
  /// slides left if it would pass the right edge.
  static Board insertInto(Board board, List<int> tiles, int setTile, int index) {
    final b = board.copy()..removeTiles(tiles);
    final blk = b.blockOf(setTile);
    if (blk == null) return b;
    index = index.clamp(0, blk.length);
    final combined = [...blk.tiles.sublist(0, index), ...tiles, ...blk.tiles.sublist(index)];
    final start = index == 0 ? blk.start - tiles.length : blk.start;
    b.clearBlock(blk);
    final others = b.blocksInRow(blk.row);
    final col = start.clamp(0, Board.width - combined.length);
    _resolveRow(b, blk.row, others, Block(blk.row, col, combined));
    return b;
  }

  /// Drag-and-drop onto a set: [tiles] dropped into the set holding [setTile] at [index].
  /// If the set would be valid with them there, they go there. If not, but the set is valid
  /// with them at one end, they go to that end instead (the end nearer [index] if both work):
  /// a 4 dropped into the middle of 5-6-7-8 makes 4-5-6-7-8, and 1-2-3-4 dropped onto
  /// 5-6-7-8 makes 1-2-3-4-5-6-7-8. With no valid placement they go where they were dropped.
  /// The set slides away from the board edge if it needs room ([insertInto]).
  static Board dropInto(Board board, List<int> tiles, int setTile, int index) {
    final b = board.copy()..removeTiles(tiles);
    final blk = b.blockOf(setTile);
    if (blk == null) return b;
    index = index.clamp(0, blk.length);
    final there = [...blk.tiles.sublist(0, index), ...tiles, ...blk.tiles.sublist(index)];
    if (!isValidMeld(there)) {
      final end = attachEnd(blk.tiles, tiles, index);
      if (end != null) return insertInto(b, tiles, setTile, end);
    }
    return insertInto(b, tiles, setTile, index);
  }

  /// End-of-turn tidying, run by the host after every played turn, so every device gets the
  /// same table. In order:
  ///  1. Row collapse, while more than 3 rows hold tiles: a set alone in its row moves into an
  ///     adjacent row that has tiles, at the same columns or 1 column left or right, if it fits
  ///     with a space on both sides.
  ///  2. Gap collapse, while the rows from the first to the last used one span more than 3 and
  ///     one between them is empty: the outer rows on the side nearer that empty row move one
  ///     row inward (rows 1, 3, 4 used: row 1 moves down to row 2).
  ///  3. Compacting: in every row the sets move toward the middle, in the same left-to-right
  ///     order, with exactly 1 empty space between them.
  ///  4. Empty rows above the top set are removed (the view zooms in); the board keeps
  ///     [LayoutTuning.startRows] rows.
  static Board tidy(Board board) {
    final b = board.copy();
    if (b.usedRows.isEmpty) return b;
    _collapseLoneSets(b);
    _collapseGaps(b);
    for (var r = 0; r < b.rowCount; r++) {
      _centreRow(b, r);
    }
    while (b.rowCount > 1 && b.isEmptyRow(0)) {
      b.rows.removeAt(0);
    }
    b.ensureRows(LayoutTuning.startRows);
    b.trim();
    return b;
  }

  static void _collapseLoneSets(Board b) {
    var moved = true;
    while (moved && b.usedRows.length > 3) {
      moved = false;
      search:
      for (final shift in const [0, -1, 1]) {
        for (final r in b.usedRows) {
          final row = b.blocksInRow(r);
          if (row.length != 1) continue;
          final blk = row.single;
          for (final adj in [r - 1, r + 1]) {
            if (adj < 0 || adj >= b.rowCount || b.isEmptyRow(adj)) continue;
            b.clearBlock(blk);
            if (b.fits(adj, blk.start + shift, blk.length)) {
              b.writeBlock(blk.at(adj, blk.start + shift));
              moved = true;
              break search;
            }
            b.writeBlock(blk);
          }
        }
      }
    }
  }

  static void _collapseGaps(Board b) {
    while (true) {
      final used = b.usedRows;
      if (used.isEmpty) return;
      final first = used.first, last = used.last;
      if (last - first + 1 <= 3) return;
      int? gap;
      for (var r = first + 1; r < last; r++) {
        if (!b.isEmptyRow(r)) continue;
        if (gap == null || math.min(r - first, last - r) < math.min(gap - first, last - gap)) gap = r;
      }
      if (gap == null) return;
      if (gap - first <= last - gap) {
        // Rows above the gap move down one.
        for (var r = gap; r > first; r--) {
          b.rows[r] = b.rows[r - 1];
        }
        b.rows[first] = List<int>.filled(Board.width, -1);
      } else {
        for (var r = gap; r < last; r++) {
          b.rows[r] = b.rows[r + 1];
        }
        b.rows[last] = List<int>.filled(Board.width, -1);
      }
    }
  }

  static void _centreRow(Board b, int r) {
    final blocks = b.blocksInRow(r);
    if (blocks.isEmpty) return;
    final span = blocks.fold<int>(0, (s, x) => s + x.length) + blocks.length - 1;
    var c = math.max(0, (Board.width - span) ~/ 2);
    for (var i = 0; i < Board.width; i++) {
      b.rows[r][i] = -1;
    }
    for (final blk in blocks) {
      b.writeBlock(blk.at(r, c));
      c += blk.length + 1;
    }
  }

  /// Splits the set just before [tile]; the right part moves 1 space away.
  static Board split(Board board, int tile) {
    final blk = board.blockOf(tile);
    if (blk == null) return board.copy();
    final i = blk.tiles.indexOf(tile);
    if (i <= 0) return board.copy();
    final right = blk.tiles.sublist(i);
    return place(board, right, blk.row, blk.start + i + 1, merge: false);
  }

  /// Moves a whole set (as given) so its first tile lands at [row], [col].
  static Board moveSet(Board board, List<int> tiles, int row, int col) =>
      place(board, tiles, row, col);

  /// Tap-to-attach: the end of [set] that [sel] joins (0 = before the first tile,
  /// set.length = after the last), or null if neither end gives a valid set. When both work,
  /// the end nearer the tapped tile ([tapIndex]) wins. With [allowPartial], a set of 1-2 tiles
  /// may grow into a still-incomplete but compatible set.
  static int? attachEnd(List<int> set, List<int> sel, int tapIndex, {bool allowPartial = false}) {
    bool ok(List<int> c) => isValidMeld(c) || (allowPartial && set.length < 3 && isCompatible(c));
    final atEnd = ok([...set, ...sel]);
    final atStart = ok([...sel, ...set]);
    if (atEnd && atStart) return tapIndex < set.length / 2 ? 0 : set.length;
    if (atEnd) return set.length;
    if (atStart) return 0;
    return null;
  }

  /// The joker swap shortcut: [tile] (from the rack, or from elsewhere on the board) is played
  /// onto the set holding [joker], taking the joker's place if it's a compatible replacement:
  ///  * a run: the tile takes the joker's position and the joker moves to an end (the high end
  ///    if both work); if neither end works (the run would span past 1-13), the joker is
  ///    detached to the nearest empty space;
  ///  * a group of fewer than 4: the tile is added and the joker sits at the group's edge;
  ///  * a group of 4: the tile takes the joker's spot and the joker is detached to the nearest
  ///    empty space.
  /// Returns null when the tile can't replace the joker. `detached` is true when the joker was
  /// set down alone (the player then places it).
  static ({Board board, bool detached})? jokerShortcut(Board board, int tile, int joker) {
    if (!isJoker(joker) || isJoker(tile) || tile == joker) return null;
    final before = board.blockOf(joker);
    if (before == null || before.tiles.contains(tile)) return null;
    final info = analyzeMeld(before.tiles);
    if (info == null) return null;
    final b = board.copy()..removeTiles([tile]);
    final blk = b.blockOf(joker)!;
    final swapped = [for (final t in blk.tiles) t == joker ? tile : t];
    if (!isValidMeld(swapped)) return null;
    final p = b.find(joker)!;
    b.rows[p.row][p.col] = tile; // the tile takes the joker's cell; the joker is in hand for a moment
    final isRun = info.kind == MeldKind.run;
    if (isRun || blk.length < 4) {
      // Runs: the high end first. Groups of fewer than 4: the joker goes to the edge.
      if (isValidMeld([...swapped, joker])) return (board: insertInto(b, [joker], tile, swapped.length), detached: false);
      if (isRun && isValidMeld([joker, ...swapped])) return (board: insertInto(b, [joker], tile, 0), detached: false);
    }
    return (board: placeNear(b, joker, p.row, p.col), detached: true);
  }

  /// Sets [tile] down alone in the empty cell nearest ([row], [col]) that doesn't touch another
  /// set (so it stays a separate set).
  static Board placeNear(Board board, int tile, int row, int col) {
    final b = board.copy()..removeTiles([tile]);
    ({int r, int c})? best;
    var bestScore = double.infinity;
    for (var r = 0; r < b.rowCount; r++) {
      for (var c = 0; c < Board.width; c++) {
        if (b.rows[r][c] >= 0) continue;
        if (c > 0 && b.rows[r][c - 1] >= 0) continue;
        if (c < Board.width - 1 && b.rows[r][c + 1] >= 0) continue;
        final dr = (r - row) * 1.4, dc = (c - col).toDouble();
        final score = dr * dr + dc * dc;
        if (score < bestScore) {
          bestScore = score;
          best = (r: r, c: c);
        }
      }
    }
    if (best == null) {
      final spot = findSpotForNewSet(b, 1);
      return place(spot.board, [tile], spot.row, spot.col, merge: false);
    }
    b.rows[best.r][best.c] = tile;
    return b;
  }

  /// Joker reclaim: puts [tile] exactly where [joker] sits (same set, same cell) and takes
  /// the joker off the board. Returns null when the joker isn't on the board or the set
  /// would not be valid with [tile] in its place.
  static Board? swapJoker(Board board, int tile, int joker) {
    if (!isJoker(joker) || isJoker(tile)) return null;
    final b = board.copy()..removeTiles([tile]);
    final p = b.find(joker);
    if (p == null) return null;
    final blk = b.blockOf(joker)!;
    final swapped = [for (final t in blk.tiles) t == joker ? tile : t];
    if (!isValidMeld(swapped)) return null;
    b.rows[p.row][p.col] = tile;
    return b;
  }

  /// The Make space button. Shifts the top half of the tile rows (rounded up)
  /// one row up, opening an empty row. Returns null (does nothing) when an
  /// empty row already exists between tile rows. If the top tile row is
  /// already at the top edge, a row is added (the table zooms out).
  static Board? makeSpace(Board board) {
    final used = board.usedRows;
    if (used.isEmpty) return null;
    for (var r = used.first; r <= used.last; r++) {
      if (board.isEmptyRow(r)) return null;
    }
    final b = board.copy();
    final half = (used.length + 1) ~/ 2;
    final lastMoved = used[half - 1];
    if (used.first == 0) {
      // Insert a blank row below the moved half: same as shifting it up
      // with the board growing by one row at the top.
      b.addRow(at: lastMoved + 1);
    } else {
      // Remove one empty row above the tiles and insert it below the half.
      b.rows.removeAt(used.first - 1);
      b.addRow(at: lastMoved);
    }
    return b;
  }

  /// Where a new set of [len] tiles would go: the first row (top down) with
  /// room, preferring a spot after the existing sets. Adds a row if needed.
  static ({Board board, int row, int col}) findSpotForNewSet(Board board, int len) {
    final b = board.copy();
    for (var r = 0; r < b.rowCount; r++) {
      final blocks = b.blocksInRow(r);
      final after = blocks.isEmpty ? 0 : blocks.last.end + 1;
      if (b.fits(r, after, len)) return (board: b, row: r, col: after);
      final s = b.nearestFit(r, len, 0);
      if (s != null) return (board: b, row: r, col: s);
    }
    b.addRow();
    return (board: b, row: b.rowCount - 1, col: 0);
  }

  // ---------------------------------------------------------------------

  static void _resolveRow(Board b, int row, List<Block> others, Block anchor) {
    final w = Board.width;
    final evicted = <Block>[];
    var placedAnchor = anchor;
    while (true) {
      final left = others.where((x) => x.start < anchor.start).toList()..sort((a, c) => a.start - c.start);
      final right = others.where((x) => x.start >= anchor.start).toList()..sort((a, c) => a.start - c.start);
      final order = [...left, anchor, ...right];
      final total = order.fold<int>(0, (s, x) => s + x.length) + order.length - 1;
      if (total > w) {
        // Evict the smaller immediate neighbour of the anchor (the right
        // one on a tie); keep going until the row fits.
        final ln = left.isEmpty ? null : left.last;
        final rn = right.isEmpty ? null : right.first;
        Block victim;
        if (ln == null) {
          victim = rn!;
        } else if (rn == null) {
          victim = ln;
        } else {
          victim = ln.length < rn.length ? ln : rn;
        }
        others.remove(victim);
        evicted.add(victim);
        continue;
      }
      final pos = _pack(order, left.length);
      // A set pushed more than 3 spaces prefers a free spot directly above
      // or below (checked against the board as it is now).
      Block? far;
      var farDist = LayoutTuning.stayInRowMax;
      for (var i = 0; i < order.length; i++) {
        if (identical(order[i], anchor)) continue;
        final d = (pos[i] - order[i].start).abs();
        if (d > farDist) {
          far = order[i];
          farDist = d;
        }
      }
      if (far != null) {
        final dest = _aboveOrBelow(b, row, far);
        if (dest != null) {
          b.clearBlock(far);
          b.writeBlock(far.at(dest, far.start));
          others.remove(far);
          continue;
        }
      }
      // Write the row.
      for (var c = 0; c < w; c++) {
        b.rows[row][c] = -1;
      }
      for (var i = 0; i < order.length; i++) {
        final blk = order[i].at(row, pos[i]);
        b.writeBlock(blk);
        if (identical(order[i], anchor)) placedAnchor = blk;
      }
      break;
    }
    for (final e in evicted) {
      _relocate(b, e, row);
    }
    assert(placedAnchor.row == row);
  }

  /// Places blocks in order with gaps of at least 1, keeping the anchor where
  /// it was dropped when possible and moving others as little as possible.
  static List<int> _pack(List<Block> order, int a) {
    final w = Board.width;
    final n = order.length;
    final pos = [for (final x in order) x.start];
    for (var i = a + 1; i < n; i++) {
      pos[i] = math.max(pos[i], pos[i - 1] + order[i - 1].length + 1);
    }
    for (var i = a - 1; i >= 0; i--) {
      pos[i] = math.min(pos[i], pos[i + 1] - order[i].length - 1);
    }
    final over = pos[n - 1] + order[n - 1].length - w;
    if (over > 0) {
      pos[n - 1] -= over;
      for (var i = n - 2; i >= 0; i--) {
        pos[i] = math.min(pos[i], pos[i + 1] - order[i].length - 1);
      }
    }
    if (pos[0] < 0) {
      pos[0] = 0;
      for (var i = 1; i < n; i++) {
        pos[i] = math.max(pos[i], pos[i - 1] + order[i - 1].length + 1);
      }
    }
    return pos;
  }

  static int? _aboveOrBelow(Board b, int row, Block blk) {
    for (final r in [row - 1, row + 1]) {
      if (r >= 0 && r < b.rowCount && b.fits(r, blk.start, blk.length)) return r;
    }
    return null;
  }

  /// Finds a new home for a set pushed out of [fromRow]: directly above or
  /// below first, then the nearest spot in the nearest row with room, else
  /// a new row at the bottom.
  static void _relocate(Board b, Block blk, int fromRow) {
    final direct = _aboveOrBelow(b, fromRow, blk);
    if (direct != null) {
      b.writeBlock(blk.at(direct, blk.start));
      return;
    }
    for (var d = 1; d < b.rowCount + 1; d++) {
      for (final r in [fromRow - d, fromRow + d]) {
        if (r < 0 || r >= b.rowCount) continue;
        final s = b.nearestFit(r, blk.length, blk.start);
        if (s != null) {
          b.writeBlock(blk.at(r, s));
          return;
        }
      }
    }
    b.addRow();
    b.writeBlock(blk.at(b.rowCount - 1, blk.start.clamp(0, Board.width - blk.length)));
  }

  static T? _firstOrNull<T>(Iterable<T> xs, bool Function(T) f) {
    for (final x in xs) {
      if (f(x)) return x;
    }
    return null;
  }
}
