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
  test('rider-r4-19: Back at Home is blocked without a popstate loop, history '
      'does not grow per Home round trip, and Back away from Home still '
      'reaches Flutter', () async {
    final run = await Process.run('node', [
      'test/web/home_lock_history_harness.js',
      'lib/core/web/web_overlay_web.dart',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final out = jsonDecode(run.stdout as String) as Map<String, dynamic>;
    final home = out['atHome'] as Map<String, dynamic>;
    // The engine's two entries only: origin + flutter.
    expect(home['lengthAtHome'], 2);
    expect(home['settled'], isTrue);
    expect(home['popstates'], 1);
    expect(home['leftSite'], isFalse);
    expect(home['popRoutes'], isEmpty);
    expect(home['top'], {'flutter': true});
    expect(out['awayPopRoutes'], ['/']);
  }, skip: _hasNode() ? false : 'node is not installed');
}
