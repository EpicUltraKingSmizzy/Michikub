import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/tiles.dart';
import 'theme.dart';

Color colorOf(TileColor c) => switch (c) {
      TileColor.red => MK.red,
      TileColor.blue => MK.blue,
      TileColor.yellow => MK.yellow,
      TileColor.black => MK.black,
    };

/// Glow states a tile can show.
enum TileGlow { none, selected, flashRed, shine, invalid }

/// The cream face of one tile: number over its suit symbol, or a joker.
class TileFace extends StatelessWidget {
  final int tile;
  final double width;
  final double height;
  final TileGlow glow;
  final bool dim;
  const TileFace({super.key, required this.tile, required this.width, required this.height, this.glow = TileGlow.none, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final c = colorOf(tileColor(tile));
    final r = width * 0.14;
    final glowShadow = switch (glow) {
      TileGlow.selected => [
          const BoxShadow(color: Color(0xFFFFD36B), spreadRadius: 2),
          BoxShadow(color: const Color(0xCCFFD36B), blurRadius: width * .35, spreadRadius: width * .06),
        ],
      TileGlow.flashRed => [
          const BoxShadow(color: Color(0xFFFF3B30), spreadRadius: 2),
          BoxShadow(color: const Color(0xCCFF3B30), blurRadius: width * .35, spreadRadius: width * .06),
        ],
      TileGlow.shine => [
          const BoxShadow(color: Color(0x99FFE08A), spreadRadius: 1),
          BoxShadow(color: const Color(0x88FFD36B), blurRadius: width * .3),
        ],
      _ => <BoxShadow>[],
    };
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dim ? const [Color(0xFFCFC6B4), Color(0xFFB9AE98)] : const [Color(0xFFFFFDF6), Color(0xFFF2EAD6)],
        ),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFCBBD98), width: math.max(1.5, height * .045)),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: width * .12, offset: Offset(0, height * .04)),
          ...glowShadow,
        ],
      ),
      foregroundDecoration: glow == TileGlow.invalid
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: const Color(0xCCFF5A4E), width: math.max(1.2, width * .05)),
            )
          : null,
      child: isJoker(tile) ? _joker(c) : _number(c),
    );
  }

  Widget _number(Color c) {
    final n = tileNumber(tile);
    final fs = (n >= 10 ? width * 0.5 : width * 0.58);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(height: height * (n >= 10 ? .12 : .08)),
        Text(
          '$n',
          maxLines: 1,
          style: TextStyle(
            fontFamily: 'Rubik',
            fontWeight: FontWeight.w800,
            fontSize: fs,
            height: 1.0,
            letterSpacing: -fs * .04,
            color: c,
          ),
        ),
        const Spacer(),
        CustomPaint(size: Size.square(width * 0.39), painter: SuitPainter(tileColor(tile), c)),
        SizedBox(height: height * .12),
      ],
    );
  }

  Widget _joker(Color c) {
    final name = ['red', 'black', 'yellow', 'blue'][tile - kJokerBase];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * .06, vertical: height * .1),
      child: Image.asset('assets/jokers/joker_$name.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
}

/// Suit symbols: red X, blue hollow square, yellow O, black dot.
class SuitPainter extends CustomPainter {
  final TileColor suit;
  final Color color;
  SuitPainter(this.suit, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round;
    switch (suit) {
      case TileColor.red:
        canvas.drawLine(Offset(s * .15, s * .15), Offset(s * .85, s * .85), stroke);
        canvas.drawLine(Offset(s * .85, s * .15), Offset(s * .15, s * .85), stroke);
      case TileColor.blue:
        stroke.strokeCap = StrokeCap.butt;
        canvas.drawRect(Rect.fromLTWH(s * .14, s * .14, s * .72, s * .72), stroke);
      case TileColor.yellow:
        canvas.drawCircle(Offset(s / 2, s / 2), s * .37, stroke);
      case TileColor.black:
        canvas.drawCircle(Offset(s / 2, s / 2), s * .32, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(SuitPainter old) => old.suit != suit || old.color != color;
}

/// A gold face-down tile (opponent indicators, the pile, flying draws).
class GoldBack extends StatelessWidget {
  final double width;
  final double height;
  const GoldBack({super.key, required this.width, required this.height});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: MK.goldGradient,
          borderRadius: BorderRadius.circular(math.max(2, width * .16)),
          border: Border.all(color: MK.goldDeep, width: math.max(.8, width * .06)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1))],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(math.max(2, width * .16)),
          gradient: const LinearGradient(
            begin: Alignment(-1, -.6),
            end: Alignment(1, .6),
            colors: [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
            stops: [.35, .48, .6],
          ),
        ),
      );
}
