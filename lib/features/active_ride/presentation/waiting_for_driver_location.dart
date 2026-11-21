part of 'waiting_for_driver.dart';

/// Contract v0.18.144 (owner 2026-11-20; approved mockup screens 6 + 7):
/// while the driver comes, the adjust-pickup banner (not once he has
/// arrived: [_pickupEditable]; only within the trip's
/// `maxPickupMoveMeters`, the existing `PATCH { pickup }`) and the rider's
/// "Share my location" switch.
extension _WaitingLocation on _WaitingForDriverState {
  bool get _driverComing => switch (_tracking.status) {
    RideStatus.driverAssigned ||
    RideStatus.driverArriving ||
    RideStatus.driverWaiting => true,
    _ => false,
  };

  Widget _locationTools(MatchedDriver? driver) {
    if (!_driverComing) return const SizedBox.shrink();
    return RideLocationTools(
      tripId: _rideId,
      phase: AdjustPickupPhase.driverComing,
      pickup: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      bookedPickup: _bookedPickup,
      maxMoveMeters:
          _tracking.terms?.maxPickupMoveMeters ??
          _zoneConfig?.maxPickupMoveMeters,
      driverName: driver?.firstName,
      settings: _zoneConfig?.liveLocation ?? const LiveLocationSettings(),
      senders: liveLocationSenders(AppScope.instance.api),
      onAdjust: _adjustPickupTo,
      // Contract: no banner once the driver has arrived (pickup fixed).
      bannerAllowed: _pickupEditable,
    );
  }

  Future<bool> _adjustPickupTo(GeoPoint to) async {
    final rideId = _rideId;
    if (rideId == null) return false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final address = await bookingPickupAddress(
      label: '',
      position: LatLng(to.latitude, to.longitude),
      reverse: (p) => AppScope.instance.geocoding.reverse(
        GeoPoint(p.latitude, p.longitude),
      ),
    );
    try {
      final projection =
          await PickupMoveController(
            api: AppScope.instance.api,
            session: AppScope.instance.ride,
          ).move(
            tripId: rideId,
            address: address,
            to: to,
            bookedPickup: _bookedPickup,
            maxMeters:
                _tracking.terms?.maxPickupMoveMeters ??
                _zoneConfig?.maxPickupMoveMeters,
          );
      if (!mounted) return false;
      final pickup = projection['pickup'];
      _applyMovedPickup(
        address: pickup is Map && pickup['address'] is String
            ? pickup['address'] as String
            : address,
        lat: pickup is Map && pickup['lat'] is num
            ? (pickup['lat'] as num).toDouble()
            : to.latitude,
        lng: pickup is Map && pickup['lng'] is num
            ? (pickup['lng'] as num).toDouble()
            : to.longitude,
      );
      return true;
    } on PickupMoveException catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }
  }
}
