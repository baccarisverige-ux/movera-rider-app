import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';

void main() {
  test('obsolete confirmation screens are gone; Plan your ride stays', () {
    expect(
      File(
        'lib/features/scheduled_rides/presentation/ride_confirmed.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/ride_pending.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/confirm_booking.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/add_note.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/cancel_ride.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/scheduled_rides/presentation/schedule_ride.dart',
      ).existsSync(),
      isTrue,
    );
    expect(const ScheduleRide(), isA<ScheduleRide>());
  });
}
