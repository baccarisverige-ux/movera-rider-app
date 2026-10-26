import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

class _Geocoder extends AppGeocoding {
  @override
  Future<String?> reverseGeocodeAddress(double latitude, double longitude) =>
      Completer<String?>().future;
}

/// rider-r5-9: a scheduled ride's arrival is the trip's real time after
/// the pickup in its zone, so it holds across a clock change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('01:50 + 30 min on spring-forward night arrives 03:20', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SetPickupPage(
          initialPosition: const LatLng(59.3293, 18.0686),
          initialAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda',
          destinationPosition: const LatLng(59.6519, 17.9186),
          ride: const SetPickupRide(
            name: 'Movera',
            image: 'missing.png',
            seats: 4,
            etaMin: 5,
            tripMinutes: 30,
          ),
          fare: const SetPickupFare(totalKr: 259),
          payment: const SetPickupPayment(
            brand: 'cash',
            name: 'Cash',
            detail: '',
          ),
          brandMark: (_) => const SizedBox(),
          geocoding: _Geocoder(),
          // The pickup zone's wall clock (ZoneClock), Stockholm.
          scheduledPickup: DateTime.utc(2026, 3, 29, 1, 50),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Arrive 03:20'), findsWidgets);
  });
}
