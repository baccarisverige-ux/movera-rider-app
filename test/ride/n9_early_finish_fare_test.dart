import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner, live test 2026-10-26 (N9): a driver who finished 29 km before the
/// drop-off ended the trip at 54 kr on the server (base + time +
/// minimum_adjust, under the 824 kr booked), and the rider's summary and
/// receipt said "Booked price 824 kr". The completed projection's `fare` is
/// what the rider pays; it travels with the live status to the completion.
class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast();
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => c.stream;
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
  void dispose() => c.close();
}

RideSnapshot _snapshot(RideStatus status) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'Södertälje centrum',
  destinationAddress: 'Stockholm Central Station',
  pickupLat: 59.1955,
  pickupLng: 17.6253,
  destinationLat: 59.33,
  destinationLng: 18.0587,
  rideType: 'Movera',
  price: 824,
  paymentMethod: 'Cash',
  rideId: 'trip-n9',
  version: 9,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  testWidgets('the poll puts the projection\'s fare on the event', (
    tester,
  ) async {
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tripId': 'trip-n9',
              'status': 'completed',
              'version': 12,
              'updatedAt': '2026-10-26T10:34:00Z',
              'fare': {'amountMinor': 5400, 'currency': 'SEK'},
              'quote': {
                'total': {'amountMinor': 82400, 'currency': 'SEK'},
              },
            }),
            200,
          ),
        ),
        env: AppEnv.current,
      ),
      pollInterval: const Duration(seconds: 2),
    );
    addTearDown(rt.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('trip-n9').listen(events.add);
    addTearDown(sub.cancel);
    await tester.pump();
    await rt.reconnectAndResync('trip-n9');
    await tester.pump();

    expect(events, isNotEmpty);
    expect(events.last.fare, const Money(5400, 'SEK'));
    rt.dispose();
  });

  test('the tracker keeps the latest fare the wire carried', () async {
    await RideSnapshotStore.save(_snapshot(RideStatus.tripInProgress));
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    final ride = RideSession(rideId: 'trip-n9')
      ..status = RideStatus.tripInProgress
      ..authoritativeVersion = 9;
    final controller = DriverTrackingController(
      realtime: realtime,
      pickupLat: 59.1955,
      pickupLng: 17.6253,
      ride: ride,
    );
    addTearDown(controller.dispose);
    controller.start(rideId: 'trip-n9', initialStatus: RideStatus.tripInProgress);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.fare, isNull);

    realtime.c.add(
      RideRealtimeEvent(
        tripId: 'trip-n9',
        status: RideStatus.tripCompleted,
        sequence: 12,
        version: 12,
        serverTime: DateTime.utc(2026, 10, 26, 10, 34),
        payload: {
          fareKey: {'amountMinor': 5400, 'currency': 'SEK'},
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.status, RideStatus.tripCompleted);
    expect(controller.fare, const Money(5400, 'SEK'));
  });

  test('the completion shows the server\'s fare, not the booked price', () async {
    final snapshot = _snapshot(RideStatus.tripInProgress);
    await RideSnapshotStore.save(snapshot);
    AppScope.instance.ride
      ..rideId = snapshot.rideId
      ..status = RideStatus.tripInProgress;

    await ActiveRideController().markCompleted(
      RideStatus.tripCompleted,
      charged: const Money(5400, 'SEK'),
    );

    expect(LastCompletedRide.charged, const Money(5400, 'SEK'));
    expect(LastCompletedRide.value?.price, 54);
    expect((await RideSnapshotStore.read())?.price, 54);
    final receipt = RideCompleteController().receipt(rideId: 'trip-n9');
    expect(receipt, isNotNull);
    expect(receipt!.isFinal, isTrue);
    expect(receipt.total, contains('54'));
    expect(receipt.total, isNot(contains('824')));
  });

  test('without a fare on the wire the booked price stays', () async {
    final snapshot = _snapshot(RideStatus.tripInProgress);
    await RideSnapshotStore.save(snapshot);
    AppScope.instance.ride
      ..rideId = snapshot.rideId
      ..status = RideStatus.tripInProgress;

    await ActiveRideController().markCompleted(RideStatus.tripCompleted);

    expect(LastCompletedRide.charged, isNull);
    expect(LastCompletedRide.value?.price, 824);
  });

  test('a fare in another currency is not this trip\'s price', () async {
    final snapshot = _snapshot(RideStatus.tripInProgress);
    await RideSnapshotStore.save(snapshot);
    AppScope.instance.ride
      ..rideId = snapshot.rideId
      ..status = RideStatus.tripInProgress;

    await ActiveRideController().markCompleted(
      RideStatus.tripCompleted,
      charged: const Money(500, 'EUR'),
    );

    expect(LastCompletedRide.charged, isNull);
    expect(LastCompletedRide.value?.price, 824);
  });
}
