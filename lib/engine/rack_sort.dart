import 'dart:math' as math;

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

/// The rack is a grid of slots (rows of [kRackRowSlots] while it holds up to 20 entries): each
/// entry is a tile or a blank slot (< 0). Players can leave blanks anywhere; only blanks at
/// the very end are dropped.
const int kRackRowSlots = 10;

var _blankSeq = -1000000;

/// A new blank slot id (unique, so lists of entries stay easy to compare).
int newRackBlank() => _blankSeq--;

/// Drops blank slots at the end.
List<int> trimRack(List<int> entries) {
  final out = List<int>.of(entries);
  while (out.isNotEmpty && isRackGap(out.last)) {
    out.removeLast();
  }
  return out;
}

/// Slots per row for [n] entries: 10, widening past 20 so two rows hold them all.
int rackSlotsPerRow(int n) => n <= 2 * kRackRowSlots ? kRackRowSlots : (n + 1) ~/ 2;

/// Rows the rack shows for [n] entries.
int rackRowsFor(int n) => n <= kRackRowSlots ? 1 : 2;

/// Puts [tiles] into the rack at [slot] onward, one slot each, leaving blanks wherever they
/// are: the slots the tiles came from become blank, a drop past the last tile pads with
/// blanks, a drop on a blank fills it, and a drop on a tile shifts tiles right only as far
/// as the next blank. Entries in [free] (tiles now on the table) count as blank.
List<int> placeInRack(List<int> entries, List<int> tiles, int slot, {Set<int> free = const {}}) {
  final out = [
    for (final e in entries) tiles.contains(e) || free.contains(e) ? newRackBlank() : e,
  ];
  var at = math.max(0, slot);
  for (final t in tiles) {
    while (out.length < at) {
      out.add(newRackBlank());
    }
    if (at == out.length) {
      out.add(t);
    } else if (isRackGap(out[at])) {
      out[at] = t;
    } else {
      var j = at + 1;
      while (j < out.length && !isRackGap(out[j])) {
        j++;
      }
      if (j < out.length) out.removeAt(j);
      out.insert(at, t);
    }
    at++;
  }
  return trimRack(out);
}

/// A tile entering the rack (a draw) goes in the slot right after the last tile, keeping any
/// blanks the player left between sets. Once that's past the two rows (20 slots), it takes
/// the first blank; with no blanks, it's added at the end.
List<int> addToRack(List<int> entries, int tile) {
  final out = trimRack(entries);
  if (out.length >= 2 * kRackRowSlots) {
    final i = out.indexWhere(isRackGap);
    if (i >= 0) {
      out[i] = tile;
      return out;
    }
  }
  return out..add(tile);
}

/// A sorted rack (sets separated by one blank) laid out so a set of up to 10 never straddles
/// the row break: it starts the second row instead (when everything still fits in 2 x 10).
List<int> keepSetsOnRows(List<int> sorted) {
  final out = <int>[];
  var i = 0;
  while (i < sorted.length) {
    if (isRackGap(sorted[i])) {
      out.add(sorted[i]);
      i++;
      continue;
    }
    var j = i;
    while (j < sorted.length && !isRackGap(sorted[j])) {
      j++;
    }
    final len = j - i;
    final col = out.length % kRackRowSlots;
    final padded = out.length + (kRackRowSlots - col) + (sorted.length - i);
    if (out.length < kRackRowSlots && col > 0 && col + len > kRackRowSlots && len <= kRackRowSlots && padded <= 2 * kRackRowSlots) {
      while (out.length < kRackRowSlots) {
        out.add(newRackBlank());
      }
    }
    out.addAll(sorted.sublist(i, j));
    i = j;
  }
  return trimRack(out);
}
