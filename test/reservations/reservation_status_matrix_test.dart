import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

void main() {
  test('reservation status capabilities are exact for every forward and inverse state', () {
    const upcoming = {
      ReservationStatus.scheduled,
      ReservationStatus.driverAssignmentPending,
      ReservationStatus.driverAssigned,
      ReservationStatus.driverEnRoute,
      ReservationStatus.driverArrived,
      ReservationStatus.inProgress,
    };
    const withDriver = {
      ReservationStatus.driverAssigned,
      ReservationStatus.driverEnRoute,
      ReservationStatus.driverArrived,
      ReservationStatus.inProgress,
      ReservationStatus.completed,
    };
    const editable = {
      ReservationStatus.scheduled,
      ReservationStatus.driverAssignmentPending,
      ReservationStatus.driverAssigned,
      ReservationStatus.driverEnRoute,
      ReservationStatus.driverArrived,
    };
    const driverOnTheWay = {
      ReservationStatus.driverEnRoute,
      ReservationStatus.driverArrived,
      ReservationStatus.inProgress,
    };

    for (final status in ReservationStatus.values) {
      expect(
        status.isUpcoming,
        upcoming.contains(status),
        reason: '${status.name}.isUpcoming',
      );
      expect(
        status.hasDriver,
        withDriver.contains(status),
        reason: '${status.name}.hasDriver',
      );
      expect(
        status.canEdit,
        editable.contains(status),
        reason: '${status.name}.canEdit',
      );
      expect(
        status.canCancel,
        upcoming.contains(status),
        reason: '${status.name}.canCancel',
      );
      expect(
        status.isSearchingDriver,
        status == ReservationStatus.driverAssignmentPending,
        reason: '${status.name}.isSearchingDriver',
      );
      expect(
        status.isDriverOnTheWay,
        driverOnTheWay.contains(status),
        reason: '${status.name}.isDriverOnTheWay',
      );
      expect(status.isCompleted, status == ReservationStatus.completed);
      expect(status.isCancelled, status == ReservationStatus.cancelled);
    }
  });

  test(
    'unknown persisted reservation status falls back safely to scheduled',
    () {
      expect(ReservationStatus.parse(null), ReservationStatus.scheduled);
      expect(ReservationStatus.parse(''), ReservationStatus.scheduled);
      expect(
        ReservationStatus.parse('not-a-real-status'),
        ReservationStatus.scheduled,
      );
    },
  );

  test('every persisted reservation status round-trips by name', () {
    for (final status in ReservationStatus.values) {
      expect(ReservationStatus.parse(status.name), status);
    }
  });
}
