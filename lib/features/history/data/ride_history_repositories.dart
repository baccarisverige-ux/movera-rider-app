import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';

/// The rides archived on this device (demo/dev).
class LocalRideHistoryRepository implements RideHistoryRepository {
  const LocalRideHistoryRepository();

  @override
  Future<List<Reservation>> loadOnDemand() => OnDemandRideHistoryStore.read();
}

/// `GET /api/v1/rider/trips?cursor=` (C-5, PROPOSED). Follows `nextCursor`
/// for at most [maxPages] pages.
class ApiRideHistoryRepository
    implements RideHistoryRepository, ServerBackedRepository {
  ApiRideHistoryRepository({required ApiClient api, this.maxPages = 5})
    : _api = api;

  static const path = '/api/v1/rider/trips';

  final ApiClient _api;
  final int maxPages;

  @override
  Future<List<Reservation>> loadOnDemand() async {
    final rides = <String, Reservation>{};
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final json = await _api.get(
        cursor == null
            ? path
            : '$path?cursor=${Uri.encodeQueryComponent(cursor)}',
      );
      final trips = json['trips'];
      if (trips is List) {
        for (final raw in trips) {
          if (raw is! Map) continue;
          final record = _record(Map<String, dynamic>.from(raw));
          if (record != null) rides[record.reservationId] = record;
        }
      }
      final next = json['nextCursor'];
      if (next is! String || next.isEmpty) break;
      cursor = next;
    }
    final list = rides.values.toList()
      ..sort((a, b) => b.scheduledPickupAt.compareTo(a.scheduledPickupAt));
    return list;
  }

  static Reservation? _record(Map<String, dynamic> trip) {
    final snapshot = RideProjection.toSnapshot(trip);
    if (snapshot == null) return null;
    return OnDemandRideHistoryStore.recordFor(
      snapshot,
      terminalStatus: snapshot.status,
      endedAt:
          WireTime.tryParse(trip['endedAt']) ??
          WireTime.tryParse(trip['updatedAt']),
      // rider-u33: the fee the server charged for a cancel.
      cancellationFee: RideProjection.cancellationFee(trip),
    );
  }
}
