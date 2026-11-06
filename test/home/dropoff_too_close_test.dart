import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same-address fix (contract v0.18.42 §67): the server refuses the quote
/// with 400 invalid_request reason dropoff_too_close; the rider reads "Drop-off
/// is too close to pickup" and is back on the destination step (Select ride
/// closes with no result: Home reopens the address screen on the destination).
class _Geocoder implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async =>
      PlaceResult(address: query, point: const GeoPoint(59.36, 18.0));
  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class _TooClose implements QuoteRepository {
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
  }) async => throw const ApiError(
    code: 'invalid_request',
    message: 'Drop-off is too close to pickup.',
    statusCode: 400,
    reason: 'dropoff_too_close',
    details: ['meters=48', 'limitMeters=300'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'dropoff_too_close: the message shows and Select ride closes to the destination step',
    (tester) async {
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
        quotes: _TooClose(),
        flags: FeatureFlags(),
      );
      addTearDown(selection.dispose);
      Object? popped = 'still open';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<Object?>(
                      MaterialPageRoute(
                        builder: (_) => SelectRide(
                          pickupAddress: 'Solnavägen 13, 171 45 Solna, Sverige',
                          destinationAddress:
                              'Solna Centrum, Solnavägen, Solna, Sverige',
                          pickupPosition: const LatLng(59.36, 18.0),
                          destinationPosition: const LatLng(
                            59.3596729,
                            18.0005394,
                          ),
                          stops: const <String>[],
                          geocoding: _Geocoder(),
                          selection: selection,
                        ),
                      ),
                    );
                  },
                  child: const Text('destination step'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('destination step'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Drop-off is too close to pickup'), findsOneWidget);
      expect(find.byType(SelectRide), findsNothing);
      expect(popped, isNull);
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
