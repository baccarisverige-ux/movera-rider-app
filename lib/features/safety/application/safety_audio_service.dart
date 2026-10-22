import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// Notifies its listeners when the platform interrupted a recording and it
/// was stopped and saved (rider-u199).
class SafetyAudioService extends ChangeNotifier {
  SafetyAudioService({
    SafetyRecorder? recorder,
    SafetyStore? store,
    this.supported = true,
  })  : _recorder = recorder ?? createSafetyRecorder(),
        _store = store ?? SafetyStore.shared {
    final recorder = _recorder;
    if (recorder is SafetyRecorderInterruptions) {
      _interruptions = (recorder as SafetyRecorderInterruptions)
          .interruptions
          .listen((_) => unawaited(_onInterrupted()));
    }
  }

  final SafetyRecorder _recorder;
  final SafetyStore _store;
  final bool supported;
  AudioRecording? _active;
  bool autoUpload = false;

  AudioRecording? get active => _active;
  bool get isRecording => _active?.isRecording == true;

  StreamSubscription<void>? _interruptions;

  bool _handedOver = false;

  /// rider-u212/u214: a Ride check card took over the running recording
  /// (it shows it and has its own Stop), so closing the Safety Kit must not
  /// stop it.
  bool get handedOver => _handedOver && _active != null;

  void handOver() {
    if (_active != null) _handedOver = true;
  }

  /// Whether the recording the platform last interrupted was saved.
  bool? lastInterruptionSaved;

  /// rider-u199: the OS paused or stopped capture (a 112 call, the app in
  /// the background). The file holds the audio up to here, so it is saved
  /// and the card and Kit stop showing "Recording".
  Future<void> _onInterrupted() async {
    if (_active == null) return;
    final saved = await stopIfRecording(reason: 'interrupted');
    lastInterruptionSaved = saved != null;
    notifyListeners();
  }

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
    // rider-r4-27: _active is set only after the awaits below, so a second
    // start() during them (a double tap on Record) is refused here too.
    if (isRecording || _starting) {
      throw SafetyAudioException(
        'ALREADY_RECORDING',
        L10n.current.audioAlreadyRecording,
      );
    }
    _starting = true;
    try {
      return await _start(rideId: rideId, deviceOnly: deviceOnly);
    } finally {
      _starting = false;
    }
  }

  bool _starting = false;

  Future<AudioRecording> _start({
    required String rideId,
    required bool deviceOnly,
  }) async {
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
    _handedOver = false;
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
      // rider-u200: nothing was captured, so the entry start() registered
      // goes too; left behind it stayed "recording" (endedAt null) forever.
      try {
        await _store.deleteAudio(current);
      } catch (error) {
        AppLog.warning(
          'safety.audio.forget_failed',
          extra: {'error': '$error'},
        );
      }
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

  /// rider-u202: the rider's data is being wiped (sign-out, another rider
  /// signing in). A running recording is cancelled at once so the
  /// microphone is released; it is not saved, since it belongs to the
  /// rider whose data is going away.
  void discardForWipe() {
    if (_active == null) return;
    _active = null;
    unawaited(
      _recorder.cancel().catchError((Object error) {
        AppLog.warning(
          'safety.audio.cancel_failed',
          extra: {'reason': 'wipe', 'error': '$error'},
        );
      }),
    );
    AppLog.info('safety.audio.discarded', extra: {'reason': 'wipe'});
  }

  @override
  void dispose() {
    unawaited(_interruptions?.cancel());
    super.dispose();
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
