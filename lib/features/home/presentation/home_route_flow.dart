part of 'home.dart';

// Rule 25 split (2026-11-07, no behaviour change): Home's booking route
// flow (destination tap, parked map, pickup picker, route and place
// pickers), moved out of home.dart unchanged.
extension _HomeRouteFlow on _HomeState {
  Future<void> _saveAddressFor(
    String target,
    String address, {
    String? customType,
    String? placeId,
  }) async {
    final resolved = await _normaliseAddress(address);
    if (resolved.isEmpty || !mounted) return;

    LatLng? resolvedPickupPosition;
    if (target == 'pickup') {
      if (resolved.toLowerCase() == 'current location') {
        resolvedPickupPosition = _gpsPickup;
      } else {
        final geocodedPickup = await _locationCtl.geocodeLatLng(resolved);
        if (geocodedPickup != null) {
          resolvedPickupPosition = geocodedPickup;
        }
      }
    }
    if (!mounted) return;

    // ignore: invalid_use_of_protected_member
    setState(() {
      _places.applyResolved(
        target: target,
        address: resolved,
        pickupPosition: resolvedPickupPosition,
        customType: customType,
        placeId: placeId,
      );
      if (target == 'destination') {
        AppScope.instance.destinationMemory.remember(address: resolved);
      }
    });
    await _persistAddressData();
    if (target == 'pickup' || target == 'destination') {
      await _moveMapToAddress(resolved);
    }
  }

  Future<void> _handleDestinationTap({
    String? initialRideId,
  }) => _runRouteFlow(() async {
    // Capture from the tap itself: the sheet sequencing below takes long enough
    // that anything typed in the meantime would otherwise be lost.
    final capture = EarlyInputCapture()..start();
    try {
      if (!_destinationSheetOpen) {
        await _openDestinationSheet();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await _showRouteAddressPicker(
        initialField: 'destination',
        capture: capture,
        initialRideId: initialRideId,
      );
    } finally {
      capture.stop();
    }
  });

  /// Long-press on Home / Work / a custom place: change its address.
  Future<void> _editSavedPlace(String target, {String? customType}) =>
      _showAddressPicker(target: target, customType: customType);

  /// rider-41: a custom place is edited by its id; another place of the
  /// same kind is left alone.
  Future<void> _editCustomPlace(_SavedPlaceData place) => _showAddressPicker(
    target: 'custom',
    customType: place.type,
    placeId: place.id,
  );

  Future<void> _useSavedPlaceAsDestination(
    String? savedAddress, {
    required String target,
    String? customType,
  }) => _runRouteFlow(() async {
    final address = _placeOrNull(savedAddress) ?? '';
    if (address.isEmpty) {
      await _showAddressPicker(target: target, customType: customType);
      return;
    }

    final destination = await _normaliseAddress(address);
    if (destination.isEmpty || !mounted) return;

    // ignore: invalid_use_of_protected_member
    setState(() {
      _destinationAddress = destination;
      // rider-u121: a saved place is a new route; stops left by an earlier
      // Where to flow the rider backed out of are not carried into it.
      _routeStops = const <String>[];
      _rememberAddress(destination);
    });
    await _persistAddressData();
    await _withParkedHomeMap(() async {
      final pickupResult = await _prefillPickup(
        _pickupAddress ?? 'Current location',
        null,
      );
      if (pickupResult == null || !mounted) return null;
      final pickupPosition = pickupResult.position;
      final bookingAddress = pickupResult.isFallback
          ? pickupResult.address
          : await _bookingPickup(pickupResult.address, pickupPosition);
      if (!mounted) return null;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _pickupAddress = bookingAddress;
        _tripPickupLatLng = pickupResult.position;
      });
      if (!mounted) return null;
      final confirmedPickupPosition = pickupPosition;
      var resolvedDestination = destination;
      LatLng? destinationPosition;
      switch (await _locationCtl.resolvePlace(destination)) {
        case GeocodeFound(:final value):
          resolvedDestination = value.address;
          destinationPosition = value.point;
        case GeocodeStale():
          // RIDE-18: a newer flow owns the geocode; stop without an error.
          return null;
        case GeocodeNotFound():
          if (mounted) {
            MoveraToast.show(context, context.l10n.homeChooseValidDestination);
          }
          return null;
        case GeocodeFailed():
          // rider-45: offline or the lookup failed; say so, never abort
          // silently.
          if (mounted) {
            MoveraToast.show(context, context.l10n.routeCouldNotReach);
          }
          return null;
      }
      final confirmedDestinationPosition = destinationPosition;
      if (!mounted) return null;
      return Navigator.of(context).push(
        RideStageTransition(
          SelectRide(
            pickupAddress: bookingAddress,
            destinationAddress: resolvedDestination,
            pickupPosition: confirmedPickupPosition,
            pickupIsFallback: pickupResult.isFallback,
            destinationPosition: confirmedDestinationPosition,
            stops: const <String>[],
            bookingMode: BookingMode.now,
            onScheduled: (context, id) {
              _scheduledInFlow = true;
              return RideScheduledPage.open(
                context,
                reservationId: id,
                replace: true,
              );
            },
          ),
          settings: const RouteSettings(name: AppRoutes.selectRide),
        ),
      );
    });
  });

  Future<T?> _withParkedHomeMap<T>(Future<T?> Function() action) async {
    final parkedNow = _mapParkingGuard.enter();
    final rideBefore = AppScope.instance.ride.rideId;
    final statusBefore = AppScope.instance.ride.status;
    try {
      if (parkedNow) {
        final parkingWatch = Stopwatch()..start();
        _parkHomeMap();
        // Let Flutter remove the platform map for one rendered frame before
        // the next map-heavy ride screen mounts.
        await WidgetsBinding.instance.endOfFrame;
        parkingWatch.stop();
        RouteTransitionMetrics.homeMapParking(parkingWatch.elapsed);
        if (!mounted) return null;
      }
      return await action();
    } finally {
      final resumeNow = _mapParkingGuard.exit();
      if (resumeNow && mounted) {
        // U6: a finished (or abandoned) booking flow must not leave its
        // pickup behind as the next booking's starting point.
        _tripPickupLatLng = null;
        // A ride that ended or was cancelled in this flow starts the next
        // booking from "Where to?", not from the last trip's destination.
        final ride = AppScope.instance.ride;
        final changed =
            ride.rideId != rideBefore || ride.status != statusBefore;
        if (_scheduledInFlow ||
            (changed &&
                (ride.status.isTerminal || ride.status.isCompletedSurface))) {
          _destinationAddress = null;
          _routeStops = const <String>[];
        }
        _scheduledInFlow = false;
        _closeDestinationSheet();
        // NAV-3: the flow's page can be replaced by another one (Book for
        // later -> Ride scheduled). Stay parked until Home is on top again.
        // A route flow that goes on (Back on the categories screen reopens
        // Plan your ride) gets the grace of [_syncRouteParking] instead of
        // a map for the frame in between.
        if (_homeIsCurrent) {
          if (_routeFlowOpen) {
            _syncRouteParking();
          } else {
            _resumeHomeMap();
          }
        }
      }
    }
  }

  void _resetPickupLabel() {
    final here = _gpsPickup;
    final generation = ++_pickupLabelGeneration;
    _pickupLabelAt = here;
    // ignore: invalid_use_of_protected_member
    setState(() {
      // U6: the label and the point go together; neither outlives the flow.
      _tripPickupLatLng = null;
      _pickupAddress = here == null
          ? locationOffPickupLabel
          : 'Current location';
    });
    if (here == null) return;
    // N7: a coarse fix names no street; the next good fix relabels.
    if (!HomeLocationController.nameable(_locationCtl.lastFixAccuracyMeters)) {
      return;
    }
    _pickupLabelAskedAt = DateTime.now();
    unawaited(() async {
      String? address;
      try {
        address = await AppScope.instance.geocoding.reverse(
          GeoPoint(here.latitude, here.longitude),
        );
      } catch (_) {
        return;
      }
      final clean = address?.trim() ?? '';
      if (!mounted ||
          generation != _pickupLabelGeneration ||
          clean.isEmpty ||
          isRawCoordinateLabel(clean) ||
          _routeFlowOpen ||
          _mapParkingGuard.isParked ||
          !isPlaceholderPickupLabel(_pickupAddress)) {
        return;
      }
      // ignore: invalid_use_of_protected_member
      setState(() => _pickupAddress = clean);
    }());
  }

  Future<PickupMapResult?> _openPickupMapPicker(
    String address, {
    bool isDestination = false,
  }) async {
    var cleanAddress = address.trim();
    // U6: only text the rider actually typed is forward-geocoded. The stored
    // pickup label came from GPS, a dropped pin or an earlier booking, and a
    // raw coordinate string is not a place — geocoding either one moved the
    // picker to wherever the *previous* trip's address resolved to.
    final storedLabel = _pickupAddress?.trim() ?? '';
    final typedByRider =
        !isPlaceholderPickupLabel(cleanAddress) &&
        !isUnusablePickupLabel(cleanAddress) &&
        cleanAddress != storedLabel;
    // This booking's own confirmed pickup (cleared when the flow ends).
    LatLng? chosen = _tripPickupLatLng;
    if (typedByRider || isDestination) {
      final geocoded = await _locationCtl.geocodeLatLng(cleanAddress);
      if (geocoded != null) chosen = geocoded;
    }
    final gps = _gpsPickup;
    // rider-u114: an approximate fix still opens the picker near the rider,
    // as a fallback point the rider has to move.
    final initialPosition =
        chosen ?? gps ?? _currentLatLng ?? _HomeState._initialPosition.target;
    // D-002: with no fix and no chosen pickup the picker opens on a default
    // map point; it must not be confirmable as if it were the rider's spot.
    final positionIsFallback = chosen == null && gps == null;
    if (chosen == null) {
      cleanAddress = gps != null ? 'Current location' : locationOffPickupLabel;
    }
    if (!mounted) return null;
    return _withParkedHomeMap(() async {
      final result = await ConfirmPickupSpot.open(
        context,
        initialPosition: initialPosition,
        initialAddress: cleanAddress.isEmpty
            ? (_pickupAddress ?? 'Current location')
            : cleanAddress,
        title: isDestination
            ? context.l10n.confirmDestination
            : context.l10n.confirmPickupSpot,
        confirmLabel: isDestination
            ? context.l10n.confirmDestination
            : context.l10n.confirmPickup,
        positionIsFallback: positionIsFallback,
        // U6 / D-011: opened at GPS (or the fallback) — take a fresh fix.
        // rider-u114: never re-seeded from an approximate fix.
        refreshCurrentLocation:
            chosen == null && !_locationCtl.preciseLocationOff,
      );
      if (result == null) return null;
      return PickupMapResult(
        address: result.address,
        position: result.position,
      );
    });
  }

  /// The pickup the categories screen starts from: a point the rider chose,
  /// an address they typed, or else their current location. Only with no
  /// location at all does the map picker open here.
  Future<PickupMapResult?> _prefillPickup(
    String address,
    GeoPoint? point, {
    bool throwOnFailure = false,
  }) async {
    final clean = address.trim();
    if (point != null) {
      return PickupMapResult(
        address: clean,
        position: LatLng(point.latitude, point.longitude),
      );
    }
    final typedByRider =
        !isPlaceholderPickupLabel(clean) &&
        !isUnusablePickupLabel(clean) &&
        clean != (_pickupAddress?.trim() ?? '');
    if (typedByRider) {
      switch (await _locationCtl.resolveLatLng(clean)) {
        case GeocodeFound(:final value):
          return PickupMapResult(address: clean, position: value);
        case GeocodeStale():
          // RIDE-18: superseded — never swap the typed pickup for GPS.
          return null;
        case GeocodeFailed():
          // rider-45: the lookup failed; the typed pickup is not swapped for
          // GPS either.
          if (throwOnFailure) throw const RouteLookupFailed();
          if (mounted) {
            MoveraToast.show(context, context.l10n.routeCouldNotReach);
          }
          return null;
        case GeocodeNotFound():
          break;
      }
    }
    // No fix yet (Safari's permission prompt, a slow first fix): wait for it
    // rather than sending the rider to the old map picker.
    final here = await _awaitCurrentFix();
    if (!mounted) return null;
    if (here != null) {
      return PickupMapResult(
        address: typedByRider ? 'Current location' : clean,
        position: here,
      );
    }
    // Still nothing: the categories screen opens as usual and Set location
    // starts on a placeholder point the rider has to move (or allow
    // location) before it can be confirmed.
    return PickupMapResult(
      address: locationOffPickupLabel,
      position: _currentLatLng ?? _HomeState._initialPosition.target,
      isFallback: true,
    );
  }

  /// The step after the rider taps a real destination.
  ///
  /// Runs under the address screen, which stays open: a lookup the server
  /// could not answer (offline, a timeout, a 5xx while it wakes) is thrown
  /// as [RouteLookupFailed], so the screen says so with Try again instead
  /// of a toast under it that reads as a silent return to Home.
  Future<Map<String, dynamic>?> _confirmRouteSelection(
    RoutePickerSelection selection, {
    bool scheduled = false,
  }) async {
    // Book now always confirms pickup; GPS only prefills. The confirm step
    // is Set pickup, opened after Book on the categories screen.
    final pickup = await _prefillPickup(
      selection.pickup,
      selection.pickupPoint,
      throwOnFailure: true,
    );
    if (pickup == null || !mounted) return null;
    var destination = selection.destination;
    var destinationPoint = selection.destinationPoint;
    if (destinationPoint == null) {
      final outcome = await _locationCtl.resolvePlace(destination);
      final geocoded = outcome.valueOrNull;
      if (geocoded == null) {
        if (outcome is GeocodeFailed) throw const RouteLookupFailed();
        if (mounted && outcome is GeocodeNotFound) {
          MoveraToast.show(context, context.l10n.homeChooseValidDestination);
        }
        return null;
      }
      destination = geocoded.address;
      destinationPoint = GeoPoint(
        geocoded.point.latitude,
        geocoded.point.longitude,
      );
    }
    DateTime? scheduledAt;
    if (scheduled) {
      if (!mounted) return null;
      // Q9: times are the pickup zone's local time, in the time zone its
      // config names; rider-r4-10: up to the zone's reservation horizon,
      // as on the schedule screen.
      final window = await AppScope.instance.riderConfig.bookingWindowAt(
        pickup.position.latitude,
        pickup.position.longitude,
      );
      if (!mounted) return null;
      // Owner A (v0.18.19): Book later is off in this zone: say so, book
      // nothing (the button stays on screen).
      if (!window.reservationsOn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.resErrZoneOff)));
        return null;
      }
      scheduledAt = await ScheduleDateTimeSelector.choose(
        context,
        timeZone: window.timeZone,
        horizonDays: window.horizonDays,
        freeChangeBeforeMin: window.freeChangeBeforeMin,
        tripMinutes: estimatedTripMinutes(
          GeoPoint(pickup.position.latitude, pickup.position.longitude),
          destinationPoint,
        ),
      );
      // Backing out of the time picker returns to Where to.
      if (scheduledAt == null || !mounted) return null;
    }
    return {
      'pickup': pickup.address,
      'pickupLat': pickup.position.latitude,
      'pickupLng': pickup.position.longitude,
      'pickupIsFallback': pickup.isFallback,
      'destination': destination,
      'destinationLat': destinationPoint.latitude,
      'destinationLng': destinationPoint.longitude,
      'stops': selection.stops,
      // rider-r5-36: the points the rider picked, so no stop is located
      // again from its label.
      'stopPoints': [
        for (var i = 0; i < selection.stops.length; i++)
          i < selection.stopPoints.length ? selection.stopPoints[i] : null,
      ],
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
    };
  }

  Future<void> _showRouteAddressPicker({
    required String initialField,
    EarlyInputCapture? capture,
    bool scheduled = false,
    String? initialRideId,
    GeoPoint? pickupPoint,
  }) async {
    // Either the capture the caller started at tap time, or a fresh one for
    // entry points that open the picker directly.
    final routeCapture = capture ?? (EarlyInputCapture()..start());
    final ownsCapture = capture == null;
    final gps = _gpsPickup;
    // Owner round 1: reopened from the categories screen, the picker starts
    // from the pickup the rider had confirmed, not from GPS.
    final here =
        pickupPoint ??
        (gps == null ? null : GeoPoint(gps.latitude, gps.longitude));
    Map<String, dynamic>? draft;
    try {
      draft = await Navigator.of(context).push<Map<String, dynamic>>(
        BottomToTopTransition(
          RoutePickerPage(
            pickupAddress: _placeOrNull(_pickupAddress),
            destinationAddress: _destinationAddress ?? '',
            destinationPoint: _routeDestinationPoint,
            stops: _HomeState._stopsSupported ? _routeStops : const <String>[],
            stopPoints: _HomeState._stopsSupported
                ? _routeStopPoints
                : const [],
            stopsSupported: _HomeState._stopsSupported,
            initialField: initialField,
            capture: routeCapture,
            here: here,
            homeAddress: _placeOrNull(_homeAddress),
            workAddress: _placeOrNull(_workAddress),
            savedPlaces: _places.savedPlaces,
            recent: _recentAddresses,
            onSetFavourite: (target) async {
              await _showAddressPicker(target: target);
              return _placeOrNull(
                target == 'home' ? _homeAddress : _workAddress,
              );
            },
            onPickOnMap: ({required pickup, required address}) async {
              final result = await _openPickupMapPicker(
                address,
                isDestination: !pickup,
              );
              if (result == null) return null;
              return RoutePickerMapPick(
                address: result.address,
                point: GeoPoint(
                  result.position.latitude,
                  result.position.longitude,
                ),
              );
            },
            onFinish: (selection) =>
                _confirmRouteSelection(selection, scheduled: scheduled),
          ),
        ),
      );
    } finally {
      if (ownsCapture) routeCapture.stop();
    }

    if (draft == null || !mounted) return;
    final rawPickup = draft['pickup'] as String? ?? '';
    final rawDestination = draft['destination'] as String? ?? '';
    final rawStops = (draft['stops'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .toList();
    final rawStopPoints = (draft['stopPoints'] as List<dynamic>? ?? const [])
        .map((point) => point is GeoPoint ? point : null)
        .toList();
    final routePreparationWatch = Stopwatch()..start();
    final normaliseBatch = _locationCtl.beginNormalisationBatch();
    final normalizedRoute = await Future.wait<String>([
      _normaliseAddress(rawPickup, generation: normaliseBatch),
      _normaliseAddress(rawDestination, generation: normaliseBatch),
      ...rawStops.map(
        (stop) => _normaliseAddress(stop, generation: normaliseBatch),
      ),
    ]);
    routePreparationWatch.stop();
    RouteTransitionMetrics.routePreparation(
      routePreparationWatch.elapsed,
      stopCount: rawStops.length,
    );
    var pickup = normalizedRoute[0];
    final destination = normalizedRoute[1];
    final stops = <String>[];
    final stopPoints = <GeoPoint?>[];
    final normalizedStops = normalizedRoute.skip(2).toList();
    for (var i = 0; i < normalizedStops.length; i++) {
      if (normalizedStops[i].isEmpty) continue;
      stops.add(normalizedStops[i]);
      stopPoints.add(i < rawStopPoints.length ? rawStopPoints[i] : null);
    }
    if (!mounted) return;
    final pickupLat = draft['pickupLat'] as double?;
    final pickupLng = draft['pickupLng'] as double?;
    final pickupIsFallback = draft['pickupIsFallback'] == true;
    final exactPickupPosition = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat, pickupLng)
        : (_tripPickupLatLng ?? _gpsPickup);
    if (exactPickupPosition != null) {
      pickup = await _bookingPickup(pickup, exactPickupPosition);
      if (!mounted) return;
    }
    final destinationLat = draft['destinationLat'] as double?;
    final destinationLng = draft['destinationLng'] as double?;
    final exactDestinationPosition =
        destinationLat != null && destinationLng != null
        ? LatLng(destinationLat, destinationLng)
        : null;
    // ignore: invalid_use_of_protected_member
    setState(() {
      if (pickup.isNotEmpty) _pickupAddress = pickup;
      if (exactPickupPosition != null) {
        _tripPickupLatLng = exactPickupPosition;
      }
      _destinationAddress = destination.isEmpty
          ? _destinationAddress
          : destination;
      _routeStops = stops;
      _stopFixes = (stops: List.of(stops), points: List.of(stopPoints));
      if (destination.isNotEmpty && exactDestinationPosition != null) {
        _destinationFix = (
          address: destination,
          point: GeoPoint(
            exactDestinationPosition.latitude,
            exactDestinationPosition.longitude,
          ),
        );
      }
      if (pickup.isNotEmpty) _rememberAddress(pickup);
      if (destination.isNotEmpty) _rememberAddress(destination);
      for (final stop in stops) {
        _rememberAddress(stop);
      }
    });
    await _persistAddressData();
    if (destination.isNotEmpty) {
      final pickupPosition = exactPickupPosition;
      final destinationPosition = exactDestinationPosition;
      if (pickupPosition == null || destinationPosition == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.homeChooseValidRoute)),
          );
        }
        return;
      }
      final scheduledAt = DateTime.tryParse(
        draft['scheduledAt'] as String? ?? '',
      );
      // Owner round 1: what tells a plain Back on the categories screen from
      // a booking or a schedule, which leave it another way.
      final rideBefore = AppScope.instance.ride.rideId;
      final statusBefore = AppScope.instance.ride.status;
      var scheduledHere = false;
      // Park the Home map before opening categories. Two Google Maps at once
      // crashes the browser tab on Flutter web.
      final result = await _withParkedHomeMap(() {
        return Navigator.of(context).push<Object?>(
          RideStageTransition(
            SelectRide(
              pickupAddress: pickup.isNotEmpty
                  ? pickup
                  : (_pickupAddress ?? 'Current location'),
              destinationAddress: destination,
              pickupPosition: pickupPosition,
              pickupIsFallback: pickupIsFallback,
              destinationPosition: destinationPosition,
              stops: List<String>.from(stops),
              stopPoints: List<GeoPoint?>.from(stopPoints),
              bookingMode: scheduledAt == null
                  ? BookingMode.now
                  : BookingMode.scheduled,
              lockBookingMode: scheduledAt != null,
              initialScheduledFor: scheduledAt,
              // NAV-11: a Home card asked for this category.
              initialRideId: initialRideId,
              onScheduled: (context, id) {
                scheduledHere = true;
                _scheduledInFlow = true;
                return RideScheduledPage.open(
                  context,
                  reservationId: id,
                  replace: scheduledAt == null,
                  untilHome: scheduledAt != null,
                );
              },
            ),
            settings: const RouteSettings(name: AppRoutes.selectRide),
          ),
        );
      });
      // Owner round 1: Back (the arrow or the system back) on the
      // categories screen returns to the address screen, filled with the
      // same route, instead of Home. Only for a plain Back: Home on top
      // again, no result, nothing booked or scheduled. Each reopen waits
      // for the rider, so this cannot loop.
      final ride = AppScope.instance.ride;
      final backedOut =
          mounted &&
          result == null &&
          !scheduledHere &&
          _homeIsCurrent &&
          ride.rideId == rideBefore &&
          ride.status == statusBefore;
      if (!backedOut) return;
      await _showRouteAddressPicker(
        initialField: 'destination',
        scheduled: scheduled,
        initialRideId: initialRideId,
        pickupPoint: pickupIsFallback
            ? null
            : GeoPoint(pickupPosition.latitude, pickupPosition.longitude),
      );
    }
  }

  Future<void> _openAddPlacePicker() async {
    if (_savedPlaces.length >= _HomeState._maxCustomPlaces) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.homeMaxCustomPlaces)));
      return;
    }
    const placeTypes = <String>[
      'gym',
      'mall',
      'school',
      'airport',
      'family',
      'restaurant',
      'other',
    ];
    final type = await MoveraSheet.show<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (sheetContext) {
        return PointerInterceptor(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              ResSize.w * 18,
              ResSize.h * 12,
              ResSize.w * 18,
              ResSize.h * 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ResSize.w * 42,
                  height: ResSize.h * 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCED4D8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                18.height,
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextWidget(
                    text: context.l10n.homeWhatPlaceToSave,
                    color: _HomeState._premiumInk,
                    fontSize: 17,
                    fontWeight: fwBold,
                  ),
                ),
                16.height,
                Wrap(
                  spacing: ResSize.w * 9,
                  runSpacing: ResSize.h * 9,
                  children: placeTypes.map((placeType) {
                    return Material(
                      color: const Color(0xFFF5F7F7),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => Navigator.pop(sheetContext, placeType),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResSize.w * 13,
                            vertical: ResSize.h * 11,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _placeIcon(placeType),
                                size: ResSize.h * 18,
                                color: _HomeState._premiumAccent,
                              ),
                              7.width,
                              TextWidget(
                                text: _placeLabel(placeType),
                                color: _HomeState._premiumInk,
                                fontSize: 11,
                                fontWeight: fwSemiBold,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (type == null || !mounted) return;
    await _showAddressPicker(target: 'custom', customType: type);
  }
}
