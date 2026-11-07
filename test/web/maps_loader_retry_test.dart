import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Finder C3: web/index.html set moveraGoogleMapsRequested before adding
/// the Maps script and had no onerror, so one failed load (a network
/// switch) left every map unavailable until the page was reloaded.
void main() {
  test('a failed Maps script load lets the next ask load it again', () async {
    final run = await Process.run('node', [
      'test/web/maps_loader_retry_harness.js',
      'web/index.html',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    expect(out['scripts'], 2, reason: 'one script, then one after the error');
    expect(out['firstRemoved'], isTrue);
  });
}
