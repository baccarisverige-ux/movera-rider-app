import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/liquid_glass_nav.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_bottom_nav_item.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-02: "When open sheet the glass disappear!" and "dont make
/// green color! Keep all black". With the Home sheet pulled fully up the
/// selected tab keeps the same glass bubble, inside the bar and the screen,
/// and its icon and label stay black.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  final lens = find.byKey(const ValueKey('liquid-glass-lens'));
  final surface = find.byKey(const ValueKey('home-sheet-surface'));
  const ink = Color(0xFF1D252C);

  Future<void> expectGlass(WidgetTester tester, {required bool open}) async {
    expect(lens, findsOneWidget);
    final opacity = tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: lens, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacity, 1, reason: 'the lens is painted');
    final rect = tester.getRect(lens);
    expect(rect.width, greaterThan(40));
    expect(rect.height, greaterThan(40));
    // On screen, not hanging past the bottom.
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(844));
    // Within the bar row, and nothing between it and the screen clips it.
    final row = tester.getRect(find.byType(LiquidGlassNavRow));
    expect(rect.bottom, lessThanOrEqualTo(row.bottom + 2.01));
    RenderObject? r = tester.renderObject(lens).parent;
    while (r != null) {
      if (r is RenderClipRect || r is RenderClipRRect || r is RenderClipPath) {
        final box = r as RenderBox;
        final clip = box.localToGlobal(Offset.zero) & box.size;
        expect(
          clip.intersect(rect),
          rect,
          reason: '${r.runtimeType} cuts the lens',
        );
      }
      r = r.parent;
    }
    // Same glass as with the sheet down.
    final glass = tester.widget(lens) as dynamic;
    expect(glass.strength, 0);
    // The selected tab stays black.
    final item = tester.widget<PremiumBottomNavItem>(
      find.ancestor(
        of: find.text('Home').last,
        matching: find.byType(PremiumBottomNavItem),
      ),
    );
    expect(item.active, isTrue);
    final label = tester.widget<Text>(
      find.descendant(of: find.byWidget(item), matching: find.text('Home')),
    );
    expect(
      label.style?.color ??
          DefaultTextStyle.of(
            tester.element(find.text('Home').last),
          ).style.color,
      ink,
      reason: open ? 'not teal with the sheet open' : 'black with it down',
    );
  }

  for (final inset in [0.0, 34.0]) {
    testWidgets('the glass stays on the selected tab with the sheet open '
        '(bottom inset $inset)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(
          MoveraScreenUtilInit(
            builder: (_, __) => MaterialApp(
              navigatorKey: moveraNavigatorKey,
              home: const Home(),
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(kGlassAlways, isTrue);
        final downTop = tester.getRect(surface).top;
        expect(downTop, greaterThan(400), reason: 'sheet starts down');
        await expectGlass(tester, open: false);

        // Pull the sheet from its handle to the top.
        final handle = tester.getRect(surface).topCenter + const Offset(0, 20);
        await tester.timedDragFrom(
          handle,
          Offset(0, -handle.dy),
          const Duration(milliseconds: 500),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.getRect(surface).top,
          lessThan(60),
          reason: 'the sheet really is fully open',
        );
        await expectGlass(tester, open: true);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
