import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// After Plan your ride + calendar, open the same category cards as Book now
/// with bookingMode = scheduled so the CTA is Schedule [category].
Future<void> openScheduledCategorySelector(
  BuildContext context, {
  required ScheduledRideSession session,
  String? editingReservationId,
  String? initialRideId,
  String? initialPaymentMethod,
}) async {
  final pickupLabel = session.pickup.trim().isEmpty
      ? 'Current location'
      : session.pickup.trim();
  final destinationLabel = session.dropoff.trim();
  final pickupPosition = session.pickupLat != null && session.pickupLng != null
      ? LatLng(session.pickupLat!, session.pickupLng!)
      : await resolveScheduledPoint(pickupLabel);
  // CODE-5: never book a pickup at a made-up point either.
  if (!context.mounted) return;
  if (pickupPosition == null) {
    MoveraToast.show(context, context.l10n.resValidPickup);
    return;
  }
  // Never book to a made-up point: a destination we cannot find on the map
  // sends the rider back to fix the address instead.
  LatLng? found;
  try {
    found = await findScheduledPoint(destinationLabel);
  } on ScheduledPointLookupFailed {
    if (context.mounted) {
      MoveraToast.show(context, context.l10n.apiUnreachable);
    }
    return;
  }
  final destinationPosition = found;
  if (!context.mounted) return;
  if (destinationPosition == null) {
    MoveraToast.show(context, context.l10n.resValidDestination);
    return;
  }

  AppScope.instance.maps.detach(owner: MapOwners.schedule);

  final created = await Navigator.of(context).push<Reservation>(
    MaterialPageRoute(
      builder: (_) => SelectRide(
        pickupAddress: pickupLabel,
        destinationAddress: destinationLabel,
        pickupPosition: pickupPosition,
        destinationPosition: destinationPosition,
        stops: List<String>.from(session.stops),
        bookingMode: BookingMode.scheduled,
        lockBookingMode: true,
        initialScheduledFor: session.scheduledAt,
        initialRideId: initialRideId ?? session.rideType,
        initialPaymentMethod:
            initialPaymentMethod ??
            (editingReservationId == null ? null : session.paymentMethod),
        note: session.note.trim().isEmpty ? null : session.note.trim(),
        editingReservationId: editingReservationId,
        pickupAlreadyConfirmed: true,
        onScheduled: editingReservationId == null
            ? (context, id) => RideScheduledPage.open(
                context,
                reservationId: id,
                untilHome: true,
              )
            : null,
      ),
    ),
  );
  if (editingReservationId != null && created != null && context.mounted) {
    Navigator.pop(context);
  }
}

/// The address lookup itself failed (offline, timed out, server error):
/// not the same as an address that was not found (rider-r5-23).
class ScheduledPointLookupFailed implements Exception {
  const ScheduledPointLookupFailed();
}

/// The map point for a typed address, or null when it cannot be found.
Future<LatLng?> findScheduledPoint(
  String label, {
  AppGeocoding? geocoding,
}) async {
  final clean = label.trim();
  if (clean.isEmpty) return null;
  try {
    final result = await (geocoding ?? AppScope.instance.geocoding)
        .geocodeAddress(clean)
        .timeout(const Duration(seconds: 6));
    if (result != null) {
      return LatLng(result.point.latitude, result.point.longitude);
    }
  } catch (_) {
    // rider-r5-23: the caller says "check your connection", not "choose a
    // valid address", for a lookup that never got an answer.
    throw const ScheduledPointLookupFailed();
  }
  return null;
}

/// The point for a scheduled pickup: the device position for "Current
/// location", else the geocoded address. Null when neither can be found:
/// CODE-5, this used to answer with the Stockholm city centre, which then
/// became the booked pickup.
Future<LatLng?> resolveScheduledPoint(String label) async {
  final clean = label.trim();
  if (clean.isEmpty || clean.toLowerCase() == 'current location') {
    try {
      final pos = await AppScope.instance.location.getCurrentPosition().timeout(
        const Duration(milliseconds: 600),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // No fix in time: the caller asks the rider to choose the pickup.
      return null;
    }
  }
  try {
    final result = await AppScope.instance.geocoding
        .geocodeAddress(clean)
        .timeout(const Duration(milliseconds: 900));
    if (result != null) {
      return LatLng(result.point.latitude, result.point.longitude);
    }
  } catch (_) {
    // Best-effort geocode: null below sends the rider back to fix it.
  }
  return null;
}
