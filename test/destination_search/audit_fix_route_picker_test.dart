import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what Change route asks the geocoder; knows no address.
class _Geo implements GeocodingRepository {
  final List<String> asked = [];

  @override
  Future<PlaceResult?> forward(String query) async {
    asked.add(query);
    return null;
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// R4.9: Where to? / Change route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rider-u87: swapping the last stop and the destination keeps '
      'their booked points, so nothing is geocoded from text', (tester) async {
    const rideId = 'u87-ride';
    final server = InProcessMockClient();
    server.rides[rideId] = {
      'id': rideId,
      'status': 'driverAssigned',
      'pickupAddress': 'Sergels torg 1',
      'pickupLat': 59.3326,
      'pickupLng': 18.0649,
      'destinationAddress': 'Dropped pin · 59.34260° N',
      'destinationLat': 59.3426,
      'destinationLng': 18.0498,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    final geo = _Geo();
    final ride = RideSnapshot(
      status: RideStatus.driverAssigned,
      savedAt: DateTime(2026, 10, 21),
      pickupAddress: 'Sergels torg 1',
      destinationAddress: 'Dropped pin · 59.34260° N',
      pickupLat: 59.3326,
      pickupLng: 18.0649,
      destinationLat: 59.3426,
      destinationLng: 18.0498,
      stops: const [
        RouteStop(address: 'Hötorget 1', latitude: 59.3365, longitude: 18.0586),
      ],
      rideType: 'Movera',
      price: 200,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
    );
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openRouteChange(
              context,
              ride: ride,
              entry: RouteChangeEntry.destination,
              pickupLocked: true,
              controller: RouteChangeController(
                api: ApiClient(client: server),
                geocoding: geo,
              ),
            ),
            child: const Text('ride'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('route-picker-swap-stop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('route-picker-done')));
    final sheet = find.byType(RouteChangeSheet);
    for (var i = 0; i < 40 && sheet.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(geo.asked, isEmpty);
    expect(sheet, findsOneWidget);
  });
}
