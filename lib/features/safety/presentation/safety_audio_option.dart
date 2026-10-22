import 'package:flutter/foundation.dart';

/// Owner decision 10 (2026-10-22): the option to start an audio recording
/// is hidden, for now, in the Safety Kit and in the Ride check card. Only
/// the option: the recorder, its store and the saved files stay as they
/// are. Set this to `true` to show the option again.
const bool safetyAudioRecordingEnabled = false;

/// Whether the Safety Kit and the Ride check card offer "Record audio".
abstract final class SafetyAudioOption {
  /// Test seam: widget tests of the recording flow turn the option on.
  @visibleForTesting
  static bool? debugEnabled;

  static bool get enabled => debugEnabled ?? safetyAudioRecordingEnabled;
}
