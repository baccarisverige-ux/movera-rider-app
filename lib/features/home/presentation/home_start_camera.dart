part of 'home.dart';

// Owner decision "Home map start" (2026-11-07, "like the driver app"): Home's
// map opens at once on the last known position and never flies in from
// central Stockholm. With no known position yet (first use), a quiet
// "locating" surface shows for at most [homeStartWaitLimit]; the map is then
// born on the first fix, or at the zone default when there is still none.

/// Longest wait for a first position before Home's map opens anyway.
const Duration homeStartWaitLimit = Duration(seconds: 3);

extension _HomeStartCamera on _HomeState {
  /// The position this app session already knows (a Home built again after
  /// a trip or a sign-in) opens the map on the first frame. Otherwise the
  /// cached and first fixes open it ([_openMapAt]), or the wait runs out.
  void _initStartCamera() {
    final known = LocationRepository.sessionFix;
    if (known != null) {
      _startCamera = _homeCameraAt(LatLng(known.latitude, known.longitude));
      return;
    }
    _startWait = Timer(homeStartWaitLimit, () {
      _startWait = null;
      _openMapAt(null);
    });
  }

  /// Opens the map at [point], or at the zone default when null. Only the
  /// first call counts: later positions move the camera of the map itself.
  void _openMapAt(LatLng? point) {
    if (!mounted || _startCamera != null) return;
    _startWait?.cancel();
    _startWait = null;
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
