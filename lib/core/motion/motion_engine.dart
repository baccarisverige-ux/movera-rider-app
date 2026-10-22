import 'package:movera_rider/core/location/location_point.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/direction_cone.dart';
import 'package:movera_rider/core/motion/interpolator.dart';
import 'package:movera_rider/core/motion/location_smoother.dart';

class MotionOutput {
  const MotionOutput({
    required this.position,
    required this.heading,
    required this.cone,
    this.velocityMps,
    this.progress = 1,
  });

  final GeoPoint position;
  final double heading;
  final DirectionConeState cone;
  final double? velocityMps;
  final double progress;
}

/// Isolated from widgets and Google Maps.
class MotionEngine {
  MotionEngine({
    LocationSmoother? smoother,
    PositionInterpolator? interpolator,
  })  : _smoother = smoother ?? LocationSmoother(),
        _interpolator = interpolator ?? PositionInterpolator();

  final LocationSmoother _smoother;
  final PositionInterpolator _interpolator;
  LocationPoint? _from;
  LocationPoint? _to;
  DateTime? _startedAt;

  /// How long the pose takes to glide from one fix to the next.
  static const window = Duration(milliseconds: 420);

  /// Takes a new fix. rider-20: the glide towards it starts now (when it
  /// arrives), not at the previous fix's own timestamp: that was always
  /// at least one fix interval old, so the pose jumped straight to the
  /// fix. Callers step the glide with [poseAt] until its progress is 1.
  MotionOutput? ingest(LocationPoint raw, {DateTime? now}) {
    final sample = _smoother.accept(raw);
    if (sample == null) return null;
    final clock = now ?? DateTime.now();
    // A fix during a glide starts the next one where the pose is now.
    final current = _startedAt == null ? null : poseAt(clock);
    _from = current == null
        ? (_to ?? sample)
        : LocationPoint(
            point: current.position,
            timestamp: clock,
            heading: current.heading,
          );
    _to = sample;
    // Nowhere to glide (the first fix, or the same point): already there.
    final from = _from!.point;
    final still = from.latitude == sample.point.latitude &&
        from.longitude == sample.point.longitude;
    _startedAt = still ? clock.subtract(window) : clock;
    return poseAt(clock);
  }

  /// The pose at [now] on the glide towards the latest fix; null before
  /// the first fix.
  MotionOutput? poseAt(DateTime now) {
    final from = _from;
    final to = _to;
    final startedAt = _startedAt;
    if (from == null || to == null || startedAt == null) return null;
    final pose = _interpolator.lerp(
      from: from.point,
      to: to.point,
      fromHeading: from.heading ?? 0,
      toHeading: to.heading ?? from.heading ?? 0,
      startedAt: startedAt,
      now: now,
      window: window,
    );
    return MotionOutput(
      position: pose.point,
      heading: pose.heading,
      cone: DirectionConeState(
        heading: pose.heading,
        accuracy: to.accuracyMeters,
      ),
      velocityMps: to.speedMps,
      progress: pose.progress,
    );
  }
}
