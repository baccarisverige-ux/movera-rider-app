import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = LatLng(59.3293, 18.0686);
const _moved = LatLng(59.31, 18.0686);

/// Every ride costs 42 kr more from the moved pin than from the original
/// pickup. [slowFirstPin] holds the first quote from the moved pin until
/// [pin] completes; [failFirstPin] makes it fail.
class _PickupQuotes implements QuoteRepository {
  _PickupQuotes({this.slowFirstPin = false, this.failFirstPin = false});

  final bool slowFirstPin;
  final bool failFirstPin;
  Completer<void>? pin;
  bool _pinSeen = false;
  int calls = 0;

  static int base(String rideType) => switch (rideType) {
    'economy' => 25900,
    'comfort' => 33900,
    _ => 30000,
  };

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
  }) async {
    calls++;
    final id = calls;
    final atOrigin =
        pickupPoint == null ||
        (pickupPoint.latitude - _origin.latitude).abs() < 1e-6;
    if (!atOrigin && !_pinSeen) {
      _pinSeen = true;
      if (failFirstPin) throw StateError('pin quote failed');
      if (slowFirstPin) {
        final wait = pin = Completer<void>();
        await wait.future;
      }
    }
    return RideQuote(
      id: 'q-$rideType-$id-${atOrigin ? 'OLD' : 'NEW'}',
      rideType: rideType,
      totalMinor: base(rideType) + (atOrigin ? 0 : 4200),
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'signature',
    );
  }
}

class _CaptureBooking extends BookingController {
  final List<String> bookings = [];

  @override
  Future<String> submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = 'SEK',
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) async {
    bookings.add('$rideType $quoteId $price');
    throw StateError('stop here');
  }
}

/// rider-79: once the rider confirmed a moved pickup, every category is
/// booked with a quote priced at that pickup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  RideSelectionController selectionWith(QuoteRepository quotes) {
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: quotes,
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    return selection;
  }

  Future<void> pumpSelectRide(
    WidgetTester tester,
    RideSelectionController selection, {
    _CaptureBooking? booking,
    ReservationController? reservations,
    DateTime? scheduledFor,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: _origin,
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
          booking: booking,
          reservations: reservations,
          initialScheduledFor: scheduledFor,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> movePin(WidgetTester tester) async {
    expect(find.byType(SetPickupPage), findsOneWidget);
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(const CameraPosition(target: _moved, zoom: 16));
    map.onCameraIdle!();
    await tester.pump();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester, 40);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('another category is booked at the moved pickup\'s price', (
    tester,
  ) async {
    final quotes = _PickupQuotes(slowFirstPin: true);
    final selection = selectionWith(quotes);
    final booking = _CaptureBooking();
    await pumpSelectRide(tester, selection, booking: booking);

    await tester.tap(find.text('Select Movera'));
    await settle(tester, 30);
    await movePin(tester);
    expect(quotes.pin, isNotNull);
    // Confirm while the pin's price loads; it lands after Set pickup
    // closed and the rider says Not now.
    await confirm(tester);
    quotes.pin!.complete();
    await settle(tester);
    expect(
      find.byKey(const ValueKey('select-ride-price-updated')),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    await settle(tester, 20);
    expect(booking.bookings, isEmpty);

    await tester.tap(find.text('Comfort').first);
    await settle(tester);
    await tester.tap(find.text('Select Comfort'));
    await settle(tester, 30);
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.text('339 kr'), findsNothing);
    await confirm(tester);

    expect(booking.bookings, hasLength(1));
    expect(booking.bookings.single, startsWith('comfort '));
    expect(booking.bookings.single, contains('-NEW'));
    expect(booking.bookings.single, endsWith(' 381.0'));
    await close(tester);
  });

  testWidgets('a failed pin re-quote is priced again before booking', (
    tester,
  ) async {
    final quotes = _PickupQuotes(failFirstPin: true);
    final selection = selectionWith(quotes);
    final booking = _CaptureBooking();
    await pumpSelectRide(tester, selection, booking: booking);

    await tester.tap(find.text('Select Movera'));
    await settle(tester, 30);
    await movePin(tester);
    await settle(tester);
    // Set pickup keeps the old fare when its re-quote fails.
    expect(find.text('259 kr'), findsWidgets);
    await confirm(tester);

    expect(booking.bookings, isEmpty);
    expect(
      find.byKey(const ValueKey('select-ride-price-updated')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('select-ride-price-accept')));
    await settle(tester, 20);
    expect(booking.bookings, hasLength(1));
    expect(booking.bookings.single, startsWith('economy '));
    expect(booking.bookings.single, contains('-NEW'));
    expect(booking.bookings.single, endsWith(' 301.0'));
    await close(tester);
  });

  testWidgets('Book for later waits for the pin price of the moved pickup', (
    tester,
  ) async {
    final quotes = _PickupQuotes(slowFirstPin: true);
    final selection = selectionWith(quotes);
    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    await pumpSelectRide(
      tester,
      selection,
      reservations: reservations,
      scheduledFor: StockholmSchedule.clampPickup(
        StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
      ),
    );

    await tester.tap(find.text('Schedule Movera'));
    await settle(tester, 30);
    await movePin(tester);
    // Confirm while the pin's price is still loading.
    await confirm(tester);
    expect(reservations.all, isEmpty);
    quotes.pin!.complete();
    await settle(tester);
    expect(
      find.byKey(const ValueKey('select-ride-price-updated')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('select-ride-price-accept')));
    await settle(tester, 30);

    expect(reservations.all, hasLength(1));
    expect(reservations.all.single.price, 301);
    expect(reservations.all.single.pickup.lat, closeTo(_moved.latitude, 0.005));
    await close(tester);
  });
}

Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
