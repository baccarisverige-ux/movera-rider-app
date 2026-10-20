import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/reservations/data/reservation_policy_catalog.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';

/// Book for later in a build where it is switched off: no reservations, and
/// every write refused, so a rider can never be told a ride is booked that
/// no server knows about (ARCH-7). Release composes this until a
/// server-backed [ReservationRepository] (contract C-8) exists.
class DisabledReservationRepository
    implements ReservationRepository, FeatureOffRepository {
  DisabledReservationRepository({ReservationPolicy? policy})
    : _policy = policy;

  /// Null: [ReservationPolicyCatalog.current], in the app language.
  final ReservationPolicy? _policy;

  @override
  List<Reservation> get cached => const [];

  @override
  ReservationPolicy get policy => _policy ?? ReservationPolicyCatalog.current;

  @override
  Future<void> hydrate() async {}

  @override
  void clearLocal() {}

  Future<Reservation> _refuse() =>
      Future.error(const ReservationsUnavailableException());

  @override
  Future<Reservation> createReservation(ReservationDraft draft) => _refuse();

  @override
  Future<Reservation> updateReservation(
    String reservationId,
    ReservationPatch patch,
  ) => _refuse();

  @override
  Future<Reservation> cancelReservation(
    String reservationId, {
    String? reason,
    Money? fee,
  }) => _refuse();

  @override
  Future<Reservation?> getReservation(String reservationId) async => null;

  @override
  Future<List<Reservation>> getUpcomingReservations() async => const [];

  @override
  Future<List<Reservation>> getRideHistory() async => const [];

  @override
  Future<Reservation> assignDriver(
    String reservationId, {
    ReservationDriver? driver,
  }) => _refuse();
}
