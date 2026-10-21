// rider-u192: a trigger detected while another Ride check card was up was
// used up by the monitor and then dropped (open() said busy), so it was
// never shown, saved or posted. It now waits and opens once the card closes.
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
  late SafetyStore store;
  late RideCheckController rideCheck;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    store = SafetyStore(
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

  test('dropped far at trip end while the long-stop card is unanswered opens '
      'once the rider answers', () async {
    rideCheck.attachTrip(const RideCheckTripContext(rideId: 'r1'), _plan);
    final stopAt = _north(_pickup, 2000);
    for (var s = 0; s <= 130; s += 5) {
      rideCheck.addSample(
        'r1',
        RideCheckSample(
          point: stopAt,
          at: _t0.add(Duration(seconds: s)),
        ),
      );
    }
    await pumpEventQueue();
    expect(rideCheck.session?.trigger, RideCheckTrigger.longStop);

    // The driver finishes 3.6 km from the drop-off; the card is still up.
    await rideCheck.tripEnded('r1', _north(_destination, 3600));
    expect(rideCheck.session?.trigger, RideCheckTrigger.longStop);

    rideCheck.imOk();
    await rideCheck.settle();
    final next = rideCheck.session;
    expect(next, isNotNull, reason: 'the dropped-far check must not be lost');
    expect(next!.trigger, RideCheckTrigger.droppedFar);
    expect(next.rideId, 'r1');
    expect(next.reason.distanceMeters, greaterThan(3000));

    // Its safety event reaches the trip and the server.
    await rideCheck.settle();
    final events = await store.cachedRideCheckEvents('r1');
    expect(
      events.map((event) => event.payload['trigger']),
      contains(RideCheckTrigger.droppedFar.wire),
    );
  });
}
