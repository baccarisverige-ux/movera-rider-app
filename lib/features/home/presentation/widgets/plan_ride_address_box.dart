import 'package:flutter/material.dart';
import 'package:movera_rider/core/config/zone_settings.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';

/// The bordered pickup / stops / destination box of Home's "Plan your ride"
/// sheet, with the add-stop button pinned inside it, top-right (Batch 10
/// Phase 112).
///
/// Extracted from `home.dart` so the add-stop design can be tested directly:
/// Home still passes `showAddStop: _stopsSupported` (a `static const false`),
/// so the button stays hidden in every build until multi-stop trips exist.
class PlanRideAddressBox extends StatelessWidget {
  const PlanRideAddressBox({
    super.key,
    required this.routeRows,
    required this.showAddStop,
    required this.stopCount,
    required this.onAddStop,
    this.maxStops = defaultMaxStops,
  });

  /// Pickup, stop and destination rows (with their dividers), top to bottom.
  final List<Widget> routeRows;

  /// Whether the add-stop button is shown at all.
  final bool showAddStop;

  /// Stops currently in the route; the button is disabled at [maxStops].
  final int stopCount;

  /// Adds one stop. Not called while disabled.
  final VoidCallback onAddStop;

  /// The zone's `booking.maxStops` (Q39: Admin sets it per zone).
  final int maxStops;

  /// `contract.json#configDefaults.maxStops`.
  static const int defaultMaxStops = ZoneDefaults.maxStops;
  static const Key addStopKey = Key('plan-ride-add-stop');

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);

  /// Existing design-system red (`AppColor.red`, #E31E37).
  static const Color addStopColor = AppColor.red;
  static Color get addStopDisabledColor => _muted.withValues(alpha: 0.4);

  @override
  Widget build(BuildContext context) {
    final buttonSize = ResSize.w * 40;
    final canAdd = stopCount < maxStops;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResSize.w * 10,
        vertical: ResSize.h * 3,
      ),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _ink, width: 1.25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: ResSize.w * 13,
            top: ResSize.h * 25,
            bottom: ResSize.h * 25,
            child: Container(width: 1.4, color: _ink.withValues(alpha: 0.72)),
          ),
          Padding(
            // Reserve the button's column so no field or clear button ever
            // sits under it, at any width.
            padding: EdgeInsets.only(
              right: showAddStop ? buttonSize + ResSize.w * 4 : 0,
            ),
            child: Column(children: routeRows),
          ),
          if (showAddStop)
            Positioned(
              top: ResSize.h * 5,
              right: 0,
              child: Semantics(
                button: true,
                enabled: canAdd,
                label: 'Add a stop',
                child: Material(
                  key: addStopKey,
                  color: const Color(0xFFF0F2F3),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: canAdd ? onAddStop : null,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: buttonSize,
                      height: buttonSize,
                      child: Icon(
                        Icons.add_rounded,
                        color: canAdd ? addStopColor : addStopDisabledColor,
                        size: buttonSize * 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
