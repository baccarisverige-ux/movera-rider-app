import 'package:flutter/material.dart';

/// Reports a quick horizontal swipe over [child] without stealing taps or
/// vertical drags (sheets, lists and buttons underneath keep working).
class HorizontalSwipe extends StatefulWidget {
  const HorizontalSwipe({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  static const double _minVelocity = 320;
  static const double _minDistance = 56;

  @override
  State<HorizontalSwipe> createState() => _HorizontalSwipeState();
}

class _HorizontalSwipeState extends State<HorizontalSwipe> {
  // rider-93: kept in the state. As locals of build, a rebuild during the
  // drag reset the start to 0 and a left swipe read as a right one.
  double _start = 0;
  double _last = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (d) => _start = _last = d.globalPosition.dx,
      onHorizontalDragUpdate: (d) => _last = d.globalPosition.dx,
      onHorizontalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        final distance = _last - _start;
        final left =
            velocity < -HorizontalSwipe._minVelocity ||
            distance < -HorizontalSwipe._minDistance;
        final right =
            velocity > HorizontalSwipe._minVelocity ||
            distance > HorizontalSwipe._minDistance;
        if (left && !right) widget.onSwipeLeft?.call();
        if (right && !left) widget.onSwipeRight?.call();
      },
      child: widget.child,
    );
  }
}
