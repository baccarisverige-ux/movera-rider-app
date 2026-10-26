import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-04 + UI-08: a stop that could not be geocoded was dropped from the
/// quote and the booking without a word, and neither Select ride nor Set
/// pickup showed the stops at all, so the rider could not notice.
class _Geocoder implements GeocodingRepository {
  _Geocoder({this.failFirst = false});
  bool failFirst;
  final queries = <String>[];

  @override
  Future<PlaceResult?> forward(String query) async {
    queries.add(query);
    if (query.startsWith('Qwxzv')) return null;
    if (failFirst && query.startsWith('KTH')) {
      failFirst = false;
      throw StateError('offline');
    }
    return PlaceResult(address: query, point: const GeoPoint(59.35, 18.07));
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class _Quotes implements QuoteRepository {
  final stopsSeen = <List<String>>[];

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
    stopsSeen.add([for (final s in stops) s.address]);
    return RideQuote(
      id: 'q-$rideType-${stopsSeen.length}',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  RideSelectionController selectionWith(QuoteRepository quotes) {
    final catalog = RideCatalogController(
      api: ApiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
        ),
      ),
      cache: MemoryRideCatalogCache(),
    );
    return RideSelectionController(catalog: catalog, quotes: quotes);
  }

  Future<void> pumpSelectRide(
    WidgetTester tester, {
    required List<String> stops,
    required _Geocoder geocoder,
    required _Quotes quotes,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = selectionWith(quotes);
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          stops: stops,
          geocoding: geocoder,
          selection: selection,
          booking: BookingController(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a stop that cannot be found is named, not silently dropped', (
    tester,
  ) async {
    final quotes = _Quotes();
    await pumpSelectRide(
      tester,
      stops: const ['Odenplan, Stockholm', 'Qwxzv Plats 999'],
      geocoder: _Geocoder(),
      quotes: quotes,
    );

    expect(
      find.byKey(const ValueKey('select-ride-stops-left-out')),
      findsOneWidget,
    );
    expect(find.textContaining('“Qwxzv Plats 999”'), findsOneWidget);
    expect(quotes.stopsSeen.last, ['Odenplan, Stockholm']);

    // UI-08: the stop that is priced shows in the header and on the map.
    expect(find.text('via Odenplan'), findsOneWidget);
    final map = find.byKey(const ValueKey('select-ride-map'));
    if (map.evaluate().isNotEmpty) {
      final markers = tester.widget<CustomGoogleMap>(map).markers;
      expect(markers!.map((m) => m.markerId.value), contains('stop-0'));
    }

    // And on Set pickup.
    await tester.tap(find.text('Select Movera'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-via-stops')), findsOneWidget);
    expect(find.text('via Odenplan'), findsWidgets);
  });

  testWidgets('a failed stop lookup can be retried and re-priced', (
    tester,
  ) async {
    final quotes = _Quotes();
    final geocoder = _Geocoder(failFirst: true);
    await pumpSelectRide(
      tester,
      stops: const ['KTH, Stockholm'],
      geocoder: geocoder,
      quotes: quotes,
    );
    expect(find.textContaining("Couldn't look up the stop"), findsOneWidget);
    expect(quotes.stopsSeen.last, isEmpty);

    await tester.tap(find.byKey(const ValueKey("select-ride-stops-retry")));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(geocoder.queries.where((q) => q.startsWith('KTH')).length, 2);
    expect(quotes.stopsSeen.last, ['KTH, Stockholm']);
    expect(find.text('via KTH'), findsOneWidget);
  });
}
