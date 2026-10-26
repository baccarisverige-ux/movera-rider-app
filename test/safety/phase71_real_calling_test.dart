import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('real emergency adapter requests the platform tel:112 URI', () async {
    Uri? launched;
    final dialer = SystemEmergencyDialer(
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );
    final service = EmergencyCallService(dialer: dialer);

    await service.callEmergencyNumber();

    expect(launched, Uri(scheme: 'tel', path: '112'));
    expect(service.explicitCallCount, 1);
  });

  test(
    'real emergency adapter fails when platform refuses the tel URI',
    () async {
      final dialer = SystemEmergencyDialer(launcher: (_) async => false);

      await expectLater(
        dialer.open('112'),
        throwsA(isA<EmergencyCallException>()),
      );
    },
  );

  test(
    'SOS records locally and posts through the safety backend contract',
    () async {
      final store = SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(
          ApiClient(client: InProcessMockClient()),
        ),
      );
      final controller = SafetyController(session: store);
      await controller.load();

      await controller.sos(rideId: 'ride_phase71');

      expect(
        controller.events.any(
          (event) =>
              event.kind == SafetyKind.sos && event.rideId == 'ride_phase71',
        ),
        isTrue,
      );
      final backendEvents = controller.rideCheck.events();
      expect(
        backendEvents.any(
          (event) =>
              event.rideId == 'ride_phase71' &&
              event.payload['kind'] == 'sos' &&
              event.payload['action'] == 'call_112',
        ),
        isTrue,
      );
    },
  );

  // rider-u241: the real WaitingForDriver wires Call (waiting card and
  // in-trip panel); a callback written in the test would prove nothing.
  Future<MockRideRealtime> pumpWaiting(
    WidgetTester tester,
    RideStatus status,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'ride_phase71_call';
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(status, id: rideId);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
      ..primeResume(status: status, driver: _driver);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Centralstation',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.33, 18.06),
          rideType: 'Movera',
          price: 190,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          driver: _driver,
          realtime: realtime,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return realtime;
  }

  Future<void> expectCallUnavailable(
    WidgetTester tester,
    MockRideRealtime realtime,
  ) async {
    final call = find.bySemanticsLabel('Call driver');
    expect(call, findsOneWidget);
    await tester.ensureVisible(call);
    await tester.pump();
    await tester.tap(call);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Driver calling unavailable'), findsOneWidget);
    expect(find.textContaining('masked calling number'), findsOneWidget);
    realtime.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('waiting driver call is explicitly unavailable', (tester) async {
    final realtime = await pumpWaiting(tester, RideStatus.driverAssigned);
    expect(find.byType(WaitingDriverCard), findsOneWidget);
    await expectCallUnavailable(tester, realtime);
  });

  testWidgets('in-trip driver call is explicitly unavailable', (tester) async {
    final realtime = await pumpWaiting(tester, RideStatus.tripInProgress);
    expect(find.byType(RiderInTripPanel), findsOneWidget);
    await expectCallUnavailable(tester, realtime);
  });
}

const _driver = MatchedDriver(
  id: 'driver_phase71',
  firstName: 'Alex',
  vehicleMake: 'Volvo',
  vehicleModel: 'EX30',
  plate: 'ABC 123',
);
