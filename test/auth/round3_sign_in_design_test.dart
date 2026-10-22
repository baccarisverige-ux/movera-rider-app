import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scene.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/balloon_brand_intro.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner round 3: the "ink and green" sign-in design.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets('the white card is square and runs edge to edge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        const AuthScaffold(
          step: 1,
          headline: 'Hello',
          headlineAccent: ' there',
          card: SizedBox(height: 120),
        ),
      ),
    );
    await tester.pump();
    final card = tester.getRect(find.byKey(const ValueKey('auth-card')));
    expect(card.left, 0);
    expect(card.right, 390);
    expect(card.bottom, 844);
    final box = tester.widget<Container>(
      find.byKey(const ValueKey('auth-card')),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.borderRadius, isNull, reason: 'no rounded corners');
    expect(decoration.border, isNull);
    // Raised over the scene: the shadow is cast upward.
    expect(decoration.boxShadow!.first.offset.dy, lessThan(0));
    // The step bar's current step is ink, not green.
    final bars = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final current = bars.firstWhere(
      (b) => (b.decoration! as BoxDecoration).color == AuthColors.ink,
    );
    expect(current, isNotNull);
  });

  testWidgets('the primary button is black, and faded black when off', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Column(
            children: [
              AuthPrimaryButton(label: 'On', onPressed: () {}),
              const AuthPrimaryButton(label: 'Off', onPressed: null),
            ],
          ),
        ),
      ),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .toList();
    final on = boxes
        .map((b) => b.decoration as BoxDecoration)
        .firstWhere((d) => d.gradient != null);
    expect(
      (on.gradient! as LinearGradient).colors.last,
      const Color(0xFF050506),
    );
    final off = boxes
        .map((b) => b.decoration as BoxDecoration)
        .firstWhere(
          (d) => d.gradient == null && d.color == AuthColors.disabled,
        );
    expect(off.color, const Color(0xFFF0F0F1));
    expect(AuthColors.disabledText, const Color(0xFFA6A7A9));
  });

  testWidgets('inputs are underlined, ink while focused', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AuthTextField(
            controller: controller,
            focusNode: focus,
            hint: 'First name',
          ),
        ),
      ),
    );
    BoxDecoration shell() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;
    expect(shell().borderRadius, isNull);
    expect(shell().color, isNull);
    expect(shell().border!.bottom.color, AuthColors.underline);
    expect(shell().border!.top, BorderSide.none);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(shell().border!.bottom.color, AuthColors.ink);
  });

  testWidgets('the phone row is three underlined parts: flag, code, number', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: AuthPhoneField(
            controller: controller,
            focusNode: focus,
            onCountryChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('auth-phone-country')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-phone-dial')), findsOneWidget);
    expect(find.text('+46'), findsOneWidget);
    expect(find.text('🇸🇪'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    final flag = tester.getRect(
      find.byKey(const ValueKey('auth-phone-country')),
    );
    final dial = tester.getRect(find.byKey(const ValueKey('auth-phone-dial')));
    final number = tester.getRect(find.byType(TextField));
    expect(flag.right, lessThan(dial.left));
    expect(dial.right, lessThan(number.left));
  });

  testWidgets('the balloon flies in one piece and lands as the pin', (
    tester,
  ) async {
    final story = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 5),
    );
    addTearDown(story.dispose);
    final sceneKey = GlobalKey();
    final wordmarkKey = GlobalKey();
    await tester.pumpWidget(
      app(
        AuthScaffold(
          step: 1,
          headline: '',
          headlineAccent: '',
          hero: BalloonBrandIntro(progress: story, wordmarkKey: wordmarkKey),
          sceneProgress: story,
          sceneKey: sceneKey,
          overlay: BalloonFlight(
            progress: story,
            sceneKey: sceneKey,
            wordmarkKey: wordmarkKey,
          ),
          card: const SizedBox(height: 100),
        ),
      ),
    );
    final flight = find.byType(BalloonFlight);
    CustomPaint? painted() {
      final paints = find.descendant(
        of: flight,
        matching: find.byType(CustomPaint),
      );
      return paints.evaluate().isEmpty
          ? null
          : tester.widget<CustomPaint>(paints);
    }

    double dotScale() => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byKey(wordmarkKey),
            matching: find.byKey(const ValueKey('movera-dot')),
          ),
        )
        .scale;

    // In the hand: the scene draws it; the wordmark already reads "Movera"
    // with its pin, only the dot waits for the balloon.
    story.value = 0.2;
    await tester.pump();
    expect(painted(), isNull);
    expect(dotScale(), 0);

    // Released: the flight layer draws it, still full size, on its arc.
    story.value = 0.5;
    await tester.pump();
    expect(painted(), isNotNull);
    expect(dotScale(), 0);
    expect(BalloonFlight.travel(0.5), inExclusiveRange(0, 1));
    expect(BalloonFlight.shrink(0.5), 0, reason: 'not shrinking yet');

    // Near the end it shrinks towards the dot, still one layer.
    story.value = 0.82;
    await tester.pump();
    expect(painted(), isNotNull);
    expect(BalloonFlight.shrink(0.82), inExclusiveRange(0, 1));
    expect(dotScale(), 0);

    // Landed: the flight stops and the wordmark's dot pops in.
    story.value = BalloonFlight.landAt;
    await tester.pump();
    expect(painted(), isNull);
    expect(dotScale(), 1);
    expect(BalloonFlight.travel(1), 1);
    expect(BalloonFlight.shrink(1), 1);
    await tester.pumpAndSettle();

    // The arc leaves the hand's position and ends on the dot's centre.
    final scene = sceneKey.currentContext!.findRenderObject()! as RenderBox;
    final start = AuthScene.balloonCentre(scene.size);
    expect(start.dx, closeTo(304 * scene.size.width / 390, 0.01));
    expect(start.dy, lessThan(scene.size.height));
    const from = Offset(300, 500);
    const to = Offset(120, 60);
    expect(BalloonFlight.along(from, to, 0), from);
    expect(BalloonFlight.along(from, to, 1), to);
    final mid = BalloonFlight.along(from, to, 0.5);
    expect(mid.dy, lessThan((from.dy + to.dy) / 2), reason: 'rises first');
  });

  testWidgets('reduce motion: no flight, the pin is simply there', (
    tester,
  ) async {
    final story = AnimationController(vsync: const TestVSync());
    addTearDown(story.dispose);
    final wordmarkKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: BalloonBrandIntro(progress: story, wordmarkKey: wordmarkKey),
        ),
      ),
    );
    final dot = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(wordmarkKey),
        matching: find.byKey(const ValueKey('movera-dot')),
      ),
    );
    expect(dot.scale, 1);
    expect(find.byType(MoveraWordmark), findsOneWidget);
  });
}
