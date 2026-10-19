import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Batch 9 Phase 99 — U6 (stale picker position), D-010 (raw coordinates
/// shown as the pickup), D-011 (picker freshness, radius lag, pin tip).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const point = LatLng(59.4032, 17.9447);

  group('D-010: never surface raw coordinates', () {
    test('confirming "Current location" gives a readable fallback', () {
      expect(
        confirmedPickupAddress('Current location', point),
        'Pickup location',
      );
      expect(confirmedPickupAddress('', point), 'Pickup location');
      expect(
        confirmedPickupAddress('59.403200, 17.944700', point),
        'Pickup location',
      );
      expect(confirmedPickupAddress('Sveavägen 1', point), 'Sveavägen 1');
    });

    test(
      'a coordinate string from the reverse-geocoder is not an address',
      () async {
        final label = await bookingPickupAddress(
          label: 'Current location',
          position: point,
          reverse: (_) async => '59.403200, 17.944700',
        );
        expect(label, pickupLocationFallbackLabel);
        final failed = await bookingPickupAddress(
          label: 'Current location',
          position: point,
          reverse: (_) => throw StateError('offline'),
        );
        expect(failed, pickupLocationFallbackLabel);
      },
    );
  });

  group('U6: the picker opens where the rider is now', () {
    final home = File(
      'lib/features/home/presentation/home.dart',
    ).readAsStringSync();
    final picker = home.substring(
      home.indexOf('Future<PickupMapResult?> _openPickupMapPicker('),
      home.indexOf('Future<void> _showRouteAddressPicker('),
    );

    test('the stored GPS / pin label is never forward-geocoded', () {
      expect(picker, contains('cleanAddress != storedLabel'));
      expect(picker, contains('if (typedByRider || isDestination)'));
      expect(picker, contains('!isUnusablePickupLabel(cleanAddress)'));
    });

    test('a GPS-seeded picker asks for a fresh fix', () {
      expect(picker, contains('refreshCurrentLocation: chosen == null'));
    });

    test('the booking pickup is cleared when the booking flow ends', () {
      final parked = home.substring(
        home.indexOf('Future<T?> _withParkedHomeMap<T>('),
        home.indexOf('Future<PickupMapResult?> _openPickupMapPicker('),
      );
      expect(parked, contains('_tripPickupLatLng = null;'));
    });
  });

  group('D-011: picker geometry', () {
    test('the pin tip sits on the map centre', () {
      // Icons.location_on's tip is at y = 22/24 of its box. Centred inside
      // (size + padding), the tip lands at the centre only with this padding.
      const size = ConfirmPickupSpot.pinSize;
      const padding = ConfirmPickupSpot.pinTipPadding;
      final tipFromCentre = -(size + padding) / 2 + size * 22 / 24;
      expect(tipFromCentre.abs(), lessThan(0.01));
      expect(padding, isNot(28));
    });

    test('the radius overlay scales with zoom like the map does', () {
      final z16 = ConfirmPickupSpot.metersToPixels(90, 59.33, 16);
      final z17 = ConfirmPickupSpot.metersToPixels(90, 59.33, 17);
      expect(z17 / z16, closeTo(2, 0.0001));
      // ~90 m at z16 in Stockholm is a few tens of pixels.
      expect(z16, inInclusiveRange(20, 80));
    });

    testWidgets(
      'the radius is a screen-centred overlay, not a lagging map circle',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(
            home: ConfirmPickupSpot(
              initialPosition: point,
              initialAddress: 'Current location',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        // The map mounts once the route has settled.
        await tester.pump();
        await tester.pump();
        final map = tester.widget<CustomGoogleMap>(
          find.byType(CustomGoogleMap),
        );
        expect(map.circles ?? const <Circle>{}, isEmpty);
        // The flat ring and centre pin need a flat camera: no zoom tilt here.
        expect(map.tiltWithZoom, isFalse);
        final overlay = find.byKey(const ValueKey('pickup-accuracy-overlay'));
        expect(overlay, findsOneWidget);
        expect(
          tester.getCenter(overlay),
          tester.getCenter(find.byType(CustomGoogleMap)),
        );
        expect(find.byKey(const ValueKey('pickup-pin')), findsOneWidget);
      },
    );
  });
}
