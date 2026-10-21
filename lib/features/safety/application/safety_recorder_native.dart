import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'safety_recorder_stub.dart';

export 'safety_recorder_stub.dart'
    show SafetyRecorder, SafetyRecorderInterruptions;

SafetyRecorder createSafetyRecorder() => NativeSafetyRecorder();

class NativeSafetyRecorder
    implements SafetyRecorder, SafetyRecorderInterruptions {
  AudioRecorder? _recorder;
  final _interrupted = StreamController<void>.broadcast();
  StreamSubscription<RecordState>? _states;
  bool _capturing = false;

  AudioRecorder get recorder => _recorder ??= AudioRecorder();

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
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/safety_recordings',
    );
    await directory.create(recursive: true);
    _states ??= recorder.onStateChanged().listen(_onState, onError: (_) {});
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: '${directory.path}/$recordingId.m4a',
    );
    _capturing = true;
  }

  @override
  Future<String?> stop() async {
    _capturing = false;
    final path = await recorder.stop();
    if (path == null || !await File(path).exists() || await File(path).length() == 0) {
      return null;
    }
    return path;
  }

  @override
  Future<void> cancel() async {
    _capturing = false;
    if (_recorder != null) await _recorder!.cancel();
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
