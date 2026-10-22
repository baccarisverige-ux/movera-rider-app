import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';

void main() {
  test('now mode still enters Finding Driver', () {
    final selection = RideSelectionController(bookingMode: BookingMode.now);
    expect(selection.bookingMode, BookingMode.now);
    expect(selection.entersFindingDriver, isTrue);
    expect(selection.createsReservation, isFalse);
    expect(selection.isScheduled, isFalse);
  });

  test('scheduled mode never enters Finding Driver', () {
    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
    );
    selection.scheduleFor(DateTime(2026, 9, 23, 6, 55));
    expect(selection.bookingMode, BookingMode.scheduled);
    expect(selection.entersFindingDriver, isFalse);
    expect(selection.createsReservation, isTrue);
    expect(selection.isScheduled, isTrue);
  });

  test('same category catalog is used for now and scheduled', () {
    final now = RideSelectionController(bookingMode: BookingMode.now);
    final later = RideSelectionController(bookingMode: BookingMode.scheduled);
    expect(
      now.rides().map((ride) => ride.id),
      later.rides().map((ride) => ride.id),
    );
    expect(
      now.rides().map((ride) => ride.image),
      later.rides().map((ride) => ride.image),
    );
    expect(
      now.rides().map((ride) => ride.name),
      later.rides().map((ride) => ride.name),
    );
    later.scheduleFor(DateTime(2026, 9, 24, 8, 15));
    expect(later.rides().length, now.rides().length);
    expect(later.rideById('comfort').name, 'Comfort');
  });

  test('calendar switches to scheduled and keeps the catalog', () {
    final selection = RideSelectionController();
    final ids = selection.rides().map((ride) => ride.id).toList();
    selection.scheduleFor(DateTime(2026, 9, 23, 6, 55));
    expect(selection.bookingMode, BookingMode.scheduled);
    expect(selection.entersFindingDriver, isFalse);
    expect(selection.rides().map((ride) => ride.id), ids);
    selection.setBookingMode(BookingMode.now);
    expect(selection.bookingMode, BookingMode.now);
    expect(selection.scheduledFor, isNull);
    expect(selection.entersFindingDriver, isTrue);
  });

  test('locked return-ride mode cannot fall back to Finding Driver', () {
    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
      lockBookingMode: true,
    );
    selection.scheduleFor(DateTime(2026, 9, 23, 18, 0));
    selection.setBookingMode(BookingMode.now);
    selection.scheduleFor(null);
    expect(selection.bookingMode, BookingMode.scheduled);
    expect(selection.entersFindingDriver, isFalse);
    expect(selection.createsReservation, isTrue);
  });

  test('return ride selector is the shared category screen', () {
    final origin = Reservation(
      reservationId: 'rsv_origin',
      createdAt: DateTime.utc(2026, 9, 1),
      scheduledPickupAt: DateTime.utc(2026, 9, 23, 6, 55),
      pickup: ReservationPlace(
        label: 'Klockarvägen 37',
        lat: 59.19,
        lng: 17.62,
      ),
      destination: ReservationPlace(
        label: 'Arlanda Express',
        lat: 59.65,
        lng: 17.93,
      ),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 522,
      paymentMethod: 'Cash',
      status: ReservationStatus.scheduled,
      note: 'Bags · Pet',
      timeZone: 'Europe/Stockholm',
    );
    final page = SelectRide.forReturnRide(origin);
    expect(page.bookingMode, BookingMode.scheduled);
    expect(page.lockBookingMode, isTrue);
    expect(page.pickupAddress, 'Arlanda Express');
    expect(page.destinationAddress, 'Klockarvägen 37');
    expect(page.parentReservationId, 'rsv_origin');
    expect(page.initialRideId, 'economy');
    expect(page.note, 'Bags · Pet');
    expect(page.pickupPosition, const LatLng(59.65, 17.93));
    expect(page.destinationPosition, const LatLng(59.19, 17.62));
    // Owner decision 9: origin + 3 h on the pickup zone's clock (06:55Z is
    // 08:55 in Stockholm), a zone wall time.
    expect(page.initialScheduledFor, DateTime.utc(2026, 9, 23, 11, 55));
    expect(
      BookingMode.scheduled.ctaLabel(origin.categoryName),
      'Schedule Movera',
    );
  });
}
