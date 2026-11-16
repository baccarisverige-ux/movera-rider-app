// BQ-S10 round 2b (supervisor MF-R2): the trip screen itself drops the kept
// share link when it sees the trip's end. A booked ride's live page opens
// the trip screen with its own ride id and its own completed / terminal
// handlers (reservation_live_ride.dart), so the ride controller's end hook
// (`stopShareForRideEnd`, which looks at the Book Now ride only) never runs
// for it: the screen's drop is the only one. The stop request also fails
// here, so no other path can clear the link.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
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
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pickup = LatLng(59.3293, 18.0686);
const _destination = LatLng(59.3326, 18.0649);

/// The safety routes of the in-process server, except that a stop request
/// (DELETE …/share) fails while [fail] is set.
class _FailingStop extends http.BaseClient {
  _FailingStop(this.inner);

  final http.Client inner;
  bool fail = false;
  int refused = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (fail &&
        request.method == 'DELETE' &&
        request.url.path.endsWith('/share')) {
      refused++;
      throw http.ClientException('test: the stop request fails');
    }
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late SafetyController safety;
  late RideCheckController rideCheck;
  late _FailingStop client;
  late List<RideStatus> completed;
  late List<RideStatus> terminal;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    // The Book Now ride is not this ride (a booked ride's live page).
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
    client = _FailingStop(InProcessMockClient());
    safety = SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
      ),
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
    );
    SafetyController.sharedForTest = safety;
    rideCheck = RideCheckController.forSafety(safety);
    RideCheckController.sharedForTest = rideCheck;
    RideCheckController.tripMonitoring = true;
    completed = [];
    terminal = [];
  });

  tearDown(() {
    RideCheckController.tripMonitoring = false;
    RideCheckController.sharedForTest = null;
    rideCheck.dispose();
    SafetyController.sharedForTest = null;
  });

  Future<void> frames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Opens the trip screen like a booked ride's live page and drives it to
  /// [until], with a kept share link for [rideId].
  Future<MockRideRealtime> pumpBookedRide(
    WidgetTester tester,
    String rideId,
    List<RideStatus> until,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await safety.load();
      await safety.setTripShare(enabled: true, mode: TripShareMode.manual);
      await safety.shareLink(rideId);
    });
    expect(safety.shareFor(rideId)?.url, isNotNull, reason: 'a kept link');
    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Center(child: Text('home root'))),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Solna centrum, 171 45 Solna',
          pickupPosition: _pickup,
          destinationPosition: _destination,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          realtime: realtime,
          persistRideSnapshot: false,
          routeChangeSupported: false,
          onCompleted: (context, status) async => completed.add(status),
          onTerminal: (context, status) async => terminal.add(status),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    realtime.holdAssignment();
    for (final step in until) {
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
    expect(AppScope.instance.ride.rideId, isNot(rideId));
    expect(safety.shareFor(rideId)?.url, isNotNull, reason: 'still live');
    return realtime;
  }

  testWidgets('a booked ride: the drop-off drops the kept link, even when '
      'the stop request fails', (tester) async {
    const rideId = 'booked-share-completed';
    final realtime = await pumpBookedRide(tester, rideId, const [
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
    ]);
    client.fail = true;
    realtime.emit(
      RideStatus.tripCompleted,
      latitude: _destination.latitude,
      longitude: _destination.longitude,
    );
    await frames(tester, 40);
    expect(completed, isNotEmpty, reason: 'the booked ride handler ran');
    expect(safety.shareFor(rideId)?.url, isNull);
  });

  testWidgets('a booked ride: a no-show drops the kept link, even when the '
      'stop request fails', (tester) async {
    const rideId = 'booked-share-no-show';
    final realtime = await pumpBookedRide(tester, rideId, const [
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
    ]);
    client.fail = true;
    realtime.emit(
      RideStatus.noShow,
      latitude: _pickup.latitude,
      longitude: _pickup.longitude,
    );
    await frames(tester, 40);
    expect(safety.shareFor(rideId)?.url, isNull);
  });
}
