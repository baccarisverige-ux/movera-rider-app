abstract class SafetyRecorder {
  bool get supported;
  Future<bool> requestPermission();
  Future<void> start(String recordingId);
  Future<String?> stop();
  Future<void> cancel();
  Future<void> delete(String path);
}

/// A recorder that says when the platform paused or stopped capture on
/// its own (a phone call or the OS taking the microphone), not because the
/// app asked it to stop.
abstract class SafetyRecorderInterruptions {
  Stream<void> get interruptions;
}

SafetyRecorder createSafetyRecorder() => const UnsupportedSafetyRecorder();

/// No recording is ever written where audio capture is unavailable.
Future<void> deleteAllSafetyRecordings() async {}

class UnsupportedSafetyRecorder implements SafetyRecorder {
  const UnsupportedSafetyRecorder();

  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> start(String recordingId) async =>
      throw UnsupportedError('Audio recording is unavailable on this platform.');
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete(String path) async {}
}
