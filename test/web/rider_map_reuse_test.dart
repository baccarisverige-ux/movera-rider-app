import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rider-cam-reuse: a pooled web map handed to the next screen is '
      'reported created (first tilesloaded replayed) and opens on that '
      "screen's own camera", () async {
    final run = await Process.run('node', [
      'test/web/rider_map_reuse_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['firstReady'], isTrue);
    expect(out['pooled'], 1);
    expect(out['reused'], isTrue, reason: 'the pooled map is reused');
    expect(
      out['secondReady'],
      isTrue,
      reason:
          'google_maps_flutter_web fires onMapCreated on the first '
          'tilesloaded; a reused map must still deliver one',
    );
    final camera = out['camera'] as Map<String, dynamic>;
    expect(camera['lat'], closeTo(59.33, 1e-9));
    expect(camera['lng'], closeTo(18.06, 1e-9));
    expect(camera['zoom'], 16);
  });

  test('rider map: a reused pooled map is told to measure its new element '
      "('resize') before its camera is set, and again after layout "
      '(no grey band)', () async {
    final run = await Process.run('node', [
      'test/web/rider_map_reuse_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['reused'], isTrue, reason: 'the pooled map is reused');
    expect(out['reuseResized'], 2);
    expect(out['resizeBeforeCamera'], isTrue);
  });

  test('rider map: redraw(id) makes Google measure the grown element '
      'again and redraw on the same camera', () async {
    final run = await Process.run('node', [
      'test/web/rider_map_reuse_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    final redraw = out['redraw'] as Map<String, dynamic>;
    expect(redraw['resized'], 1);
    expect(redraw['centerSet'], 1);
    expect(redraw['lat'], closeTo(59.33, 1e-9));
    expect(redraw['lng'], closeTo(18.06, 1e-9));
  });

  Future<Map<String, dynamic>> runHarness([
    String search = '',
    String stored = '',
  ]) async {
    final run = await Process.run('node', [
      'test/web/rider_map_reuse_harness.js',
      'web/rider_map_camera.js',
      search,
      stored,
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    return jsonDecode(run.stdout as String) as Map<String, dynamic>;
  }

  test('rider map test switch: without ?mappool=0 the pool is kept and '
      'nothing is logged (real riders unchanged)', () async {
    final out = await runHarness();
    expect(out['poolMax'], 2);
    expect(out['reused'], isTrue);
    expect(out['created'], 1);
    expect(out['recycled'], 1);
    expect(out['stored'], isNull);
    expect(out['sizeLogs'], isEmpty);
  });

  test('rider map test switch: ?mappool=0 disables reuse (a fresh Map per '
      'screen, the old one released) and logs sizes', () async {
    final out = await runHarness('?mappool=0');
    expect(out['poolMax'], 0);
    expect(out['reused'], isFalse);
    expect(out['created'], 2);
    expect(out['recycled'], 0);
    expect(out['released'], 1, reason: 'a removed map is still gutted');
    expect(out['pooled'], 0);
    expect(out['secondReady'], isTrue);
    expect(out['stored'], '0', reason: 'kept for the session');
    final logs = (out['sizeLogs'] as List).cast<Map<String, dynamic>>();
    expect(
      logs.map((l) => '${l['id']}:${l['phase']}'),
      containsAll(['1:shown', '1:settled', '2:shown', '2:settled']),
    );
    for (final log in logs) {
      expect(
        log.keys,
        containsAll(['element', 'container', 'mapDiv', 'canvas', 'pool']),
      );
    }
  });

  test('rider map test switch: kept in sessionStorage after in-app '
      'navigation drops the query; ?mappool=1 turns it off', () async {
    final kept = await runHarness('', '0');
    expect(kept['poolMax'], 0);
    expect(kept['reused'], isFalse);
    final off = await runHarness('?mappool=1', '0');
    expect(off['poolMax'], 2);
    expect(off['reused'], isTrue);
    expect(off['stored'], isNull);
  });
}
