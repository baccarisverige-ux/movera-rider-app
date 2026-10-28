// Safety part 2 (contract v0.12.0 §22, owner decisions 2026-10-28): on the
// contract wire a Ride check is reported to POST /rider/trips/{tripId}/
// ride-check once when the card shows (no answer) and once with the answer
// (ok | need_help), with one Idempotency-Key per report. After "I need help"
// the card says only "Sent".
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/ride_check_reporter.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/l10n/l10n.dart';
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
    at: DateTime.utc(2026, 10, 28, 10),
  );

  late List<http.Request> sent;
  late List<int> statuses;

  ApiClient api() => ApiClient(
    env: staging,
    client: MockClient((request) async {
      sent.add(request);
      final status = statuses.isEmpty ? 200 : statuses.removeAt(0);
      final asked = jsonDecode(request.body) as Map<String, dynamic>;
      final body = status == 200
          ? {
              'checkId': asked['checkId'],
              'tripId': 'trp_0001',
              if (asked['answer'] != null) 'answer': asked['answer'],
              'receivedAt': '2026-10-28T10:00:01Z',
              if (asked['answer'] == 'need_help') 'incidentId': 'inc_0007',
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

  RideCheckReporter reporter() =>
      RideCheckReporter(api(), sleep: (_) async {}, locate: () async => gps);

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  setUp(() {
    sent = [];
    statuses = [];
    SharedPreferences.setMockInitialValues({});
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  test('shown report: no answer, the trigger, at and the phone GPS', () async {
    final receipt = await reporter().report(
      tripId: 'trp_0001',
      checkId: 'rc_1',
      trigger: RideCheckTrigger.longStop,
      at: DateTime.utc(2026, 10, 28, 10),
    );
    expect(receipt?.checkId, 'rc_1');
    expect(receipt?.incidentId, isNull);
    expect(sent.single.url.path, '/api/v1/rider/trips/trp_0001/ride-check');
    expect(sent.single.headers['Idempotency-Key'], isNotEmpty);
    expect(body(sent.single), {
      'checkId': 'rc_1',
      'trigger': 'long_stop',
      'at': '2026-10-28T10:00:00.000Z',
      'position': gps.toJson(),
    });
  });

  test('retries with the same Idempotency-Key; 409 is null', () async {
    statuses = [503, 503];
    final receipt = await reporter().report(
      tripId: 'trp_0001',
      checkId: 'rc_2',
      trigger: RideCheckTrigger.offRoute,
      at: DateTime.utc(2026, 10, 28, 10),
      answer: RideCheckWireAnswer.needHelp,
    );
    expect(receipt?.incidentId, 'inc_0007');
    expect(sent, hasLength(3));
    expect(sent.map((r) => r.headers['Idempotency-Key']).toSet(), hasLength(1));
    expect(body(sent.last)['answer'], 'need_help');

    sent.clear();
    statuses = [409];
    expect(
      await reporter().report(
        tripId: 'trp_0001',
        checkId: 'rc_3',
        trigger: RideCheckTrigger.droppedFar,
        at: DateTime.utc(2026, 10, 28, 10),
        answer: RideCheckWireAnswer.ok,
      ),
      isNull,
    );

    statuses = [503, 503, 503, 503];
    await expectLater(
      reporter().report(
        tripId: 'trp_0001',
        checkId: 'rc_4',
        trigger: RideCheckTrigger.droppedFar,
        at: DateTime.utc(2026, 10, 28, 10),
      ),
      throwsA(anything),
    );
  });

  test('without a GPS fix the report goes without position', () async {
    final r = RideCheckReporter(
      api(),
      locate: () async => throw StateError('no gps'),
    );
    await r.report(
      tripId: 'trp_0001',
      checkId: 'rc_5',
      trigger: RideCheckTrigger.possibleCrash,
      at: DateTime.utc(2026, 10, 28, 10),
      answer: RideCheckWireAnswer.ok,
    );
    expect(body(sent.single).containsKey('position'), isFalse);
    expect(body(sent.single)['trigger'], 'possible_crash');
  });

  SafetyStore liveStore() => SafetyStore(
    local: PreferencesSafetyLocalDataSource(memoryOnly: true),
    remote: const UnservedSafetyRemoteDataSource(),
    rideCheckReporter: reporter(),
  );

  test(
    'the store sends ok for answers without alert, need_help with',
    () async {
      final store = liveStore();
      expect(store.reportsRideCheck, isTrue);
      final base = RideCheckSubmission(
        checkId: 'rc_6',
        trigger: RideCheckTrigger.longStop,
        shownAt: DateTime.utc(2026, 10, 28, 10),
        answers: const [],
        context: const RideCheckTripContext(rideId: 'trp_0001'),
      );
      final ok = await store.submitRideCheckAnswers(base);
      expect(ok.alerted, isFalse);
      expect(body(sent.last)['answer'], 'ok');
      final help = await store.submitRideCheckAnswers(
        RideCheckSubmission(
          checkId: 'rc_6',
          trigger: RideCheckTrigger.longStop,
          shownAt: DateTime.utc(2026, 10, 28, 10),
          answers: const [],
          context: const RideCheckTripContext(rideId: 'trp_0001'),
          alert: true,
        ),
      );
      expect(help.alerted, isTrue);
      expect(help.alertId, 'inc_0007');
      expect(body(sent.last)['answer'], 'need_help');
    },
  );

  test('the demo (mock) store reports nothing to movera-server', () async {
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: const UnservedSafetyRemoteDataSource(),
    );
    expect(store.reportsRideCheck, isFalse);
    await store.reportRideCheckShown(
      tripId: 'trp_0001',
      checkId: 'rc_7',
      trigger: RideCheckTrigger.longStop,
      at: DateTime.utc(2026, 10, 28, 10),
    );
    expect(sent, isEmpty);
  });

  testWidgets('I need help: shown + need_help reports, the card says only '
      '"Sent"', (tester) async {
    final shot = Platform.environment['MOVERA_SHOT'];
    if (shot != null) await tester.runAsync(_loadFonts);
    L10n.use(shot != null ? 'sv' : 'en');
    addTearDown(() => L10n.use('en'));
    final store = liveStore();
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(store: store),
    );
    await tester.runAsync(safety.load);
    final rideCheck = RideCheckController.forSafety(safety);
    addTearDown(rideCheck.dispose);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'trp_0001'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3429, 18.0496),
        destination: GeoPoint(59.36, 18.0),
      ),
    );
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF8FA3B0), Color(0xFFDDE3E6)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: RideCheckLayer(
                    rideId: 'trp_0001',
                    controller: rideCheck,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => rideCheck.open(RideCheckTrigger.longStop, rideId: 'trp_0001'),
    );
    await tester.runAsync(rideCheck.settle);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final row = find.byKey(const ValueKey<String>('ride-check-row-accident'));
    final redRow = row.evaluate().isNotEmpty
        ? row
        : find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'ride-check-row-',
                    ),
              )
              .first;
    await tester.ensureVisible(redRow);
    await tester.tap(redRow);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    final bodies = [for (final r in sent) body(r)];
    expect(bodies.first.containsKey('answer'), isFalse);
    expect(bodies.first['trigger'], 'long_stop');
    expect(bodies.any((b) => b['answer'] == 'need_help'), isTrue);
    expect(bodies.map((b) => b['checkId']).toSet(), hasLength(1));
    final banner = find.byKey(
      const ValueKey<String>('ride-check-alert-banner'),
    );
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text(L10n.current.rcSent)),
      findsOneWidget,
    );
    expect(find.text(L10n.current.rcAlertSentBody), findsNothing);

    if (shot != null) {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(shot)
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}

/// Screenshots only: real glyphs for the Poppins families the card asks for.
Future<void> _loadFonts() async {
  const dir = '/usr/share/fonts/truetype/dejavu';
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(File('$dir/$f').readAsBytesSync());
  for (final (family, file) in [
    ('Poppins_regular', 'DejaVuSans.ttf'),
    ('Poppins_500', 'DejaVuSans.ttf'),
    ('Poppins_600', 'DejaVuSans-Bold.ttf'),
    ('Poppins_700', 'DejaVuSans-Bold.ttf'),
    ('Roboto', 'DejaVuSans.ttf'),
  ]) {
    await (FontLoader(family)..addFont(bytes(file))).load();
  }
}
