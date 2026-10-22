import 'dart:async';

import 'package:movera_rider/core/contracts/wire_time.dart';
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
    this.onProjectionVersion,
  }) : connection = connection ?? RealtimeConnection();

  /// R-O2: told the server's `TripProjection.version` each time a commit
  /// or read answers with one, so the rider's next command can send it as
  /// `expectedVersion`. The events below are numbered by this transport,
  /// not by the server, so their `version` cannot be used for that.
  final void Function(String tripId, int version)? onProjectionVersion;

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
  double? _resumePickupLat;
  double? _resumePickupLng;

  /// rider-u30: the rider moved the pickup after the accept (Q40). The
  /// demo driver turns towards the new point, and arrives there, instead
  /// of the pickup it was first sent to. Ignored once the rider is aboard.
  void movePickup(double lat, double lng) {
    if (_onTripStatuses.contains(lastStatus) ||
        lastStatus.isCompletedSurface ||
        lastStatus.isTerminal) {
      return;
    }
    _pickupLat = lat;
    _pickupLng = lng;
  }

  /// The stand-in pickup when neither the caller nor the server knows one.
  static const _fallbackPickup = (59.3293, 18.0686);

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
  ///
  /// rider-24: [pickupLat]/[pickupLng] are the restored trip's own pickup,
  /// so the resumed driver approaches it (not a fixed Stockholm point).
  void primeResume({
    required RideStatus status,
    MatchedDriver? driver,
    int? version,
    double? pickupLat,
    double? pickupLng,
  }) {
    _resumeStatus = status;
    _resumeDriver = driver;
    _resumeVersion = version;
    _resumePickupLat = pickupLat;
    _resumePickupLng = pickupLng;
  }

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    // Consumed exactly once per call, on every path, so a primed value can
    // never leak into a later, unrelated subscribe().
    final resumeStatus = _resumeStatus;
    final resumeDriver = _resumeDriver;
    final resumeVersion = _resumeVersion;
    final resumePickupLat = _resumePickupLat;
    final resumePickupLng = _resumePickupLng;
    _resumeStatus = null;
    _resumeDriver = null;
    _resumeVersion = null;
    _resumePickupLat = null;
    _resumePickupLng = null;

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
    _acceptedAt = null;
    _waitingSince = null;
    _committedTarget = null;
    // A new ride starts a new commit queue (an older ride's pending commit
    // must never hold this one back).
    _commits = Future<void>.value();
    lastLat = null;
    lastLng = null;
    lastLocationAt = null;
    // rider-u28: a new ride has its own pickup. Kept, the next ride's
    // driver spawned next to the previous ride's pickup and drove across.
    _pickupLat = null;
    _pickupLng = null;
    _progress = 0;
    _tripStartLat = null;
    _tripStartLng = null;
    connection.markConnected();

    if (resumeStatus != null && resumeStatus.isMatched) {
      _sequence = resumeVersion ?? 0;
      lastStatus = resumeStatus;
      lastDriver = resumeDriver;
      if (resumePickupLat != null && resumePickupLng != null) {
        _pickupLat = resumePickupLat;
        _pickupLng = resumePickupLng;
      }
      unawaited(_resume(rideId, resumeStatus));
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

  /// rider-24: the trip's pickup and the server's accept/waiting stamps
  /// are read before the resumed driver is placed or a clock is shown, so
  /// after a reload the driver approaches (and arrives at) the trip's own
  /// pickup and the free-cancel and waiting clocks do not restart.
  ///
  /// A broadcast StreamController cannot deliver an event added before a
  /// listener exists, and the caller's `.subscribe(id).listen(...)` chain
  /// attaches its listener only after [subscribe] returns. The await below
  /// always defers the resumed status past that point.
  Future<void> _resume(String rideId, RideStatus status) async {
    final ride = await _serverRide();
    if (cancelled || disposed || _rideId != rideId) return;
    if (ride != null) {
      _adoptPickup(ride);
      _acceptedAt = WireTime.tryParse(ride['acceptedAt']);
      final waiting = ride['waiting'];
      if (waiting is Map) _waitingSince = WireTime.tryParse(waiting['arrivedAt']);
    }
    _pickupLat ??= _fallbackPickup.$1;
    _pickupLng ??= _fallbackPickup.$2;
    const tripStatuses = {
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
      RideStatus.approachingDropoff,
    };
    final onTrip = tripStatuses.contains(status);
    // rider-u27: a driver already waiting stays at the pickup and the ride
    // goes on to boarding. Through the approach below, the first GPS tick
    // put them back about 800 m away as "driver arriving".
    final waiting = status == RideStatus.driverWaiting;
    if (waiting) {
      lastLat ??= _pickupLat;
      lastLng ??= _pickupLng;
    } else if (!onTrip) {
      // The remaining isMatched statuses are the pre-trip approach:
      // driverAssigned, driverArriving.
      lastLat ??= _pickupLat! + 0.0072;
      lastLng ??= _pickupLng! - 0.0048;
    }
    _emit(status);
    if (onTrip) {
      _tripStartLat ??= _pickupLat;
      _tripStartLng ??= _pickupLng;
      _runTripTicks();
    } else if (waiting) {
      _startTrip();
    } else {
      _startGps();
    }
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
    // rider-24: the driver spawns near this trip's pickup. When it is not
    // known yet, the accept's answer (the trip projection) says where it
    // is, and the driver is placed before being shown. Before, a fixed
    // Stockholm point was used and the pickup read only afterwards.
    final pickupKnown = _pickupLat != null && _pickupLng != null;
    if (pickupKnown) _spawnDriver();
    // Matching is what knows the driver. Assign before persisting so the
    // stored ride, every later resync, and a restored session all agree.
    lastDriver ??= MockDriverPool.forRide(
      rideId,
      attempt: _assignmentAttempt,
    );

    final accepted = await _persistAssignment(rideId);

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

    if (!pickupKnown) {
      if (accepted != null) _adoptPickup(accepted);
      _pickupLat ??= _fallbackPickup.$1;
      _pickupLng ??= _fallbackPickup.$2;
      _spawnDriver();
      _commitFix();
    }
    lastStatus = RideStatus.driverAssigned;
    _assignmentInFlight = false;
    _emit(RideStatus.driverAssigned);
    _startGps();
  }

  /// The assigned driver's first fix, a short drive from the pickup.
  void _spawnDriver() {
    lastLat ??= _pickupLat! + 0.0072;
    lastLng ??= _pickupLng! - 0.0048;
    lastLocationAt = DateTime.now();
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
    // Contract v0.4.0: the projection stamps the accept (Q12) and the start
    // of the waiting clock (Q42); a new search clears both.
    if (status.isSearching) {
      _acceptedAt = null;
      _waitingSince = null;
    } else if (status.isMatched) {
      _acceptedAt ??= DateTime.now().toUtc();
    }
    if (status == RideStatus.driverWaiting) {
      _waitingSince ??= DateTime.now().toUtc();
    }
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
        payload: {
          if (_acceptedAt case final at?) acceptedAtKey: WireTime.format(at),
          if (_waitingSince case final at?)
            waitingArrivedAtKey: WireTime.format(at),
        },
      ),
    );
    if (status.isTerminal) {
      cancelled = true;
      _stopMotion();
      unsubscribe();
    }
  }

  /// When this ride's driver accepted and started waiting (UTC).
  DateTime? _acceptedAt;
  DateTime? _waitingSince;

  void _emit(RideStatus status) {
    final eta = _etaSeconds();
    emit(status, etaSeconds: eta);
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
    _acceptedAt = null;
    _waitingSince = null;
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
  /// True when the driver moved.
  bool _advanceTripPosition() {
    final destLat = destinationLat;
    final destLng = destinationLng;
    final startLat = _tripStartLat;
    final startLng = _tripStartLng;
    if (destLat == null ||
        destLng == null ||
        startLat == null ||
        startLng == null) {
      return false;
    }
    final t = (_tripTicksDone / tripTicks).clamp(0.0, 1.0);
    lastLat = startLat + (destLat - startLat) * t;
    lastLng = startLng + (destLng - startLng) * t;
    lastLocationAt = DateTime.now();
    return true;
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
      final moved = _advanceTripPosition();
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
      if (moved) _commitFix();
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

  /// Seconds to where the driver is headed: the pickup before boarding,
  /// the destination once the rider is aboard (rider-u31: measured to the
  /// pickup, the in-trip 'Arrive by' moved later as the car neared the
  /// drop-off). Null when that point is not known.
  int? _etaSeconds() {
    final lat = lastLat;
    final lng = lastLng;
    final aboard = _onTripStatuses.contains(lastStatus);
    final toLat = aboard ? destinationLat : _pickupLat;
    final toLng = aboard ? destinationLng : _pickupLng;
    if (lat == null || lng == null || toLat == null || toLng == null) {
      return null;
    }
    return GeoDistance.urbanSecondsForDistance(
      GeoDistance.metersBetween(lat, lng, toLat, toLng),
    );
  }

  /// The stand-in server's projection of this ride, when it has one.
  Future<Map<dynamic, dynamic>?> _serverRide() async {
    final client = api;
    final id = _rideId;
    if (client == null || id == null) return null;
    try {
      final json = await client.get('/api/v1/rides/$id');
      _observe(json);
      final ride = json['ride'];
      return ride is Map ? ride : null;
    } catch (_) {
      // Mock transport: the caller falls back to what it already knows.
      return null;
    }
  }

  void _adoptPickup(Map<dynamic, dynamic> ride) {
    final lat = (ride['pickupLat'] as num?)?.toDouble();
    final lng = (ride['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    _pickupLat ??= lat;
    _pickupLng ??= lng;
  }

  /// Commits the accept; answers the server's trip projection, if any.
  Future<Map<dynamic, dynamic>?> _persistAssignment(String rideId) async {
    final client = api;
    if (client == null) return null;
    _committedTarget = TripStatus.accepted.wireName;
    final driver = lastDriver?.toJson();
    final lat = lastLat;
    final lng = lastLng;
    final response = await _enqueue(
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
    final ride = response is Map ? response['ride'] : null;
    return ride is Map ? ride : null;
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
    // R-O1: on board, the driver's fix rides along, so the server can
    // measure the distance driven from where the trip started.
    final lat = lastLat;
    final lng = lastLng;
    final onTrip = _onTripStatuses.contains(status);
    final payload = {
      ...body,
      if (onTrip && lat != null && lng != null) 'lat': lat,
      if (onTrip && lat != null && lng != null) 'lng': lng,
    };
    unawaited(
      _enqueue(
        () => client.post('/api/v1/rides/$rideId/status', body: payload),
      ),
    );
  }

  static const _onTripStatuses = {
    RideStatus.tripStarted,
    RideStatus.tripInProgress,
    RideStatus.approachingDropoff,
  };

  /// R-O1: one GPS fix of the driver for the server (a `location` event
  /// there, version unchanged), queued after the status commits.
  void _commitFix() {
    final client = api;
    final rideId = _rideId;
    final lat = lastLat;
    final lng = lastLng;
    if (client == null || rideId == null || lat == null || lng == null) {
      return;
    }
    unawaited(
      _enqueue(
        () => client.post(
          '/api/v1/rides/$rideId/status',
          body: {'lat': lat, 'lng': lng},
        ),
      ),
    );
  }

  /// Queues [call] after the earlier commits; answers its response, or
  /// null when it was refused or lost.
  Future<Object?> _enqueue(Future<Object?> Function() call) {
    final done = _commits.then((_) async {
      try {
        final response = await call();
        _observe(response);
        return response;
      } catch (_) {
        // Mock transport: a refused or lost commit leaves the server as is.
        return null;
      }
    });
    _commits = done;
    return done;
  }

  /// R-O2: passes on the server's projection version from a response.
  void _observe(Object? response) {
    final callback = onProjectionVersion;
    if (callback == null || response is! Map) return;
    final ride = response['ride'] ?? response['projection'] ?? response;
    if (ride is! Map) return;
    final id = (ride['tripId'] ?? ride['id'])?.toString();
    final version = ride['version'];
    if (id == null || id.isEmpty || version is! num) return;
    callback(id, version.toInt());
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
        _observe(json);
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
