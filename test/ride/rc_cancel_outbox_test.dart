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
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RC-02 / RC-03: the pending-cancel outbox keeps which command the rider
/// sent, a queued cancel is not committed before the server confirms it,
/// and a refusal for a ride that is still live is reported, not dropped.
class _Realtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> events =
      StreamController<RideRealtimeEvent>.broadcast();

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

ApiClient _offline() => ApiClient(
  client: MockClient((_) async => throw http.ClientException('offline')),
  env: AppEnv.current,
);

/// A server that refuses every command with [status] and reports the ride
/// at [rideStatus] (bare projection when [bare]).
ApiClient _refusing(
  int status, {
  String rideStatus = 'accepted',
  bool bare = false,
  List<String>? paths,
}) => ApiClient(
  client: MockClient((request) async {
    paths?.add('${request.method} ${request.url.path}');
    if (request.method == 'GET') {
      final ride = {'tripId': 'r1', 'status': rideStatus, 'version': 4};
      return http.Response(jsonEncode(bare ? ride : {'ride': ride}), 200);
    }
    return http.Response(jsonEncode({'code': 'invalid_transition'}), status);
  }),
  env: AppEnv.current,
);

ApiClient _accepting(List<String> paths) => ApiClient(
  client: MockClient((request) async {
    paths.add(request.url.path);
    return http.Response(jsonEncode({'code': 'OK'}), 200);
  }),
  env: AppEnv.current,
);

RideSnapshot _snap(String rideId) => RideSnapshot(
  status: RideStatus.findingDriver,
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

  group('RC-02 the outbox keeps the command', () {
    test('an offline on-board end-early is flushed as end-early', () async {
      final ride = AppScope.instance.ride;
      ride.backendReconcile(RideStatus.tripInProgress, id: 'ride-9', version: 5);
      final outcome = await ActiveRideController(
        api: _offline(),
      ).markCancelled(reasonId: 'changed_plans');
      expect(outcome, RideCancelOutcome.pendingRetry);
      final queued = (await PendingCancelStore.all()).single;
      expect(queued.command, PendingCancelCommand.endEarly);

      final paths = <String>[];
      final results = await FindingDriverController.flushPendingCancels(
        api: _accepting(paths),
      );
      // R-O2: the trip is read again before the replay.
      expect(paths, ['/api/v1/rides/ride-9', '/api/v1/rides/ride-9/end-early']);
      expect(results['ride-9'], PendingCancelResult.sent);
      expect(await PendingCancelStore.all(), isEmpty);
    });

    test('an entry stored before the command existed flushes as cancel',
        () async {
      SharedPreferences.setMockInitialValues({
        'movera_pending_cancels': [
          jsonEncode({'rideId': 'old', 'reasonId': null, 'idempotencyKey': 'k'}),
        ],
      });
      final paths = <String>[];
      await FindingDriverController.flushPendingCancels(api: _accepting(paths));
      expect(paths, ['/api/v1/rides/old', '/api/v1/rides/old/cancel']);
    });

    test('a different command for the same ride gets its own key', () async {
      final first = await PendingCancelStore.enqueue(rideId: 'r');
      final again = await PendingCancelStore.enqueue(rideId: 'r');
      final ended = await PendingCancelStore.enqueue(
        rideId: 'r',
        command: PendingCancelCommand.endEarly,
      );
      expect(again.idempotencyKey, first.idempotencyKey);
      expect(ended.idempotencyKey, isNot(first.idempotencyKey));
      expect((await PendingCancelStore.all()).single.command,
          PendingCancelCommand.endEarly);
    });
  });

  group('RC-03 a refusal is not dropped silently', () {
    test('409 for a ride that is still live is reported as refused',
        () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'r1', idempotencyKey: 'k1'),
      );
      final reported = <PendingCancelOutcome>[];
      final sub = PendingCancelStore.outcomes.listen(reported.add);
      addTearDown(sub.cancel);
      final shown = <String>[];
      final waiting = ActiveRideController.queuedCancelRefusals.listen(
        shown.add,
      );
      addTearDown(waiting.cancel);
      final paths = <String>[];
      final results = await FindingDriverController.flushPendingCancels(
        api: _refusing(409, paths: paths),
      );
      await Future<void>.delayed(Duration.zero);
      expect(paths, [
        'GET /api/v1/rides/r1',
        'POST /api/v1/rides/r1/cancel',
        'GET /api/v1/rides/r1',
      ]);
      expect(results['r1'], PendingCancelResult.refused);
      expect(reported.single.result, PendingCancelResult.refused);
      expect(shown, ['r1']);
      expect(await PendingCancelStore.all(), isEmpty);
    });

    test('the re-read accepts a bare contract projection', () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'r1', idempotencyKey: 'k1'),
      );
      final results = await FindingDriverController.flushPendingCancels(
        api: _refusing(422, bare: true),
      );
      expect(results['r1'], PendingCancelResult.refused);
    });

    // rider-r4-24: a trip the server already closed (completed, expired,
    // cancelled by the driver or Movera) is `ended` with the server's
    // status, not `gone`, which was then filed as the rider's cancel.
    test('a refusal for a ride that already ended is ended', () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'r1', idempotencyKey: 'k1'),
      );
      final results = await FindingDriverController.flushPendingCancels(
        api: _refusing(409, rideStatus: 'completed'),
      );
      expect(results['r1'], PendingCancelResult.ended);
    });

    test('a queued cancel for an expired search reports how it ended',
        () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'r1', idempotencyKey: 'k1'),
      );
      final reported = <PendingCancelOutcome>[];
      final sub = PendingCancelStore.outcomes.listen(reported.add);
      addTearDown(sub.cancel);
      final paths = <String>[];
      final results = await FindingDriverController.flushPendingCancels(
        api: _refusing(409, rideStatus: 'expired', paths: paths),
      );
      await pumpEventQueue();
      expect(paths, ['GET /api/v1/rides/r1'], reason: 'nothing is sent');
      expect(results['r1'], PendingCancelResult.ended);
      expect(reported.single.endedAs, RideStatus.noDriverFound);
    });
  });

  group('RC-03 Finding: a queued cancel is not committed', () {
    late _Realtime rt;
    late RideSession ride;
    late FindingDriverController controller;
    final terminal = <RideStatus>[];
    var matched = 0;
    var refused = 0;

    Future<void> startOffline(String rideId) async {
      rt = _Realtime();
      ride = RideSession()
        ..rideId = rideId
        ..status = RideStatus.findingDriver;
      terminal.clear();
      matched = 0;
      refused = 0;
      final store = FindingDriverRepository();
      await store.save(_snap(rideId));
      controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: store,
        api: _offline(),
      );
      controller.start(
        snapshot: _snap(rideId),
        onTick: (_) {},
        onMatched: () => matched += 1,
        onTerminal: terminal.add,
        onCancelRefused: () => refused += 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await controller.cancelSearch(), SearchCancelResult.queued);
    }

    tearDown(() {
      controller.dispose();
      rt.dispose();
    });

    test('offline: the ride stays live and shows Cancelling…', () async {
      await startOffline('q1');
      expect(controller.cancelQueued, isTrue);
      expect(controller.cancelled, isFalse);
      expect(controller.copy, FindingDriverController.cancellingCopy);
      expect(ride.status, RideStatus.findingDriver);
      expect(await RideSnapshotStore.read(), isNotNull);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
      expect((await PendingCancelStore.all()).single.rideId, 'q1');
    });

    test('the server confirming it commits the cancel', () async {
      await startOffline('q2');
      rt.events.add(RideRealtimeEvent(
        rideId: 'q2',
        status: RideStatus.cancelledByRider,
        sequence: 5,
        version: 5,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.cancelled, isTrue);
      expect(terminal, [RideStatus.cancelledByRider]);
      expect(await RideSnapshotStore.read(), isNull);
      expect((await OnDemandRideHistoryStore.read()).single.status.name,
          'cancelled');
    });

    test('a sent outbox entry commits it too', () async {
      await startOffline('q3');
      PendingCancelStore.report(const PendingCancelOutcome(
        rideId: 'q3',
        command: PendingCancelCommand.cancel,
        result: PendingCancelResult.sent,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.cancelled, isTrue);
      expect(terminal, [RideStatus.cancelledByRider]);
    });

    test('a driver who accepted first wins; the stale cancel leaves the '
        'outbox', () async {
      await startOffline('q4');
      rt.events.add(RideRealtimeEvent(
        rideId: 'q4',
        status: RideStatus.driverAssigned,
        sequence: 3,
        version: 3,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.cancelled, isFalse);
      expect(controller.cancelQueued, isFalse);
      expect(refused, 1);
      expect(matched, 1);
      expect(await PendingCancelStore.all(), isEmpty);
    });

    test('a search the server ended is shown as it ended, not cancelled '
        '(rider-r4-24)', () async {
      await startOffline('q6');
      PendingCancelStore.report(const PendingCancelOutcome(
        rideId: 'q6',
        command: PendingCancelCommand.cancel,
        result: PendingCancelResult.ended,
        endedAs: RideStatus.noDriverFound,
      ));
      await pumpEventQueue();
      expect(controller.cancelled, isFalse);
      expect(terminal, [RideStatus.noDriverFound]);
      final filed = (await OnDemandRideHistoryStore.read()).single;
      expect(filed.cancellationReason, 'system_no_driver');
    });

    test('a refused flush resumes the search and tells the rider', () async {
      await startOffline('q5');
      PendingCancelStore.report(const PendingCancelOutcome(
        rideId: 'q5',
        command: PendingCancelCommand.cancel,
        result: PendingCancelResult.refused,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.cancelQueued, isFalse);
      expect(controller.cancelled, isFalse);
      expect(refused, 1);
      expect(terminal, isEmpty);
    });
  });

  group('RC-03 cold restore waits for the server', () {
    Future<RideRestoreCoordinator> restoring(
      PendingCancelResult? answer,
    ) async {
      await RideSnapshotStore.save(_snap('rq'));
      await PendingCancelStore.enqueue(rideId: 'rq');
      return RideRestoreCoordinator(
        reader: RideSnapshotStore.read,
        resync: (_) async {},
        authRequired: () => false,
        flushCancel: (_) async => answer,
      );
    }

    test('no answer (offline): the search is restored, not archived',
        () async {
      final coordinator = await restoring(null);
      await coordinator.root();
      expect(coordinator.showing, RestoredSurface.finding);
      expect(await RideSnapshotStore.read(), isNotNull);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
    });

    test('refused: the live ride is restored', () async {
      final coordinator = await restoring(PendingCancelResult.refused);
      await coordinator.root();
      expect(coordinator.showing, RestoredSurface.finding);
      expect(await RideSnapshotStore.read(), isNotNull);
    });

    test('ended by the server: restored to show how, not archived as the '
        "rider's cancel (rider-r4-24)", () async {
      final coordinator = await restoring(PendingCancelResult.ended);
      await coordinator.root();
      expect(await RideSnapshotStore.read(), isNotNull);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
    });

    test('confirmed: Home, with the cancel archived', () async {
      final coordinator = await restoring(PendingCancelResult.sent);
      await coordinator.root();
      expect(coordinator.showing, RestoredSurface.home);
      expect(await RideSnapshotStore.read(), isNull);
      expect((await OnDemandRideHistoryStore.read()).single.status.name,
          'cancelled');
    });
  });
}
