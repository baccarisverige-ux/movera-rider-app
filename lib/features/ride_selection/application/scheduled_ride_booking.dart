import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

/// Shared Book-later confirm path. SelectRide and tests use this so
/// scheduled mode never starts a live Finding Driver search.
class ScheduledRideBooking {
  static String ctaLabel(BookingMode mode, String categoryName) =>
      '${mode.ctaVerb} $categoryName';

  /// ARCH-16: the price a scheduled ride is booked at is the server's
  /// current quote for [categoryId], never the catalog list price. Throws
  /// [ScheduledQuoteRequiredException] when the quote failed or expired, as
  /// Book now refuses to book without one.
  ///
  /// A quote binding the price for the scheduled time (contract C-8) is
  /// PROPOSED and needs backend agreement; until then the Book now quote
  /// taken at booking time is the authoritative figure.
  static double quotedPrice(
    RideSelectionController selection,
    String categoryId, {
    DateTime? now,
  }) {
    final price = selection.authoritativePriceFor(categoryId, now: now);
    if (price == null) throw ScheduledQuoteRequiredException(categoryId);
    return price;
  }

  static Future<Reservation> confirm({
    required ReservationController reservations,
    required RideSelectionController selection,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    String? note,
    String? parentReservationId,
    String? editingReservationId,
    double? price,
  }) {
    if (selection.entersFindingDriver || !selection.createsReservation) {
      throw StateError('scheduled booking cannot enter Finding Driver');
    }
    final when = selection.scheduledFor;
    if (when == null) {
      throw StateError('scheduled booking needs a pickup time');
    }
    final ride = selection.rideById(selection.selectedRideId);
    final payment = selection.selectedPaymentItem();
    if (payment == null) {
      throw StateError('scheduled booking needs an available payment method');
    }
    final dropoff = when.add(Duration(minutes: ride.etaMin));
    final quoted = quotedPrice(selection, ride.id);
    // A caller's price (the reviewed draft) must still be the quoted one.
    if (price != null &&
        selection.moneyOf(price) != selection.moneyOf(quoted)) {
      throw ScheduledQuoteRequiredException(ride.id);
    }
    final nextPrice = quoted;
    if (editingReservationId != null) {
      return reservations.update(
        editingReservationId,
        ReservationPatch(
          scheduledPickupAt: when,
          estimatedDropoffAt: dropoff,
          pickup: pickup,
          destination: destination,
          categoryId: ride.id,
          categoryName: ride.name,
          categoryImage: ride.image,
          passengerCount: ride.seats,
          price: nextPrice,
          currency: selection.currency,
          paymentMethod: payment.name,
          note: note,
        ),
      );
    }
    return reservations.create(
      ReservationDraft(
        scheduledPickupAt: when,
        estimatedDropoffAt: dropoff,
        pickup: pickup,
        destination: destination,
        categoryId: ride.id,
        categoryName: ride.name,
        categoryImage: ride.image,
        passengerCount: ride.seats,
        price: nextPrice,
        currency: selection.currency,
        paymentMethod: payment.name,
        note: note,
        parentReservationId: parentReservationId,
      ),
    );
  }
}
