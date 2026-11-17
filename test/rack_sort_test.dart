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

  group('rack slots (v0.1.7: blanks stay where the player leaves them)', () {
    List<String> show(List<int> e) => [for (final x in e) isRackGap(x) ? '_' : '$x'];

    test('only blanks at the end are trimmed', () {
      expect(show(trimRack([-1, 5, -2, -3, 6, -4])), ['_', '5', '_', '_', '6']);
    });

    test('a drop past the last tile pads with blanks', () {
      expect(show(placeInRack([1, 2, 3], [9], 6)), ['1', '2', '3', '_', '_', '_', '9']);
    });

    test('moving a tile leaves its slot blank; a drop on a blank fills it', () {
      final e = placeInRack([1, 2, 3, 4], [2], 6);
      expect(show(e), ['1', '_', '3', '4', '_', '_', '2']);
      expect(show(placeInRack(e, [4], 1)), ['1', '4', '3', '_', '_', '_', '2']);
    });

    test('a drop on a tile shifts tiles right only as far as the next blank', () {
      expect(show(placeInRack([1, 2, -5, 3, 4], [9], 0)), ['9', '1', '2', '3', '4']);
      expect(show(placeInRack([1, 2, 3], [9], 1)), ['1', '9', '2', '3']);
    });

    test('several tiles land in consecutive slots', () {
      expect(show(placeInRack([1, 2, 3, 4, 5], [4, 5], 7)), ['1', '2', '3', '_', '_', '_', '_', '4', '5']);
    });

    test('tiles on the table count as blank slots', () {
      expect(show(placeInRack([1, 7, 3], [9], 1, free: {7})), ['1', '9', '3']);
    });

    test('drawn tiles go right after the last tile, keeping blanks between sets; past two rows, the first blank', () {
      expect(show(addToRack([1, -3, 2, -4], 8)), ['1', '_', '2', '8']);
      expect(show(addToRack([1, -3, -5, 2, -4, -6], 8)), ['1', '_', '_', '2', '8'], reason: 'the gap the player left stays');
      final full = [for (var i = 0; i < 20; i++) i == 4 || i == 15 ? -7 - i : i + 100];
      final out = addToRack(full, 8);
      expect(out.length, 20);
      expect(out[4], 8, reason: 'the first blank, not a random one');
      expect(isRackGap(out[15]), true);
    });

    test('sorted sets do not straddle the row break', () {
      // 8 tiles, gap, then a 3-tile set: the set starts the second row.
      final sorted = [for (var i = 0; i < 8; i++) i + 1, -1, 50, 51, 52];
      final out = keepSetsOnRows(sorted);
      expect(out.indexOf(50), kRackRowSlots);
      expect(out.sublist(kRackRowSlots), [50, 51, 52]);
    });
  });
}
