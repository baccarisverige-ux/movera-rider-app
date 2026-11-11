import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// Finished Book now rides for History (ARCH-12, contract C-5).
///
/// PROPOSED, needs agreement with Driver, Admin and backend:
/// `GET /api/v1/rider/trips?cursor=` → `{code, trips: [C-6 projection +
/// endedAt, cancellationReason], nextCursor}`, newest first, including
/// cancelled trips.
abstract interface class RideHistoryRepository {
  /// Newest first.
  Future<List<Reservation>> loadOnDemand();
}

/// One page of finished Book now rides (`TripPage {items, nextCursor}`).
class RideHistoryPage {
  const RideHistoryPage(this.items, {this.nextCursor});

  /// Newest first.
  final List<Reservation> items;

  /// The cursor of the next (older) page; null when this is the last one.
  final String? nextCursor;
}

/// A [RideHistoryRepository] that can read one page at a time, so History
/// shows the newest page at once and reads older ones on scroll.
abstract interface class PagedRideHistoryRepository {
  Future<RideHistoryPage> loadOnDemandPage({String? cursor});
}
