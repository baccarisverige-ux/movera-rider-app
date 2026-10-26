import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/utils/stale_guard.dart';
import 'package:movera_rider/features/pickup/data/pickup_repository.dart';

enum PickupLocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class PickupCurrentPositionResult {
  const PickupCurrentPositionResult._({this.position, this.failure});

  const PickupCurrentPositionResult.success(LatLng position)
    : this._(position: position);

  const PickupCurrentPositionResult.failure(PickupLocationFailure failure)
    : this._(failure: failure);

  final LatLng? position;
  final PickupLocationFailure? failure;

  bool get hasPosition => position != null;
}

class PickupMapFix {
  const PickupMapFix({required this.position, this.address});
  final LatLng position;
  final String? address;
}

class PickupMapController {
  PickupMapController({required this.location, required this.geocoding});

  final LocationRepository location;
  final AppGeocoding geocoding;
  final StaleGuard _stale = StaleGuard();
  int _inFlight = 0;

  /// How long My location waits for a fix before it reports "unavailable".
  static const currentPositionTimeout = Duration(seconds: 16);

  /// A lookup is running.
  bool get resolving => _inFlight > 0;

  /// The address at [position]. A newer call supersedes an older one: the
  /// older returns null. A call made while another runs is not dropped, so
  /// the pin's latest point always gets its own lookup (RIDE-12).
  Future<String?> reverse(LatLng position) async {
    _inFlight += 1;
    final generation = _stale.next();
    try {
      final address = await geocoding.reverseGeocodeAddress(
        position.latitude,
        position.longitude,
      );
      if (!_stale.isCurrent(generation)) return null;
      if (address == null || address.trim().isEmpty) return null;
      PickupRepository.instance.remember(
        address: address,
        lat: position.latitude,
        lng: position.longitude,
      );
      return address;
    } catch (_) {
      return null;
    } finally {
      _inFlight -= 1;
    }
  }

  Future<PickupCurrentPositionResult> currentPosition() async {
    try {
      if (!await location.isLocationServiceEnabled()) {
        return const PickupCurrentPositionResult.failure(
          PickupLocationFailure.servicesDisabled,
        );
      }
      var permission = await location.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await location.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const PickupCurrentPositionResult.failure(
          PickupLocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const PickupCurrentPositionResult.failure(
          PickupLocationFailure.permissionDenied,
        );
      }
      // D-003 / rider-u134: geolocator_web passes timeLimit in microseconds
      // (15 s becomes ~4 h). The Dart-side timeout makes a fix that never
      // comes end as "unavailable".
      final current = await location
          .getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          )
          .timeout(currentPositionTimeout);
      return PickupCurrentPositionResult.success(
        LatLng(current.latitude, current.longitude),
      );
    } catch (_) {
      return const PickupCurrentPositionResult.failure(
        PickupLocationFailure.unavailable,
      );
    }
  }

  /// Null when nothing was found or the lookup failed (offline, a timeout):
  /// the callers treat both as "not found" (rider-45).
  Future<PickupMapFix?> search(String query) async {
    final PlaceResult? result;
    try {
      result = await geocoding.geocodeAddress(query);
    } catch (_) {
      return null;
    }
    if (result == null) return null;
    return PickupMapFix(
      position: LatLng(result.point.latitude, result.point.longitude),
      address: result.address,
    );
  }

  void dispose() => _stale.dispose();
}
