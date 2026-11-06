import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/search_step.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// N2 + P17 screenshot review (Rules audits/screens-2026-11-05/rider-510,
/// rule 36: written before the fix).
/// 3) at pickup + 16 min the page still offered "Cancel this reservation and
///    book again" and "Edit reservation" although the server ended the ride;
/// 4) the finding screen still said "It's busier than usual" / "Raise your
///    offer" next to the no_driver_found card;
/// 5) between the pickup time and the stop a booked ride with no driver said
///    "Reservation confirmed".
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('en');
  });

  Future<ReservationController> booked(DateTime now) async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_n2',
      ),
      clock: () => now,
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.utc(2026, 11, 6, 8),
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
    return c;
  }

  Future<void> show(WidgetTester tester, ReservationController c) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(reservationId: 'rsv_n2', controller: c),
      ),
    );
  }

  testWidgets('pickup + 16 min (server ended it): no cancel-and-book-again, '
      'no Edit reservation, "you pay nothing"', (tester) async {
    final c = await booked(DateTime.utc(2026, 11, 6, 8, 16));
    await show(tester, c);
    expect(find.textContaining('Cancel this reservation'), findsNothing);
    expect(find.text('Edit reservation'), findsNothing);
    expect(
      find.textContaining('You pay nothing'),
      findsOneWidget,
    ); // Rule-29 review: the page subtitle no longer says the ride is reserved.
    expect(find.textContaining('Your ride is reserved for'), findsNothing);
  });

  testWidgets('pickup + 10 min, no driver yet: "Still looking for a driver", '
      'never "Reservation confirmed"', (tester) async {
    final c = await booked(DateTime.utc(2026, 11, 6, 8, 10));
    await show(tester, c);
    expect(find.text('Reservation confirmed'), findsNothing);
    expect(find.text('Still looking for a driver'), findsOneWidget);
  });

  test(
    'finding screen with no_driver_found: no busier copy, no raise card',
    () {
      RideSnapshotStore.epoch = 0;
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(rt.dispose);
      final c = FindingDriverController(
        realtime: rt,
        ride: RideSession()..rideId = 'ride-nf',
        store: FindingDriverRepository(),
        api: ApiClient(client: InProcessMockClient()),
        delayedAfter: Duration.zero,
        priceBumpAfter: Duration.zero,
      );
      addTearDown(c.dispose);
      c.elapsedSeconds = 120;
      c.searchStep = TripSearchStep.fromWire({
        'id': 'nf',
        'kind': 'no_driver_found',
        'message': 'x',
      });
      expect(c.copy.headline, isNot(L10n.current.searchBusier));
      expect(c.copy.headline, L10n.current.termNoDriverAvailable);
      expect(c.showPriceBump, isFalse);
    },
  );

  test(
    'finding screen with no_driver_nearby: no "busier than usual" heading',
    () {
      RideSnapshotStore.epoch = 0;
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(rt.dispose);
      final c = FindingDriverController(
        realtime: rt,
        ride: RideSession()..rideId = 'ride-nd',
        store: FindingDriverRepository(),
        api: ApiClient(client: InProcessMockClient()),
        delayedAfter: Duration.zero,
        priceBumpAfter: Duration.zero,
      );
      addTearDown(c.dispose);
      c.elapsedSeconds = 300;
      c.searchStep = TripSearchStep.fromWire({
        'id': 'nd',
        'kind': 'no_driver_nearby',
        'message': 'x',
      });
      expect(c.copy.headline, isNot(L10n.current.searchBusier));
      expect(c.copy.headline, L10n.current.stillLooking);
    },
  );
}
