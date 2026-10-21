// rider-u206: Safety audio stopped capturing when the app went to the
// background or the 112 dialer opened: iOS had no audio background mode,
// and on Android a backgrounded app records silence while the saved
// recording claimed the full time.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/safety/application/safety_recorder_background.dart';

void main() {
  // The iOS audio background mode is checked with the other Info.plist
  // release checks in test/platform/audit_fix_release_readiness_test.dart.

  testWidgets('where the background silences the mic, capture ends when the '
      'app leaves the foreground', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var ended = 0;
    final guard = BackgroundCaptureGuard(endsCapture: true)
      ..watch(() => ended++);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(ended, 0, reason: 'a dialog or the app switcher is not background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(ended, 1);
    guard.release();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('where recording continues in the background, nothing ends', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var ended = 0;
    final guard = BackgroundCaptureGuard(endsCapture: false)
      ..watch(() => ended++);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(ended, 0);
    guard.release();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
