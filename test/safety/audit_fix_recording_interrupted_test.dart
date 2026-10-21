// rider-u199: when the OS paused or stopped capture on its own (a 112
// call, the app going to the background), the Ride check card and the
// Safety Kit kept showing "Recording m:ss" because nothing listened to the
// recorder. An interruption now stops and saves the recording, and both
// surfaces stop saying it is recording.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A recorder whose capture the "OS" can interrupt.
class _Recorder implements SafetyRecorder, SafetyRecorderInterruptions {
  final _interrupts = StreamController<void>.broadcast();
  int stops = 0;

  void interrupt() => _interrupts.add(null);

  @override
  Stream<void> get interruptions => _interrupts.stream;
  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start(String recordingId) async {}
  @override
  Future<String?> stop() async {
    stops++;
    return '/device/safety_recordings/ride_check.m4a';
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {}
}

void main() {
  late _Recorder recorder;
  late SafetyStore store;
  late SafetyController safety;
  late RideCheckController rideCheck;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
    recorder = _Recorder();
    store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    await safety.load();
    rideCheck = RideCheckController.forSafety(safety);
    rideCheck.attachTrip(
      const RideCheckTripContext(rideId: 'r1'),
      const RideCheckPlan(
        pickup: GeoPoint(59.3293, 18.0686),
        destination: GeoPoint(59.3600, 18.0000),
      ),
    );
  });

  tearDown(() => rideCheck.dispose());

  test(
    'an interrupted Ride check recording stops, is saved and says so',
    () async {
      await rideCheck.open(RideCheckTrigger.longStop, rideId: 'r1');
      await rideCheck.toggleRecording();
      expect(rideCheck.recording, isTrue);
      var notified = 0;
      rideCheck.addListener(() => notified++);

      recorder.interrupt(); // the 112 call takes the microphone
      await pumpEventQueue();

      expect(
        rideCheck.recording,
        isFalse,
        reason: 'the card must not keep counting "Recording m:ss"',
      );
      expect(recorder.stops, 1);
      expect(notified, greaterThan(0));
      expect(rideCheck.session!.recordingNote, L10n.current.rcRecordingSaved);
    },
  );

  test('the Safety Kit hears about an interrupted recording', () async {
    await safety.audio.start(rideId: 'r1');
    var notified = 0;
    safety.addListener(() => notified++);
    recorder.interrupt();
    await pumpEventQueue();
    expect(safety.audio.isRecording, isFalse);
    expect(notified, greaterThan(0));
  });

  test('a stop the rider asked for is not an interruption', () async {
    await safety.audio.start(rideId: 'r1');
    await safety.audio.stop();
    recorder.interrupt();
    await pumpEventQueue();
    expect(recorder.stops, 1);
  });
}
