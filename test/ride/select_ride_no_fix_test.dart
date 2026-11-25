import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_route_location_badge.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _ImmediateQuoteRepository implements QuoteRepository {
  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int? durationSeconds,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'quote-$rideType',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'signature',
    ),
  );
}

/// With no location fix, Home sends a placeholder pickup point to the
/// categories screen instead of the old map picker; Set location then opens
/// on that point with Confirm disabled until the rider moves the pin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('a pickup result is a real point unless it says otherwise', () {
    const real = PickupMapResult(
      address: 'Klockarvägen 37',
      position: LatLng(59.2390, 17.8450),
    );
    const placeholder = PickupMapResult(
      address: 'Location off, set pickup',
      position: LatLng(59.3293, 18.0686),
      isFallback: true,
    );
    expect(real.isFallback, isFalse);
    expect(placeholder.isFallback, isTrue);
  });

  testWidgets('a placeholder pickup opens Set location with Confirm off', (
    tester,
  ) async {
    final catalog = RideCatalogController(
      api: ApiClient(
        client: MockClient(
          // The server is down: the built-in categories are used.
          (_) async => http.Response(
            jsonEncode({'code': 'SERVER_ERROR', 'message': 'down'}),
            500,
          ),
        ),
      ),
      cache: MemoryRideCatalogCache(),
    );
    final selection = RideSelectionController(
      catalog: catalog,
      quotes: _ImmediateQuoteRepository(),
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Location off, set pickup',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          pickupIsFallback: true,
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SelectRide), findsOneWidget);

    await tester.tap(find.text('Select Movera'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(SetPickupPage), findsOneWidget);
    final page = tester.widget<SetPickupPage>(find.byType(SetPickupPage));
    expect(page.positionIsFallback, isTrue);
    expect(page.initialIsCurrentLocation, isFalse);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('set-pickup-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text('Your current location'), findsNothing);

    // Let Set location's address lookup (8 s timeout) finish.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
  });
}
