// Builds the prepackaged puzzle pack: dart run tool/gen_puzzles.dart [perLevel] [out.json]
// Fixed seed, so the same pack comes out every time.
import 'dart:convert';
import 'dart:io';

import 'package:michikub/engine/puzzle.dart';

void main(List<String> args) {
  final per = args.isNotEmpty ? int.parse(args[0]) : 400;
  final outPath = args.length > 1 ? args[1] : null;
  final maxSeconds = args.length > 2 ? int.parse(args[2]) : 1200;
  final sw = Stopwatch()..start();
  final gen = PuzzleGenerator(20261126);
  final seen = <String>{};
  // Keep a surplus pool per level so curation can pick a balanced mix.
  final pool = {for (final l in PuzzleLevel.values) l: <Puzzle>[]};
  final want = (per * 1.25).ceil();
  var dupes = 0, wrongLevel = 0;
  final perLevelAttempts = {for (final l in PuzzleLevel.values) l: 0};
  while (PuzzleLevel.values.any((l) => pool[l]!.length < want)) {
    if (sw.elapsed.inSeconds > maxSeconds) {
      stderr.writeln('STALL: time limit hit');
      break;
    }
    for (final aim in PuzzleLevel.values) {
      if (pool[aim]!.length >= want) continue;
      perLevelAttempts[aim] = perLevelAttempts[aim]! + 1;
      final p = gen.attempt(aim);
      if (p == null) continue;
      final lvl = p.band;
      if (lvl == null) continue;
      if (pool[lvl]!.length >= want) {
        wrongLevel++;
        continue;
      }
      if (!seen.add(canonicalKey(p))) {
        dupes++;
        continue;
      }
      pool[lvl]!.add(p);
    }
  }
  final pack = <String, List<Puzzle>>{};
  for (final l in PuzzleLevel.values) {
    pack[l.name] = curate(pool[l]!, per, l);
  }
  final secs = sw.elapsedMilliseconds / 1000;
  final s = gen.stats;
  stdout.writeln('time ${secs.toStringAsFixed(1)} s');
  stdout.writeln(s);
  stdout.writeln('yield ${(100 * s.accepted / s.attempts).toStringAsFixed(1)}% of attempts; '
      'repair success ${s.repairsTried == 0 ? 0 : (100 * s.repairsWorked / s.repairsTried).toStringAsFixed(1)}%');
  stdout.writeln('dupes $dupes, overflow (level already full) $wrongLevel');
  stdout.writeln('attempts aimed per level: $perLevelAttempts');
  for (final l in PuzzleLevel.values) {
    final ps = pack[l.name]!;
    final techs = <Technique, int>{};
    for (final p in ps) {
      for (final t in p.techniques) {
        techs[t] = (techs[t] ?? 0) + 1;
      }
    }
    final rack = ps.isEmpty ? 0 : ps.map((p) => p.rack.length).reduce((a, b) => a + b) / ps.length;
    final jok = ps.where((p) => p.allTiles.any((t) => t >= 104)).length;
    final sc = <int, int>{};
    for (final p in ps) {
      sc[p.setsChanged] = (sc[p.setsChanged] ?? 0) + 1;
    }
    final tm = ps.isEmpty ? 0 : ps.map((p) => p.tilesMoved).reduce((a, b) => a + b) / ps.length;
    final scAvg = ps.isEmpty ? 0 : ps.map((p) => p.setsChanged).reduce((a, b) => a + b) / ps.length;
    stdout.writeln('${l.name}: ${ps.length} (pool ${pool[l]!.length}), avg rack ${rack.toStringAsFixed(1)}, '
        'avg setsChanged ${scAvg.toStringAsFixed(1)}, avg tilesMoved ${tm.toStringAsFixed(1)}, '
        'setsChanged dist $sc, with jokers $jok, techniques ${techs.map((k, v) => MapEntry(k.name, v))}');
  }
  if (outPath != null) {
    final json = {
      'version': kPuzzlePackVersion,
      'seed': 20261126,
      for (final e in pack.entries) e.key: [for (final p in e.value) p.toJson()],
    };
    File(outPath).writeAsStringSync(jsonEncode(json));
    stdout.writeln('wrote $outPath (${File(outPath).lengthSync()} bytes)');
  }
}

/// Picks [n] puzzles with a balanced mix of techniques, then orders them so each technique
/// gets introduced on its own before they mix, easiest first.
List<Puzzle> curate(List<Puzzle> pool, int n, PuzzleLevel level) {
  final byTech = {for (final t in Technique.values) t: <Puzzle>[]};
  for (final p in pool) {
    // File each puzzle under its rarest technique so rare ones aren't crowded out.
    final t = p.techniques.reduce((a, b) => a.index > b.index ? a : b);
    byTech[t]!.add(p);
  }
  for (final l in byTech.values) {
    l.sort((a, b) => a.score.compareTo(b.score));
  }
  // Round-robin across techniques (balanced), lowest scores first.
  final picked = <Puzzle>[];
  var i = 0;
  while (picked.length < n && byTech.values.any((l) => l.length > i)) {
    for (final t in Technique.values) {
      if (picked.length >= n) break;
      if (byTech[t]!.length > i) picked.add(byTech[t]![i]);
    }
    i++;
  }
  // Order: an intro block per technique (Easy: 4 each, others: 2 each), then by score.
  final intro = <Puzzle>[];
  final rest = List.of(picked)..sort((a, b) => a.score.compareTo(b.score));
  final per = level == PuzzleLevel.easy ? 4 : 2;
  for (final t in const [
    Technique.splitGroup,
    Technique.runToGroup,
    Technique.jokerShift,
    Technique.jokerToNewSet,
    Technique.splitRun,
  ]) {
    final mine = rest.where((p) => p.techniques.length == 1 && p.techniques.first == t).take(per).toList();
    intro.addAll(mine);
    rest.removeWhere(mine.contains);
  }
  return [...intro, ...rest];
}
