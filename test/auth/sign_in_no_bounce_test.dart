import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner 2026-11-22 (iPhone Safari): dragging the sign-in page up showed an
// empty grey-green band under the white card ("When I scroll up or down must
// be fix"). On an iPhone Flutter web runs as TargetPlatform.iOS, whose default
// scroll physics bounce past the edge. The sign-in page must stay put; it may
// only scroll when its content is taller than the screen (keyboard up).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAuth(WidgetTester tester, double cardHeight) async {
    tester.view.physicalSize = const Size(390, 664);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AuthScaffold(
          step: 1,
          headline: 'Hello',
          headlineAccent: ' there',
          card: SizedBox(height: cardHeight),
        ),
      ),
    );
    await tester.pump();
  }

  for (final tall in [false, true]) {
    testWidgets('iPhone: no empty band under the card on a drag '
        '(${tall ? 'taller' : 'shorter'} than the screen)', (tester) async {
      await pumpAuth(tester, tall ? 700 : 120);
      final card = find.byKey(const ValueKey('auth-card'));
      final gesture = await tester.startGesture(const Offset(300, 400));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      expect(
        tester.getRect(card).bottom,
        greaterThanOrEqualTo(664),
        reason: 'dragging up must not lift the card off the bottom edge',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      final pos = tester.state<ScrollableState>(find.byType(Scrollable));
      if (tall) {
        // Still scrolls when the form is taller than the screen.
        expect(pos.position.pixels, greaterThan(0));
      }
      expect(tester.getRect(card).bottom, greaterThanOrEqualTo(664));
      final down = await tester.startGesture(const Offset(300, 200));
      for (var i = 0; i < 30; i++) {
        await down.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(
        scroll.position.pixels,
        greaterThanOrEqualTo(0),
        reason: 'dragging down must not pull the page below its top',
      );
      await down.up();
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
