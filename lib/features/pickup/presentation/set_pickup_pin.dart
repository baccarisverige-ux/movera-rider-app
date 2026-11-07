part of 'set_pickup_page.dart';

// Rule 25 split (2026-11-07, no behaviour change): the centre pin, moved
// out of set_pickup_page.dart unchanged.

/// The fixed centre pin: a green "N min" bubble on a stem. It lifts while the
/// map moves (its shadow spreads) and drops back with a small bounce.
class _PickupPin extends StatelessWidget {
  const _PickupPin({super.key, required this.lift});

  /// The lift, already curved (ease out up, a small bounce down).
  final Animation<double> lift;

  static const _bubble = 34.0;
  static const _stem = 14.0;

  /// From the top of the widget to the pin's tip.
  static const tipOffset = _bubble + _stem + 4;

  @override
  Widget build(BuildContext context) {
    final drop = lift;
    return AnimatedBuilder(
      animation: drop,
      builder: (context, _) {
        final t = drop.value;
        return SizedBox(
          width: 80,
          height: tipOffset + 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Shadow on the ground: grows and softens as the pin rises.
              Positioned(
                top: tipOffset - 4,
                child: Container(
                  width: 10 + 14 * t,
                  height: 6 + 3 * t,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28 - 0.12 * t),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -14 * t),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _bubble,
                      height: _bubble,
                      decoration: BoxDecoration(
                        color: RiderRouteStyle.pickup,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: RiderRouteStyle.pickup.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 10 + 8 * t,
                            offset: Offset(0, 4 + 6 * t),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 3,
                      height: _stem,
                      color: RiderRouteStyle.pickup,
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: RiderRouteStyle.pickup,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
