import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every ride costs 412 kr. The first round of quotes lives [firstTtl],
/// later ones five minutes, on the server clock (as the app judges them).
class _ShortQuotes implements QuoteRepository {
  _ShortQuotes(this.firstTtl);

  final Duration firstTtl;
  final Set<String> _quoted = {};
  int calls = 0;

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
    final first = _quoted.add(rideType);
    return RideQuote(
      id: 'q-$rideType-$calls',
      rideType: rideType,
      totalMinor: 41200,
      currency: 'SEK',
      expiresAt: ServerClock.now().add(
        first ? firstTtl : const Duration(minutes: 5),
      ),
      signedPayload: 'signature',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('rider-u185: an expired quote', () {
    test('is not replaced by the list price as the fare', () {
      final selection = RideSelectionController(
        store: RideSelectionRepository(),
        quotes: CatalogQuoteRepository(),
        flags: FeatureFlags(),
      );
      final t0 = DateTime.now();
      selection.adoptQuote(
        'economy',
        RideQuote(
          id: 'q1',
          rideType: 'economy',
          totalMinor: 41200,
          currency: 'SEK',
          expiresAt: t0.add(const Duration(minutes: 2)),
          signedPayload: 'mock-api',
        ),
      );
      expect(selection.hasPriceFor('economy', catalogCurrency: 'SEK'), isTrue);
      expect(selection.priceFor('economy', 259, now: t0), 412);

      final later = t0.add(const Duration(minutes: 2, seconds: 1));
      selection.priceFor('economy', 259, now: later);
      expect(selection.hasPriceFor('economy', catalogCurrency: 'SEK'), isFalse);
      // Tapping the row does not make the list price its fare either.
      selection.selectRide('economy', 259, catalogCurrency: 'SEK');
      expect(selection.hasPriceFor('economy', catalogCurrency: 'SEK'), isFalse);

      selection.adoptQuote(
        'economy',
        RideQuote(
          id: 'q2',
          rideType: 'economy',
          totalMinor: 41500,
          currency: 'SEK',
          expiresAt: later.add(const Duration(minutes: 2)),
          signedPayload: 'mock-api',
        ),
      );
      expect(selection.hasPriceFor('economy', catalogCurrency: 'SEK'), isTrue);
      expect(selection.priceFor('economy', 259, now: later), 415);
    });

    testWidgets('Select Ride shows no list price and prices the ride again', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(ServerClock.reset);
      final quotes = _ShortQuotes(const Duration(minutes: 10));
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
      await tester.pumpWidget(
        MaterialApp(
          home: SelectRide(
            pickupAddress: 'Klockarvägen 37',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.6519, 17.9186),
            selection: selection,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('412 kr'), findsWidgets);
      expect(find.text('259 kr'), findsNothing);
      final firstRound = quotes.calls;

      // The quotes run out while the rider looks at the list: the server
      // clock moves 11 minutes on (not the real clock, so a slow machine
      // cannot spend them early), before the expiry timer has fired.
      final server = DateTime.utc(2026, 10, 22, 12);
      ServerClock.observeDateHeader(
        HttpDate.format(server),
        receivedAt: server.subtract(const Duration(minutes: 11)),
      );
      expect(ServerClock.offset, const Duration(minutes: 11));
      expect(quotes.calls, firstRound, reason: 'nothing re-priced yet');
      await tester.tap(find.text('Comfort').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('259 kr'), findsNothing);
      expect(find.text('339 kr'), findsNothing);

      // Priced again at expiry (the expiry timer), without a tap on Book.
      await tester.pump(const Duration(minutes: 10));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(quotes.calls, greaterThan(firstRound));
      expect(find.text('412 kr'), findsWidgets);
      expect(find.text('259 kr'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });

  test('rider-r4-29: a spent quote or one of a removed category never '
      'holds up the next expiry re-quote', () async {
    final selection = RideSelectionController(
      store: RideSelectionRepository(),
      quotes: CatalogQuoteRepository(),
      flags: FeatureFlags(),
    );
    final t0 = DateTime.now();
    RideQuote quote(String id, Duration ttl) => RideQuote(
      id: 'q-$id',
      rideType: id,
      totalMinor: 41200,
      currency: 'SEK',
      expiresAt: t0.add(ttl),
      signedPayload: 'signed',
    );
    final first = selection.rides().first.id;
    selection.adoptQuote(first, quote(first, const Duration(minutes: 2)));
    selection.adoptQuote('retired', quote('retired', const Duration(minutes: 1)));
    final later = t0.add(const Duration(minutes: 3));
    // Back from a booking flow that outlasted the quote: it is spent.
    expect(selection.discardExpiredQuotes(now: later), isTrue);
    expect(selection.nextQuoteExpiry, isNull);
    expect(selection.discardExpiredQuotes(now: later), isFalse);

    // A category the catalog no longer has loses its quote on the next load.
    selection.adoptQuote('retired', quote('retired', const Duration(minutes: 1)));
    await selection.loadQuotes(
      generation: selection.beginQuotes(),
      pickup: 'A',
      destination: 'B',
    );
    expect(selection.expiryFor('retired'), isNull);
  });
}
