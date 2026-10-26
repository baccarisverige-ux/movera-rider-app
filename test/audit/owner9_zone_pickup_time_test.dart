import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

import '../reservations/scheduled_quote_harness.dart';

/// Owner decision 9 (rider-13, rider-r4-12): a scheduled pickup is the
/// pickup zone's wall time, held so the phone's own time zone can never
/// move it, and stored as its instant with the zone. CI runs this file
/// under TZ=UTC, Europe/Stockholm and America/New_York; it must read the
/// same in each.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  // captureSchedule clamps against StockholmSchedule.clock, not the `now`
  // the picker gets, so the file's fixed dates must drive that clock too.
  setUp(() => StockholmSchedule.clock = () => DateTime.utc(2026, 10, 21, 10));
  tearDown(() => StockholmSchedule.clock = DateTime.now);

  const tunisPickup = ReservationPlace(
    label: 'Avenue Habib Bourguiba',
    lat: 36.80,
    lng: 10.18,
  );
  const tunisDrop = ReservationPlace(
    label: 'Tunis-Carthage',
    lat: 36.85,
    lng: 10.23,
  );

  Future<(DateTime?, bool)> pick(
    WidgetTester tester, {
    required DateTime now,
    required DateTime initial,
    required String timeZone,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTime? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await ScheduleDateTimeSelector.choose(
                  context,
                  initial: initial,
                  now: () => now,
                  timeZone: timeZone,
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final moved = find
        .textContaining('next available slot')
        .evaluate()
        .isNotEmpty;
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();
    return (chosen, moved);
  }

  testWidgets('a Stockholm phone booking Tunis 09:00 sends the Tunis instant', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 21, 10);
    final (chosen, moved) = await pick(
      tester,
      now: now,
      initial: DateTime.utc(2026, 10, 22, 9),
      timeZone: ZoneClock.tunis,
    );
    expect(moved, isFalse);
    final session = ScheduledRideSession()
      ..captureSchedule(chosen!, timezone: ZoneClock.tunis);
    expect(session.scheduledAtWire, '2026-10-22T08:00:00.000Z');

    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
    );
    addTearDown(selection.dispose);
    final ride = selection.rideById('economy');
    selection.selectRide(ride.id, ride.price);
    selection.scheduleFor(chosen);
    adoptScheduledQuote(selection, 'economy');
    final booked = await ScheduledRideBooking.confirm(
      reservations: ReservationController(
        store: LocalReservationRepository(storage: MemoryReservationStorage()),
        clock: () => now,
      ),
      selection: selection,
      pickup: tunisPickup,
      destination: tunisDrop,
    );
    expect(
      booked.scheduledPickupAt.isAtSameMomentAs(DateTime.utc(2026, 10, 22, 8)),
      isTrue,
    );
    expect(booked.timeZone, ZoneClock.tunis);
  });

  testWidgets(
    'Tunis 02:30 on the EU spring-forward night stays 02:30 (rider-r4-12)',
    (tester) async {
      final (chosen, moved) = await pick(
        tester,
        now: DateTime.utc(2027, 3, 27, 10),
        initial: DateTime.utc(2027, 3, 28, 2, 30),
        timeZone: ZoneClock.tunis,
      );
      expect(moved, isFalse);
      expect(chosen, DateTime.utc(2027, 3, 28, 2, 30));
      expect(
        ZoneClock.toUtc(chosen!, ZoneClock.tunis),
        DateTime.utc(2027, 3, 28, 1, 30),
      );
    },
  );

  testWidgets(
    'a Stockholm time in its own spring-forward gap moves forward and says so',
    (tester) async {
      final (chosen, moved) = await pick(
        tester,
        now: DateTime.utc(2027, 3, 27, 10),
        initial: DateTime.utc(2027, 3, 28, 2, 30),
        timeZone: ZoneClock.stockholm,
      );
      expect(moved, isTrue);
      expect(chosen, DateTime.utc(2027, 3, 28, 3, 30));
      expect(
        ZoneClock.exists(DateTime.utc(2027, 3, 28, 2, 30), ZoneClock.stockholm),
        isFalse,
      );
      expect(
        ZoneClock.toUtc(chosen!, ZoneClock.stockholm),
        DateTime.utc(2027, 3, 28, 1, 30),
      );
    },
  );

  test('a fall-back time that happens twice is the first one', () {
    final wall = DateTime.utc(2026, 10, 25, 2, 30);
    expect(ZoneClock.exists(wall, ZoneClock.stockholm), isTrue);
    expect(
      ZoneClock.toUtc(wall, ZoneClock.stockholm),
      DateTime.utc(2026, 10, 25, 0, 30),
    );
    expect(
      ZoneClock.wallTime(
        ZoneClock.stockholm,
        DateTime.utc(2026, 10, 25, 1, 30),
      ),
      wall,
    );
    const schedule = PickupSchedule(ZoneClock.stockholm);
    expect(schedule.clampPickup(wall, DateTime.utc(2026, 10, 24, 10)), wall);
  });

  test('cards and the countdown show the Tunis wall time', () {
    final ride = Reservation(
      reservationId: 'r1',
      createdAt: DateTime.utc(2026, 10, 20),
      scheduledPickupAt: DateTime.utc(2026, 10, 22, 8),
      pickup: tunisPickup,
      destination: tunisDrop,
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 20,
      currency: 'TND',
      paymentMethod: 'Wallet',
      status: ReservationStatus.scheduled,
      timeZone: ZoneClock.tunis,
    );
    expect(ReservationFormat.time(ride.pickupWallTime), '09:00');
    expect(
      ReservationFormat.reservedHeadline(ride.pickupWallTime),
      contains('09:00'),
    );
    // 23:30 UTC on the 21st is already the 22nd in Tunis: "Today".
    final today = ReservationFormat.historyWhen(
      ride,
      now: DateTime.utc(2026, 10, 21, 23, 30),
    );
    expect(today, contains('09:00'));
    expect(
      today,
      startsWith(
        ReservationFormat.cardDate(
          DateTime(2026, 10, 22),
          now: DateTime(2026, 10, 22),
        ),
      ),
    );
    expect(
      ReservationFormat.remainingCompact(
        ride.scheduledPickupAt,
        now: DateTime.utc(2026, 10, 22, 7, 30),
      ),
      ReservationFormat.remainingCompact(
        DateTime.utc(2000, 1, 1, 0, 30),
        now: DateTime.utc(2000),
      ),
    );
  });

  test(
    'an old stored ride reads to the same instant as before, in its pickup zone',
    () async {
      // Saved before rides kept their zone: an offset-less device-local value
      // (read as device-local, as written) and a UTC one.
      final storage = MemoryReservationStorage(
        jsonEncode([
          for (final (id, at) in [
            ('legacy', '2026-10-22T09:00:00.000'),
            ('utc', '2026-10-22T08:00:00.000Z'),
          ])
            {
              'reservationId': id,
              'createdAt': '2026-10-20T10:00:00.000Z',
              'scheduledPickupAt': at,
              'pickup': tunisPickup.toJson(),
              'destination': tunisDrop.toJson(),
              'status': 'scheduled',
            },
          {
            'reservationId': 'nopoint',
            'createdAt': '2026-10-20T10:00:00.000Z',
            'scheduledPickupAt': '2026-10-22T09:00:00.000',
            'pickup': 'Somewhere',
            'destination': 'Elsewhere',
          },
        ]),
      );
      final repo = LocalReservationRepository(storage: storage);
      await repo.hydrate();
      final byId = {for (final r in repo.cached) r.reservationId: r};
      expect(
        byId['legacy']!.scheduledPickupAt.isAtSameMomentAs(
          DateTime(2026, 10, 22, 9),
        ),
        isTrue,
      );
      expect(byId['legacy']!.timeZone, ZoneClock.tunis);
      expect(
        byId['utc']!.scheduledPickupAt.isAtSameMomentAs(
          DateTime.utc(2026, 10, 22, 8),
        ),
        isTrue,
      );
      expect(ReservationFormat.time(byId['utc']!.pickupWallTime), '09:00');
      // No pickup point: still the device's clock, as it always read.
      expect(byId['nopoint']!.timeZone, isNull);
      expect(ReservationFormat.time(byId['nopoint']!.pickupWallTime), '09:00');
    },
  );
}
