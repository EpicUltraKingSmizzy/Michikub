import 'bot.dart';
import 'tiles.dart';

/// Rack entries are tile ids (>= 0) or gap markers (< 0). Gaps are small spaces in the rack
/// that keep sorted sets apart. Each gap has its own id so it can be tracked in a list.
bool isRackGap(int entry) => entry < 0;

/// Sorts a rack for the 789 (runs) and 777 (groups) buttons:
/// the valid sets of 3+ tiles that can be made from the rack come first (top left), each
/// followed by a gap, then the remaining tiles sorted by the chosen mode.
/// [rack] holds tile ids only. Returns tiles with gap markers -1, -2, ... between sets.
List<int> sortRackWithSets(List<int> rack, {required bool runs}) {
  final key = runs ? runSortKey : groupSortKey;
  int byKey(int a, int b) => key(a) - key(b);
  final tiles = rack.where((t) => !isRackGap(t)).toList();
  // Prefer the button's kind of set: rank those candidates first so ties go their way.
  final cands = candidateMelds(tiles);
  bool isRun(List<int> m) {
    final real = m.where((t) => !isJoker(t)).toList();
    return real.length >= 2 && tileNumber(real[0]) != tileNumber(real[1]);
  }

  cands.sort((a, b) => (isRun(a) == runs ? 0 : 1) - (isRun(b) == runs ? 0 : 1));
  final sets = bestCombination(cands);
  final used = {for (final m in sets) ...m};
  // Order the sets by their first numbered tile in the chosen mode; keep run order within a run.
  int setKey(List<int> m) => key(m.firstWhere((t) => !isJoker(t), orElse: () => m.first));
  final ordered = [
    for (final m in sets) isRun(m) ? m : (List.of(m)..sort(byKey)),
  ]..sort((a, b) => setKey(a) - setKey(b));
  final rest = tiles.where((t) => !used.contains(t)).toList()..sort(byKey);
  final out = <int>[];
  var gap = -1;
  for (final m in ordered) {
    out.addAll(m);
    out.add(gap--); // A trailing gap keeps later (drawn) tiles apart from the last set.
  }
  out.addAll(rest);
  return out;
}

/// The rack as shown: no gap at the start or end, and never two gaps in a row.
List<int> tidyRackGaps(List<int> entries) {
  final out = <int>[];
  for (final e in entries) {
    if (isRackGap(e) && (out.isEmpty || isRackGap(out.last))) continue;
    out.add(e);
  }
  while (out.isNotEmpty && isRackGap(out.last)) {
    out.removeLast();
  }
  return out;
}
