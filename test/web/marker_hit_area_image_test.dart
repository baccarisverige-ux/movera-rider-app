import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner decision (rider map, 2026-10-30): no broken-image box around the
/// rider's dot. Google's legacy marker hit area is an <img> of
/// mapfiles/transparent.png; when it fails to load the browser frames it.
void main() {
  test('web/index.html styles hide the marker hit-area image inside the '
      'map, and only that image', () async {
    final run = await Process.run('node', [
      'test/web/marker_hit_area_harness.js',
      'web/index.html',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['rules'], greaterThan(0));
    expect(out['hitArea'], 'hidden');
    expect(out['tile'], 'visible', reason: 'map tiles must stay visible');
    expect(out['outside'], 'visible', reason: 'scoped to .gm-style only');
  });
}
