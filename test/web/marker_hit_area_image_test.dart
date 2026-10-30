import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner decision (rider map, 2026-10-30): no broken-image box around the
/// rider's dot. Google's legacy marker hit area is an <img> of
/// mapfiles/transparent.png; when it fails to load the browser frames it.
void main() {
  test('web/index.html hides the marker hit-area image', () {
    final html = File('web/index.html').readAsStringSync();
    final rule = RegExp(
      r'\.gm-style\s+img\[src\*="/mapfiles/transparent\.png"\]\s*\{\s*'
      r'visibility:\s*hidden',
    );
    expect(rule.hasMatch(html), isTrue);
  });
}
