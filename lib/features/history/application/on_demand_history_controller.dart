import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// Read-only application layer for Book Now ride history.
///
/// It intentionally owns no demo data. It reads the composed
/// [RideHistoryRepository] (ARCH-12): the device archive in demo/dev, the
/// server's trip list in release.
class OnDemandHistoryController {
  const OnDemandHistoryController({RideHistoryRepository? repository})
    : _repository = repository;

  final RideHistoryRepository? _repository;

  Future<List<Reservation>> load() =>
      (_repository ?? AppScope.instance.rideHistory).loadOnDemand();

  /// One page for History: the newest with a null [cursor], then older ones.
  /// A repository without pages answers everything as one last page.
  Future<RideHistoryPage> loadPage({String? cursor}) async {
    final repository = _repository ?? AppScope.instance.rideHistory;
    if (repository is PagedRideHistoryRepository) {
      return (repository as PagedRideHistoryRepository).loadOnDemandPage(
        cursor: cursor,
      );
    }
    return RideHistoryPage(await repository.loadOnDemand());
  }

  /// Fires whenever the on-demand history is written (FLOW-13).
  Stream<void> get changes => OnDemandRideHistoryStore.changes;

  List<Reservation> combine(
    List<Reservation> reservations,
    List<Reservation> onDemand, {
    required bool completed,
  }) {
    final byId = <String, Reservation>{};
    for (final ride in [...reservations, ...onDemand]) {
      final belongs = completed
          ? ride.status.isCompleted
          : ride.status.isCancelled;
      if (!belongs) continue;
      final current = byId[ride.reservationId];
      if (current == null ||
          ride.scheduledPickupAt.isAfter(current.scheduledPickupAt)) {
        byId[ride.reservationId] = ride;
      }
    }
    final rides = byId.values.toList()
      ..sort((a, b) => b.scheduledPickupAt.compareTo(a.scheduledPickupAt));
    return rides;
  }
}
