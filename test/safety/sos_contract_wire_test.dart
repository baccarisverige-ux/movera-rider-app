// Safety part 1 (contract v0.7.0 §15, owner decisions 2026-10-27): on the
// contract wire the rider's SOS goes to POST /rider/trips/{tripId}/sos with
// the phone's last GPS, retries with the same Idempotency-Key, and the
// Safety Kit says only "SOS sent". The 112 dialer still opens.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  final gps = SosPosition(
    lat: 59.3331,
    lng: 18.0651,
    accuracyM: 8,
    at: DateTime.utc(2026, 10, 27, 10),
  );

  late List<http.Request> sent;
  late List<int> answers;

  ApiClient api() => ApiClient(
    env: staging,
    client: MockClient((request) async {
      sent.add(request);
      final status = answers.isEmpty ? 200 : answers.removeAt(0);
      final body = status == 200
          ? {
              'incidentId': 'inc_0001',
              'tripId': 'trp_0001',
              'receivedAt': '2026-10-27T10:00:01Z',
            }
          : {
              'code': status == 409 ? 'invalid_transition' : 'unavailable',
              'message': 'x',
              'requestId': 'r',
              'retryable': status != 409,
            };
      return http.Response(jsonEncode(body), status);
    }),
  );

  setUp(() {
    sent = [];
    answers = [];
    SharedPreferences.setMockInitialValues({});
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    SafetyController.locateForSos = () async => gps;
  });
  tearDown(() => SafetyController.locateForSos = lastSosPosition);

  test('sends at and the phone GPS once, to the rider SOS endpoint', () async {
    final ok = await SosSender(api()).send('trp_0001', position: gps);
    expect(ok, isTrue);
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/api/v1/rider/trips/trp_0001/sos');
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['position'], {
      'lat': 59.3331,
      'lng': 18.0651,
      'accuracyM': 8.0,
      'at': '2026-10-27T10:00:00.000Z',
    });
    expect(body['at'], isA<String>());
    expect(sent.single.headers['Idempotency-Key'], startsWith('sos-'));
  });

  test('retries with the same Idempotency-Key until Movera has it', () async {
    answers = [503, 503];
    final waits = <Duration>[];
    final ok = await SosSender(
      api(),
      sleep: (d) async => waits.add(d),
    ).send('trp_0001');
    expect(ok, isTrue);
    expect(sent, hasLength(3));
    expect(sent.map((r) => r.headers['Idempotency-Key']).toSet(), hasLength(1));
    expect(sent.map((r) => r.body).toSet(), hasLength(1));
    expect(waits, SosSender.retryDelays.take(2));
    expect(jsonDecode(sent.first.body), isNot(contains('position')));
  });

  test(
    'gives up after the last retry; a trip that is not live is false',
    () async {
      answers = [503, 503, 503, 503];
      await expectLater(
        SosSender(api(), sleep: (_) async {}).send('trp_0001'),
        throwsA(anything),
      );
      expect(sent, hasLength(4));
      sent = [];
      answers = [409];
      expect(await SosSender(api()).send('trp_0001'), isFalse);
      expect(sent, hasLength(1));
    },
  );

  test('the store uses the endpoint on the contract wire', () async {
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: const UnservedSafetyRemoteDataSource(),
      sos: SosSender(api()),
    );
    expect(await store.sendSos('trp_0001', position: gps), isTrue);
    expect(sent.single.url.path, '/api/v1/rider/trips/trp_0001/sos');
  });

  testWidgets('Safety Kit: the dialer opens 112 and the rider sees SOS sent', (
    tester,
  ) async {
    final client = api();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: const UnservedSafetyRemoteDataSource(),
      sos: SosSender(client),
    );
    final dialer = RecordingEmergencyDialer();
    final ctl = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: dialer),
    );
    await tester.runAsync(ctl.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideSafetyKitSheet(rideId: 'trp_0001', controller: ctl),
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
    expect(dialer.calls, ['112']);
    expect(sent.single.url.path, '/api/v1/rider/trips/trp_0001/sos');
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['position'], isNotNull);
    expect(find.text('SOS sent'), findsOneWidget);
    expect(
      ctl.events.where(
        (e) => e.kind == SafetyKind.sos && e.rideId == 'trp_0001',
      ),
      hasLength(1),
    );
    await tester.pump(const Duration(seconds: 5));
  });
}
