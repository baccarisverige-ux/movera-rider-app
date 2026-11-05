import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fix job 9 (contract v0.18.36 §60), RULE 0 check for the rider app: the
/// airport queue is a driver + admin + server feature. Owner job 9 Q6
/// (2026-11-05): riders see NOTHING of it, so the rider app has no new screen
/// and no rider route or trip field carries a queue.
void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync())
          as Map<String, dynamic>;
  final openapi = File('contracts/openapi.yaml').readAsStringSync();

  test(
    'contract (v0.18.36 on) has the airport queue and says riders see nothing',
    () {
      final queue = contract['airportQueue'] as Map<String, dynamic>?;
      expect(queue, isNotNull);
      expect(queue!['riders'], contains('riders see nothing'));
    },
  );

  test('no rider operation and no TripProjection field names the queue', () {
    // Every queue operation is driver or admin only.
    final ops = RegExp(
      r'operationId: (\w*[Aa]irportQueue\w*)[\s\S]*?x-actor:\n((?:\s+- \w+\n)+)',
    ).allMatches(openapi).toList();
    expect(ops.length, 4);
    for (final op in ops) {
      expect(op.group(2), isNot(contains('rider')), reason: op.group(1));
    }
    final trip = RegExp(
      r'\n    TripProjection:\n([\s\S]*?)\n    \w+:\n',
    ).firstMatch(openapi)!.group(1)!;
    expect(trip.toLowerCase(), isNot(contains('airportqueue')));
  });
}
