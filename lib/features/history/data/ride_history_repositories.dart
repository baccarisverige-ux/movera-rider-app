import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

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
  ApiRideHistoryRepository({
    required ApiClient api,
    this.maxPages = 5,
    this.categoryLabel,
  }) : _api = api;

  static const path = '/api/v1/rider/trips';

  final ApiClient _api;
  final int maxPages;

  /// The catalog's category names; null is the built-in catalog.
  final CategoryLabel? categoryLabel;

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
      // Contract `TripPage {items, nextCursor}`; `trips` is the older key.
      final trips = json['items'] ?? json['trips'];
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

  static Object? _cancelledAt(Map<String, dynamic> trip) {
    final cancellation = trip['cancellation'];
    return cancellation is Map ? cancellation['at'] : null;
  }

  Reservation? _record(Map<String, dynamic> trip) {
    final snapshot = RideProjection.toSnapshot(
      trip,
      categoryLabel: categoryLabel,
    );
    if (snapshot == null) return null;
    // rider-r5-47: a plain rider cancel is never rated, an end-early is
    // (contract: ratingStatus pending → submitted | skipped), and its
    // `fare` is what the rider paid for the distance driven.
    final rating = TripRatingStatusWire.parse(trip['ratingStatus']);
    final endedEarly =
        snapshot.status == RideStatus.cancelledByRider &&
        rating != null &&
        rating != TripRatingStatus.notRequested;
    final reversal = RideProjection.noShowReversal(trip);
    return OnDemandRideHistoryStore.recordFor(
      snapshot,
      terminalStatus: snapshot.status,
      endedEarly: endedEarly,
      charged: endedEarly ? Money.fromWire(trip['fare']) : null,
      // rider-r5-51: `cancellation.at` is stable; `updatedAt` moves with
      // every later rating, payment or refund change.
      endedAt:
          WireTime.tryParse(trip['endedAt']) ??
          WireTime.tryParse(_cancelledAt(trip)) ??
          WireTime.tryParse(trip['updatedAt']),
      // rider-u33: the fee the server charged for a cancel.
      cancellationFee: RideProjection.cancellationFee(trip),
      noShowReversed: reversal.reversed,
      refundedToWallet: reversal.refunded,
    );
  }
}
