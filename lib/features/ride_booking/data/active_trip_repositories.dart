import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
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
}
