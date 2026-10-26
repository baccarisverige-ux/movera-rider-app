import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test(
    'realtime event exposes shared platform metadata with legacy aliases',
    () {
      final occurred = DateTime.utc(2026, 9, 23, 6);
      final event = RideRealtimeEvent(
        tripId: 'trip-1',
        eventId: 'evt-1',
        status: RideStatus.driverAssigned,
        sequence: 7,
        version: 3,
        occurredAt: occurred,
        serverTime: occurred.add(const Duration(milliseconds: 10)),
        payload: const {'source': 'dispatch'},
      );

      expect(event.tripId, 'trip-1');
      expect(event.rideId, 'trip-1');
      expect(event.eventId, 'evt-1');
      expect(event.sequence, 7);
      expect(event.version, 3);
      expect(event.occurredAt, occurred);
      expect(event.at, occurred);
      expect(event.payload['source'], 'dispatch');
    },
  );

  test('backend version wins ordering when both events have versions', () {
    final old = RideRealtimeEvent(
      tripId: 'trip-1',
      status: RideStatus.driverAssigned,
      sequence: 100,
      version: 4,
    );
    final next = RideRealtimeEvent(
      tripId: 'trip-1',
      status: RideStatus.driverArriving,
      sequence: 2,
      version: 5,
    );

    expect(next.isNewerThan(old), isTrue);
    expect(old.isNewerThan(next), isFalse);
  });

  test('sequence orders legacy events when backend version is absent', () {
    final old = RideRealtimeEvent(
      tripId: 'trip-1',
      status: RideStatus.findingDriver,
      sequence: 4,
    );
    final next = RideRealtimeEvent(
      tripId: 'trip-1',
      status: RideStatus.driverAssigned,
      sequence: 5,
    );

    expect(next.isNewerThan(old), isTrue);
  });
}
