import 'dart:async';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_eta.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/contracts/on_trip.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

class DriverTrackingController {
  DriverTrackingController({
    RideRealtime? realtime,
    required this.pickupLat,
    required this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.persistRideSnapshot = true,
    RideSession? ride,
  }) : _realtime = realtime ?? AppScope.instance.rideRealtime,
       _ride = ride;

  final RideRealtime _realtime;
  final RideSession? _ride;
  final bool persistRideSnapshot;

  /// Route ends; updated when the rider changes the route mid-ride so the
  /// next fix measures the distance to the new place.
  double pickupLat;
  double pickupLng;
  double? destinationLat;
  double? destinationLng;
  StreamSubscription<RideRealtimeEvent>? _sub;
  Timer? _staleCheck;
  MatchedDriver? driver;
  DriverEta? eta;
  RideStatus status = RideStatus.driverAssigned;
  RideRealtimeSignal? lastSignal;
  String? signalMessage;

  /// N9: the trip's fare as the last accepted projection carried it (the
  /// server's final fare once the trip ends). Null until the wire says.
  Money? fare;

  /// Q12: when the driver accepted, from the projection's `acceptedAt`.
  /// Null when the server has not said (the caller falls back to when it
  /// first saw the driver).
  DateTime? acceptedAt;

  /// Q42: when the driver's waiting clock started: the projection's
  /// `waiting.arrivedAt`, else when this app first saw the driver waiting.
  DateTime? waitingSince;

  /// rider-r4-13: the projection's `waiting.freeUntil` and
  /// `waiting.noShowAt`, on the device clock; null when the server has not
  /// said (the zone's free-wait minutes from [waitingSince] apply then).
  DateTime? waitingFreeUntil;
  DateTime? waitingNoShowAt;

  /// Q13: the last accepted back-to-searching came from an admin reassign,
  /// so the rider is not told their driver cancelled.
  bool reassignedByAdmin = false;

  /// v0.18.7 (Q4): the server's road-route ETA as the last event carried
  /// it (every 30 s on the stream, on every projection). Null until the
  /// server has computed one, and while the driver waits at the pickup.
  TripEta? serverEta;

  /// v0.18.7: the rules this trip is charged by (`TripProjection.terms`):
  /// waiting, no-show, cancel and the pickup move limit, in the trip's
  /// currency. Null until a projection carried them.
  TripTerms? terms;

  /// v0.18.9 (G7 decision 1): the server's ride check of this trip.
  TripRideCheck? rideCheck;

  /// v0.18.9 (G7 decision 3): the newest route change and its answer.
  TripRouteChange? routeChange;

  /// A route change that was answered since the screen last looked: once
  /// per change and status, so the rider is told once.
  TripRouteChange? takeRouteChangeOutcome() {
    final change = routeChange;
    if (change == null || change.pending) return null;
    if (!_routeOutcomesSeen.add('${change.changeId}:${change.status}')) {
      return null;
    }
    return change;
  }

  final Set<String> _routeOutcomesSeen = {};

  /// Marks the outcomes already there when the screen opens as told.
  void markRouteChangeSeen(TripRouteChange change) =>
      _routeOutcomesSeen.add('${change.changeId}:${change.status}');

  /// v0.18.7 (Q5): the waiting cost so far while the driver waits
  /// (`waiting.chargedSoFar`); null when not waiting or not said.
  Money? waitingChargedSoFar;
  int? waitingChargedSecondsNow;

  /// v0.18.7 (Q2/Q6): the cancel fee and its kind once the trip was
  /// cancelled (the rider's own cancel, or a no-show), from the projection.
  RiderCancelOutcomeFee? cancellation;

  /// v0.18.8 (`arrivedWaiting.pin`): the trip needs the rider PIN before
  /// Start, the PIN itself (rider view only) and whether the driver has
  /// entered it. The PIN shows while [showPin] is true.
  bool pinRequired = false;
  String? pickupPin;
  bool pinVerified = false;

  /// The PIN card shows from accept until the driver entered the code.
  bool get showPin =>
      pinRequired &&
      !pinVerified &&
      pickupPin != null &&
      (status == RideStatus.driverAssigned ||
          status == RideStatus.driverArriving ||
          status == RideStatus.driverWaiting);

  /// v0.18.8 (`arrivedWaiting.alerts`, owner decision 6): each waiting
  /// alert kind shows once per arrival; the screen takes new ones here.
  List<String> takeNewAlerts() {
    final fresh = List<String>.of(_newAlerts);
    _newAlerts.clear();
    return fresh;
  }

  final Set<String> _alertsSeen = {};
  final List<String> _newAlerts = [];

  /// Kept on the device as `trip|arrivedAt|kind` so a message already shown
  /// does not come back when the app is reopened during the same wait.
  static const alertsSeenKey = 'movera_waiting_alerts_seen_v1';
  static const _alertsKept = 40;
  Set<String>? _persistedAlerts;
  final List<String> _alertsBeforeLoad = [];
  bool _alertsLoadStarted = false;

  void _loadPersistedAlerts() {
    if (_alertsLoadStarted) return;
    _alertsLoadStarted = true;
    unawaited(() async {
      Set<String> kept = {};
      try {
        final prefs = await PreferencesStore.load();
        kept = {...?prefs.getStringList(alertsSeenKey)};
      } catch (_) {
        kept = {};
      }
      _persistedAlerts = kept;
      final waiting = List<String>.of(_alertsBeforeLoad);
      _alertsBeforeLoad.clear();
      var fresh = false;
      for (final entry in waiting) {
        fresh = _offerAlert(entry) || fresh;
      }
      if (fresh) onChange?.call();
    }());
  }

  bool _offerAlert(String entry) {
    final kept = _persistedAlerts;
    if (kept == null) {
      if (!_alertsBeforeLoad.contains(entry)) _alertsBeforeLoad.add(entry);
      return false;
    }
    if (!_alertsSeen.add(entry) || kept.contains(entry)) return false;
    kept.add(entry);
    _newAlerts.add(entry.substring(entry.lastIndexOf('|') + 1));
    final list = kept.toList();
    final trimmed = list.length > _alertsKept
        ? list.sublist(list.length - _alertsKept)
        : list;
    unawaited(() async {
      try {
        await (await PreferencesStore.load()).setStringList(
          alertsSeenKey,
          trimmed,
        );
      } catch (_) {
        // Only a convenience: at worst the message shows once more.
      }
    }());
    return true;
  }

  void _takeAlerts(RideRealtimeEvent event) {
    if (event.status != RideStatus.driverWaiting) return;
    final arrival = event.waitingArrivedAt?.toUtc().toIso8601String() ?? '';
    for (final kind in event.waitingAlerts) {
      _offerAlert('${event.tripId}|$arrival|$kind');
    }
  }

  /// A new PIN (the trip changed driver) replaces the old one and is shown
  /// again until that driver enters it; `pinVerified` follows every
  /// projection (a `trip_projection` event after the driver's check).
  void _takePin(RideRealtimeEvent event) {
    pinRequired = event.pinRequired ?? pinRequired;
    final pin = event.pickupPin;
    if (pin != null && pin != pickupPin) {
      pickupPin = pin;
      pinVerified = false;
    }
    pinVerified = event.pinVerified ?? pinVerified;
    if (event.status.isTerminal) clearPin();
  }

  /// The trip is over (404 `pin_trip_over`, or an end status): no PIN.
  void clearPin() {
    pickupPin = null;
    pinRequired = false;
  }

  /// `GET /trips/{id}/pin` answered (same value as `pickupPin`).
  void setFetchedPin(String pin) {
    if (RegExp(r'^\d{4}$').hasMatch(pin)) pickupPin = pin;
  }

  /// v0.18.7 (item 4): a pickup the server moved (a `pickup_moved` event,
  /// or a projection whose pickup differs from the one this screen shows).
  /// Waiting takes it once to re-draw the route and say so.
  ({String address, double lat, double lng})? takeMovedPickup() {
    final moved = _movedPickup;
    _movedPickup = null;
    return moved;
  }

  ({String address, double lat, double lng})? _movedPickup;

  void _takePickup(RideRealtimeEvent event) {
    final pickup = event.pickup;
    if (pickup == null) return;
    final moved =
        GeoDistance.metersBetween(
          pickupLat,
          pickupLng,
          pickup.lat,
          pickup.lng,
        ) >
        1;
    if (!moved && event.kind != RealtimeKind.pickupMoved) return;
    pickupLat = pickup.lat;
    pickupLng = pickup.lng;
    _movedPickup = pickup;
  }

  /// v0.18.7: the server facts an event carries whatever the ordering
  /// verdict on its status: the ETA (no version change on the tick), the
  /// terms, the waiting cost, the cancellation and the pickup.
  void _takeServerFacts(RideRealtimeEvent event) {
    terms = event.terms ?? terms;
    rideCheck = event.rideCheck ?? rideCheck;
    routeChange = event.routeChange ?? routeChange;
    final eta = event.eta;
    if (eta != null) {
      final known = serverEta;
      if (known == null || !eta.at.isBefore(known.at)) serverEta = eta;
    }
    final cancellation = event.cancellation;
    if (cancellation != null) this.cancellation = cancellation;
    _takePickup(event);
    _takePin(event);
    _takeAlerts(event);
  }

  /// rider-u23: the driver who dropped the trip when the feed went straight
  /// to another driver (the polls never saw the `searching` between).
  /// Waiting takes it once to say so and to forget the old arrival.
  MatchedDriver? takeReplacedDriver() {
    final replaced = _replacedDriver;
    _replacedDriver = null;
    return replaced;
  }

  MatchedDriver? _replacedDriver;
  RideStatus? _lastPersistedStatus;
  int? _lastVersion;
  DateTime? _lastServerTime;
  void Function()? onChange;

  /// R-O1: how far the driver has driven with the rider on board, in
  /// metres: the route progress summed from the driver's fixes since the
  /// first one after boarding. Contract v0.3.0 has no driven distance on
  /// the projection, so this is what the ended-early receipt shows. In
  /// memory: a reload mid-trip counts from the next fix again.
  int get drivenMeters => _drivenMeters.round();
  double _drivenMeters = 0;
  double? _drivenFromLat;
  double? _drivenFromLng;

  static const _onBoard = {
    RideStatus.tripStarted,
    RideStatus.tripInProgress,
    RideStatus.approachingDropoff,
  };

  void _trackDriven(double lat, double lng) {
    if (!_onBoard.contains(status)) return;
    final fromLat = _drivenFromLat;
    final fromLng = _drivenFromLng;
    if (fromLat != null && fromLng != null) {
      _drivenMeters += GeoDistance.metersBetween(fromLat, fromLng, lat, lng);
    }
    _drivenFromLat = lat;
    _drivenFromLng = lng;
  }

  /// Re-evaluates staleness on a timer, independent of new fixes arriving.
  /// Without this, a marker whose updates simply stopped (a dropped
  /// connection, a crashed driver client) never registers as stale, because
  /// [DriverEta.fromFix] — the only other place staleness is computed — only
  /// runs when an event actually arrives.
  static const _staleCheckInterval = Duration(seconds: 5);

  /// rider-r4-13: `acceptedAt` and `waiting.arrivedAt` are server stamps;
  /// the waiting-fee clock and the cancel-fee preview measure from them
  /// with the device clock, so they are moved onto it (a phone 90 s fast
  /// would otherwise show the fee 90 s early).
  static DateTime? _onDevice(DateTime? server) =>
      server == null ? null : ServerClock.toDevice(server);

  void _takeWaitingDeadlines(RideRealtimeEvent event) {
    waitingFreeUntil = _onDevice(event.waitingFreeUntil);
    waitingNoShowAt = _onDevice(event.waitingNoShowAt);
  }

  void _clearWaitingDeadlines() {
    waitingFreeUntil = null;
    waitingNoShowAt = null;
    // A new arrival (another driver) may send its alerts again.
    _alertsSeen.clear();
    _newAlerts.clear();
  }

  void start({
    required String rideId,
    MatchedDriver? initial,
    RideStatus? initialStatus,
    void Function()? onChange,
  }) {
    driver = initial;
    // RIDE-7: a restored ride resumes from its own stage (for example in
    // trip), not from the "driver assigned" default.
    if (initialStatus != null &&
        (initialStatus.isMatched || initialStatus.isCompletedSurface)) {
      status = initialStatus;
    }
    // rider-u45: a restored wait has a clock from the start; the server's
    // own stamp replaces it when a projection carries one. Without this
    // the screen fell back to "now" on every rebuild.
    if (status == RideStatus.driverWaiting) waitingSince ??= DateTime.now();
    this.onChange = onChange;
    _loadPersistedAlerts();
    // rider-26: a restored matched ride tells the server feed what the
    // rider last saw, so a first poll that says `searching` is read as the
    // driver drop it is (and Waiting goes back to the search).
    final realtime = _realtime;
    if (realtime is ApiRideRealtime && status.isMatched) {
      realtime.primeShown(rideId: rideId, status: status, driverId: driver?.id);
    }
    // A fresh subscription is a fresh feed; only its own errors degrade it.
    connectionDegraded = false;
    _sub?.cancel();
    _staleCheck?.cancel();
    _sub = _realtime
        .subscribe(rideId)
        .listen(
          (event) {
            // A location fix is independently useful even when the status it
            // arrived with is rejected as stale by backendReconcile: dropping the
            // whole event discarded a possibly-newer coordinate along with a
            // status the app had already superseded. Only skip the status/signal
            // side when the event is rejected; the position always applies if it
            // is not itself older than what is already tracked.
            final eventVersion = event.version ?? event.sequence;
            final accepted =
                !persistRideSnapshot ||
                (_ride ?? AppScope.instance.ride).backendReconcile(
                  event.status,
                  id: event.tripId,
                  version: eventVersion,
                  updatedAt: event.serverTime ?? event.occurredAt,
                );
            final statusChanged = accepted && event.status != status;
            _takeServerFacts(event);
            if (accepted) {
              status = event.status;
              lastSignal = event.signal;
              signalMessage = event.message;
              reassignedByAdmin = event.isAdminReassign;
              _lastVersion = eventVersion;
              _lastServerTime = event.serverTime ?? _lastServerTime;
              if (event.status.isSearching ||
                  event.status == RideStatus.cancelledByDriver) {
                // Back in dispatch: the next accept starts new clocks.
                acceptedAt = null;
                waitingSince = null;
                _clearWaitingDeadlines();
              } else if (event.kind == RealtimeKind.driverCancelled &&
                  event.status.isMatched) {
                // rider-u23: another driver already took the dropped trip; the
                // new accept starts new clocks too.
                _replacedDriver = driver;
                acceptedAt = null;
                waitingSince = null;
                _clearWaitingDeadlines();
              }
              fare = event.fare ?? fare;
              // Q5: the waiting cost grows while the driver waits; it is
              // over (and in the fare) once the rider is on board.
              if (event.status == RideStatus.driverWaiting) {
                waitingChargedSoFar =
                    event.waitingChargedSoFar ?? waitingChargedSoFar;
                waitingChargedSecondsNow =
                    event.waitingChargedSecondsNow ?? waitingChargedSecondsNow;
              } else {
                waitingChargedSoFar = null;
                waitingChargedSecondsNow = null;
              }
              // The car is there: no ETA while arrived (Q4).
              if (event.status == RideStatus.driverWaiting) serverEta = null;
              acceptedAt = _onDevice(event.acceptedAt) ?? acceptedAt;
              if (event.waitingArrivedAt != null) {
                waitingSince = _onDevice(event.waitingArrivedAt);
                _takeWaitingDeadlines(event);
              } else if (event.status == RideStatus.driverWaiting) {
                waitingSince ??= DateTime.now();
              }
            } else if (_carriesCurrentClocks(event, eventVersion)) {
              // rider-u45: the projection's `acceptedAt` and `waiting.arrivedAt`
              // are server facts about this trip whatever the ordering verdict
              // on its status. After a reload the first projection repeats the
              // version the restore seeded and is rejected as a duplicate;
              // dropping its stamps restarted the waiting clock and the
              // free-cancel preview on the device clock.
              acceptedAt = _onDevice(event.acceptedAt) ?? acceptedAt;
              if (event.waitingArrivedAt != null) {
                waitingSince = _onDevice(event.waitingArrivedAt);
                _takeWaitingDeadlines(event);
              }
            }
            if (event.driver != null) driver = event.driver;
            final incomingLocationAt = event.locationAt ?? event.at;
            final currentLocationAt = eta?.locationAt;
            final isNewerFix =
                currentLocationAt == null ||
                !incomingLocationAt.isBefore(currentLocationAt);
            // v0.18.7: the server ETA (road route, every 30 s) is what
            // both apps show; its tick keeps the marker fresh while a
            // parked driver's phone sends few fixes.
            final routed = status == RideStatus.driverWaiting
                ? null
                : serverEta;
            final routedAt = routed == null
                ? null
                : _onDevice(routed.at) ?? routed.at;
            if (event.latitude != null &&
                event.longitude != null &&
                isNewerFix) {
              _trackDriven(event.latitude!, event.longitude!);
              eta = DriverEta.fromFix(
                latitude: event.latitude!,
                longitude: event.longitude!,
                pickupLat: pickupLat,
                pickupLng: pickupLng,
                destinationLat: destinationLat,
                destinationLng: destinationLng,
                locationAt: incomingLocationAt,
                etaSeconds: event.etaSeconds,
                status: status,
                server: routed,
                serverEtaAt: routedAt,
              );
            } else if (eta != null && eta!.locationAt != null) {
              eta = DriverEta.fromFix(
                latitude: eta!.latitude ?? pickupLat,
                longitude: eta!.longitude ?? pickupLng,
                pickupLat: pickupLat,
                pickupLng: pickupLng,
                destinationLat: destinationLat,
                destinationLng: destinationLng,
                locationAt: eta!.locationAt!,
                etaSeconds: event.etaSeconds ?? eta!.seconds,
                status: status,
                server: routed,
                serverEtaAt: routedAt,
              );
            }
            // Also persist an accepted event that confirms the current stage
            // when that stage is not stored yet (start never stores a stage it
            // could not prove, RIDE-7).
            if (statusChanged || (accepted && _lastPersistedStatus != status)) {
              unawaited(_persistLiveStatus());
            }
            this.onChange?.call();
          },
          onError: (Object error) {
            connectionDegraded = true;
            this.onChange?.call();
          },
          onDone: () {
            connectionDegraded = true;
            this.onChange?.call();
          },
        );
    unawaited(_persistLiveStatus());
    _staleCheck = Timer.periodic(_staleCheckInterval, (_) {
      final current = eta;
      if (current == null) return;
      final refreshed = current.withStalenessCheckedAt(DateTime.now());
      if (identical(refreshed, current)) return;
      eta = refreshed;
      this.onChange?.call();
    });
  }

  /// Whether a rejected [event] is still current enough for its clock
  /// stamps to apply: not older than the last accepted version, and not a
  /// return to dispatch (which starts new clocks when it is accepted).
  bool _carriesCurrentClocks(RideRealtimeEvent event, int eventVersion) {
    if (event.status.isSearching ||
        event.status == RideStatus.cancelledByDriver) {
      return false;
    }
    final last = _lastVersion;
    return last == null || eventVersion >= last;
  }

  /// Set when the realtime stream itself errors or closes (see M-05). Waiting
  /// renders it as a "live updates paused" banner with a Retry (D-015), so a
  /// dead feed no longer looks like a stationary driver.
  bool connectionDegraded = false;

  Future<void> _persistLiveStatus() async {
    if (!persistRideSnapshot || status.isTerminal) return;
    if (_lastPersistedStatus == status) return;
    final stored = await RideSnapshotStore.read();
    if (stored == null) return;
    // RIDE-7: never move the stored ride backwards. A later stage stored
    // with the same or a newer server version stays; only a newer version
    // (for example a fresh match after a driver drop) may replace it.
    if (_wouldRegress(stored)) return;
    _lastPersistedStatus = status;
    await RideSnapshotStore.save(
      stored.copyWith(
        status: status,
        savedAt: DateTime.now(),
        driver: driver ?? stored.driver,
        version: _lastVersion,
        serverUpdatedAt: _lastServerTime?.toUtc(),
      ),
    );
  }

  bool _wouldRegress(RideSnapshot stored) {
    if (stored.status.isTerminal || stored.status.index <= status.index) {
      return false;
    }
    final incoming = _lastVersion;
    final current = stored.version;
    if (incoming == null) return true;
    return current != null && incoming <= current;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _staleCheck?.cancel();
    _staleCheck = null;
  }
}
