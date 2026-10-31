import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_eta.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';

enum RideRealtimeSignal { driverArrived, riderOnTheWay }

/// Payload key and value of a back-to-searching event an admin caused
/// (Q13): the rider is not told "driver cancelled".
const String reassignedByKey = 'reassignedBy';
const String reassignedByAdmin = 'admin';

/// Payload keys of the projection's `acceptedAt` (Q12) and
/// `waiting.arrivedAt` (Q42), as wire timestamps.
const String acceptedAtKey = 'acceptedAt';

/// N9: the projection's `fare` (Money) on a realtime event.
const String fareKey = 'fare';
const String waitingArrivedAtKey = 'waitingArrivedAt';

/// rider-r4-13: the projection's `waiting.freeUntil` (when the waiting fee
/// starts) and `waiting.noShowAt` (when the driver may report a no-show).
const String waitingFreeUntilKey = 'waitingFreeUntil';
const String waitingNoShowAtKey = 'waitingNoShowAt';

/// v0.18.7 (`pickupWaiting`): the server ETA (`TripProjection.eta` or a
/// `location` event's `eta`), the trip's `terms`, the waiting cost so far
/// while the driver waits, the `cancellation` (fee + feeKind) and the
/// projection's `pickup` (a `pickup_moved` event).
const String etaKey = 'eta';
const String termsKey = 'terms';
const String waitingChargedSoFarKey = 'waitingChargedSoFar';
const String waitingChargedSecondsNowKey = 'waitingChargedSecondsNow';
const String cancellationKey = 'cancellation';
const String pickupKey = 'pickup';

class RideRealtimeEvent {
  RideRealtimeEvent({
    String? rideId,
    String? tripId,
    required this.status,
    required this.sequence,
    DateTime? at,
    DateTime? occurredAt,
    String? eventId,
    this.version,
    this.serverTime,
    this.payload = const <String, Object?>{},
    this.driver,
    this.latitude,
    this.longitude,
    this.etaSeconds,
    this.locationAt,
    this.signal,
    this.message,
    RealtimeKind? kind,
  }) : rideId = (tripId ?? rideId)!,
       _kind = kind,
       // ARCH-11: client-side stamps are UTC like server ones.
       at = occurredAt ?? at ?? WireTime.now(),
       eventId = eventId ?? '${tripId ?? rideId}:$sequence:${status.name}';

  /// Backwards-compatible Rider identifier. New platform code should use
  /// [tripId] so Rider, Driver and Admin speak the same contract.
  final String rideId;

  String get tripId => rideId;

  final String eventId;
  final RideStatus status;

  /// Monotonic transport ordering for this trip stream.
  final int sequence;

  /// Optional persisted backend aggregate version.
  final int? version;

  /// Backwards-compatible local occurrence time.
  final DateTime at;

  DateTime get occurredAt => at;

  /// Server clock when the event was committed, when available.
  final DateTime? serverTime;

  /// Extensible contract payload for backend-authored event metadata.
  final Map<String, Object?> payload;

  final MatchedDriver? driver;
  final double? latitude;
  final double? longitude;
  final int? etaSeconds;
  final DateTime? locationAt;
  final RideRealtimeSignal? signal;
  final String? message;
  final RealtimeKind? _kind;

  /// Q13: an admin moved the trip back to searching (not a driver cancel).
  bool get isAdminReassign => payload[reassignedByKey] == reassignedByAdmin;

  /// N9: the trip's `fare` as the projection carried it with this event
  /// (the server's final fare once the trip ends). Null when absent.
  Money? get fare => Money.fromWire(payload[fareKey]);

  /// When the driver accepted, as the server stamped it (Q12); null when
  /// the projection does not say.
  DateTime? get acceptedAt => WireTime.tryParse(payload[acceptedAtKey]);

  /// When the driver's waiting clock started at the pickup (Q42).
  DateTime? get waitingArrivedAt =>
      WireTime.tryParse(payload[waitingArrivedAtKey]);

  /// When the free wait ends and the waiting fee starts (Q41/Q42).
  DateTime? get waitingFreeUntil =>
      WireTime.tryParse(payload[waitingFreeUntilKey]);

  /// From when the driver may report the rider as a no-show (Q41).
  DateTime? get waitingNoShowAt =>
      WireTime.tryParse(payload[waitingNoShowAtKey]);

  /// v0.18.7 (Q4): the server's road-route ETA, when the event carries one.
  TripEta? get eta => TripEta.fromWire(payload[etaKey]);

  /// v0.18.7: the rules this trip is charged by, when the projection says.
  TripTerms? get terms => TripTerms.fromWire(payload[termsKey]);

  /// v0.18.7 (Q5): the waiting cost so far while the driver waits.
  Money? get waitingChargedSoFar =>
      Money.fromWire(payload[waitingChargedSoFarKey]);

  /// v0.18.7 (Q5): the paid waiting seconds so far while the driver waits.
  int? get waitingChargedSecondsNow {
    final raw = payload[waitingChargedSecondsNowKey];
    return raw is num && raw >= 0 ? raw.round() : null;
  }

  /// v0.18.7 (Q2/Q6): the cancel fee and which rule set it, once the trip
  /// is cancelled; null while the projection carries no `cancellation`.
  RiderCancelOutcomeFee? get cancellation =>
      RiderCancelOutcomeFee.fromProjection({
        'cancellation': payload[cancellationKey],
      });

  /// v0.18.7 (item 4): the projection's pickup (address and point), when
  /// the event carries it (a `pickup_moved` event always does).
  ({String address, double lat, double lng})? get pickup {
    final raw = payload[pickupKey];
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    final address = raw['address'];
    return (
      address: address is String ? address.trim() : '',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    );
  }

  /// The contract event kind (`contract.json#realtime.kinds`). The server
  /// says it; for a transport that does not, it follows from the event.
  RealtimeKind get kind =>
      _kind ??
      RealtimeKindWire.parse(payload['kind']) ??
      switch (signal) {
        RideRealtimeSignal.driverArrived => RealtimeKind.driverArrived,
        RideRealtimeSignal.riderOnTheWay => RealtimeKind.riderOnTheWay,
        null => switch (status) {
          RideStatus.paymentProcessing ||
          RideStatus.paymentFinalized ||
          RideStatus.paymentFailed => RealtimeKind.paymentUpdated,
          RideStatus.ratingPending ||
          RideStatus.closed => RealtimeKind.ratingUpdated,
          RideStatus.cancelledByRider => RealtimeKind.riderCancelled,
          RideStatus.cancelledByDriver => RealtimeKind.driverCancelled,
          _ => RealtimeKind.tripProjection,
        },
      };

  bool isNewerThan(RideRealtimeEvent other) {
    if (tripId != other.tripId) return true;
    final thisVersion = version;
    final otherVersion = other.version;
    if (thisVersion != null && otherVersion != null) {
      return thisVersion > otherVersion;
    }
    return sequence > other.sequence;
  }
}

abstract class RideRealtime {
  /// Whether this transport has an authoritative rider -> driver signal path.
  /// Surfaces must not claim a signal was sent when the transport cannot send it.
  bool get supportsRiderSignals => true;

  Stream<RideRealtimeEvent> subscribe(String rideId);
  Future<void> reconnectAndResync(String rideId);
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  });
  void unsubscribe();
  void cancelRide();

  /// Search again for the same ride after its driver dropped it before pickup.
  ///
  /// The rider keeps their ride, pickup, destination and price; only the driver
  /// changes. Implementations that cannot re-dispatch may no-op.
  void researchAfterDriverCancel() {}

  void dispose();
}
