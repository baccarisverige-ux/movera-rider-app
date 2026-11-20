import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_page.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Check 2026-11-20 (apps every control, live test web): Safety >
/// Resekontroll > "Aviseringar för resekontroll" answered "Det gick inte att
/// uppdatera resekontrollen." on every tap. movera-server serves only the
/// emergency contacts (safety_store.dart UnservedSafetyRemoteDataSource), so
/// the switch could only fail, like the PIN switch in R4. On the live wire
/// the switch is not shown; demo and test builds keep it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  /// The live wire: movera-server serves the emergency contacts only.
  SafetyController liveController(List<String> calls) {
    final api = ApiClient(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({'items': <Object>[], 'updatedAt': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      env: staging,
    );
    return SafetyController(
      session: SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        api: api,
      ),
    );
  }

  /// The demo wire, where the rider's own setting is served.
  SafetyController demoController() => SafetyController(
    session: SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    ),
  );

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('live server: Resekontroll has no switch that can only fail', (
    tester,
  ) async {
    final ctl = liveController(<String>[]);
    await ctl.load();
    expect(ctl.serverKeepsSettings, isFalse);
    await tester.pumpWidget(app(RideCheckPage(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Trip check alerts'), findsNothing);
    expect(ctl.error, isNull);
  });

  testWidgets('demo wire: the switch stays and turns off', (tester) async {
    final ctl = demoController();
    await ctl.load();
    expect(ctl.serverKeepsSettings, isTrue);
    await tester.pumpWidget(app(RideCheckPage(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    final before = ctl.rideCheckPolicy.enabled;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(ctl.rideCheckPolicy.enabled, !before);
    expect(ctl.error, isNull);
  });
}
