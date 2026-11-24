import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner 2026-11-24: the safety kit showed 3 times while searching. The old
/// SafetyKitSheetRow is not shown on the searching screen (the round quick
/// action and the top-right button stay); the widget itself is kept and is
/// still used on the waiting and in-trip sheets.
void main() {
  test('searching sheet does not build SafetyKitSheetRow; the widget stays', () {
    final searching = File(
      'lib/features/finding_driver/presentation/finding_drivers_map_panel.dart',
    ).readAsStringSync();
    expect(searching.contains('SafetyKitSheetRow('), isFalse);
    expect(
      File(
        'lib/features/safety/presentation/ride_safety_kit.dart',
      ).readAsStringSync(),
      contains('class SafetyKitSheetRow'),
    );
    expect(
      File(
        'lib/features/active_ride/presentation/rider_in_trip_panel.dart',
      ).readAsStringSync(),
      contains('SafetyKitSheetRow('),
    );
  });
}
