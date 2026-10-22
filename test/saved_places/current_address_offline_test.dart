import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/saved_places/application/current_address.dart';
import 'package:movera_rider/l10n/l10n.dart';

class _Here extends LocationRepository {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      Position(
        latitude: 59.33,
        longitude: 18.06,
        timestamp: DateTime.utc(2026, 10, 22),
        accuracy: 4,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

/// rider-r5-38: a street lookup that fails is a connection problem, not
/// "no address for where you are".
void main() {
  test('a failed lookup says check your connection', () async {
    await expectLater(
      resolveCurrentAddress(
        location: _Here(),
        reverse: (_) async => throw StateError('offline'),
      ),
      throwsA(isA<CurrentAddressException>().having(
        (e) => e.message,
        'message',
        L10n.current.apiUnreachable,
      )),
    );
  });
}
