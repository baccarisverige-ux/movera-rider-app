import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final lifecycle certification suites remain present', () {
    const required = <String>[
      'integration_test/global_uat_flow_test.dart',
      'integration_test/pre15_all_lifecycle_paths_test.dart',
      'integration_test/ride_flow_test.dart',
      'test/ride/batch3_phase44_state_races_test.dart',
      'test/ride/batch3_phase45_persistence_test.dart',
      'test/ride/batch3_phase46_location_recovery_test.dart',
      'test/ride/batch3_phase47_geocoding_privacy_test.dart',
      'test/ride/batch3_phase48_receipt_dispute_wiring_test.dart',
      'test/ride/batch3_phase49_scheduled_saved_places_test.dart',
      'test/ride/batch3_phase50_api_auth_update_test.dart',
      'test/web/pwa_ride_lifecycle_test.dart',
    ];
    for (final path in required) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
