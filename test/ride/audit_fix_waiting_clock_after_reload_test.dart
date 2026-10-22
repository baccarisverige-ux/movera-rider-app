import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u45: after a reload the session is seeded with the snapshot's
/// version, so the first projection usually repeats that version and status
/// and is rejected as a duplicate. The tracker applied the projection's
/// `acceptedAt` and `waiting.arrivedAt` only for accepted events, so both
/// stayed null: the waiting-fee clock restarted from "now" on every rebuild
/// and the free-cancel preview counted from the reload.
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

  const rideId = 'waiting-reload-clock';
  final acceptedAt = DateTime.utc(2026, 10, 21, 9, 0);
  final arrivedAt = DateTime.utc(2026, 10, 21, 9, 7);

  RideRealtimeEvent replay({
    required int version,
    RideStatus status = RideStatus.driverWaiting,
    bool stamped = true,
    int? etaSeconds,
  }) => RideRealtimeEvent(
    tripId: rideId,
    status: status,
    sequence: version,
    version: version,
    serverTime: DateTime.utc(2026, 10, 21, 9, 8),
    etaSeconds: etaSeconds,
    payload: {
      if (stamped) acceptedAtKey: WireTime.format(acceptedAt),
      if (stamped) waitingArrivedAtKey: WireTime.format(arrivedAt),
    },
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..bookedCategoryId = null
      ..restoreFromBackend(RideStatus.idle);
  });

  test('a same-version replay still carries the server clocks', () async {
    // The restore seeded version 5 at driverWaiting from the snapshot.
    final session = RideSession()
      ..restoreFromBackend(RideStatus.driverWaiting, id: rideId)
      ..authoritativeVersion = 5;
    final feed = _Feed();
    addTearDown(feed.dispose);
    final tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      ride: session,
    );
    addTearDown(tracking.dispose);
    tracking.start(rideId: rideId, initialStatus: RideStatus.driverWaiting);

    feed.add(replay(version: 5));
    await Future<void>.delayed(Duration.zero);

    expect(tracking.status, RideStatus.driverWaiting);
    expect(tracking.acceptedAt, acceptedAt);
    expect(tracking.waitingSince, arrivedAt);
  });

  test('rider-r4-13: the server stamps are moved onto a fast device clock',
      () async {
    addTearDown(ServerClock.reset);
    final device = DateTime.utc(2026, 10, 21, 9, 10);
    // The API's Date header: this phone runs 90 s fast.
    ServerClock.observeDateHeader(
      HttpDate.format(device.subtract(const Duration(seconds: 90))),
      receivedAt: device,
    );
    final session = RideSession()
      ..restoreFromBackend(RideStatus.driverWaiting, id: rideId)
      ..authoritativeVersion = 5;
    final feed = _Feed();
    addTearDown(feed.dispose);
    final tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      ride: session,
    );
    addTearDown(tracking.dispose);
    tracking.start(rideId: rideId, initialStatus: RideStatus.driverWaiting);

    feed.add(replay(version: 6));
    await Future<void>.delayed(Duration.zero);

    const fast = Duration(seconds: 90);
    expect(tracking.acceptedAt, acceptedAt.add(fast));
    expect(tracking.waitingSince, arrivedAt.add(fast));
  });

  test('an older replay never moves the clocks back', () async {
    final session = RideSession()
      ..restoreFromBackend(RideStatus.driverWaiting, id: rideId)
      ..authoritativeVersion = 5;
    final feed = _Feed();
    addTearDown(feed.dispose);
    final tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      ride: session,
    );
    addTearDown(tracking.dispose);
    tracking.start(rideId: rideId, initialStatus: RideStatus.driverWaiting);

    feed.add(replay(version: 6));
    await Future<void>.delayed(Duration.zero);
    final stale = RideRealtimeEvent(
      tripId: rideId,
      status: RideStatus.driverArriving,
      sequence: 4,
      version: 4,
      payload: {
        acceptedAtKey: WireTime.format(DateTime.utc(2026, 10, 21, 8)),
        waitingArrivedAtKey: WireTime.format(DateTime.utc(2026, 10, 21, 8, 1)),
      },
    );
    feed.add(stale);
    await Future<void>.delayed(Duration.zero);

    expect(tracking.acceptedAt, acceptedAt);
    expect(tracking.waitingSince, arrivedAt);
  });

  Future<_Feed> pumpWaiting(WidgetTester tester) async {
    await RideSnapshotStore.save(
      RideSnapshot(
        status: RideStatus.driverWaiting,
        savedAt: DateTime.now(),
        pickupAddress: 'Stockholm pickup',
        destinationAddress: 'Stockholm destination',
        pickupLat: 59.3293,
        pickupLng: 18.0686,
        destinationLat: 59.3326,
        destinationLng: 18.0649,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: rideId,
        categoryId: 'economy',
        version: 5,
      ),
    );
    AppScope.instance.ride
      ..restoreFromBackend(RideStatus.driverWaiting, id: rideId)
      ..authoritativeVersion = 5
      ..bookedCategoryId = 'economy';
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          realtime: feed,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return feed;
  }

  WaitingFeeCounter counter(WidgetTester tester) =>
      tester.widget<WaitingFeeCounter>(find.byType(WaitingFeeCounter));

  testWidgets('the waiting clock counts from the server arrival stamp', (
    tester,
  ) async {
    final feed = await pumpWaiting(tester);

    feed.add(replay(version: 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(WaitingFeeCounter), findsOneWidget);
    expect(counter(tester).since, arrivedAt);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a server stamp the clock start is kept, not "now"', (
    tester,
  ) async {
    final feed = await pumpWaiting(tester);

    feed.add(replay(version: 5, stamped: false, etaSeconds: 60));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WaitingFeeCounter), findsOneWidget);
    final first = counter(tester).since;

    // Waiting rebuilds (a new ETA on the sheet) a little later.
    feed.add(replay(version: 5, stamped: false, etaSeconds: 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(counter(tester).since, first);
    await tester.pumpWidget(const SizedBox());
  });
}
