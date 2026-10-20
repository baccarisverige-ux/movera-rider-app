import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/core/analytics/analytics.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/core/contracts/trip_projection_wire.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/trip_transitions.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/finding_driver/domain/nearby_vehicle.dart';
import 'package:movera_rider/features/finding_driver/domain/search_copy.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// What happened when the rider cancelled the search (cancel-first).
enum SearchCancelResult {
  /// The server confirmed the cancel (or no longer knows the ride). Local
  /// state is committed: cancelled, archived to History, snapshot cleared.
  confirmed,

  /// The server could not be reached. The cancel sits in the pending-cancel
  /// outbox with its idempotency key and is retried on reconnect or launch.
  /// Nothing is committed (RC-03): the search shows "Cancelling…" and keeps
  /// listening, so a driver who accepted meanwhile is not lost. The server's
  /// answer commits it, or brings the match.
  queued,

  /// The server refused with 409: a driver accepted the ride first. Nothing
  /// was committed; the search keeps listening and resyncs so the rider is
  /// moved to the matched screen.
  driverAccepted,

  /// The server refused (410/422): the ride can no longer be cancelled.
  /// Nothing was committed; realtime reports the real outcome.
  rejected,

  /// The server refused with `409 version_mismatch` (X7): the trip changed
  /// since this screen read it. Nothing was committed or re-sent; the
  /// search resyncs and the rider decides again.
  stale,

  /// Nothing to do: already cancelled, finished, matched or disposed.
  ignored,
}

class FindingDriverController {
  FindingDriverController({
    FindingDriverRepository? store,
    RideRealtime? realtime,
    RideSession? ride,
    ApiClient? api,
    OnDemandArchiveWriter? historyArchiveWriter,
    this.delayedAfter = SearchCopy.delayedAfter,
    Duration? priceBumpAfter,
    this.searchTimeout = const Duration(minutes: 3),
    this.serverCheckEvery = const Duration(seconds: 15),
  }) : priceBumpAfter =
           priceBumpAfter ??
           (AppScope.instance.environment.allowsMockTransport
               ? SearchCopy.demoPriceBumpAfter
               : SearchCopy.priceBumpAfter),
       _store = store ?? FindingDriverRepository(),
       _realtime = realtime ?? AppScope.instance.rideRealtime,
       _ride = ride,
       _api = api,
       _historyArchiveWriter = historyArchiveWriter;

  static FindingDriverController? active;

  final FindingDriverRepository _store;
  final RideRealtime _realtime;
  final RideSession? _ride;
  final ApiClient? _api;
  final OnDemandArchiveWriter? _historyArchiveWriter;
  final Duration delayedAfter;

  /// When the "raise your offer" card appears, if no driver has accepted.
  final Duration priceBumpAfter;

  /// ARCH-3: after this long without a driver the rider is offered "Still
  /// looking for a driver" (keep searching or cancel) and the server is asked
  /// for the ride's state. It is a UI mark only: the ride ends as "no driver
  /// found" when the server says so, never on this client timer.
  final Duration searchTimeout;

  /// While still looking, how often the server is asked again.
  final Duration serverCheckEvery;
  final MutationAttempt _pickupMutation = MutationAttempt('ride-pickup');
  final MutationAttempt _priceMutation = MutationAttempt('ride-price');
  final MutationAttempt _reasonMutation = MutationAttempt('ride-cancel-reason');
  Timer? _tick;
  StreamSubscription<RideRealtimeEvent>? _sub;
  bool _assigned = false;
  bool _cancelled = false;
  bool _cancelInFlight = false;

  /// RC-03: the rider's cancel is in the outbox, not yet confirmed.
  bool _cancelQueued = false;
  String? _queuedReasonId;
  StreamSubscription<PendingCancelOutcome>? _outboxSub;
  void Function()? _onCancelRefused;

  /// R-O2: the last queued-cancel refusal was the outbox dropping it
  /// because the trip changed first, not a server refusal.
  bool get lastRefusalWasStale => _lastRefusalStale;
  bool _lastRefusalStale = false;
  bool _terminated = false;
  bool _disposed = false;
  bool _delayedLogged = false;
  bool _bumpDismissed = false;
  bool _priceUpdated = false;
  bool _editInFlight = false;
  bool _assignmentPending = false;
  bool _stillLooking = false;
  bool _stillLookingDismissed = false;
  bool _serverCheckInFlight = false;
  /// Contract v0.3.0 realtime gate: the server's sequence and eventId,
  /// `sequence <= last` dropped, nothing but payment/rating/message after a
  /// terminal status.
  final RealtimeGate _gate = RealtimeGate();
  int _nearbyRequestEpoch = 0;
  int _pickupUpdateEpoch = 0;
  int _editEpoch = 0;
  RideSnapshot? _snapshot;
  double? _catalogPrice;
  void Function()? _onMatched;
  void Function(RideStatus status)? _onTerminal;
  void Function(int elapsed)? _onTick;
  int timeoutLogs = 0;
  int elapsedSeconds = 0;
  String? offerConfirmation;
  String? editFeedback;
  MatchedDriver? matchedDriver;
  List<NearbyVehicle> nearby = const [];

  RideSession get ride => _ride ?? AppScope.instance.ride;
  ApiClient get api => _api ?? AppScope.instance.api;

  /// Stable identity captured when this Finding owner started. Unlike the
  /// process-wide RideSession, this cannot be overwritten by a concurrent
  /// booking response before ownership is reconciled.
  String? get ownedRideId => _snapshot?.rideId?.trim();

  RideSnapshot? get ownershipSnapshot => _snapshot;

  int get matchCount => _assigned ? 1 : 0;

  /// True while a cancel request is waiting for the server's answer.
  bool get cancelInFlight => _cancelInFlight;

  /// True once the rider's cancel has been committed locally.
  bool get cancelled => _cancelled;

  /// True while the rider's cancel waits in the outbox for the server
  /// (offline). The ride is still live until the server answers.
  bool get cancelQueued => _cancelQueued && !_cancelled && !_terminated;
  bool get editInFlight => _editInFlight;
  bool get isDelayed => elapsedSeconds >= delayedAfter.inSeconds;

  /// True once the search passed [searchTimeout] without a driver. The ride
  /// is still searching on the server.
  bool get stillLooking =>
      _stillLooking && !_assigned && !_cancelled && !_terminated;

  /// The "Still looking for a driver" card (Keep searching / Cancel request).
  bool get showStillLooking =>
      stillLooking &&
      !_stillLookingDismissed &&
      !_cancelInFlight &&
      !_cancelQueued &&
      !_assignmentPending;
  bool get showPriceBump =>
      elapsedSeconds >= priceBumpAfter.inSeconds &&
      !_bumpDismissed &&
      !_assigned &&
      !_assignmentPending &&
      !_cancelQueued &&
      !_cancelled &&
      !_terminated;
  double get currentPrice => _snapshot?.price ?? 0;

  /// Q7: the currency of this trip (its pickup's zone). [currentPrice] and
  /// [maxOfferPrice] are whole units of it.
  String get currency => _snapshot?.currency ?? Money.defaultCurrency;
  /// ARCH-20: the ceiling the booking carries (server or booked fare), so a
  /// raised offer plus a reload does not lift it; the catalog rule only for
  /// a snapshot without one.
  double get maxOfferPrice {
    final minor = _snapshot?.maxOfferMinor;
    if (minor != null) return Money(minor, currency).major;
    return FareRules.maximum(_catalogPrice ?? currentPrice);
  }
  String get pickupAddress => _snapshot?.pickupAddress ?? '';
  double? get pickupLat => _snapshot?.pickupLat;
  double? get pickupLng => _snapshot?.pickupLng;
  SearchCopy get copy => cancelQueued
      ? cancellingCopy
      : stillLooking
      ? stillLookingCopy
      : SearchCopy.forElapsed(elapsedSeconds);

  static const cancellingCopy = SearchCopy(
    headline: 'Cancelling your ride…',
    subtitle: 'We’ll confirm it with Movera as soon as you’re back online.',
  );

  static const stillLookingCopy = SearchCopy(
    headline: 'Still looking for a driver',
    subtitle: 'No driver has accepted yet. Your request is still active.',
  );

  void startFrom({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    String currency = Money.defaultCurrency,
    required String paymentMethod,
    int walletAmountMinor = 0,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    DateTime? searchStartedAt,
    DateTime? createdAt,
    required void Function(int elapsed) onTick,
    required void Function() onMatched,
    void Function(RideStatus status)? onTerminal,
    void Function()? onCancelRefused,
  }) {
    final now = DateTime.now();
    final session = ride;
    final rideId = session.rideId;
    start(
      snapshot: RideSnapshot(
        stops: stops,
        status: RideStatus.findingDriver,
        savedAt: now,
        createdAt: createdAt,
        // ARCH-3: a restored search keeps its own start, so the "still
        // looking" mark survives a reload.
        searchStartedAt: searchStartedAt ?? now,
        // ARCH-1: keep the server ordering the session already holds for
        // this ride, so every later snapshot save persists it.
        version: rideId == null ? null : session.authoritativeVersion,
        serverUpdatedAt:
            rideId == null ? null : session.authoritativeUpdatedAt?.toUtc(),
        categoryId: rideId == null ? null : session.bookedCategoryId,
        paymentMethodId: rideId == null ? null : session.bookedPaymentMethodId,
        maxOfferMinor: rideId == null ? null : session.bookedMaxOfferMinor,
        pickupAddress: pickupAddress,
        destinationAddress: destinationAddress,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
        rideType: rideType,
        price: price,
        currency: currency,
        paymentMethod: paymentMethod,
        rideId: ride.rideId,
        notes: notes,
        walletAmountMinor: walletAmountMinor,
      ),
      onTick: onTick,
      onMatched: onMatched,
      onTerminal: onTerminal,
      onCancelRefused: onCancelRefused,
    );
  }

  void start({
    int seconds = 12,
    required RideSnapshot snapshot,
    required void Function(int elapsed) onTick,
    required void Function() onMatched,
    void Function(RideStatus status)? onTerminal,
    void Function()? onCancelRefused,
  }) {
    if (_realtime is ApiRideRealtime &&
        snapshot.rideId?.trim().isNotEmpty != true) {
      throw StateError('Cannot search without a server rideId.');
    }
    active = this;
    _snapshot = snapshot;
    _catalogPrice = snapshot.price;
    _onMatched = onMatched;
    _onTerminal = onTerminal;
    _onTick = onTick;
    _onCancelRefused = onCancelRefused;
    _assigned = false;
    _cancelled = false;
    _cancelInFlight = false;
    _cancelQueued = false;
    _queuedReasonId = null;
    _terminated = false;
    _disposed = false;
    _delayedLogged = false;
    _bumpDismissed = false;
    _priceUpdated = false;
    _editInFlight = false;
    _assignmentPending = false;
    _stillLooking = false;
    _stillLookingDismissed = false;
    _serverCheckInFlight = false;
    _gate.reset();
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _editEpoch += 1;
    // ARCH-3 / RIDE-5: elapsed counts from when this search started, not
    // from when this screen mounted, so a reload does not restart it.
    final sinceStart = DateTime.now().difference(snapshot.searchStart);
    elapsedSeconds = sinceStart.isNegative ? 0 : sinceStart.inSeconds;
    timeoutLogs = 0;
    offerConfirmation = null;
    editFeedback = null;
    matchedDriver = snapshot.driver;
    nearby = const [];
    if (ride.status != snapshot.status || ride.rideId != snapshot.rideId) {
      ride.backendReconcile(snapshot.status, id: snapshot.rideId);
    }
    _tick?.cancel();
    _sub?.cancel();
    _evaluatePhase();
    _onTick?.call(elapsedSeconds);
    _startTick();
    final rideId = snapshot.rideId ?? ride.rideId ?? 'ride';
    if (elapsedSeconds >= searchTimeout.inSeconds) {
      scheduleMicrotask(_reachSearchTimeout);
    }
    unawaited(_outboxSub?.cancel());
    _outboxSub = PendingCancelStore.outcomes.listen(_onOutboxOutcome);
    unawaited(_adoptQueuedCancel(snapshot.rideId));
    _sub = _realtime.subscribe(rideId).listen((event) {
      if (_disposed || _cancelled || _terminated) return;
      // A projection at sequence 0 (contract minimum: no realtime event
      // yet) carries no event to gate; the transport ordered it by version.
      if (event.sequence > 0) {
        final disposition = _gate.admit(
          eventId: event.eventId,
          tripId: event.tripId,
          sequence: event.sequence,
          kind: event.kind,
          isTerminalStatus: event.status.isTerminal,
        );
        if (!disposition.passes) return;
      }
      if (_cancelQueued && event.status == RideStatus.cancelledByRider) {
        // The queued cancel reached the server.
        unawaited(_confirmQueuedCancel());
        return;
      }
      // The server answers again and the ride is still searching: send the
      // queued cancel now (never for a ride a driver already accepted).
      if (_cancelQueued && event.status.isSearching) _flushQueuedCancel();
      if (_assigned && event.status == RideStatus.driverAssigned) return;
      if (event.driver != null) matchedDriver = event.driver;

      final accepted = ride.backendReconcile(
        event.status,
        id: event.tripId,
        version: event.version ?? event.sequence,
        updatedAt: event.serverTime ?? event.occurredAt,
      );
      if (!accepted && event.status != ride.status) return;

      if (event.status.isTerminal) {
        unawaited(_completeTerminal(event.status));
        return;
      }
      if (event.status == RideStatus.driverAssigned || event.status.isMatched) {
        _completeAssigned();
      }
    });
    _loadNearby(rideId);
    installMatchingQaHooks(
      hold: () {
        final realtime = _realtime;
        if (realtime is MockRideRealtime) realtime.holdAssignment();
      },
      assign: () {
        final realtime = _realtime;
        if (realtime is MockRideRealtime) realtime.assignNow();
      },
      advance: debugAdvance,
    );
    _reportQa();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || _assigned || _cancelled || _terminated) {
        timer.cancel();
        return;
      }
      elapsedSeconds += 1;
      _evaluatePhase();
      _afterElapsed(1);
      _onTick?.call(elapsedSeconds);
    });
  }

  void debugAdvance(int seconds) {
    if (_disposed || _assigned || _cancelled || _terminated) return;
    elapsedSeconds += seconds;
    _evaluatePhase();
    _afterElapsed(seconds);
    _onTick?.call(elapsedSeconds);
    _reportQa();
  }

  /// The search-timeout mark and the periodic server check after it.
  void _afterElapsed(int step) {
    if (elapsedSeconds < searchTimeout.inSeconds) return;
    if (!_stillLooking) {
      _reachSearchTimeout();
      return;
    }
    final every = serverCheckEvery.inSeconds;
    if (every <= 0) return;
    final past = elapsedSeconds - searchTimeout.inSeconds;
    // A check is due whenever this step crossed a multiple of [every].
    if (past ~/ every != (past - step) ~/ every) {
      unawaited(checkServerSearchState());
    }
  }

  void _reachSearchTimeout() {
    if (_stillLooking ||
        _assigned ||
        _assignmentPending ||
        _cancelled ||
        _terminated ||
        _disposed) {
      return;
    }
    _stillLooking = true;
    AppLog.info(
      'ride.finding.still_looking',
      extra: {'rideId': _snapshot?.rideId, 'elapsed': elapsedSeconds},
    );
    _onTick?.call(elapsedSeconds);
    _reportQa();
    unawaited(checkServerSearchState());
  }

  /// "Keep searching": hides the still-looking card. The search and the
  /// periodic server check go on.
  void keepSearching() {
    if (!stillLooking) return;
    _stillLookingDismissed = true;
    _onTick?.call(elapsedSeconds);
    _reportQa();
  }

  /// ARCH-3: asks the server (GET /rides/{id}) where the search stands.
  /// Only the server ends it: "no driver found" / expired is shown when the
  /// server says so; a driver the server already assigned moves the rider
  /// on. Anything else, or no answer, keeps the search going.
  Future<void> checkServerSearchState() async {
    if (_serverCheckInFlight ||
        _assigned ||
        _assignmentPending ||
        _cancelled ||
        _cancelInFlight ||
        _terminated ||
        _disposed) {
      return;
    }
    final id = (_snapshot?.rideId ?? ride.rideId)?.trim();
    if (id == null || id.isEmpty) return;
    _serverCheckInFlight = true;
    try {
      final json = await api.get('/api/v1/rides/$id');
      if (_assigned ||
          _cancelled ||
          _cancelInFlight ||
          _terminated ||
          _disposed) {
        return;
      }
      final raw = tripProjectionOf(json);
      if (raw == null || tripIdOf(raw) != id) return;
      // ARCH-10 / contract v0.3.0: the one wire parser (`expired` means
      // what it means everywhere: no driver found).
      final status = RideStatusWire.fromProjection(raw);
      if (status == null || status.isSearching) return;
      final version = (raw['version'] as num?)?.toInt();
      final updatedAt = raw['updatedAt'] is String
          ? DateTime.tryParse(raw['updatedAt'] as String)
          : null;
      final accepted = ride.backendReconcile(
        status,
        id: id,
        version: version,
        updatedAt: updatedAt,
      );
      if (!accepted && ride.status != status) return;
      if (status.isTerminal) {
        _realtime.unsubscribe();
        await _completeTerminal(status);
        return;
      }
      if (status.isMatched) {
        final driver = raw['driver'];
        if (driver is Map) {
          matchedDriver =
              MatchedDriver.fromJson(Map<String, dynamic>.from(driver)) ??
              matchedDriver;
        }
        _completeAssigned();
      }
    } catch (error) {
      AppLog.warning(
        'ride.finding.server_check_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
    } finally {
      _serverCheckInFlight = false;
    }
  }

  /// The stored snapshot of [rideId] (the session's ride when null), or
  /// null when the store holds another ride or none. It carries what other
  /// screens saved meanwhile, such as a route change made on Waiting.
  Future<RideSnapshot?> storedRide({String? rideId}) async {
    final id = (rideId ?? ownedRideId ?? ride.rideId)?.trim();
    if (id == null || id.isEmpty) return null;
    try {
      final stored = await _store.read();
      return stored?.rideId?.trim() == id ? stored : null;
    } catch (_) {
      return null;
    }
  }

  /// The snapshot with the server ordering the session holds for its ride.
  RideSnapshot _ordered(RideSnapshot snapshot) {
    final session = ride;
    if (session.rideId == null || session.rideId != snapshot.rideId) {
      return snapshot;
    }
    return snapshot.copyWith(
      version: session.authoritativeVersion,
      serverUpdatedAt: session.authoritativeUpdatedAt?.toUtc(),
    );
  }

  void _evaluatePhase() {
    if (_assigned || _cancelled || _terminated || _disposed) return;
    if (!isDelayed) return;
    if (!_delayedLogged) {
      _delayedLogged = true;
      timeoutLogs += 1;
      if (ride.status == RideStatus.findingDriver) {
        ride.localTransition(RideStatus.searchDelayed);
      }
      final snapshot = _snapshot;
      if (snapshot != null) {
        _store.save(
          _ordered(snapshot).copyWith(
            status: RideStatus.searchDelayed,
            savedAt: DateTime.now(),
          ),
        );
      }
      AppLog.info(
        'ride.finding.delayed',
        extra: {'rideId': _snapshot?.rideId, 'elapsed': elapsedSeconds},
      );
    }
    _reportQa();
  }

  Future<void> _loadNearby(String rideId) async {
    final requestEpoch = ++_nearbyRequestEpoch;
    try {
      final json = await api.get('/api/v1/rides/$rideId/nearby');
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      final raw = json['vehicles'];
      if (raw is! List) return;
      final nextNearby = raw
          .whereType<Map>()
          .map(
            (item) => NearbyVehicle.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<NearbyVehicle>()
          .toList();
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      nearby = nextNearby;
      _onTick?.call(elapsedSeconds);
    } catch (_) {
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      nearby = const [];
      _onTick?.call(elapsedSeconds);
    }
  }

  int? _beginEdit() {
    if (_assigned ||
        _assignmentPending ||
        _editInFlight ||
        _cancelInFlight ||
        _cancelled ||
        _terminated ||
        _disposed) {
      return null;
    }
    _editInFlight = true;
    _editEpoch += 1;
    return _editEpoch;
  }

  bool _editInvalid(int token) =>
      token != _editEpoch || _cancelled || _terminated || _disposed;

  void _finishEdit(int token) {
    if (token == _editEpoch || _editInFlight) {
      _editInFlight = false;
    }
    _onTick?.call(elapsedSeconds);
    if (_assignmentPending &&
        !_cancelInFlight &&
        !_cancelled &&
        !_terminated &&
        !_disposed) {
      _assignmentPending = false;
      _completeAssigned();
    }
  }

  Future<bool> updatePickup({
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final snapshot = _snapshot;
    final id = snapshot?.rideId ?? ride.rideId;
    if (snapshot == null || id == null) return false;
    final editToken = _beginEdit();
    if (editToken == null) {
      editFeedback = _assigned || _assignmentPending
          ? 'Driver assigned before the pickup change could be applied.'
          : 'Couldn’t update pickup. Try again.';
      _onTick?.call(elapsedSeconds);
      return false;
    }
    editFeedback = null;
    _onTick?.call(elapsedSeconds);
    final updateEpoch = ++_pickupUpdateEpoch;
    final intent = jsonEncode({
      'rideId': id,
      'pickupAddress': address,
      'pickupLat': latitude,
      'pickupLng': longitude,
    });
    try {
      // R-O2: changed on the trip this search last saw.
      final version = _pickupMutation.versionFor(
        intent,
        ride.projectionVersionOf(id),
      );
      final response = await api.patch(
        '/api/v1/rides/$id',
        body: {
          'pickupAddress': address,
          'pickupLat': latitude,
          'pickupLng': longitude,
          'expectedVersion': ?version,
        },
        idempotencyKey: _pickupMutation.keyFor(intent),
      );
      _pickupMutation.succeeded(intent);
      ride.observeProjection(response);
      if (_editInvalid(editToken) || updateEpoch != _pickupUpdateEpoch) {
        return false;
      }
      final updated = snapshot.copyWith(
        status: ride.status,
        savedAt: DateTime.now(),
        pickupAddress: address,
        pickupLat: latitude,
        pickupLng: longitude,
      );
      _snapshot = updated;
      await _store.save(updated);
      if (_editInvalid(editToken) || updateEpoch != _pickupUpdateEpoch) {
        return false;
      }
      if (!_assignmentPending && !_assigned) {
        await _loadNearby(id);
      }
      if (_editInvalid(editToken) || updateEpoch != _pickupUpdateEpoch) {
        return false;
      }
      editFeedback = 'Pickup updated';
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return true;
    } catch (error) {
      editFeedback = _staleEdit(error, _pickupMutation)
          ? rideJustChangedMessage
          : 'Couldn’t update pickup. Try again.';
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return false;
    } finally {
      _finishEdit(editToken);
    }
  }

  /// Adopts a route change that [RouteChangeController] already applied and
  /// saved, so the price, pickup, destination and stops stay in sync here.
  void adoptRouteChange(RideSnapshot updated) {
    if (_cancelled || _terminated || _disposed) return;
    _snapshot = updated;
    _catalogPrice = updated.price;
    final id = updated.rideId;
    if (id != null && !_assignmentPending && !_assigned) {
      unawaited(_loadNearby(id));
    }
    _onTick?.call(elapsedSeconds);
    _reportQa();
  }

  /// Raises the offer by [kr] whole units of the trip's [currency]
  /// (kronor, euros, dinars).
  Future<bool> confirmPriceIncrease(int kr) {
    if (kr <= 0) return Future.value(false);
    return confirmPriceIncreaseBy(Money.fromLegacyMajor(kr, currency));
  }

  /// Raises the offer by [increase], in the trip's [currency] (a raise in
  /// another currency is refused here, never converted).
  Future<bool> confirmPriceIncreaseBy(Money increase) async {
    if (!increase.isPositive || increase.currency != currency) return false;
    final snapshot = _snapshot;
    final id = snapshot?.rideId ?? ride.rideId;
    if (snapshot == null || id == null) return false;
    final catalog = _catalogPrice ?? snapshot.price;
    final next = Money(snapshot.fare.amountMinor + increase.amountMinor, currency)
        .major;
    if (next > maxOfferPrice ||
        (snapshot.maxOfferMinor == null &&
            !FareRules.allowsTotal(total: next, catalog: catalog))) {
      return false;
    }
    final editToken = _beginEdit();
    if (editToken == null) {
      editFeedback = _assigned || _assignmentPending
          ? 'Driver assigned before the offer change could be applied.'
          : 'Couldn’t update offer. Try again.';
      _onTick?.call(elapsedSeconds);
      return false;
    }
    editFeedback = null;
    _onTick?.call(elapsedSeconds);
    // D-012: send only the rider's intent — how much to raise the offer by.
    // The client-computed total is a preview for the button label, never a
    // value the server is asked to accept. The fare shown afterwards is the
    // one the server's response actually carries.
    final intent = jsonEncode({
      'rideId': id,
      'fromPrice': snapshot.price,
      'offerIncrease': increase.toJson(),
    });
    try {
      // R-O2: raised on the trip this search last saw.
      final version = _priceMutation.versionFor(
        intent,
        ride.projectionVersionOf(id),
      );
      final response = await api.patch(
        '/api/v1/rides/$id',
        // Contract v0.3.0: the raise as Money, not kronor.
        body: {
          'offerIncrease': increase.toJson(),
          'expectedVersion': ?version,
        },
        idempotencyKey: _priceMutation.keyFor(intent),
      );
      _priceMutation.succeeded(intent);
      ride.observeProjection(response);
      if (_editInvalid(editToken)) return false;
      _bumpDismissed = true;
      final serverPrice = _serverPrice(response);
      if (serverPrice == null) {
        // Accepted, but the response did not say what the fare now is.
        // Keep showing the last fare the server confirmed rather than
        // assuming the preview total is what happened.
        offerConfirmation = null;
        editFeedback =
            'Offer sent. Your fare will update once Movera confirms it.';
        AppLog.warning(
          'ride.offer.price_unconfirmed',
          extra: {'rideId': id, 'increase': increase.majorString},
        );
        _onTick?.call(elapsedSeconds);
        _reportQa();
        return true;
      }
      _priceUpdated = true;
      offerConfirmation =
          'Updated offer: ${formatMoney(Money.fromLegacyMajor(serverPrice, currency), whole: true)}';
      editFeedback = offerConfirmation;
      _snapshot = snapshot.copyWith(
        status: ride.status,
        price: serverPrice,
        savedAt: DateTime.now(),
        maxOfferMinor: _serverMaxOfferMinor(response),
      );
      await _store.save(_snapshot!);
      if (_editInvalid(editToken)) return false;
      AppLog.info(
        'ride.offer.updated',
        extra: {
          'rideId': id,
          'increase': increase.majorString,
          'serverPrice': serverPrice,
          if (serverPrice != next) 'previewPrice': next,
        },
      );
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return true;
    } catch (error) {
      editFeedback = _staleEdit(error, _priceMutation)
          ? rideJustChangedMessage
          : 'Couldn’t update offer. Try again.';
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return false;
    } finally {
      _finishEdit(editToken);
    }
  }

  /// R-O2: an edit refused as stale changed nothing; its key is dropped so
  /// the rider's next try is a new request on the trip as it is now. The
  /// screen reads the ride again.
  bool _staleEdit(Object error, MutationAttempt mutation) {
    if (error is! ApiError || !error.isVersionMismatch) return false;
    mutation.reset();
    ride.observeProjection(error.projection);
    final id = ownedRideId;
    if (id != null) {
      unawaited(
        _realtime.reconnectAndResync(id).catchError((Object resyncError) {
          AppLog.warning(
            'ride.edit.resync_failed',
            extra: {'rideId': id, 'error': resyncError.toString()},
          );
        }),
      );
    }
    return true;
  }

  /// The offer ceiling the server says the ride has, when it says.
  static int? _serverMaxOfferMinor(Map<String, dynamic> response) {
    final ride = response['ride'];
    final raw = ride is Map ? ride['maxOfferMinor'] : null;
    return raw is num && raw > 0 ? raw.round() : null;
  }

  /// The fare the server says the ride now has, from a PATCH response's
  /// `ride.price` (or a top-level `price`). Null when absent or unusable.
  double? _serverPrice(Map<String, dynamic> response) {
    final ride = response['ride'];
    final fare = Money.fromWire(ride is Map ? ride['fare'] : response['fare']);
    // A fare in another currency is not this trip's price.
    if (fare != null) {
      return fare.isPositive && fare.currency == currency ? fare.major : null;
    }
    final raw = ride is Map ? ride['price'] : response['price'];
    if (raw is! num) return null;
    final value = raw.toDouble();
    return value.isFinite && value > 0 ? value : null;
  }

  void dismissPriceBump() {
    if (_terminated) return;
    _bumpDismissed = true;
    _onTick?.call(elapsedSeconds);
    _reportQa();
  }

  void _completeAssigned() {
    if (_assigned || _cancelled || _terminated || _disposed) return;
    if (_editInFlight || _cancelInFlight) {
      // A cancel waiting on the server decides first: if it is confirmed
      // this match is dropped; if the server refuses because the driver
      // accepted, the match completes as soon as the answer arrives.
      _assignmentPending = true;
      return;
    }
    _assignmentPending = false;
    if (_cancelQueued) {
      // RC-03: a driver accepted before the queued cancel reached the
      // server. The rider is told and moved on; the stale request leaves
      // the outbox so it cannot cancel the matched ride later.
      _cancelQueued = false;
      final id = ownedRideId;
      if (id != null) unawaited(PendingCancelStore.remove(id));
      AppLog.info('ride.cancel.queued_overtaken_by_match', extra: {
        'rideId': id,
      });
      _lastRefusalStale = false;
      _onCancelRefused?.call();
    }
    _assigned = true;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    final snapshot = _snapshot;
    final matched = _onMatched;
    if (_cancelled || _terminated || _disposed) return;
    Analytics.driverFound(rideId: ride.rideId);
    if (_cancelled || _disposed) {
      if (!ride.status.isTerminal) {
        ride.localTransition(RideStatus.cancelledByRider);
      }
      unawaited(_store.clear());
      return;
    }
    if (_terminated) return;
    unawaited(_persistAssigned(snapshot, matched));
  }

  Future<void> _persistAssigned(
    RideSnapshot? snapshot,
    void Function()? matched,
  ) async {
    if (snapshot != null) {
      await _store.save(
        _ordered(snapshot).copyWith(
          status: ride.status.isMatched
              ? ride.status
              : RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          rideId: ride.rideId,
          driver: matchedDriver,
        ),
      );
    }
    if (_terminated) {
      await _store.clear();
      return;
    }
    if (_cancelled || _disposed) {
      if (!ride.status.isTerminal) {
        ride.localTransition(RideStatus.cancelledByRider);
      }
      await _store.clear();
      return;
    }
    _reportQa();
    matched?.call();
  }

  Future<void> _completeTerminal(RideStatus status) async {
    if (_terminated || _cancelled || _disposed || !status.isTerminal) return;
    _terminated = true;
    _assignmentPending = false;
    // The ride is over; this screen no longer owns a live search, so a new
    // request ("Try again") is not refused as a duplicate.
    if (identical(active, this)) active = null;
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _onMatched = null;
    _tick?.cancel();
    _tick = null;
    // Not awaited (as in _commitCancelled): the flags above already drop any
    // later event, and a broadcast cancel's future belongs to the root zone.
    unawaited(_sub?.cancel());
    _sub = null;
    final snapshot = _snapshot;
    if (snapshot != null &&
        (status == RideStatus.cancelledByDriver ||
            status == RideStatus.cancelledBySystem ||
            status == RideStatus.cancelledByAdmin ||
            status == RideStatus.tripFailed ||
            // RIDE-5: a search the server ended is kept in History too.
            status == RideStatus.noDriverFound ||
            status == RideStatus.bookingExpired)) {
      await _archiveTerminalRide(snapshot, status);
    }
    await _store.clear();
    _reportQa();
    if (_disposed) return;
    final callback = _onTerminal;
    if (callback != null) {
      callback(status);
    } else {
      RideNavigator.home(null, status: status);
    }
  }

  Future<void> _archiveTerminalRide(
    RideSnapshot snapshot,
    RideStatus status,
  ) async {
    final writer = _historyArchiveWriter ??
        (
          RideSnapshot candidate,
          RideStatus terminalStatus,
          String? cancellationReason,
        ) =>
            OnDemandRideHistoryStore.archive(
              candidate,
              terminalStatus: terminalStatus,
              cancellationReason: cancellationReason,
            );

    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        await writer(snapshot, status, null);
        return;
      } catch (error) {
        AppLog.warning(
          'ride.history.archive_failed',
          extra: {
            'rideId': snapshot.rideId,
            'status': status.name,
            'attempt': attempt,
            'error': error.toString(),
          },
        );
        if (attempt == 2) return;
      }
    }
  }

  /// Cancels the search, server first (CODE-3 / RIDE-4).
  ///
  /// The intent goes into the pending-cancel outbox with one idempotency key
  /// before the request is sent, then the server is asked (one in-session
  /// retry, same key). Only its answer commits the cancel locally:
  /// - confirmed (or 404, nothing left to cancel): cancelled, archived to
  ///   History and the snapshot cleared, so a reload lands on Home;
  /// - unreachable: the same local commit, with the outbox entry kept so the
  ///   next reconnect or launch retries it;
  /// - 409 "driver already accepted" (or 410/422): nothing is committed. The
  ///   search keeps listening and resyncs, so a match that raced the cancel
  ///   moves the rider to the matched screen.
  ///
  /// The optional reason is usually sent afterwards with [sendCancelReason].
  Future<SearchCancelResult> cancelSearch({String? reasonId}) async {
    if (_cancelled || _cancelInFlight || _terminated || _disposed || _assigned) {
      return SearchCancelResult.ignored;
    }
    _cancelInFlight = true;
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _tick?.cancel();
    _tick = null;
    _reportQa();
    final id = (_snapshot?.rideId ?? ride.rideId)?.trim();
    SearchCancelResult result;
    if (id == null || id.isEmpty) {
      AppLog.warning(
        'ride.cancel.local_only_no_ride_id',
        extra: {'status': ride.status.name},
      );
      result = SearchCancelResult.confirmed;
    } else {
      result = await _requestServerCancel(id, reasonId: reasonId);
    }
    if (result == SearchCancelResult.confirmed) {
      await _commitCancelled(reasonId: reasonId);
      return result;
    }
    if (result == SearchCancelResult.queued) {
      // RC-03: not committed. The ride stays live and this search keeps
      // listening until the server confirms the cancel or a match arrives.
      _cancelInFlight = false;
      _cancelQueued = true;
      _queuedReasonId = reasonId ?? _queuedReasonId;
      AppLog.info('ride.cancel.queued', extra: {'rideId': id});
      if (_disposed || _terminated) return result;
      if (_assignmentPending && !_editInFlight) {
        _completeAssigned();
      }
      _onTick?.call(elapsedSeconds);
      _reportQa();
      return result;
    }

    // Refused: the ride is not ours to cancel any more. Pick up where the
    // search was, let a match that arrived meanwhile through, and ask the
    // transport for the server's current state in case it did not.
    _cancelInFlight = false;
    AppLog.info(
      'ride.cancel.refused',
      extra: {'rideId': id, 'result': result.name},
    );
    if (_disposed || _terminated) return result;
    if (_assignmentPending && !_editInFlight) {
      _assignmentPending = false;
      _completeAssigned();
    } else if (!_assigned) {
      _startTick();
    }
    if (id != null && !_assigned && !_assignmentPending) {
      unawaited(
        _realtime.reconnectAndResync(id).catchError((Object error) {
          AppLog.warning(
            'ride.cancel.resync_failed',
            extra: {'rideId': id, 'error': error.toString()},
          );
        }),
      );
    }
    _onTick?.call(elapsedSeconds);
    _reportQa();
    return result;
  }

  Future<SearchCancelResult> _requestServerCancel(
    String id, {
    String? reasonId,
  }) async {
    // R-O2: the trip version this search last saw, kept with the entry so
    // a retry is the same request (same key, same body).
    final entry = await PendingCancelStore.enqueue(
      rideId: id,
      reasonId: reasonId,
      expectedVersion: ride.projectionVersionOf(id),
    );
    // One in-session retry, only for an unreachable server: a refusal is
    // final and is never sent again.
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final response = await api.post(
          '/api/v1/rides/$id/cancel',
          body: entry.body(reasonId),
          idempotencyKey: entry.idempotencyKey,
        );
        await PendingCancelStore.remove(id);
        ride.observeProjection(response);
        return SearchCancelResult.confirmed;
      } catch (error) {
        AppLog.warning(
          'ride.cancel.adapter_failed',
          extra: {'rideId': id, 'error': error.toString(), 'attempt': attempt},
        );
        if (isPermanentCancelFailure(error)) {
          // D-020: retrying can never succeed, so the entry leaves the outbox.
          await PendingCancelStore.remove(id);
          ride.observeProjection((error as ApiError).projection);
          // R-O3: already cancelled by the rider is what they asked for.
          if (alreadyCancelledByRider(error)) {
            return SearchCancelResult.confirmed;
          }
          final status = error.statusCode;
          if (status == 404) return SearchCancelResult.confirmed;
          if (error.isVersionMismatch) return SearchCancelResult.stale;
          return status == 409
              ? SearchCancelResult.driverAccepted
              : SearchCancelResult.rejected;
        }
      }
    }
    // Still unreachable: the outbox entry, with its key, stays for the
    // reconnect / next-launch flush.
    return SearchCancelResult.queued;
  }

  /// A restored search whose cancel is still in the outbox shows it as
  /// cancelling (RC-03) and tries to send it.
  Future<void> _adoptQueuedCancel(String? rideId) async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty) return;
    PendingCancel? queued;
    try {
      queued = await PendingCancelStore.find(id);
    } catch (_) {
      return;
    }
    if (queued == null ||
        queued.command != PendingCancelCommand.cancel ||
        ownedRideId != id ||
        _cancelled ||
        _cancelInFlight ||
        _terminated ||
        _disposed ||
        _assigned) {
      return;
    }
    _cancelQueued = true;
    _queuedReasonId = queued.reasonId;
    _tick?.cancel();
    _tick = null;
    _onTick?.call(elapsedSeconds);
    _reportQa();
    _flushQueuedCancel();
  }

  void _flushQueuedCancel() {
    unawaited(
      flushPendingCancels(api: api).catchError((Object error) {
        AppLog.warning(
          'ride.cancel.flush_failed',
          extra: {'rideId': ownedRideId, 'error': error.toString()},
        );
        return const <String, PendingCancelResult>{};
      }),
    );
  }

  void _onOutboxOutcome(PendingCancelOutcome outcome) {
    if (!_cancelQueued ||
        _cancelled ||
        _terminated ||
        _disposed ||
        outcome.rideId != ownedRideId) {
      return;
    }
    switch (outcome.result) {
      case PendingCancelResult.sent:
      case PendingCancelResult.gone:
        unawaited(_confirmQueuedCancel());
      case PendingCancelResult.refused:
      case PendingCancelResult.stale:
        // The server kept the ride (a driver accepted first), or the trip
        // moved on before the queued cancel could be sent (R-O2). Pick the
        // search back up; the match arrives on realtime.
        _cancelQueued = false;
        _lastRefusalStale = outcome.result == PendingCancelResult.stale;
        _onCancelRefused?.call();
        final id = ownedRideId;
        if (_assignmentPending && !_editInFlight) {
          _completeAssigned();
        } else if (!_assigned) {
          _startTick();
          if (id != null) {
            unawaited(
              _realtime.reconnectAndResync(id).catchError((Object error) {
                AppLog.warning(
                  'ride.cancel.resync_failed',
                  extra: {'rideId': id, 'error': error.toString()},
                );
              }),
            );
          }
        }
        _onTick?.call(elapsedSeconds);
        _reportQa();
    }
  }

  /// The server confirmed the queued cancel: commit it now and leave.
  Future<void> _confirmQueuedCancel() async {
    if (!_cancelQueued || _cancelled || _terminated || _disposed) return;
    _cancelQueued = false;
    await _commitCancelled(reasonId: _queuedReasonId);
    if (_disposed) return;
    final callback = _onTerminal;
    if (callback != null) {
      callback(RideStatus.cancelledByRider);
    } else {
      RideNavigator.home(null, status: RideStatus.cancelledByRider);
    }
  }

  Future<void> _commitCancelled({String? reasonId}) async {
    _cancelled = true;
    _cancelInFlight = false;
    _assignmentPending = false;
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _onMatched = null;
    _tick?.cancel();
    _tick = null;
    _sub?.cancel();
    _sub = null;
    Analytics.rideCancelled(rideId: ride.rideId);
    if (reasonId != null) {
      AppLog.info(
        'ride.cancelled',
        extra: {'reason': reasonId, 'rideId': ride.rideId},
      );
    }
    if (!ride.status.isTerminal) {
      ride.localTransition(RideStatus.cancelledByRider);
    }
    await OnDemandRideHistoryStore.archiveCancelledThenClear(
      snapshot: _snapshot,
      reasonId: reasonId,
    );
    _realtime.cancelRide();
    _reportQa();
  }

  /// Sends the rider's optional reason for a cancel that is already
  /// committed. Best effort: it updates the History record, rides along
  /// with a cancel still queued in the outbox, or is posted to the cancel
  /// endpoint again (idempotent for a cancelled ride). It never changes the
  /// ride's state.
  Future<void> sendCancelReason(String reasonId) async {
    if (!_cancelled) return;
    final snapshot = _snapshot;
    final id = (snapshot?.rideId ?? ride.rideId)?.trim();
    AppLog.info('ride.cancelled', extra: {'reason': reasonId, 'rideId': id});
    if (id == null || id.isEmpty) return;
    if (snapshot != null) {
      try {
        final writer = _historyArchiveWriter;
        if (writer != null) {
          await writer(snapshot, RideStatus.cancelledByRider, reasonId);
        } else {
          await OnDemandRideHistoryStore.archive(
            snapshot,
            terminalStatus: RideStatus.cancelledByRider,
            cancellationReason: reasonId,
          );
        }
      } catch (error) {
        AppLog.warning(
          'ride.history.cancel_reason_failed',
          extra: {'rideId': id, 'error': error.toString()},
        );
      }
    }
    if (await PendingCancelStore.attachReason(id, reasonId)) return;
    final intent = jsonEncode({'rideId': id, 'reasonId': reasonId});
    try {
      // A second cancel of a cancelled trip: quietly accepted (R-O3). It
      // still names the version the cancel left the trip at (R-O2).
      final version = ride.projectionVersionOf(id);
      await api.post(
        '/api/v1/rides/$id/cancel',
        body: {
          ...CancelReasonCodes.riderCancelBody(reasonId),
          'expectedVersion': ?version,
        },
        idempotencyKey: _reasonMutation.keyFor(intent),
      );
      _reasonMutation.succeeded(intent);
    } catch (error) {
      AppLog.warning(
        'ride.cancel.reason_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
    }
  }

  static Future<Map<String, PendingCancelResult>>? _flushInFlight;
  static StreamSubscription<RealtimeState>? _reconnectFlush;

  /// Retries any ride cancellations that were never acknowledged. Called at
  /// app start, after [AppScope] is composed, and again whenever the shared
  /// realtime connection comes back (D-020: previously cold start only).
  ///
  /// Each entry is retried with its own persisted idempotency key and its
  /// own command (`cancel` or `end-early`, RC-02). Entries the server
  /// permanently rejects leave the outbox rather than being retried forever;
  /// a refusal for a ride that is still live is reported as
  /// [PendingCancelResult.refused] (RC-03), never dropped silently. The
  /// result maps each ride the server answered to what it said; every
  /// answer is also reported on [PendingCancelStore.outcomes].
  static Future<Map<String, PendingCancelResult>> flushPendingCancels({
    ApiClient? api,
  }) {
    if (api == null) {
      watchReconnectForPendingCancels(AppScope.instance.realtime);
    }
    final inFlight = _flushInFlight;
    if (inFlight != null) return inFlight;
    final run = _flushPendingCancels(api ?? AppScope.instance.api);
    _flushInFlight = run;
    return run.whenComplete(() => _flushInFlight = null);
  }

  /// Flushes the outbox every time [connection] returns to connected after
  /// having been down. Installing it again replaces the previous watcher.
  static void watchReconnectForPendingCancels(
    RealtimeConnection connection, {
    ApiClient? api,
  }) {
    unawaited(_reconnectFlush?.cancel());
    var wasDown = connection.state != RealtimeState.connected;
    _reconnectFlush = connection.states.listen((state) {
      if (state == RealtimeState.connected) {
        if (wasDown) {
          wasDown = false;
          unawaited(flushPendingCancels(api: api ?? AppScope.instance.api));
        }
      } else if (state == RealtimeState.failed ||
          state == RealtimeState.disconnected ||
          state == RealtimeState.reconnecting) {
        wasDown = true;
      }
    });
  }

  @visibleForTesting
  static Future<void> debugStopReconnectFlush() async {
    await _reconnectFlush?.cancel();
    _reconnectFlush = null;
  }

  static Future<Map<String, PendingCancelResult>> _flushPendingCancels(
    ApiClient client,
  ) async {
    final results = <String, PendingCancelResult>{};
    final pending = await PendingCancelStore.all();
    if (pending.isEmpty) return results;
    for (var cancel in pending) {
      if (cancel.idempotencyKey == null) {
        // Entry from before D-020: mint its one key now and keep it.
        cancel = cancel.withKey(newIdempotencyKey('ride-cancel'));
        await PendingCancelStore.add(cancel);
      }
      // R-O2: read the trip again before replaying a command queued while
      // offline. The rider tapped on a screen that may be long out of date.
      final current = await _rereadForReplay(client, cancel);
      if (current == null) continue; // Still unreachable: kept for later.
      PendingCancelResult? result = current.result;
      if (result == null) {
        final version = current.version;
        if (version != null && version != cancel.expectedVersion) {
          // Still applies on a newer trip: sent for the version it is at now,
          // so it is not refused as stale for a change that does not matter.
          cancel = cancel.forVersion(version);
          await PendingCancelStore.add(cancel);
        }
        try {
          final response = await client.post(
            '/api/v1/rides/${cancel.rideId}/${cancel.command.pathSegment}',
            body: cancel.body(),
            idempotencyKey: cancel.idempotencyKey,
          );
          AppScope.instance.ride.observeProjection(response);
          result = PendingCancelResult.sent;
        } catch (error) {
          if (!isPermanentCancelFailure(error)) {
            AppLog.warning(
              'ride.cancel.flush_failed',
              extra: {'rideId': cancel.rideId, 'error': error.toString()},
            );
            continue;
          }
          result = await _refusalResult(client, cancel, error);
        }
      }
      await PendingCancelStore.remove(cancel.rideId);
      results[cancel.rideId] = result;
      PendingCancelStore.report(PendingCancelOutcome(
        rideId: cancel.rideId,
        command: cancel.command,
        result: result,
      ));
    }
    return results;
  }

  /// R-O2: the trip as it is now, before a queued command is replayed.
  /// Null when it cannot be read (offline): the entry waits. A [result]
  /// means the command is not sent at all: the trip is gone, already
  /// cancelled by the rider (R-O3: that is what they asked for), over, or
  /// at a stage where the command no longer applies (dropped as stale and
  /// the rider is told). Otherwise [version] is the version to send.
  static Future<({PendingCancelResult? result, int? version})?>
  _rereadForReplay(ApiClient client, PendingCancel cancel) async {
    Map<String, dynamic>? projection;
    try {
      projection = tripProjectionOf(
        await client.get('/api/v1/rides/${cancel.rideId}'),
      );
    } on ApiError catch (error) {
      if (error.statusCode == 404 || error.statusCode == 410) {
        AppLog.warning(
          'ride.cancel.flush_dropped_permanent',
          extra: {'rideId': cancel.rideId, 'error': error.toString()},
        );
        return (result: PendingCancelResult.gone, version: null);
      }
      AppLog.warning(
        'ride.cancel.flush_reread_failed',
        extra: {'rideId': cancel.rideId, 'error': error.toString()},
      );
      return null;
    } catch (error) {
      AppLog.warning(
        'ride.cancel.flush_reread_failed',
        extra: {'rideId': cancel.rideId, 'error': error.toString()},
      );
      return null;
    }
    AppScope.instance.ride.observeProjection(projection);
    final status = TripStatusWire.parse(projection?['status']);
    final rawVersion = projection?['version'];
    final version = rawVersion is num ? rawVersion.toInt() : null;
    // A projection without a readable status says nothing about the stage:
    // the command is replayed as it was queued.
    if (status == null) return (result: null, version: null);
    if (status == TripStatus.cancelledByRider) {
      return (result: PendingCancelResult.sent, version: version);
    }
    if (status.isTerminal) {
      return (result: PendingCancelResult.gone, version: version);
    }
    final command = switch (cancel.command) {
      PendingCancelCommand.cancel => 'cancel',
      PendingCancelCommand.endEarly => 'end_early',
    };
    final applies = TripStateMachine.apply(
          status,
          command,
          TripActor.rider,
          kind: TripKindWire.parse(projection?['kind']) ?? TripKind.live,
        ) !=
        null;
    if (!applies) {
      AppLog.warning(
        'ride.cancel.flush_dropped_stale',
        extra: {
          'rideId': cancel.rideId,
          'command': cancel.command.pathSegment,
          'status': status.wireName,
        },
      );
      return (result: PendingCancelResult.stale, version: version);
    }
    return (result: null, version: version);
  }

  /// A permanent refusal: 404/410 means the ride is gone. For 409/422 the
  /// ride is read again, since "a driver accepted first" and "already
  /// over" both refuse (RC-03). A ride that is still live is a refusal the
  /// rider must hear about; it is logged as an error, not dropped quietly.
  static Future<PendingCancelResult> _refusalResult(
    ApiClient client,
    PendingCancel cancel,
    Object error,
  ) async {
    final apiError = error as ApiError;
    AppScope.instance.ride.observeProjection(apiError.projection);
    // R-O3: the rider already cancelled it; nothing more to do.
    if (alreadyCancelledByRider(apiError)) return PendingCancelResult.sent;
    final status = apiError.statusCode;
    if (status == 404 || status == 410) {
      AppLog.warning(
        'ride.cancel.flush_dropped_permanent',
        extra: {'rideId': cancel.rideId, 'error': error.toString()},
      );
      return PendingCancelResult.gone;
    }
    RideStatus? current;
    try {
      final json = await client.get('/api/v1/rides/${cancel.rideId}');
      final projection = tripProjectionOf(json);
      if (projection != null) {
        current = RideStatusWire.fromProjection(projection);
      }
    } catch (readError) {
      AppLog.warning(
        'ride.cancel.flush_reread_failed',
        extra: {'rideId': cancel.rideId, 'error': readError.toString()},
      );
    }
    if (current == RideStatus.cancelledByRider) return PendingCancelResult.sent;
    if (current == null || !current.tripStatus.isTerminal) {
      // Live, or unknown: treated as live, so the ride stays on screen and
      // realtime shows how it really stands.
      AppLog.error(
        'ride.cancel.flush_refused_ride_live',
        extra: {
          'rideId': cancel.rideId,
          'command': cancel.command.pathSegment,
          'status': current?.name ?? 'unknown',
          'error': error.toString(),
        },
      );
      // R-O2: the trip changed between the re-read and the replay.
      return apiError.isVersionMismatch
          ? PendingCancelResult.stale
          : PendingCancelResult.refused;
    }
    AppLog.warning(
      'ride.cancel.flush_dropped_permanent',
      extra: {'rideId': cancel.rideId, 'error': error.toString()},
    );
    return PendingCancelResult.gone;
  }

  Future<void> resync() async {
    final id = _snapshot?.rideId;
    if (id == null || _cancelled || _terminated || _disposed) return;
    await _realtime.reconnectAndResync(id);
  }

  Map<String, dynamic> qaSnapshot() => {
    'elapsed': elapsedSeconds,
    'delayed': isDelayed,
    'bumpVisible': showPriceBump,
    'price': currentPrice,
    'priceUpdated': _priceUpdated,
    'headline': copy.headline,
    'rideId': _snapshot?.rideId ?? ride.rideId,
    'assigned': _assigned,
    'assignmentPending': _assignmentPending,
    'editInFlight': _editInFlight,
    'editFeedback': editFeedback,
    'terminated': _terminated,
    'cancelInFlight': _cancelInFlight,
    'cancelled': _cancelled,
    'cancelQueued': cancelQueued,
    'stillLooking': stillLooking,
    'status': ride.status.name,
    'offerConfirmation': offerConfirmation,
    'nearby': nearby.length,
    'pickupAddress': _snapshot?.pickupAddress,
    'pickupLat': _snapshot?.pickupLat,
    'pickupLng': _snapshot?.pickupLng,
  };

  void _reportQa() {
    reportSearchSnapshot(jsonEncode(qaSnapshot()));
  }

  void dispose() {
    _disposed = true;
    _assignmentPending = false;
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    if (identical(active, this)) active = null;
    _tick?.cancel();
    _sub?.cancel();
    unawaited(_outboxSub?.cancel());
    _outboxSub = null;
    if (!_assigned) _realtime.unsubscribe();
  }
}
