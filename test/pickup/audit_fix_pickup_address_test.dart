import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// A reverse geocoder the test answers by hand; unanswered lookups never
/// complete.
class _HandGeocoder extends AppGeocoding {
  final List<Completer<String?>> lookups = [];

  @override
  Future<String?> reverseGeocodeAddress(double latitude, double longitude) {
    final c = Completer<String?>();
    lookups.add(c);
    return c.future;
  }
}

/// RIDE-12 / AUD-2: Confirm on Set pickup books the pin's own street, or a
/// labelled dropped pin, never the previous street or "Pickup location".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const start = LatLng(59.3293, 18.0686);
  const moved = LatLng(59.3100, 18.0686);

  Future<Future<SetPickupResult?>> open(
    WidgetTester tester,
    _HandGeocoder geocoder, {
    String initialAddress = 'Klockarvägen 37',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Future<SetPickupResult?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = Navigator.of(context).push<SetPickupResult>(
                  MaterialPageRoute(
                    builder: (_) => SetPickupPage(
                      initialPosition: start,
                      initialAddress: initialAddress,
                      destinationAddress: 'Arlanda',
                      destinationPosition: const LatLng(59.6519, 17.9186),
                      ride: const SetPickupRide(
                        name: 'Movera',
                        image: 'missing.png',
                        seats: 4,
                        etaMin: 5,
                        tripMinutes: 40,
                      ),
                      fare: const SetPickupFare(totalKr: 259),
                      payment: const SetPickupPayment(
                        brand: 'cash',
                        name: 'Cash',
                        detail: '',
                      ),
                      brandMark: (_) => const SizedBox(),
                      geocoding: geocoder,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('set-pickup-map')), findsOneWidget);
    return Future.value(result);
  }

  Future<void> dragPinTo(WidgetTester tester, LatLng target) async {
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(CameraPosition(target: target, zoom: 16));
    map.onCameraIdle!();
    await tester.pump();
  }

  testWidgets('Confirm right after a drag waits, then books a dropped pin, '
      'not the previous street', (tester) async {
    final geocoder = _HandGeocoder();
    final result = await open(tester, geocoder);
    await dragPinTo(tester, moved);
    expect(geocoder.lookups, isNotEmpty);

    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await tester.pump();
    // Still on Set pickup, waiting for the address.
    expect(
      find.byKey(const ValueKey('set-pickup-confirm-waiting')),
      findsOneWidget,
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final picked = await result;
    expect(picked, isNotNull);
    expect(picked!.address, isNot('Klockarvägen 37'));
    expect(picked.address, isNot(pickupLocationFallbackLabel));
    expect(picked.address, droppedPinPickupAddress(picked.position));
    expect(picked.address, startsWith('Dropped pin'));
    expect(picked.position.latitude, isNot(closeTo(start.latitude, 0.001)));
  });

  testWidgets('Confirm during the lookup books the street once it answers', (
    tester,
  ) async {
    final geocoder = _HandGeocoder();
    final result = await open(tester, geocoder);
    await dragPinTo(tester, moved);

    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await tester.pump();
    geocoder.lookups.last.complete('Tingsvägen 4, Alby');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final picked = await result;
    expect(picked!.address, 'Tingsvägen 4, Alby');
  });

  testWidgets('a lookup that fails for "Current location" books a dropped pin, '
      'not "Pickup location"', (tester) async {
    final geocoder = _HandGeocoder();
    final result = await open(
      tester,
      geocoder,
      initialAddress: 'Current location',
    );
    expect(geocoder.lookups, isNotEmpty);
    geocoder.lookups.last.complete(null);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final picked = await result;
    expect(picked!.address, droppedPinPickupAddress(start));
  });

  test('the dropped-pin label survives the short place label', () {
    final label = droppedPinPickupAddress(const LatLng(59.31, 18.0686));
    expect(label, 'Dropped pin · 59.31000° N 18.06860° E');
    expect(label.contains(','), isFalse);
  });
}
