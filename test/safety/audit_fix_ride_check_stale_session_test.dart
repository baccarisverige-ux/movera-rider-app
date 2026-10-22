// rider-u194: a Ride check left open when its trip ended without a
// completion screen (admin cancel, failed) stayed the session for good, so
// no later trip could open a Ride check until the app restarted.
import 'package:flutter_test/flutter_test.dart';
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

const _pickup = GeoPoint(59.3293, 18.0686);
const _destination = GeoPoint(59.3600, 18.0000);
const _plan = RideCheckPlan(pickup: _pickup, destination: _destination);

GeoPoint _north(GeoPoint from, double meters) =>
    GeoPoint(from.latitude + meters / 111320, from.longitude);

final _t0 = DateTime.utc(2026, 10, 15, 14, 0);

void main() {
  late RideCheckController rideCheck;

  setUp(() async {
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
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    );
    await safety.load();
    rideCheck = RideCheckController.forSafety(safety);
    RideCheckController.tripMonitoring = true;
  });

  tearDown(() {
    rideCheck.dispose();
    RideCheckController.tripMonitoring = false;
  });

  test(
    'a card left open on an ended trip does not block the next trip',
    () async {
      rideCheck.attachTrip(const RideCheckTripContext(rideId: 'x'), _plan);
      expect(
        await rideCheck.open(RideCheckTrigger.longStop, rideId: 'x'),
        RideCheckOpenResult.shown,
      );
      // The admin cancels ride x; the rider lands on Home with the card
      // unanswered. Ride y starts in the same app session.
      rideCheck.detachTrip('x');
      rideCheck.attachTrip(const RideCheckTripContext(rideId: 'y'), _plan);
      await rideCheck.resume('y');

      final stopAt = _north(_pickup, 2000);
      for (var s = 0; s <= 130; s += 5) {
        rideCheck.addSample(
          'y',
          RideCheckSample(
            point: stopAt,
            at: _t0.add(Duration(seconds: s)),
          ),
        );
      }
      await pumpEventQueue();
      expect(rideCheck.sessionFor('y'), isNotNull);
      expect(rideCheck.sessionFor('y')!.trigger, RideCheckTrigger.longStop);
      expect(rideCheck.blocks('x'), isFalse);
    },
  );

  test('the same trip coming back keeps its open card', () async {
    rideCheck.attachTrip(const RideCheckTripContext(rideId: 'x'), _plan);
    await rideCheck.open(RideCheckTrigger.longStop, rideId: 'x');
    rideCheck.detachTrip('x');
    rideCheck.attachTrip(const RideCheckTripContext(rideId: 'x'), _plan);
    expect(rideCheck.sessionFor('x'), isNotNull);
    expect(
      await rideCheck.open(RideCheckTrigger.offRoute, rideId: 'x'),
      RideCheckOpenResult.busy,
    );
  });
}
