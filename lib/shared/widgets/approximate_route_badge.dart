import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner N2: without a road route (the server has no router configured,
/// or it answered with its straight-line estimate) the map draws the
/// direct line. This small label says so, as the trip map always has.
class ApproximateRouteBadge extends StatelessWidget {
  const ApproximateRouteBadge({super.key});

  /// Whether [points] (a routing answer) is only the direct line.
  static bool isStraight(List<Object?>? points) =>
      points != null && points.length <= 2;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const ValueKey('approximate-route-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          context.l10n.approximateRoute,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
