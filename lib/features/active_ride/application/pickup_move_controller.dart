import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Why a pickup move was refused (contract v0.18.7 `pickupWaiting.pickupMove`).
enum PickupMoveFailure {
  /// Further than the zone's `booking.maxPickupMoveMeters` from the booked
  /// pickup (`400 pickup_move_too_far`, or checked here before sending).
  tooFar,

  /// The driver is already there (`409 pickup_fixed_after_arrival`).
  fixedAfterArrival,

  /// The trip changed since this screen read it (`409 version_mismatch`).
  stale,

  /// The trip is over or cannot be changed any more.
  rideFinished,

  /// No answer from the server.
  network,
}

class PickupMoveException implements Exception {
  const PickupMoveException(this.failure, {this.maxMeters});

  final PickupMoveFailure failure;

  /// The zone's limit behind [PickupMoveFailure.tooFar].
  final int? maxMeters;

  /// The plain-words text the rider sees (`pickupMove.texts`).
  String get message => switch (failure) {
    PickupMoveFailure.tooFar => L10n.current.pickupMoveTooFar(
      '${maxMeters ?? TripTerms.defaultMaxPickupMoveMeters}',
    ),
    PickupMoveFailure.fixedAfterArrival =>
      L10n.current.pickupMoveFixedAfterArrival,
    PickupMoveFailure.stale => L10n.current.rideJustChanged,
    PickupMoveFailure.rideFinished => L10n.current.routeNoLongerChangeable,
    PickupMoveFailure.network => L10n.current.routeUpdateFailed,
  };
}

/// Moves the pickup of a booked trip: `PATCH /trips/{tripId}
/// { expectedVersion, pickup }` while the trip is requested … driver on the
/// way. The limit is the trip's `terms.maxPickupMoveMeters` (the zone's
/// `booking.maxPickupMoveMeters`, admin Dispatch › Booking, default 200),
/// measured from the BOOKED pickup; the fare does not change.
class PickupMoveController {
  PickupMoveController({required ApiClient api, RideSession? session})
    : _api = api,
      _session = session;

  final ApiClient _api;
  final RideSession? _session;

  /// `details: ["maxMeters=200", "meters=…"]` of a `pickup_move_too_far`.
  static int? maxMetersOf(List<String>? details) {
    for (final item in details ?? const <String>[]) {
      final parts = item.split('=');
      if (parts.length == 2 && parts.first.trim() == 'maxMeters') {
        return int.tryParse(parts.last.trim());
      }
    }
    return null;
  }

  /// Checks the limit before sending: null when [to] is within
  /// [maxMeters] of [bookedPickup], else the refusal to show.
  static PickupMoveException? check({
    required GeoPoint bookedPickup,
    required GeoPoint to,
    required int maxMeters,
  }) {
    final meters = GeoDistance.metersBetween(
      bookedPickup.latitude,
      bookedPickup.longitude,
      to.latitude,
      to.longitude,
    );
    if (meters > maxMeters) {
      return PickupMoveException(
        PickupMoveFailure.tooFar,
        maxMeters: maxMeters,
      );
    }
    return null;
  }

  /// Sends the move. Returns the new projection (`pickup` moved, version
  /// + 1). Throws [PickupMoveException].
  Future<Map<String, dynamic>> move({
    required String tripId,
    required String address,
    required GeoPoint to,
    GeoPoint? bookedPickup,
    int? maxMeters,
  }) async {
    if (bookedPickup != null && maxMeters != null) {
      final refused = check(
        bookedPickup: bookedPickup,
        to: to,
        maxMeters: maxMeters,
      );
      if (refused != null) throw refused;
    }
    final version = _session?.projectionVersionOf(tripId);
    try {
      final response = await _api.patch(
        _api.tripPath(tripId),
        body: {
          if (version != null) 'expectedVersion': version,
          'pickup': {
            'address': address,
            'lat': to.latitude,
            'lng': to.longitude,
          },
        },
      );
      _session?.observeProjection(response);
      final projection = response['projection'] ?? response;
      return projection is Map
          ? Map<String, dynamic>.from(projection)
          : <String, dynamic>{};
    } on ApiError catch (error) {
      _session?.observeProjection(error.projection);
      throw _translate(error);
    } catch (_) {
      throw const PickupMoveException(PickupMoveFailure.network);
    }
  }

  static PickupMoveException _translate(ApiError error) {
    final reason = error.detail;
    if (reason == 'pickup_move_too_far') {
      return PickupMoveException(
        PickupMoveFailure.tooFar,
        maxMeters: maxMetersOf(error.details),
      );
    }
    if (reason == 'pickup_fixed_after_arrival') {
      return const PickupMoveException(PickupMoveFailure.fixedAfterArrival);
    }
    if (error.isVersionMismatch) {
      return const PickupMoveException(PickupMoveFailure.stale);
    }
    final status = error.statusCode;
    if (status != null && (status == 409 || status == 410 || status == 422)) {
      return const PickupMoveException(PickupMoveFailure.rideFinished);
    }
    return const PickupMoveException(PickupMoveFailure.network);
  }
}
