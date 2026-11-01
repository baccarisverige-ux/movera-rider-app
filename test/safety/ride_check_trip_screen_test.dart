import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
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
    String rideId, {
    // The live wire (contract TripProjection) may carry no driver position.
    bool positions = true,
    LocationRepository? location,
  }) async {
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
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Solna centrum, 171 45 Solna',
          pickupPosition: _pickup,
          destinationPosition: _destination,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          location: location,
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
        latitude: positions ? _pickup.latitude : null,
        longitude: positions ? _pickup.longitude : null,
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

  testWidgets(
    'the card opens at the top of the in-trip screen and back does nothing',
    (tester) async {
      const rideId = 'rc-in-trip';
      await pumpInTrip(tester, rideId);
      final before = pushed.length;

      expect(
        await rideCheck.open(
          RideCheckTrigger.longStop,
          rideId: rideId,
          reason: const RideCheckReason(stoppedMinutes: 4),
        ),
        RideCheckOpenResult.shown,
      );
      await frames(tester);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(find.text('I asked the driver to stop'), findsOneWidget);
      // The rider, driver and trip the alert would carry.
      expect(rideCheck.trip?.destination?.label, 'Solna centrum');
      expect(rideCheck.trip?.status, RideStatus.tripInProgress.name);

      // Back on the in-trip screen normally opens the ride details; with the
      // card up it does nothing.
      await tester.binding.handlePopRoute();
      await frames(tester);
      expect(pushed.length, before, reason: 'no sheet or page opened');
      expect(find.text('Is everything OK?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('ride-check-ok')));
      await frames(tester);
      expect(find.text('Is everything OK?'), findsNothing);
      expect(rideCheck.blocks(rideId), isFalse);
    },
  );

  testWidgets(
    'a trip that ends far from the drop-off opens "dropped far away" over the ride summary',
    (tester) async {
      const rideId = 'rc-dropped-far';
      final realtime = await pumpInTrip(tester, rideId);

      // The driver finishes about 3.6 km from Solna centrum (admin's
      // default is 3 km).
      realtime.emit(
        RideStatus.tripCompleted,
        latitude: _destination.latitude + 0.0324,
        longitude: _destination.longitude,
      );
      await tester.pump();
      expect(rideCheck.session?.trigger, RideCheckTrigger.droppedFar);
      await frames(tester, 14);

      expect(find.byType(RideCompleted), findsOneWidget);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(
        find.text(
          'Your trip ended 3.6 km from Solna centrum',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('I was left at the wrong place'), findsOneWidget);
      // The summary behind cannot be left until the rider answers.
      await tester.binding.handlePopRoute();
      await frames(tester);
      expect(find.byType(RideCompleted), findsOneWidget);
      expect(find.text('home root'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-check-row-wrong_place')),
      );
      await frames(tester);
      expect(find.text('Thanks, this is saved to the trip.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('ride-check-done')));
      await frames(tester);
      expect(find.text('Is everything OK?'), findsNothing);
      expect(
        safetyMockForProcess().rideCheckAnswers.single['trigger'],
        'dropped_far',
      );
      // Its trip details carry the entry.
      await tester.scrollUntilVisible(
        find.text('Trip check'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RideCompleted),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Trip check'), findsOneWidget);
      expect(find.text('I was left at the wrong place'), findsOneWidget);
    },
  );

  testWidgets(
    'the driver ending the trip on board far from the drop-off opens the card, '
    'before the "trip ended" sheet',
    (tester) async {
      const rideId = 'rc-ended-by-driver';
      final realtime = await pumpInTrip(tester, rideId);

      // Live: the driver's "End trip early" is a cancel on board; the server
      // reports cancelled_by_driver with the car 3.6 km from Solna centrum.
      realtime.emit(
        RideStatus.endedByDriver,
        latitude: _destination.latitude + 0.0324,
        longitude: _destination.longitude,
      );
      await tester.pump();
      expect(rideCheck.session?.trigger, RideCheckTrigger.droppedFar);
      await frames(tester, 14);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(find.text('I was left at the wrong place'), findsOneWidget);
      // The "trip ended" sheet waits for the answer: it would cover the card.
      expect(find.byType(RideTerminalStateSheet), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-check-row-wrong_place')),
      );
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey<String>('ride-check-done')));
      await frames(tester, 14);
      expect(find.text('Is everything OK?'), findsNothing);
      expect(
        safetyMockForProcess().rideCheckAnswers.single['trigger'],
        'dropped_far',
      );
      expect(find.byType(RideTerminalStateSheet), findsOneWidget);
    },
  );

  testWidgets(
    'a completion the wire reports without a driver position asks the phone '
    'where the rider is',
    (tester) async {
      const rideId = 'rc-phone-end';
      final phone = _PhoneFarAway();
      final realtime = await pumpInTrip(
        tester,
        rideId,
        positions: false,
        location: phone,
      );
      realtime.emit(RideStatus.tripCompleted);
      await tester.pump();
      await frames(tester, 14);
      expect(phone.reads, 1);
      expect(rideCheck.session?.trigger, RideCheckTrigger.droppedFar);
      expect(find.byType(RideCompleted), findsOneWidget);
      expect(find.text('Is everything OK?'), findsOneWidget);
      expect(
        find.text(
          'Your trip ended 3.6 km from Solna centrum',
          findRichText: true,
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a trip that ends at the drop-off opens nothing', (tester) async {
    const rideId = 'rc-at-dropoff';
    final realtime = await pumpInTrip(tester, rideId);
    realtime.emit(
      RideStatus.tripCompleted,
      latitude: _destination.latitude,
      longitude: _destination.longitude,
    );
    await tester.pump();
    await frames(tester, 14);
    expect(find.byType(RideCompleted), findsOneWidget);
    expect(rideCheck.session, isNull);
    expect(find.text('Is everything OK?'), findsNothing);
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

/// The rider's phone, 3.6 km from Solna centrum when the trip ends.
class _PhoneFarAway extends LocationRepository {
  int reads = 0;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads += 1;
    return Position(
      latitude: _destination.latitude + 0.0324,
      longitude: _destination.longitude,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}
