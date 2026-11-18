import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Follow-up to #641 (owner 2026-11-18, option A "Empty price + Try
/// again"): a price request that fails left the tile's '…' loader on
/// screen for good, and a failure that is not retryable never offered
/// "Try again". Now a failed price shows no price and "Try again".
class _RefusedQuotes implements QuoteRepository {
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
    throw const ApiError(
      code: 'invalid_request',
      message: 'Refused.',
      statusCode: 400,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.promotion.value = null;
    // A live build shows only server prices: with no quote the tile
    // shows its loader, as a zone row without a list price does (#641).
    LiveDataOnly.on = true;
  });
  tearDown(() {
    LiveDataOnly.on = false;
    AppScope.instance.promotion.value = null;
  });

  testWidgets('a failed price hides the loader and offers Try again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quotes = _RefusedQuotes();
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(quotes.calls, greaterThan(0));
    expect(find.text('…'), findsNothing);
    final retry = find.byKey(const ValueKey('select-ride-quotes-retry'));
    expect(retry, findsOneWidget);

    // Try again asks for the prices again.
    final before = quotes.calls;
    await tester.tap(retry);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(quotes.calls, greaterThan(before));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
