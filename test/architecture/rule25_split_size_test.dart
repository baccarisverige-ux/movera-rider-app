import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Rule 25 (owner): no hand-written source file over 1500 lines. The Home
// and Set pickup screens were split (2026-11-07, no behaviour change); this
// keeps each of their files, and every part file they name, under the limit
// so the next change does not grow them back.
void main() {
  const limit = 1500;
  const libraries = [
    'lib/features/home/presentation/home.dart',
    'lib/features/pickup/presentation/set_pickup_page.dart',
    'lib/core/api/in_process_mock_client.dart',
  ];

  for (final library in libraries) {
    test('Rule 25: $library and its part files stay under $limit lines', () {
      final source = File(library).readAsStringSync();
      final dir = File(library).parent.path;
      final parts = RegExp(
        r"^part '([^']+)';",
        multiLine: true,
      ).allMatches(source).map((m) => '$dir/${m.group(1)}').toList();
      expect(parts, isNotEmpty, reason: '$library is split into parts');
      for (final path in [library, ...parts]) {
        final lines = File(path).readAsLinesSync().length;
        expect(lines, lessThan(limit), reason: '$path has $lines lines');
      }
    });
  }
}
