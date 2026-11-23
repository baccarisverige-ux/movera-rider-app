import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/search_games.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: two games side by side in the pulled-up searching
/// sheet — Stockholm quiz (5 of 10 questions) and a 3×3 sliding puzzle.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  group('sliding puzzle', () {
    test('a shuffle is always solvable and is not solved', () {
      for (var seed = 0; seed < 50; seed++) {
        final puzzle = SlidingPuzzle();
        final history = puzzle.shuffle(Random(seed));
        expect(puzzle.solved, isFalse, reason: 'seed $seed');
        for (final tile in history.reversed) {
          expect(puzzle.move(tile), isTrue);
        }
        expect(puzzle.solved, isTrue, reason: 'seed $seed');
      }
    });

    test('only a tile next to the gap moves', () {
      final puzzle = SlidingPuzzle();
      expect(puzzle.move(0), isFalse); // far from the gap (cell 8)
      expect(puzzle.move(7), isTrue); // left of the gap
      expect(puzzle.solved, isFalse);
    });
  });

  testWidgets('quiz: 5 questions, right is green with the fact, the end '
      'says the score, best kept on this phone', (tester) async {
    await pump(tester, QuizGame(random: Random(1)));
    expect(find.text('Stockholm quiz'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(const ValueKey('quiz-question')), findsOneWidget);
      final key = i == 1 ? 'quiz-answer-wrong' : 'quiz-answer-ok';
      await tester.tap(find.byKey(ValueKey(key)).first);
      await tester.pump();
      expect(
        find.textContaining(i == 1 ? 'Not quite.' : 'Right!'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('4 of 5 right!'), findsOneWidget);
    expect(find.text('Well done!'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(QuizGame.bestKey), 4);
  });

  testWidgets('puzzle: shuffled, tiles move, solving says the moves', (
    tester,
  ) async {
    late SlidingPuzzle puzzle;
    await pump(
      tester,
      PuzzleGame(random: Random(3), onPuzzle: (p) => puzzle = p),
    );
    expect(find.text('Puzzle'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 3));
    expect(puzzle.solved, isFalse);
    expect(find.text('Moves'), findsOneWidget);
    // Solve by undoing the shuffle, tapping the tiles on screen.
    for (final tile in puzzle.history.reversed.toList()) {
      await tester.tap(find.byKey(ValueKey('puzzle-tile-$tile')));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(puzzle.solved, isTrue);
    expect(find.text('Done!'), findsOneWidget);
    expect(find.text('${puzzle.history.length} moves'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(PuzzleGame.bestKey), puzzle.history.length);
  });

  testWidgets('the swipe row holds both cards, snaps per card, has dots', (
    tester,
  ) async {
    await pump(tester, const SearchGamesRow());
    expect(find.byKey(const ValueKey('search-games-row')), findsOneWidget);
    expect(find.byType(QuizGame), findsOneWidget);
    final list = find.byKey(const ValueKey('search-games-list'));
    expect(list, findsOneWidget);
    expect(find.byKey(const ValueKey('search-games-dots')), findsOneWidget);
    await tester.drag(list, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(PuzzleGame), findsOneWidget);
    // Snapped: the second card sits where the first one did.
    expect(tester.getTopLeft(find.byType(PuzzleGame)).dx, 16);
  });

  testWidgets('a driver accepting stops a running game', (tester) async {
    final active = ValueNotifier<bool>(true);
    await pump(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (_, on, __) => QuizGame(random: Random(1), active: on),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.byKey(const ValueKey('quiz-question')), findsOneWidget);
    active.value = false;
    await tester.pump();
    expect(find.byKey(const ValueKey('quiz-question')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
