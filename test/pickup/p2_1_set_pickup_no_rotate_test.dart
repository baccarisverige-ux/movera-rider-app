// P2-1 (finder C pass 2, 2026-11-07, fail-before on main): Set pickup let
// the rider rotate the map, but the pickup under the pin is worked out as
// "N px due north of the camera centre" (setPickupPointAbove never sees the
// camera bearing). At bearing 20 / 90 / 180 the saved pickup was 28.5 /
// 116.2 / 164.3 m from the pin (finder C's maths test). Fix: the Set pickup
// map cannot be rotated, so the bearing stays 0, where the maths is right.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

class _SilentGeocoder extends AppGeocoding {
  @override
  Future<String?> reverseGeocodeAddress(double latitude, double longitude) =>
      Completer<String?>().future;
}

double _meters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final x = dLng * math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  return r * math.sqrt(x * x + dLat * dLat);
}

/// The ground point [px] screen pixels above the centre of a flat map
/// whose camera has [bearing] (degrees clockwise from north at screen-up).
LatLng _underPin(LatLng target, double zoom, double px, double bearing) {
  final mpp =
      156543.03392 *
      math.cos(target.latitude * math.pi / 180) /
      math.pow(2, zoom);
  final d = px * mpp;
  final b = bearing * math.pi / 180;
  final north = d * math.cos(b), east = d * math.sin(b);
  return LatLng(
    target.latitude + north / 111320.0,
    target.longitude +
        east / (111320.0 * math.cos(target.latitude * math.pi / 180)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('P2-1: the Set pickup map cannot be rotated', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SetPickupPage(
          initialPosition: const LatLng(59.3326, 18.0649),
          initialAddress: 'Drottninggatan 1',
          destinationAddress: 'Odenplan',
          destinationPosition: const LatLng(59.3429, 18.0496),
          ride: const SetPickupRide(
            name: 'Movera',
            image: 'missing.png',
            seats: 4,
            etaMin: 5,
            tripMinutes: 12,
          ),
          fare: const SetPickupFare(totalKr: 226),
          payment: const SetPickupPayment(
            brand: 'cash',
            name: 'Cash',
            detail: '',
          ),
          brandMark: (_) => const SizedBox(),
          geocoding: _SilentGeocoder(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    expect(map.rotateGesturesEnabled, isFalse);
    // Flat and north-up: the two things setPickupPointAbove assumes.
    expect(map.tiltWithZoom, isFalse);
    expect(map.initialPosition?.bearing, 0);
  });

  // Finder C's maths check, at the only bearing Set pickup can now have.
  test('P2-1: at bearing 0 the saved pickup is the point under the pin', () {
    const height = 844.0;
    const px = height / 2 - height * SetPickupPage.pinFraction;
    const camera = LatLng(59.3326, 18.0649);
    const zoom = 17.0;
    final saved = setPickupPointAbove(camera, zoom, px);
    final off = _meters(saved, _underPin(camera, zoom, px, 0));
    expect(
      off,
      lessThan(3),
      reason: 'saved pickup is ${off.toStringAsFixed(1)} m from the pin',
    );
  });
}
