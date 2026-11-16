import 'dart:math' as math;

import 'package:flutter/material.dart';

enum SeatPos { left, top, right }

/// All positions on the game table, computed from the screen size. Every
/// tile is placed with plain maths so dragging and dropping can hit-test
/// without widget lookups.
class TableGeo {
  final Size size;
  final int boardRows;
  final int rackCount;
  final int seatCount;

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

  static const tileAspect = 1.38;
  static const rowWidth = 27;

  TableGeo(this.size, {required this.boardRows, required this.rackCount, required this.seatCount}) {
    final w = size.width, h = size.height;
    topH = (h * .12).clamp(42.0, 66.0);
    sideW = (w * .085).clamp(56.0, 92.0);
    ctrlW = (w * .21).clamp(150.0, 250.0);
    avatar = (h * .1).clamp(30.0, 48.0);
    backW = (h * .024).clamp(7.0, 12.0);
    backH = backW * 1.33;

    // Rack: 10 tiles per row, 2 rows past 10. Past 20, the two rows share
    // the tiles and the tiles narrow.
    rackPerRow = rackCount <= 20 ? 10 : (rackCount + 1) ~/ 2;
    rackRows = rackCount <= 10 ? 1 : 2;
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
    makeSpaceRect = Rect.fromLTWH(rackRect.left - 52, h - 50, 44, 44);

    ctrlH = math.min(118, h * .3);
    final boardBottom = math.min(rackRect.top, h - ctrlH) - 4;
    boardRect = Rect.fromLTRB(sideW, topH, w - sideW, boardBottom);
    final gapF = (0.42 - 0.04 * boardRows).clamp(0.08, 0.35);
    cellW = math.min(boardRect.width / rowWidth, boardRect.height / (boardRows * tileAspect * (1 + gapF)));
    tileH = cellW * tileAspect;
    rowPitch = tileH * (1 + gapF);
    final usedH = boardRows * rowPitch - tileH * gapF;
    boardOrigin = Offset(
      boardRect.left + (boardRect.width - rowWidth * cellW) / 2,
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
    final col = fx.floor().clamp(0, rowWidth - 1);
    final row = math.max(0, ((p.dy - boardOrigin.dy + rowPitch * .1) / rowPitch).floor());
    return (row: row, col: col, frac: fx - fx.floor());
  }

  Rect rackSlot(int i) {
    final r = i ~/ rackPerRow, c = i % rackPerRow;
    return Rect.fromLTWH(
      rackRect.left + rackPadX + c * rackTileW + rackTileW * .03,
      rackRect.top + rackPadTop + r * rackRowH,
      rackTileW * .94,
      rackTileH,
    );
  }

  bool inRack(Offset p) => rackRect.inflate(8).contains(p);

  int rackIndexAt(Offset p, int count) {
    final c = ((p.dx - rackRect.left - rackPadX) / rackTileW).round().clamp(0, rackPerRow);
    final r = ((p.dy - rackRect.top - rackPadTop) / rackRowH).floor().clamp(0, rackRows - 1);
    return math.min(count, r * rackPerRow + c);
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
