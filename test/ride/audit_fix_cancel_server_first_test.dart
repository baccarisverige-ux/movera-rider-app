import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RIDE-4: Finding's cancel waits for the server. A 409 ("a driver already
/// accepted") must not be dropped while the rider is sent Home.
class _CancelGate extends http.BaseClient {
  _CancelGate(this.inner);

  final InProcessMockClient inner;
  Completer<http.StreamedResponse>? gate;
  int posts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
      posts += 1;
      final pending = gate;
      if (pending != null) return pending.future;
    }
    return inner.send(request);
  }
}

http.StreamedResponse _conflict() => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode({'code': 'CONFLICT'}))),
  409,
  headers: {'content-type': 'application/json'},
);

http.StreamedResponse _ok() => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode({'code': 'OK'}))),
  200,
  headers: {'content-type': 'application/json'},
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

  late InProcessMockClient server;
  late _CancelGate client;
  late ApiClient api;
  late MockRideRealtime rt;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    server = InProcessMockClient();
    client = _CancelGate(server);
    api = ApiClient(client: client);
    rt = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
  });

  tearDown(() => rt.dispose());

  Future<FindingDriverController> start(
    String rideId,
    RideSession ride, {
    void Function()? onMatched,
  }) async {
    server.rides[rideId] = {'id': rideId, 'status': 'findingDriver'};
    final store = FindingDriverRepository();
    await store.save(_snap(rideId));
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: store,
      api: api,
    );
    controller.start(
      snapshot: _snap(rideId),
      onTick: (_) {},
      onMatched: onMatched ?? () {},
    );
    return controller;
  }

  test('nothing is committed until the server answers', () async {
    final ride = RideSession()..rideId = 'sf-wait';
    final controller = await start('sf-wait', ride);
    client.gate = Completer<http.StreamedResponse>();

    final cancelling = controller.cancelSearch();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.cancelInFlight, isTrue);
    expect(ride.status, RideStatus.findingDriver);
    expect(await RideSnapshotStore.read(), isNotNull);
    // The intent is already in the outbox with its key.
    expect(
      (await PendingCancelStore.find('sf-wait'))?.idempotencyKey,
      isNotNull,
    );

    client.gate!.complete(_ok());
    expect(await cancelling, SearchCancelResult.confirmed);
    expect(ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    expect(await PendingCancelStore.all(), isEmpty);
    controller.dispose();
  });

  test('409 commits nothing and lets the racing match through', () async {
    final ride = RideSession()..rideId = 'sf-409';
    var matches = 0;
    final controller = await start(
      'sf-409',
      ride,
      onMatched: () => matches += 1,
    );
    client.gate = Completer<http.StreamedResponse>();

    final cancelling = controller.cancelSearch();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // A driver accepts while the cancel is on its way.
    rt.emit(RideStatus.driverAssigned, sequence: 5);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(matches, 0, reason: 'the match waits for the cancel answer');

    client.gate!.complete(_conflict());
    expect(await cancelling, SearchCancelResult.driverAccepted);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(matches, 1);
    expect(controller.matchCount, 1);
    expect(ride.status, RideStatus.driverAssigned);
    expect(await OnDemandRideHistoryStore.read(), isEmpty);
    expect(await PendingCancelStore.all(), isEmpty);
    expect((await RideSnapshotStore.read())?.status, RideStatus.driverAssigned);
    controller.dispose();
  });

  test('a confirmed cancel drops a match that raced it', () async {
    final ride = RideSession()..rideId = 'sf-ok';
    var matches = 0;
    final controller = await start(
      'sf-ok',
      ride,
      onMatched: () => matches += 1,
    );
    final cancelling = controller.cancelSearch();
    rt.emit(RideStatus.driverAssigned, sequence: 5);
    expect(await cancelling, SearchCancelResult.confirmed);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(matches, 0);
    expect(ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    controller.dispose();
  });

  test(
    'the reason sent afterwards updates History and the server once',
    () async {
      final ride = RideSession()..rideId = 'sf-reason';
      final controller = await start('sf-reason', ride);
      expect(await controller.cancelSearch(), SearchCancelResult.confirmed);
      expect(client.posts, 1);

      await controller.sendCancelReason('plans_changed');
      // Owner decision 6: POST /trips/{id}/cancel-reason, no second /cancel.
      expect(client.posts, 1);
      expect(
        (server.rides['sf-reason']!['cancellation'] as Map)['reasonCode'],
        'plans_changed',
      );

      final history = await OnDemandRideHistoryStore.read();
      expect(history, hasLength(1));
      expect(history.single.cancellationReason, 'plans_changed');
      expect(server.rides['sf-reason']!['cancellationReason'], 'plans_changed');
      expect(server.rides['sf-reason']!['status'], 'cancelled_by_rider');
      expect(ride.status, RideStatus.cancelledByRider);
      controller.dispose();
    },
  );
}
