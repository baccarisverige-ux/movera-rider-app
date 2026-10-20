import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_ride_realtime.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

abstract final class ReservationLiveRide {
  static const _fallback = LatLng(59.3293, 18.0686);

  static MatchedDriver driverOf(ReservationDriver driver) {
    final parts = (driver.vehicle ?? '')
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return MatchedDriver(
      id: 'rsv-driver-${driver.firstName}',
      firstName: driver.firstName,
      rating: driver.rating,
      vehicleMake: parts.isNotEmpty ? parts.first : driver.vehicle,
      vehicleModel: parts.length > 1 ? parts.sublist(1).join(' ') : null,
      plate: driver.plate,
      photoAsset: driver.photoAsset,
    );
  }

  static RideNotes notesOf(Reservation ride) {
    final note = ride.note ?? '';
    return RideNotes(
      bags: note.contains('Bags'),
      pet: note.contains('Pet'),
      baby: note.contains('Baby'),
      child: note.contains('Child'),
    );
  }

  static LatLng _point(ReservationPlace place) {
    if (place.lat != null && place.lng != null) {
      return LatLng(place.lat!, place.lng!);
    }
    return _fallback;
  }

  static ReservationController _controller(ReservationController? controller) =>
      controller ?? AppScope.instance.reservations;

  static WaitingForDriver pageFor(
    Reservation ride, {
    ReservationController? controller,
  }) {
    final reservations = _controller(controller);
    final realtime = ReservationRideRealtime(
      controller: reservations,
      reservationId: ride.reservationId,
    );

    return WaitingForDriver(
      pickupAddress: ride.pickup.label,
      destinationAddress: ride.destination.label,
      pickupPosition: _point(ride.pickup),
      destinationPosition: _point(ride.destination),
      rideType: ride.categoryName,
      price: ride.price,
      currency: ride.currency,
      paymentMethod: ride.paymentMethod,
      notes: notesOf(ride),
      driver: ride.driver == null ? null : driverOf(ride.driver!),
      rideId: ride.reservationId,
      realtime: realtime,
      persistRideSnapshot: false,
      onCancel: (context, reasonId) async {
        await reservations.cancel(
          ride.reservationId,
          reason: reasonId ?? 'rider_cancelled_live',
        );
        if (!context.mounted) return;
        Navigator.of(context).popUntil(AppRoutes.isHomeRoute);
      },
      onDriverCancelled: (context) async {
        if (!context.mounted) return;
        // The parent is either Upcoming Reservation or Home. Returning one
        // route preserves the reverse path and leaves the reservation alive.
        Navigator.of(context).pop();
      },
      onTerminal: (context, status) async {
        if (!context.mounted) return;
        Navigator.of(context).popUntil(AppRoutes.isHomeRoute);
      },
      onCompleted: (context, status) async {
        if (!context.mounted) return;
        final completionRealtime = ReservationRideRealtime(
          controller: reservations,
          reservationId: ride.reservationId,
        );
        Navigator.of(context).pushReplacement(
          RideStageTransition(
            RideCompleted(
              status: status,
              rideId: ride.reservationId,
              realtime: completionRealtime,
              persistOnDemandState: false,
              feedbackAvailableOnCompletion: true,
              showConnectionBanner: false,
              onClose: (completionContext) async {
                if (!completionContext.mounted) return;
                Navigator.of(
                  completionContext,
                ).popUntil(AppRoutes.isHomeRoute);
              },
            ),
            settings: const RouteSettings(name: AppRoutes.rideCompleted),
          ),
        );
      },
    );
  }

  static Future<void> open(
    BuildContext context,
    Reservation ride, {
    ReservationController? controller,
    bool replace = false,
  }) {
    final route = BottomToTopTransition(
      pageFor(ride, controller: controller),
      settings: const RouteSettings(name: AppRoutes.reservationLive),
    );
    if (replace) {
      return Navigator.of(context).pushReplacement(route);
    }
    return Navigator.of(context).push(route);
  }
}
