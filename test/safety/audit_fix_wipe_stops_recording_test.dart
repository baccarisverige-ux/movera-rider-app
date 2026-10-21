// rider-u202: the user-data wipe (sign-out, a new rider signing in)
// disposed the Safety and Ride check controllers without stopping a
// running recording, so the microphone kept recording with no owner.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Recorder implements SafetyRecorder {
  bool capturing = false;
  int saves = 0;

  @override
  bool get supported => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start(String recordingId) async => capturing = true;
  @override
  Future<String?> stop() async {
    capturing = false;
    saves++;
    return '/device/safety_recordings/a.m4a';
  }

  @override
  Future<void> cancel() async => capturing = false;
  @override
  Future<void> delete(String path) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
    SafetyController.resetShared();
  });

  test('the wipe releases the microphone of a running recording', () async {
    final recorder = _Recorder();
    final store = SafetyStore(
      local: PreferencesSafetyLocalDataSource(memoryOnly: true),
      remote: ApiSafetyRemoteDataSource(
        ApiClient(client: InProcessMockClient()),
      ),
    );
    final safety = SafetyController(
      session: store,
      emergency: EmergencyCallService(dialer: RecordingEmergencyDialer()),
      audio: SafetyAudioService(recorder: recorder, store: store),
    );
    SafetyController.sharedForTest = safety;
    RideCheckController.sharedForTest = RideCheckController.forSafety(safety);
    await safety.load();
    // Rider A starts a Ride check recording during the trip.
    await safety.audio.start(rideId: 'r1', deviceOnly: true);
    expect(recorder.capturing, isTrue);

    // Rider B signs in: the wipe replaces the controllers.
    SafetyController.resetShared();
    await pumpEventQueue();

    expect(recorder.capturing, isFalse, reason: 'no one owns the mic now');
    expect(safety.audio.isRecording, isFalse);
    expect(recorder.saves, 0, reason: "rider A's audio is not kept for B");
  });
}
