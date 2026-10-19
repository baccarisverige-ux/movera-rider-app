import 'package:flutter/material.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scene.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';

/// Shared layout of every sign-in step: progress, wordmark, a headline whose
/// last words are green, the illustration, and a white card holding the form.
///
/// The whole page scrolls when space runs short (small phones, landscape, or
/// the keyboard up), so the card's controls stay reachable.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.step,
    this.totalSteps = 3,
    this.onBack,
    required this.headline,
    required this.headlineAccent,
    this.headlineSize = 40,
    this.lede,
    this.hero,
    this.sceneProgress,
    this.showCar = true,
    required this.card,
  });

  final int step;
  final int totalSteps;

  /// Null hides the back button (the first screen of the flow).
  final VoidCallback? onBack;

  /// Headline text in ink, followed by [headlineAccent] in green.
  final String headline;
  final String headlineAccent;
  final double headlineSize;
  final Widget? lede;
  final Widget? hero;
  final Animation<double>? sceneProgress;
  final bool showCar;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AuthColors.ground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 24, 0),
                    child: _TopBar(
                      step: step,
                      totalSteps: totalSteps,
                      onBack: onBack,
                    ),
                  ),
                  if (hero != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: hero!,
                    )
                  else ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 10, 24, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MoveraWordmark(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Semantics(
                        header: true,
                        child: Text.rich(
                          TextSpan(
                            text: headline,
                            children: [
                              TextSpan(
                                text: headlineAccent,
                                style: const TextStyle(color: AuthColors.green),
                              ),
                            ],
                          ),
                          style: AuthText.headline(headlineSize),
                        ),
                      ),
                    ),
                    if (lede != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 40, 0),
                        child: DefaultTextStyle(
                          style: AuthText.lede(),
                          child: lede!,
                        ),
                      ),
                  ],
                  // Takes whatever height the card leaves, never less than
                  // 96: on short screens (landscape, keyboard up) the page
                  // scrolls instead of squeezing the form.
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 96),
                      child: AuthScene(showCar: showCar, storyProgress: sceneProgress),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFFE4EAE5)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12281E14),
                          blurRadius: 30,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        card,
                        if (AppEnv.current.authPreview) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AuthColors.deepGreen,
                            ),
                            onPressed: () => enterMoveraApp(context),
                            child: const Text('Skip for now (demo)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.totalSteps,
    required this.onBack,
  });

  final int step;
  final int totalSteps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // UI-11: 48 px, so Back is a full-size target (was 40).
          SizedBox(
            width: 48,
            child: onBack == null
                ? null
                : Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    child: IconButton(
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: AuthColors.ink,
                        size: 26,
                      ),
                      onPressed: onBack,
                    ),
                  ),
          ),
          Expanded(
            child: Semantics(
              label: 'Step $step of $totalSteps',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= totalSteps; i++) ...[
                    if (i > 1) const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == step ? 32 : 20,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == step
                            ? AuthColors.deepGreen
                            : i < step
                                ? AuthColors.stepDone
                                : AuthColors.stepIdle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '$step / $totalSteps',
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                // UI-6: was 0xFF738078 (4.13:1 on white).
                color: const Color(0xFF647069),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
