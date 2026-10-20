import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _ImmediateQuoteRepository implements QuoteRepository {
  final requested = <String>[];

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
  }) {
    requested.add(rideType);
    return Future<RideQuote>.value(
      RideQuote(
        id: 'remote-quote-$rideType',
        rideType: rideType,
        totalMinor: rideType == 'shuttle' ? 44900 : 25900,
        currency: 'SEK',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        signedPayload: 'remote-signature',
      ),
    );
  }
}

/// A server catalog with a category the app does not ship with.
const _serverRows = [
  {
    'id': 'economy',
    'name': 'Movera',
    'seats': 4,
    'etaMin': 8,
    'price': 259,
    'description': 'Affordable and convenient rides',
    'badge': 'RECOMMENDED',
    'imageKey': 'economy',
    'order': 1,
    'enabled': true,
  },
  {
    'id': 'shuttle',
    'name': 'Shuttle',
    'seats': 8,
    'etaMin': 14,
    'price': 449,
    'description': 'Shared shuttle rides',
    'imageKey': 'xl',
    'order': 2,
    'enabled': true,
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('a category that is not built in shows up from the server', (
    tester,
  ) async {
    expect(
      RideSelectionRepository.builtInRides.any((ride) => ride.id == 'shuttle'),
      isFalse,
    );

    final catalog = RideCatalogController(
      api: ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'OK', 'rideTypes': _serverRows}),
            200,
          ),
        ),
      ),
      cache: MemoryRideCatalogCache(),
    );
    final quotes = _ImmediateQuoteRepository();
    final selection = RideSelectionController(catalog: catalog, quotes: quotes);

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    // The built-in list shows at once; the server answer rebuilds the sheet.
    expect(find.text('Shuttle'), findsNothing);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(catalog.source, RideCatalogSource.server);
    expect(selection.rides().map((ride) => ride.id), ['economy', 'shuttle']);
    expect(find.text('Shuttle'), findsWidgets);
    expect(find.text('Shared shuttle rides'), findsWidgets);
    expect(find.text('Comfort'), findsNothing);
    // The new category was quoted too, so it can be booked.
    expect(quotes.requested, contains('shuttle'));
    expect(selection.quoteIsAvailable('shuttle'), isTrue);

    await tester.tap(find.text('Shuttle').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selection.selectedRideId, 'shuttle');
    expect(selection.authoritativePriceFor('shuttle'), 449);
  });
}
