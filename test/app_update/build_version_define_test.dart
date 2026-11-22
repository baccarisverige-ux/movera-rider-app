import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract v0.18.154 P16c (contract.json#appUpdate.headers): every Android
/// / iOS build in .github/workflows passes --dart-define=MOVERA_APP_VERSION,
/// so the store build carries the minimum-version check (a build without
/// it is "dev": never checked, no X-App-Version). A command whose output
/// goes to /tmp is a must-fail check build and is left out.
void main() {
  test('every mobile build workflow passes MOVERA_APP_VERSION', () {
    final missing = <String>[];
    var seen = 0;
    final files = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(
          r'flutter build (apk|appbundle|ios|ipa)\b',
        ).hasMatch(lines[i])) {
          continue;
        }
        final command = StringBuffer(lines[i]);
        var j = i;
        while (lines[j].trimRight().endsWith(r'\') && j + 1 < lines.length) {
          command.write(lines[++j]);
        }
        final text = command.toString();
        if (text.contains('> /tmp/')) continue;
        seen++;
        if (!text.contains('--dart-define=MOVERA_APP_VERSION=')) {
          missing.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(seen, greaterThan(0));
    expect(missing, isEmpty);
  });

  test('tool/app_version.sh prints the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: *([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    final out = Process.runSync('sh', ['tool/app_version.sh', '7']);
    expect(out.exitCode, 0);
    expect((out.stdout as String).trim(), '$version+7');
  });
}
