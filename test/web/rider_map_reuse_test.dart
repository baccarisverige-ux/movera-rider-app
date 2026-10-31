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
    expect(camera['zoom'], 13.5);
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
}
