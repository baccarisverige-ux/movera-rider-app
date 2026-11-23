import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/search_games.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/finding_driver/application/game_scores.dart';

TextStyle gameText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = const Color(0xFF1D252C),
  double? height,
}) => GoogleFonts.poppins(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

const Color _green = Color(0xFF3AA169);
const Color _muted = Color(0xFF5C656C);

/// One quiz question: its picture and its texts (the first answer is the
/// right one).
class QuizQuestion {
  const QuizQuestion(this.scene, this.text);

  /// `assets/games/quiz_<scene>.svg`
  final String scene;
  final ({String q, List<String> a, String fact}) Function(AppLocalizations)
  text;
}

/// Names and numbers are the same in every language, so they are not
/// translated texts.
///
/// The ten Stockholm questions (owner 2026-11-23; question 10 corrected:
/// the Nobel banquet is in City Hall, the prize is handed out at the
/// Concert Hall).
final List<QuizQuestion> stockholmQuiz = [
  QuizQuestion(
    'stadshuset',
    (l) => (
      q: l.gameQuizQ1,
      a: [l.gameQuizQ1A1, l.gameQuizQ1A2, l.gameQuizQ1A3],
      fact: l.gameQuizQ1Fact,
    ),
  ),
  QuizQuestion(
    'gamlastan',
    (l) => (
      q: l.gameQuizQ2,
      a: const ['Gamla stan', 'Södermalm', 'Vasastan'],
      fact: l.gameQuizQ2Fact,
    ),
  ),
  QuizQuestion(
    'vasa',
    (l) => (
      q: l.gameQuizQ3,
      a: const ['Vasa', 'Kronan', 'Götheborg'],
      fact: l.gameQuizQ3Fact,
    ),
  ),
  QuizQuestion(
    'globen',
    (l) => (
      q: l.gameQuizQ4,
      a: const ['Globen', 'Friends Arena', 'Tele2 Arena'],
      fact: l.gameQuizQ4Fact,
    ),
  ),
  QuizQuestion(
    'kaknas',
    (l) => (
      q: l.gameQuizQ5,
      a: [l.gameQuizQ5A1, l.gameQuizQ5A2, l.gameQuizQ5A3],
      fact: l.gameQuizQ5Fact,
    ),
  ),
  QuizQuestion(
    'islands',
    (l) =>
        (q: l.gameQuizQ6, a: const ['14', '7', '24'], fact: l.gameQuizQ6Fact),
  ),
  QuizQuestion(
    'metro',
    (l) => (
      q: l.gameQuizQ7,
      a: const ['1950', '1925', '1975'],
      fact: l.gameQuizQ7Fact,
    ),
  ),
  QuizQuestion(
    'malaren',
    (l) => (
      q: l.gameQuizQ8,
      a: const ['Mälaren', 'Vänern', 'Vättern'],
      fact: l.gameQuizQ8Fact,
    ),
  ),
  QuizQuestion(
    'library',
    (l) => (
      q: l.gameQuizQ9,
      a: const ['Observatorielunden', 'Humlegården', 'Kungsträdgården'],
      fact: l.gameQuizQ9Fact,
    ),
  ),
  QuizQuestion(
    'stadshuset',
    (l) => (
      q: l.gameQuizQ10,
      a: [l.gameQuizQ10A1, l.gameQuizQ10A2, l.gameQuizQ10A3],
      fact: l.gameQuizQ10Fact,
    ),
  ),
];

enum _QuizStage { start, play, end }

/// Q1 Stockholmsquiz: 5 of the 10 questions per round, a picture each;
/// right = green with the fact, wrong = a gentle shake (none with reduce
/// motion); "N av 5 rätt!" and Spela igen. Best score on this phone only.
class QuizGame extends StatefulWidget {
  const QuizGame({super.key, this.active = true, this.random});

  static const String bestKey = GameScores.quizKey;
  static const int perRound = 5;

  final bool active;
  final Random? random;

  @override
  State<QuizGame> createState() => _QuizGameState();
}

class _QuizGameState extends State<QuizGame>
    with SingleTickerProviderStateMixin {
  late final Random _random = widget.random ?? Random();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  _QuizStage _stage = _QuizStage.start;
  List<QuizQuestion> _round = const [];
  List<int> _order = const [];
  int _index = 0;
  final List<bool> _results = [];
  int? _picked;
  Timer? _next;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didUpdateWidget(QuizGame old) {
    super.didUpdateWidget(old);
    if (!widget.active && _stage != _QuizStage.start) _stop();
  }

  @override
  void dispose() {
    _next?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _stop() {
    _next?.cancel();
    _stage = _QuizStage.start;
    _picked = null;
  }

  void _start() {
    if (!widget.active) return;
    final all = List.of(stockholmQuiz)..shuffle(_random);
    setState(() {
      _round = all.take(QuizGame.perRound).toList();
      _index = 0;
      _results.clear();
      _stage = _QuizStage.play;
      _showQuestion();
    });
  }

  void _showQuestion() {
    _picked = null;
    _order = [0, 1, 2]..shuffle(_random);
  }

  void _pick(int answer) {
    if (_picked != null) return;
    final right = answer == 0;
    setState(() {
      _picked = answer;
      _results.add(right);
    });
    if (!right && !_still) _shake.forward(from: 0);
    _next = Timer(Duration(milliseconds: right ? 2400 : 3000), _advance);
  }

  void _advance() {
    _next?.cancel();
    if (!mounted || _picked == null) return;
    setState(() {
      _index++;
      if (_index >= _round.length) {
        _stage = _QuizStage.end;
        unawaited(_saveBest(_results.where((r) => r).length));
      } else {
        _showQuestion();
      }
    });
  }

  Future<void> _saveBest(int score) async =>
      GameScores.keepBest(GameScores.quizKey, score);

  @override
  Widget build(BuildContext context) {
    return GameCard(
      child: switch (_stage) {
        _QuizStage.start => _startView(context),
        _QuizStage.play => _playView(context),
        _QuizStage.end => _endView(context),
      },
    );
  }

  Widget _hero(double height) => SizedBox(
    height: height,
    width: double.infinity,
    child: SvgPicture.asset(
      'assets/games/quiz_hero.svg',
      fit: BoxFit.cover,
      alignment: Alignment.bottomCenter,
      excludeFromSemantics: true,
    ),
  );

  Widget _startView(BuildContext context) {
    final l = context.l10n;
    return Column(
      children: [
        _hero(150),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 18),
                  Text(
                    l.gameQuizTitle,
                    style: gameText(
                      20,
                      weight: FontWeight.w700,
                      color: AppColor.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l.gameQuizBody,
                      textAlign: TextAlign.center,
                      style: gameText(14, color: _muted),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GamePill(
                    label: l.gameStart,
                    onPressed: widget.active ? _start : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dots({double size = 9, bool onPill = false}) {
    final children = <Widget>[
      for (var k = 0; k < QuizGame.perRound; k++)
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: k < _results.length
                ? (_results[k] ? _green : Colors.white)
                : (k == _index && onPill
                      ? _green.withValues(alpha: 0.0)
                      : const Color(0xFFD3D8DD)),
            border: k < _results.length && !_results[k]
                ? Border.all(color: const Color(0xFF9AA3A9), width: 1.5)
                : (k == _index && onPill
                      ? Border.all(color: const Color(0xFF9AA3A9), width: 1.5)
                      : null),
          ),
        ),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _playView(BuildContext context) {
    final l = context.l10n;
    final question = _round[_index];
    final text = question.text(l);
    final picked = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: picked != null ? _advance : null,
          child: SizedBox(
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SvgPicture.asset(
                  'assets/games/quiz_${question.scene}.svg',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _dots(size: 8, onPill: true),
                  ),
                ),
                if (picked != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00061B44), Color(0xE6142E57)],
                        ),
                      ),
                      child: Text.rich(
                        key: const ValueKey('quiz-fact'),
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${picked == 0 ? l.gameRight : l.gameNotQuite} ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: text.fact),
                          ],
                        ),
                        style: gameText(12.5, color: Colors.white, height: 1.3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Text(
            text.q,
            key: const ValueKey('quiz-question'),
            maxLines: 2,
            style: gameText(15, weight: FontWeight.w600, height: 1.3),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = _shake.isAnimating
                  ? sin(t * pi * 6) * 6 * (1 - t)
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 312,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final answer in _order)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Transform.translate(
                              offset: Offset(
                                picked != null &&
                                        answer == picked &&
                                        answer != 0
                                    ? dx
                                    : 0,
                                0,
                              ),
                              child: _answer(text.a[answer], answer, picked),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _answer(String label, int answer, int? picked) {
    final right = answer == 0;
    final done = picked != null;
    final green = done && right;
    final wrongPick = done && answer == picked && !right;
    final dim = done && !green && !wrongPick;
    return Material(
      key: ValueKey(right ? 'quiz-answer-ok' : 'quiz-answer-wrong'),
      color: green ? const Color(0xFFE6F4EA) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: green
              ? const Color(0xFF8ED1A4)
              : wrongPick
              ? const Color(0xFFE8B4B0)
              : const Color(0xFFE7EBEE),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: done ? null : () => _pick(answer),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: gameText(
                      14,
                      weight: FontWeight.w500,
                      color: green
                          ? const Color(0xFF1E6B3E)
                          : dim
                          ? const Color(0xFFA9B0B6)
                          : const Color(0xFF1D252C),
                    ),
                  ),
                ),
                if (green)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _endView(BuildContext context) {
    final l = context.l10n;
    final right = _results.where((r) => r).length;
    final message = right == QuizGame.perRound
        ? l.gameQuizAllRight
        : right >= 3
        ? l.gameQuizGood
        : l.gameQuizTryAgain;
    return Column(
      children: [
        _hero(92),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 22),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final ok in _results)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 3.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ok ? _green : Colors.white,
                            border: ok
                                ? null
                                : Border.all(
                                    color: const Color(0xFF9AA3A9),
                                    width: 1.5,
                                  ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.gameQuizScore('$right', '${QuizGame.perRound}'),
                    style: gameText(
                      26,
                      weight: FontWeight.w700,
                      color: AppColor.navy,
                    ),
                  ),
                  Text(message, style: gameText(14, color: _muted)),
                  const SizedBox(height: 10),
                  GamePill(label: l.gamePlayAgain, onPressed: _start),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
