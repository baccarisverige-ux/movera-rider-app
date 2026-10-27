// rider-u215: Safety Kit "Contact 112" sent no SOS to Movera when the
// phone dialer could not be opened; the dialer error skipped the SOS.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  Future<SafetyStore> pumpKit(
    WidgetTester tester, {
    required EmergencyUriLauncher launcher,
  }) async {
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final ctl = SafetyController(
      session: store,
      emergency: EmergencyCallService(
        dialer: SystemEmergencyDialer(launcher: launcher),
      ),
    );
    await tester.runAsync(ctl.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(rideId: 'ride_u215', controller: ctl),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact 112'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return store;
  }

  bool sosPosted(SafetyStore store) => store.rideCheckEvents.any(
    (e) => e.rideId == 'ride_u215' && e.payload['kind'] == 'sos',
  );

  testWidgets('no dialer: the SOS still reaches Movera and the rider is told', (
    tester,
  ) async {
    final store = await pumpKit(tester, launcher: (_) async => false);
    expect(sosPosted(store), isTrue, reason: 'Movera must be told');
    expect(
      find.text(
        'SOS sent. Could not open the phone dialer: '
        'call 112 from another phone if you can.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('with a dialer the SOS is posted as before', (tester) async {
    final store = await pumpKit(tester, launcher: (_) async => true);
    expect(sosPosted(store), isTrue);
    expect(find.text('SOS sent'), findsOneWidget);
  });
}
