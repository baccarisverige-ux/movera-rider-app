import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'safety_recorder_background.dart';
import 'safety_recorder_stub.dart';

export 'safety_recorder_stub.dart'
    show SafetyRecorder, SafetyRecorderInterruptions;

SafetyRecorder createSafetyRecorder() => NativeSafetyRecorder();

/// rider-u69 / rider-u71: removes every Safety recording on this device
/// (the sign-out wipe). The files are the rider's own cabin audio, and
/// nothing can reach them once their index is gone.
Future<void> deleteAllSafetyRecordings() async {
  if (!NativeSafetyRecorder.savesFilesHere) return;
  final directory = await NativeSafetyRecorder.recordingsDirectory();
  if (await directory.exists()) await directory.delete(recursive: true);
}

class NativeSafetyRecorder
    implements SafetyRecorder, SafetyRecorderInterruptions {
  AudioRecorder? _recorder;
  final _interrupted = StreamController<void>.broadcast();
  StreamSubscription<RecordState>? _states;
  bool _capturing = false;

  /// rider-u206: iOS keeps recording in the background (the `audio`
  /// background mode in Info.plist); Android silences a backgrounded app's
  /// microphone, so there leaving the foreground ends the capture.
  final _background = BackgroundCaptureGuard(endsCapture: Platform.isAndroid);

  AudioRecorder get recorder => _recorder ??= AudioRecorder();

  /// Recordings are written on the phone apps only (desktop hosts, such as
  /// the test runner, never record); tests switch it on.
  @visibleForTesting
  static bool savesFilesHere = Platform.isIOS || Platform.isAndroid;

  /// Where the app's documents live; tests point it at a temporary folder.
  @visibleForTesting
  static Future<Directory> Function() documentsDirectory =
      getApplicationDocumentsDirectory;

  /// `<documents>/safety_recordings`, one `<id>.m4a` per recording.
  static Future<Directory> recordingsDirectory() async =>
      Directory('${(await documentsDirectory()).path}/safety_recordings');

  /// rider-u199: capture paused or stopped while the app had not asked
  /// (iOS pauses on a call; the OS can stop the recorder).
  @override
  Stream<void> get interruptions => _interrupted.stream;

  void _onState(RecordState state) {
    if (!_capturing || state == RecordState.record) return;
    _capturing = false;
    _interrupted.add(null);
  }

  @override
  bool get supported => true;

  // record.hasPermission requests the native microphone permission if needed.
  @override
  Future<bool> requestPermission() => recorder.hasPermission();

  @override
  Future<void> start(String recordingId) async {
    final directory = await recordingsDirectory();
    await directory.create(recursive: true);
    _states ??= recorder.onStateChanged().listen(_onState, onError: (_) {});
    await recorder.start(
      // An interruption (a call) pauses capture; the pause is reported
      // through [interruptions] and the recording is saved (rider-u199).
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        audioInterruption: AudioInterruptionMode.pause,
      ),
      path: '${directory.path}/$recordingId.m4a',
    );
    _capturing = true;
    _background.watch(() => _onState(RecordState.stop));
  }

  @override
  Future<String?> stop() async {
    _capturing = false;
    _background.release();
    final path = await recorder.stop();
    if (path == null || !await File(path).exists()) return null;
    if (await File(path).length() == 0) {
      // rider-u200: an empty take is not kept on the phone.
      await File(path).delete();
      return null;
    }
    return path;
  }

  @override
  Future<void> cancel() async {
    _capturing = false;
    _background.release();
    if (_recorder != null) await _recorder!.cancel();
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
