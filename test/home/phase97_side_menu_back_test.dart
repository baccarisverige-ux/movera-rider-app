import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 9 Phase 97 — U1 (menu pages return to the menu), D-026 (Ride
/// History "Book a ride" starts a booking), D-024 (profile empty copy).
/// The menu is now a full-screen page pushed over Home.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Home with the menu page pushed over it, as the menu button does.
  Future<void> pumpHomeWithMenu(
    WidgetTester tester, {
    VoidCallback? onStartBooking,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => RiderMenuPage.open(
                    context,
                    onStartBooking: onStartBooking,
                  ),
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
    expect(find.byType(RiderMenuPage), findsOneWidget);
  }

  testWidgets('U1: Back from a menu page returns to the menu', (tester) async {
    await pumpHomeWithMenu(tester);
    await tester.scrollUntilVisible(
      find.text('About Movera'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Movera'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpArticle), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(RiderMenuPage), findsOneWidget);
    expect(find.byType(HelpArticle), findsNothing);
  });

  testWidgets('the menu page carries every destination and a way back', (
    tester,
  ) async {
    await pumpHomeWithMenu(tester);
    for (final title in [
      'Wallet',
      'Ride History',
      'Notifications',
      'Saved Places',
      'Support',
      'Your promotions',
      'Safety checkup',
      'Movera Family',
      'Invite friends',
      'Movera Business',
      'Greener rides',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // The account rows sit below the fold.
    await tester.scrollUntilVisible(
      find.text('About Movera'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final title in [
      'Personal info',
      'Security',
      'Privacy',
      'Terms',
      'Privacy notice',
      'About Movera',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(
      find.text('Movera Rider v${RiderMenuPage.appVersion}'),
      findsOneWidget,
    );
    // The back arrow returns to Home.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-back')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-back')));
    await tester.pumpAndSettle();
    expect(find.byType(RiderMenuPage), findsNothing);
    expect(find.text('Home body'), findsOneWidget);
  });

  testWidgets('Where to and Later leave the menu and continue on Home', (
    tester,
  ) async {
    var booked = 0;
    await pumpHomeWithMenu(tester, onStartBooking: () => booked++);
    expect(find.text('Where to?'), findsOneWidget);
    await tester.tap(find.text('Where to?'));
    await tester.pumpAndSettle();
    expect(find.byType(RiderMenuPage), findsNothing);
    expect(find.text('Home body'), findsOneWidget);
    expect(booked, 1);
  });

  testWidgets('D-026: Ride History "Book a ride" asks to start a booking', (
    tester,
  ) async {
    Object? result = 'unset';
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (_) => RideHistory(
                        reservations: ReservationController(
                          store: LocalReservationRepository(
                            storage: MemoryReservationStorage(),
                          ),
                        ),
                        onDemandReader: () async => const <Reservation>[],
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book a ride').first);
    await tester.pumpAndSettle();
    expect(result, RideHistory.startBookingResult);
  });

  test('D-026: the menu turns that result into a booking, not the menu', () {
    final menu = File(
      'lib/features/home/presentation/side_menu.dart',
    ).readAsStringSync();
    expect(menu, contains('result == RideHistory.startBookingResult'));
    expect(menu, contains('onStartBooking?.call();'));
    // The menu page itself leaves first, so booking starts over Home.
    expect(menu, contains('nav.pop();\n      onStartBooking?.call();'));
    final home = File(
      'lib/features/home/presentation/home.dart',
    ).readAsStringSync();
    // NAV-6: Home starts the booking after the menu's park scope ends.
    expect(
      home,
      contains('onStartBooking: () => then = _handleDestinationTap'),
    );
    expect(home, contains('await then?.call();'));
  });

  test('D-024: an empty profile never reads as a literal placeholder', () {
    // The account screen's empty state is covered by account_flow_test.
    expect(ProfileRepository.emptyDisplayName, isNot('Profile not set'));
    expect(ProfileRepository.emptyDisplayName, 'Welcome to Movera');
  });
}
