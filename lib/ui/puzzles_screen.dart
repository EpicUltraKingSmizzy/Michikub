import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/puzzles.dart';
import '../engine/puzzle.dart';
import 'game_screen.dart';
import 'theme.dart';

/// Puzzles: Easy, Medium and Hard. Each button shows how many are solved (20/400) and fills
/// with gold from the left like a loading bar; a finished difficulty gets a gold star. A tap
/// opens the next unsolved puzzle (after the star, new puzzles are made on the phone).
class PuzzlesScreen extends StatefulWidget {
  const PuzzlesScreen({super.key});
  @override
  State<PuzzlesScreen> createState() => _PuzzlesScreenState();
}

class _PuzzlesScreenState extends State<PuzzlesScreen> {
  PuzzlePack? _pack;
  final progress = PuzzleProgress.instance;

  @override
  void initState() {
    super.initState();
    progress.addListener(_changed);
    PuzzlePack.load().then((p) {
      progress.ensurePackVersion(p.version);
      if (mounted) setState(() => _pack = p);
    });
  }

  @override
  void dispose() {
    progress.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _open(PuzzleLevel l) {
    final pack = _pack;
    if (pack == null) return;
    final session = PuzzleSession(level: l, pack: pack);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(session: session)));
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return MkScaffold(
      title: 'Puzzles',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: pack == null
              ? const CircularProgressIndicator(color: MK.gold)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Play every tile from your rack. You\'ll have to rearrange the table.',
                      textAlign: TextAlign.center, style: MK.body(14, color: MK.gold)),
                  const SizedBox(height: 16),
                  for (final l in PuzzleLevel.values) ...[
                    PuzzleLevelButton(
                      key: ValueKey('level-${l.name}'),
                      label: puzzleLevelName(l),
                      solved: math.min(progress.solved[l]!.length, pack.count(l)),
                      total: pack.count(l),
                      onPressed: () => _open(l),
                    ),
                    const SizedBox(height: 12),
                  ],
                ]),
        ),
      ),
    );
  }
}

/// One difficulty: label on the left, "solved/total" on the right, a gold fill from the left
/// for the share solved, and a gold star beside it once every puzzle is solved (the space is
/// kept either way, so the buttons line up).
class PuzzleLevelButton extends StatelessWidget {
  final String label;
  final int solved;
  final int total;
  final VoidCallback? onPressed;
  final double width;
  const PuzzleLevelButton({super.key, required this.label, required this.solved, required this.total, this.onPressed, this.width = 300});

  double get fraction => total <= 0 ? 0 : (solved / total).clamp(0.0, 1.0);
  bool get complete => total > 0 && solved >= total;

  @override
  Widget build(BuildContext context) {
    const h = 58.0;
    final text = MK.body(18, color: MK.creamText, weight: FontWeight.w800)
        .copyWith(shadows: const [Shadow(color: Colors.black, blurRadius: 4), Shadow(color: Colors.black87, blurRadius: 1)]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 44), // balances the star on the right
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(h / 2),
          onTap: onPressed,
          child: Container(
            width: width,
            height: h,
            decoration: BoxDecoration(
              gradient: MK.lipGradient,
              borderRadius: BorderRadius.circular(h / 2),
              border: Border.all(color: MK.gold, width: 1.4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(h / 2),
              child: Stack(children: [
                // The gold fill, left to right.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * fraction,
                  child: const DecoratedBox(key: ValueKey('levelFill'), decoration: BoxDecoration(gradient: MK.goldGradient)),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(children: [
                      Expanded(child: Text(label, style: text)),
                      Text('$solved/$total', key: const ValueKey('levelProgress'), style: text.copyWith(fontSize: 16)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 44,
        height: 44,
        child: complete ? const Padding(padding: EdgeInsets.only(left: 8), child: GoldStar(key: ValueKey('levelStar'))) : null,
      ),
    ]);
  }
}

/// A five-pointed gold star, drawn (not an emoji).
class GoldStar extends StatelessWidget {
  final double size;
  const GoldStar({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _StarPainter()));
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * .45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawShadow(path, Colors.black, 3, false);
    final rect = Rect.fromCircle(center: c, radius: outer);
    canvas.drawPath(path, Paint()..shader = MK.goldGradient.createShader(rect));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, outer * .07)
          ..strokeJoin = StrokeJoin.round
          ..color = MK.goldDeep);
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}
