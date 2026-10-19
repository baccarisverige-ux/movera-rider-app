import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/mock_driver_pool.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';

/// Mock matching transport. Assignment is an event, not a widget timer.
///
/// It plays the driver app and dispatch for the demo. Every lifecycle step
/// it shows is first committed on the stand-in server (`POST
/// /rides/{id}/status`), which applies the shared transition table, so the
/// server projection and what the rider sees agree (contract v0.3.0).
class MockRideRealtime implements RideRealtime {
  @override
  bool get supportsRiderSignals => true;

  MockRideRealtime({
    this.assignAfter = const Duration(seconds: 25),
    this.boardAfter = const Duration(seconds: 8),
    this.tripTick = const Duration(seconds: 3),
    this.tripTicks = 6,
    this.paymentProcessingAfter = const Duration(milliseconds: 500),
    this.paymentFinalizedAfter = const Duration(milliseconds: 500),
    this.ratingPendingAfter = const Duration(milliseconds: 300),
    RealtimeConnection? connection,
    this.api,
  }) : connection = connection ?? RealtimeConnection();

  final Duration assignAfter;

  /// Once the driver is waiting at pickup, how long before the rider boards.
  final Duration boardAfter;

  /// Cadence and length of the trip itself, so a ride can actually finish.
  final Duration tripTick;
  final int tripTicks;

  /// Demo-only post-trip cadence. Production replaces MockRideRealtime with
  /// the real transport, where these statuses are backend-authored.
  final Duration paymentProcessingAfter;
  final Duration paymentFinalizedAfter;
  final Duration ratingPendingAfter;

  final RealtimeConnection connection;
  final ApiClient? api;
  final _controller = StreamController<RideRealtimeEvent>.broadcast();
  Timer? _assign;
  Timer? _gps;
  Timer? _board;
  Timer? _trip;
  Timer? _paymentProcessing;
  Timer? _paymentFinalized;
  Timer? _ratingPending;
  int _tripTicksDone = 0;
  int _assignmentAttempt = 0;
  String? _rideId;
  int _sequence = 0;

  /// Server commits run one after another, in the order they were shown.
  Future<void> _commits = Future<void>.value();

  /// The last lifecycle target committed to the server, to skip repeats.
  String? _committedTarget;
  bool cancelled = false;
  bool disposed = false;
  bool held = false;
  bool _assignmentInFlight = false;
  RideStatus lastStatus = RideStatus.findingDriver;
  MatchedDriver? lastDriver;
  double? lastLat;
  double? lastLng;
  DateTime? lastLocationAt;
  double? _pickupLat;
  double? _pickupLng;
  double _progress = 0;

  /// Set by the caller once the destination is known (Waiting doesn't exist
  /// until after booking, so this can't be a constructor parameter). Left
  /// null, trip ticks emit no movement at all — the same as before this was
  /// added, so nothing regresses for a caller that never sets it.
  double? destinationLat;
  double? destinationLng;
  double? _tripStartLat;
  double? _tripStartLng;
  RideStatus? _resumeStatus;
  MatchedDriver? _resumeDriver;
  int? _resumeVersion;

  /// Primes the next [subscribe] call to resume from a previously known
  /// status/driver/version instead of unconditionally resetting to
  /// findingDriver (Phase 135).
  ///
  /// A fresh MockRideRealtime construction - always true after a page
  /// reload - otherwise always resets to findingDriver and restarts the
  /// 25-second assignment timer, even when the restored ride already had a
  /// driver or was mid-trip. That reset event was then wrongly accepted as
  /// authoritative because nothing had ever seeded RideSession's ordering
  /// metadata, regressing a restored "driver found"/in-trip ride back to
  /// "finding driver". [version] should be the same ordering number the
  /// restore seeded RideSession.authoritativeVersion with, so this resumed
  /// emission is recognized as continuing that ordering, not restarting it.
  void primeResume({
    required RideStatus status,
    MatchedDriver? driver,
    int? version,
  }) {
    _resumeStatus = status;
    _resumeDriver = driver;
    _resumeVersion = version;
  }

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    // Consumed exactly once per call, on every path, so a primed value can
    // never leak into a later, unrelated subscribe().
    final resumeStatus = _resumeStatus;
    final resumeDriver = _resumeDriver;
    final resumeVersion = _resumeVersion;
    _resumeStatus = null;
    _resumeDriver = null;
    _resumeVersion = null;

    if (_rideId == rideId && !disposed && !cancelled) {
      // RC-08: [unsubscribe] cancelled the only assignment timer. A search
      // for the same ride subscribing again must still get a driver.
      if (lastStatus == RideStatus.findingDriver &&
          _assign == null &&
          !held &&
          !_assignmentInFlight) {
        _armAssignment(rideId);
      }
      return _controller.stream;
    }
    _assign?.cancel();
    _gps?.cancel();
    _board?.cancel();
    _trip?.cancel();
    _paymentProcessing?.cancel();
    _paymentFinalized?.cancel();
    _ratingPending?.cancel();
    _tripTicksDone = 0;
    _assignmentAttempt = 0;
    cancelled = false;
    disposed = false;
    held = false;
    _assignmentInFlight = false;
    _rideId = rideId;
    _committedTarget = null;
    // A new ride starts a new commit queue (an older ride's pending commit
    // must never hold this one back).
    _commits = Future<void>.value();
    lastLat = null;
    lastLng = null;
    lastLocationAt = null;
    _progress = 0;
    _tripStartLat = null;
    _tripStartLng = null;
    connection.markConnected();

    if (resumeStatus != null && resumeStatus.isMatched) {
      _sequence = resumeVersion ?? 0;
      lastStatus = resumeStatus;
      lastDriver = resumeDriver;
      _pickupLat ??= 59.3293;
      _pickupLng ??= 18.0686;
      // A broadcast StreamController cannot deliver an event added before a
      // listener exists - and the caller's own `.subscribe(id).listen(...)`
      // chain only attaches its listener immediately *after* this method
      // returns. Emitting synchronously here would silently vanish before
      // DriverTrackingController ever sees it, leaving it stuck on its own
      // constructor default (driverAssigned) until whatever timer/tick
      // happens to fire next. Defer by one microtask so the just-attached
      // listener actually receives the resumed status.
      scheduleMicrotask(() {
        if (cancelled || disposed || _rideId != rideId) return;
        _emit(resumeStatus);
      });
      const tripStatuses = {
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.approachingDropoff,
      };
      if (tripStatuses.contains(resumeStatus)) {
        _tripStartLat ??= _pickupLat;
        _tripStartLng ??= _pickupLng;
        _runTripTicks();
      } else {
        // The remaining isMatched statuses are the pre-trip approach:
        // driverAssigned, driverArriving, driverWaiting.
        lastLat ??= _pickupLat! + 0.0072;
        lastLng ??= _pickupLng! - 0.0048;
        _startGps();
      }
      return _controller.stream;
    }

    _sequence = 0;
    lastStatus = RideStatus.findingDriver;
    lastDriver = null;
    // RC-08: like the resume path, deliver the first status once the
    // caller's listener is attached (a broadcast stream drops it otherwise).
    scheduleMicrotask(() {
      if (cancelled || disposed || _rideId != rideId) return;
      if (lastStatus != RideStatus.findingDriver) return;
      _emit(RideStatus.findingDriver);
    });
    _armAssignment(rideId);
    return _controller.stream;
  }

  void _armAssignment(String rideId) {
    _assign = Timer(assignAfter, () {
      _assign = null;
      if (cancelled || disposed || held || _rideId != rideId) return;
      assignNow();
    });
  }

  void holdAssignment() {
    held = true;
    _assign?.cancel();
    _assign = null;
  }

  void assignNow() {
    unawaited(_assignNow());
  }

  Future<void> _assignNow() async {
    final rideId = _rideId;
    if (cancelled ||
        disposed ||
        rideId == null ||
        lastStatus.isTerminal ||
        _assignmentInFlight) {
      return;
    }
    if (lastStatus.isMatched) return;

    _assignmentInFlight = true;
    final assignmentAttempt = _assignmentAttempt;
    _assign?.cancel();
    _assign = null;
    _pickupLat ??= 59.3293;
    _pickupLng ??= 18.0686;
    lastLat ??= _pickupLat! + 0.0072;
    lastLng ??= _pickupLng! - 0.0048;
    lastLocationAt = DateTime.now();
    // Matching is what knows the driver. Assign before persisting so the
    // stored ride, every later resync, and a restored session all agree.
    lastDriver ??= MockDriverPool.forRide(
      rideId,
      attempt: _assignmentAttempt,
    );

    await _persistAssignment(rideId);

    if (cancelled ||
        disposed ||
        _rideId != rideId ||
        assignmentAttempt != _assignmentAttempt ||
        lastStatus != RideStatus.findingDriver) {
      _assignmentInFlight = false;
      // A driver drop can invalidate this attempt while its persistence call
      // is in flight. If the search has already restarted, guarantee a
      // fresh attempt instead of leaving redispatch without a timer.
      if (!cancelled &&
          !disposed &&
          !held &&
          _rideId == rideId &&
          lastStatus == RideStatus.findingDriver &&
          assignmentAttempt != _assignmentAttempt) {
        _assign?.cancel();
        _assign = Timer(assignAfter, () {
          if (cancelled || disposed || held || _rideId != rideId) return;
          assignNow();
        });
      }
      return;
    }

    lastStatus = RideStatus.driverAssigned;
    _assignmentInFlight = false;
    _emit(RideStatus.driverAssigned);
    _startGps();
    unawaited(_hydratePickup());
  }

  void emit(
    RideStatus status, {
    int? sequence,
    MatchedDriver? driver,
    double? latitude,
    double? longitude,
    int? etaSeconds,
    RideRealtimeSignal? signal,
    String? message,
  }) {
    if (_rideId == null || disposed || cancelled || lastStatus.isTerminal) {
      return;
    }
    _sequence = sequence ?? _sequence + 1;
    if (signal == null) _commit(status);
    lastStatus = status;
    if (driver != null) lastDriver = driver;
    if (latitude != null) lastLat = latitude;
    if (longitude != null) lastLng = longitude;
    if (latitude != null || longitude != null) lastLocationAt = DateTime.now();
    final occurredAt = DateTime.now().toUtc();
    _controller.add(
      RideRealtimeEvent(
        tripId: _rideId!,
        eventId: '${_rideId!}:$_sequence:${status.name}',
        status: status,
        sequence: _sequence,
        version: _sequence,
        occurredAt: occurredAt,
        serverTime: occurredAt,
        driver: lastDriver,
        latitude: lastLat,
        longitude: lastLng,
        etaSeconds: etaSeconds,
        locationAt: lastLocationAt,
        signal: signal,
        message: message,
      ),
    );
    if (status.isTerminal) {
      cancelled = true;
      _stopMotion();
      unsubscribe();
    }
  }

  void _emit(RideStatus status) {
    final eta = _etaSeconds();
    emit(status, etaSeconds: eta);
  }

  Future<void> _hydratePickup() async {
    final pickup = await _pickup();
    _pickupLat = pickup.$1;
    _pickupLng = pickup.$2;
  }

  void _startGps() {
    _gps?.cancel();
    _gps = Timer.periodic(const Duration(seconds: 3), (_) {
      if (cancelled || disposed || !lastStatus.isMatched) return;
      _progress = min(1, _progress + 0.12);
      final pickupLat = _pickupLat;
      final pickupLng = _pickupLng;
      if (pickupLat == null ||
          pickupLng == null ||
          lastLat == null ||
          lastLng == null) {
        return;
      }
      lastLat = lastLat! + (pickupLat - lastLat!) * 0.18;
      lastLng = lastLng! + (pickupLng - lastLng!) * 0.18;
      lastLocationAt = DateTime.now();
      var status = RideStatus.driverArriving;
      final distance = GeoDistance.metersBetween(
        lastLat!,
        lastLng!,
        pickupLat,
        pickupLng,
      );
      if (distance < 50) {
        status = RideStatus.driverWaiting;
      }
      lastStatus = status;
      _emit(status);
      if (status == RideStatus.driverWaiting) {
        _gps?.cancel();
        _gps = null;
        emit(
          RideStatus.driverWaiting,
          signal: RideRealtimeSignal.driverArrived,
          message: 'Your driver has arrived at the pickup point.',
        );
        _startTrip();
      }
    });
  }

  /// The assigned driver drops the ride before pickup.
  ///
  /// The rider's ride is not over — dispatch simply looks again — so this
  /// returns to searching and offers a different driver, rather than ending
  /// the trip the way a rider's own cancellation does.
  void cancelByDriver() {
    final rideId = _rideId;
    if (rideId == null || cancelled || disposed) return;
    if (lastStatus.isCompletedSurface || lastStatus.isTerminal) return;

    _stopMotion();
    _assign?.cancel();
    _assign = null;
    _assignmentAttempt += 1;
    lastDriver = null;
    lastLat = null;
    lastLng = null;
    lastLocationAt = null;
    _progress = 0;
    _tripStartLat = null;
    _tripStartLng = null;

    // Publish the driver-drop outcome exactly once so Waiting can explain it.
    // Do not tear the transport down: this terminal-looking dispatch event is
    // reversible for the same ride and researchAfterDriverCancel owns restart.
    // Contract v0.3.0: a live driver cancel before boarding returns the
    // trip to `searching` on the server (never a terminal status that is
    // later undone). The rider sees the reassignment notice.
    _persistDriverCancel(rideId);
    lastStatus = RideStatus.cancelledByDriver;
    _sequence += 1;
    final now = DateTime.now().toUtc();
    _controller.add(
      RideRealtimeEvent(
        tripId: rideId,
        eventId: '$rideId:$_sequence:${RideStatus.cancelledByDriver.name}',
        status: RideStatus.cancelledByDriver,
        sequence: _sequence,
        version: _sequence,
        occurredAt: now,
        serverTime: now,
        payload: {
          'kind': 'driver_cancelled',
          'tripStatus': TripStatus.searching.wireName,
        },
      ),
    );
  }

  /// Search again for the same ride after a driver dropped it.
  @override
  void researchAfterDriverCancel() {
    final rideId = _rideId;
    if (rideId == null) return;

    // Waiting disposes its tracking subscription before the driver-cancel
    // sheet, but that must not dispose this shared transport: redispatch is
    // the same live ride. emit() also latches `cancelled` for every terminal
    // status, including this reversible driver drop. Clear that latch here
    // whether or not the transport itself was disposed.
    if (lastStatus != RideStatus.cancelledByDriver) return;
    disposed = false;
    cancelled = false;
    connection.markConnected();

    // The previous assignment may still be unwinding an async persistence
    // request. Its generation was invalidated by cancelByDriver(), so it must
    // not block the rider-visible redispatch state. Reopen searching now; the
    // stale assignment's post-await guard cannot publish because its captured
    // attempt no longer matches.
    lastStatus = RideStatus.findingDriver;
    _emit(RideStatus.findingDriver);
    _assign?.cancel();
    _assign = Timer(assignAfter, () {
      if (cancelled || disposed || held || _rideId != rideId) return;
      if (_assignmentInFlight) {
        // Let the invalidated persistence unwind, then retry through the same
        // guarded scheduling path instead of dropping redispatch completely.
        _assign = Timer(const Duration(milliseconds: 1), () {
          if (cancelled || disposed || held || _rideId != rideId) return;
          assignNow();
        });
        return;
      }
      assignNow();
    });
  }

  /// Tests drive arrival directly: the GPS walk depends on real pickup
  /// coordinates fetched over the mock API, which unit tests do not stand up.
  @visibleForTesting
  void markArrivedForTest() {
    if (cancelled || disposed || _rideId == null || lastStatus.isTerminal) {
      return;
    }
    lastStatus = RideStatus.driverWaiting;
    emit(
      RideStatus.driverWaiting,
      signal: RideRealtimeSignal.driverArrived,
      message: 'Your driver has arrived at the pickup point.',
    );
    _startTrip();
  }

  /// Moves the driver from pickup toward the destination as the trip ticks
  /// pass, so the in-trip marker/route path is actually exercised by every
  /// journey through this mock, not left sitting at pickup for the whole ride.
  void _advanceTripPosition() {
    final destLat = destinationLat;
    final destLng = destinationLng;
    final startLat = _tripStartLat;
    final startLng = _tripStartLng;
    if (destLat == null ||
        destLng == null ||
        startLat == null ||
        startLng == null) {
      return;
    }
    final t = (_tripTicksDone / tripTicks).clamp(0.0, 1.0);
    lastLat = startLat + (destLat - startLat) * t;
    lastLng = startLng + (destLng - startLng) * t;
    lastLocationAt = DateTime.now();
  }

  /// The driver is at pickup; carry the ride through to completion so the
  /// rider reaches the finished-ride screen instead of waiting forever.
  void _startTrip() {
    // The pickup-approach GPS loop belongs only to the pre-trip stage.
    // Test-driven arrival can bypass the normal GPS distance threshold, so
    // stop it here as well to avoid an orphan periodic timer after boarding.
    _gps?.cancel();
    _gps = null;
    _board?.cancel();
    _board = Timer(boardAfter, () {
      if (cancelled || disposed || _rideId == null) return;
      lastStatus = RideStatus.tripStarted;
      _tripStartLat = lastLat;
      _tripStartLng = lastLng;
      _emit(RideStatus.tripStarted);
      _runTripTicks();
    });
  }

  /// The recurring tick loop shared by a normal boarding-triggered trip start
  /// and a Phase 135 resume that primes straight into a trip-stage status.
  void _runTripTicks() {
    _trip?.cancel();
    _tripTicksDone = 0;
    _trip = Timer.periodic(tripTick, (timer) {
      if (cancelled || disposed || _rideId == null) {
        timer.cancel();
        return;
      }
      _tripTicksDone += 1;
      _advanceTripPosition();
      if (_tripTicksDone >= tripTicks) {
        timer.cancel();
        lastStatus = RideStatus.tripCompleted;
        _emit(RideStatus.tripCompleted);
        // A real backend updates its own ride record before it ever pushes
        // the "trip completed" realtime event, so post-trip feedback always
        // lands against a ride the backend already agrees is finished.
        // Mirror that here the same way _persistAssignment mirrors the
        // driver-assigned handshake: without it, this mock's REST responder
        // never learns the trip ended and rejects feedback submitted against
        // an authoritative-looking rideId with 409 RIDE_NOT_COMPLETE.
        if (_rideId != null) unawaited(_persistCompletion(_rideId!));
        _startPostTripFlow();
        return;
      }
      lastStatus = RideStatus.tripInProgress;
      _emit(RideStatus.tripInProgress);
    });
  }

  void _startPostTripFlow() {
    _paymentProcessing?.cancel();
    _paymentFinalized?.cancel();
    _ratingPending?.cancel();

    _paymentProcessing = Timer(paymentProcessingAfter, () {
      if (cancelled || disposed || _rideId == null) return;
      lastStatus = RideStatus.paymentProcessing;
      _emit(RideStatus.paymentProcessing);

      _paymentFinalized = Timer(paymentFinalizedAfter, () {
        if (cancelled || disposed || _rideId == null) return;
        lastStatus = RideStatus.paymentFinalized;
        _emit(RideStatus.paymentFinalized);

        _ratingPending = Timer(ratingPendingAfter, () {
          if (cancelled || disposed || _rideId == null) return;
          lastStatus = RideStatus.ratingPending;
          _emit(RideStatus.ratingPending);
        });
      });
    });
  }

  int? _etaSeconds() {
    final lat = lastLat;
    final lng = lastLng;
    final pickupLat = _pickupLat;
    final pickupLng = _pickupLng;
    if (lat == null || lng == null || pickupLat == null || pickupLng == null) {
      return null;
    }
    return GeoDistance.urbanSecondsForDistance(
      GeoDistance.metersBetween(lat, lng, pickupLat, pickupLng),
    );
  }

  Future<(double, double)> _pickup() async {
    final client = api;
    final id = _rideId;
    if (client != null && id != null) {
      try {
        final json = await client.get('/api/v1/rides/$id');
        final ride = json['ride'];
        if (ride is Map) {
          final lat = (ride['pickupLat'] as num?)?.toDouble();
          final lng = (ride['pickupLng'] as num?)?.toDouble();
          if (lat != null && lng != null) return (lat, lng);
        }
      } catch (_) {
        // Mock transport: fall back to the default pickup below.
      }
    }
    return (59.3293, 18.0686);
  }

  Future<void> _persistAssignment(String rideId) async {
    final client = api;
    if (client == null) return;
    _committedTarget = TripStatus.accepted.wireName;
    final driver = lastDriver?.toJson();
    final lat = lastLat;
    final lng = lastLng;
    await _enqueue(
      () => client.post(
        '/api/v1/rides/$rideId/status',
        body: {
          // searching → offered → accepted, walked by the server.
          'status': TripStatus.accepted.wireName,
          'driver': driver,
          'lat': lat,
          'lng': lng,
        },
      ),
    );
  }

  Future<void> _persistCompletion(String rideId) async {
    final client = api;
    if (client == null) return;
    _committedTarget = TripStatus.completed.wireName;
    // A real backend updates its own ride record before it ever pushes
    // the "trip completed" realtime event; queued after every earlier step.
    await _enqueue(
      () => client.post(
        '/api/v1/rides/$rideId/status',
        body: {'status': TripStatus.completed.wireName},
      ),
    );
  }

  /// The driver's own cancel (`cancel` by driver): before boarding the
  /// server puts a live trip back to `searching`.
  void _persistDriverCancel(String rideId) {
    final client = api;
    if (client == null) return;
    _committedTarget = null;
    unawaited(
      _enqueue(
        () => client.post(
          '/api/v1/rides/$rideId/status',
          body: {'command': 'cancel', 'actor': 'driver'},
        ),
      ),
    );
  }

  /// Commits [status] on the stand-in server: a lifecycle step as its
  /// contract status, a post-trip UI state as the payment / rating field it
  /// stands for. The server refuses anything the transition table does not
  /// allow (e.g. after the rider cancelled), and the refusal is ignored
  /// here: the server projection stays the truth.
  void _commit(RideStatus status) {
    final client = api;
    final rideId = _rideId;
    if (client == null || rideId == null) return;
    final Map<String, Object?>? body = switch (status) {
      RideStatus.driverAssigned => null, // _persistAssignment carries it.
      RideStatus.findingDriver || RideStatus.cancelledByDriver => null,
      RideStatus.driverArriving ||
      RideStatus.driverWaiting ||
      RideStatus.tripStarted ||
      RideStatus.tripInProgress ||
      RideStatus.approachingDropoff => {
        'status': status.tripStatus.wireName,
      },
      RideStatus.tripCompleted => null, // _persistCompletion carries it.
      RideStatus.paymentProcessing => {'paymentStatus': 'authorized'},
      RideStatus.paymentFinalized => {'paymentStatus': 'captured'},
      RideStatus.ratingPending => {'ratingStatus': 'pending'},
      _ => null,
    };
    if (body == null) return;
    final target = '${body.values.single}';
    if (target == _committedTarget) return;
    _committedTarget = target;
    unawaited(_enqueue(() => client.post('/api/v1/rides/$rideId/status', body: body)));
  }

  Future<void> _enqueue(Future<Object?> Function() call) {
    return _commits = _commits.then((_) async {
      try {
        await call();
      } catch (_) {
        // Mock transport: a refused or lost commit leaves the server as is.
      }
    });
  }

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {
    if (_rideId != rideId || disposed || cancelled) return;
    emit(
      lastStatus,
      signal: signal,
      message: message,
    );
  }

  @override
  Future<void> reconnectAndResync(String rideId) async {
    connection.state = RealtimeState.reconnecting;
    await Future<void>.delayed(connection.nextBackoff());
    connection.markConnected();
    var status = lastStatus;
    final client = api;
    if (client != null) {
      try {
        final json = await client.get('/api/v1/rides/$rideId');
        final raw = json['ride'];
        if (raw is Map &&
            (raw['tripId'] ?? raw['id'])?.toString() == rideId &&
            raw['status'] is String) {
          status = RideStatusWire.fromProjection(raw) ?? status;
          lastDriver =
              MatchedDriver.fromJson(
                raw['driver'] is Map
                    ? Map<String, dynamic>.from(raw['driver'] as Map)
                    : null,
              ) ??
              lastDriver;
        }
      } catch (_) {
        // Mock transport: keep the last driver.
      }
    }
    // Deliver the authoritative resync status before committing it to
    // lastStatus. emit() guards against events after a terminal status; writing
    // the incoming terminal status first would therefore make the event block
    // itself and disappear from the Rider stream.
    if (!cancelled && !disposed && _rideId == rideId) {
      _emit(status);
    }
  }

  @override
  void unsubscribe() {
    _assign?.cancel();
    _assign = null;
  }

  @override
  void cancelRide() {
    cancelled = true;
    lastStatus = RideStatus.cancelledByRider;
    _stopMotion();
    unsubscribe();
  }

  /// Every timer that advances a ride, stopped together — a cancelled or
  /// disposed ride must not keep driving itself to completion.
  void _stopMotion() {
    _gps?.cancel();
    _gps = null;
    _board?.cancel();
    _board = null;
    _trip?.cancel();
    _trip = null;
    _paymentProcessing?.cancel();
    _paymentProcessing = null;
    _paymentFinalized?.cancel();
    _paymentFinalized = null;
    _ratingPending?.cancel();
    _ratingPending = null;
  }

  @override
  void dispose() {
    disposed = true;
    cancelled = true;
    _stopMotion();
    unsubscribe();
    if (!_controller.isClosed) _controller.close();
  }
}
