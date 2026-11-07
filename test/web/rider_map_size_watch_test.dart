import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Grey band (owner 2026-11-07 23:00, rider Home: a flat grey band above the
/// sheet that goes away after a zoom). Maps JS measures its element only
/// when its hidden size frame fires 'load' or 'resize'; when the browser
/// misses those, Google keeps drawing the old height. The rider layer
/// watches each map's element and runs Google's own measuring once the
/// element's size changes.
void main() {
  Future<Map<String, dynamic>> runHarness() async {
    final run = await Process.run('node', [
      'test/web/rider_map_size_watch_harness.js',
      'web/rider_map_camera.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    return jsonDecode(run.stdout as String) as Map<String, dynamic>;
  }

  test('rider map: a map element that grows is measured again by Google '
      'without a zoom (no grey band)', () async {
    final out = await runHarness();
    expect(out['watched'], isTrue, reason: "each map's element is watched");
    expect(out['firstSize'], 555);
    expect(
      out['grownSize'],
      844,
      reason: 'Google must draw the grown element, not its old 555 px',
    );
  });

  test('rider map size watch: one measure per frame, none while the map is '
      'out of the page, and the camera is never moved (no flight)', () async {
    final out = await runHarness();
    expect(out['measuredSync'], 0, reason: 'waits for the next frame');
    expect(out['measuresForGrow'], 1, reason: 'three reports, one measure');
    expect(out['measuresWhenHidden'], 0);
    expect(out['cameraCalls'], {'moves': 0, 'centers': 0, 'zooms': 0});
    expect(out['cameraKept'], isTrue);
  });

  test('rider map size watch: a map moved into a new box whose frame never '
      'fired its load is still measured, and a pooled map stays '
      'watched', () async {
    final out = await runHarness();
    expect(out['newWindowSize'], 621);
    expect(out['pooled'], 1);
    expect(out['pooledStillWatched'], isTrue);
  });
}
