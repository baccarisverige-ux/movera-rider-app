import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// Writes one reservation lifecycle step. Returns false when the ride has
/// already moved on by other means (rider cancelled, driver dropped, record
/// gone), which stops the trip.
typedef ReservationStepWriter =
    Future<bool> Function(ReservationStatus from, ReservationStatus to);

/// Who assigns drivers to scheduled rides and moves them through the trip.
///
/// Only a mock implementation exists today (`MockReservationDispatch`, wired
/// in `di.dart` for demo/dev/test builds only). Builds that talk to a real
/// backend get no dispatch at all: there, assignment and trip progression
/// must arrive from the backend via `ReservationController`
/// `applyDriverAssignment` / `update`, never be invented on the device.
abstract class ReservationDispatch {
  /// How long before pickup a driver is assigned.
  Duration get assignmentLead;

  /// How soon after booking a driver accepts the ride, before
  /// [assignmentLead] is reached. Null: only at [assignmentLead].
  Duration? get acceptAfterBooking;

  /// A driver for [ride], or null when none can be found. Null keeps today's
  /// path: the ride goes to "searching" at T-2 min and, still without a
  /// driver, to "No driver found" at T+5 min.
  ReservationDriver? driverFor(Reservation ride);

  /// Another driver taking over [ride] from the driver who accepted it, at
  /// [now], or null. Asked only while the ride is accepted and more than
  /// [assignmentLead] from pickup.
  ReservationDriver? handoverFor(Reservation ride, DateTime now);

  /// Starts — or resumes after an app restart — the remaining trip for a ride
  /// that is already [current] (en route, arrived or in progress). Idempotent
  /// per reservation.
  void driveTrip(
    String reservationId,
    ReservationStatus current,
    ReservationStepWriter writeStep,
  );

  void dispose();
}
