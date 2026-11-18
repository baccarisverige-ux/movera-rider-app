import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-17 ("Yes, like the example"): Where to? opens with one
/// slide up out of the bar, the cursor and keyboard already in Destination,
/// up to ten recents, and X slides back into the bar with Home collapsed.
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

  Future<void> frames(WidgetTester tester, int count, {int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await frames(tester, 8);
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  /// Home's PopScope blocks the pop while its sheet is open.
  bool homeSheetOpen(WidgetTester tester) => !tester
      .widget<PopScope>(
        find
            .descendant(
              of: find.byType(Home, skipOffstage: false),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopScope,
                skipOffstage: false,
              ),
            )
            .first,
      )
      .canPop;

  Iterable<T> above<T extends Widget>(WidgetTester tester) =>
      tester.widgetList<T>(
        find.ancestor(
          of: find.byType(RoutePickerPage, skipOffstage: false),
          matching: find.byType(T, skipOffstage: false),
        ),
      );

  double headerTop(WidgetTester tester) =>
      tester.getTopLeft(find.text('Your route').first).dy;
  double listTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('where-to-split-list'))).dy;

  testWidgets('owner 2026-11-17 two parts: the header slides down from above '
      'the screen top while the list rises out of the bar; X reverses it', (
    tester,
  ) async {
    await pumpHome(tester);
    final bar = tester.getTopLeft(find.text('Where to?')).dy;
    await tester.tap(find.text('Where to?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(RoutePickerPage, skipOffstage: false), findsOneWidget);
    expect(homeSheetOpen(tester), isFalse, reason: 'Home sheet unchanged');
    // The route itself does not slide as one block.
    expect(
      above<SlideTransition>(tester).where((s) => s.position.value.dy != 0),
      isEmpty,
    );
    expect(headerTop(tester), lessThan(0), reason: 'header above the top');
    expect(listTop(tester), greaterThan(bar - 120), reason: 'list at the bar');
    await tester.pump(const Duration(milliseconds: 120));
    final midHeader = headerTop(tester);
    expect(midHeader, greaterThan(-60));
    await frames(tester, 4);
    final openHeader = headerTop(tester);
    final openList = listTop(tester);
    expect(openHeader, greaterThan(0));
    expect(openList, lessThan(260), reason: 'list under the header');
    // Close: header back up off the top, list back down into the bar.
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(headerTop(tester), lessThan(openHeader));
    expect(listTop(tester), greaterThan(openList + 100));
    await tester.pump(const Duration(milliseconds: 140));
    expect(headerTop(tester), lessThan(0), reason: 'header gone up');
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('where-to-split-list')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacity.opacity, lessThan(1), reason: 'list fades into the bar');
    await frames(tester, 4);
    expect(find.byType(RoutePickerPage), findsNothing);
    expect(homeSheetOpen(tester), isFalse);
    await tearDownHome(tester);
  });

  testWidgets('X slides back into the bar and Home stays collapsed', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Where to?'));
    await frames(tester, 8);
    expect(find.byType(RoutePickerPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    for (final fade in above<FadeTransition>(tester)) {
      expect(fade.opacity.value, 1.0, reason: 'no fade out');
    }
    await frames(tester, 8);
    expect(find.byType(RoutePickerPage), findsNothing);
    expect(homeSheetOpen(tester), isFalse, reason: 'back at the bar');
    await tearDownHome(tester);
  });

  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(WhereToCard)).dy;

  testWidgets('from an expanded sheet: same slide, X returns it expanded', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    expect(homeSheetOpen(tester), isTrue);
    final before = sheetTop(tester);
    await tester.tap(find.text('Where to?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(RoutePickerPage, skipOffstage: false), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    for (final fade in above<FadeTransition>(tester)) {
      expect(fade.opacity.value, 1.0, reason: 'no fade in');
    }
    await frames(tester, 8);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await frames(tester, 12);
    expect(find.byType(RoutePickerPage), findsNothing);
    expect(homeSheetOpen(tester), isTrue, reason: 'back expanded');
    expect(sheetTop(tester), closeTo(before, 2));
    await tearDownHome(tester);
  });

  testWidgets('from a half-open sheet: X returns it to the same middle snap', (
    tester,
  ) async {
    await pumpHome(tester);
    final low = sheetTop(tester);
    // A short drag up from the bar settles on the middle snap.
    await tester.drag(find.byType(WhereToCard), const Offset(0, -60));
    await frames(tester, 10);
    final middle = sheetTop(tester);
    expect(homeSheetOpen(tester), isFalse, reason: 'not fully open');
    expect(middle, lessThan(low - 2), reason: 'not collapsed');
    await tester.tap(find.text('Where to?'));
    await frames(tester, 8);
    expect(find.byType(RoutePickerPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await frames(tester, 12);
    expect(find.byType(RoutePickerPage), findsNothing);
    expect(sheetTop(tester), closeTo(middle, 2));
    await tearDownHome(tester);
  });

  testWidgets('from a collapsed sheet: X returns it to the same spot', (
    tester,
  ) async {
    await pumpHome(tester);
    final before = sheetTop(tester);
    await tester.tap(find.text('Where to?'));
    await frames(tester, 8);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await frames(tester, 12);
    expect(homeSheetOpen(tester), isFalse);
    expect(sheetTop(tester), closeTo(before, 2));
    await tearDownHome(tester);
  });

  testWidgets('dragging the Home sheet works as before: up expands, down '
      'returns to the bar, no search screen', (tester) async {
    await pumpHome(tester);
    expect(homeSheetOpen(tester), isFalse);
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    expect(homeSheetOpen(tester), isTrue, reason: 'drag up expands');
    expect(find.byType(RoutePickerPage), findsNothing);
    await tester.drag(find.byType(WhereToCard), const Offset(0, 600));
    await frames(tester, 10);
    expect(homeSheetOpen(tester), isFalse, reason: 'drag down collapses');
    expect(find.byType(RoutePickerPage), findsNothing);
    await tearDownHome(tester);
  });

  Widget picker({List<String> recent = const []}) => MaterialApp(
    home: RoutePickerPage(
      pickupAddress: 'Sergels torg 1, Stockholm',
      destinationAddress: '',
      stops: const [],
      stopsSupported: true,
      initialField: 'destination',
      capture: EarlyInputCapture(),
      here: const GeoPoint(59.3326, 18.0649),
      homeAddress: null,
      workAddress: null,
      recent: recent,
      onPickOnMap: ({required pickup, required address}) async => null,
      onFinish: (_) async => null,
    ),
  );

  testWidgets('the cursor is in Destination on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(picker());
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('route-picker-field-destination')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('up to ten recents are listed, not three', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      picker(
        recent: [for (var i = 1; i <= 12; i++) 'Gata $i, 111 2$i Stockholm'],
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 10; i++) {
      expect(find.text('Gata $i'), findsOneWidget, reason: 'recent $i');
    }
    expect(find.text('Gata 11'), findsNothing);
  });
}
