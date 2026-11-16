// BQ-S10 follow-up SF-F5 (supervisor, audits/impact/s10-followups.md): the
// Safety sheet called SafetyController.load() in initState. load() notifies
// at once, so a screen listening to the same controller (the trip screen's
// Safety row) was marked dirty while the sheet was being built: the
// debug-only "setState() or markNeedsBuild() called during build". The load
// now starts right after the sheet's first frame. SOS never waits for it.
import 'dart:async';
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

/// A phone store whose read does not answer until [release] (a slow disk or
/// a hung secure store): the sheet's load stays in flight.
class _HeldLocal implements SafetyLocalDataSource {
  final _inner = PreferencesSafetyLocalDataSource(memoryOnly: true);
  final _gate = Completer<void>();
  var loads = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<SafetyCache> load() async {
    loads++;
    await _gate.future;
    return _inner.load();
  }

  @override
  Future<void> save(SafetyCache cache) => _inner.save(cache);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  late List<http.Request> sent;
  late _HeldLocal local;
  late RecordingEmergencyDialer dialer;
  late SafetyController ctl;

  setUp(() {
    sent = [];
    SharedPreferences.setMockInitialValues({});
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    SafetyController.locateForSos = () async => null;
    local = _HeldLocal();
    dialer = RecordingEmergencyDialer();
    ctl = SafetyController(
      session: SafetyStore(
        local: local,
        remote: const UnservedSafetyRemoteDataSource(),
        sos: SosSender(
          ApiClient(
            env: staging,
            client: MockClient((request) async {
              sent.add(request);
              return http.Response(
                jsonEncode({
                  'incidentId': 'inc_f5',
                  'tripId': 'trp_f5',
                  'receivedAt': '2026-11-16T10:00:01Z',
                }),
                200,
              );
            }),
          ),
        ),
      ),
      emergency: EmergencyCallService(dialer: dialer),
    );
  });
  tearDown(() {
    local.release();
    SafetyController.locateForSos = lastSosPosition;
  });

  /// The sheet inside a screen that listens to the same controller, as the
  /// trip screen's Safety row does (WaitingNotesAndPin).
  Widget screen({required bool open}) => MaterialApp(
    home: Scaffold(
      body: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => Column(
          children: [
            Text(ctl.loading ? 'listener: loading' : 'listener: idle'),
            if (open)
              Expanded(
                child: RideSafetyKitSheet(
                  rideId: 'trp_f5',
                  controller: ctl,
                  duringTrip: true,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  testWidgets('opening the sheet under a listening screen raises no '
      '"setState during build"; the load starts right after the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(screen(open: false));
    expect(local.loads, 0);
    await tester.pumpWidget(screen(open: true));
    // Any FlutterError (the assertion included) fails the test by itself;
    // this names it.
    expect(tester.takeException(), isNull);
    expect(local.loads, 1, reason: 'the load started after the first frame');
    expect(ctl.loading, isTrue);
    await tester.pump();
    expect(find.text('listener: loading'), findsOneWidget);
    expect(tester.takeException(), isNull);
    local.release();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(ctl.hasLoaded, isTrue);
    await tester.pump();
    expect(find.text('listener: idle'), findsOneWidget);
  });

  testWidgets('SOS works at once, while the sheet\'s load has not finished', (
    tester,
  ) async {
    await tester.pumpWidget(screen(open: true));
    expect(ctl.loading, isTrue, reason: 'the load is still in flight');
    expect(ctl.hasLoaded, isFalse);
    final sos = find.byKey(const ValueKey('safety-sos'));
    expect(sos, findsOneWidget, reason: 'SOS is drawn in the first frame');
    await tester.tap(sos);
    for (var i = 0; i < 50 && sent.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(dialer.calls, ['112'], reason: 'the dialer opened');
    expect(sent, hasLength(1), reason: 'Movera has the SOS');
    expect(sent.single.url.path, '/api/v1/rider/trips/trp_f5/sos');
    await tester.pump();
    expect(find.text('SOS sent'), findsOneWidget);
    expect(ctl.hasLoaded, isFalse, reason: 'all of it before the load ended');
    expect(
      ctl.events.where((e) => e.kind == SafetyKind.sos && e.rideId == 'trp_f5'),
      hasLength(1),
    );
    local.release();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 5));
  });
}
