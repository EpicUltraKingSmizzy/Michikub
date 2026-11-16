import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/ui/table_geo.dart';

const phone = Size(844, 390);
List<int> tiles(int n) => [for (var i = 0; i < n; i++) i];

void main() {
  test('the board starts zoomed in: 3 rows and narrower than 27 columns, so tiles are bigger', () {
    final start = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16);
    final full = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 5, viewCols: 27);
    expect(start.cellW, greaterThan(full.cellW * 1.3));
    expect(start.shownCols, lessThan(27));
    expect(start.shownRows, 3);
    expect(full.shownCols, 27);
  });

  test('height and width zoom out independently', () {
    final base = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16);
    final taller = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 4, viewCols: 16);
    final wider = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 27);
    expect(taller.cellW, lessThan(base.cellW));
    expect(taller.shownRows, 4);
    expect(wider.cellW, lessThanOrEqualTo(base.cellW));
    expect(wider.shownCols, 27);
    expect(wider.shownRows, greaterThanOrEqualTo(3));
  });

  test('rack gaps add a small space and a sorted set is not split across rows', () {
    // 8 tiles, gap, 3-tile set, gap, 6 tiles: the set would straddle the row break.
    final entries = [...tiles(8), -1, 100, 101, 102, -2, ...[200, 201, 202, 203, 204, 205]];
    final g = TableGeo(phone, boardRows: 5, rackEntries: entries, seatCount: 2);
    final a = g.rackSlot(7), set0 = g.rackSlot(9), set2 = g.rackSlot(11);
    expect(set0.top, set2.top, reason: 'the whole set is on one row');
    expect(set0.top, greaterThan(a.top), reason: 'it moved down to the second row');
    // Gap between sets is smaller than a tile.
    final afterGap = g.rackSlot(13);
    final gap = afterGap.left - set2.right;
    expect(gap, greaterThan(g.rackTileW * .2));
    expect(gap, lessThan(g.rackTileW * .8));
    // Dropping just left of the first tile after the gap inserts before it.
    expect(g.rackIndexAt(Offset(afterGap.left + 2, afterGap.center.dy)), 13);
  });
}
