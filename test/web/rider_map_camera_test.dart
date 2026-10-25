import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test('rider-cam-1: web flights and follow glides run on the browser frame '
      'clock, land exactly, keep their speed when retargeted and stop under '
      'a finger', () async {
    final run = await Process.run('node', [
      'test/web/rider_map_camera_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['hasGlide'], isTrue);

    Map<String, dynamic> of(String key) => out[key] as Map<String, dynamic>;
    double lng(Map<String, dynamic> run) =>
        ((run['last'] as Map<String, dynamic>)['lng'] as num).toDouble();

    // A 500 ms flight lands on time (60 fps: 30 frames) on its goal.
    final flight = of('flight');
    expect(flight['landed'], isTrue);
    expect(flight['frames'], inInclusiveRange(29, 32));
    expect((flight['last'] as Map<String, dynamic>)['zoom'], 15);

    // A 300 px follow glide settles in about 450 ms (was 2-3 s), moving
    // one way only, leaving gently and landing exactly.
    final glide = of('glide');
    expect(glide['landed'], isTrue);
    expect(glide['frames'], lessThanOrEqualTo(36), reason: 'under 600 ms');
    expect(glide['monotonic'], isTrue);
    expect(
      glide['firstStep'] as num,
      lessThan((glide['peakStep'] as num) * .8),
      reason: 'it gains speed instead of jumping',
    );
    expect(lng(glide), closeTo(18.06 + 300 / (256 * 8192 / 360), 1e-9));

    // Zoom and heading are no slower than the pan.
    final zoomTurn = of('zoomTurn');
    expect(zoomTurn['landed'], isTrue);
    expect(zoomTurn['frames'], lessThanOrEqualTo(40));
    expect((zoomTurn['last'] as Map<String, dynamic>)['zoom'], 14);
    expect((zoomTurn['last'] as Map<String, dynamic>)['heading'], 40);

    // A newer goal keeps the glide's speed: no stop, no restart from rest.
    final retarget = of('retarget');
    expect(retarget['landed'], isTrue);
    expect(retarget['stalled'], isFalse);
    expect(
      retarget['after'] as num,
      greaterThanOrEqualTo(retarget['before'] as num),
    );
    expect(lng(retarget), closeTo(18.06 + 600 / (256 * 8192 / 360), 1e-9));

    // A finger ends the glide at once (Dart is told it did not land).
    final touch = of('touch');
    expect(touch['result'], isFalse);
    expect(touch['movedAfter'], 0);

    // Cancelling hands back where the camera stopped, and it stays there.
    final cancel = of('cancel');
    expect(cancel['pose'], cancel['live']);
    expect(cancel['movedAfter'], 0);
  }, skip: _hasNode() ? false : 'node is not installed');
}
