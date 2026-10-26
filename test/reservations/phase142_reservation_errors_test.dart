import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/plan_return_ride.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage that can be told to fail its next writes.
class _FlakyStorage extends MemoryReservationStorage {
  Object? failWith;

  @override
  Future<void> write(String json) async {
    final error = failWith;
    if (error != null) throw error;
    await super.write(json);
  }
}

const _offline = ApiError(code: 'NETWORK', message: 'no route to host');

/// Phase 142: a failed cancel, booking or edit of a scheduled ride used to
/// be silent — the button stopped spinning and nothing said whether the ride
/// was booked, changed or still on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  ReservationDraft draft(DateTime at) => ReservationDraft(
    scheduledPickupAt: at,
    pickup: const ReservationPlace(
      label: 'Klockarvägen 37',
      lat: 59.19,
      lng: 17.62,
    ),
    destination: const ReservationPlace(
      label: 'Arlanda Express',
      lat: 59.65,
      lng: 17.93,
    ),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 522,
    paymentMethod: 'Cash',
  );

  group('messages say what state the ride is left in', () {
    test(
      'every failed cancel except a refusal says the ride is still booked',
      () {
        final errors = <Object>[
          _offline,
          TimeoutException('slow'),
          const ApiError(code: 'X', message: '', statusCode: 429),
          const ApiError(code: 'X', message: '', statusCode: 503),
          StateError('bug'),
        ];
        for (final error in errors) {
          expect(
            reservationErrorMessage(error, ReservationAction.cancel),
            contains('still booked'),
            reason: '$error',
          );
        }
        expect(
          reservationErrorMessage(
            const ApiError(code: 'X', message: '', statusCode: 409),
            ReservationAction.cancel,
          ),
          "This ride can't be cancelled right now.",
        );
      },
    );

    test('offline, rate limit and server trouble are told apart', () {
      expect(
        reservationErrorMessage(_offline, ReservationAction.book),
        startsWith('No connection'),
      );
      expect(
        reservationErrorMessage(
          const ApiError(
            code: 'RATE_LIMITED',
            message: '',
            retryAfter: Duration(seconds: 45),
          ),
          ReservationAction.edit,
        ),
        "Too many tries, so your changes weren't confirmed. "
        'Try again in 45 seconds.',
      );
      expect(
        reservationErrorMessage(
          const ApiError(code: 'X', message: '', statusCode: 500),
          ReservationAction.book,
        ),
        startsWith('Movera is having trouble'),
      );
    });

    test('a failed booking or edit points the rider to check first', () {
      expect(
        reservationErrorMessage(StateError('bug'), ReservationAction.book),
        contains('Check Upcoming rides'),
      );
      expect(
        reservationErrorMessage(StateError('bug'), ReservationAction.edit),
        contains("Check your ride's details"),
      );
    });
  });

  test('a cancel that cannot be saved leaves the ride booked', () async {
    final storage = _FlakyStorage();
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: storage,
        nextId: () => 'rsv_keep',
      ),
    );
    await c.create(draft(DateTime(2026, 9, 23, 6, 55)));
    storage.failWith = _offline;

    await expectLater(c.cancel('rsv_keep'), throwsA(same(_offline)));
    expect(c.byId('rsv_keep')!.status, ReservationStatus.scheduled);

    await expectLater(
      c.create(draft(DateTime(2026, 9, 24, 6, 55))),
      throwsA(same(_offline)),
    );
    expect(c.all, hasLength(1), reason: 'an unsaved booking never appears');
  });

  test('overlapping changes all land, none built on a stale copy', () async {
    final storage = _FlakyStorage();
    var n = 0;
    final repo = LocalReservationRepository(
      storage: storage,
      nextId: () => 'rsv_${++n}',
    );
    await repo.createReservation(draft(DateTime(2026, 9, 23, 6, 55)));

    await Future.wait([
      repo.createReservation(draft(DateTime(2026, 9, 24, 6, 55))),
      repo.cancelReservation('rsv_1'),
    ]);

    expect(repo.cached.map((r) => r.reservationId), ['rsv_2', 'rsv_1']);
    expect(repo.cached.last.status, ReservationStatus.cancelled);
    final reloaded = LocalReservationRepository(storage: storage);
    await reloaded.hydrate();
    expect(reloaded.cached, hasLength(2), reason: 'both changes were saved');
  });

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed cancel tells the rider the ride is still booked', (
    tester,
  ) async {
    final storage = _FlakyStorage();
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: storage,
        nextId: () => 'rsv_cancel',
      ),
    );
    await c.create(draft(DateTime(2026, 9, 23, 6, 55)));
    await pumpPhone(
      tester,
      UpcomingReservationPage(reservationId: 'rsv_cancel', controller: c),
    );
    storage.failWith = _offline;

    final cancel = find.text('Cancel reservation');
    await tester.scrollUntilVisible(cancel, 300);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    // The confirmation sheet's button, on top of the page's own.
    await tester.tap(find.text('Cancel reservation').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    const message =
        "No connection, so your cancellation wasn't confirmed. Your ride is "
        "still booked — try again when you're back online.";
    // The message follows the reason sheet's close animation.
    for (var i = 0; i < 30 && find.text(message).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text(message), findsOneWidget);
    expect(c.byId('rsv_cancel')!.status, ReservationStatus.scheduled);
    expect(tester.takeException(), isNull);

    // The rider can try again once back online (after the message goes).
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    storage.failWith = null;
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Cancel reservation?'), findsOneWidget);
    // The confirmation sheet's button, on top of the page's own.
    await tester.tap(find.text('Cancel reservation').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(c.byId('rsv_cancel')!.status, ReservationStatus.cancelled);
  });

  testWidgets('a failed return-ride booking says it was not confirmed', (
    tester,
  ) async {
    // Select Ride quotes through the mock API, which needs a desktop
    // platform in widget tests (see phase114_return_ride_time_test.dart).
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final storage = _FlakyStorage()..failWith = _offline;
      final c = ReservationController(
        store: LocalReservationRepository(storage: storage),
      );
      // Tomorrow on the 5-minute grid, so origin + 3 h is a legal pickup and
      // the flow goes straight to confirming the pickup spot.
      final pickupAt = StockholmSchedule.clampPickup(
        StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
      );
      final origin = Reservation(
        reservationId: 'rsv_origin',
        createdAt: pickupAt.subtract(const Duration(days: 1)),
        scheduledPickupAt: pickupAt,
        pickup: draft(pickupAt).pickup,
        destination: draft(pickupAt).destination,
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
        status: ReservationStatus.scheduled,
      );
      final opened = <String>[];

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            navigatorKey: moveraNavigatorKey,
            home: const Scaffold(body: Center(child: Text('phase142-home'))),
          ),
        ),
      );
      moveraNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PlanReturnRidePage(
            origin: origin,
            controller: c,
            onScheduled: (context, id) async => opened.add(id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      final cta = find.text('Schedule Movera');
      await waitFor(cta);
      await tester.ensureVisible(cta);
      await tester.tap(cta);
      await tester.pump();
      await waitFor(find.byType(SetPickupPage));
      final confirm = find.widgetWithText(FilledButton, 'Confirm and schedule');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();

      const message =
          "No connection, so your booking wasn't confirmed. Check Upcoming "
          'rides before trying again.';
      await waitFor(find.text(message));
      expect(find.text(message), findsOneWidget);
      expect(c.all, isEmpty);
      expect(
        opened,
        isEmpty,
        reason: 'no "ride scheduled" for a failed booking',
      );
      expect(find.text('Schedule Movera'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
