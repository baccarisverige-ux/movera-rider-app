import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

RideSnapshot _snapshot(RideStatus status, {DateTime? savedAt}) {
  return RideSnapshot(
    status: status,
    savedAt: savedAt ?? DateTime.now(),
    pickupAddress: 'A',
    destinationAddress: 'B',
    pickupLat: 59.3,
    pickupLng: 18.0,
    destinationLat: 59.4,
    destinationLng: 18.1,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: 'matrix-ride',
  );
}

void main() {
  test('every fresh ride status restores to exactly one expected surface', () {
    const finding = {
      RideStatus.bookingRequested,
      RideStatus.findingDriver,
      RideStatus.searchDelayed,
    };
    const waiting = {
      RideStatus.driverAssigned,
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
      RideStatus.approachingDropoff,
    };
    const complete = {
      RideStatus.tripCompleted,
      RideStatus.paymentProcessing,
      RideStatus.paymentFinalized,
      RideStatus.ratingPending,
    };

    final coordinator = RideRestoreCoordinator(reader: () async => null);

    for (final status in RideStatus.values) {
      final expected = status.isTerminal
          ? RestoredSurface.home
          : finding.contains(status)
          ? RestoredSurface.finding
          : waiting.contains(status)
          ? RestoredSurface.waiting
          : complete.contains(status)
          ? RestoredSurface.complete
          : RestoredSurface.home;
      expect(
        coordinator.surfaceFor(_snapshot(status)),
        expected,
        reason: 'unexpected restore surface for ${status.name}',
      );
    }
  });

  test(
    'every stale ride status restores Home, including otherwise active states',
    () {
      final coordinator = RideRestoreCoordinator(reader: () async => null);
      final staleAt = DateTime.now().subtract(const Duration(days: 1));

      for (final status in RideStatus.values) {
        expect(
          coordinator.surfaceFor(_snapshot(status, savedAt: staleAt)),
          RestoredSurface.home,
          reason: 'stale ${status.name} must never restore an active surface',
        );
      }
    },
  );

  test('null snapshot is the inverse of restore and lands Home', () {
    final coordinator = RideRestoreCoordinator(reader: () async => null);
    expect(coordinator.surfaceFor(null), RestoredSurface.home);
  });
}
