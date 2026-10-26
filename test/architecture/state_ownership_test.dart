import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';

void main() {
  test('local transitions reject illegal authoritative jumps', () {
    final ride = RideSession();

    expect(
      () => ride.localTransition(RideStatus.driverAssigned),
      throwsA(isA<InvalidRideTransition>()),
    );
    expect(ride.status, RideStatus.idle);
  });

  test('backend reconciliation accepts forward projection and rejects stale version', () {
    final ride = RideSession();

    expect(
      ride.backendReconcile(
        RideStatus.driverAssigned,
        id: 'trip-26',
        version: 5,
        updatedAt: DateTime.utc(2026, 9, 23, 10),
      ),
      isTrue,
    );
    expect(ride.status, RideStatus.driverAssigned);

    expect(
      ride.backendReconcile(
        RideStatus.findingDriver,
        id: 'trip-26',
        version: 4,
        updatedAt: DateTime.utc(2026, 9, 23, 11),
      ),
      isFalse,
    );
    expect(ride.status, RideStatus.driverAssigned);
  });

  test('completed surfaces may be explicitly closed by the rider', () {
    for (final status in <RideStatus>[
      RideStatus.tripCompleted,
      RideStatus.paymentProcessing,
      RideStatus.paymentFinalized,
      RideStatus.ratingPending,
    ]) {
      expect(canTransition(status, RideStatus.closed), isTrue);
    }
  });
}
