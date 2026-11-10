// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingDetails on _WaitingForDriverState {
  void _openProfile() {
    final driver = _tracking.driver ?? widget.driver;
    if (driver == null) return;
    Navigator.push(
      context,
      RightToLeftTransition(DriverProfilePage(driver: driver)),
    );
  }

  /// Contract v0.13.0 §22: the masked call, never the driver's number.
  void _callDriver() {
    SafetyController.shared.record(SafetyKind.maskedCall, rideId: _rideId);
    unawaited(
      callTripPeer(
        context,
        rideId: _rideId,
        transport: AppScope.instance.tripCall,
      ),
    );
  }

  /// The three dots on the ride card: the route screen with the current
  /// addresses. The pickup can move until the driver is there; the
  /// destination and the stops can change until the trip ends.
  Future<void> _openDetails() async {
    if (_routeEditOpen || _leaving) return;
    // G7 live fix: before boarding, read the zone's switch again (the admin
    // may have changed it since this screen opened). `beforePickup` covers
    // only the destination and the stops: with it off, the pickup can still
    // move (owner decision), so the three dots open the pickup move.
    final off = await _routeChangeOffBeforePickup();
    if (!mounted) return;
    switch (WaitingForDriver.detailsAction(
      beforePickupOff: off,
      pickupEditable: _pickupEditable,
    )) {
      case DetailsAction.routeScreen:
        await _changeRoute(null, RouteChangeEntry.destination);
      case DetailsAction.movePickup:
        await _movePickup();
      case DetailsAction.refused:
        _showRouteBeforePickupOff();
    }
  }

  Future<void> _movePickup() async {
    if (_pickupMoveOpen || _leaving) return;
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_pickupEditable) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.l10n.pickupMoveFixedAfterArrival)),
      );
      return;
    }
    _pickupMoveOpen = true;
    _modalHandoffInProgress = true;
    try {
      await _parkMapForStageChange();
      if (!mounted) return;
      final picked = await ConfirmPickupSpot.open(
        context,
        initialPosition: _pickupPosition,
        initialAddress: _pickupAddress,
        title: context.l10n.movePickup,
        confirmLabel: context.l10n.confirmPickup,
      );
      if (!mounted) return;
      _mapParked = false;
      setState(() {});
      if (picked == null) return;
      final to = GeoPoint(picked.position.latitude, picked.position.longitude);
      final controller =
          widget.pickupMove ??
          PickupMoveController(
            api: AppScope.instance.api,
            session: AppScope.instance.ride,
          );
      final maxMeters =
          _tracking.terms?.maxPickupMoveMeters ??
          _zoneConfig?.maxPickupMoveMeters ??
          await _maxPickupMoveFromConfig();
      if (!mounted) return;
      try {
        final projection = await controller.move(
          tripId: rideId,
          address: picked.address,
          to: to,
          bookedPickup: _bookedPickup,
          maxMeters: maxMeters,
        );
        if (!mounted) return;
        final pickup = projection['pickup'];
        final lat = pickup is Map && pickup['lat'] is num
            ? (pickup['lat'] as num).toDouble()
            : to.latitude;
        final lng = pickup is Map && pickup['lng'] is num
            ? (pickup['lng'] as num).toDouble()
            : to.longitude;
        final address = pickup is Map && pickup['address'] is String
            ? (pickup['address'] as String)
            : picked.address;
        _applyMovedPickup(address: address, lat: lat, lng: lng);
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.pickupMoved)));
      } on PickupMoveException catch (error) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      _pickupMoveOpen = false;
      _modalHandoffInProgress = false;
    }
  }

  /// The pickup the server now has (the rider's own move, or a
  /// `pickup_moved` event): the route, the marker and the tracking follow.
  void _applyMovedPickup({
    required String address,
    required double lat,
    required double lng,
  }) {
    if (address.trim().isNotEmpty) _pickupAddress = address.trim();
    _pickupPosition = LatLng(lat, lng);
    _tracking
      ..pickupLat = lat
      ..pickupLng = lng;
    final realtime = _realtime;
    if (realtime is MockRideRealtime) realtime.movePickup(lat, lng);
    final rideId = _rideId?.trim();
    if (rideId != null && rideId.isNotEmpty) {
      RideCheckController.shared.replan(rideId, _rideCheckPlan());
    }
    // The device copy is not rewritten here: a restore reads the trip
    // from the server, whose projection carries the moved pickup.
    if (mounted) setState(() {});
  }

  /// Change the pickup (until the driver is there), the destination or the
  /// stops: the new price is confirmed first, then the driver is told.
  Future<void> _changeRoute(
    BuildContext? sheetContext,
    RouteChangeEntry entry, {
    int? removeStop,
  }) async {
    if (_routeEditOpen || _leaving || !_routeEditable) return;
    _routeEditOpen = true;
    _modalHandoffInProgress = true;
    try {
      if (sheetContext != null) {
        await popCurrentRouteAndWaitForExit(sheetContext);
        if (!mounted) return;
      }
      final ride = await _currentRide();
      if (ride == null || !mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      final updated = removeStop != null
          ? await removeRouteStop(
              context,
              ride: ride,
              index: removeStop,
              onProposed: _onRouteProposed,
            )
          : await openRouteChange(
              context,
              ride: ride,
              entry: entry,
              pickupLocked: !_pickupEditable,
              driverAccepted: true,
              onProposed: _onRouteProposed,
            );
      if (!mounted) return;
      if (updated != null) _applyRouteChange(updated);
      _mapParked = false;
      setState(() {});
      if (updated != null) {
        showRouteUpdated(
          context,
          driverAssigned: true,
          paymentMethod: widget.paymentMethod,
          // rider-u36: the server's difference, as the sheet showed it.
          differenceKr: lastRouteDifferenceKr ?? updated.price - ride.price,
          currency: updated.currency,
        );
      }
    } finally {
      _routeEditOpen = false;
      _modalHandoffInProgress = false;
    }
  }

  /// The confirmed change waits for the driver (the card says so).
  void _onRouteProposed(TripRouteChange change) {
    if (!mounted) return;
    setState(() => _tracking.routeChange = change);
  }

  /// The server's ride check (G7 decision 1) opens the Ride check card; a
  /// route change the driver answered (decision 3) is told once.
  void _onTripG7() {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final check = _tracking.rideCheck;
    final trigger = parseRideCheckTrigger(check?.trigger);
    if (check != null &&
        trigger != null &&
        check.openForRider(DateTime.now().toUtc())) {
      unawaited(
        RideCheckController.shared.openServer(
          rideId: rideId,
          checkId: check.checkId,
          trigger: trigger,
          askedAt: check.askedAt,
        ),
      );
    }
    // The pending card follows the projection (a change from another
    // device, an answer): rebuild when its state moved.
    final shownKey =
        '${_tracking.routeChange?.changeId}:'
        '${_tracking.routeChange?.status}';
    if (shownKey != _routeChangeShown) {
      _routeChangeShown = shownKey;
      setState(() {});
    }
    final outcome = _tracking.takeRouteChangeOutcome();
    if (outcome == null) return;
    final String text;
    if (outcome.accepted) {
      text = context.l10n.g7RouteAccepted;
      unawaited(_adoptAcceptedRoute(outcome));
    } else if (outcome.status == 'withdrawn') {
      text = context.l10n.g7RouteWithdrawn;
    } else if (outcome.status == 'expired') {
      // Deep-fix 2026-11-02: no answer in time is not a refusal.
      text = context.l10n.g7RouteExpired;
    } else {
      text = context.l10n.g7RouteRefused;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey('route-change-${outcome.status}'),
          content: Text(text),
          // G7 live fix: long enough to read, and closable.
          duration: WaitingForDriver.routeOutcomeNoticeDuration,
          showCloseIcon: true,
        ),
      );
  }

  Future<void> _adoptAcceptedRoute(TripRouteChange change) async {
    final ride = await _currentRide();
    if (ride == null || !mounted) return;
    final updated = await RouteChangeController.adoptAccepted(ride, change);
    if (!mounted) return;
    setState(() => _applyRouteChange(updated));
  }

  Future<void> _withdrawRouteChange(TripRouteChange change) async {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty || _routeWithdrawing) return;
    setState(() => _routeWithdrawing = true);
    try {
      final after = await RouteChangeController(
        api: AppScope.instance.api,
        geocoding: AppScope.instance.geocoding,
        session: AppScope.instance.ride,
      ).withdraw(tripId: rideId, changeId: change.changeId);
      if (!mounted) return;
      _tracking.routeChange = after ?? _tracking.routeChange;
      _onTripG7();
    } on RouteChangeException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _routeWithdrawing = false);
    }
  }
}
