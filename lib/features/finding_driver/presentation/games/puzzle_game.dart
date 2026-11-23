import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/quiz_game.dart'
    show gameText;
import 'package:movera_rider/features/finding_driver/presentation/games/search_games.dart'
    show GameCard, GamePill;
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/finding_driver/application/game_scores.dart';

/// A 3×3 sliding puzzle: tile k (0..7) belongs in cell k, the gap (8) in
/// cell 8. [pos] holds each tile's current cell.
class SlidingPuzzle {
  final List<int> pos = List<int>.generate(9, (k) => k);

  /// The tiles moved by the last [shuffle], in order.
  List<int> history = const [];

  static const int gap = 8;

  bool get solved => [for (var k = 0; k < 9; k++) pos[k] == k].every((b) => b);

  static bool _next(int a, int b) =>
      (a % 3 - b % 3).abs() + (a ~/ 3 - b ~/ 3).abs() == 1;

  bool canMove(int tile) => tile != gap && _next(pos[tile], pos[gap]);

  /// Slides [tile] into the gap; false when it is not next to it.
  bool move(int tile) {
    if (!canMove(tile)) return false;
    final cell = pos[tile];
    pos[tile] = pos[gap];
    pos[gap] = cell;
    return true;
  }

  void reset() {
    for (var k = 0; k < 9; k++) {
      pos[k] = k;
    }
  }

  /// Mixes the solved board by [moves] legal moves (never straight back),
  /// so it is always solvable; never left solved.
  List<int> shuffle(Random random, {int moves = 24}) {
    reset();
    final done = <int>[];
    var last = -1;
    while (done.length < moves || solved) {
      final options = [
        for (var k = 0; k < gap; k++)
          if (canMove(k) && k != last) k,
      ];
      final tile = options[random.nextInt(options.length)];
      move(tile);
      done.add(tile);
      last = tile;
    }
    history = done;
    return done;
  }
}

enum _PuzzleStage { start, mixing, play, done }

/// Q2 Pussel: a 3×3 sliding picture of Stockholm, a move counter,
/// "Klart! N drag" and Spela igen. Fewest moves kept on this phone only.
class PuzzleGame extends StatefulWidget {
  const PuzzleGame({
    super.key,
    this.active = true,
    this.random,
    @visibleForTesting this.onPuzzle,
  });

  static const String bestKey = GameScores.puzzleKey;
  static const String picture = 'assets/games/puzzle.svg';

  final bool active;
  final Random? random;
  final ValueChanged<SlidingPuzzle>? onPuzzle;

  @override
  State<PuzzleGame> createState() => _PuzzleGameState();
}

class _PuzzleGameState extends State<PuzzleGame> {
  late final Random _random = widget.random ?? Random();
  final SlidingPuzzle _puzzle = SlidingPuzzle();
  _PuzzleStage _stage = _PuzzleStage.start;
  int _moves = 0;
  Timer? _timer;

  static const double _board = 222;
  static const double _tile = _board / 3;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    widget.onPuzzle?.call(_puzzle);
  }

  @override
  void didUpdateWidget(PuzzleGame old) {
    super.didUpdateWidget(old);
    if (!widget.active && _stage != _PuzzleStage.start) {
      _timer?.cancel();
      _puzzle.reset();
      _stage = _PuzzleStage.start;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (!widget.active) return;
    _timer?.cancel();
    final target = List<int>.of((SlidingPuzzle()..shuffle(_random)).history);
    _puzzle
      ..reset()
      ..history = target;
    setState(() {
      _moves = 0;
      _stage = _PuzzleStage.mixing;
    });
    if (_still) {
      for (final tile in target) {
        _puzzle.move(tile);
      }
      setState(() => _stage = _PuzzleStage.play);
      return;
    }
    var step = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 75), (timer) {
      if (!mounted) return;
      if (step >= target.length) {
        timer.cancel();
        setState(() => _stage = _PuzzleStage.play);
        return;
      }
      setState(() => _puzzle.move(target[step++]));
    });
  }

  void _tap(int tile) {
    if (_stage != _PuzzleStage.play || !_puzzle.move(tile)) return;
    setState(() => _moves++);
    if (_puzzle.solved) {
      setState(() => _stage = _PuzzleStage.done);
      unawaited(_saveBest(_moves));
    }
  }

  Future<void> _saveBest(int moves) async =>
      GameScores.keepBest(GameScores.puzzleKey, moves, lowerWins: true);

  Widget _picture(double size) => SvgPicture.asset(
    PuzzleGame.picture,
    width: size,
    height: size,
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );

  Widget _boardView() {
    final whole = _stage == _PuzzleStage.start || _stage == _PuzzleStage.done;
    final duration = _still ? Duration.zero : const Duration(milliseconds: 160);
    return Container(
      width: _board + 6,
      height: _board + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFDCE5EC),
        borderRadius: BorderRadius.circular(14),
        boxShadow: whole
            ? const [
                BoxShadow(
                  color: Color(0x24061B44),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: whole
            ? _picture(_board)
            : Stack(
                children: [
                  for (var k = 0; k < 8; k++)
                    AnimatedPositioned(
                      key: ValueKey('puzzle-slot-$k'),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      left: (_puzzle.pos[k] % 3) * _tile,
                      top: (_puzzle.pos[k] ~/ 3) * _tile,
                      width: _tile,
                      height: _tile,
                      child: _tileView(k),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _tileView(int k) {
    return Semantics(
      button: true,
      label: context.l10n.gamePuzzleTile('${k + 1}'),
      child: GestureDetector(
        key: ValueKey('puzzle-tile-$k'),
        onTap: () => _tap(k),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2E061B44),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                children: [
                  Positioned(
                    left: -(k % 3) * _tile - 1.5,
                    top: -(k ~/ 3) * _tile - 1.5,
                    child: _picture(_board),
                  ),
                  Positioned(
                    left: 5,
                    top: 5,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${k + 1}',
                        style: gameText(
                          11,
                          weight: FontWeight.w700,
                          color: AppColor.navy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _side() {
    final l = context.l10n;
    switch (_stage) {
      case _PuzzleStage.start:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l.gamePuzzleTitle,
              style: gameText(
                18,
                weight: FontWeight.w700,
                color: AppColor.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.gamePuzzleBody,
              style: gameText(13, color: const Color(0xFF5C656C), height: 1.35),
            ),
            const SizedBox(height: 12),
            GamePill(
              label: l.gameStart,
              small: true,
              onPressed: widget.active ? _start : null,
            ),
          ],
        );
      case _PuzzleStage.mixing:
      case _PuzzleStage.play:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l.gamePuzzleGoal,
              style: gameText(
                12,
                weight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 76,
              height: 76,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24061B44),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: _picture(76),
            ),
            const SizedBox(height: 14),
            Text(
              l.gamePuzzleMovesLabel,
              style: gameText(
                12,
                weight: FontWeight.w600,
                color: const Color(0xFF5C656C),
              ),
            ),
            Text(
              '$_moves',
              key: const ValueKey('puzzle-moves'),
              style: gameText(
                28,
                weight: FontWeight.w700,
                color: AppColor.navy,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _stage == _PuzzleStage.play ? _start : null,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(color: Color(0xFFE7EBEE)),
                foregroundColor: const Color(0xFF1D252C),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                l.gamePuzzleShuffle,
                style: gameText(12.5, weight: FontWeight.w600),
              ),
            ),
          ],
        );
      case _PuzzleStage.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFF3AA169),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.gamePuzzleDone,
              style: gameText(
                18,
                weight: FontWeight.w700,
                color: AppColor.navy,
              ),
            ),
            Text(
              l.gamePuzzleMoves('$_moves'),
              style: gameText(14, color: const Color(0xFF5C656C)),
            ),
            const SizedBox(height: 10),
            GamePill(label: l.gamePlayAgain, small: true, onPressed: _start),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameCard(
      color: const Color(0xFFF9FBFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        child: Row(
          children: [
            _boardView(),
            const SizedBox(width: 12),
            // Large text sizes scale the side column down, never overflow.
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(width: box.maxWidth, child: _side()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
