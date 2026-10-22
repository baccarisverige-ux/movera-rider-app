import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

/// Shared Book-later confirm path. SelectRide and tests use this so
/// scheduled mode never starts a live Finding Driver search.
class ScheduledRideBooking {
  static String ctaLabel(BookingMode mode, String categoryName) =>
      mode.ctaLabel(categoryName);

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

  /// rider-63: the pickup zone a Book-later time was picked in (Q9):
  /// [timeZone] when the caller knows it, else the zone of [pickup]'s
  /// point. Null only for a pickup with no point (a device-local booking).
  static String? pickupTimeZone(ReservationPlace pickup, {String? timeZone}) {
    if (timeZone != null) return timeZone;
    final lat = pickup.lat;
    final lng = pickup.lng;
    if (lat == null || lng == null) return null;
    return PickupSchedule.at(lat, lng).timeZone;
  }

  /// The instant of the wall-clock pick [wall] in [timeZone]; without a
  /// zone, [wall]'s fields in the device's time zone.
  static DateTime pickupInstant(DateTime wall, String? timeZone) =>
      timeZone == null
      ? DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute)
      : PickupSchedule(timeZone).toUtc(wall);

  static Future<Reservation> confirm({
    required ReservationController reservations,
    required RideSelectionController selection,
    required ReservationPlace pickup,
    required ReservationPlace destination,
    String? note,
    String? parentReservationId,
    String? editingReservationId,
    double? price,
    String? timeZone,
    List<ReservationPlace> stops = const <ReservationPlace>[],
  }) {
    if (selection.entersFindingDriver || !selection.createsReservation) {
      throw StateError('scheduled booking cannot enter Finding Driver');
    }
    final picked = selection.scheduledFor;
    if (picked == null) {
      throw StateError('scheduled booking needs a pickup time');
    }
    // rider-63: the pick is the pickup zone's wall-clock time; the ride
    // keeps its instant and its zone.
    final zone = pickupTimeZone(pickup, timeZone: timeZone);
    final when = pickupInstant(picked, zone);
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
          timeZone: zone,
          // rider-r4-28: the stops [quoted] priced.
          stops: stops,
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
        timeZone: zone,
        stops: stops,
      ),
    );
  }
}
