import 'package:movera_rider/features/active_ride/presentation/trip_pin_card.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

const Color _ink = Color(0xFF1D252C);
const Color _muted = Color(0xFF5C656C);
const Color _line = Color(0xFFE7EBEE);
const Color _accent = Color(0xFF2D5878);

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
    final name = driver?.firstName;
    final plate = driver?.plate;
    final vehicle = driver?.vehicleLabel;

    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F0F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_outlined,
                    color: _accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name == null
                        ? context.l10n.driverIsHere
                        : context.l10n.nameIsHere(name),
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.driverWaitingAtPickup,
              style: GoogleFonts.poppins(fontSize: 14, color: _muted),
            ),
            if (plate != null && plate.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plate,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (vehicle != null && vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        style: GoogleFonts.poppins(fontSize: 13, color: _muted),
                      ),
                  ],
                ),
              ),
            ],
            if (pin case final code?) ...[
              const SizedBox(height: 16),
              TripPinCard(pin: code),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _sendOnWayAndClose(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF11181D),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  context.l10n.imOnTheWay,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
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
