import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI workflow guards (AUDIT-R10, AUDIT-R11).
void main() {
  String read(String name) =>
      File('.github/workflows/$name').readAsStringSync();

  test('D11 (R11-11): the test APK uses only the Android Maps key', () {
    final yml = read('android-test-apk.yml');
    final line = RegExp(
      r'^\s*MAPS_API_KEY:.*$',
      multiLine: true,
    ).firstMatch(yml)!.group(0)!;
    for (final web in [
      'MAPS1',
      'secrets.MAPS ',
      'secrets.MAPS }',
      'GOOGLE_MAPS_WEB_API_KEY',
      'GOOGLE_MAPS_API_KEY',
    ]) {
      expect(line, isNot(contains(web)), reason: web);
    }
    expect(line, contains('secrets.ANDROID_MAPS_API_KEY'));
    expect(yml, isNot(contains('TEST_BUILD_NO_MAP')));
    expect(yml, contains('::error::Missing Android Google Maps key'));
  });

  test('D12 (R10 #14): the live web build has the same size budget as CI', () {
    final budget = RegExp(
      r'python3 tool/check_web_budget\.py build/web --main-raw \d+ --main-gzip \d+',
    );
    final ci = budget.firstMatch(read('ci.yml'))!.group(0)!;
    expect(read('publish-web-live.yml'), contains(ci));
  });
}
