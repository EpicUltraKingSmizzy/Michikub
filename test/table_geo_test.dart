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

  test('the rack is a grid of slots: blanks are a tile wide, drops find the slot under them', () {
    final entries = [1, 2, -1, 3, ...[for (var i = 10; i < 18; i++) i]];
    final g = TableGeo(phone, boardRows: 5, rackEntries: entries, seatCount: 2);
    expect(g.rackRows, 2);
    expect(g.rackPerRow, 10);
    final s0 = g.rackSlot(0), s3 = g.rackSlot(3), s10 = g.rackSlot(10);
    expect(s3.left - s0.left, closeTo(3 * g.rackTileW, .01), reason: 'the blank takes a full slot');
    expect(s10.left, closeTo(s0.left, .01));
    expect(s10.top, greaterThan(s0.top));
    expect(g.rackSlotAt(g.slotRect(2).center), 2, reason: 'a blank slot can be hit');
    expect(g.rackSlotAt(g.slotRect(19).center), 19, reason: 'past the last entry');
  });

  test('the columns in view are centred on the board (where tidying gathers sets)', () {
    final g = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16);
    expect(g.firstCol + g.lastCol, closeTo(26, 1), reason: 'centred on column 13');
    // The middle column sits in the middle of the board area.
    expect(g.cellRect(0, 13).center.dx, closeTo(g.boardRect.center.dx, g.cellW));
    expect(g.cellAt(Offset(g.boardRect.left + 1, g.cellRect(0, 0).center.dy))!.col, g.firstCol);
    expect(TableGeo.colsToShow(10, 16), 16);
    expect(TableGeo.colsToShow(0, 26), 27);
  });

  test('v0.1.7: no spare columns, and off-centre sets shift the window instead of zooming out', () {
    // Only the sets' own span counts.
    expect(TableGeo.colsToShow(2, 14), 16);
    expect(TableGeo.colsToShow(3, 22), 20);
    final centred = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16);
    final left = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16, contentFrom: 0, contentTo: 12);
    expect(left.cellW, centred.cellW, reason: 'same zoom');
    expect(left.firstCol, 0, reason: 'the window shifted left to show column 0');
    final right = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16, contentFrom: 14, contentTo: 26);
    expect(right.lastCol, 26);
    expect(right.cellW, centred.cellW);
    // Sets near the middle keep the centred window.
    final mid = TableGeo(phone, boardRows: 5, rackEntries: tiles(14), seatCount: 4, viewRows: 3, viewCols: 16, contentFrom: 10, contentTo: 16);
    expect(mid.firstCol, centred.firstCol);
  });

  test('v0.1.7: the board reaches closer to the side seats', () {
    final g = TableGeo(const Size(873, 393), boardRows: 5, rackEntries: tiles(14), seatCount: 4);
    expect(g.sideW, lessThanOrEqualTo(62));
    expect(g.boardRect.left, g.sideW);
  });
}
