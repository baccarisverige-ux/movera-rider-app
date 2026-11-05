part of 'home.dart';

extension _HomeRoutes on _HomeState {
  /// A saved place that only says "Current location" was never really set.
  String? _placeOrNull(String? address) {
    final value = address?.trim() ?? '';
    if (value.isEmpty || value == 'Current location') return null;
    return value;
  }

  /// rider-46: the pickup label when it names a real place, else null. With
  /// location off it is the placeholder 'Location off, set pickup', which
  /// must never be saved as Home, Work or a Recent.
  String? _currentAddressToSave() {
    final value = _placeOrNull(_pickupAddress);
    if (value == null ||
        isPlaceholderPickupLabel(value) ||
        isUnusablePickupLabel(value)) {
      return null;
    }
    return value;
  }

  /// RIDE-9: runs one route flow at a time; a second tap while one is
  /// opening or open does nothing. RIDE-10: when the flow ends, the pickup
  /// label goes back to the rider's current location.
  Future<void> _runRouteFlow(Future<void> Function() flow) async {
    if (_routeFlowOpen) return;
    _routeFlowOpen = true;
    try {
      await flow();
    } finally {
      _routeFlowOpen = false;
      if (mounted) {
        _resetPickupLabel();
        // A flow that ended without opening another screen (Plan your ride
        // closed) gives Home its map back now, not after the grace above.
        _syncRouteParking();
      }
    }
  }

  /// RIDE-10: a live fix far from where the pickup label was resolved
  /// makes that label wrong; derive it again from the new point.
  void _refreshPickupLabelIfMoved(LatLng fix) {
    final at = _pickupLabelAt;
    if (at == null) {
      _pickupLabelAt = fix;
      return;
    }
    // Not during a flow, and never over a pickup the rider chose.
    if (_routeFlowOpen ||
        _mapParkingGuard.isParked ||
        _tripPickupLatLng != null) {
      return;
    }
    final moved = AppScope.instance.location.distanceBetween(
      at.latitude,
      at.longitude,
      fix.latitude,
      fix.longitude,
    );
    // N7: a pickup still unnamed (the first fix was too coarse to name)
    // takes its street from the first fix that is good enough.
    final askedAt = _pickupLabelAskedAt;
    final unnamed =
        isPlaceholderPickupLabel(_pickupAddress) &&
        _pickupAddress != locationOffPickupLabel &&
        HomeLocationController.nameable(_locationCtl.lastFixAccuracyMeters) &&
        (askedAt == null ||
            DateTime.now().difference(askedAt) > const Duration(seconds: 8));
    if (moved > 75 || unnamed) _resetPickupLabel();
  }
}
