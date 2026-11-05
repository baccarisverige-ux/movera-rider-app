part of 'waiting_for_driver.dart';

extension _WaitingChanges on _WaitingForDriverState {
  /// Before boarding on the server wire: re-reads the zone's
  /// `routeChange.beforePickup` and says whether a destination or stop
  /// change is refused now.
  Future<bool> _routeChangeOffBeforePickup() async {
    if (_isInTrip || !widget.routeChangeSupported || !_serverPickupMove) {
      return false;
    }
    await _loadRouteChangeRules();
    return mounted && !_isInTrip && !_changeBeforePickup;
  }

  void _showRouteBeforePickupOff() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.g7RouteBeforePickupOff),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  /// v0.18.7 (Q5): from boarding on, the trip's `fare` (it already holds
  /// the charged waiting) is the total the rider pays; before that the
  /// booked (or changed) price.
  double get _price {
    final fare = _tracking.fare;
    if (_isInTrip && fare != null && fare.currency == widget.currency) {
      return fare.major;
    }
    return _changedPrice ?? widget.price;
  }

  /// v0.18.7 (item 4): the pickup moves on the server (`PATCH
  /// /trips/{tripId}`) on the contract wire, where the demo's route
  /// screen is not served.
  bool get _serverPickupMove {
    if (widget.pickupMove != null) return true;
    // G7 live fix 2: the live screens (restore and the in-app booking) get
    // no `realtime:` and use the app's transport, so read that one, not
    // only the injected one.
    final realtime = _realtime;
    return realtime is ApiRideRealtime && realtime.contractWire;
  }

  /// The three dots on the driver card and the ride card: the route
  /// screen (demo), or the pickup move until the driver is there (hidden
  /// after arrival, `pickupWaiting.pickupMove`).
  VoidCallback? get _moreAction {
    if (_serverPickupMove) return _pickupEditable ? _movePickup : null;
    return widget.routeChangeSupported ? _openDetails : null;
  }

  /// G7 live fix 2: the ride card's three dots. On the server wire they
  /// follow the zone's `routeChange.beforePickup` ([_openDetails]: the
  /// route screen when on, the pickup move when off); the driver card's
  /// dots stay the pickup move ([_moreAction]).
  VoidCallback? get _rideCardMore {
    if (_serverPickupMove && widget.routeChangeSupported) return _openDetails;
    return _moreAction;
  }

  /// The pickup as booked: the server measures a move from it. The
  /// session keeps it per trip (a reopened screen may start from an
  /// already moved pickup); this screen's first pickup otherwise.
  GeoPoint get _bookedPickup {
    final rideId = _rideId?.trim();
    final session = AppScope.instance.ride;
    session.observeBookedPickup(
      rideId,
      widget.pickupPosition.latitude,
      widget.pickupPosition.longitude,
    );
    final booked = session.bookedPickupOf(rideId);
    return booked == null
        ? GeoPoint(
            widget.pickupPosition.latitude,
            widget.pickupPosition.longitude,
          )
        : GeoPoint(booked.lat, booked.lng);
  }

  Future<int> _maxPickupMoveFromConfig() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      if (config != null) return config.maxPickupMoveMeters;
    } catch (_) {
      // The contract default below.
    }
    return RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters;
  }

  /// The ride as the server knows it, for pricing a route change.
  Future<RideSnapshot?> _currentRide() async {
    final stored = await RouteChangeController.storedRide();
    final rideId = _rideId;
    if (stored != null && (rideId == null || stored.rideId == rideId)) {
      return stored.copyWith(
        status: _tracking.status,
        pickupAddress: _pickupAddress,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
        destinationAddress: _destinationAddress,
        destinationLat: _destinationPosition.latitude,
        destinationLng: _destinationPosition.longitude,
        stops: _stops,
        price: _price,
        currency: widget.currency,
      );
    }
    if (rideId == null || rideId.trim().isEmpty) return null;
    return RideSnapshot(
      status: _tracking.status,
      savedAt: DateTime.now(),
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      pickupLat: _pickupPosition.latitude,
      pickupLng: _pickupPosition.longitude,
      destinationLat: _destinationPosition.latitude,
      destinationLng: _destinationPosition.longitude,
      rideType: widget.rideType,
      price: _price,
      currency: widget.currency,
      paymentMethod: widget.paymentMethod,
      rideId: rideId,
      notes: widget.notes,
      stops: _stops,
      driver: _tracking.driver ?? widget.driver,
      walletAmountMinor: widget.walletAmountMinor,
    );
  }

  /// rider-u56: whether this screen's live feed is down. The polling
  /// transport never errors the tracking stream on a failed poll; it marks
  /// the shared connection failed and backs off, so that state counts too.
  bool get _liveFeedDown =>
      _tracking.connectionDegraded ||
      (widget.realtime == null &&
          AppScope.instance.realtime.state != RealtimeState.connected);

  /// A driver app may stay quiet while the car stands still, so no new fix
  /// comes in to measure the stop. While the trip is under way and the live
  /// feed is up, check the long stop against the clock as well. With the
  /// feed down (the rider's own phone offline) no fix can come, so time
  /// without one says nothing about the car; the stop clock restarts when
  /// the feed is back.
  void _startRideCheckStillTimer(String rideId) {
    _rideCheckStillTimer?.cancel();
    if (!RideCheckController.tripMonitoring) return;
    _rideCheckStillTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      if (_liveFeedDown) {
        _liveFeedWasDown = true;
        return;
      }
      if (_liveFeedWasDown) {
        _liveFeedWasDown = false;
        RideCheckController.shared.liveFeedResumed(rideId);
        return;
      }
      if (!DriverEta.isInTrip(_tracking.status)) return;
      RideCheckController.shared.checkStill(rideId);
    });
  }

  List<RideCheckPlace> _rideCheckStops() => [
    for (final stop in _stops)
      RideCheckPlace(
        label: stop.address,
        point: GeoPoint(stop.latitude, stop.longitude),
      ),
  ];

  void _feedRideCheck(RideStatus status) {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final rideCheck = RideCheckController.shared;
    final driver = _tracking.driver ?? widget.driver;
    rideCheck.updateTrip(
      rideId,
      (trip) => trip.copyWith(
        status: status.name,
        driverId: driver?.id,
        driverName: driver?.hasFirstName == true
            ? driver!.displayFirstName
            : null,
        driverPlate: driver?.plate,
        driverVehicle: driver == null || driver.vehicleLabel.isEmpty
            ? null
            : driver.vehicleLabel,
      ),
    );
    if (DriverEta.isInTrip(status) && !_autoShareAsked) {
      // rider-u217: "Automatically share every ride".
      _autoShareAsked = true;
      unawaited(SafetyController.shared.autoShareRide(rideId));
    }
    if (status.isCompletedSurface) {
      _rideCheckTripEnded(rideId);
      return;
    }
    if (!DriverEta.isInTrip(status)) return;
    _rideCheckOnBoard = true;
    final eta = _tracking.eta;
    final lat = eta?.latitude;
    final lng = eta?.longitude;
    final at = eta?.locationAt;
    if (lat == null || lng == null || at == null) return;
    rideCheck.addSample(
      rideId,
      RideCheckSample(
        point: GeoPoint(lat, lng),
        at: at,
        etaSeconds: eta?.seconds,
      ),
    );
  }

  /// The trip is over, completed or ended by the driver with the rider on
  /// board: Ride check compares where it ended with the drop-off ("Finished
  /// far from drop-off"). The end is the driver's last position on the
  /// wire; without one (the live server sends none for an ended trip whose
  /// driver already drove on) the rider's own phone says where the car
  /// stopped. Never a saved old fix: that would be the pickup, a false
  /// alarm on every trip.
  void _rideCheckTripEnded(String rideId) {
    if (_rideCheckEnded) return;
    _rideCheckEnded = true;
    final rideCheck = RideCheckController.shared;
    final eta = _tracking.eta;
    final lat = eta?.latitude;
    final lng = eta?.longitude;
    if (lat != null && lng != null) {
      _rideCheckEnding = rideCheck.tripEnded(rideId, GeoPoint(lat, lng));
      return;
    }
    _rideCheckEnding = rideCheck.tripEndedAt(rideId, _whereThePhoneIs);
  }

  /// The driver ended the trip on board. The "trip ended" sheet is a route
  /// above this screen's card layer and Home has no layer, so a Ride check
  /// that is open, or still being decided, is answered first.
  Future<void> _awaitRideCheck(String rideId) async {
    final pending = _rideCheckEnding;
    if (pending != null) await pending;
    final rideCheck = RideCheckController.shared;
    if (!rideCheck.blocks(rideId)) return;
    final answered = Completer<void>();
    void listen() {
      if (!rideCheck.blocks(rideId) && !answered.isCompleted) {
        answered.complete();
      }
    }

    rideCheck.addListener(listen);
    try {
      await answered.future;
    } finally {
      rideCheck.removeListener(listen);
    }
  }

  List<double> _snaps(MediaQueryData media) {
    final low = _collapsedSheet(media);
    final mid = _minSheet(media);
    final full = _maxSheet(media);
    return [low, mid, if (full > mid + 24) full];
  }

  /// Room the map keeps clear at the bottom: the resting sheet, but never so
  /// much that the route shrinks to a sliver when the sheet is fully up.
  double _cameraClearance(MediaQueryData media) {
    final resting = _settledSheet ?? _minSheet(media);
    return math.min(resting, media.size.height * 0.6);
  }

  /// Low stop: the handle and one compact row (ETA, driver, plate).
  double _collapsedSheet(MediaQueryData media) => 118 + media.padding.bottom;

  double _minSheet(MediaQueryData media) => 390 + media.padding.bottom;

  double _maxSheet(MediaQueryData media) {
    final minH = _minSheet(media);
    final maxH = media.size.height - media.padding.top - 72;
    final screenMax = maxH < minH + 48 ? minH + 48 : maxH;
    // The full stop ends where the content does: no empty white space.
    final content = _contentHeight;
    if (content == null) return screenMax;
    return content.clamp(minH, screenMax);
  }
}
