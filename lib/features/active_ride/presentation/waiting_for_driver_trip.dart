part of 'waiting_for_driver.dart';

extension _WaitingTrip on _WaitingForDriverState {
  /// rider-u44: the category of this ride only. The on-demand session's
  /// booked category and the stored snapshot describe whatever Book Now
  /// ride ran last, so they count only when they are this ride.
  Future<String?> _tripCategoryId() async {
    final own = widget.categoryId;
    if (own != null && own.trim().isNotEmpty) return own;
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return null;
    final session = AppScope.instance.ride;
    if (session.rideId?.trim() == rideId && session.bookedCategoryId != null) {
      return session.bookedCategoryId;
    }
    final stored = await RouteChangeController.storedRide();
    return stored?.rideId?.trim() == rideId ? stored?.categoryId : null;
  }

  RideCheckPlan _rideCheckPlan() => RideCheckPlan(
    pickup: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
    destination: GeoPoint(
      _destinationPosition.latitude,
      _destinationPosition.longitude,
    ),
    stops: [for (final stop in _stops) GeoPoint(stop.latitude, stop.longitude)],
    destinationLabel: _WaitingForDriverState._placeName(_destinationAddress),
  );

  /// Rider, driver and trip details the safety team gets with an alert.
  RideCheckTripContext _rideCheckTrip(String rideId) {
    final driver = _tracking.driver ?? widget.driver;
    String? riderName;
    String? riderPhone;
    try {
      final profile = AppScope.instance.profile.profile;
      riderName = profile.name.trim().isEmpty ? null : profile.name.trim();
      riderPhone = profile.phone.trim().isEmpty ? null : profile.phone.trim();
    } catch (error) {
      // The alert still goes out with the trip and driver.
      AppLog.warning(
        'safety.ridecheck.profile_unavailable',
        extra: {'error': '$error'},
      );
    }
    return RideCheckTripContext(
      rideId: rideId,
      riderName: riderName,
      riderPhone: riderPhone,
      driverId: driver?.id,
      driverName: driver?.hasFirstName == true
          ? driver!.displayFirstName
          : null,
      driverPlate: driver?.plate,
      driverVehicle: driver == null || driver.vehicleLabel.isEmpty
          ? null
          : driver.vehicleLabel,
      pickup: RideCheckPlace(
        label: _pickupAddress,
        point: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      ),
      destination: RideCheckPlace(
        label: _WaitingForDriverState._placeName(_destinationAddress),
        point: GeoPoint(
          _destinationPosition.latitude,
          _destinationPosition.longitude,
        ),
      ),
      stops: _rideCheckStops(),
      rideType: widget.rideType,
      status: _tracking.status.name,
    );
  }

  void _applyRouteChange(RideSnapshot updated) {
    _pickupAddress = updated.pickupAddress;
    _pickupPosition = LatLng(updated.pickupLat, updated.pickupLng);
    _destinationAddress = updated.destinationAddress;
    _destinationPosition = LatLng(
      updated.destinationLat,
      updated.destinationLng,
    );
    _stops = List<RouteStop>.from(updated.stops);
    _changedPrice = updated.price;
    _tracking
      ..pickupLat = _pickupPosition.latitude
      ..pickupLng = _pickupPosition.longitude
      ..destinationLat = _destinationPosition.latitude
      ..destinationLng = _destinationPosition.longitude;
    final realtime = _realtime;
    if (realtime is MockRideRealtime) {
      realtime.destinationLat = _destinationPosition.latitude;
      realtime.destinationLng = _destinationPosition.longitude;
      realtime.movePickup(_pickupPosition.latitude, _pickupPosition.longitude);
    }
    final rideId = _rideId?.trim();
    if (rideId != null && rideId.isNotEmpty) {
      RideCheckController.shared
        ..replan(rideId, _rideCheckPlan())
        ..updateTrip(
          rideId,
          (trip) => trip.copyWith(
            destination: RideCheckPlace(
              label: _WaitingForDriverState._placeName(_destinationAddress),
              point: GeoPoint(
                _destinationPosition.latitude,
                _destinationPosition.longitude,
              ),
            ),
            stops: _rideCheckStops(),
          ),
        );
    }
    _sheetSignature = '';
  }
}
