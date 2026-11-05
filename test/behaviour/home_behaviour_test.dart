import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/history/presentation/ride_history_result.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_ticket.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B16 (2026-11-04): behaviour tests for Home that replace source-reading
/// guards (archived in Rules/archive/old-tests/movera-rider-app/). They pump
/// the real Home on the in-process demo transport.

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) =>
          MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
    ),
  );
  await _settle(tester);
  expect(find.byType(Home), findsOneWidget);
}

Future<void> _settle(WidgetTester tester, [int ticks = 12]) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
  debugDefaultTargetPlatformOverride = null;
}

const _serverPromotion = RiderPromotion(
  id: 'promo_admin_b16',
  title: 'Admin promotion B16',
  percentOff: 15,
  ridesLeft: 2,
  ridesTotal: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  testWidgets('Home asks for no compass or motion permission', (tester) async {
    await _pumpHome(tester);
    await _settle(tester, 30);
    for (final text in [
      'Enable compass',
      'Motion permission',
      'Device orientation',
    ]) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    await _end(tester);
  });

  testWidgets('Home draws no trip polyline on its map', (tester) async {
    await _pumpHome(tester);
    await _settle(tester, 30);
    final maps = tester.widgetList<CustomGoogleMap>(
      find.byType(CustomGoogleMap, skipOffstage: false),
    );
    expect(maps, isNotEmpty);
    for (final map in maps) {
      expect(map.polylines ?? const {}, isEmpty);
    }
    await _end(tester);
  });

  testWidgets('Home shows only the promotion the server sent, with no close '
      'button', (tester) async {
    await _pumpHome(tester);
    // What the server says replaces what Home showed.
    AppScope.instance.promotion.value = _serverPromotion;
    await _settle(tester, 20);
    expect(find.byType(PromotionTicket), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PromotionTicket),
        matching: find.textContaining('Admin promotion B16'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PromotionTicket),
        matching: find.byIcon(Icons.close),
      ),
      findsNothing,
    );

    // No promotion from the server: Home invents none.
    AppScope.instance.promotion.value = null;
    await _settle(tester, 20);
    expect(find.byType(PromotionTicket), findsNothing);
    expect(find.textContaining(RegExp(r'\d+% off your next')), findsNothing);
    await _end(tester);
  });

  testWidgets('D-026: Ride History "Book a ride" from the menu opens Where to '
      'over Home', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Menu').first);
    await _settle(tester, 10);
    expect(find.byType(RiderMenuPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ride History'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Ride History').last);
    await _settle(tester, 10);
    moveraNavigatorKey.currentState!.pop(rideHistoryStartBookingResult);
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RiderMenuPage), findsNothing);
    expect(find.byType(Home), findsOneWidget);
    // Where to: the pickup and destination fields.
    expect(find.byType(TextField), findsNWidgets(2));
    await _end(tester);
  });

  testWidgets('Home keeps the reservation chrono, its Account page and no '
      'other brand\'s account wording', (tester) async {
    await _pumpHome(tester);
    expect(find.byType(HomeReservationChrono), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Account').first);
    await _settle(tester, 10);
    expect(find.byType(AccountHomePage), findsOneWidget);
    expect(find.textContaining('Uber account'), findsNothing);
    await _end(tester);
  });

  testWidgets('Where to "Set pickup on map" opens Confirm pickup', (
    tester,
  ) async {
    await _pumpHome(tester);
    await tester.tap(find.text('Where to?'));
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 450));
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump(const Duration(milliseconds: 200));
    final onMap = find.bySemanticsLabel('Set pickup on map');
    expect(onMap, findsWidgets);
    await tester.tap(onMap.first);
    for (
      var i = 0;
      i < 40 && find.byType(ConfirmPickupSpot).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ConfirmPickupSpot), findsOneWidget);
    await _end(tester);
    // The pickup lookup's own timeout outlives the tree.
    await tester.pump(const Duration(seconds: 30));
  });
}
