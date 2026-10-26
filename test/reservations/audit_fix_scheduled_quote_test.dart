import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/application/scheduled_ride_checkout.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

import 'scheduled_quote_harness.dart';

/// ARCH-16: a scheduled ride is only booked at the server's quote, never at
/// the catalog list price.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReservationController reservations() => ReservationController(
    store: LocalReservationRepository(storage: MemoryReservationStorage()),
  );

  RideSelectionController scheduled() {
    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
    );
    addTearDown(selection.dispose);
    final ride = selection.rideById('economy');
    selection.selectRide(ride.id, ride.price);
    selection.scheduleFor(DateTime(2026, 10, 20, 8, 30));
    return selection;
  }

  Future<Reservation> book(
    ReservationController c,
    RideSelectionController selection, {
    double? price,
  }) => ScheduledRideBooking.confirm(
    reservations: c,
    selection: selection,
    pickup: const ReservationPlace(label: 'A', lat: 59.3, lng: 18.0),
    destination: const ReservationPlace(label: 'B', lat: 59.6, lng: 17.9),
    price: price,
  );

  test('without a quote nothing is booked at the catalog price', () async {
    final c = reservations();
    final selection = scheduled();
    await expectLater(
      () => book(c, selection),
      throwsA(isA<ScheduledQuoteRequiredException>()),
    );
    expect(c.all, isEmpty);
    expect(
      () => ScheduledRideCheckout.draftFrom(
        selection: selection,
        pickup: const ReservationPlace(label: 'A'),
        destination: const ReservationPlace(label: 'B'),
      ),
      throwsA(isA<ScheduledQuoteRequiredException>()),
    );
  });

  test('an expired quote is not authoritative either', () async {
    final c = reservations();
    final selection = scheduled();
    adoptScheduledQuote(selection, 'economy', kr: 312);
    selection.quoteExpiresAt['economy'] = DateTime.now().subtract(
      const Duration(seconds: 1),
    );
    await expectLater(
      () => book(c, selection),
      throwsA(isA<ScheduledQuoteRequiredException>()),
    );
    expect(c.all, isEmpty);
  });

  test('the reservation carries the quoted price', () async {
    final c = reservations();
    final selection = scheduled();
    adoptScheduledQuote(selection, 'economy', kr: 312);
    final created = await book(c, selection);
    expect(created.price, 312);
  });

  test('a reviewed price that is not the quote is refused', () async {
    final c = reservations();
    final selection = scheduled();
    adoptScheduledQuote(selection, 'economy', kr: 312);
    await expectLater(
      () => book(c, selection, price: 259),
      throwsA(isA<ScheduledQuoteRequiredException>()),
    );
    expect(c.all, isEmpty);
  });

  test('the rider is told nothing was booked', () {
    const error = ScheduledQuoteRequiredException('economy');
    expect(
      reservationErrorMessage(error, ReservationAction.book),
      contains("so it wasn't booked"),
    );
    expect(
      reservationErrorMessage(error, ReservationAction.edit),
      contains("weren't saved"),
    );
  });

  testWidgets('rider-r4-35: a quote that runs out on Review changes is '
      'priced again, not refused', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = reservations();
    final selection = scheduled();
    adoptScheduledQuote(selection, 'economy', kr: 312);
    final booked = await tester.runAsync(() => book(c, selection));
    double? reviewed;
    Reservation? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await ScheduledRideCheckout.run(
                context,
                reservations: c,
                selection: selection,
                pickup: const ReservationPlace(
                  label: 'A',
                  lat: 59.3,
                  lng: 18.0,
                ),
                destination: const ReservationPlace(label: 'B'),
                pickupPosition: const LatLng(59.3, 18.0),
                editingReservationId: booked!.reservationId,
                original: booked,
                requote: (price) async {
                  reviewed = price;
                  adoptScheduledQuote(selection, 'economy', kr: 318);
                  return 318;
                },
              );
            },
            child: const Text('edit'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    // Two minutes reading the changes: the quote is spent.
    selection.quoteExpiresAt['economy'] = DateTime.now().subtract(
      const Duration(seconds: 1),
    );
    await tester.tap(find.text('Confirm changes'));
    await tester.pumpAndSettle();

    expect(reviewed, 312);
    expect(saved?.price, 318);
    expect(c.byId(booked!.reservationId)!.price, 318);
  });
}
