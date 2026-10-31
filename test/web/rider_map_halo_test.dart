import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-10-31 (plan/rider-pin/SPEC.md): on the web the accuracy halo
/// under the rider's pin is drawn by web/rider_map_camera.js. It runs here
/// against a fake Google map (node), not read as text.
void main() {
  test('rider-pin: the web halo is grey #7797A8 at 35 %, no border, its real '
      'accuracy kept 60-110 pt on screen on every zoom step', () async {
    final run = await Process.run('node', [
      'test/web/rider_map_halo_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['hasHalo'], isTrue);
    expect(out['options'], {
      'fillColor': '#7797A8',
      'fillOpacity': 0.35,
      'strokeWeight': 0,
      'onMap': true,
    });
    expect(out['circles'], 1);
    // Zoomed out: a 40 m fix keeps the 60 pt minimum.
    expect(out['at15'] as num, closeTo(60, 1e-6));
    expect(out['at11'] as num, closeTo(60, 1e-6));
    // Each zoom step of a pinch re-clamps it in the same camera move.
    final pinch = (out['pinch'] as List).cast<Map<String, dynamic>>();
    for (final step in pinch) {
      expect(step['points'] as num, inInclusiveRange(60 - 1e-6, 110 + 1e-6));
    }
    // In between the clamps it is the real accuracy (40 m).
    final real = pinch.where((s) => s['zoom'] == 17 || s['zoom'] == 17.5);
    expect(real.map((s) => s['meters']), everyElement(40));
    // Zoomed in: capped at 110 pt.
    expect(pinch.last['points'] as num, closeTo(110, 1e-6));
    // A new fix moves the same circle; unknown accuracy is the minimum.
    expect(out['afterMove'], {'circles': 1, 'lat': 59.21});
    expect(out['unknown'] as num, closeTo(60, 0.1));
    // A null centre removes it.
    expect(out['removed'], {'onMap': false, 'haloOf': null});
  });
}
