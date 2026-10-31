import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/utils/stale_guard.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';
import 'package:movera_rider/features/payments/domain/payment_status.dart';
import 'package:movera_rider/features/ratings/domain/rating_status.dart';
import 'package:movera_rider/features/trips/domain/ride_status_adapter.dart';
import 'package:movera_rider/features/trips/domain/trip_status.dart';

class RideSession {
  RideSession({this.rideId});

  String? rideId;
  RideStatus status = RideStatus.idle;
  TripStatus tripStatus = TripStatus.draft;
  PaymentStatus paymentStatus = PaymentStatus.notStarted;
  RatingStatus ratingStatus = RatingStatus.notRequested;
  RideQuote? quote;
  final stale = StaleGuard();
  bool suppressRestore = false;

  /// Last authoritative backend ordering metadata accepted for this ride.
  ///
  /// Not always the server's projection version: realtime events are
  /// ordered here by `version ?? sequence`, and the demo transport numbers
  /// its own events. Commands send [projectionVersionOf] instead.
  int? authoritativeVersion;
  DateTime? authoritativeUpdatedAt;

  /// R-O2: the newest `TripProjection.version` seen per trip, from server
  /// responses and the realtime transport only. It is what the rider's
  /// commands send as `expectedVersion`, so a tap made on a screen the
  /// trip has already moved past is refused (`409 version_mismatch`).
  final Map<String, int> _projectionVersions = {};

  /// The trip's projection version this device last saw, or null when it
  /// has seen none (the command is then sent without one).
  int? projectionVersionOf(String? tripId) {
    final id = tripId?.trim();
    if (id == null || id.isEmpty) return null;
    return _projectionVersions[id];
  }

  /// Records [version] for [tripId]. Versions only grow: an older answer
  /// that arrives late never moves it back.
  void observeProjectionVersion(String? tripId, Object? version) {
    final id = tripId?.trim();
    if (id == null || id.isEmpty || version is! num || version < 1) return;
    final value = version.toInt();
    final known = _projectionVersions[id];
    if (known == null || value > known) _projectionVersions[id] = value;
  }

  /// Records the version of a trip projection in a server response: the
  /// bare contract projection, `{projection}` or the pre-v0.3 `{ride}`.
  void observeProjection(Object? response) {
    if (response is! Map) return;
    final ride = response['projection'] ?? response['ride'] ?? response;
    if (ride is! Map) return;
    observeProjectionVersion(
      (ride['tripId'] ?? ride['rideId'] ?? ride['id'])?.toString(),
      ride['version'],
    );
  }

  /// v0.18.7 (pickup move): the BOOKED pickup of each trip (lat, lng),
  /// the point the server measures a move from. Kept from the first
  /// time the trip was seen, or from the projection's `bookedPickup`.
  final Map<String, ({double lat, double lng})> _bookedPickups = {};

  ({double lat, double lng})? bookedPickupOf(String? tripId) =>
      tripId == null ? null : _bookedPickups[tripId.trim()];

  /// Records [tripId]'s booked pickup once; [authoritative] (the server's
  /// own field) replaces what this device guessed.
  void observeBookedPickup(
    String? tripId,
    double lat,
    double lng, {
    bool authoritative = false,
  }) {
    final id = tripId?.trim();
    if (id == null || id.isEmpty) return;
    if (authoritative || !_bookedPickups.containsKey(id)) {
      _bookedPickups[id] = (lat: lat, lng: lng);
    }
  }

  /// The booked category and payment method ids of [rideId] (RIDE-19), so
  /// the search screen can request the same ride again. Set by booking and
  /// by restore; the labels shown to the rider live in the snapshot.
  String? bookedCategoryId;
  String? bookedPaymentMethodId;

  /// ARCH-20: the offer ceiling of [rideId], in öre (see
  /// RideSnapshot.maxOfferMinor). Set by booking and by restore.
  int? bookedMaxOfferMinor;

  /// v0.18.6 (G4-E4): the booked fare of [rideId], in minor units (see
  /// RideSnapshot.bookedFareMinor). Set by booking and by restore.
  int? bookedFareMinor;

  /// Strict client-side mutation path. Local/UI actions must obey the graph.
  RideStatus localTransition(RideStatus next) {
    status = transitionRide(status, next);
    _syncContractProjection();
    suppressRestore = status.isTerminal;
    AppLog.info(
      'ride.transition',
      extra: {'to': status.name, 'rideId': rideId},
    );
    return status;
  }

  /// Backwards-compatible alias for existing local callers.
  RideStatus apply(RideStatus next) => localTransition(next);

  /// Authoritative backend reconciliation path.
  ///
  /// Backend projections may legitimately jump over client-only intermediate
  /// states, but they must never move this session backwards in backend
  /// ordering. A new ride id starts a fresh ordering domain.
  bool backendReconcile(
    RideStatus backendStatus, {
    String? id,
    int? version,
    DateTime? updatedAt,
  }) {
    final incomingRideId = id?.trim();
    final currentRideId = rideId?.trim();
    final isNewRide =
        incomingRideId != null &&
        incomingRideId.isNotEmpty &&
        currentRideId != null &&
        currentRideId.isNotEmpty &&
        incomingRideId != currentRideId;

    // A new ride id establishes a fresh authoritative ordering domain.
    // Wrong-ride realtime events are filtered by the subscription/controller
    // that owns the expected ride id; RideSession also serves restore/rebook
    // flows where replacing the previous ride id is intentional.
    if (isNewRide) {
      authoritativeVersion = null;
      authoritativeUpdatedAt = null;
      bookedCategoryId = null;
      bookedPaymentMethodId = null;
      bookedMaxOfferMinor = null;
      bookedFareMinor = null;
    } else if (!_isFreshBackendProjection(
      backendStatus,
      version: version,
      updatedAt: updatedAt,
    )) {
      AppLog.info(
        'ride.restore.stale',
        extra: {
          'status': backendStatus.name,
          'rideId': id ?? rideId,
          'version': version,
          'updatedAt': updatedAt?.toIso8601String(),
        },
      );
      return false;
    }

    // Deliberately do not apply the local transition graph here. Backend
    // projections are authoritative and may skip client-only intermediate
    // states (for example driverArriving -> paymentFinalized after reconnect).
    // Ordering and ride identity are the safety boundaries for this path.
    // rider-69: DECISIONS R6 - a jump the graph does not allow is logged
    // (a session with no ride yet has nothing to jump from).
    if (!isNewRide &&
        status != RideStatus.idle &&
        status != backendStatus &&
        !canTransition(status, backendStatus)) {
      AppLog.info(
        'ride.restore.jump',
        extra: {
          'from': status.name,
          'to': backendStatus.name,
          'rideId': id ?? rideId,
          'version': version,
        },
      );
    }

    rideId = id ?? rideId;
    status = backendStatus;
    _syncContractProjection();
    suppressRestore = backendStatus.isTerminal;
    if (version != null) authoritativeVersion = version;
    if (updatedAt != null) authoritativeUpdatedAt = updatedAt;
    return true;
  }

  /// Backwards-compatible adapter for restore/realtime callers that do not yet
  /// carry backend ordering metadata.
  void restoreFromBackend(RideStatus backendStatus, {String? id}) {
    backendReconcile(backendStatus, id: id);
  }

  bool _isFreshBackendProjection(
    RideStatus incomingStatus, {
    int? version,
    DateTime? updatedAt,
  }) {
    final currentVersion = authoritativeVersion;
    final currentUpdatedAt = authoritativeUpdatedAt;

    if (version != null && currentVersion != null) {
      if (version < currentVersion) return false;
      if (version > currentVersion) return true;

      // Same backend version is either a duplicate or a conflicting replay.
      if (incomingStatus == status) return false;
      if (updatedAt == null || currentUpdatedAt == null) return false;
      return updatedAt.isAfter(currentUpdatedAt);
    }

    // ARCH-1: a versioned server projection outranks a session that has no
    // server version yet. Whatever timestamp the session holds then came
    // from a path without server ordering, so it must not reject a newer
    // server state.
    if (version != null && currentVersion == null) return true;

    if (updatedAt != null && currentUpdatedAt != null) {
      if (updatedAt.isBefore(currentUpdatedAt)) return false;
      if (updatedAt.isAtSameMomentAs(currentUpdatedAt) &&
          incomingStatus == status) {
        return false;
      }
    }

    return true;
  }

  void _syncContractProjection() {
    tripStatus = status.tripStatus;
    paymentStatus = status.paymentStatus;
    ratingStatus = status.ratingStatus;
  }

  Future<RideSnapshot?> loadSnapshot() => RideSnapshotStore.read();

  /// Back to "no ride" at the end of a rider's session. Pending async
  /// results for the previous ride are made stale.
  void reset() {
    stale.next();
    rideId = null;
    status = RideStatus.idle;
    quote = null;
    suppressRestore = false;
    authoritativeVersion = null;
    authoritativeUpdatedAt = null;
    _projectionVersions.clear();
    // rider-u44: the booked category, payment method and offer ceiling
    // belong to the ride that is gone (and to the rider who booked it).
    bookedCategoryId = null;
    bookedPaymentMethodId = null;
    bookedMaxOfferMinor = null;
    bookedFareMinor = null;
    tripStatus = TripStatus.draft;
    paymentStatus = PaymentStatus.notStarted;
    ratingStatus = RatingStatus.notRequested;
  }

  void dispose() => stale.dispose();
}
