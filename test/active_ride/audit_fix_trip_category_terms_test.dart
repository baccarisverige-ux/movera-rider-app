import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u44: WaitingForDriver took the category for its waiting terms and
/// cancel-fee preview from the on-demand RideSession's last booked
/// category (or the on-demand snapshot) without checking the ride id, so
/// a scheduled XL ride's live screen counted economy's free wait, and a
/// sign-out never cleared the booked fields.
class _Feed implements RideRealtime {
  final StreamController<RideRealtimeEvent> _events =
      StreamController<RideRealtimeEvent>.broadcast();

  void add(RideRealtimeEvent event) => _events.add(event);

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    // Earlier in this process the rider took an Economy Book Now ride.
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.closed, id: 'bn-earlier')
      ..bookedCategoryId = 'economy';
  });

  testWidgets('a scheduled XL ride counts XL\'s free wait, not economy\'s', (
    tester,
  ) async {
    const rideId = 'rsv-xl-live';
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'XL',
          price: 459,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          categoryId: 'xl',
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    feed.add(
      RideRealtimeEvent(
        tripId: rideId,
        status: RideStatus.driverWaiting,
        sequence: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final counter = tester.widget<WaitingFeeCounter>(
      find.byType(WaitingFeeCounter),
    );
    // Seed config: xl waits 3 free minutes, economy 5.
    expect(counter.freeWaitMin, 3);
    await tester.pumpWidget(const SizedBox());
  });

  test('the reservation live screen is built with its own category', () {
    final page = ReservationLiveRide.pageFor(
      Reservation(
        reservationId: 'rsv-1',
        createdAt: DateTime(2026, 10, 20, 9),
        scheduledPickupAt: DateTime(2026, 10, 21, 23, 50),
        pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
        destination: const ReservationPlace(
          label: 'Arlanda',
          lat: 59.65,
          lng: 17.93,
        ),
        categoryId: 'xl',
        categoryName: 'XL',
        categoryImage: '',
        price: 459,
        paymentMethod: 'Cash',
        status: ReservationStatus.driverEnRoute,
      ),
    );
    expect(page.categoryId, 'xl');
  });

  test('ending the rider\'s session forgets the booked category', () {
    final session = RideSession()
      ..rideId = 'bn-1'
      ..bookedCategoryId = 'economy'
      ..bookedPaymentMethodId = 'visa'
      ..bookedMaxOfferMinor = 30000;
    session.reset();
    expect(session.bookedCategoryId, isNull);
    expect(session.bookedPaymentMethodId, isNull);
    expect(session.bookedMaxOfferMinor, isNull);
  });
}
