// Live 5+5 test 2026-11-08 item 2 (1-ride-now-p1 204/206, 3-ride-now-p3
// 171/177): at trip start "Framme HH:MM" showed the start time for 8-10 s.
// The rider_onboard projection still carries the server's stored PICKUP
// ETA (trips.eta, 60 s) until the next 30 s tick routes to the drop-off,
// and a start event without an ETA kept the pickup seconds. On board, a
// pickup ETA never gives the arrival time: no time until a drop-off ETA.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';

class _Feed implements RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;
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
  void dispose() => unawaited(events.close());
}

const pLat = 59.3293, pLng = 18.0686; // pickup
const dLat = 59.40, dLng = 17.95; // drop-off ~10 km away

void main() {
  Map<String, Object?> eta(DateTime at, String target, int s, int m) => {
    'etaSeconds': s,
    'distanceMeters': m,
    'target': target,
    'at': at.toUtc().toIso8601String(),
    'source': 'osrm',
  };
  late _Feed feed;
  late DriverTrackingController tracking;
  var seq = 0;
  setUp(() {
    seq = 0;
    L10n.use('sv');
    feed = _Feed();
    tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: pLat,
      pickupLng: pLng,
      destinationLat: dLat,
      destinationLng: dLng,
      persistRideSnapshot: false,
    )..start(rideId: 'trp_1', initialStatus: RideStatus.driverArriving);
  });
  tearDown(() {
    tracking.dispose();
    feed.dispose();
    L10n.use('en');
  });
  Future<void> send(
    RideStatus status, {
    double? lat,
    double? lng,
    DateTime? at,
    int? etaSeconds,
    Map<String, Object?> payload = const {},
  }) async {
    seq += 1;
    feed.events.add(
      RideRealtimeEvent(
        tripId: 'trp_1',
        status: status,
        sequence: seq,
        version: seq,
        latitude: lat,
        longitude: lng,
        locationAt: at,
        etaSeconds: etaSeconds,
        payload: payload,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('trip start with the stored PICKUP eta: no arrival time until a '
      'drop-off eta arrives', () async {
    final t0 = DateTime.now().subtract(const Duration(seconds: 90));
    // Last pickup tick before arrival, as the server stored it.
    final pickupEta = eta(t0, 'pickup', 60, 40);
    await send(
      RideStatus.driverArriving,
      lat: pLat,
      lng: pLng,
      at: t0,
      etaSeconds: 60,
      payload: {etaKey: pickupEta},
    );
    await send(
      RideStatus.driverWaiting,
      lat: pLat,
      lng: pLng,
      at: t0.add(const Duration(seconds: 30)),
    );
    // Start: the projection still carries trips.eta (target pickup).
    await send(
      RideStatus.tripStarted,
      lat: pLat,
      lng: pLng,
      at: DateTime.now(),
      etaSeconds: 60,
      payload: {etaKey: pickupEta},
    );
    expect(tracking.eta?.server?.toPickup, isNot(true));
    expect(tracking.eta?.seconds, isNull, reason: 'no arrival time yet');
    expect(
      tracking.eta!.subtitle(status: RideStatus.tripStarted),
      L10n.current.etaToDropoff,
    );
    // The first drop-off tick gives the real arrival time.
    final now = DateTime.now();
    await send(
      RideStatus.tripStarted,
      lat: pLat,
      lng: pLng,
      at: now,
      etaSeconds: 720,
      payload: {etaKey: eta(now, 'dropoff', 720, 9000)},
    );
    expect(tracking.eta?.seconds, 720);
    expect(tracking.eta?.server?.toPickup, isFalse);
  });

  test('trip start without any eta does not keep the pickup seconds', () async {
    final t0 = DateTime.now();
    await send(
      RideStatus.driverWaiting,
      lat: pLat,
      lng: pLng,
      at: t0,
      etaSeconds: 60,
    );
    await send(RideStatus.tripStarted); // status event: no position, no eta
    expect(tracking.eta?.seconds, isNull, reason: 'no arrival time yet');
  });
}
