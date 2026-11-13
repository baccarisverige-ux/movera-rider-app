import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';

/// v0.18.32 fix job 2 + P21 / B-n (contract.json#bookedRideSeen).
///
/// * A trip made elsewhere (admin, API, another phone) or a booked ride
///   whose driver starts driving reaches the rider's Home at once:
///   `rider_trip_changed` on `/rider/config/stream`, and a poll of
///   `GET /rider/trips/active` every [pollEvery] while Home shows no trip
///   and the app is in front (the stream may be down).
/// * Owner Q1 "Live ride + banner": while a live ride is on screen,
///   [bookedDriverOnTheWay] says a booked ride's driver is heading to the
///   rider (the live ride stays on screen).
/// * v0.18.83 (`bookedRideSeen.pollBackoff`, owner 2026-11-13 "32 s"):
///   after failed reads the poll waits 16 s, then 32 s (the cap), never
///   less than Retry-After; the first answer brings back [pollEvery]. A
///   hint, a stream reconnect and a resume still read at once.
class RiderTripWatch {
  RiderTripWatch({
    bool Function()? showsHome,
    Future<void> Function()? adopt,
    Future<bool> Function()? bookedOnTheWay,
    Future<void> Function()? refreshBooked,
    bool Function()? hasBooked,
    this.pollEvery = const Duration(seconds: 8),
    this.maxBackoff = const Duration(seconds: 32),
  }) : _showsHome = showsHome ?? _defaultShowsHome,
       _adopt = adopt ?? _defaultAdopt,
       _bookedOnTheWay = bookedOnTheWay ?? _defaultBookedOnTheWay,
       _refreshBooked = refreshBooked ?? _defaultRefreshBooked,
       _hasBooked = hasBooked ?? _defaultHasBooked;

  static RiderTripWatch instance = RiderTripWatch();

  /// contract.json#bookedRideSeen.pollSeconds.
  final Duration pollEvery;

  /// contract.json#bookedRideSeen.pollBackoff.maxSeconds (32): the longest
  /// wait between two failed reads (unless Retry-After says longer).
  /// `GET /rider/trips/active` is never shed, so before this every Home
  /// held a slot in the busy pool every 8 s.
  final Duration maxBackoff;

  /// Failed reads in a row.
  int _failures = 0;

  /// Poll ticks still to skip before the next read.
  int _skipTicks = 0;

  final bool Function() _showsHome;
  final Future<void> Function() _adopt;
  final Future<bool> Function() _bookedOnTheWay;

  /// SUP3-R1: reads the booked rides (Upcoming, the Home chrono) again.
  final Future<void> Function() _refreshBooked;

  /// R09 N5: whether the rider has a booked ride (the Upcoming list this
  /// app already holds). Without one the banner check is not sent;
  /// `rider_trip_changed` and resume still read the list again.
  final bool Function() _hasBooked;

  /// Owner Q1: the banner "Your booked driver is on the way".
  final ValueNotifier<bool> bookedDriverOnTheWay = ValueNotifier(false);

  Timer? _poll;
  bool _checking = false;

  static const bookedOnTheWayPath =
      '/api/v1/rider/trips?kind=scheduled&status=driver_to_pickup&status=arrived';

  /// Owner 2026-11-07: `showing` stays `home` while Finding / Waiting / the
  /// trip / the receipt are pushed over Home, so a pushed ride screen counts
  /// as "not Home" too.
  static bool _defaultShowsHome() =>
      RideRestoreCoordinator.instance.showing == RestoredSurface.home &&
      !RideRestoreCoordinator.rideStageOnScreen();

  static Future<void> _defaultAdopt() async {
    final coordinator = RideRestoreCoordinator.instance;
    // A resume that does not ask the server (a live ride is held here)
    // leaves no failure of an earlier read behind.
    coordinator.lastActiveTripReadFailure = null;
    await coordinator.resumeIfNeeded();
    // The lookup keeps Home as it is on a failed read (it returns null);
    // the poll still needs to know, to back off (with its Retry-After).
    final failure = coordinator.lastActiveTripReadFailure;
    if (failure != null) throw failure;
  }

  static Future<void> _defaultRefreshBooked() =>
      AppScope.instance.reservations.refresh();

  static bool _defaultHasBooked() =>
      AppScope.instance.reservations.upcoming().isNotEmpty;

  static Future<bool> _defaultBookedOnTheWay() async {
    final scope = AppScope.instance;
    if (!scope.api.contractWire) return false;
    final body = await scope.api.get(bookedOnTheWayPath);
    final items = body['items'];
    if (items is! List) return false;
    final shown = scope.ride.rideId?.trim();
    return items.any(
      (item) =>
          item is Map && item['tripId'] != null && item['tripId'] != shown,
    );
  }

  /// A server-sent event of `/rider/config/stream`.
  void onConfigEvent(Map<String, Object?> event) {
    if (event['kind'] != 'rider_trip_changed') return;
    // A booked ride changed: Upcoming and the chrono read it again, also
    // while a ride is on screen.
    unawaited(_refreshList());
    // A real hint is read at once, even during a backoff pause.
    unawaited(check());
  }

  /// E15: `/rider/config/stream` connected again. Hints sent while it was
  /// down are lost (no catch-up event), so the booked rides and the active
  /// trip are read again.
  void onStreamReconnected() {
    unawaited(_refreshList());
    unawaited(check());
  }

  /// The app is in front (start, resume): poll until [stop]. Coming to the
  /// front also reads the booked rides again.
  void start() {
    if (_poll != null) return;
    // Back in front: the resume reads at once (app_lifecycle), so the
    // next tick reads too instead of waiting out an old pause.
    _skipTicks = 0;
    _poll = Timer.periodic(pollEvery, (_) {
      if (_skipTicks > 0) {
        _skipTicks--;
        return;
      }
      unawaited(check());
    });
    unawaited(_refreshList());
  }

  Future<void> _refreshList() async {
    try {
      await _refreshBooked();
    } catch (error) {
      AppLog.warning(
        'ride.trip_watch.booked_refresh_failed',
        extra: {'error': error.runtimeType.toString()},
      );
    }
  }

  /// The app went to the background.
  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  bool get polling => _poll != null;

  /// Poll ticks to skip after the [_failures]-th failed read: the wait is
  /// 16 s, then 32 s and stays there ([maxBackoff]), never shorter than
  /// the server's Retry-After.
  int _ticksToSkip(Object error) {
    final every = pollEvery.inMilliseconds;
    final cap = maxBackoff.inMilliseconds;
    var wait = every << _failures.clamp(0, 16);
    if (wait > cap) wait = cap;
    final retryAfter = error is ApiError ? error.retryAfter : null;
    if (retryAfter != null && retryAfter.inMilliseconds > wait) {
      wait = retryAfter.inMilliseconds;
    }
    // A read every [pollEvery]: the next one comes after ceil(wait / every)
    // ticks, so the ones before it are skipped.
    return ((wait + every - 1) ~/ every) - 1;
  }

  /// Home: read the server's active trip and open it. A ride on screen:
  /// refresh the booked-driver banner.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      if (_showsHome()) {
        bookedDriverOnTheWay.value = false;
        // Rule 33 (load): the 8 s check reads only the active trip
        // (contract pollFallback); the booked list is read again on
        // rider_trip_changed, on resume, after sign-in and when Home or the
        // chrono opens.
        await _adopt();
      } else if (!_hasBooked()) {
        // R09 N5: no booked ride, so no booked driver can be on the way.
        bookedDriverOnTheWay.value = false;
      } else {
        bookedDriverOnTheWay.value = await _bookedOnTheWay();
      }
      _failures = 0;
      _skipTicks = 0;
    } catch (error) {
      _failures += 1;
      _skipTicks = _ticksToSkip(error);
      AppLog.warning(
        'ride.trip_watch.failed',
        extra: {'error': error.runtimeType.toString()},
      );
    } finally {
      _checking = false;
    }
  }
}
