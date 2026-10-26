import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unused legacy scheduled-ride surfaces stay removed', () {
    const removed = [
      'lib/features/scheduled_rides/data/scheduled_rides_repository.dart',
      'lib/features/history/data/scheduled_ride_cards.dart',
      'lib/features/history/presentation/my_rides.dart',
      'lib/features/history/presentation/my_rides_requests.dart',
      'lib/features/history/presentation/my_rides_confirmed.dart',
    ];
    for (final path in removed) {
      expect(File(path).existsSync(), isFalse, reason: 'Legacy file returned');
    }
  });
}
