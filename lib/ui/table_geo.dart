import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/rack_sort.dart';

enum SeatPos { left, top, right }

/// All positions on the game table, computed from the screen size. Every
/// tile is placed with plain maths so dragging and dropping can hit-test
/// without widget lookups.
class TableGeo {
  final Size size;
  final int boardRows;

  /// Rack entries in order: tile ids, and gap markers (< 0) between sorted sets.
  final List<int> rackEntries;
  final int seatCount;

  /// How much of the board to fit on screen: rows and columns (fractional while zooming).
  /// The board starts zoomed in (3 rows, [minViewCols] columns) and zooms out as sets
  /// spread down or across, up to every row and the full 27 columns.
  final double viewRows, viewCols;
  static const minViewRows = 3.0;
  static const minViewCols = 16.0;

  /// Width of a gap between sorted sets in the rack, as a share of a rack tile.
  static const rackGapFrac = 0.4;

  late final double topH, sideW, ctrlW, ctrlH;
  late final double avatar;
  late final double backW, backH;
  late final int rackPerRow, rackRows;
  late final double rackTileW, rackTileH, rackRowH, rackPadX, rackPadTop;
  late final Rect rackRect;
  late final Rect boardRect;
  late final double cellW, tileH, rowPitch;
  late final Offset boardOrigin;
  late final Rect pileRect;
  late final Rect makeSpaceRect;
  late final double shownCols;
  late final int shownRows;
  late final List<Rect?> _rackRects;

  static const tileAspect = 1.38;
  static const rowWidth = 27;

  TableGeo(this.size,
      {required this.boardRows, required this.rackEntries, required this.seatCount, double? viewRows, double? viewCols})
      : viewRows = (viewRows ?? minViewRows).clamp(minViewRows, math.max(minViewRows, boardRows.toDouble())),
        viewCols = (viewCols ?? minViewCols).clamp(minViewCols, rowWidth.toDouble()) {
    final rackCount = math.max(1, rackEntries.length);
    final w = size.width, h = size.height;
    topH = (h * .12).clamp(42.0, 66.0);
    sideW = (w * .085).clamp(56.0, 92.0);
    ctrlW = (w * .21).clamp(150.0, 250.0);
    avatar = (h * .1).clamp(30.0, 48.0);
    backW = (h * .024).clamp(7.0, 12.0);
    backH = backW * 1.33;

    // Rack: 10 tiles per row, 2 rows past 10. Past 20, the two rows share
    // the tiles and the tiles narrow.
    // Gaps count as a full slot here, so there is always room for them.
    var perRow = rackCount <= 20 ? 10 : (rackCount + 1) ~/ 2;
    rackRows = rackCount <= 10 ? 1 : 2;
    final rackAvail = w - 2 * ctrlW - 16;
    final baseTileW = math.min(h * .115, rackAvail / 10.8);
    var rects = _layoutRack(perRow, baseTileW * 10 / perRow);
    while (rects == null) {
      perRow++;
      rects = _layoutRack(perRow, baseTileW * 10 / perRow);
    }
    rackPerRow = perRow;
    rackTileW = baseTileW * 10 / rackPerRow;
    rackTileH = baseTileW * tileAspect;
    rackRowH = rackTileH + baseTileW * .34;
    rackPadX = baseTileW * .3;
    rackPadTop = baseTileW * .18;
    final rackW = rackPerRow * rackTileW + 2 * rackPadX;
    final rackH = rackRows * rackRowH + rackPadTop + 2;
    rackRect = Rect.fromLTWH((w - rackW) / 2, h - rackH, rackW, rackH);
    _rackRects = [
      for (final r in rects)
        r == null
            ? null
            : Rect.fromLTWH(rackRect.left + rackPadX + r.left + rackTileW * .03, rackRect.top + rackPadTop + r.top * rackRowH,
                rackTileW * .94, rackTileH),
    ];
    makeSpaceRect = Rect.fromLTWH(rackRect.left - 52, h - 50, 44, 44);

    ctrlH = math.min(118, h * .3);
    final boardBottom = math.min(rackRect.top, h - ctrlH) - 4;
    boardRect = Rect.fromLTRB(sideW, topH, w - sideW, boardBottom);
    // Zoom: fit [viewRows] x [viewCols] cells. Whichever way has room to spare shows extra
    // columns (up to 27) or rows (up to the board's rows) rather than leaving it empty.
    final gapF = (0.42 - 0.04 * this.viewRows).clamp(0.08, 0.35);
    cellW = math.min(boardRect.width / this.viewCols, boardRect.height / (this.viewRows * tileAspect * (1 + gapF)));
    tileH = cellW * tileAspect;
    rowPitch = tileH * (1 + gapF);
    shownCols = math.min(rowWidth.toDouble(), boardRect.width / cellW);
    shownRows = math.max(1, math.min(boardRows, ((boardRect.height + tileH * gapF) / rowPitch + 0.01).floor()));
    final usedH = math.max(this.viewRows, shownRows.toDouble()) * rowPitch - tileH * gapF;
    boardOrigin = Offset(
      boardRect.left + (boardRect.width - shownCols * cellW) / 2,
      boardRect.top + math.max(0, (boardRect.height - usedH) / 2),
    );
    final pw = (h * .06).clamp(22.0, 34.0);
    // The pile sits in the top-right corner, clear of the side seats.
    pileRect = Rect.fromLTWH(w - pw - 62, 6, pw, pw * 1.38);
  }

  Rect cellRect(int row, int col) => Rect.fromLTWH(
      boardOrigin.dx + col * cellW + cellW * .04, boardOrigin.dy + row * rowPitch, cellW * .92, tileH);

  /// Board cell under a point (the centre of a dragged tile).
  ({int row, int col, double frac})? cellAt(Offset p, {bool loose = false}) {
    final pad = loose ? cellW : 0;
    if (p.dx < boardRect.left - pad || p.dx > boardRect.right + pad) return null;
    if (p.dy < boardRect.top - pad || p.dy > boardRect.bottom + pad) return null;
    final fx = (p.dx - boardOrigin.dx) / cellW;
    final col = fx.floor().clamp(0, math.max(0, shownCols.floor() - 1)).toInt();
    final row = ((p.dy - boardOrigin.dy + rowPitch * .1) / rowPitch).floor().clamp(0, math.max(0, shownRows - 1)).toInt();
    return (row: row, col: col, frac: fx - fx.floor());
  }

  /// Lays out the rack entries in rows of [perRow] tile widths: x offsets in pixels, rows as `top`.
  /// A sorted set that would straddle the row break starts on the next row instead.
  /// Returns null when the entries don't fit in [rackRows] rows.
  List<Rect?>? _layoutRack(int perRow, double tileW) {
    final cap = perRow * tileW + 0.5;
    List<Rect?>? attempt(bool keepSetsTogether) {
      final out = <Rect?>[];
      var x = 0.0;
      var row = 0;
      for (var i = 0; i < rackEntries.length; i++) {
        final e = rackEntries[i];
        if (isRackGap(e)) {
          if (x > 0) x += tileW * rackGapFrac;
          out.add(null);
          continue;
        }
        if (keepSetsTogether && x > 0 && (i == 0 || isRackGap(rackEntries[i - 1]))) {
          var j = i;
          while (j < rackEntries.length && !isRackGap(rackEntries[j])) {
            j++;
          }
          final isSet = j < rackEntries.length;
          if (isSet && x + (j - i) * tileW > cap && (j - i) <= perRow) {
            row++;
            x = 0;
          }
        }
        if (x + tileW > cap) {
          row++;
          x = 0;
        }
        if (row >= rackRows) return null;
        out.add(Rect.fromLTWH(x, row.toDouble(), tileW, 1));
        x += tileW;
      }
      return out;
    }

    return attempt(true) ?? attempt(false);
  }

  /// Where rack entry [i] sits (null for a gap).
  Rect rackSlot(int i) =>
      (i >= 0 && i < _rackRects.length ? _rackRects[i] : null) ??
      Rect.fromLTWH(rackRect.left + rackPadX, rackRect.top + rackPadTop, rackTileW * .94, rackTileH);

  bool inRack(Offset p) => rackRect.inflate(8).contains(p);

  /// Index in [rackEntries] where tiles dropped at [p] would be inserted.
  int rackIndexAt(Offset p) {
    final row = ((p.dy - rackRect.top - rackPadTop) / rackRowH).floor().clamp(0, rackRows - 1);
    int? lastInRow;
    for (var i = 0; i < _rackRects.length; i++) {
      final r = _rackRects[i];
      if (r == null) continue;
      final rr = ((r.top - rackRect.top - rackPadTop) / rackRowH).round();
      if (rr < row) continue;
      if (rr > row) return lastInRow == null ? i : lastInRow + 1;
      if (p.dx < r.center.dx) return i;
      lastInRow = i;
    }
    return lastInRow == null ? rackEntries.length : lastInRow + 1;
  }

  // --- opponent seats --------------------------------------------------

  Offset seatCenter(SeatPos s) {
    final w = size.width;
    switch (s) {
      case SeatPos.left:
        return Offset(sideW / 2, topH + avatar / 2 - 4);
      case SeatPos.right:
        return Offset(w - sideW / 2, topH + avatar / 2 - 4);
      case SeatPos.top:
        return Offset(w / 2 - backLineLen / 2 - avatar * .7, avatar / 2 + 6);
    }
  }

  double get backLineLen => 10 * (backW + 2) + 4;

  /// Face-down indicator tile [i] of [n] for a seat: lines of 10 with a gap
  /// after 5; across for the top seat, downward for side seats; lines
  /// squeeze together past 20.
  Rect backRect(SeatPos s, int i, int n) {
    final vert = s != SeatPos.top;
    final a = vert ? backH : backW, c = vert ? backW : backH;
    final k = i % 10;
    final along = k * (a + 2) + (k >= 5 ? 4 : 0);
    final step = n > 20 ? c * .62 : c + 3;
    final cross = (i ~/ 10) * step;
    final center = seatCenter(s);
    switch (s) {
      case SeatPos.left:
        final x0 = center.dx - (n > 10 ? (n > 20 ? c * 1.1 : c + 1.5) : c / 2);
        return Rect.fromLTWH(x0 + cross, center.dy + avatar / 2 + 22 + along, c, a);
      case SeatPos.right:
        final x0 = center.dx + (n > 10 ? (n > 20 ? c * 1.1 : c + 1.5) : c / 2) - c;
        return Rect.fromLTWH(x0 - cross, center.dy + avatar / 2 + 22 + along, c, a);
      case SeatPos.top:
        return Rect.fromLTWH(center.dx + avatar * .7 + 10 + along, 6 + cross, a, c);
    }
  }
}
