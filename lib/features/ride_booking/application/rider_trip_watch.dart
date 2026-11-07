import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
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
class RiderTripWatch {
  RiderTripWatch({
    bool Function()? showsHome,
    Future<void> Function()? adopt,
    Future<bool> Function()? bookedOnTheWay,
    this.pollEvery = const Duration(seconds: 8),
  }) : _showsHome = showsHome ?? _defaultShowsHome,
       _adopt = adopt ?? _defaultAdopt,
       _bookedOnTheWay = bookedOnTheWay ?? _defaultBookedOnTheWay;

  static RiderTripWatch instance = RiderTripWatch();

  /// contract.json#bookedRideSeen.pollSeconds.
  final Duration pollEvery;

  final bool Function() _showsHome;
  final Future<void> Function() _adopt;
  final Future<bool> Function() _bookedOnTheWay;

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
    await RideRestoreCoordinator.instance.resumeIfNeeded();
  }

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
    if (event['kind'] == 'rider_trip_changed') unawaited(check());
  }

  /// The app is in front: poll until [stop].
  void start() {
    _poll ??= Timer.periodic(pollEvery, (_) => unawaited(check()));
  }

  /// The app went to the background.
  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  bool get polling => _poll != null;

  /// Home: read the server's active trip and open it. A ride on screen:
  /// refresh the booked-driver banner.
  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      if (_showsHome()) {
        bookedDriverOnTheWay.value = false;
        await _adopt();
      } else {
        bookedDriverOnTheWay.value = await _bookedOnTheWay();
      }
    } catch (error) {
      AppLog.warning(
        'ride.trip_watch.failed',
        extra: {'error': error.runtimeType.toString()},
      );
    } finally {
      _checking = false;
    }
  }
}
