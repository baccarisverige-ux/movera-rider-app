import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B9 "Fast app start" (owner 2026-11-04): Help (Support), Personal info,
/// Security and Privacy load on first open. A rider who taps them in the
/// real menu still gets the screen (after the short first-open spinner).
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The parts download for real outside the fake clock (as on a phone).
    await loadDeferredScreens();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder screenNamed(String name) =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

  Future<void> openMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => RiderMenuPage.open(context),
                  child: const Text('Home body'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home body'));
    await tester.pumpAndSettle();
  }

  final cases = [
    ('Support', 'SupportHome'),
    ('Personal info', 'PersonalInfoPage'),
    ('Security', 'SecurityPage'),
    ('Privacy', 'PrivacyPage'),
  ];
  for (final (label, screen) in cases) {
    testWidgets('menu "$label" opens $screen', (tester) async {
      await openMenu(tester);
      final item = find.text(label);
      await tester.scrollUntilVisible(
        item,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(item.first);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(screenNamed(screen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('deferred-screen-loading')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
