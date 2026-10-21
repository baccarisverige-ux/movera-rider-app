// rider-u198: a Ride check the rider had answered came back when a ride
// screen resumed while its close was still queued behind a slow alert.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _answersPath = '/api/v1/safety/ridecheck/answers';

/// Holds the first Ride check answers request until [release].
class _SlowClient extends InProcessMockClient {
  final _gate = Completer<void>();
  bool _held = false;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == _answersPath && !_held) {
      _held = true;
      await _gate.future;
    }
    return super.send(request);
  }
}

void main() {
  late _SlowClient client;
  late RideCheckController rideCheck;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    client = _SlowClient();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
    );
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    );
    await safety.load();
    rideCheck = RideCheckController.forSafety(safety);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'r2'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3293, 18.0686),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
  });

  tearDown(() {
    client.release();
    rideCheck.dispose();
  });

  test(
    'an answered card does not come back while its close is queued',
    () async {
      expect(
        await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r2'),
        RideCheckOpenResult.shown,
      );
      await pumpEventQueue();
      final red = rideCheck.session!.rows.firstWhere((row) => row.red);
      rideCheck.chooseRow(red.id); // the alert waits on the slow network
      await pumpEventQueue();
      rideCheck.done();
      expect(rideCheck.session, isNull);

      // The trip's next screen mounts its Ride check layer.
      await rideCheck.resume('r2');
      expect(
        rideCheck.session,
        isNull,
        reason: 'the rider already answered this Ride check',
      );

      client.release();
      await rideCheck.settle();
      await pumpEventQueue();
      expect(rideCheck.session, isNull);
    },
  );
}
