import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u56: the 15-second stillness check was meant to run only "while
/// the live feed is up", gated on DriverTrackingController.connectionDegraded.
/// The polling transport never sets that flag (a failed poll only marks the
/// shared connection failed and backs off), so when the rider's own phone
/// lost network mid-trip, no fixes arrived, the time since the last fix
/// counted as a stop, and after longStopMinutes the "long stop" Ride check
/// opened though the car was driving.
const _pickup = LatLng(59.3293, 18.0686);
const _destination = LatLng(59.3626, 18.0649);

RideSnapshot _snapshot(String rideId) => RideSnapshot(
  status: RideStatus.driverAssigned,
  savedAt: DateTime.now(),
  pickupAddress: 'Stockholm pickup',
  destinationAddress: 'Solna centrum, 171 45 Solna',
  pickupLat: _pickup.latitude,
  pickupLng: _pickup.longitude,
  destinationLat: _destination.latitude,
  destinationLng: _destination.longitude,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late SafetyController safety;
  late RideCheckController rideCheck;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
    AppScope.instance.realtime.markConnected();
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    safety = SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      ),
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    );
    SafetyController.sharedForTest = safety;
    now = DateTime.now();
    rideCheck = RideCheckController(
      service: safety.rideCheck,
      emergency: safety.emergency,
      audio: safety.audio,
      clock: () => now,
    );
    RideCheckController.sharedForTest = rideCheck;
    RideCheckController.tripMonitoring = true;
  });

  tearDown(() {
    RideCheckController.tripMonitoring = false;
    RideCheckController.sharedForTest = null;
    rideCheck.dispose();
    SafetyController.sharedForTest = null;
    AppScope.instance.realtime.markConnected();
  });

  /// Waiting in trip, the car 1 km past the pickup on the shared transport.
  Future<MockRideRealtime> pumpInTrip(
    WidgetTester tester,
    String rideId,
  ) async {
    await RideSnapshotStore.save(_snapshot(rideId));
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: rideId,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Solna centrum, 171 45 Solna',
          pickupPosition: _pickup,
          destinationPosition: _destination,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    realtime.holdAssignment();
    for (final step in [
      RideStatus.driverArriving,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
    ]) {
      realtime.emit(
        step,
        latitude: _pickup.latitude + 0.01,
        longitude: _pickup.longitude,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    return realtime;
  }

  testWidgets('no "long stop" while the rider\'s own connection is down', (
    tester,
  ) async {
    const rideId = 'rc-offline-no-stop';
    await pumpInTrip(tester, rideId);

    // The phone loses network: no more fixes, the shared connection fails.
    AppScope.instance.realtime.markFailed();
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 16));
    expect(rideCheck.session, isNull, reason: 'offline is not a stop');

    // Back online: the stop clock starts again from here.
    AppScope.instance.realtime.markConnected();
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 16));
    expect(rideCheck.session, isNull);

    // A real stop after that still opens Ride check.
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 16));
    expect(rideCheck.session?.trigger, RideCheckTrigger.longStop);
    await tester.pumpWidget(const SizedBox());
  });
}
