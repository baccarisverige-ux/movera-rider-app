import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Demo/dev: only this device's snapshot exists, so there is never a server
/// trip to fall back to. Keeps mock-transport restore exactly as before.
class DeviceOnlyActiveTripRepository implements ActiveTripRepository {
  const DeviceOnlyActiveTripRepository();

  @override
  Future<RideSnapshot?> fetchActive() async => null;
}

/// `GET /api/v1/rider/trips/active`: the rider's live trip (contract v0.5).
class ApiActiveTripRepository
    implements ActiveTripRepository, ServerBackedRepository {
  ApiActiveTripRepository({required ApiClient api, this.categoryLabel})
      : _api = api;

  static const path = '/api/v1/rider/trips/active';

  final ApiClient _api;

  /// The catalog's category names; null is the built-in catalog.
  final CategoryLabel? categoryLabel;

  @override
  Future<RideSnapshot?> fetchActive() async {
    final json = await _api.get(path);
    // Contract: the bare TripProjection, or 204 (no body) when the rider
    // has no live trip; `{trip}` / `{ride}` is the older envelope.
    final trip =
        json['trip'] ?? json['ride'] ?? (json['tripId'] != null ? json : null);
    if (trip is! Map) return null;
    final snapshot = RideProjection.toSnapshot(
      Map<String, dynamic>.from(trip),
      categoryLabel: categoryLabel,
    );
    if (snapshot == null || snapshot.status.isTerminal) return null;
    return snapshot;
  }

  /// `GET /api/v1/rider/trips` (newest first), the last finished live trip.
  static const finishedPath =
      '/api/v1/rider/trips?status=completed&kind=live&limit=1';

  /// Owner, live test 2026-10-26: a trip the driver finished while the app
  /// was closed shows its finished-trip / tip screen on the next open, also
  /// on a phone that never saw the trip (another device, cleared storage).
  /// The rider's last trip, when it finished within [within] and the rider
  /// has neither rated nor skipped it (`ratingStatus` pending; closing the
  /// screen skips). [TripProjection] carries no end time; `updatedAt` is
  /// the completion until the rider rates.
  Future<RideSnapshot?> fetchRecentlyFinished({
    Duration within = RideSnapshot.activeRideWindow,
    DateTime? now,
  }) async {
    final json = await _api.get(finishedPath);
    final items = json['items'];
    if (items is! List || items.isEmpty || items.first is! Map) return null;
    final trip = Map<String, dynamic>.from(items.first as Map);
    if (trip['ratingStatus'] != 'pending') return null;
    final updatedAt = WireTime.tryParse(trip['updatedAt']);
    if (updatedAt == null ||
        (now ?? DateTime.now()).difference(updatedAt) > within) {
      return null;
    }
    final snapshot = RideProjection.toSnapshot(
      trip,
      categoryLabel: categoryLabel,
    );
    if (snapshot == null || !snapshot.status.isCompletedSurface) return null;
    return snapshot;
  }
}
