import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/puzzle_game.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/quiz_game.dart';

export 'package:movera_rider/features/finding_driver/presentation/games/puzzle_game.dart';
export 'package:movera_rider/features/finding_driver/presentation/games/quiz_game.dart';

/// Owner 2026-11-23 (approved, PROPOSAL-game-quiz-puzzle): the two games of
/// the pulled-up searching sheet side by side — a horizontal row of 340 px
/// cards, the next one peeking 24 px, snapping per card, with page dots.
/// Silent, local only; [active] false (a driver accepted) stops them.
class SearchGamesRow extends StatefulWidget {
  const SearchGamesRow({super.key, this.active = true});

  final bool active;

  static const double cardWidth = 340;
  static const double cardHeight = 300;
  static const double edge = 16;
  static const double gap = 10;

  @override
  State<SearchGamesRow> createState() => _SearchGamesRowState();
}

class _SearchGamesRowState extends State<SearchGamesRow> {
  PageController? _pages;
  double _forWidth = 0;
  int _page = 0;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  PageController _controllerFor(double width) {
    if (_pages == null || _forWidth != width) {
      _pages?.dispose();
      _forWidth = width;
      _pages = PageController(
        initialPage: _page,
        viewportFraction:
            ((SearchGamesRow.cardWidth + SearchGamesRow.gap) / width).clamp(
              0.1,
              1.0,
            ),
      );
    }
    return _pages!;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final cards = <Widget>[
      QuizGame(active: widget.active),
      PuzzleGame(active: widget.active),
    ];
    return Column(
      key: const ValueKey('search-games-row'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: SearchGamesRow.cardHeight + 16,
          // The row runs from screen edge to screen edge, out of the sheet's
          // side padding, so the next card can peek.
          child: OverflowBox(
            maxWidth: screen,
            minWidth: screen,
            child: PageView(
              controller: _controllerFor(screen),
              padEnds: false,
              clipBehavior: Clip.none,
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                for (final card in cards)
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: SearchGamesRow.cardWidth + SearchGamesRow.edge,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: SearchGamesRow.edge,
                        bottom: 16,
                      ),
                      child: SizedBox(
                        width: SearchGamesRow.cardWidth,
                        height: SearchGamesRow.cardHeight,
                        child: card,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Row(
          key: const ValueKey('search-games-dots'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++)
              AnimatedContainer(
                duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page ? AppColor.navy : const Color(0xFFD3D8DD),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The shell of a game card: white, 24 px corners, a hair border and a
/// soft shadow.
class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.child, this.color = Colors.white});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EBEE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14162C36),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The black pill button of the game cards.
class GamePill extends StatelessWidget {
  const GamePill({
    super.key,
    required this.label,
    required this.onPressed,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF111614),
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        minimumSize: Size(small ? 0 : 100, small ? 40 : 44),
        padding: EdgeInsets.symmetric(horizontal: small ? 18 : 28),
        elevation: 4,
        shadowColor: const Color(0x33061B44),
      ),
      child: Text(
        label,
        style: gameText(
          small ? 15 : 16,
          weight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
