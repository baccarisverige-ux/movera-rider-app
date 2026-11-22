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
    // The real script, run in a copy of the layout it expects (tool/ next
    // to pubspec.yaml) with a version this test chose.
    final root = Directory.systemTemp.createTempSync('movera_app_version');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/tool').createSync();
    final script = File(
      'tool/app_version.sh',
    ).copySync('${root.path}/tool/app_version.sh');
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: movera_rider\nversion: 9.8.7+123\nenvironment:\n  sdk: ^3.0.0\n',
    );

    final withBuild = Process.runSync('sh', [script.path, '7']);
    expect(withBuild.exitCode, 0, reason: '${withBuild.stderr}');
    expect((withBuild.stdout as String).trim(), '9.8.7+7');

    final plain = Process.runSync('sh', [script.path]);
    expect(plain.exitCode, 0, reason: '${plain.stderr}');
    expect((plain.stdout as String).trim(), '9.8.7');

    // And here: this app's own version, x.y.z.
    final own = Process.runSync('sh', ['tool/app_version.sh']);
    expect(own.exitCode, 0);
    expect((own.stdout as String).trim(), matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });
}
