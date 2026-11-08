import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/history/presentation/ride_history_result.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B16 (2026-11-04): behaviour tests that replace the source-reading menu
/// guards (archived in Rules/archive/old-tests/movera-rider-app/). They run
/// the real menu and Account pages instead of reading their source.

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: const Scaffold(body: Text('home-root')),
      ),
    ),
  );
  moveraNavigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDefaultTargetPlatformOverride = null;
}

/// Every text the page builds while scrolled from top to bottom.
Future<Set<String>> _allTexts(WidgetTester tester) async {
  final seen = <String>{};
  void collect() {
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final s = w.data ?? w.textSpan?.toPlainText();
      if (s != null) seen.add(s);
    }
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      seen.add(w.text.toPlainText());
    }
  }

  collect();
  final scrollable = find.byType(Scrollable).last;
  for (var i = 0; i < 30; i++) {
    await tester.drag(scrollable, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
    collect();
  }
  return seen;
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  final row = find.text(label).last;
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.tap(row);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // B9: Help (Support) is a deferred part now; load it outside the fake clock.
    await loadDeferredScreens();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'side menu shows only currently reachable production destinations',
    (tester) async {
      await _pump(tester, const RiderMenuPage());
      final texts = (await _allTexts(tester)).join('\n');
      for (final shown in [
        'Wallet',
        'Ride History',
        'Safety',
        'Support',
        'About',
      ]) {
        expect(texts, contains(shown), reason: shown);
      }
      for (final hidden in [
        'Promotions',
        'Scheduled Rides',
        'Subscriptions',
        'Expense Your Rides',
        'Invite Friends',
        'Become a driver',
      ]) {
        expect(texts, isNot(contains(hidden)), reason: hidden);
      }
      await _unmount(tester);
    },
  );

  testWidgets('the menu Wallet entry opens Wallet and payments', (
    tester,
  ) async {
    await _pump(tester, const RiderMenuPage());
    await _tapLabel(tester, 'Wallet');
    await _settle(tester);
    expect(find.byType(WalletAndPaymentsScreen), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('help stays reachable from the side menu', (tester) async {
    await _pump(tester, const RiderMenuPage());
    await _tapLabel(tester, 'Support');
    expect(find.byType(SupportHome), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('help stays reachable from Account', (tester) async {
    await _pump(tester, const AccountHomePage());
    await _tapLabel(tester, 'Support');
    expect(find.byType(SupportHome), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
    'D-026: Ride History "Book a ride" closes the menu and starts booking',
    (tester) async {
      var started = 0;
      await _pump(tester, RiderMenuPage(onStartBooking: () => started++));
      await _tapLabel(tester, 'Ride History');
      expect(find.byType(RiderMenuPage, skipOffstage: false), findsOneWidget);
      // Ride History hands back its start-booking result.
      moveraNavigatorKey.currentState!.pop(rideHistoryStartBookingResult);
      await _settle(tester);
      expect(started, 1);
      expect(find.byType(RiderMenuPage, skipOffstage: false), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
      await _unmount(tester);
    },
  );

  testWidgets('a plain back from a menu page keeps the menu open', (
    tester,
  ) async {
    var started = 0;
    await _pump(tester, RiderMenuPage(onStartBooking: () => started++));
    await _tapLabel(tester, 'Ride History');
    moveraNavigatorKey.currentState!.pop();
    await _settle(tester);
    expect(started, 0);
    expect(find.byType(RiderMenuPage), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Ride History "Schedule a ride" opens Plan your ride, not the '
      'category list', (tester) async {
    await _pump(
      tester,
      RideHistory(
        reservations: ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
        ),
        onDemandReader: () async => const <Reservation>[],
      ),
    );
    final button = find.byWidgetPredicate(
      (w) =>
          (w is FilledButton || w is OutlinedButton) &&
          find
              .descendant(
                of: find.byWidget(w),
                matching: find.textContaining('Schedule'),
              )
              .evaluate()
              .isNotEmpty,
    );
    expect(button, findsWidgets);
    await tester.ensureVisible(button.first);
    await tester.tap(button.first);
    await _settle(tester);
    expect(find.byType(ScheduleRide), findsOneWidget);
    expect(find.text('Plan your ride'), findsWidgets);
    expect(find.byType(SelectRide), findsNothing);
    await _unmount(tester);
  });
}
