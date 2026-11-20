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
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/presentation/pin_verification_page.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R4 (owner 2026-11-20, "Yes, all 7 as drafts"): Safety > PIN verification
/// had a switch that never turned on on the live server: "Det gick inte att
/// uppdatera PIN-verifieringen." The PIN check before Start is Movera's
/// switch per area (admin, per zone; owner 2026-11-01 "PIN per-zone admin
/// switch"), the server keeps no rider PIN setting.
/// A phone that still holds "PIN on" from a demo build or an old version.
class _OldPhone implements SafetyLocalDataSource {
  @override
  Future<SafetyCache> load() async =>
      SafetyCache(preferences: const SafetyPreferences(pinRequired: true));

  @override
  Future<void> save(SafetyCache cache) async {}
}

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
  SafetyController liveController(
    List<String> calls, {
    SafetyLocalDataSource? local,
  }) {
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
        local: local ?? PreferencesSafetyLocalDataSource(memoryOnly: true),
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

  testWidgets(
    'live server: no switch that can only fail; the page says who decides',
    (tester) async {
      final calls = <String>[];
      final ctl = liveController(calls);
      await ctl.load();
      expect(ctl.serverKeepsSettings, isFalse);
      await tester.pumpWidget(app(PinVerificationPage(controller: ctl)));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
      expect(find.byKey(const ValueKey('pin-decided-by-area')), findsOneWidget);
      expect(
        find.textContaining('Movera turns the PIN check on per area'),
        findsOneWidget,
      );
      // No PIN of the phone's own and no "Change PIN": the ride's PIN is the
      // server's and shows on the ride screen.
      expect(find.text('Change PIN'), findsNothing);
      expect(find.text('YOUR PIN'), findsNothing);
      expect(find.text('Could not update PIN verification.'), findsNothing);
      expect(ctl.error, isNull);
    },
  );

  testWidgets('live server: the Safety list says "Set per area", not Off', (
    tester,
  ) async {
    final ctl = liveController(<String>[]);
    await ctl.load();
    expect(ctl.pinStatusLabel(), 'Set per area');
    await tester.pumpWidget(app(SafetyHub(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.text('Set per area'), findsOneWidget);
  });

  testWidgets('demo wire: the switch stays and turns on', (tester) async {
    final ctl = demoController();
    await ctl.load();
    expect(ctl.serverKeepsSettings, isTrue);
    expect(ctl.pinStatusLabel(), 'Off');
    await tester.pumpWidget(app(PinVerificationPage(controller: ctl)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pin-decided-by-area')), findsNothing);
    expect(find.text('Change PIN'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(ctl.preferences.pinRequired, isTrue);
    expect(ctl.pinStatusLabel(), 'On');
  });

  testWidgets(
    'live server: an old "PIN on" kept on the phone shows no second PIN box '
    'on the ride sheet',
    (tester) async {
      final ctl = liveController(<String>[], local: _OldPhone());
      await ctl.load();
      expect(ctl.preferences.pinRequired, isTrue);
      SafetyController.sharedForTest = ctl;
      addTearDown(() => SafetyController.sharedForTest = null);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: WaitingNotesAndPin(notes: RideNotes.empty, rideId: 'trp_1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('PIN unavailable — verify plate and driver name'),
        findsNothing,
      );
      expect(find.text('Loading PIN…'), findsNothing);
    },
  );

  test('the words in sv and fr', () {
    final sv = lookupAppLocalizations(const Locale('sv'));
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(sv.pinStatusByArea, 'Styrs per område');
    expect(sv.pinDecidedByArea, startsWith('Movera slår på PIN-kontrollen'));
    expect(fr.pinStatusByArea, 'Selon la zone');
    expect(fr.pinDecidedByArea, startsWith('Movera active la vérification'));
  });
}
