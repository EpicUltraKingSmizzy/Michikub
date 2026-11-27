// Builds the prepackaged puzzle pack: dart run tool/gen_puzzles.dart [perLevel] [out.json]
// Fixed seed, so the same pack comes out every time.
import 'dart:convert';
import 'dart:io';

import 'package:michikub/engine/puzzle.dart';

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == 'master') {
    _genMaster(args.skip(1).toList());
    return;
  }
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


/// Append Master puzzles to an existing pack without touching Easy, Medium or Hard.
/// dart run tool/gen_puzzles.dart master [count] [out.json] [maxSeconds]
/// Kept puzzles are checkpointed to a side file next to [out.json] after each one
/// (atomic replace), and a later run loads them so a cap or crash cannot lose work.
void _genMaster(List<String> args) {
  final per = args.isNotEmpty ? int.parse(args[0]) : 200;
  final outPath = args.length > 1 ? args[1] : null;
  final maxSeconds = args.length > 2 ? int.parse(args[2]) : 2700;
  const masterSeed = 20261127;
  final sw = Stopwatch()..start();
  final seen = <String>{};
  final pool = <Puzzle>[];
  var dupes = 0;
  final checkpointPath = outPath == null ? null : _masterCheckpointPath(outPath);

  var resumeSeed = masterSeed;
  GenStats? loadedStats;
  if (checkpointPath != null) {
    final loaded = _loadMasterCheckpoint(checkpointPath, masterSeed);
    if (loaded != null) {
      for (final p in loaded.puzzles) {
        if (p.band != PuzzleLevel.master) continue;
        if (!seen.add(canonicalKey(p))) continue;
        pool.add(p);
      }
      dupes = loaded.dupes;
      resumeSeed = loaded.resumeSeed;
      loadedStats = loaded.stats;
      stderr.writeln('loaded checkpoint $checkpointPath: ${pool.length} kept, '
          'resumeSeed $resumeSeed, prior attempts ${loaded.stats.attempts}');
    }
  }

  if (pool.length >= per) {
    stderr.writeln('checkpoint already has ${pool.length} (>= $per); skipping generation');
    _finishMasterPack(pool, per, masterSeed, outPath, checkpointPath, sw, loadedStats ?? GenStats(), dupes);
    return;
  }

  final gen = PuzzleGenerator(resumeSeed);
  if (loadedStats != null) _copyStats(loadedStats, gen.stats);

  final want = per;
  while (pool.length < want) {
    if (sw.elapsed.inSeconds >= maxSeconds) {
      stderr.writeln('STALL: time limit hit after ${sw.elapsedMilliseconds / 1000} s, pool ${pool.length}');
      break;
    }
    final p = gen.attempt(PuzzleLevel.master);
    if (gen.stats.attempts % 10 == 0 || p != null) {
      stderr.writeln('progress ${sw.elapsedMilliseconds / 1000}s  pool ${pool.length}/$want  ${gen.stats}');
    }
    if (p == null) continue;
    if (p.band != PuzzleLevel.master) continue;
    if (!seen.add(canonicalKey(p))) {
      dupes++;
      continue;
    }
    pool.add(p);
    if (checkpointPath != null) {
      // Continuation seed so a resume does not replay the same Random sequence.
      final nextSeed = masterSeed + 1000003 * pool.length + gen.stats.attempts;
      _saveMasterCheckpoint(checkpointPath, masterSeed, nextSeed, pool, gen.stats, dupes);
    }
  }
  if (checkpointPath != null && pool.isNotEmpty) {
    final nextSeed = masterSeed + 1000003 * pool.length + gen.stats.attempts;
    _saveMasterCheckpoint(checkpointPath, masterSeed, nextSeed, pool, gen.stats, dupes);
  }
  _finishMasterPack(pool, per, masterSeed, outPath, checkpointPath, sw, gen.stats, dupes);
}

void _finishMasterPack(List<Puzzle> pool, int per, int masterSeed, String? outPath,
    String? checkpointPath, Stopwatch sw, GenStats s, int dupes) {
  // Ship the first [per] kept, in the order they were found.
  final picked = pool.length <= per ? List.of(pool) : pool.sublist(0, per);
  final secs = sw.elapsedMilliseconds / 1000;
  stdout.writeln('MASTER time ${secs.toStringAsFixed(1)} s');
  stdout.writeln(s);
  stdout.writeln('yield ${s.attempts == 0 ? 0 : (100 * s.accepted / s.attempts).toStringAsFixed(1)}% of attempts; '
      'dupes $dupes, pool ${pool.length}, kept ${picked.length}');
  final coreRate = s.uniqueCores == 0 ? 0 : 100 * s.decoyHits / s.uniqueCores;
  final comboRate = s.decoyTries == 0 ? 0 : 100 * s.decoyHits / s.decoyTries;
  stdout.writeln('unique cores ${s.uniqueCores}, decoy-pack success ${s.decoyHits}/${s.uniqueCores} '
      '(${coreRate.toStringAsFixed(1)}% of unique cores); '
      'combo tries ${s.decoyTries}, hits ${s.decoyHits} (${comboRate.toStringAsFixed(1)}% of combos)');
  if (picked.isNotEmpty) {
    final rack = picked.map((p) => p.rack.length).reduce((a, b) => a + b) / picked.length;
    final sc = picked.map((p) => p.setsChanged).reduce((a, b) => a + b) / picked.length;
    final tm = picked.map((p) => p.tilesMoved).reduce((a, b) => a + b) / picked.length;
    final dc = picked.map((p) => p.decoyCount).reduce((a, b) => a + b) / picked.length;
    final eq = picked.map((p) => p.equivalentSolutions).reduce((a, b) => a + b) / picked.length;
    final techs = <Technique, int>{};
    final scDist = <int, int>{};
    final dcDist = <int, int>{};
    for (final p in picked) {
      for (final t in p.techniques) {
        techs[t] = (techs[t] ?? 0) + 1;
      }
      scDist[p.setsChanged] = (scDist[p.setsChanged] ?? 0) + 1;
      dcDist[p.decoyCount] = (dcDist[p.decoyCount] ?? 0) + 1;
    }
    final jok = picked.where((p) => p.allTiles.any((t) => t >= 104)).length;
    stdout.writeln('avg rack ${rack.toStringAsFixed(1)}, avg setsChanged ${sc.toStringAsFixed(1)}, '
        'avg tilesMoved ${tm.toStringAsFixed(1)}, avg decoys ${dc.toStringAsFixed(1)}, '
        'avg equivalentSolutions ${eq.toStringAsFixed(2)}, setsChanged dist $scDist, '
        'decoy dist $dcDist, with jokers $jok, techniques ${techs.map((k, v) => MapEntry(k.name, v))}');
  }
  final projected = picked.isEmpty || secs == 0 ? 0 : secs / picked.length * per;
  stdout.writeln('projected time for $per: ${projected.toStringAsFixed(1)} s');
  if (outPath != null) {
    if (picked.length < per) {
      stderr.writeln('REFUSED to write $outPath: only ${picked.length} of $per Master puzzles '
          '(checkpoint kept at $checkpointPath)');
      exitCode = 2;
      return;
    }
    final existing = File(outPath).existsSync()
        ? jsonDecode(File(outPath).readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{'version': kPuzzlePackVersion, 'seed': 20261126};
    final out = {
      'version': existing['version'] ?? kPuzzlePackVersion,
      'seed': existing['seed'] ?? 20261126,
      'masterSeed': masterSeed,
      'easy': existing['easy'],
      'medium': existing['medium'],
      'hard': existing['hard'],
      'master': [for (final p in picked) p.toJson()],
    };
    final tmp = '$outPath.tmp';
    File(tmp).writeAsStringSync(jsonEncode(out));
    File(tmp).renameSync(outPath);
    stdout.writeln('wrote $outPath (${File(outPath).lengthSync()} bytes) with ${picked.length} master, '
        'kept existing easy/medium/hard');
    if (checkpointPath != null) {
      final ck = File(checkpointPath);
      if (ck.existsSync()) ck.deleteSync();
      final ctmp = File('$checkpointPath.tmp');
      if (ctmp.existsSync()) ctmp.deleteSync();
    }
  }
}

String _masterCheckpointPath(String outPath) {
  if (outPath.endsWith('.json')) {
    return '${outPath.substring(0, outPath.length - 5)}.master-checkpoint.json';
  }
  return '$outPath.master-checkpoint.json';
}

class _MasterCheckpoint {
  final int resumeSeed;
  final List<Puzzle> puzzles;
  final GenStats stats;
  final int dupes;
  _MasterCheckpoint(this.resumeSeed, this.puzzles, this.stats, this.dupes);
}

_MasterCheckpoint? _loadMasterCheckpoint(String path, int masterSeed) {
  final f = File(path);
  if (!f.existsSync()) return null;
  try {
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    if (j['masterSeed'] != masterSeed) {
      stderr.writeln('ignoring checkpoint $path: masterSeed ${j['masterSeed']} != $masterSeed');
      return null;
    }
    final puzzles = <Puzzle>[
      for (final p in (j['puzzles'] as List? ?? const []))
        Puzzle.fromJson((p as Map).cast<String, dynamic>()),
    ];
    final stats = GenStats();
    final raw = j['stats'];
    if (raw is Map) {
      _statsFromJson(raw.cast<String, dynamic>(), stats);
    }
    final resumeSeed = j['resumeSeed'] as int? ?? (masterSeed + 1000003 * puzzles.length);
    final dupes = j['dupes'] as int? ?? 0;
    return _MasterCheckpoint(resumeSeed, puzzles, stats, dupes);
  } catch (e) {
    stderr.writeln('ignoring unreadable checkpoint $path: $e');
    return null;
  }
}

void _saveMasterCheckpoint(
    String path, int masterSeed, int resumeSeed, List<Puzzle> pool, GenStats stats, int dupes) {
  final payload = {
    'masterSeed': masterSeed,
    'resumeSeed': resumeSeed,
    'dupes': dupes,
    'stats': _statsToJson(stats),
    'puzzles': [for (final p in pool) p.toJson()],
  };
  final tmp = '$path.tmp';
  File(tmp).writeAsStringSync(jsonEncode(payload));
  File(tmp).renameSync(path);
}

Map<String, int> _statsToJson(GenStats s) => {
      'attempts': s.attempts,
      'accepted': s.accepted,
      'simpleRejects': s.simpleRejects,
      'repairsTried': s.repairsTried,
      'repairsWorked': s.repairsWorked,
      'otherRejects': s.otherRejects,
      'scrambleFails': s.scrambleFails,
      'pullFails': s.pullFails,
      'qualifyRejects': s.qualifyRejects,
      'solverCaps': s.solverCaps,
      'decoyFails': s.decoyFails,
      'uniqueRejects': s.uniqueRejects,
      'fitRejects': s.fitRejects,
      'uniqueCores': s.uniqueCores,
      'decoyTries': s.decoyTries,
      'decoyHits': s.decoyHits,
    };

void _statsFromJson(Map<String, dynamic> j, GenStats s) {
  s.attempts = j['attempts'] as int? ?? 0;
  s.accepted = j['accepted'] as int? ?? 0;
  s.simpleRejects = j['simpleRejects'] as int? ?? 0;
  s.repairsTried = j['repairsTried'] as int? ?? 0;
  s.repairsWorked = j['repairsWorked'] as int? ?? 0;
  s.otherRejects = j['otherRejects'] as int? ?? 0;
  s.scrambleFails = j['scrambleFails'] as int? ?? 0;
  s.pullFails = j['pullFails'] as int? ?? 0;
  s.qualifyRejects = j['qualifyRejects'] as int? ?? 0;
  s.solverCaps = j['solverCaps'] as int? ?? 0;
  s.decoyFails = j['decoyFails'] as int? ?? 0;
  s.uniqueRejects = j['uniqueRejects'] as int? ?? 0;
  s.fitRejects = j['fitRejects'] as int? ?? 0;
  s.uniqueCores = j['uniqueCores'] as int? ?? 0;
  s.decoyTries = j['decoyTries'] as int? ?? 0;
  s.decoyHits = j['decoyHits'] as int? ?? 0;
}

void _copyStats(GenStats from, GenStats to) {
  to.attempts = from.attempts;
  to.accepted = from.accepted;
  to.simpleRejects = from.simpleRejects;
  to.repairsTried = from.repairsTried;
  to.repairsWorked = from.repairsWorked;
  to.otherRejects = from.otherRejects;
  to.scrambleFails = from.scrambleFails;
  to.pullFails = from.pullFails;
  to.qualifyRejects = from.qualifyRejects;
  to.solverCaps = from.solverCaps;
  to.decoyFails = from.decoyFails;
  to.uniqueRejects = from.uniqueRejects;
  to.fitRejects = from.fitRejects;
  to.uniqueCores = from.uniqueCores;
  to.decoyTries = from.decoyTries;
  to.decoyHits = from.decoyHits;
}
