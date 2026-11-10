import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';

/// Owner 2026-11-10 "Yes, fix": booking ahead follows the admin switch at
/// once. Both sides are built at start-up and every call asks [isOn] (the
/// server's `features.scheduledRides`, via `FeatureFlags`), so switching it
/// on mid-session works without a restart; switched off, the fail-closed
/// stand-in answers.
class SwitchedReservationRepository
    implements ReservationRepository, ServerBackedRepository {
  SwitchedReservationRepository({
    required this.on,
    required this.off,
    required this.isOn,
  });

  final ReservationRepository on;
  final ReservationRepository off;
  final bool Function() isOn;

  bool get switchedOn => isOn();

  ReservationRepository get _now => isOn() ? on : off;

  @override
  List<Reservation> get cached => _now.cached;

  @override
  ReservationPolicy get policy => _now.policy;

  @override
  Future<void> hydrate() => _now.hydrate();

  @override
  void clearLocal() {
    on.clearLocal();
    off.clearLocal();
  }

  @override
  Future<Reservation> createReservation(ReservationDraft draft) =>
      _now.createReservation(draft);

  @override
  Future<Reservation> updateReservation(
    String reservationId,
    ReservationPatch patch,
  ) => _now.updateReservation(reservationId, patch);

  @override
  Future<Reservation> cancelReservation(
    String reservationId, {
    String? reason,
    Money? fee,
  }) => _now.cancelReservation(reservationId, reason: reason, fee: fee);

  @override
  Future<Reservation?> getReservation(String reservationId) =>
      _now.getReservation(reservationId);

  @override
  Future<List<Reservation>> getUpcomingReservations() =>
      _now.getUpcomingReservations();

  @override
  Future<List<Reservation>> getRideHistory() => _now.getRideHistory();

  @override
  Future<Reservation> assignDriver(
    String reservationId, {
    ReservationDriver? driver,
  }) => _now.assignDriver(reservationId, driver: driver);
}
