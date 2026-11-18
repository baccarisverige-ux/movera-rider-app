import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_category_gate.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-18 (saved-places design, step 9): the categories screen
/// opens in two parts on EVERY way in: its header slides down from above
/// the screen while the car sheet rises from the bottom; Back reverses it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  const screen = Size(390, 844);

  Future<void> frames(WidgetTester tester, int count, {int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: screen,
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: home),
      ),
    );
    await frames(tester, 8);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  double shiftOf(WidgetTester tester, String key) => tester
      .widget<Transform>(find.byKey(ValueKey(key)))
      .transform
      .getTranslation()
      .y;

  /// Waits in small steps for the categories route, so its first frames are
  /// seen.
  Future<void> waitForCategories(WidgetTester tester) async {
    final f = find.byType(SelectRide, skipOffstage: false);
    for (var i = 0; i < 2000 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    expect(f, findsOneWidget);
  }

  /// The split route, its first frames, the open state and Back reversed.
  Future<void> expectSplitOpenAndBack(WidgetTester tester) async {
    final route = ModalRoute.of(
      tester.element(find.byType(SelectRide, skipOffstage: false)),
    );
    expect(route, isA<CategoriesSplitTransition<dynamic>>());
    await tester.pump();
    final header0 = shiftOf(tester, 'categories-split-header');
    final sheet0 = shiftOf(tester, 'categories-split-sheet');
    final footer0 = shiftOf(tester, 'categories-split-footer');
    expect(header0, lessThan(-60), reason: 'header starts above the top');
    expect(sheet0, greaterThan(screen.height * 0.6), reason: 'sheet below');
    expect(footer0, greaterThan(screen.height * 0.6), reason: 'footer below');
    await tester.pump(const Duration(milliseconds: 120));
    expect(shiftOf(tester, 'categories-split-header'), greaterThan(header0));
    expect(shiftOf(tester, 'categories-split-sheet'), lessThan(sheet0));
    await frames(tester, 4);
    expect(shiftOf(tester, 'categories-split-header'), closeTo(0, 0.5));
    expect(shiftOf(tester, 'categories-split-sheet'), closeTo(0, 0.5));
    // Back: the same two parts in reverse.
    route!.navigator!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      shiftOf(tester, 'categories-split-header'),
      lessThan(-10),
      reason: 'header going back up',
    );
    expect(
      shiftOf(tester, 'categories-split-sheet'),
      greaterThan(50),
      reason: 'sheet going back down',
    );
    // Nothing (the address screen Home reopens on Back) covers the reverse.
    expect(
      find.byType(RoutePickerPage),
      findsNothing,
      reason: 'the reverse is seen, not hidden under the next screen',
    );
    await frames(tester, 6);
    expect(find.byType(SelectRide), findsNothing);
  }

  Future<void> searchTo(WidgetTester tester) async {
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField).at(0), 'Stockholm Central');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Arlanda');
    await tester.pump();
    final pick = find.textContaining(
      'Stockholm Arlanda Airport',
      findRichText: true,
    );
    await waitFor(tester, pick);
    await tester.tap(pick.first);
  }

  testWidgets('after the Where to search: two-part open, Back reverses', (
    tester,
  ) async {
    await pumpApp(tester, const Home());
    await tester.tap(find.text('Where to?'));
    await searchTo(tester);
    await waitForCategories(tester);
    await expectSplitOpenAndBack(tester);
    await tearDownApp(tester);
  });

  testWidgets('after Later (Senare): the same two-part open and Back', (
    tester,
  ) async {
    await pumpApp(tester, const Home());
    await tester.tap(find.text('Later'));
    await searchTo(tester);
    await waitFor(tester, find.byType(ScheduleDateTimeSelector));
    await tester.tap(find.text('Continue'));
    await waitForCategories(tester);
    await expectSplitOpenAndBack(tester);
    await tearDownApp(tester);
  });

  testWidgets('the scheduled gate (Plan your ride) uses the same split', (
    tester,
  ) async {
    final session = ScheduledRideSession()
      ..pickup = 'Stockholm Central'
      ..pickupLat = 59.3303
      ..pickupLng = 18.0586
      ..dropoff = 'Stockholm Arlanda Airport'
      ..scheduledAt = DateTime.now().add(const Duration(days: 1));
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  openScheduledCategorySelector(context, session: session),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await waitForCategories(tester);
    await expectSplitOpenAndBack(tester);
    // Reopen: plays again from the start.
    await tester.tap(find.text('open'));
    await waitForCategories(tester);
    await expectSplitOpenAndBack(tester);
    await tearDownApp(tester);
  });

  testWidgets('reduced motion: no movement', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => pushCategories<void>(
              context,
              SelectRide(
                pickupAddress: 'A',
                destinationAddress: 'B',
                pickupPosition: const LatLng(59.33, 18.06),
                destinationPosition: const LatLng(59.65, 17.92),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    final split = tester.widget<CategoriesSplit>(find.byType(CategoriesSplit));
    expect(split.animation.value, 1, reason: 'already in place, no movement');
    await tearDownApp(tester);
  });

  testWidgets('unwinding the ride stack to Home: categories go at once', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Text('home')),
    );
    unawaited(
      pushCategories<void>(
        nav.currentContext!,
        const ColoredBox(color: Colors.white, child: Text('categories')),
      ),
    );
    await frames(tester, 5);
    unawaited(
      nav.currentState!.push(
        RideStageTransition<void>(const ColoredBox(color: Colors.white)),
      ),
    );
    await frames(tester, 5);
    nav.currentState!.popUntil((r) => r.isFirst);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('categories'), findsNothing, reason: 'no flash');
    expect(find.text('home'), findsOneWidget);
  });

  test('guard: nothing in lib/ opens the categories screen without '
      'pushCategories', () {
    // Files that define the screen (and the return page that wraps it).
    const defining = {
      'lib/features/ride_selection/presentation/select_ride.dart',
      'lib/features/reservations/presentation/plan_return_ride.dart',
    };
    final opener = RegExp(
      r'\b(SelectRide(\.forReturnRide)?|PlanReturnRidePage)\(',
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (defining.contains(path)) continue;
      final src = file.readAsStringSync();
      for (final m in opener.allMatches(src)) {
        final lineStart = src.lastIndexOf('\n', m.start) + 1;
        if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) {
          continue; // a comment, not code
        }
        final before = src.substring(
          (m.start - 80).clamp(0, src.length),
          m.start,
        );
        // The page must be the direct argument of pushCategories(context, …).
        final ok = RegExp(
          r'pushCategories(<[^>]*>)?\(\s*context,\s*$',
        ).hasMatch(before);
        if (!ok) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('$path:$line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'open the categories screen only with pushCategories() '
          '(CategoriesSplitTransition), never MaterialPageRoute or '
          'RideStageTransition',
    );
  });
}
