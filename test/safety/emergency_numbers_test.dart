// v0.18.57 §79: the emergency numbers come from the country's settings
// (RiderAppConfig.emergencyNumbers), never a fixed 112; 112 only when no
// list was ever received.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/config/emergency_numbers.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `contract.json#configDefaults.emergencyNumbers.TN`.
const tunisiaEmergencyNumbers = [
  {
    'kind': 'police',
    'number': '197',
    'label': {'sv': 'Polis', 'fr': 'Police', 'en': 'Police'},
  },
  {
    'kind': 'ambulance',
    'number': '190',
    'label': {
      'sv': 'Ambulans (SAMU)',
      'fr': 'SAMU (ambulance)',
      'en': 'Ambulance (SAMU)',
    },
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EmergencyNumbers.reset();
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });
  tearDown(EmergencyNumbers.reset);

  Future<(SafetyStore, RecordingEmergencyDialer)> pumpKit(
    WidgetTester tester, {
    String? rideId,
  }) async {
    final dialer = RecordingEmergencyDialer();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final ctl = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: dialer),
    );
    await tester.runAsync(ctl.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(rideId: rideId, controller: ctl),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (store, dialer);
  }

  test('parse keeps valid rows and rejects a bad list', () {
    expect(EmergencyNumbers.parse(tunisiaEmergencyNumbers), hasLength(2));
    expect(EmergencyNumbers.parse([]), isNull);
    expect(
      EmergencyNumbers.parse([
        {
          'kind': 'police',
          'number': 'abc',
          'label': {'en': 'x'},
        },
      ]),
      isNull,
    );
  });

  test('the last list is kept offline; 112 only if never received', () async {
    expect(EmergencyNumbers.main.number, '112');
    expect(EmergencyNumbers.received, isFalse);
    await EmergencyNumbers.accept(tunisiaEmergencyNumbers);
    EmergencyNumbers.reset();
    await EmergencyNumbers.restore();
    expect(EmergencyNumbers.current.map((r) => r.number), ['197', '190']);
    // A bad served list does not replace the kept one.
    await EmergencyNumbers.accept('nope');
    expect(EmergencyNumbers.main.number, '197');
  });

  testWidgets('shield with no trip, no config: one Call 112 button', (
    tester,
  ) async {
    final (_, dialer) = await pumpKit(tester);
    expect(find.text('Call 112'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('safety-call-112')));
    await tester.pump();
    expect(dialer.calls, ['112']);
  });

  testWidgets('shield with no trip, TN: Call 197 and Call 190 buttons', (
    tester,
  ) async {
    await EmergencyNumbers.accept(tunisiaEmergencyNumbers);
    final (_, dialer) = await pumpKit(tester);
    expect(find.text('Call 112'), findsNothing);
    expect(find.text('Call Police 197'), findsOneWidget);
    expect(find.text('Call Ambulance (SAMU) 190'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('safety-call-197')));
    await tester.tap(find.byKey(const ValueKey('safety-call-190')));
    await tester.pump();
    expect(dialer.calls, ['197', '190']);
  });

  testWidgets('TN SOS dials 197, alerts Movera, then offers 190', (
    tester,
  ) async {
    await EmergencyNumbers.accept(tunisiaEmergencyNumbers);
    final (store, dialer) = await pumpKit(tester, rideId: 'ride_tn');
    expect(find.byKey(const ValueKey('sos-call-190')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('safety-sos')));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        if (store.rideCheckEvents.any((e) => e.payload['kind'] == 'sos')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dialer.calls, ['197']);
    expect(store.rideCheckEvents.any((e) => e.payload['kind'] == 'sos'), true);
    await tester.tap(find.byKey(const ValueKey('sos-call-190')));
    await tester.pump();
    expect(dialer.calls, ['197', '190']);
  });
}
