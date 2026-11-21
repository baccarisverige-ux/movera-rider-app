import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';

/// Contract v0.18.152 (`bookLater.liveFixes.driverShown`,
/// `bookedRideSeen.searchSeen.riderApp`; owner 2026-11-21 15:00 (B)): a
/// booked ride a list driver accepted early shows only the booked card until
/// he drives to the pickup. The server says so with
/// `TripProjection.driverAssigned: true` and no driver details; the Home
/// chrono's "driver assigned" check (badge confirmed) reads it. Before, the
/// app read no driverAssigned and the check never showed for such a ride.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Map<String, dynamic> trip({bool assigned = true}) => {
    'tripId': 'trp_held',
    'kind': 'scheduled',
    'status': 'accepted',
    'version': 3,
    'categoryId': 'economy',
    'scheduledAt': '2026-11-05T08:00:00Z',
    'createdAt': '2026-11-05T05:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    if (assigned) 'driverAssigned': true,
  };

  test('a held booked ride (driverAssigned, no driver) reads as assigned, '
      'with no driver details', () {
    final ride = ApiReservationRepository.reservationOfTrip(trip());
    expect(ride.status, ReservationStatus.driverAssigned);
    expect(ride.driver, isNull);
    expect(ride.driverAssigned, isTrue);
    expect(ride.revealsDriver, isFalse);
  });

  test('the flag survives the device copy (toJson / tryParse)', () {
    final ride = ApiReservationRepository.reservationOfTrip(trip());
    final back = Reservation.tryParse(
      jsonDecode(jsonEncode(ride.toJson())) as Map<String, dynamic>,
    )!;
    expect(back.driverAssigned, isTrue);
    expect(back.driver, isNull);
  });

  test('without driverAssigned and without a driver it is not assigned '
      '(unchanged)', () {
    final ride = ApiReservationRepository.reservationOfTrip(
      trip(assigned: false),
    );
    expect(ride.driverAssigned, isFalse);
  });

  testWidgets('Home chrono shows the "driver assigned" check for a held '
      'booked ride', (tester) async {
    final ride = ApiReservationRepository.reservationOfTrip(trip());
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(jsonEncode([ride.toJson()])),
      ),
    );
    await c.hydrate();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = ride.scheduledPickupAt.subtract(const Duration(minutes: 90));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HomeReservationChrono(controller: c, now: () => now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reservation-chrono-badge-confirmed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reservation-chrono-badge-booked')),
      findsNothing,
    );
  });
}
