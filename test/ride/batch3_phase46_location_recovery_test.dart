import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';

class _Geo extends AppGeocoding {}

class _Location extends LocationRepository {
  _Location({
    this.enabled = true,
    this.permission = LocationPermission.whileInUse,
    this.error,
  });

  bool enabled;
  LocationPermission permission;
  Object? error;
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests += 1;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (error != null) throw error!;
    return Position(
      latitude: 59.33,
      longitude: 18.06,
      timestamp: DateTime.utc(2026, 9, 24),
      accuracy: 4,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Home distinguishes disabled services from denied permission', () async {
    final disabled = HomeLocationController(
      location: _Location(enabled: false),
      geocoding: _Geo(),
      motion: MotionEngine(),
    );
    final disabledResult = await disabled.detectCurrent();
    expect(disabledResult.failure, HomeLocationFailure.servicesDisabled);
    expect(disabledResult.target, isNull);
    disabled.dispose();

    final deniedLocation = _Location(permission: LocationPermission.denied);
    final denied = HomeLocationController(
      location: deniedLocation,
      geocoding: _Geo(),
      motion: MotionEngine(),
    );
    final deniedResult = await denied.detectCurrent();
    expect(deniedResult.failure, HomeLocationFailure.permissionDenied);
    expect(deniedLocation.requests, 1);
    denied.dispose();
  });

  test(
    'temporary GPS exception becomes recoverable unavailable state',
    () async {
      final location = _Location(error: StateError('temporary GPS failure'));
      final home = HomeLocationController(
        location: location,
        geocoding: _Geo(),
        motion: MotionEngine(),
      );
      final result = await home.detectCurrent();
      expect(result.failure, HomeLocationFailure.unavailable);
      expect(result.target, isNull);
      home.dispose();
    },
  );

  test(
    'pickup exposes disabled, permanently denied and unavailable failures',
    () async {
      final disabled = PickupMapController(
        location: _Location(enabled: false),
        geocoding: _Geo(),
      );
      expect(
        (await disabled.currentPosition()).failure,
        PickupLocationFailure.servicesDisabled,
      );

      final forever = PickupMapController(
        location: _Location(permission: LocationPermission.deniedForever),
        geocoding: _Geo(),
      );
      expect(
        (await forever.currentPosition()).failure,
        PickupLocationFailure.permissionDeniedForever,
      );

      final unavailable = PickupMapController(
        location: _Location(error: StateError('GPS timeout')),
        geocoding: _Geo(),
      );
      expect(
        (await unavailable.currentPosition()).failure,
        PickupLocationFailure.unavailable,
      );
    },
  );

  test('location recovery succeeds after services become available', () async {
    final location = _Location(enabled: false);
    final pickup = PickupMapController(location: location, geocoding: _Geo());
    expect(
      (await pickup.currentPosition()).failure,
      PickupLocationFailure.servicesDisabled,
    );
    location.enabled = true;
    final recovered = await pickup.currentPosition();
    expect(recovered.hasPosition, isTrue);
    expect(recovered.position?.latitude, 59.33);
  });
}
