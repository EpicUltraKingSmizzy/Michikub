import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michikub/app/puzzles.dart';
import 'package:michikub/app/sfx.dart';
import 'package:michikub/engine/board.dart';
import 'package:michikub/engine/host.dart';
import 'package:michikub/engine/puzzle.dart';
import 'package:michikub/engine/tiles.dart';
import 'package:michikub/ui/game_screen.dart';
import 'package:michikub/ui/home.dart';
import 'package:michikub/ui/puzzles_screen.dart';

int r(int n) => makeTile(TileColor.red, n);
int b(int n) => makeTile(TileColor.blue, n);
int y(int n) => makeTile(TileColor.yellow, n);
int k(int n) => makeTile(TileColor.black, n);

final p1 = Puzzle(board: [[r(7), b(7), y(7), k(7)]], rack: [r(8), r(9)], solution: [[b(7), y(7), k(7)], [r(7), r(8), r(9)]]);
final p2 = Puzzle(board: [[r(4), r(5), r(6), r(7)]], rack: [b(7), y(7)], solution: [[r(4), r(5), r(6)], [r(7), b(7), y(7)]]);
final pack = PuzzlePack({PuzzleLevel.easy: [p1, p2], PuzzleLevel.medium: [p2, p1], PuzzleLevel.hard: [p1]});

Board solvedBoard(Puzzle p) {
  final b = Board.empty();
  var row = 0;
  for (final s in p.solution) {
    b.ensureRows(row + 1);
    b.rows[row].setAll(0, s);
    row++;
  }
  return b;
}

void main() {
  setUp(() {
    PuzzleProgress.instance.reset();
    PuzzleProgress.instance.packVersion = pack.version;
    PuzzlePack.debugPack = pack;
  });

  group('session', () {
    test('opens the next unsolved puzzle, saves progress, lists beaten ones', () async {
      final s = PuzzleSession(level: PuzzleLevel.easy, pack: pack);
      expect(s.number, 1);
      expect(s.view!.rack.toSet(), p1.rack.toSet());
      expect(s.view!.pile, greaterThan(0));
      expect((await s.act(const DrawAction())).ok, false, reason: 'no draws in puzzles');
      // Not done yet: one rack tile still in the rack.
      final half = s.view!.board.copy();
      expect((await s.act(PreviewAction(half))).ok, true);
      expect(s.phase, PuzzlePhase.playing);
      await s.act(PreviewAction(solvedBoard(p1)));
      expect(s.phase, PuzzlePhase.solved);
      expect(PuzzleProgress.instance.solved[PuzzleLevel.easy], {0});
      s.clearTable();
      expect(s.view!.board.allTiles, isEmpty);
      expect(s.view!.rack, isEmpty);
      s.nextPuzzle();
      expect(s.number, 2);
      expect(s.beaten.map((x) => x.number), [1]);
      s.open(s.beaten.first);
      expect(s.number, 1, reason: 'replay from the list');
    });

    test('after the last pack puzzle (the star), new puzzles are made on the phone', () async {
      final s = PuzzleSession(level: PuzzleLevel.hard, pack: pack);
      await s.act(PreviewAction(solvedBoard(p1)));
      expect(PuzzleProgress.instance.complete(PuzzleLevel.hard, 1), true);
      s.clearTable();
      s.nextPuzzle();
      expect(s.isEndless, true);
      expect(s.number, 2);
      final made = s.puzzle;
      expect(checkPuzzle(made.board, made.rack), isNotNull);
      await s.act(PreviewAction(solvedBoard(made)));
      expect(s.phase, PuzzlePhase.solved);
      expect(PuzzleProgress.instance.endless[PuzzleLevel.hard], hasLength(1));
      expect(s.beaten.map((x) => x.number), [1, 2]);
    });

    test('progress survives a save and load (as JSON)', () {
      final p = PuzzleProgress();
      p.solved[PuzzleLevel.medium]!.addAll([0, 3]);
      p.endless[PuzzleLevel.easy]!.add(p1);
      p.endlessSolved[PuzzleLevel.easy] = 1;
      final q = PuzzleProgress()..fromJson(p.toJson());
      expect(q.solved[PuzzleLevel.medium], {0, 3});
      expect(q.endless[PuzzleLevel.easy]!.single.rack, p1.rack);
      expect(q.nextUnsolved(PuzzleLevel.medium, 5), 1);
    });

    test('a new pack version clears saved progress', () {
      final p = PuzzleProgress();
      p.packVersion = 1;
      p.solved[PuzzleLevel.easy]!.add(3);
      p.endless[PuzzleLevel.easy]!.add(p1);
      p.endlessSolved[PuzzleLevel.easy] = 1;
      p.ensurePackVersion(2);
      expect(p.packVersion, 2);
      expect(p.solved[PuzzleLevel.easy], isEmpty);
      expect(p.endless[PuzzleLevel.easy], isEmpty);
      expect(p.endlessSolved[PuzzleLevel.easy], 0);
      p.ensurePackVersion(2);
      expect(p.packVersion, 2, reason: 'same version does not reset again');
    });
  });

  group('screens', () {
    testWidgets('home: Host and Join on top, then Puzzles, Play vs bots, Pass-and-play, Options', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(home: HomeScreen(fitToScreen: false)));
      final labels = ['Host a game', 'Join a game', 'Puzzles', 'Play vs bots', 'Pass-and-play', 'Options'];
      final tops = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
      expect(tops, [...tops]..sort());
      tester.view.reset();
    });

    testWidgets('difficulty buttons: progress text, gold fill and a star only when complete', (tester) async {
      PuzzleProgress.instance.solved[PuzzleLevel.easy]!.add(0); // 1/2
      PuzzleProgress.instance.solved[PuzzleLevel.hard]!.add(0); // 1/1
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(home: PuzzlesScreen()));
      await tester.pump();
      await tester.pump();
      String progress(String l) => tester.widget<Text>(find.descendant(of: find.byKey(ValueKey('level-$l')), matching: find.byKey(const ValueKey('levelProgress')))).data!;
      expect(progress('easy'), '1/2');
      expect(progress('medium'), '0/2');
      expect(progress('hard'), '1/1');
      double fill(String l) => tester.getSize(find.descendant(of: find.byKey(ValueKey('level-$l')), matching: find.byKey(const ValueKey('levelFill')))).width;
      expect(fill('easy'), closeTo(150, .5));
      expect(fill('medium'), 0);
      expect(fill('hard'), closeTo(300, .5));
      expect(find.descendant(of: find.byKey(const ValueKey('level-hard')), matching: find.byType(GoldStar)), findsOneWidget);
      expect(find.byType(GoldStar), findsOneWidget);
      tester.view.reset();
    });

    testWidgets('a puzzle at the table: #number, no Draw, a win plays the success sound, tidies up and deals the next', (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      final s = PuzzleSession(level: PuzzleLevel.easy, pack: pack);
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Easy  #1'), findsOneWidget);
      expect(find.byKey(const ValueKey('drawButton')), findsNothing);
      expect(find.text('IN PILE'), findsNothing);
      SoundBoard.instance.log.clear();
      (tester.state(find.byType(GameScreen)) as dynamic).debugSetWorking(solvedBoard(p1));
      await tester.pump();
      expect(s.phase, PuzzlePhase.solved);
      expect(SoundBoard.instance.log, contains(Sfx.turnEnd));
      expect(find.byKey(const ValueKey('puzzleBlock')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: TableTuning.puzzlePauseMs + 50));
      expect(s.phase, PuzzlePhase.clearing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(s.phase, PuzzlePhase.playing);
      expect(find.text('Easy  #2'), findsOneWidget);
      // The list of beaten puzzles.
      await tester.tap(find.text('Easy  #2'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('#1'), findsOneWidget);
      await tester.tap(find.text('#1'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Easy  #1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tester.view.reset();
    });

    testWidgets('the deal: table and rack tiles fly in from the deck with the opening sound', (tester) async {
      TableTuning.dealAnimation = true;
      addTearDown(() => TableTuning.dealAnimation = false);
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      SoundBoard.instance.log.clear();
      final s = PuzzleSession(level: PuzzleLevel.easy, pack: pack);
      await tester.pumpWidget(MaterialApp(home: GameScreen(session: s)));
      expect(SoundBoard.instance.log, contains(Sfx.gameStart));
      expect(find.byKey(const ValueKey('dealBlock')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('dealBlock')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tester.view.reset();
    });
  });
}
