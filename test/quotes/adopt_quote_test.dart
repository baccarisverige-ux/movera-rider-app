import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/straight_line.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

void main() {
  RideSelectionController controller() => RideSelectionController(
    store: RideSelectionRepository(),
    quotes: CatalogQuoteRepository(),
  );

  group('adoptQuote', () {
    test('makes the quote authoritative for that ride, as a load would', () {
      final selection = controller();
      final now = DateTime(2026, 10, 13, 12);
      selection.unavailableQuoteIds.add('economy');
      selection.offeredPrices['economy'] = 259;

      final quote = RideQuote(
        id: 'q_movera_pin',
        rideType: 'economy',
        totalMinor: 30100,
        currency: 'SEK',
        expiresAt: now.add(const Duration(minutes: 2)),
        discountMinor: 4000,
        signedPayload: 'mock-api',
      );
      selection.adoptQuote('economy', quote);

      expect(selection.offeredPrices['economy'], 301);
      expect(selection.quoteIds['economy'], 'q_movera_pin');
      expect(selection.quoteExpiresAt['economy'], quote.expiresAt);
      expect(selection.authoritativeQuotes['economy'], same(quote));
      expect(selection.unavailableQuoteIds, isNot(contains('economy')));
      expect(selection.quoteIsAvailable('economy', now: now), isTrue);
      expect(selection.authoritativePriceFor('economy', now: now), 301);
      expect(selection.quoteForBooking('economy', now: now), same(quote));
    });

    test('touches only that ride', () {
      final selection = controller();
      selection.offeredPrices['comfort'] = 339;
      selection.unavailableQuoteIds.add('comfort');
      selection.adoptQuote(
        'economy',
        RideQuote(
          id: 'q1',
          rideType: 'economy',
          totalMinor: 25900,
          currency: 'SEK',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          signedPayload: 'mock-api',
        ),
      );
      expect(selection.offeredPrices['comfort'], 339);
      expect(selection.unavailableQuoteIds, contains('comfort'));
    });

    test('does nothing after dispose', () {
      final selection = controller()..dispose();
      selection.adoptQuote(
        'economy',
        RideQuote(
          id: 'q1',
          rideType: 'economy',
          totalMinor: 25900,
          currency: 'SEK',
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
      );
      expect(selection.offeredPrices, isEmpty);
    });
  });

  group('demo quote prices by distance', () {
    ApiQuoteRepository repo() =>
        ApiQuoteRepository(api: ApiClient(client: InProcessMockClient()));

    test('a 3 km trip is the catalog price', () async {
      final quote = await repo().quote(
        rideType: 'economy',
        distanceMeters: 3000,
      );
      expect(quote.totalMinor, 25900);
      expect(quote.baseMinor, 25900);
      expect(quote.distanceMinor, 0);
    });

    test('longer trips cost 12 kr per extra kilometre', () async {
      final quote = await repo().quote(
        rideType: 'economy',
        distanceMeters: 13000,
      );
      expect(quote.totalMinor, 37900);
      expect(quote.baseMinor, 25900);
      expect(quote.distanceMinor, 12000);
      final nextKm = await repo().quote(
        rideType: 'economy',
        distanceMeters: 4000,
      );
      expect(nextKm.totalMinor, 27100);
    });

    test(
      'shorter trips cost less, never below 60% of the catalog price',
      () async {
        final short = await repo().quote(
          rideType: 'economy',
          distanceMeters: 1000,
        );
        expect(short.totalMinor, 23500);
        final tiny = await repo().quote(rideType: 'economy', distanceMeters: 1);
        expect(tiny.totalMinor, 22300);
        final xl = await repo().quote(rideType: 'xl', distanceMeters: 1);
        // 399 - 36 = 363 is above the 60% floor (239), so the slope applies.
        expect(xl.totalMinor, 36300);
      },
    );

    test('moving the pin a few hundred metres changes the price', () async {
      const destination = LatLng(59.6519, 17.9186);
      const pin = LatLng(59.3293, 18.0686);
      const movedPin = LatLng(59.3250, 18.0686);
      final before = await repo().quote(
        rideType: 'economy',
        distanceMeters: straightLineMeters(pin, destination),
      );
      final after = await repo().quote(
        rideType: 'economy',
        distanceMeters: straightLineMeters(movedPin, destination),
      );
      expect(after.totalMinor, greaterThan(before.totalMinor));
    });
  });

  test('straightLineMeters is the haversine distance', () {
    expect(straightLineMeters(const LatLng(0, 0), const LatLng(0, 0)), 1);
    // One degree of latitude is about 111.2 km.
    expect(
      straightLineMeters(const LatLng(59, 18), const LatLng(60, 18)),
      closeTo(111195, 50),
    );
    expect(
      straightLineMeters(
        const LatLng(59.3293, 18.0686),
        const LatLng(59.6519, 17.9186),
      ),
      closeTo(36900, 500),
    );
  });
}
