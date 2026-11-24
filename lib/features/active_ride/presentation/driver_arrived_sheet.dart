import 'package:movera_rider/features/active_ride/presentation/trip_pin_card.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

const Color _ink = Color(0xFF1D252C);
const Color _muted = Color(0xFF5C656C);

/// Announced once, when the driver reaches the pickup point.
///
/// The rider may have the phone in a pocket, so this has to interrupt rather
/// than quietly change a line of text on the map.
///
/// [onRoute] receives the sheet's own route so the caller can close exactly
/// this sheet later, whatever has been pushed above it (NAV-9).
Future<void> showDriverArrivedSheet(
  BuildContext context, {
  MatchedDriver? driver,
  Future<void> Function()? onWay,
  ValueChanged<Route<Object?>>? onRoute,
  String? pin,
}) {
  return MoveraSheet.show<void>(
    context: context,
    builder: (sheetContext) {
      final route = ModalRoute.of(sheetContext);
      if (route != null) onRoute?.call(route);
      return DriverArrivedSheet(driver: driver, onWay: onWay, pin: pin);
    },
  );
}

/// Closes [route] if it is still on its navigator: popped when it is on
/// top, otherwise removed without touching the routes above it.
void closeRouteByReference(Route<Object?>? route) {
  if (route == null || !route.isActive) return;
  final navigator = route.navigator;
  if (navigator == null) return;
  if (route.isCurrent) {
    navigator.pop();
  } else {
    navigator.removeRoute(route);
  }
}

class DriverArrivedSheet extends StatelessWidget {
  const DriverArrivedSheet({super.key, this.driver, this.onWay, this.pin});

  final MatchedDriver? driver;

  /// G6: the trip PIN to tell the driver (null = no PIN on this trip).
  final String? pin;
  final Future<void> Function()? onWay;

  /// B5 (finder 2026-11-07): the tap always closes the sheet. Before, a
  /// failing POST /on-the-way (offline, or 409 because the trip already
  /// moved on) threw out of the button and left the sheet open with no
  /// message. A 409 closes quietly (the trip stream shows where the ride
  /// is now); any other failure says Movera could not be reached.
  Future<void> _sendOnWayAndClose(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final unreachable = context.l10n.apiUnreachable;
    var failed = false;
    try {
      await onWay?.call();
    } catch (error, stackTrace) {
      AppLog.error(
        'ride.on_the_way_failed',
        error: error,
        stackTrace: stackTrace,
      );
      failed = !(error is ApiError && error.statusCode == 409);
    }
    if (context.mounted) Navigator.of(context).pop();
    if (failed) {
      messenger?.showSnackBar(SnackBar(content: Text(unreachable)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final d = driver;
    final name = d?.firstName;
    final plate = d?.plate;
    final car = [
      d?.vehicleColor,
      d?.vehicleMake,
      d?.vehicleModel,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');

    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Owner 2026-11-23 (C1): a centred navy pin over two calm blue
            // rings; still with reduce motion.
            const ArrivedPin(),
            const SizedBox(height: 10),
            Text(
              name == null
                  ? context.l10n.driverIsHere
                  : context.l10n.nameIsHere(name),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.driverWaitingAtPickup,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: _muted),
            ),
            if (d != null) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DriverRatedPhoto(
                    driver: d,
                    radius: 22,
                    photoKey: const ValueKey('arrived-photo'),
                  ),
                  if (plate != null && plate.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    SwedishPlate(text: plate),
                  ],
                  if (car.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        car,
                        maxLines: 2,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (pin case final code?) ...[
              const SizedBox(height: 16),
              TripPinCard(pin: code),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('driver-arrived-on-way'),
                onPressed: () => _sendOnWayAndClose(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111614),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  context.l10n.imOnTheWay,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C1: the navy pin standing on two soft blue rings that widen calmly.
class ArrivedPin extends StatefulWidget {
  const ArrivedPin({super.key});

  @override
  State<ArrivedPin> createState() => _ArrivedPinState();
}

class _ArrivedPinState extends State<ArrivedPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _rings
        ..stop()
        ..value = 0.5;
    } else if (!_rings.isAnimating && !_played) {
      // A few calm waves, then still (never an endless motion).
      _played = true;
      _rings.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('arrived-pin'),
      width: 210,
      height: 96,
      child: AnimatedBuilder(
        animation: _rings,
        builder: (context, _) => CustomPaint(
          painter: _RingsPainter(_rings.value),
          child: const Align(
            alignment: Alignment(0, -0.45),
            child: Icon(Icons.location_on, size: 64, color: Color(0xFF061B44)),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.78);
    for (final phase in [t, (t + 0.5) % 1]) {
      final w = 70 + 130 * phase;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: w, height: w * 0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(
            0xFF9CC3E0,
          ).withValues(alpha: 0.9 * (1 - phase)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}
