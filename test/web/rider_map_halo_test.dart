import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-10-31 (plan/rider-pin/SPEC.md): on the web the accuracy halo
/// under the rider's pin is drawn by web/rider_map_camera.js. It runs here
/// against a fake Google map (node), not read as text.
void main() {
  test('rider-pin: the web halo is grey #7797A8 at 35 %, no border, and 60 '
      'pt on screen at every zoom step', () async {
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
    // Owner: "Blue must be same in all zoom steps": 60 pt at every zoom,
    // re-sized in the same camera move as each zoom step.
    expect(out['at15'] as num, closeTo(60, 1e-6));
    expect(out['at11'] as num, closeTo(60, 1e-6));
    final pinch = (out['pinch'] as List).cast<Map<String, dynamic>>();
    expect(pinch.map((s) => s['zoom']), containsAll([12, 14.5, 17, 19]));
    for (final step in pinch) {
      expect(step['points'] as num, closeTo(60, 1e-6), reason: '$step');
    }
    // A new fix moves the same circle; neither a 5 km nor an unknown
    // accuracy changes its size.
    expect(out['afterMove'], {'circles': 1, 'lat': 59.21});
    expect(out['worseFix'] as num, closeTo(60, 1e-6));
    expect(out['unknown'] as num, closeTo(60, 0.1));
    // A null centre removes it.
    expect(out['removed'], {'onMap': false, 'haloOf': null});
  });
}
