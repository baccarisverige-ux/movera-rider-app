import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import 'safety/safety_test.dart' show TestSafetyRecorder;

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
}
