part of 'home.dart';

// Owner decision "Home map start" (2026-11-07, "like the driver app"): Home's
// map opens at once on the last known position (this session's, else the
// saved last good fix) and never flies in from central Stockholm. Very
// first use, nothing known: the quiet "locating" surface stays until a
// position comes (owner 2026-11-07 item 9: no 3 s fallback to Stockholm).
// Location refused or turned off: the map opens at the zone's city
// (Stockholm for Swedish zones, Paris for French ones), without a flight.

/// Tests: how long a Home without any position waited before item 9. Home
/// no longer opens its map when it runs out.
const Duration homeStartWaitLimit = Duration(seconds: 3);

/// Item 9: the city a refused-location map opens at, per zone country.
const LatLng homeStockholm = LatLng(59.3293, 18.0686);
const LatLng homeParis = LatLng(48.8566, 2.3522);

extension _HomeStartCamera on _HomeState {
  /// The position this app session already knows (a Home built again after
  /// a trip or a sign-in) opens the map on the first frame. Otherwise the
  /// cached and first fixes open it ([_openMapAt]), or the wait runs out.
  void _initStartCamera() {
    final known = LocationRepository.sessionFix;
    if (known != null) {
      _startCamera = _homeCameraAt(LatLng(known.latitude, known.longitude));
    }
    // Otherwise the saved fix (_centerCameraOnQuickFix), the first fix, or
    // a refusal ([_openMapAtZoneCity]) opens it.
  }

  /// Item 9: location refused or off. The zone the rider was last in (kept
  /// on the device), else the home zone; its city, born there (no flight).
  Future<void> _openMapAtZoneCity() async {
    if (!mounted || _startCamera != null) return;
    final zone = await LocationRepository.readLastZone() ?? RiderZones.home;
    if (!mounted || _startCamera != null) return;
    _openMapAt(homeZoneCity(zone));
  }

  /// Opens the map at [point], or at the zone default when null. Only the
  /// first call counts: later positions move the camera of the map itself.
  void _openMapAt(LatLng? point) {
    if (!mounted || _startCamera != null) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _startCamera = point == null
          ? _HomeState._initialPosition
          : _homeCameraAt(point);
    });
  }

  CameraPosition _homeCameraAt(LatLng point) =>
      CameraPosition(target: point, zoom: homeOpeningZoom);

  /// The camera a new Home map is born with: the rider's position when it
  /// is known (a map made again after being parked), else the start camera.
  CameraPosition get _mapBirthCamera {
    final at = _currentLatLng;
    return at == null ? _startCamera! : _homeCameraAt(at);
  }

  /// A map born on [target] already shows it: no camera command. A target
  /// that moved while the map was being made is placed at once (no flight).
  void _placeNewMapOn(LatLng target, LatLng bornAt) {
    final apart = AppScope.instance.location.distanceBetween(
      bornAt.latitude,
      bornAt.longitude,
      target.latitude,
      target.longitude,
    );
    if (apart <= 1) return;
    unawaited(
      AppScope.instance.maps.moveCamera(
        GeoPoint(target.latitude, target.longitude),
        zoom: homeOpeningZoom,
      ),
    );
  }

  /// Soft neutral surface while the first position is found (as the
  /// driver app's Home).
  Widget _locatingSurface(BuildContext context) => ColoredBox(
    key: const ValueKey<String>('home-map-locating'),
    color: const Color(0xFFEEF1E8),
    child: Align(
      alignment: const Alignment(0, -0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Static on purpose: no endless animation on the map surface.
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x1F2B3036),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(7),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF8A939B),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.homeFindingLocation,
            style: const TextStyle(
              // WCAG AA (4.5:1) on the surface colour.
              color: _HomeState._premiumMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Item 9: Stockholm for a Swedish zone, Paris for a French one, else the
/// middle of the zone's box.
LatLng homeZoneCity(RiderZone zone) => switch (zone.country?.toUpperCase()) {
  'SE' => homeStockholm,
  'FR' => homeParis,
  _ => LatLng((zone.south + zone.north) / 2, (zone.west + zone.east) / 2),
};
