import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/destination_search/data/place_suggestion_repository.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'safety/safety_test.dart' show TestSafetyRecorder;

/// In front of the in-process backend: the next PATCH reaches the server,
/// then its answer is lost (a client timeout), as in
/// audit_fix_route_change_idempotency_test.
class _LosesNextPatch extends http.BaseClient {
  _LosesNextPatch(this.inner);
  final InProcessMockClient inner;
  bool loseNext = true;
  int patches = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH') {
      patches++;
      if (loseNext) {
        loseNext = false;
        await (await inner.send(request)).stream.drain<void>();
        throw TimeoutException('client gave up');
      }
    }
    return inner.send(request);
  }
}

/// Wave 5 R5.2 parts a+b: messages that claim success they did not get.
void main() {
  testWidgets(
      'rider-u24: a stationary driver\'s newer fix is delivered, not dropped',
      (tester) async {
    final t0 = DateTime.utc(2026, 10, 21, 9);
    var poll = 0;
    // Same version, updatedAt, status and coordinates; only measuredAt moves.
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tripId': 'trip-1',
                'status': 'arrived',
                'version': 4,
                'updatedAt': t0.toIso8601String(),
                'driverLocation': {
                  'lat': 59.33,
                  'lng': 18.06,
                  'measuredAt':
                      t0.add(Duration(seconds: 5 * poll++)).toIso8601String(),
                },
              }),
              200,
            )),
        env: AppEnv.current,
      ),
      pollInterval: const Duration(seconds: 2),
    );
    addTearDown(rt.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('trip-1').listen(events.add);
    addTearDown(sub.cancel);
    await tester.pump();
    await rt.reconnectAndResync('trip-1');
    await tester.pump();

    expect(events, hasLength(2), reason: 'the second fix is fresh');
    expect(events.last.locationAt!.isAfter(events.first.locationAt!), isTrue);
    rt.dispose();
  });

  test('rider-u35: completion keeps an open Ride check card\'s recording',
      () async {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final recorder = TestSafetyRecorder()..permissionGranted = true;
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    SafetyController.sharedForTest = safety;
    final rideCheck = RideCheckController.forSafety(safety);
    RideCheckController.sharedForTest = rideCheck;
    addTearDown(() {
      RideCheckController.sharedForTest = null;
      SafetyController.sharedForTest = null;
      rideCheck.dispose();
    });
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'r1'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3293, 18.0686),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
    await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1');
    await rideCheck.toggleRecording();
    expect(rideCheck.recording, isTrue);
    AppScope.instance.ride
      ..rideId = 'r1'
      ..status = RideStatus.tripInProgress;

    await ActiveRideController().markCompleted(RideStatus.tripCompleted);
    await pumpEventQueue();

    expect(rideCheck.recording, isTrue,
        reason: 'the card on the summary still offers Stop');
    expect(recorder.stops, 0);
  });

  test('rider-u82: a failed autocomplete is an error, not "no address"',
      () async {
    final offline = PlaceSuggestionRepository(ApiClient(
      client: MockClient((_) async => throw http.ClientException('offline')),
      env: AppEnv.current,
    ));
    // The picker shows "No address found" only for an empty answer.
    await expectLater(offline.suggest('Kungsgatan 4'), throwsA(anything));
  });

  test('rider-u97: a raise whose answer was lost is adopted, not "failed"',
      () async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    final server = InProcessMockClient();
    server.rides['r52-raise'] = {
      'id': 'r52-raise',
      'status': 'findingDriver',
      'pickupAddress': 'Sergels torg 1',
      'pickupLat': 59.3326,
      'pickupLng': 18.0649,
      'destinationAddress': 'Odenplan 2',
      'destinationLat': 59.3426,
      'destinationLng': 18.0498,
      'price': 200.0,
      'bookedPrice': 200.0,
      'stops': <Map<String, dynamic>>[],
      'version': 1,
    };
    final backend = _LosesNextPatch(server);
    final api = ApiClient(client: backend);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    final finding = FindingDriverController(
      realtime: realtime,
      ride: RideSession()..rideId = 'r52-raise',
      store: FindingDriverRepository(),
      priceBumpAfter: Duration.zero,
      api: api,
    );
    addTearDown(finding.dispose);
    finding.start(
      snapshot: RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'Sergels torg 1',
        destinationAddress: 'Odenplan 2',
        pickupLat: 59.3326,
        pickupLng: 18.0649,
        destinationLat: 59.3426,
        destinationLng: 18.0498,
        rideType: 'Movera',
        price: 200,
        paymentMethod: 'Apple Pay',
        rideId: 'r52-raise',
      ),
      onTick: (_) {},
      onMatched: () {},
    );

    final raised = await finding.confirmPriceIncreaseBy(const Money(2000));

    expect(finding.editFeedback, isNot(L10n.current.editOfferFailed));
    expect(raised, isTrue);
    expect(finding.currentPrice, 220, reason: 'the fare the server applied');
    expect(backend.patches, 2);
  });
}
