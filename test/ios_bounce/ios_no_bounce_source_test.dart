import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-11-24: nothing in the rider app may bounce past its edge on
/// iOS. A hard-coded bouncing physics would override the app's clamping
/// scroll behaviour, so none may be added back.
void main() {
  test('no bouncing physics in lib/', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'Bouncing(Scroll|Sheet)Physics\(').hasMatch(lines[i])) {
          hits.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('MaterialApp uses the Movera clamping scroll behaviour', () {
    final src = File('lib/app/app.dart').readAsStringSync();
    expect(src, contains('scrollBehavior: const MoveraScrollBehavior()'));
  });

  test('every smooth_sheets Sheet uses the clamping Movera physics', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'\b(Sheet|PagedSheet)\(').allMatches(src)) {
        final window = src.substring(
          m.start,
          (m.start + 400).clamp(0, src.length),
        );
        if (!window.contains('physics: MoveraSheetMotion.physics')) {
          bad.add('${f.path}@${m.start}');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
