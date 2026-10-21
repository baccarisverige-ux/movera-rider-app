import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_booked_popup.dart';
import 'package:movera_rider/features/reservations/presentation/review_changes.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// Create or update after pickup is already confirmed. Never Finding Driver.
class ScheduledRideCheckout {
  static ReservationDraft draftFrom({
    required RideSelectionController selection,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    String? note,
    String? parentReservationId,
    double? price,
    String? timeZone,
  }) {
    final picked = selection.scheduledFor;
    if (picked == null) {
      throw StateError('scheduled checkout needs a pickup time');
    }
    // rider-63: as ScheduledRideBooking.confirm books it.
    final zone = ScheduledRideBooking.pickupTimeZone(
      pickup,
      timeZone: timeZone,
    );
    final when = ScheduledRideBooking.pickupInstant(picked, zone);
    final ride = selection.rideById(selection.selectedRideId);
    final payment = selection.selectedPaymentItem();
    if (payment == null) {
      throw StateError('scheduled checkout needs an available payment method');
    }
    return ReservationDraft(
      scheduledPickupAt: when,
      estimatedDropoffAt: when.add(Duration(minutes: ride.etaMin)),
      pickup: pickup,
      destination: destination,
      categoryId: ride.id,
      categoryName: ride.name,
      categoryImage: ride.image,
      passengerCount: ride.seats,
      price: price ?? ScheduledRideBooking.quotedPrice(selection, ride.id),
      currency: selection.currency,
      paymentMethod: payment.name,
      note: note,
      parentReservationId: parentReservationId,
      timeZone: zone,
    );
  }

  static Future<Reservation?> run(
    BuildContext context, {
    required ReservationController reservations,
    required RideSelectionController selection,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    required LatLng pickupPosition,
    String? note,
    String? parentReservationId,
    String? editingReservationId,
    Reservation? original,
    String? timeZone,
  }) async {
    if (selection.entersFindingDriver || !selection.createsReservation) {
      throw StateError('scheduled checkout cannot enter Finding Driver');
    }
    if (selection.scheduledFor == null) return null;

    final confirmedPickup = ReservationPlace(
      label: pickup.label,
      lat: pickup.lat ?? pickupPosition.latitude,
      lng: pickup.lng ?? pickupPosition.longitude,
      subtitle: pickup.subtitle,
    );
    final draft = draftFrom(
      selection: selection,
      pickup: confirmedPickup,
      destination: destination,
      note: note,
      parentReservationId: parentReservationId,
      timeZone: timeZone,
    );

    if (editingReservationId != null && original != null) {
      final accepted = await Navigator.of(context).push<bool>(
        BottomToTopTransition(
          ReviewChangesPage(
            original: original,
            draft: draft,
            controller: reservations,
          ),
        ),
      );
      if (accepted != true || !context.mounted) return null;
      return ScheduledRideBooking.confirm(
        reservations: reservations,
        selection: selection,
        pickup: confirmedPickup,
        destination: destination,
        note: note,
        editingReservationId: editingReservationId,
        price: draft.price,
        timeZone: timeZone,
      );
    }

    final created = await ScheduledRideBooking.confirm(
      reservations: reservations,
      selection: selection,
      pickup: confirmedPickup,
      destination: destination,
      note: note,
      parentReservationId: parentReservationId,
      price: draft.price,
      timeZone: timeZone,
    );
    if (context.mounted) {
      await showReservationBookedPopup(context);
    }
    return created;
  }
}
