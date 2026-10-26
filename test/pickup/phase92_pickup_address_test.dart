import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';
import 'package:movera_rider/core/location/location_repository.dart';

const _point = LatLng(59.3293, 18.0686);

class _Geocoder extends AppGeocoding {
  String? next;
  bool fail = false;
  int calls = 0;

  @override
  Future<String?> reverse(GeoPoint point) async {
    calls++;
    if (fail) throw StateError('temporary geocode failure');
    return next;
  }
}

void main() {
  test('booking keeps a real address without asking geocoder', () async {
    final actual = await bookingPickupAddress(
      label: '  Sveavägen 1  ',
      position: _point,
      reverse: (_) => throw StateError('must not call'),
    );
    expect(actual, 'Sveavägen 1');
  });

  test(
    'booking resolves UI label, and falls back to coordinates on failure',
    () async {
      final address = await bookingPickupAddress(
        label: 'Current location',
        position: _point,
        reverse: (_) async => 'Stockholm, Sweden',
      );
      expect(address, 'Stockholm, Sweden');
      final fallback = await bookingPickupAddress(
        label: 'Current location',
        position: _point,
        reverse: (_) => throw StateError('offline'),
      );
      expect(fallback, pickupLocationFallbackLabel);
    },
  );

  test('map confirmation returns coordinates immediately for the UI label', () {
    expect(
      confirmedPickupAddress('Current location', _point),
      pickupLocationFallbackLabel,
    );
  });

  test(
    'pickup reverse recovers after an error and never remembers null',
    () async {
      final geo = _Geocoder()..fail = true;
      final controller = PickupMapController(
        location: LocationRepository(),
        geocoding: geo,
      );
      expect(await controller.reverse(_point), isNull);
      expect(controller.resolving, isFalse);
      geo.fail = false;
      expect(await controller.reverse(_point), isNull);
      expect(controller.resolving, isFalse);
      geo.next = 'Sveavägen 1';
      expect(await controller.reverse(_point), 'Sveavägen 1');
      controller.dispose();
    },
  );
}
