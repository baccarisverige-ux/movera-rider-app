import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';

/// rider-j8-1: Home declared the ride "No driver found" five minutes after
/// pickup, but its Upcoming page (from History or a notification) still
/// said "Reservation confirmed" in a green banner.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('a ride with no driver found does not read as confirmed', (
    tester,
  ) async {
    final pickup = DateTime.utc(2026, 10, 21, 8);
    final now = pickup.add(const Duration(minutes: 6));
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_nodriver',
      ),
      clock: () => now,
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: pickup,
        pickup: const ReservationPlace(label: 'Klockarvägen 37'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
      ),
    );
    await c.startLiveIfDue();
    expect(c.isNoDriverFound(c.byId('rsv_nodriver')!), isTrue);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(
          reservationId: 'rsv_nodriver',
          controller: c,
        ),
      ),
    );

    expect(find.text('Reservation confirmed'), findsNothing);
    expect(find.text('No driver found'), findsOneWidget);
  });
}
