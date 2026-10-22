// Owner decision 10 (FIX_PLAN "Owner decisions"): the demo refused booking
// (rider-u29) and the hidden audio recording option.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/safety/presentation/safety_audio_option.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts the stand-in server's answers to `POST /rides/{id}/status`.
class _Counting extends http.BaseClient {
  final inner = InProcessMockClient();
  int statusAnswers = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.url.path.endsWith('/status')) statusAnswers++;
    return response;
  }
}

class _Recorder implements SafetyRecorder {
  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start(String recordingId) async {}
  @override
  Future<String?> stop() async => '/device/safety/rec.m4a';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {}
}

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('rider-u29: a refused accept shows no made-up driver', () async {
    final transport = _Counting();
    final rt = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: ApiClient(client: transport),
    );
    addTearDown(rt.dispose);
    final seen = <RideStatus>[];
    // The stand-in server never had this ride: the accept answers 404.
    rt.subscribe('ride_the_server_never_had').listen((e) => seen.add(e.status));
    rt.assignNow();
    await _until(() => transport.statusAnswers > 0 && rt.lastDriver == null);

    expect(transport.statusAnswers, 1);
    expect(rt.lastDriver, isNull);
    expect(rt.lastStatus, RideStatus.findingDriver);
    expect(seen, isNot(contains(RideStatus.driverAssigned)));
  });

  testWidgets('owner 10: Record audio is hidden in the Safety Kit and in '
      'Ride check; a running recording keeps its Stop', (tester) async {
    expect(safetyAudioRecordingEnabled, isFalse);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: _Recorder(), store: store),
    );
    await tester.runAsync(safety.load);

    // Safety Kit: Contact 112 and Share trip only.
    Widget kit(Key key) => MaterialApp(
      home: Scaffold(
        body: RideSafetyKitSheet(
          key: key,
          rideId: 'ride_o10',
          controller: safety,
        ),
      ),
    );
    await tester.pumpWidget(kit(const ValueKey('kit-1')));
    await tester.pumpAndSettle();
    expect(find.text('Contact 112'), findsOneWidget);
    expect(find.text('Share trip'), findsOneWidget);
    expect(find.text('Record audio'), findsNothing);
    expect(find.text('Stop audio'), findsNothing);

    // A recording already running when the kit opens still shows its Stop
    // (closing a kit stops its recording, so the first one closes first).
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => safety.audio.start(rideId: 'ride_o10'));
    await tester.pumpWidget(kit(const ValueKey('kit-2')));
    await tester.pumpAndSettle();
    expect(find.text('Stop audio'), findsOneWidget);
    await tester.tap(find.text('Stop audio'));
    await tester.runAsync(() => _until(() => !safety.audio.isRecording));
    await tester.pumpAndSettle();
    expect(safety.audio.isRecording, isFalse);
    expect(find.text('Stop audio'), findsNothing);
    expect(find.text('Record audio'), findsNothing);

    // Ride check card: Call 112 and I'm OK, no Record audio.
    final rideCheck = RideCheckController.forSafety(safety);
    addTearDown(rideCheck.dispose);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'ride_o10'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3429, 18.0496),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideCheckLayer(rideId: 'ride_o10', controller: rideCheck),
        ),
      ),
    );
    await tester.runAsync(
      () => rideCheck.open(RideCheckTrigger.longStop, rideId: 'ride_o10'),
    );
    // The card keeps a live clock, so it never settles: pump its entry.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text("I'm OK"), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ride-check-record')),
      findsNothing,
    );
    expect(
      find.textContaining('Record audio', findRichText: true),
      findsNothing,
    );
  });
}
