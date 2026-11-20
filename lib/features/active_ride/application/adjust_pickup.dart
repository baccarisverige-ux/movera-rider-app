import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';

/// Contract v0.18.144 (`contract.json#liveLocation.adjustPickup`, owner
/// 2026-11-20 "add bande on searching screen and while waiting for driver to
/// adjust pickup depend of current rider location"): when the banner shows.
enum AdjustPickupPhase {
  /// requested / searching / offered: any distance (v0.18.143 route change).
  searching,

  /// accepted … arrived: only within the trip's `maxPickupMoveMeters`
  /// (the existing `PATCH { pickup }`).
  driverComing,
}

abstract final class AdjustPickup {
  /// A fix less precise than this is never offered as the pickup.
  static const maxAccuracyMeters = 50.0;

  /// The whole metres to show in the banner, or null for no banner.
  static int? metersToShow({
    required AdjustPickupPhase phase,
    required GeoPoint gps,
    required GeoPoint pickup,
    required int thresholdMeters,
    double? accuracyMeters,
    GeoPoint? bookedPickup,
    int? maxMoveMeters,
  }) {
    // 0 m = the banner is off in the zone (admin).
    if (thresholdMeters <= 0 || !gps.isValid || !pickup.isValid) return null;
    if (accuracyMeters != null && accuracyMeters > maxAccuracyMeters) {
      return null;
    }
    final away = GeoDistance.metersBetween(
      pickup.latitude,
      pickup.longitude,
      gps.latitude,
      gps.longitude,
    );
    if (away <= thresholdMeters) return null;
    if (phase == AdjustPickupPhase.driverComing) {
      final from = bookedPickup ?? pickup;
      final moved = GeoDistance.metersBetween(
        from.latitude,
        from.longitude,
        gps.latitude,
        gps.longitude,
      );
      if (maxMoveMeters == null || moved > maxMoveMeters) return null;
    }
    return away.round();
  }
}

/// While searching: the v0.18.143 server path (`onTrip.routeChange.
/// whileSearching`, built by the change-pickup job): `POST /trips/{id}/
/// route-quote { pickup, dropoff, stops }` then `PATCH /trips/{id}
/// { routeQuoteId }` (transition change_route). Nothing new on the server.
class SearchingPickupMove {
  SearchingPickupMove({required ApiClient api, RideSession? session})
    : _api = api,
      _session = session;

  final ApiClient _api;
  final RideSession? _session;

  /// The route quote for the new pickup (the rider confirms a new price
  /// before [apply], `riderConfirmNewPrice`).
  Future<Map<String, dynamic>> quote({
    required String tripId,
    required GeoPoint pickup,
    required String pickupAddress,
    required Map<String, Object?> dropoff,
    List<Map<String, Object?>> stops = const [],
  }) {
    final version = _session?.projectionVersionOf(tripId);
    return _api.post(
      '/api/v1/trips/${Uri.encodeComponent(tripId)}/route-quote',
      body: {
        'expectedVersion': ?version,
        'pickup': {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'address': pickupAddress,
        },
        'dropoff': dropoff,
        'stops': stops,
      },
    );
  }

  /// Applies the quote: the old search stops free, a new one starts.
  Future<Map<String, dynamic>> apply({
    required String tripId,
    required String routeQuoteId,
  }) async {
    final version = _session?.projectionVersionOf(tripId);
    final response = await _api.patch(
      '/api/v1/trips/${Uri.encodeComponent(tripId)}',
      body: {'expectedVersion': ?version, 'routeQuoteId': routeQuoteId},
      idempotencyKey: 'adjust-pickup-$routeQuoteId',
    );
    _session?.observeProjection(response);
    return response;
  }
}
