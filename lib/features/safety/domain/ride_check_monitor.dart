import 'dart:math' as math;

import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';

/// One live position of the car during the trip.
class RideCheckSample {
  const RideCheckSample({
    required this.point,
    required this.at,
    this.etaSeconds,
    this.inTraffic = false,
  });

  final GeoPoint point;

  /// When the fix was taken (not when it arrived).
  final DateTime at;

  /// Seconds left to the drop-off, when the server says.
  final int? etaSeconds;

  /// Slow traffic or a queue the car is in; a stop in traffic is not a
  /// long stop.
  final bool inTraffic;
}

/// The trip as booked: where Ride check expects the car to go and stop.
class RideCheckPlan {
  const RideCheckPlan({
    required this.pickup,
    required this.destination,
    this.stops = const [],
    this.destinationLabel,
  });

  final GeoPoint pickup;
  final GeoPoint destination;
  final List<GeoPoint> stops;
  final String? destinationLabel;

  List<GeoPoint> get plannedStops => [pickup, ...stops, destination];
}

class RideCheckDetection {
  const RideCheckDetection(this.trigger, this.reason);

  final RideCheckTrigger trigger;
  final RideCheckReason reason;
}

/// Watches one trip and says when a Ride check trigger is met (RC1). Each
/// trigger fires at most once per trip. Pure: positions and times come in,
/// nothing is read from the clock.
class RideCheckMonitor {
  RideCheckMonitor({required this.settings, required RideCheckPlan plan})
    : _plan = plan;

  /// A car that moved less than this is standing still.
  static const stillRadiusMeters = 25.0;

  /// A stop this close to the pickup, a stop on the route or the drop-off is
  /// a planned stop, not a long stop.
  static const plannedStopRadiusMeters = 150.0;

  /// Faster than this between two fixes is a GPS jump, not driving.
  static const plausibleSpeedMps = 60.0;

  /// Possible crash: from at least 30 km/h to standing still, braking at
  /// least this hard.
  static const crashFromSpeedMps = 8.3;
  static const crashToSpeedMps = 1.5;
  static const crashDecelerationMps2 = 4.0;

  /// "Longer than expected" also needs the trip to run this much over, so a
  /// short hop that takes two extra minutes is not flagged.
  static const minimumExtraDelay = Duration(minutes: 3);

  /// The trip's time budget is taken from the ETAs of its first minute.
  /// The first sample can still carry the ETA to the pickup, so a later
  /// one in that minute can raise it (rider-r3-3).
  static const budgetWindow = Duration(minutes: 1);

  RideCheckTriggerSettings settings;
  RideCheckPlan _plan;
  RideCheckPlan get plan => _plan;

  List<GeoPoint>? _route;
  final Set<RideCheckTrigger> _fired = {};
  RideCheckSample? _previous;
  double? _previousSpeed;
  Duration? _previousGap;
  GeoPoint? _stillAt;
  DateTime? _stillSince;
  DateTime? _tripStartedAt;
  int? _expectedSeconds;

  bool hasFired(RideCheckTrigger trigger) => _fired.contains(trigger);

  /// The road route the trip is expected to follow. Off-route distance is
  /// only measured against a real road route, never a straight line.
  void setPlannedRoute(List<GeoPoint> points, {bool replace = false}) {
    if (points.length < 2) return;
    if (_route != null && !replace) return;
    _route = List.unmodifiable(points);
  }

  /// The rider changed the route: new stops and drop-off, and the time and
  /// route expectations start again from here.
  void replan(RideCheckPlan plan) {
    _plan = plan;
    _route = null;
    _tripStartedAt = null;
    _expectedSeconds = null;
  }

  RideCheckDetection? addSample(RideCheckSample sample) {
    final previous = _previous;
    if (previous != null && !sample.at.isAfter(previous.at)) return null;
    // rider-r3-4: a fix faster than a car can go from the last one is a
    // GPS jump. It is dropped whole (no stop-clock reset, no off-route
    // hit). After two dropped in a row the kept fix is taken to be the odd
    // one, so the next fix stands.
    if (previous != null && _isJump(previous, sample) && _jumps < 2) {
      _jumps++;
      return null;
    }
    _jumps = 0;
    _previous = sample;
    _tripStartedAt ??= sample.at;
    _budget(sample);

    double? speed;
    Duration? gap;
    if (previous != null) {
      gap = sample.at.difference(previous.at);
      final seconds = gap.inMilliseconds / 1000;
      if (seconds >= 0.5 && seconds <= 10) {
        final candidate = _meters(previous.point, sample.point) / seconds;
        if (candidate <= plausibleSpeedMps) speed = candidate;
      }
    }

    final detection =
        _crash(speed, gap) ??
        _longStop(sample) ??
        _offRoute(sample) ??
        _tooLong(sample);
    _previousSpeed = speed;
    _previousGap = gap;
    return detection;
  }

  /// The driver finished the trip at [end]: more than admin's
  /// `finishFarFromDropoffKm` from the drop-off is a Ride check.
  RideCheckDetection? tripEnded(GeoPoint end) {
    if (!_canFire(RideCheckTrigger.droppedFar)) return null;
    final meters = _meters(end, _plan.destination);
    if (!settings.finishedFarFromDropoff(meters)) return null;
    return _fire(
      RideCheckTrigger.droppedFar,
      RideCheckReason(
        distanceMeters: meters,
        destinationLabel: _plan.destinationLabel,
      ),
    );
  }

  RideCheckDetection? _crash(double? speed, Duration? gap) {
    if (!_canFire(RideCheckTrigger.possibleCrash)) return null;
    final before = _previousSpeed;
    final beforeGap = _previousGap;
    if (speed == null || before == null || gap == null || beforeGap == null) {
      return null;
    }
    if (before < crashFromSpeedMps || speed > crashToSpeedMps) return null;
    // The two speeds are averages over their gaps; their midpoints are this
    // far apart.
    final seconds = (gap.inMilliseconds + beforeGap.inMilliseconds) / 2000;
    if (seconds <= 0) return null;
    if ((before - speed) / seconds < crashDecelerationMps2) return null;
    return _fire(RideCheckTrigger.possibleCrash, const RideCheckReason());
  }

  RideCheckDetection? _longStop(RideCheckSample sample) {
    final anchor = _stillAt;
    if (anchor == null ||
        sample.inTraffic ||
        _meters(anchor, sample.point) > stillRadiusMeters) {
      _stillAt = sample.point;
      _stillSince = sample.at;
      return null;
    }
    return _stoppedFor(anchor, sample.at.difference(_stillSince!));
  }

  /// rider-u56: the app's own live feed was down and is back at [now].
  /// The car was not watched meanwhile, so the stop clock starts again
  /// here instead of counting the outage as a stop.
  void feedResumed(DateTime now) {
    if (_stillSince == null) return;
    if (now.isAfter(_stillSince!)) _stillSince = now;
  }

  /// No new position has come in (a driver app that stays quiet while the
  /// car stands still): at [now] the car is still where it was last seen,
  /// so a stop longer than `longStopMinutes` opens Ride check even without
  /// another fix.
  RideCheckDetection? checkStill(DateTime now) {
    final last = _previous;
    final anchor = _stillAt;
    final since = _stillSince;
    if (last == null || anchor == null || since == null || last.inTraffic) {
      return null;
    }
    if (!now.isAfter(last.at)) return null;
    return _stoppedFor(anchor, now.difference(since));
  }

  RideCheckDetection? _stoppedFor(GeoPoint anchor, Duration still) {
    if (!_canFire(RideCheckTrigger.longStop)) return null;
    if (!settings.isLongStop(still)) return null;
    final planned = _plan.plannedStops.any(
      (stop) => _meters(stop, anchor) <= plannedStopRadiusMeters,
    );
    if (planned) return null;
    return _fire(
      RideCheckTrigger.longStop,
      RideCheckReason(stoppedMinutes: still.inMinutes),
    );
  }

  RideCheckDetection? _offRoute(RideCheckSample sample) {
    final route = _route;
    if (route == null || !_canFire(RideCheckTrigger.offRoute)) return null;
    final off = distanceToPolyline(sample.point, route);
    if (off <= settings.offRouteKm * 1000) return null;
    return _fire(
      RideCheckTrigger.offRoute,
      RideCheckReason(distanceMeters: off),
    );
  }

  RideCheckDetection? _tooLong(RideCheckSample sample) {
    if (!_canFire(RideCheckTrigger.offRoute)) return null;
    final started = _tripStartedAt;
    final expected = _expectedSeconds ?? _straightLineSeconds();
    if (started == null || expected <= 0) return null;
    final elapsed = sample.at.difference(started);
    final limit = expected * (1 + settings.longerThanExpectedPercent / 100);
    if (elapsed.inSeconds < limit) return null;
    if (elapsed - Duration(seconds: expected) < minimumExtraDelay) return null;
    final percent = ((elapsed.inSeconds / expected - 1) * 100).round();
    return _fire(
      RideCheckTrigger.offRoute,
      RideCheckReason(longerPercent: percent),
    );
  }

  /// rider-r3-3: a missing or non-positive ETA is unknown (the straight
  /// line stands in), never a budget of 0.
  void _budget(RideCheckSample sample) {
    final eta = sample.etaSeconds;
    final started = _tripStartedAt;
    if (eta == null || eta <= 0 || started == null) return;
    final elapsed = sample.at.difference(started);
    if (elapsed > budgetWindow) return;
    final candidate = elapsed.inSeconds + eta;
    final current = _expectedSeconds;
    if (current == null || candidate > current) _expectedSeconds = candidate;
  }

  int _straightLineSeconds() {
    var meters = 0.0;
    final stops = _plan.plannedStops;
    for (var i = 1; i < stops.length; i++) {
      meters += _meters(stops[i - 1], stops[i]);
    }
    return GeoDistance.urbanSecondsForDistance(meters);
  }

  int _jumps = 0;

  bool _isJump(RideCheckSample previous, RideCheckSample sample) {
    final seconds = sample.at.difference(previous.at).inMilliseconds / 1000;
    if (seconds < 0.5) return false;
    return _meters(previous.point, sample.point) / seconds > plausibleSpeedMps;
  }

  bool _canFire(RideCheckTrigger trigger) =>
      settings.isOn(trigger) && !_fired.contains(trigger);

  RideCheckDetection _fire(RideCheckTrigger trigger, RideCheckReason reason) {
    _fired.add(trigger);
    return RideCheckDetection(trigger, reason);
  }
}

double _meters(GeoPoint a, GeoPoint b) =>
    GeoDistance.metersBetween(a.latitude, a.longitude, b.latitude, b.longitude);

/// Shortest distance in metres from [point] to the line through [route].
double distanceToPolyline(GeoPoint point, List<GeoPoint> route) {
  if (route.isEmpty) return double.infinity;
  if (route.length == 1) return _meters(point, route.first);
  // A local flat projection around [point] is exact enough at city scale.
  const earth = 6371000.0;
  final latRad = point.latitude * math.pi / 180;
  math.Point<double> project(GeoPoint p) => math.Point(
    (p.longitude - point.longitude) * math.pi / 180 * earth * math.cos(latRad),
    (p.latitude - point.latitude) * math.pi / 180 * earth,
  );
  var best = double.infinity;
  for (var i = 1; i < route.length; i++) {
    final a = project(route[i - 1]);
    final b = project(route[i]);
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = dx * dx + dy * dy;
    final t = length == 0
        ? 0.0
        : ((-a.x * dx - a.y * dy) / length).clamp(0.0, 1.0);
    final x = a.x + dx * t;
    final y = a.y + dy * t;
    best = math.min(best, math.sqrt(x * x + y * y));
  }
  return best;
}
