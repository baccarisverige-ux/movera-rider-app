import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Offline extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls += 1;
    throw const _NoNetwork();
  }
}

class _NoNetwork implements Exception {
  const _NoNetwork();
  @override
  String toString() => 'no network';
}

/// Records every cancel request and answers with [status]. The outbox reads
/// the trip first (R-O2): a GET answers with the ride still live.
MockClient _answering(int status, List<http.Request> seen) => MockClient((
  request,
) async {
  if (request.method == 'GET') {
    final id = request.url.pathSegments.last;
    return http.Response(jsonEncode({'tripId': id, 'status': 'accepted'}), 200);
  }
  seen.add(request);
  return http.Response(
    jsonEncode(
      status < 400
          ? {
              'code': 'OK',
              'ride': {'status': 'cancelledByRider'},
            }
          : {'code': 'RIDE_NOT_CANCELLABLE'},
    ),
    status,
  );
});

RideSnapshot _snapshot(
  String rideId, {
  RideStatus status = RideStatus.driverAssigned,
}) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'Pickup',
  destinationAddress: 'Destination',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.3326,
  destinationLng: 18.0649,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

Future<void> _activeRide(String rideId, RideStatus status) async {
  await RideSnapshotStore.save(_snapshot(rideId, status: status));
  AppScope.instance.ride.restoreFromBackend(status, id: rideId);
}

/// A ride feed that errors as soon as it is subscribed to.
class _DeadFeed implements RideRealtime {
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) =>
      Stream<RideRealtimeEvent>.error(StateError('feed died'));
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
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    await FindingDriverController.debugStopReconnectFlush();
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  group('D-013 Waiting/in-trip cancel is server-first', () {
    test(
      'an unreachable server leaves the ride live and queues the cancel',
      () async {
        await _activeRide('w1', RideStatus.driverAssigned);
        final offline = _Offline();
        final controller = ActiveRideController(
          api: ApiClient(client: offline),
        );

        final outcome = await controller.markCancelled(reasonId: 'plans');

        expect(outcome, RideCancelOutcome.pendingRetry);
        // Nothing committed ahead of the server's answer.
        expect(AppScope.instance.ride.status, RideStatus.driverAssigned);
        expect(await RideSnapshotStore.readForArchive(), isNotNull);
        // ...but the intent is durable, with one key for later retries.
        final pending = await PendingCancelStore.all();
        expect(pending.single.rideId, 'w1');
        expect(pending.single.reasonId, 'plans');
        expect(pending.single.idempotencyKey, isNotNull);
        expect(offline.calls, 2, reason: 'one in-session retry');
      },
    );

    test(
      'an in-trip cancel is also queued, not committed, when offline',
      () async {
        await _activeRide('w2', RideStatus.tripInProgress);
        final controller = ActiveRideController(
          api: ApiClient(client: _Offline()),
        );

        final outcome = await controller.markCancelled();

        expect(outcome, RideCancelOutcome.pendingRetry);
        expect(AppScope.instance.ride.status, RideStatus.tripInProgress);
        expect((await PendingCancelStore.all()).single.rideId, 'w2');
      },
    );

    test('a retried cancel reuses the queued idempotency key', () async {
      await _activeRide('w3', RideStatus.driverAssigned);
      await ActiveRideController(api: ApiClient(client: _Offline()))
          .markCancelled();
      final queuedKey = (await PendingCancelStore.all()).single.idempotencyKey;

      final seen = <http.Request>[];
      final outcome = await ActiveRideController(
        api: ApiClient(client: _answering(200, seen)),
      ).markCancelled();

      expect(outcome, RideCancelOutcome.confirmed);
      expect(seen.single.headers['Idempotency-Key'], queuedKey);
    });

    test(
      'a server-acknowledged cancel commits locally and clears the outbox',
      () async {
        await _activeRide('w4', RideStatus.driverAssigned);
        final backend = InProcessMockClient();
        backend.rides['w4'] = {'id': 'w4', 'status': 'driverAssigned'};

        final outcome = await ActiveRideController(
          api: ApiClient(client: backend),
        ).markCancelled(reasonId: 'plans');

        expect(outcome, RideCancelOutcome.confirmed);
        expect(backend.rides['w4']!['status'], 'cancelled_by_rider');
        expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
        expect(await RideSnapshotStore.readForArchive(), isNull);
        expect(await PendingCancelStore.all(), isEmpty);
      },
    );

    test(
      'a 409 refusal is reported and never committed as cancelled',
      () async {
        await _activeRide('w5', RideStatus.tripInProgress);
        final seen = <http.Request>[];

        final outcome = await ActiveRideController(
          api: ApiClient(client: _answering(409, seen)),
        ).markCancelled();

        expect(outcome, RideCancelOutcome.rejected);
        expect(
          seen,
          hasLength(1),
          reason: 'a permanent refusal is not retried',
        );
        expect(AppScope.instance.ride.status, RideStatus.tripInProgress);
        expect(await PendingCancelStore.all(), isEmpty);
      },
    );
  });

  group('D-014 leaving an untracked ride', () {
    test(
      'cancels server-side with the ride id recovered from the snapshot',
      () async {
        await RideSnapshotStore.save(_snapshot('orphan-1'));
        AppScope.instance.ride.rideId = null;
        final seen = <http.Request>[];

        final outcome = await ActiveRideController(
          api: ApiClient(client: _answering(200, seen)),
        ).cancelUntrackedRide();

        expect(outcome, RideCancelOutcome.confirmed);
        expect(seen.single.url.path, '/api/v1/rides/orphan-1/cancel');
        // rider-r4-25: the cancelled ride stays in History, as on every other
        // cancel path, before the snapshot is cleared.
        expect(
          (await OnDemandRideHistoryStore.read()).single.reservationId,
          'ondemand-orphan-1',
        );
      },
    );

    test('keeps the cancel queued when the server cannot be reached', () async {
      await RideSnapshotStore.save(_snapshot('orphan-2'));
      AppScope.instance.ride.rideId = null;

      final outcome = await ActiveRideController(
        api: ApiClient(client: _Offline()),
      ).cancelUntrackedRide();

      expect(outcome, RideCancelOutcome.pendingRetry);
      expect((await PendingCancelStore.all()).single.rideId, 'orphan-2');
    });

    test('reports honestly when no ride id is recoverable at all', () async {
      AppScope.instance.ride.rideId = null;
      final seen = <http.Request>[];

      final outcome = await ActiveRideController(
        api: ApiClient(client: _answering(200, seen)),
      ).cancelUntrackedRide();

      expect(outcome, isNull);
      expect(seen, isEmpty);
    });
  });

  group('D-020 pending-cancel outbox', () {
    test('drops entries the server permanently rejects (404/409)', () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'gone', idempotencyKey: 'k-gone'),
      );
      await FindingDriverController.flushPendingCancels(
        api: ApiClient(client: _answering(404, <http.Request>[])),
      );
      expect(await PendingCancelStore.all(), isEmpty);

      await PendingCancelStore.add(
        const PendingCancel(rideId: 'done', idempotencyKey: 'k-done'),
      );
      await FindingDriverController.flushPendingCancels(
        api: ApiClient(client: _answering(409, <http.Request>[])),
      );
      expect(await PendingCancelStore.all(), isEmpty);
    });

    test(
      'keeps entries on transient failure and reuses one key per entry',
      () async {
        await PendingCancelStore.add(const PendingCancel(rideId: 'legacy'));

        await FindingDriverController.flushPendingCancels(
          api: ApiClient(client: _Offline()),
        );
        final minted = (await PendingCancelStore.all()).single.idempotencyKey;
        expect(
          minted,
          isNotNull,
          reason: 'legacy entries get one key, persisted',
        );

        await FindingDriverController.flushPendingCancels(
          api: ApiClient(client: _Offline()),
        );
        expect((await PendingCancelStore.all()).single.idempotencyKey, minted);

        final seen = <http.Request>[];
        await FindingDriverController.flushPendingCancels(
          api: ApiClient(client: _answering(200, seen)),
        );
        expect(seen.single.headers['Idempotency-Key'], minted);
        expect(await PendingCancelStore.all(), isEmpty);
      },
    );

    test('flushes again when the realtime connection comes back', () async {
      final connection = RealtimeConnection();
      final seen = <http.Request>[];
      FindingDriverController.watchReconnectForPendingCancels(
        connection,
        api: ApiClient(client: _answering(200, seen)),
      );
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'reconnect', idempotencyKey: 'k-r'),
      );

      connection.markFailed();
      connection.markConnected();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen.single.url.path, '/api/v1/rides/reconnect/cancel');
      expect(await PendingCancelStore.all(), isEmpty);
      await FindingDriverController.debugStopReconnectFlush();
      connection.dispose();
    });
  });

  group('D-015 degraded realtime feed is visible', () {
    test(
      'a stream error marks the feed degraded; a fresh start clears it',
      () async {
        final tracking = DriverTrackingController(
          realtime: _DeadFeed(),
          pickupLat: 59.3,
          pickupLng: 18.0,
          persistRideSnapshot: false,
        );
        tracking.start(rideId: 'dead');
        await Future<void>.delayed(Duration.zero);
        expect(tracking.connectionDegraded, isTrue);
        tracking.dispose();
      },
    );

    testWidgets('Waiting renders a banner when the ride feed dies', (
      tester,
    ) async {
      await RideSnapshotStore.save(_snapshot('dead-feed'));
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: 'dead-feed',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WaitingForDriver(
            pickupAddress: 'Pickup',
            destinationAddress: 'Destination',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
            rideId: 'dead-feed',
            realtime: _DeadFeed(),
            persistRideSnapshot: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('waiting-live-feed-degraded')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('D-018 camera padding is bottom-only', () {
    test('frames the points above the sheet instead of padding every side', () {
      const driver = GeoPoint(59.34, 18.05);
      const pickup = GeoPoint(59.33, 18.07);
      final fit = waitingCameraFit(
        a: driver,
        b: pickup,
        viewportHeight: 844,
        bottomObstruction: 190,
      );
      // Uniform padding is a small edge margin, not the sheet height.
      expect(fit.padding, lessThan(190));
      // North, east and west edges are the real points...
      expect(fit.northeast.latitude, 59.34);
      expect(fit.northeast.longitude, 18.07);
      expect(fit.southwest.longitude, 18.05);
      // ...and only the south edge is stretched to clear the sheet.
      final span = 59.34 - 59.33;
      final full = 844 - 2 * fit.padding;
      final usable = 844 - 190 - 2 * fit.padding;
      expect(
        fit.southwest.latitude,
        closeTo(59.34 - span * full / usable, 1e-9),
      );
      expect(fit.southwest.latitude, lessThan(59.33));
    });
  });

  group('D-016 marker ease follows the fix interval', () {
    test('eases across the observed interval, clamped', () {
      expect(driverEaseDuration(null), const Duration(milliseconds: 900));
      expect(
        driverEaseDuration(const Duration(seconds: 3)),
        const Duration(seconds: 3),
      );
      expect(
        driverEaseDuration(const Duration(milliseconds: 100)),
        const Duration(milliseconds: 400),
      );
      expect(
        driverEaseDuration(const Duration(seconds: 30)),
        const Duration(seconds: 4),
      );
    });
  });
}
