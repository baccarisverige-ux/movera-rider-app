import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Finder (2026-11-07): rider web/index.html deleted ALL Cache Storage of
/// the origin on every boot. The rider and the driver web apps share one
/// origin (baccarisverige-ux.github.io), so this also wiped the driver
/// app's caches (its push preferences, `movera-push-prefs`), and removed
/// the driver's service workers. The clean-up is for the rider's own old
/// Flutter service worker only.
void main() {
  Future<Map<String, dynamic>> run() async {
    final result = await Process.run('node', [
      'test/web/boot_cleanup_harness.js',
      'web/index.html',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  test("the driver app's caches survive the rider's boot", () async {
    final out = await run();
    expect(out['deleted'], isNot(contains('movera-push-prefs')));
  });

  test("the driver app's service workers survive the rider's boot", () async {
    final out = await run();
    final gone = (out['unregistered'] as List).cast<String>();
    expect(gone.where((s) => s.contains('/Movera-driver-app/')), isEmpty);
  });

  test("the rider's own old Flutter worker and its caches are removed", () async {
    final out = await run();
    expect(out['unregistered'], [
      'https://baccarisverige-ux.github.io/movera-rider-app/flutter_service_worker.js',
    ]);
    expect(
      out['deleted'],
      containsAll([
        'flutter-app-cache',
        'flutter-temp-cache',
        'flutter-app-manifest',
      ]),
    );
  });
}
