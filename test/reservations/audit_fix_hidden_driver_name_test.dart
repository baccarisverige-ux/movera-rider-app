import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';

/// rider-u163: with admin's showDriverOnAccept off the driver card was
/// hidden, but the status banner above it ("Amina is assigned to this
/// reservation.") and the driver-left banner still named the driver.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const amina = ReservationDriver(
    firstName: 'Amina',
    rating: 4.9,
    vehicle: 'Volvo EX40',
    plate: 'ABC 123',
  );

  Future<ReservationController> seeded() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_hidden',
      ),
      rules: const ScheduledRideRules(showDriverOnAccept: false),
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.utc(2026, 9, 23, 4, 55),
        pickup: const ReservationPlace(label: 'Klockarvägen 37'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
      ),
    );
    await c.assignMockDriver('rsv_hidden', driver: amina);
    return c;
  }

  Future<void> pumpPage(WidgetTester tester, ReservationController c) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(
          reservationId: 'rsv_hidden',
          controller: c,
        ),
      ),
    );
  }

  testWidgets('the status banner does not name a hidden driver', (
    tester,
  ) async {
    final c = await seeded();
    await pumpPage(tester, c);
    expect(find.textContaining('Amina'), findsNothing);
    expect(
      find.text('A driver has been assigned to this reservation.'),
      findsOneWidget,
    );
  });

  testWidgets('the driver-left banner does not name a hidden driver', (
    tester,
  ) async {
    final c = await seeded();
    await c.driverCancelled('rsv_hidden');
    await pumpPage(tester, c);
    expect(find.byKey(const Key('reservation-driver-left')), findsOneWidget);
    expect(find.textContaining('Amina'), findsNothing);
  });
}
