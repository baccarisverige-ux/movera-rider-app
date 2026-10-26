import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/formatters/name_format.dart';

/// Phase 132 cluster 5: driver-initial logic was duplicated verbatim in
/// MatchedDriver.initial and ReservationDriver.initial, plus a third,
/// slightly different version inline in driver_info.dart (which fell back
/// to '?' instead of '' for an empty name). [initialFromName] covers both
/// shapes via its whenEmpty parameter, verified against each old formula.
void main() {
  String oldEntityInitial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.substring(0, 1).toUpperCase();
  }

  String oldDriverInfoInitial(String name) {
    return name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();
  }

  test('matches MatchedDriver/ReservationDriver.initial for typical names', () {
    for (final name in ['Erik', 'anna', '  Björn  ', '', '   ']) {
      expect(initialFromName(name), oldEntityInitial(name));
    }
  });

  test('matches driver_info.dart inline formula with whenEmpty: "?"', () {
    for (final name in ['Erik', 'anna', '  Björn  ', '', '   ']) {
      expect(initialFromName(name, whenEmpty: '?'), oldDriverInfoInitial(name));
    }
  });
}
