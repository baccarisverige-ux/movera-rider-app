import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_category_gate.dart';

class _Offline extends AppGeocoding {
  @override
  Future<PlaceResult?> geocodeAddress(String address) async =>
      throw StateError('offline');
}

class _NotFound extends AppGeocoding {
  @override
  Future<PlaceResult?> geocodeAddress(String address) async => null;
}

/// rider-r5-23: Book for later tells a failed address lookup apart from an
/// address that was not found.
void main() {
  test('a failed lookup is not "not found"', () async {
    expect(
      await findScheduledPoint('Arlanda Terminal 5', geocoding: _NotFound()),
      isNull,
    );
    await expectLater(
      findScheduledPoint('Arlanda Terminal 5', geocoding: _Offline()),
      throwsA(isA<ScheduledPointLookupFailed>()),
    );
  });
}
