// rider-u217: "Automatically share every ride" could be switched on and
// Safety showed "Every ride", but nothing started a share when a ride
// started. The trip screen now starts it once when the trip begins.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pickup = LatLng(59.3293, 18.0686);
const _destination = LatLng(59.3326, 18.0649);

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
  late List<String> pushed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
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
    rideCheck = RideCheckController.forSafety(safety);
    RideCheckController.sharedForTest = rideCheck;
    RideCheckController.tripMonitoring = true;
  });

  tearDown(() {
    RideCheckController.tripMonitoring = false;
    RideCheckController.sharedForTest = null;
    rideCheck.dispose();
    SafetyController.sharedForTest = null;
  });

  Future<MockRideRealtime> pumpInTrip(
    WidgetTester tester,
    String rideId,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await RideSnapshotStore.save(_snapshot(rideId));
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: rideId,
    );
    pushed = [];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [_PushLog(pushed)],
          home: const Scaffold(body: Center(child: Text('home root'))),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WaitingForDriver(
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
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
    ]) {
      realtime.emit(
        step,
        latitude: _pickup.latitude,
        longitude: _pickup.longitude,
      );
      await tester.pump();
      if (step == RideStatus.driverWaiting) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RiderInTripPanel), findsOneWidget);
    return realtime;
  }

  Future<void> frames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('auto share on: the trip starting shares it with the contacts', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await safety.load();
      await safety.addContact(
        name: 'Anna',
        phone: '0701234561',
        shareTrips: true,
      );
      await safety.setTripShare(enabled: true, mode: TripShareMode.auto);
    });
    const rideId = 'rc-auto-share';
    await pumpInTrip(tester, rideId);
    await frames(tester);
    final share = safetyMockForProcess().shares[rideId];
    expect(share, isNotNull, reason: 'the rider asked to share every ride');
    expect(share!['contactIds'], [safety.contacts.single.id]);
  });

  testWidgets('auto share off: the trip starting shares nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await safety.load();
      await safety.addContact(
        name: 'Anna',
        phone: '0701234561',
        shareTrips: true,
      );
      await safety.setTripShare(enabled: true, mode: TripShareMode.manual);
    });
    const rideId = 'rc-manual-share';
    await pumpInTrip(tester, rideId);
    await frames(tester);
    expect(safetyMockForProcess().shares[rideId], isNull);
  });
}

class _PushLog extends NavigatorObserver {
  _PushLog(this.log);

  final List<String> log;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    log.add(route.settings.name ?? route.runtimeType.toString());
  }
}
