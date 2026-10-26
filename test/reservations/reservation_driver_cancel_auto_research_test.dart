import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When the driver of a live scheduled ride drops it, the rider is not asked
/// anything: the reservation goes straight back to finding a driver and a
/// short notice says why. It used to wait on a "Keep searching" tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  testWidgets('a dropped live reservation searches again with no tap', (
    tester,
  ) async {
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_dropped',
      ),
    );
    await controller.create(
      ReservationDraft(
        scheduledPickupAt: DateTime(2026, 9, 23, 8),
        pickup: const ReservationPlace(
          label: 'Stockholm Central',
          lat: 59.3300,
          lng: 18.0590,
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Airport',
          lat: 59.6519,
          lng: 17.9186,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 349,
        paymentMethod: 'Apple Pay',
      ),
    );
    await controller.assignMockDriver(
      'rsv_dropped',
      driver: const ReservationDriver(
        firstName: 'Amina',
        rating: 4.9,
        vehicle: 'Volvo EX40',
        plate: 'ABC 123',
      ),
    );
    final live = await controller.update(
      'rsv_dropped',
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('upcoming-parent'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReservationLiveRide.pageFor(live, controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(WaitingForDriver), findsOneWidget);

    // The driver drops the ride.
    await controller.driverCancelled('rsv_dropped');
    for (
      var i = 0;
      i < 30 && find.byType(WaitingForDriver).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Nothing was tapped, yet the rider is back where they came from with
    // a notice, and the ride is still booked and waiting for a new driver.
    expect(find.text('Keep searching'), findsNothing);
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.text('upcoming-parent'), findsOneWidget);
    expect(find.text('Amina cancelled'), findsOneWidget);
    expect(find.text(DriverCancelledNotice.body), findsOneWidget);
    final ride = controller.byId('rsv_dropped')!;
    expect(ride.status, ReservationStatus.driverAssignmentPending);
    expect(ride.driver, isNull);
    expect(controller.upcoming().map((r) => r.reservationId), ['rsv_dropped']);

    await tester.pump(driverCancelledNoticeDuration);
    await tester.pumpAndSettle();
    expect(find.byType(DriverCancelledNotice), findsNothing);
  });
}
