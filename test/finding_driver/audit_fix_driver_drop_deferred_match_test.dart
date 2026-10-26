import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 2026-10-21 (rider-32): a driver who accepts and drops the ride while
/// Finding still waits for an edit's answer (a raised offer, a moved pickup)
/// is a reversible dispatch event. Finding used to file the ride as
/// cancelled, clear the snapshot and send the rider Home while the server
/// trip was searching again.
class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast();
  int researches = 0;
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
  void researchAfterDriverCancel() => researches += 1;
  @override
  void dispose() => c.close();
}

/// Holds the pickup PATCH until the test answers it.
class _EditGate extends http.BaseClient {
  Completer<http.StreamedResponse>? pending;
  bool get inFlight => pending != null;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'PATCH') {
      final completer = Completer<http.StreamedResponse>();
      pending = completer;
      return completer.future;
    }
    return Future.value(
      _json(200, {'tripId': 'drop-deferred', 'status': 'searching'}),
    );
  }

  void answer(int status, Map<String, Object?> body) {
    final completer = pending!;
    pending = null;
    completer.complete(_json(status, body));
  }

  static http.StreamedResponse _json(int status, Map<String, Object?> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rideId = 'drop-deferred';
  const driver = MatchedDriver(id: 'drv-1', firstName: 'Ali');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  RideSnapshot snapshot() => RideSnapshot(
    status: RideStatus.findingDriver,
    savedAt: DateTime.now(),
    searchStartedAt: DateTime.now(),
    pickupAddress: 'Stockholm Central',
    destinationAddress: 'Arlanda Airport',
    pickupLat: 59.33,
    pickupLng: 18.059,
    destinationLat: 59.6519,
    destinationLng: 17.9186,
    rideType: 'Movera',
    price: 349,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
  );

  RideRealtimeEvent event(
    RideStatus status,
    int sequence, {
    RealtimeKind? kind,
  }) => RideRealtimeEvent(
    tripId: rideId,
    status: status,
    sequence: sequence,
    version: sequence,
    kind: kind,
    driver: status.isMatched ? driver : null,
    serverTime: DateTime.utc(2026, 10, 23, 9, sequence),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a driver drop during a deferred match keeps the search', (
    tester,
  ) async {
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    final gate = _EditGate();
    final api = ApiClient(client: gate);
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    final controller = FindingDriverController(realtime: realtime, api: api);
    var matched = 0;
    RideStatus? terminal;
    controller.start(
      snapshot: snapshot(),
      onTick: (_) {},
      onMatched: () => matched += 1,
      onTerminal: (status) => terminal = status,
    );
    await settle(tester);
    await RideSnapshotStore.save(snapshot());

    // The rider moves the pickup; the PATCH is out.
    unawaited(
      controller.updatePickup(
        address: 'Stockholm Odenplan',
        latitude: 59.343,
        longitude: 18.05,
      ),
    );
    for (var i = 0; i < 20 && !gate.inFlight; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(gate.inFlight, isTrue, reason: 'the pickup edit is in flight');

    // A driver accepts (the match is deferred behind the edit) and drops.
    realtime.c.add(event(RideStatus.driverAssigned, 2));
    await settle(tester);
    expect(matched, 0, reason: 'the match waits for the edit answer');
    realtime.c.add(
      event(
        RideStatus.cancelledByDriver,
        3,
        kind: RealtimeKind.driverCancelled,
      ),
    );
    await settle(tester);

    expect(terminal, isNull, reason: 'a driver drop does not end the ride');
    expect(
      identical(FindingDriverController.active, controller),
      isTrue,
      reason: 'the search still owns the ride',
    );
    expect(
      await RideSnapshotStore.read(),
      isNotNull,
      reason: 'the ride snapshot is kept for the next driver',
    );
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    expect(controller.matchCount, 0);
    expect(controller.matchedDriver, isNull);
    expect(realtime.researches, 1, reason: 'dispatch is asked to look again');

    // The edit answer arrives: no stale match completes from it.
    gate.answer(200, {'tripId': rideId, 'status': 'searching', 'version': 4});
    await settle(tester);
    expect(matched, 0);
    expect(controller.matchCount, 0);

    // The next driver accepts: the gate did not seal the feed.
    realtime.c.add(event(RideStatus.driverAssigned, 5));
    await settle(tester);
    expect(matched, 1, reason: 'the next match completes');
    expect(controller.matchCount, 1);
    expect(terminal, isNull);

    controller.dispose();
    await tester.pump(const Duration(seconds: 15));
  });
}
