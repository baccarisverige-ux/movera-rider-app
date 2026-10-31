import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/realtime/sse_event_parser.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_projection_wire.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

/// Follows each active trip and shares its events across all screen owners.
/// A screen cancelling its subscription cannot disconnect another screen.
///
/// Contract v0.18.7 `pickupWaiting.follow`: on the contract wire the trip
/// is followed on its SSE stream (`GET /trips/{tripId}/events`), read once
/// (`GET /trips/{tripId}`) when the screen opens and after a resync; the
/// projection is polled only while the stream is down, every
/// [pollInterval] (10 s, never under [minPollInterval]). The ETA tick comes
/// on the stream every 30 s as a `location` event with `eta`, so there is
/// nothing to poll for. The demo / test wire (no stream) polls.
///
/// ARCH-13, event envelope: besides the ride projection a response may
/// carry `eventId` (unique per change, replayed unchanged on reconnect),
/// `serverTime` (the server clock when it answered) and the projection's
/// `etaSeconds`. Events are deduplicated by `eventId` and ordered by the
/// projection's monotonic `version`; the transport `sequence` survives a
/// re-subscribe so it never restarts at 1 for the same ride.
class ApiRideRealtime implements RideRealtime {
  ApiRideRealtime({
    required ApiClient api,
    RealtimeConnection? connection,
    this.pollInterval = defaultPollInterval,
    this.notFoundLimit = 3,
    this.failedAfter = 3,
    this.maxRetryWait = const Duration(seconds: 8),
    this.streamRetryWait = const Duration(seconds: 5),
    DateTime Function()? clock,
    this.onProjectionVersion,
    bool? followStream,
  }) : _api = api,
       connection = connection ?? RealtimeConnection(),
       followStream = followStream ?? api.contractWire,
       _clock = clock ?? WireTime.now;

  /// `pickupWaiting.follow.pollSeconds` / `minPollSeconds`.
  static const defaultPollInterval = Duration(seconds: 10);
  static const minPollInterval = Duration(seconds: 5);

  final ApiClient _api;
  final RealtimeConnection connection;

  /// How often `GET /trips/{tripId}` is read while the stream is down (or
  /// on a wire without a stream). The app uses [defaultPollInterval]; a
  /// value under [minPollInterval] is a test seam only.
  final Duration pollInterval;

  /// Whether the trip stream is opened at all (the contract wire); the
  /// demo mock has none and polls.
  final bool followStream;

  /// How long after the stream drops it is opened again.
  final Duration streamRetryWait;

  /// R-O2: told each accepted projection's `version` (the trip's aggregate
  /// version, never the realtime `sequence`), so the rider's next command
  /// sends what this screen last saw as `expectedVersion`.
  final void Function(String tripId, int version)? onProjectionVersion;

  /// Consecutive `404`s after which polling pauses and the connection is
  /// marked failed. The client never invents a lifecycle state for it
  /// (contract v0.3.0): the ride keeps its last server status until a
  /// resync ([reconnectAndResync]) reads the trip again.
  final int notFoundLimit;

  /// Consecutive failed polls (no answer, a timeout, a 5xx) before the
  /// connection is shown as failed. Until then it is "reconnecting": one
  /// slow or refused answer from a small server is not a lost ride, and
  /// the trip itself lives on the server whatever this poll sees.
  final int failedAfter;

  /// The longest pause between polls after failures. The connection's
  /// backoff doubles up to 16 s; waiting that long after the server is
  /// back left the banner up and the trip stale for most of that time.
  final Duration maxRetryWait;
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

  /// Whether this transport speaks the contract wire (`/trips/{tripId}`,
  /// the trip stream, `PATCH` pickup moves).
  bool get contractWire => _api.contractWire;

  /// Contract v0.5.4: on the live wire the rider's "I'm on the way" is
  /// `POST /trips/{tripId}/on-the-way`; the mock transport has no signals.
  @override
  bool get supportsRiderSignals => _api.contractWire;

  /// Whether the trip stream of [rideId] is up right now (test seam).
  bool isStreamUp(String rideId) => _rides[rideId.trim()]?.streamUp ?? false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    final id = rideId.trim();
    if (_disposed || id.isEmpty || id == 'ride') {
      throw StateError('A server rideId is required for realtime updates.');
    }
    final poll = _rides.putIfAbsent(id, () => _RidePoll(id));
    poll.controller ??= StreamController<RideRealtimeEvent>.broadcast(
      onListen: () {
        if (poll.timer != null || poll.streamUp) return;
        connection.state = RealtimeState.connecting;
        // The screen's first read, then the stream; the poll timer only
        // runs while the stream is down.
        unawaited(_poll(poll));
        if (followStream) {
          unawaited(_openStream(poll));
        } else {
          _startPolling(poll);
        }
      },
      onCancel: () {
        _stopFollowing(poll);
        if (identical(_rides[id], poll)) _rides.remove(id);
        final controller = poll.controller;
        if (controller != null) unawaited(controller.close());
        if (_rides.isEmpty) connection.markDisconnected();
      },
    );
    return poll.controller!.stream;
  }

  void _startPolling(_RidePoll poll) {
    poll.timer ??= Timer.periodic(pollInterval, (_) => unawaited(_poll(poll)));
  }

  void _stopPolling(_RidePoll poll) {
    poll.timer?.cancel();
    poll.timer = null;
  }

  void _stopFollowing(_RidePoll poll) {
    _stopPolling(poll);
    poll.streamRetry?.cancel();
    poll.streamRetry = null;
    final stream = poll.stream;
    poll.stream = null;
    poll.streamUp = false;
    if (stream != null) unawaited(stream.cancel());
  }

  /// Opens `GET /trips/{tripId}/events` after the last sequence this
  /// transport accepted. While it is up the poll timer is off; when it
  /// ends or fails the poll takes over at [pollInterval] and the stream is
  /// tried again after [streamRetryWait].
  Future<void> _openStream(_RidePoll poll) async {
    if (_disposed || !identical(_rides[poll.id], poll) || poll.ended) return;
    if (poll.streamUp || poll.streamOpening) return;
    poll.streamOpening = true;
    try {
      final after = poll.gate.lastSequence;
      final path = _api.tripPath(poll.id, 'events');
      final lines = await _api.openEventStream(
        after > 0 ? '$path?after=$after' : path,
        lastEventId: after > 0 ? '$after' : null,
      );
      if (_disposed || !identical(_rides[poll.id], poll)) return;
      poll.streamUp = true;
      poll.streamFailures = 0;
      _stopPolling(poll);
      final parser = SseEventParser();
      poll.stream = lines.listen(
        (line) {
          final event = parser.add(line);
          if (event != null) _onStreamEvent(poll, event);
        },
        onDone: () => _streamDown(poll, null),
        onError: (Object error) => _streamDown(poll, error),
        cancelOnError: true,
      );
    } catch (error) {
      _streamDown(poll, error);
    } finally {
      poll.streamOpening = false;
    }
  }

  void _streamDown(_RidePoll poll, Object? error) {
    poll.stream = null;
    poll.streamUp = false;
    if (_disposed || !identical(_rides[poll.id], poll)) return;
    poll.streamFailures += 1;
    AppLog.info(
      'realtime.stream_down',
      extra: {
        'rideId': poll.id,
        'error': error?.toString() ?? 'ended',
        'failures': poll.streamFailures,
      },
    );
    if (poll.ended) return;
    if (error is ApiError && error.statusCode == 404) {
      poll.notFound += 1;
      if (poll.notFound >= notFoundLimit) {
        _endNotFound(poll);
        return;
      }
    }
    // `pickupWaiting.follow`: poll only while the stream is down. The
    // stream is tried again after [streamRetryWait], doubling on each
    // failure in a row up to a minute: a server that is down is not
    // hammered on two paths at once.
    if (poll.controller?.hasListener ?? false) {
      _startPolling(poll);
      poll.streamRetry?.cancel();
      final factor = 1 << (poll.streamFailures.clamp(1, 6) - 1);
      var wait = streamRetryWait * factor;
      if (wait > const Duration(minutes: 1)) wait = const Duration(minutes: 1);
      poll.streamRetry = Timer(wait, () {
        poll.streamRetry = null;
        unawaited(_openStream(poll));
      });
    }
  }

  /// One `RealtimeEvent` from the stream: a kind with a projection goes
  /// through the same path as a polled projection (gate, ordering, the
  /// rider's view of the change); a `location` event carries the driver's
  /// fix and the server ETA without a version change and never replaces
  /// the cached projection.
  void _onStreamEvent(_RidePoll poll, Map<String, Object?> event) {
    if (_disposed || !identical(_rides[poll.id], poll)) return;
    final projection = event['projection'];
    if (projection is Map) {
      _applyProjection(poll, {
        'ride': Map<String, dynamic>.from(projection),
        'eventId': event['eventId'],
        'sequence': event['sequence'],
        'version': event['version'],
        'kind': event['kind'],
        'serverTime': event['serverTime'],
        'occurredAt': event['occurredAt'],
      });
      return;
    }
    final kind = RealtimeKindWire.parse(event['kind']);
    if (kind != RealtimeKind.location) return;
    final status = poll.lastStatus;
    // No projection seen yet: the fix has no trip state to ride on; the
    // next projection carries the driver's position anyway.
    if (status == null) return;
    final sequence = _version(event['sequence']);
    if (sequence == null || sequence < 1) return;
    final eventId = _eventId(event['eventId']) ?? '${poll.id}:$sequence';
    final disposition = poll.gate.admit(
      eventId: eventId,
      tripId: poll.id,
      sequence: sequence,
      kind: RealtimeKind.location,
    );
    if (!disposition.passes) return;
    if (disposition == RealtimeDisposition.acceptedWithGap) {
      // A gap on the stream: the next read brings the whole projection.
      AppLog.info(
        'realtime.gap',
        extra: {'rideId': poll.id, 'sequence': sequence},
      );
      unawaited(_poll(poll, force: true));
    }
    final fix = event['location'];
    final lat = fix is Map && fix['lat'] is num
        ? (fix['lat'] as num).toDouble()
        : null;
    final lng = fix is Map && fix['lng'] is num
        ? (fix['lng'] as num).toDouble()
        : null;
    final measuredAt = fix is Map ? _date(fix['measuredAt']) : null;
    final serverTime = _date(event['serverTime']);
    final locationAt = measuredAt ?? _date(event['occurredAt']) ?? serverTime;
    final eta = event['eta'];
    final etaSeconds =
        _seconds(event['etaSeconds']) ??
        (eta is Map ? _seconds(eta['etaSeconds']) : null);
    if (lat != null && lng != null) {
      poll.lastLat = lat;
      poll.lastLng = lng;
      poll.lastLocationAt = locationAt;
    }
    if (eventId.isNotEmpty) poll.remember(eventId);
    poll.controller?.add(
      RideRealtimeEvent(
        rideId: poll.id,
        status: status,
        sequence: sequence,
        kind: RealtimeKind.location,
        eventId: eventId,
        version: poll.version,
        serverTime: serverTime,
        latitude: lat,
        longitude: lng,
        etaSeconds: etaSeconds,
        locationAt: _onDeviceClock(locationAt, serverNow: serverTime),
        payload: {
          if (locationAt != null)
            'serverLocationAt': WireTime.format(locationAt),
          if (poll.lastWireStatus is String) 'tripStatus': poll.lastWireStatus,
          if (eta is Map) etaKey: Map<String, Object?>.from(eta),
        },
      ),
    );
    connection.markConnected();
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
      final json = await _api.get(_api.tripPath(poll.id));
      if (_disposed || !identical(_rides[poll.id], poll)) return;
      poll.retryAt = null;
      poll.notFound = 0;
      poll.failures = 0;
      _applyProjection(poll, json);
    } catch (error) {
      if (!_disposed && identical(_rides[poll.id], poll)) {
        poll.failures += 1;
        AppLog.warning(
          'realtime.poll_failed',
          extra: {
            'rideId': poll.id,
            'error': error.toString(),
            'failures': poll.failures,
          },
        );
        if (error is ApiError && error.statusCode == 404) {
          poll.notFound += 1;
          if (poll.notFound >= notFoundLimit) {
            _endNotFound(poll);
            return;
          }
        }
        // The first misses are a blip to ride out (the banner says
        // "Reconnecting"); only a run of them is a problem to show. The
        // poll goes on either way: a network error never ends the search
        // on this side.
        if (poll.failures >= failedAfter) {
          connection.markFailed();
        } else {
          connection.markReconnecting();
        }
        final backoff = connection.nextBackoff();
        poll.retryAt = _clock().add(
          backoff > maxRetryWait ? maxRetryWait : backoff,
        );
      }
    } finally {
      poll.inFlight = false;
    }
  }

  /// A trip projection, read by the poll or carried by a stream event:
  /// the gate, the ordering by version, and the rider's view of the change
  /// (a driver drop, an admin reassign) decide what the screens get.
  void _applyProjection(_RidePoll poll, Map<String, dynamic> json) {
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
      AppLog.warning(
        'realtime.unknown_status',
        extra: {'rideId': poll.id, 'status': '${ride['status']}'},
      );
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
    final serverSequence = rawSequence != null && rawSequence > 0
        ? rawSequence
        : null;
    // A projection's own `kind` is the TripKind (live/scheduled), never an
    // event kind. Without an explicit event kind the change is read from
    // the projection: same lifecycle status, only payment or rating moved.
    final explicitKind = RealtimeKindWire.parse(
      envelope['kind'] ?? ride['eventKind'],
    );
    final kind = explicitKind ?? _projectionKind(poll, ride);
    if (serverSequence != null) {
      final disposition = poll.gate.admit(
        eventId: eventId ?? '${poll.id}:$serverSequence',
        tripId: tripIdOf(ride) ?? poll.id,
        sequence: serverSequence,
        kind: kind,
        isTerminalStatus:
            status.tripStatus.isTerminal &&
            status != RideStatus.cancelledByDriver,
      );
      if (!disposition.passes) {
        connection.markConnected();
        return;
      }
      if (disposition == RealtimeDisposition.acceptedWithGap) {
        // A whole projection is the resync; the missing events are not
        // replayed one by one.
        AppLog.info(
          'realtime.gap',
          extra: {'rideId': poll.id, 'sequence': serverSequence},
        );
      }
    }
    if (version == null && updatedAt == null) {
      throw const FormatException('Ride projection needs version or updatedAt');
    }
    if (poll.version != null && version != null && version < poll.version!) {
      connection.markConnected();
      return;
    }
    // The aggregate version wins over a clock that moves backwards. Within
    // the same version, updatedAt can still order location projections.
    if ((poll.version == null || version == null || version == poll.version) &&
        poll.updatedAt != null &&
        updatedAt != null &&
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
    final swapped =
        !reassigned &&
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
    final eta = ride['eta'];
    final etaAt = eta is Map ? _date(eta['at']) : null;
    if (poll.version == version &&
        poll.updatedAt == updatedAt &&
        poll.lastStatus == status &&
        poll.lastLat == location.lat &&
        poll.lastLng == location.lng &&
        // rider-u24: a stationary driver still sends fresh fixes; a newer
        // fix time with the same coordinates is news, not a repeat.
        poll.lastLocationAt == location.at &&
        // v0.18.7: the ETA tick changes `eta.at` without a version change.
        poll.lastEtaAt == etaAt) {
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
    poll.lastLocationAt = location.at;
    poll.lastEtaAt = etaAt;
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
    final serverNow =
        _date(envelope['serverTime'] ?? ride['serverTime']) ?? updatedAt;
    poll.controller?.add(
      RideRealtimeEvent(
        rideId: poll.id,
        status: status,
        sequence: sequence,
        kind: dropped ? RealtimeKind.driverCancelled : kind,
        eventId: eventId,
        version: version,
        serverTime: serverNow,
        driver: driver,
        latitude: location.lat,
        longitude: location.lng,
        etaSeconds:
            _seconds(ride['etaSeconds']) ??
            (eta is Map ? _seconds(eta['etaSeconds']) : null),
        // rider-r4-9: the contract's bare TripProjection has no
        // serverTime; its own updatedAt is the newest server stamp then.
        locationAt: _onDeviceClock(serverLocationAt, serverNow: serverNow),
        payload: {
          if (serverLocationAt != null)
            'serverLocationAt': WireTime.format(serverLocationAt),
          if (ride['status'] is String) 'tripStatus': ride['status'],
          // Owner, live test 2026-10-26 (N9): the fare the projection carries
          // (the server's final fare once the trip ends, below the booked
          // one when it ended early) travels with the status, so the
          // summary and the receipt show what the rider pays.
          if (ride['fare'] is Map) fareKey: ride['fare'],
          // Contract v0.4.0: when the driver accepted (Q12) and when the
          // waiting clock started (Q42), as the server stamped them.
          if (ride['acceptedAt'] is String) acceptedAtKey: ride['acceptedAt'],
          if (_waiting(ride, 'arrivedAt') case final String at)
            waitingArrivedAtKey: at,
          if (_waiting(ride, 'freeUntil') case final String at)
            waitingFreeUntilKey: at,
          if (_waiting(ride, 'noShowAt') case final String at)
            waitingNoShowAtKey: at,
          // v0.18.7: the server ETA, the trip's terms, the waiting cost so
          // far, the cancel fee and kind, and the pickup (a move).
          if (eta is Map) etaKey: Map<String, Object?>.from(eta),
          if (ride['terms'] is Map) termsKey: ride['terms'],
          if (_waitingField(ride, 'chargedSoFar') case final Map charged)
            waitingChargedSoFarKey: charged,
          if (_waitingField(ride, 'chargedSecondsNow') case final num seconds)
            waitingChargedSecondsNowKey: seconds,
          if (ride['cancellation'] is Map)
            cancellationKey: ride['cancellation'],
          if (ride['pickup'] is Map) pickupKey: ride['pickup'],
          if (dropped) 'kind': 'driver_cancelled',
          if (byAdmin) reassignedByKey: reassignedByAdmin,
        },
      ),
    );
    connection.markConnected();
  }

  /// `TripProjection.waiting.<field>` (arrivedAt, freeUntil, noShowAt),
  /// when the projection has it.
  static String? _waiting(Map<String, dynamic> ride, String field) {
    final at = _waitingField(ride, field);
    return at is String ? at : null;
  }

  static Object? _waitingField(Map<String, dynamic> ride, String field) {
    final waiting = ride['waiting'];
    return waiting is Map ? waiting[field] : null;
  }

  /// Whether a matched trip that went back to `searching` was moved by an
  /// admin: the projection's `cancellation.actor` says so, or the server
  /// named the change with a kind other than `driver_cancelled` (a driver
  /// drop always carries that kind).
  ///
  /// rider-u26: the kind is the newest event's. It names the change that
  /// ended the match only while the trip still sits where that change put
  /// it (`searching`). Once dispatch has moved on (re-offered, another
  /// driver accepted) within one poll, the kind is that later step's, so
  /// without an actor the rider is told the driver cancelled.
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
    if (ride['status'] != TripStatus.searching.wireName) return false;
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
        at:
            _date(fix['measuredAt']) ??
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

  /// The server no longer knows the ride. Following pauses and the
  /// connection shows a problem; no status is made up on the client
  /// (contract v0.3.0, audit B5). [reconnectAndResync] asks again.
  void _endNotFound(_RidePoll poll) {
    poll.ended = true;
    _stopFollowing(poll);
    AppLog.warning('realtime.ride_not_found', extra: {'rideId': poll.id});
    connection.markFailed();
  }

  /// ARCH-13: [locationAt] is server time; staleness is judged against the
  /// device clock. With the server's own clock at answer time the age is
  /// `serverNow - locationAt`, which is moved onto the device clock so a
  /// phone whose clock runs fast or slow does not see a fresh fix as stale.
  /// Without a `serverTime` the projection's `updatedAt` stands in for it
  /// (rider-r4-9), never the device clock.
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
        (poll.controller?.hasListener ?? false)) {
      if (followStream && !poll.streamUp) {
        poll.streamRetry?.cancel();
        poll.streamRetry = null;
        unawaited(_openStream(poll));
      }
      if (!poll.streamUp) _startPolling(poll);
    }
  }

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {
    if (!_api.contractWire) {
      throw UnsupportedError(
        'Rider signals are not available on the polling transport.',
      );
    }
    switch (signal) {
      case RideRealtimeSignal.riderOnTheWay:
        // The driver hears it as a rider_on_the_way event on the trip's
        // stream (contract v0.5.4). No body; the key makes a retry safe.
        await _api.post(
          '/api/v1/trips/${Uri.encodeComponent(rideId)}/on-the-way',
          body: const <String, dynamic>{},
          idempotencyKey:
              'on-the-way-$rideId-${_clock().millisecondsSinceEpoch ~/ 10000}',
        );
      case RideRealtimeSignal.driverArrived:
        throw UnsupportedError('Only the driver says they have arrived.');
    }
  }

  @override
  void unsubscribe() {
    // Legacy callers also cancel their own StreamSubscription. Closing every
    // stream here would disconnect other screens that still own this ride.
  }

  @override
  void cancelRide() {
    for (final poll in _rides.values.toList()) {
      _stopFollowing(poll);
      final controller = poll.controller;
      if (controller != null) unawaited(controller.close());
    }
    _rides.clear();
    connection.markDisconnected();
  }

  /// rider-26: what a ride was last shown with before this transport saw
  /// any of its projections. A reload between a driver drop and the next
  /// accept restores Waiting with the dropped driver from the device copy;
  /// without this the first poll's `searching` was a plain search status
  /// (no drop to judge against) and Waiting kept showing that driver. Only
  /// fills a gap: a ride this transport already followed keeps its own
  /// record.
  void primeShown({
    required String rideId,
    required RideStatus status,
    String? driverId,
  }) {
    final id = rideId.trim();
    if (id.isEmpty || !status.isMatched) return;
    _shown.putIfAbsent(id, () => (status: status, driverId: driverId));
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

  /// Consecutive polls that failed since the last good answer.
  int failures = 0;
  DateTime? retryAt;

  /// The trip stream (`pickupWaiting.follow`), while it is up.
  StreamSubscription<String>? stream;
  bool streamUp = false;
  bool streamOpening = false;
  int streamFailures = 0;
  Timer? streamRetry;

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
  DateTime? lastLocationAt;
  DateTime? lastEtaAt;
}
