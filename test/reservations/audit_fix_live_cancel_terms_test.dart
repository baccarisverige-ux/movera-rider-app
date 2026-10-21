import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u53: on the reservation live screen the cancel sheet's fee line
/// came from the Book Now session's leftover category and the live fee
/// rule ("free for 2 more minutes" from economy's live rule, or no line at
/// all), while the cancel that ran applied the reservation's own terms with
/// no fee recorded. The rider confirmed against the wrong line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    // An Economy Book Now ride ran earlier in this process.
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.closed, id: 'bn-earlier')
      ..bookedCategoryId = 'economy';
  });

  const driver = ReservationDriver(
    firstName: 'Amina',
    rating: 4.9,
    vehicle: 'Volvo EX40',
    plate: 'ABC 123',
  );

  testWidgets('the live cancel sheet shows the reservation\'s own fee', (
    tester,
  ) async {
    // 23:20 now, pickup at 23:50: inside the 60-minute late window, so the
    // reservation rules charge the 50 kr late fee.
    final now = DateTime(2026, 10, 21, 23, 20);
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv-live-fee',
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    final created = await controller.create(
      ReservationDraft(
        scheduledPickupAt: DateTime(2026, 10, 21, 23, 50),
        pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
        destination: const ReservationPlace(
          label: 'Arlanda',
          lat: 59.65,
          lng: 17.93,
        ),
        categoryId: 'comfort',
        categoryName: 'Comfort',
        categoryImage: 'assets/images/rides/comfort.webp',
        price: 450,
        paymentMethod: 'Cash',
      ),
    );
    await controller.assignMockDriver(created.reservationId, driver: driver);
    final live = await controller.update(
      created.reservationId,
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );
    final expectedFee = controller.cancelTermsFor(live).fee;
    expect(expectedFee, const Money(5000));

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('audit-root'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReservationLiveRide.pageFor(live, controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WaitingForDriver), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.text('Cancellation fee: 50 kr'), findsOneWidget);
    expect(find.textContaining('free for'), findsNothing);

    // Confirming records the fee the rider saw, as the Upcoming screen does.
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final cancelled = controller.byId(created.reservationId)!;
    expect(cancelled.status, ReservationStatus.cancelled);
    expect(cancelled.cancellationFee, const Money(5000));
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.text('audit-root'), findsOneWidget);
  });
}
