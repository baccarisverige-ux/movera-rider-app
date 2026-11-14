import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';

import 'contract_fixtures.dart';

/// The repo ships a byte-for-byte copy of the shared contract (v0.9.0, from the movera-contracts repository).
/// CHECKSUMS is written by the sync script; a hand edit of any contract file
/// fails here.
void main() {
  test('every contract file matches contracts/CHECKSUMS', () {
    final lines = utf8
        .decode(File('contracts/CHECKSUMS').readAsBytesSync())
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    expect(lines, isNotEmpty);
    final listed = <String>{};
    for (final line in lines) {
      final match = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line);
      expect(match, isNotNull, reason: line);
      final path = match!.group(2)!;
      listed.add(path);
      final digest = sha256.convert(File('contracts/$path').readAsBytesSync());
      expect(digest.toString(), match.group(1), reason: path);
    }
    final onDisk = Directory('contracts')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.substring('contracts/'.length))
        .where((path) => path != 'CHECKSUMS' && !path.contains('__pycache__'))
        .toSet();
    expect(onDisk, listed, reason: 'files added or removed without a re-sync');
  });

  test('the copy is contract v0.18.92', () {
    expect(contract['contract'], 'movera');
    expect(contract['version'], '0.18.92');
    expect(TripStateMachine.contractVersion, contract['version']);
  });

  // v0.18.89 / v0.18.92 (BQ-M22): the cancel sheet reads the server's
  // TripProjection.cancelPreview; the copy carries the field and its rule.
  test('v0.18.92: priceDisplay.cancelPreview is in the copy', () {
    final price = contract['priceDisplay'] as Map<String, dynamic>;
    final preview = price['cancelPreview'] as Map<String, dynamic>;
    expect(preview['apps'], isA<String>());
  });
}
