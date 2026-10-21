import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_projection_wire.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

/// Polls each active ride once and shares its events across all screen owners.
/// A screen cancelling its subscription cannot disconnect another screen.
///
/// ARCH-13, event envelope (contract C-6, PROPOSED, needs agreement with
/// Driver, Admin and backend): besides the ride projection a response may
/// carry `eventId` (unique per change, replayed unchanged on reconnect),
/// `serverTime` (the server clock when it answered) and the projection's
/// `etaSeconds`. Events are deduplicated by `eventId` and ordered by the
/// projection's monotonic `version`; the transport `sequence` survives a
/// re-subscribe so it never restarts at 1 for the same ride.
class ApiRideRealtime implements RideRealtime {
  ApiRideRealtime({
    required ApiClient api,
    RealtimeConnection? connection,
    this.pollInterval = const Duration(seconds: 2),
    this.notFoundLimit = 3,
    DateTime Function()? clock,
    this.onProjectionVersion,
  }) : _api = api,
       connection = connection ?? RealtimeConnection(),
       _clock = clock ?? WireTime.now;

  final ApiClient _api;
  final RealtimeConnection connection;
  final Duration pollInterval;

  /// R-O2: told each accepted projection's `version` (the trip's aggregate
  /// version, never the realtime `sequence`), so the rider's next command
  /// sends what this screen last saw as `expectedVersion`.
  final void Function(String tripId, int version)? onProjectionVersion;

  /// Consecutive `404`s after which polling pauses and the connection is
  /// marked failed. The client never invents a lifecycle state for it
  /// (contract v0.3.0): the ride keeps its last server status until a
  /// resync ([reconnectAndResync]) reads the trip again.
  final int notFoundLimit;
  final DateTime Function() _clock;
  final Map<String, _RidePoll> _rides = {};

  /// Per-ride transport sequence, kept across subscriptions (ARCH-13).
  final Map<String, int> _sequences = {};

  /// rider-u23: the lifecycle status and driver each ride was last shown
  /// with, kept across subscriptions like [_sequences]. Every handover
  /// (Finding to Waiting, a feed retry) starts a new poll, so a drop judged
  /// by the poll's own last status was missed when the new poll's first
  /// read already said `searching`.
  final Map<String, ({RideStatus status, String? driverId})> _shown = {};
  bool _disposed = false;

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    final id = rideId.trim();
    if (_disposed || id.isEmpty || id == 'ride') {
      throw StateError('A server rideId is required for realtime updates.');
    }
    final poll = _rides.putIfAbsent(id, () => _RidePoll(id));
    poll.controller ??= StreamController<RideRealtimeEvent>.broadcast(
      onListen: () {
        if (poll.timer != null) return;
        connection.state = RealtimeState.connecting;
        unawaited(_poll(poll));
        _startPolling(poll);
      },
      onCancel: () {
        poll.timer?.cancel();
        poll.timer = null;
        if (identical(_rides[id], poll)) _rides.remove(id);
        final controller = poll.controller;
        if (controller != null) unawaited(controller.close());
        if (_rides.isEmpty) connection.markDisconnected();
      },
    );
    return poll.controller!.stream;
  }

  void _startPolling(_RidePoll poll) {
    poll.timer = Timer.periodic(pollInterval, (_) => unawaited(_poll(poll)));
  }

  Future<void> _poll(_RidePoll poll, {bool force = false}) async {
    if (_disposed || !_rides.containsKey(poll.id) || poll.inFlight) return;
    if (poll.ended) return;
    // ARCH-13: after a failure, wait out the connection's backoff instead
    // of hammering the server every tick. A resync asks right away.
    final retryAt = poll.retryAt;
    if (!force && retryAt != null && _clock().isBefore(retryAt)) return;
    poll.inFlight = true;
    try {
      final json = await _api.get('/api/v1/rides/${Uri.encodeComponent(poll.id)}');
      if (_disposed || !identical(_rides[poll.id], poll)) return;
      poll.retryAt = null;
      poll.notFound = 0;
      // Contract v0.3 §1: a success response is the bare TripProjection.
      // The pre-v0.3 `{code, ride}` envelope is still read during the
      // migration; only that envelope carries event fields beside `ride`.
      final projection = tripProjectionOf(json);
      if (projection == null) {
        throw const FormatException('Missing ride projection');
      }
      final ride = projection;
      final enveloped = json['ride'] is Map;
      var status = RideStatusWire.fromProjection(ride);
      if (status == null) {
        AppLog.warning('realtime.unknown_status', extra: {
          'rideId': poll.id,
          'status': '${ride['status']}',
        });
        // Keep the last valid state and retry. An unknown backend status is
        // never evidence that a matched ride resumed searching.
        connection.markFailed();
        return;
      }
      final envelope = enveloped ? json : const <String, dynamic>{};
      final eventId = _eventId(envelope['eventId'] ?? ride['eventId']);
      if (eventId != null && poll.seenEventIds.contains(eventId)) {
        // The same server change again (a replay after reconnect).
        connection.markConnected();
        return;
      }
      final version = _version(ride['version'] ?? envelope['version']);
      final updatedAt = _date(ride['updatedAt'] ?? envelope['updatedAt']);
      // Contract v0.3.0 §4: the server's own `sequence` orders events and
      // the shared gate decides (dedupe by eventId, `sequence <= last` is a
      // duplicate, after a terminal status only payment/rating/message).
      // A projection's `sequence` is its resync cursor (minimum 0): 0 means
      // no realtime event yet, so it is ordered by `version` alone.
      final rawSequence = _version(envelope['sequence'] ?? ride['sequence']);
      final serverSequence =
          rawSequence != null && rawSequence > 0 ? rawSequence : null;
      // A projection's own `kind` is the TripKind (live/scheduled), never an
      // event kind. Without an explicit event kind the change is read from
      // the projection: same lifecycle status, only payment or rating moved.
      final explicitKind =
          RealtimeKindWire.parse(envelope['kind'] ?? ride['eventKind']);
      final kind = explicitKind ?? _projectionKind(poll, ride);
      if (serverSequence != null) {
        final disposition = poll.gate.admit(
          eventId: eventId ?? '${poll.id}:$serverSequence',
          tripId: tripIdOf(ride) ?? poll.id,
          sequence: serverSequence,
          kind: kind,
          isTerminalStatus: status.tripStatus.isTerminal &&
              status != RideStatus.cancelledByDriver,
        );
        if (!disposition.passes) {
          connection.markConnected();
          return;
        }
        if (disposition == RealtimeDisposition.acceptedWithGap) {
          // Polling already returns the whole projection, which is the
          // resync; the missing events are not replayed one by one.
          AppLog.info('realtime.gap', extra: {
            'rideId': poll.id,
            'sequence': serverSequence,
          });
        }
      }
      if (version == null && updatedAt == null) {
        throw const FormatException('Ride projection needs version or updatedAt');
      }
      if (poll.version != null && version != null &&
          version < poll.version!) {
        connection.markConnected();
        return;
      }
      // The aggregate version wins over a clock that moves backwards. Within
      // the same version, updatedAt can still order location projections.
      if ((poll.version == null || version == null ||
              version == poll.version) &&
          poll.updatedAt != null && updatedAt != null &&
          updatedAt.isBefore(poll.updatedAt!)) {
        connection.markConnected();
        return;
      }
      if (poll.version != null && version == null) {
        // Do not replace a versioned projection with an unversioned response.
        connection.markConnected();
        return;
      }
      final rawDriver = ride['driver'];
      final driver = rawDriver is Map
          ? MatchedDriver.fromJson(Map<String, dynamic>.from(rawDriver))
          : null;
      final shown = _shown[poll.id];
      final wasMatched = shown?.status.isMatched ?? false;
      // Contract v0.3.0: a driver drop before boarding (or an admin
      // reassign) puts the trip back to `searching`. The rider keeps the
      // trip; Waiting shows the reassignment notice for it.
      final reassigned = status.isSearching && wasMatched;
      // rider-u23: the polls can also skip the `searching` step (a
      // backgrounded app, a failed poll): a different driver on a matched
      // trip is that drop too. The event keeps the new driver's status.
      final swapped = !reassigned &&
          wasMatched &&
          status.isMatched &&
          driver != null &&
          shown?.driverId != null &&
          driver.id != shown!.driverId;
      // Q13 / X19: an admin reassign is not a driver cancel. The rider
      // keeps the same redispatch path but is never told "driver
      // cancelled": they see searching, then the next driver assigned.
      final byAdmin =
          (reassigned || swapped) && _reassignedByAdmin(ride, explicitKind);
      final dropped = (reassigned || swapped) && !byAdmin;
      if (reassigned) status = RideStatus.cancelledByDriver;
      final location = _location(ride);
      if (poll.version == version && poll.updatedAt == updatedAt &&
          poll.lastStatus == status &&
          poll.lastLat == location.lat &&
          poll.lastLng == location.lng) {
        connection.markConnected();
        return;
      }
      poll.version = version ?? poll.version;
      if (version != null) onProjectionVersion?.call(poll.id, version);
      poll.updatedAt = updatedAt ?? poll.updatedAt;
      poll.lastStatus = status;
      poll.lastWireStatus = ride['status'];
      poll.lastPaymentStatus = ride['paymentStatus'];
      poll.lastRatingStatus = ride['ratingStatus'];
      poll.lastLat = location.lat;
      poll.lastLng = location.lng;
      _shown[poll.id] = (
        status: status,
        // A matched projection without a driver keeps the one shown.
        driverId: driver?.id ?? (status.isMatched ? shown?.driverId : null),
      );
      if (eventId != null) poll.remember(eventId);
      // The server's sequence (0 = no realtime event yet), else its
      // version. Only a legacy server that sends neither gets a local
      // counter (compatibility, one release).
      final sequence = rawSequence ?? version ?? _nextSequence(poll.id);
      final serverLocationAt = location.at;
      poll.controller?.add(RideRealtimeEvent(
        rideId: poll.id,
        status: status,
        sequence: sequence,
        kind: dropped ? RealtimeKind.driverCancelled : kind,
        eventId: eventId,
        version: version,
        serverTime: updatedAt,
        driver: driver,
        latitude: location.lat,
        longitude: location.lng,
        etaSeconds: _seconds(ride['etaSeconds']),
        locationAt: _onDeviceClock(
          serverLocationAt,
          serverNow: _date(envelope['serverTime'] ?? ride['serverTime']),
        ),
        payload: {
          if (serverLocationAt != null)
            'serverLocationAt': WireTime.format(serverLocationAt),
          if (ride['status'] is String) 'tripStatus': ride['status'],
          // Contract v0.4.0: when the driver accepted (Q12) and when the
          // waiting clock started (Q42), as the server stamped them.
          if (ride['acceptedAt'] is String) acceptedAtKey: ride['acceptedAt'],
          if (_waitingArrivedAt(ride) case final String at)
            waitingArrivedAtKey: at,
          if (dropped) 'kind': 'driver_cancelled',
          if (byAdmin) reassignedByKey: reassignedByAdmin,
        },
      ));
      connection.markConnected();
    } catch (error) {
      if (!_disposed && identical(_rides[poll.id], poll)) {
        AppLog.warning('realtime.poll_failed', extra: {
          'rideId': poll.id,
          'error': error.toString(),
        });
        connection.markFailed();
        if (error is ApiError && error.statusCode == 404) {
          poll.notFound += 1;
          if (poll.notFound >= notFoundLimit) {
            _endNotFound(poll);
            return;
          }
        }
        poll.retryAt = _clock().add(connection.nextBackoff());
      }
    } finally {
      poll.inFlight = false;
    }
  }

  /// `TripProjection.waiting.arrivedAt`, when the projection has one.
  static String? _waitingArrivedAt(Map<String, dynamic> ride) {
    final waiting = ride['waiting'];
    final at = waiting is Map ? waiting['arrivedAt'] : null;
    return at is String ? at : null;
  }

  /// Whether a matched trip that went back to `searching` was moved by an
  /// admin: the projection's `cancellation.actor` says so, or the server
  /// named the change with a kind other than `driver_cancelled` (a driver
  /// drop always carries that kind).
  static bool _reassignedByAdmin(
    Map<String, dynamic> ride,
    RealtimeKind? explicitKind,
  ) {
    final cancellation = ride['cancellation'];
    if (cancellation is Map) {
      final actor = cancellation['actor'];
      if (actor == 'admin') return true;
      if (actor == 'driver') return false;
    }
    return explicitKind != null && explicitKind != RealtimeKind.driverCancelled;
  }

  /// The event kind of a polled projection that names none. After a
  /// terminal status the gate lets only payment/rating changes through, so
  /// a projection whose lifecycle status is unchanged and whose payment or
  /// rating status moved is that update (RC-01); anything else is a
  /// `trip_projection`.
  RealtimeKind _projectionKind(_RidePoll poll, Map<String, dynamic> ride) {
    if (poll.lastWireStatus == null || ride['status'] != poll.lastWireStatus) {
      return RealtimeKind.tripProjection;
    }
    if (ride['paymentStatus'] != poll.lastPaymentStatus) {
      return RealtimeKind.paymentUpdated;
    }
    if (ride['ratingStatus'] != poll.lastRatingStatus) {
      return RealtimeKind.ratingUpdated;
    }
    return RealtimeKind.tripProjection;
  }

  /// The driver position: the contract `driverLocation` GeoFix, else the
  /// legacy flat `driverLat`/`driverLng` (pre-v0.3 wire).
  ({double? lat, double? lng, DateTime? at}) _location(
    Map<String, dynamic> ride,
  ) {
    final fix = ride['driverLocation'];
    if (fix is Map && fix['lat'] is num && fix['lng'] is num) {
      return (
        lat: (fix['lat'] as num).toDouble(),
        lng: (fix['lng'] as num).toDouble(),
        at: _date(fix['measuredAt']) ??
            _date(ride['locationAt'] ?? ride['driverLocationAt']),
      );
    }
    return (
      lat: (ride['driverLat'] as num?)?.toDouble(),
      lng: (ride['driverLng'] as num?)?.toDouble(),
      at: _date(ride['locationAt'] ?? ride['driverLocationAt']),
    );
  }

  int _nextSequence(String rideId) =>
      _sequences[rideId] = (_sequences[rideId] ?? 0) + 1;

  /// The server no longer knows the ride. Polling pauses and the
  /// connection shows a problem; no status is made up on the client
  /// (contract v0.3.0, audit B5). [reconnectAndResync] asks again.
  void _endNotFound(_RidePoll poll) {
    poll.ended = true;
    poll.timer?.cancel();
    poll.timer = null;
    AppLog.warning('realtime.ride_not_found', extra: {'rideId': poll.id});
    connection.markFailed();
  }

  /// ARCH-13: [locationAt] is server time; staleness is judged against the
  /// device clock. With the server's own clock at answer time the age is
  /// `serverNow - locationAt`, which is moved onto the device clock so a
  /// phone whose clock runs fast or slow does not see a fresh fix as stale.
  DateTime? _onDeviceClock(DateTime? locationAt, {DateTime? serverNow}) {
    if (locationAt == null || serverNow == null) return locationAt;
    final age = serverNow.difference(locationAt);
    return _clock().subtract(age.isNegative ? Duration.zero : age);
  }

  String? _eventId(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  int? _seconds(Object? raw) => raw is num && raw >= 0 ? raw.round() : null;

  int? _version(Object? raw) =>
      raw is int ? raw : (raw is String ? int.tryParse(raw) : null);

  DateTime? _date(Object? raw) => WireTime.tryParse(raw);

  @override
  Future<void> reconnectAndResync(String rideId) async {
    final poll = _rides[rideId.trim()];
    if (poll == null) return;
    connection.markReconnecting();
    if (poll.ended) {
      // An explicit resync after the not-found pause reads the trip once
      // more; a further 404 pauses again.
      poll.ended = false;
      poll.notFound = poll.notFound > 0 ? notFoundLimit - 1 : 0;
    }
    await _poll(poll, force: true);
    // rider-23: the pause cancelled the periodic poll, and onListen never
    // runs again for the listener still attached. Without this a resync
    // that reads the trip left it frozen while the banner said connected.
    if (!_disposed &&
        identical(_rides[poll.id], poll) &&
        !poll.ended &&
        poll.timer == null &&
        (poll.controller?.hasListener ?? false)) {
      _startPolling(poll);
    }
  }

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) {
    throw UnsupportedError(
      'Rider signals are not available on the polling transport.',
    );
  }

  @override
  void unsubscribe() {
    // Legacy callers also cancel their own StreamSubscription. Closing every
    // stream here would disconnect other screens that still own this ride.
  }

  @override
  void cancelRide() {
    for (final poll in _rides.values.toList()) {
      poll.timer?.cancel();
      final controller = poll.controller;
      if (controller != null) unawaited(controller.close());
    }
    _rides.clear();
    connection.markDisconnected();
  }

  @override
  void researchAfterDriverCancel() {
    for (final poll in _rides.values) {
      unawaited(_poll(poll));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelRide();
  }
}

class _RidePoll {
  _RidePoll(this.id);
  final String id;
  StreamController<RideRealtimeEvent>? controller;
  Timer? timer;
  bool inFlight = false;
  bool ended = false;
  int notFound = 0;
  DateTime? retryAt;

  /// The contract realtime gate for this trip.
  final RealtimeGate gate = RealtimeGate();

  /// Recent server event ids, newest last, for dedupe on replay.
  final List<String> seenEventIds = [];

  void remember(String eventId) {
    seenEventIds.add(eventId);
    if (seenEventIds.length > 64) seenEventIds.removeAt(0);
  }

  int? version;
  DateTime? updatedAt;
  RideStatus? lastStatus;
  Object? lastWireStatus;
  Object? lastPaymentStatus;
  Object? lastRatingStatus;
  double? lastLat;
  double? lastLng;
}
