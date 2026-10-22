import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

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

/// rider-r5-30 (owner decision 10 keeps audio hidden): once a taken-over
/// recording is stopped on the Ride check card, its note stays but no
/// "Record audio" button comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('no Record audio after Stop', (tester) async {
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
      remote: ApiSafetyRemoteDataSource(ApiClient(client: InProcessMockClient())),
    );
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: _Recorder(), store: store),
    );
    await tester.runAsync(safety.load);
    await tester.runAsync(() => safety.audio.start(rideId: 'ride_r5_30'));
    final rideCheck = RideCheckController.forSafety(safety);
    addTearDown(rideCheck.dispose);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'ride_r5_30'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3429, 18.0496),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RideCheckLayer(rideId: 'ride_r5_30', controller: rideCheck),
      ),
    ));
    await tester.runAsync(
      () => rideCheck.open(RideCheckTrigger.longStop, rideId: 'ride_r5_30'),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final record = find.byKey(const ValueKey<String>('ride-check-record'));
    expect(rideCheck.recording, isTrue);
    await tester.ensureVisible(record);
    await tester.tap(record);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(rideCheck.recording, isFalse);
    expect(record, findsNothing);
  });
}
