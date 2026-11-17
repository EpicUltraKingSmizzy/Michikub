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

  /// The whole columns in view: [firstCol]..[lastCol], centred on the board's middle (where
  /// end-of-turn tidying gathers the sets).
  late final int firstCol, lastCol;
  late final int shownRows;
  late final List<Rect?> _rackRects;

  static const tileAspect = 1.38;
  static const rowWidth = 27;

  /// The columns holding sets ([contentFrom]..[contentTo]); the window of columns in view
  /// stays centred on the board when it can, and shifts just enough to show them all.
  final int? contentFrom, contentTo;

  TableGeo(this.size,
      {required this.boardRows,
      required this.rackEntries,
      required this.seatCount,
      double? viewRows,
      double? viewCols,
      this.contentFrom,
      this.contentTo})
      : viewRows = (viewRows ?? minViewRows).clamp(minViewRows, math.max(minViewRows, boardRows.toDouble())),
        viewCols = (viewCols ?? minViewCols).clamp(minViewCols, rowWidth.toDouble()) {
    final rackCount = math.max(1, rackEntries.length);
    final w = size.width, h = size.height;
    topH = (h * .12).clamp(42.0, 66.0);
    // Side seat columns: just wide enough for an avatar, its count badge and two columns of backs.
    sideW = (w * .07).clamp(56.0, 80.0);
    ctrlW = (w * .21).clamp(150.0, 250.0);
    avatar = (h * .1).clamp(30.0, 48.0);
    backW = (h * .024).clamp(7.0, 12.0);
    backH = backW * 1.33;

    // Rack: a grid of slots, 10 per row, 2 rows past 10 entries. Past 20, the two rows share
    // the entries and the tiles narrow. Blank slots (entries < 0) are a full tile wide.
    rackPerRow = rackSlotsPerRow(rackCount);
    rackRows = rackRowsFor(rackCount);
    final rackAvail = w - 2 * ctrlW - 16;
    final baseTileW = math.min(h * .115, rackAvail / 10.8);
    rackTileW = baseTileW * 10 / rackPerRow;
    rackTileH = baseTileW * tileAspect;
    rackRowH = rackTileH + baseTileW * .34;
    rackPadX = baseTileW * .3;
    rackPadTop = baseTileW * .18;
    final rackW = rackPerRow * rackTileW + 2 * rackPadX;
    final rackH = rackRows * rackRowH + rackPadTop + 2;
    rackRect = Rect.fromLTWH((w - rackW) / 2, h - rackH, rackW, rackH);
    _rackRects = [
      for (var i = 0; i < rackEntries.length; i++)
        isRackGap(rackEntries[i]) ? null : slotRect(i),
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
    final whole = math.min(rowWidth, (shownCols + 1e-6).floor());
    var first = firstColFor(whole);
    if (contentFrom != null && contentTo != null) {
      // Shift (don't zoom) so off-centre sets stay in view: right edge first, then left.
      first = math.max(first, contentTo! - whole + 1);
      first = math.min(first, contentFrom!);
      first = first.clamp(0, rowWidth - whole);
    }
    firstCol = first;
    lastCol = firstCol + whole - 1;
    boardOrigin = Offset(
      boardRect.left + (boardRect.width - whole * cellW) / 2 - firstCol * cellW,
      boardRect.top + math.max(0, (boardRect.height - usedH) / 2),
    );
    final pw = (h * .06).clamp(22.0, 34.0);
    // The pile sits in the top-right corner, clear of the side seats.
    pileRect = Rect.fromLTWH(w - pw - 62, 6, pw, pw * 1.38);
  }

  /// First column in view when [n] whole columns are shown, centred on the board.
  static int firstColFor(int n) => (rowWidth - n.clamp(1, rowWidth)) ~/ 2;

  /// Columns to show (at least [minViewCols]) so that columns [from]..[to] fit. The window
  /// can shift ([contentFrom]), so only their span counts, not their distance from the middle.
  static int colsToShow(int from, int to) => math.max(minViewCols.toInt(), math.min(rowWidth, to - from + 1));

  Rect cellRect(int row, int col) => Rect.fromLTWH(
      boardOrigin.dx + col * cellW + cellW * .04, boardOrigin.dy + row * rowPitch, cellW * .92, tileH);

  /// Board cell under a point (the centre of a dragged tile).
  ({int row, int col, double frac})? cellAt(Offset p, {bool loose = false}) {
    final pad = loose ? cellW : 0;
    if (p.dx < boardRect.left - pad || p.dx > boardRect.right + pad) return null;
    if (p.dy < boardRect.top - pad || p.dy > boardRect.bottom + pad) return null;
    final fx = (p.dx - boardOrigin.dx) / cellW;
    final col = fx.floor().clamp(firstCol, lastCol).toInt();
    final row = ((p.dy - boardOrigin.dy + rowPitch * .1) / rowPitch).floor().clamp(0, math.max(0, shownRows - 1)).toInt();
    return (row: row, col: col, frac: fx - fx.floor());
  }

  /// Where rack entry [i] sits (null for a gap).
  Rect rackSlot(int i) =>
      (i >= 0 && i < _rackRects.length ? _rackRects[i] : null) ??
      Rect.fromLTWH(rackRect.left + rackPadX, rackRect.top + rackPadTop, rackTileW * .94, rackTileH);

  bool inRack(Offset p) => rackRect.inflate(8).contains(p);

  /// Where rack slot [i] is (filled or blank).
  Rect slotRect(int i) => Rect.fromLTWH(rackRect.left + rackPadX + (i % rackPerRow) * rackTileW + rackTileW * .03,
      rackRect.top + rackPadTop + (i ~/ rackPerRow) * rackRowH, rackTileW * .94, rackTileH);

  /// The rack slot under [p] (it may be past the last entry: a drop there leaves blanks).
  int rackSlotAt(Offset p) {
    final row = ((p.dy - rackRect.top - rackPadTop) / rackRowH).floor().clamp(0, rackRows - 1);
    final col = ((p.dx - rackRect.left - rackPadX) / rackTileW).floor().clamp(0, rackPerRow - 1);
    return row * rackPerRow + col;
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
