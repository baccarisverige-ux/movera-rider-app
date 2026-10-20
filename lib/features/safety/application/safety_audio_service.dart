import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/audio_recording.dart';
import 'safety_recorder.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SafetyAudioException implements Exception {
  const SafetyAudioException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'SafetyAudioException($code, $message)';
}

class SafetyAudioService {
  SafetyAudioService({
    SafetyRecorder? recorder,
    SafetyStore? store,
    this.supported = true,
  })  : _recorder = recorder ?? createSafetyRecorder(),
        _store = store ?? SafetyStore.shared;

  final SafetyRecorder _recorder;
  final SafetyStore _store;
  final bool supported;
  AudioRecording? _active;
  bool autoUpload = false;

  AudioRecording? get active => _active;
  bool get isRecording => _active?.isRecording == true;

  /// Starts the microphone. With [deviceOnly] (Ride check, RC5) the
  /// recording is kept on this phone only: nothing about it is sent to
  /// Movera, not even that it exists.
  Future<AudioRecording> start({
    String rideId = 'ride_local',
    bool deviceOnly = false,
  }) async {
    if (!supported || !_recorder.supported) {
      throw SafetyAudioException(
        'UNSUPPORTED',
        L10n.current.audioUnsupported,
      );
    }
    if (isRecording) {
      throw SafetyAudioException(
        'ALREADY_RECORDING',
        L10n.current.audioAlreadyRecording,
      );
    }
    if (!await _recorder.requestPermission()) {
      throw SafetyAudioException(
        'MIC_DENIED',
        L10n.current.audioMicRequired,
      );
    }
    final recording = deviceOnly
        ? await _store.initDeviceAudio(rideId)
        : await _store.initAudio(rideId);
    try {
      await _recorder.start(recording.id);
    } catch (_) {
      await _recorder.cancel();
      await _store.deleteAudio(recording);
      throw SafetyAudioException(
        'START_FAILED',
        L10n.current.audioStartFailed,
      );
    }
    _active = recording.copyWith(
      createdAt: DateTime.now().toUtc(),
    );
    return _active!;
  }

  Future<AudioRecording> stop() async {
    final current = _active;
    if (current == null) {
      throw SafetyAudioException(
        'NOT_RECORDING',
        L10n.current.audioNothingToStop,
      );
    }
    final ended = DateTime.now().toUtc();
    final started = current.createdAt ?? ended;
    final duration = ended.difference(started).inMilliseconds;
    final path = await _recorder.stop();
    _active = null;
    if (path == null) {
      throw SafetyAudioException('NO_AUDIO', L10n.current.audioNoFile);
    }
    AudioRecording next;
    try {
      final captured = current.copyWith(
        localPath: path,
        durationMs: duration,
        endedAt: ended,
      );
      next = current.deviceOnly
          ? await _store.completeDeviceAudio(captured)
          : await _store.completeAudio(captured);
    } catch (_) {
      throw SafetyAudioException('SAVE_FAILED', L10n.current.audioSaveFailed);
    }
    if (autoUpload) {
      throw SafetyAudioException(
        'UPLOAD_DISABLED',
        L10n.current.audioUploadDisabled,
      );
    }
    return next;
  }

  /// FLOW-6: stops and saves a running recording; does nothing when none
  /// runs. For the moments the rider can no longer reach Stop audio (the
  /// Safety Kit closed, the ride ended), so it never throws. If the save
  /// fails the microphone is still released.
  Future<AudioRecording?> stopIfRecording({String reason = 'unknown'}) async {
    if (_active == null) return null;
    try {
      final saved = await stop();
      AppLog.info('safety.audio.auto_stopped', extra: {'reason': reason});
      return saved;
    } catch (error) {
      AppLog.warning(
        'safety.audio.auto_stop_failed',
        extra: {'reason': reason, 'error': '$error'},
      );
      if (_active != null) {
        _active = null;
        try {
          await _recorder.cancel();
        } catch (cancelError) {
          AppLog.warning(
            'safety.audio.cancel_failed',
            extra: {'error': '$cancelError'},
          );
        }
      }
      return null;
    }
  }

  Future<void> delete(AudioRecording recording) async {
    if (_active?.id == recording.id) {
      await _recorder.cancel();
      _active = null;
    }
    await _store.deleteAudio(recording);
    if (recording.localPath != null) {
      await _recorder.delete(recording.localPath!);
    }
  }
}
