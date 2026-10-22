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
  test('rider-21: the app loads without Flutter\'s service worker, so it '
      'never replaces the root-scope Firebase push worker', () async {
    final run = await Process.run('node', [
      'test/web/flutter_bootstrap_harness.js',
      'web/flutter_bootstrap.js',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final calls = (jsonDecode(run.stdout as String) as Map)['calls'] as List;
    expect(calls, hasLength(1), reason: 'the app is loaded once');
    final config = calls.single as Map?;
    expect(config?['serviceWorkerSettings'], isNull);
  }, skip: _hasNode() ? false : 'node is not installed');
}
