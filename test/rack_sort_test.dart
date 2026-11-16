import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/engine/meld.dart';
import 'package:michikub/engine/rack_sort.dart';
import 'package:michikub/engine/tiles.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);

/// Splits sorted entries at the gaps.
List<List<int>> segments(List<int> e) {
  final out = <List<int>>[[]];
  for (final x in e) {
    if (isRackGap(x)) {
      out.add([]);
    } else {
      out.last.add(x);
    }
  }
  return out.where((s) => s.isNotEmpty).toList();
}

void main() {
  test('sets go first, each followed by a gap, then the rest sorted', () {
    final rack = [k(12), r(5), b(7), r(4), y(7), r(3), k(1), r(7), b(2)];
    final e = sortRackWithSets(rack, runs: true);
    expect(e.where((x) => !isRackGap(x)).toSet(), rack.toSet(), reason: 'same tiles, nothing lost');
    final segs = segments(e);
    expect(segs.length, 3);
    expect(segs[0], [r(3), r(4), r(5)], reason: 'run in order, top left');
    expect(isValidMeld(segs[1]), true);
    expect(segs[1].toSet(), {b(7), y(7), r(7)});
    expect(segs[2], [b(2), k(1), k(12)], reason: 'leftovers sorted by colour then number (runs mode)');
    // A gap after each set, none inside sets.
    expect(isRackGap(e[3]), true);
    expect(isRackGap(e[7]), true);
  });

  test('groups mode sorts leftovers by number and the gaps are distinct ids', () {
    final rack = [k(12), r(9), b(9), y(9), b(2), r(1)];
    final e = sortRackWithSets(rack, runs: false);
    final segs = segments(e);
    expect(segs[0].toSet(), {r(9), b(9), y(9)});
    expect(segs[1], [r(1), b(2), k(12)]);
    final gaps = e.where(isRackGap).toList();
    expect(gaps.toSet().length, gaps.length);
  });

  test('no sets: just sorted, no gaps', () {
    final rack = [k(12), r(9), b(3)];
    expect(sortRackWithSets(rack, runs: true), [b(3), k(12), r(9)]..sort((a, c) => runSortKey(a) - runSortKey(c)));
    expect(sortRackWithSets(rack, runs: true).any(isRackGap), false);
  });

  test('tidy removes leading, trailing and doubled gaps', () {
    expect(tidyRackGaps([-1, 5, -2, -3, 6, -4]), [5, -2, 6]);
  });
}
