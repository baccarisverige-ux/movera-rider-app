import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/application/scheduled_ride_checkout.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

import 'scheduled_quote_harness.dart';

class _Geocoder implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async =>
      PlaceResult(address: query, point: const GeoPoint(59.35, 18.07));

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class _Quotes implements QuoteRepository {
  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async => RideQuote(
    id: 'q-$rideType',
    rideType: rideType,
    totalMinor: 25900,
    currency: 'SEK',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    signedPayload: 'signature',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  ReservationController reservations({String Function()? nextId}) {
    var n = 0;
    return ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: nextId ?? () => 'rsv_${++n}',
      ),
    );
  }

  RideSelectionController scheduledSelection({
    String rideId = 'economy',
    DateTime? when,
  }) {
    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
    );
    final ride = selection.rideById(rideId);
    selection.selectRide(ride.id, ride.price);
    selection.scheduleFor(when ?? DateTime(2026, 9, 23, 6, 55));
    adoptScheduledQuote(selection, ride.id);
    return selection;
  }

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, [int steps = 10]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The real Select ride screen on fakes (catalog, quotes, geocoding).
  Future<RideSelectionController> pumpSelectRide(
    WidgetTester tester, {
    required ReservationController reservations,
    String pickup = 'Klockarvägen 37',
    String destination = 'Arlanda Airport',
    String? editingReservationId,
    DateTime? scheduledFor,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: _Quotes(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: pickup,
          destinationAddress: destination,
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          geocoding: _Geocoder(),
          selection: selection,
          reservations: reservations,
          editingReservationId: editingReservationId,
          initialScheduledFor: scheduledFor,
          onScheduled: (_, _) async {},
        ),
      ),
    );
    await settle(tester);
    return selection;
  }

  test('now mode still shows Select [category] and enters Finding Driver', () {
    final selection = RideSelectionController(bookingMode: BookingMode.now);
    expect(selection.bookingMode.ctaLabel('Movera'), 'Select Movera');
    expect(
      ScheduledRideBooking.ctaLabel(BookingMode.now, 'Movera'),
      'Select Movera',
    );
    expect(selection.entersFindingDriver, isTrue);
    expect(selection.createsReservation, isFalse);
  });

  test('scheduled date/time turns Select Movera into Schedule Movera', () {
    final selection = RideSelectionController();
    expect(selection.bookingMode.ctaLabel('Movera'), 'Select Movera');
    expect(selection.entersFindingDriver, isTrue);
    final catalog = selection.rides().map((ride) => ride.id).toList();
    selection.scheduleFor(DateTime(2026, 9, 23, 6, 55));
    expect(selection.bookingMode, BookingMode.scheduled);
    expect(selection.bookingMode.ctaLabel('Movera'), 'Schedule Movera');
    expect(
      ScheduledRideBooking.ctaLabel(selection.bookingMode, 'Movera'),
      'Schedule Movera',
    );
    expect(selection.entersFindingDriver, isFalse);
    expect(selection.createsReservation, isTrue);
    expect(selection.rides().map((ride) => ride.id), catalog);
    expect(selection.selectedRideId, 'economy');
  });

  test(
    'now-mode confirm refuses to create a reservation or start a search',
    () {
      final selection = RideSelectionController(bookingMode: BookingMode.now);
      final c = reservations();
      expect(
        () => ScheduledRideBooking.confirm(
          reservations: c,
          selection: selection,
          pickup: const ReservationPlace(label: 'Klockarvägen 37'),
          destination: const ReservationPlace(label: 'Arlanda Express'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(c.all, isEmpty);
      expect(FindingDriverController.active, isNull);
      expect(AppScope.instance.ride.status, RideStatus.idle);
    },
  );

  test(
    'Schedule Movera creates exactly one reservation and never finds a driver',
    () async {
      final c = reservations();
      final selection = scheduledSelection();
      expect(selection.bookingMode.ctaLabel('Movera'), 'Schedule Movera');
      final created = await ScheduledRideBooking.confirm(
        reservations: c,
        selection: selection,
        pickup: const ReservationPlace(
          label: 'Klockarvägen 37',
          lat: 59.19,
          lng: 17.62,
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Express',
          lat: 59.65,
          lng: 17.93,
        ),
      );
      expect(c.all, hasLength(1));
      expect(created.reservationId, 'rsv_1');
      expect(created.categoryName, 'Movera');
      expect(created.status, ReservationStatus.scheduled);
      expect(FindingDriverController.active, isNull);
      expect(AppScope.instance.ride.status, RideStatus.idle);
      expect(AppScope.instance.ride.rideId, isNull);
    },
  );

  testWidgets(
    'tapping Schedule Movera opens Ride scheduled, not Finding Driver',
    (tester) async {
      final c = reservations();
      final selection = scheduledSelection();
      await pumpPhone(
        tester,
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final created = await ScheduledRideBooking.confirm(
                      reservations: c,
                      selection: selection,
                      pickup: const ReservationPlace(label: 'Klockarvägen 37'),
                      destination: const ReservationPlace(
                        label: 'Arlanda Express',
                      ),
                    );
                    if (!context.mounted) return;
                    await RideScheduledPage.open(
                      context,
                      reservationId: created.reservationId,
                      controller: c,
                    );
                  },
                  child: Text(selection.bookingMode.ctaLabel('Movera')),
                ),
              ),
            );
          },
        ),
      );
      expect(find.text('Select Movera'), findsNothing);
      expect(find.text('Schedule Movera'), findsOneWidget);
      await tester.tap(find.text('Schedule Movera'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(c.all, hasLength(1));
      expect(c.all.single.reservationId, 'rsv_1');
      expect(find.text('Your ride is scheduled'), findsOneWidget);
      expect(find.text('Driver pending'), findsOneWidget);
      expect(find.text('Connecting you with nearby drivers'), findsNothing);
      expect(FindingDriverController.active, isNull);
      expect(AppScope.instance.ride.status, RideStatus.idle);
    },
  );

  testWidgets('Ride scheduled appears under Upcoming with the same id', (
    tester,
  ) async {
    final store = MemoryReservationStorage();
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: store,
        nextId: () => 'rsv_keep',
      ),
    );
    final created = await ScheduledRideBooking.confirm(
      reservations: c,
      selection: scheduledSelection(),
      pickup: const ReservationPlace(label: 'Klockarvägen 37'),
      destination: const ReservationPlace(label: 'Arlanda Express'),
    );
    await pumpPhone(
      tester,
      RideScheduledPage(reservationId: created.reservationId, controller: c),
    );
    expect(find.text('Your ride is scheduled'), findsOneWidget);
    expect(c.upcoming().single.reservationId, 'rsv_keep');

    await pumpPhone(tester, RideHistory(reservations: c));
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Klockarvägen 37 → Arlanda Express'), findsOneWidget);
    expect(c.all, hasLength(1));

    await c.update(
      'rsv_keep',
      ReservationPatch(
        scheduledPickupAt: DateTime(2026, 9, 24, 8, 15),
        pickup: const ReservationPlace(label: 'T-Centralen'),
        destination: const ReservationPlace(label: 'Arlanda Terminal 5'),
        paymentMethod: 'Swish',
      ),
    );
    await tester.pump();
    expect(c.all, hasLength(1));
    expect(c.byId('rsv_keep')!.reservationId, 'rsv_keep');
    expect(c.byId('rsv_keep')!.pickup.label, 'T-Centralen');
    expect(c.byId('rsv_keep')!.destination.label, 'Arlanda Terminal 5');
    expect(c.byId('rsv_keep')!.paymentMethod, 'Swish');
    expect(c.byId('rsv_keep')!.scheduledPickupAt, DateTime(2026, 9, 24, 8, 15));

    final restored = ReservationController(
      store: LocalReservationRepository(storage: store),
    );
    await restored.hydrate();
    expect(restored.all, hasLength(1));
    expect(restored.all.single.reservationId, 'rsv_keep');
    expect(restored.all.single.paymentMethod, 'Swish');

    await c.cancel('rsv_keep', reason: 'plans_changed');
    await tester.pump();
    expect(c.upcoming(), isEmpty);
    expect(c.cancelled().single.reservationId, 'rsv_keep');
    expect(c.all, hasLength(1));
  });

  test(
    'plan return ride uses the same category cards and waits for confirm',
    () async {
      final c = reservations();
      final origin = await ScheduledRideBooking.confirm(
        reservations: c,
        selection: scheduledSelection(),
        pickup: const ReservationPlace(
          label: 'Klockarvägen 37',
          lat: 59.19,
          lng: 17.62,
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Express',
          lat: 59.65,
          lng: 17.93,
        ),
      );
      expect(c.all, hasLength(1));

      final returnSelection = RideSelectionController(
        bookingMode: BookingMode.scheduled,
        lockBookingMode: true,
      );
      returnSelection.scheduleFor(
        origin.scheduledPickupAt.add(const Duration(hours: 3)),
      );
      returnSelection.selectRide('comfort', 339);
      adoptScheduledQuote(returnSelection, 'comfort');
      expect(
        returnSelection.bookingMode.ctaLabel('Comfort'),
        'Schedule Comfort',
      );
      expect(returnSelection.entersFindingDriver, isFalse);
      expect(
        c.all,
        hasLength(1),
        reason: 'return ride must not exist before confirm',
      );

      final ret = await ScheduledRideBooking.confirm(
        reservations: c,
        selection: returnSelection,
        pickup: ReservationPlace(label: origin.destination.label),
        destination: ReservationPlace(label: origin.pickup.label),
        parentReservationId: origin.reservationId,
      );
      expect(c.all, hasLength(2));
      expect(ret.reservationId, isNot(origin.reservationId));
      expect(ret.categoryId, 'comfort');
      expect(ret.pickup.label, 'Arlanda Express');
      expect(ret.destination.label, 'Klockarvägen 37');
      expect(ret.parentReservationId, origin.reservationId);
      expect(FindingDriverController.active, isNull);
      expect(AppScope.instance.ride.status, RideStatus.idle);
    },
  );

  testWidgets('When should we pick you up Continue returns a scheduled time', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 26, 10);
    DateTime? picked;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await ScheduleDateTimeSelector.choose(
                    context,
                    now: () => now,
                  );
                },
                child: const Text('open calendar'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('When should we'), findsOneWidget);
    expect(find.text('Pickup at'), findsOneWidget);
    expect(find.text('Arrive by'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked, isNotNull);
    expect(StockholmSchedule.isLegalPickup(picked!, now), isTrue);

    final selection = RideSelectionController();
    expect(selection.bookingMode.ctaLabel('Movera'), 'Select Movera');
    selection.scheduleFor(picked);
    expect(selection.bookingMode.ctaLabel('Movera'), 'Schedule Movera');
    expect(selection.entersFindingDriver, isFalse);
  });

  testWidgets('Book for later keeps the addresses already entered', (
    tester,
  ) async {
    // rider-u237: the addresses go through the real Select ride screen,
    // its Book now or later picker and Book for later, into the
    // reservation it creates.
    final c = reservations();
    await pumpSelectRide(
      tester,
      reservations: c,
      pickup: 'Klockarvägen 37',
      destination: 'Arlanda Express',
    );
    expect(find.text('Select Movera'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('Book now or later')));
    await settle(tester);
    await tester.tap(find.text('Book for later'));
    await settle(tester);
    expect(find.textContaining('When should we'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.text('Schedule Movera'));
    await settle(tester, 30);
    await tester.tap(find.text('Confirm and schedule'));
    await settle(tester, 30);

    final booked = c.all.single;
    expect(booked.pickup.label, 'Klockarvägen 37');
    expect(booked.destination.label, 'Arlanda Express');
    expect(FindingDriverController.active, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  test('editing a reservation keeps the same id after the full flow', () async {
    final c = reservations();
    final first = await ScheduledRideBooking.confirm(
      reservations: c,
      selection: scheduledSelection(),
      pickup: const ReservationPlace(label: 'Current location'),
      destination: const ReservationPlace(label: 'Arlanda'),
    );
    expect(c.all, hasLength(1));
    expect(first.reservationId, 'rsv_1');

    final updated = await ScheduledRideBooking.confirm(
      reservations: c,
      selection: scheduledSelection(
        rideId: 'comfort',
        when: DateTime(2026, 9, 24, 9, 30),
      ),
      pickup: const ReservationPlace(label: 'T-Centralen'),
      destination: const ReservationPlace(label: 'Bromma'),
      editingReservationId: first.reservationId,
    );
    expect(c.all, hasLength(1));
    expect(updated.reservationId, 'rsv_1');
    expect(updated.pickup.label, 'T-Centralen');
    expect(updated.destination.label, 'Bromma');
    expect(updated.categoryId, 'comfort');
    expect(updated.scheduledPickupAt, DateTime(2026, 9, 24, 9, 30));
    expect(FindingDriverController.active, isNull);
    expect(AppScope.instance.ride.status, RideStatus.idle);
  });

  testWidgets(
    'edit hydrates the saved payment instead of defaulting to Cash',
    (tester) async {
      final c = reservations();
      final create = scheduledSelection();
      create.selectPaymentNamed('Card');
      final first = await ScheduledRideBooking.confirm(
        reservations: c,
        selection: create,
        pickup: const ReservationPlace(label: 'Current location'),
        destination: const ReservationPlace(label: 'Arlanda'),
      );
      expect(first.paymentMethod, 'Card');
      expect(first.reservationId, 'rsv_1');

      // rider-u238: SelectRide itself must hydrate the saved method when it
      // edits the reservation; the test no longer does it.
      final edit = await pumpSelectRide(
        tester,
        reservations: c,
        editingReservationId: first.reservationId,
        scheduledFor: StockholmSchedule.clampPickup(
          StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
        ),
      );
      expect(edit.payments()[edit.selectedPayment].name, 'Card');
      // Booking it from here asks for a saved card first (rider-r4-34);
      // that ScheduledRideBooking.confirm keeps the selection's method is
      // covered above.
      expect(c.all.single.paymentMethod, 'Card');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    },
  );

  test('selectPaymentNamed ignores unknown methods', () {
    final selection = RideSelectionController();
    final before = selection.selectedPayment;
    selection.selectPaymentNamed('Not a method');
    expect(selection.selectedPayment, before);
    selection.selectPaymentNamed('Card');
    expect(selection.payments()[selection.selectedPayment].name, 'Card');
    // Bookings saved as "Cash" before the rename map to Cash.
    selection.selectPaymentNamed('Cash');
    expect(selection.payments()[selection.selectedPayment].name, 'Cash');
  });

  test('checkout draft does not create a reservation', () {
    final c = reservations();
    final selection = scheduledSelection();
    final draft = ScheduledRideCheckout.draftFrom(
      selection: selection,
      pickup: const ReservationPlace(label: 'Current location'),
      destination: const ReservationPlace(label: 'Arlanda'),
    );
    expect(c.all, isEmpty);
    expect(draft.categoryName, 'Movera');
    expect(FindingDriverController.active, isNull);
  });

  test('price change copy stays in the pricing layer', () {
    expect(
      const ReservationPriceChange(previous: 289, next: 329).summary,
      'Your updated ride costs 40 kr more.',
    );
    expect(
      const ReservationPriceChange(previous: 329, next: 289).summary,
      'Your updated ride costs 40 kr less.',
    );
    expect(
      const ReservationPriceChange(previous: 259, next: 259).summary,
      'Price unchanged',
    );
  });
}
