import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// X7: a cancel the server refuses with `409 version_mismatch` (the trip
/// changed since the rider's screen read it) commits nothing, is sent once
/// (no automatic second cancel), and the screen reads the ride again.
class _Realtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> events =
      StreamController<RideRealtimeEvent>.broadcast();
  final resyncs = <String>[];

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;

  @override
  Future<void> reconnectAndResync(String rideId) async => resyncs.add(rideId);

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

ApiClient _staleServer(List<String> posts, {String status = 'accepted'}) =>
    ApiClient(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          posts.add(request.url.path);
          final projection = {'tripId': 'v1', 'status': status, 'version': 7};
          return http.Response(
            jsonEncode({
              'code': 'version_mismatch',
              'message': 'The trip is at version 7.',
              'retryable': false,
              'projection': projection,
            }),
            409,
          );
        }
        return http.Response(
          jsonEncode({'tripId': 'v1', 'status': status, 'version': 7}),
          200,
        );
      }),
      env: AppEnv.current,
    );

RideSnapshot _snap(String rideId, RideStatus status) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test(
    'Waiting: stale is its own outcome; nothing committed or re-sent',
    () async {
      final posts = <String>[];
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.driverArriving, id: 'v1');
      await RideSnapshotStore.save(_snap('v1', RideStatus.driverArriving));

      final outcome = await ActiveRideController(
        api: _staleServer(posts),
      ).markCancelled(reasonId: 'plans_changed');

      expect(outcome, RideCancelOutcome.stale);
      expect(posts, ['/api/v1/rides/v1/cancel'], reason: 'sent once');
      expect(AppScope.instance.ride.status, RideStatus.driverArriving);
      expect(await RideSnapshotStore.read(), isNotNull);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
      expect(
        await PendingCancelStore.all(),
        isEmpty,
        reason: 'the outbox does not resend a refused cancel later',
      );
    },
  );

  test(
    'Finding: the search resumes and resyncs; the rider decides again',
    () async {
      final posts = <String>[];
      final realtime = _Realtime();
      addTearDown(realtime.dispose);
      final ride = RideSession()
        ..rideId = 'v1'
        ..status = RideStatus.findingDriver;
      final store = FindingDriverRepository();
      await store.save(_snap('v1', RideStatus.findingDriver));
      final controller = FindingDriverController(
        realtime: realtime,
        ride: ride,
        store: store,
        api: _staleServer(posts, status: 'searching'),
      );
      addTearDown(controller.dispose);
      final terminal = <RideStatus>[];
      controller.start(
        snapshot: _snap('v1', RideStatus.findingDriver),
        onTick: (_) {},
        onMatched: () {},
        onTerminal: terminal.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await controller.cancelSearch(), SearchCancelResult.stale);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(posts, ['/api/v1/rides/v1/cancel']);
      expect(controller.cancelled, isFalse);
      expect(controller.cancelQueued, isFalse);
      expect(terminal, isEmpty);
      expect(realtime.resyncs, ['v1']);
      expect(await PendingCancelStore.all(), isEmpty);
      expect(await RideSnapshotStore.read(), isNotNull);
    },
  );
}
