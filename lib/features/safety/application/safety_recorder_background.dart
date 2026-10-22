import 'package:flutter/widgets.dart';

/// rider-u206: on Android a backgrounded app gets silence from the
/// microphone unless a microphone foreground service runs, and the record
/// plugin in use (7.1) has none. Where that is so ([endsCapture]), capture
/// is treated as ended when the app leaves the foreground (the 112 dialer
/// opens, the screen locks), so the recording is saved with what it holds
/// instead of claiming silent minutes.
class BackgroundCaptureGuard {
  BackgroundCaptureGuard({required this.endsCapture});

  final bool endsCapture;
  AppLifecycleListener? _listener;

  /// Calls [onBackground] once the app is hidden, until [release].
  void watch(void Function() onBackground) {
    release();
    if (!endsCapture) return;
    _listener = AppLifecycleListener(onHide: onBackground);
  }

  void release() {
    _listener?.dispose();
    _listener = null;
  }
}
