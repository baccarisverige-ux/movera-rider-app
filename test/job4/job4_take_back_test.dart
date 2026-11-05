import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// FIX JOB 4 "take-back" (contract v0.18.35 §59). Rider app: no new screen.
/// Owner job-4 Q2: before the booked driver starts driving the rider sees
/// nothing; after it, the existing "searching" screen and the
/// `trip_update` / `driver_changed` push. Owner Q3: no late message.
/// Owner Q-A: a live ride is never taken back.
void main() {
  final c =
      jsonDecode(File('contracts/contract.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the rider is told through the existing driver_changed moment', () {
    final take = c['bookedTakeBack'] as Map;
    expect(take['rider'], contains('driver_changed'));
    expect((c['riderTripPush'] as Map)['moments'], contains('driver_changed'));
  });

  test('live rides are never taken back (reassign false)', () {
    final heading = (c['configDefaults'] as Map)['headingCheck'] as Map;
    expect(heading['reassign'], isFalse);
  });
}
