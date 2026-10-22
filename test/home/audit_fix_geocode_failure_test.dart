import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';

/// Offline: every forward geocode throws, as ApiClient does on NETWORK,
/// TIMEOUT or an HTTP error.
class _OfflineGeo extends AppGeocoding {
  @override
  Future<PlaceResult?> forward(String address) async =>
      throw StateError('NETWORK');
}

/// rider-45: a failed forward geocode must not escape as an unhandled
/// error from Home's route flows (route picker, saved place, address sheet).
void main() {
  late HomeLocationController ctl;

  setUp(() {
    ctl = HomeLocationController(
      location: LocationRepository(),
      geocoding: _OfflineGeo(),
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );
  });
  tearDown(() => ctl.dispose());

  test('normalising keeps the rider\'s text when the lookup fails', () async {
    final batch = ctl.beginNormalisationBatch();
    final route = await Future.wait([
      ctl.normaliseAddress('Stockholm Central', generation: batch),
      ctl.normaliseAddress('Arlanda Airport', generation: batch),
    ]);
    expect(route, ['Stockholm Central', 'Arlanda Airport']);
  });

  test('a saved place or typed pickup that cannot be looked up resolves to '
      'nothing instead of throwing', () async {
    final place = await ctl.resolvePlace('Arlanda Airport');
    expect(place.valueOrNull, isNull);
    final point = await ctl.resolveLatLng('Kungsgatan 1');
    expect(point.valueOrNull, isNull);
    expect(await ctl.geocodeLatLng('Kungsgatan 1'), isNull);
  });

  test(
    'the outcome says the lookup failed, not that nothing was found',
    () async {
      expect(
        await ctl.resolvePlace('Arlanda Airport'),
        isA<GeocodeFailed<({LatLng point, String address})>>(),
      );
      expect(
        await ctl.resolveLatLng('Kungsgatan 1'),
        isA<GeocodeFailed<LatLng>>(),
      );
    },
  );

  test('pickup search treats a failed lookup as not found', () async {
    final pickup = PickupMapController(
      location: LocationRepository(),
      geocoding: _OfflineGeo(),
    );
    expect(await pickup.search('Kungsgatan 1'), isNull);
    pickup.dispose();
  });
}
