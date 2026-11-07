part of 'home.dart';

// Rule 25 split (2026-11-07, no behaviour change): Home's first-fix and
// location-detection methods, moved out of home.dart unchanged.
extension _HomeLocationDetect on _HomeState {
  /// rider-u114: the notice's "Turn on" button.
  Future<void> _turnOnPreciseLocation() async {
    final wasOff = _locationCtl.preciseLocationOff;
    await _locationCtl.requestPreciseLocation();
    if (!mounted) return;
    if (!_hasFix) {
      await _detectCurrentAddress(askPermission: false);
    } else if (wasOff != _locationCtl.preciseLocationOff) {
      _applyPrecisionChange();
    }
  }

  /// Detects the rider's location once; a second call while one is running
  /// joins it, so the booking flow can wait for the fix Home already asked
  /// for instead of asking again.
  Future<void> _detectCurrentAddress({bool askPermission = true}) {
    return _detectInFlight ??=
        _runDetectCurrentAddress(askPermission: askPermission).whenComplete(() {
          _detectInFlight = null;
        });
  }

  Future<void> _runDetectCurrentAddress({bool askPermission = true}) async {
    final located = _locatedSignal = Completer<void>();
    // ignore: invalid_use_of_protected_member
    if (mounted) setState(() {});
    try {
      Future<void>? binding;
      final detected = await _locationCtl.detectCurrent(
        askPermission: askPermission,
        onQuickFix: (point) => unawaited(_showQuickFix(point)),
        // Owner round 1: puck, pickup point and camera before the address.
        onLocated: (fix) => binding ??= _bindFirstFix(fix),
      );
      if (!mounted) return;
      final target = detected.target;
      if (detected.denied || target == null) {
        // U2: no fix — never call a fallback point "Current location".
        if (isPlaceholderPickupLabel(_pickupAddress)) {
          // ignore: invalid_use_of_protected_member
          setState(() => _pickupAddress = locationOffPickupLabel);
        }
        if (detected.failure == HomeLocationFailure.unavailable && !_hasFix) {
          _scheduleDetectRetry();
        }
        return;
      }
      // An approximate fix is named no address; it is bound here.
      await (binding ??= _bindFirstFix(detected));
      if (!mounted) return;
      // The address, once the reverse geocode answers. Never over a pickup
      // set meanwhile (a flow, a dropped pin).
      if (!detected.approximate &&
          _tripPickupLatLng == null &&
          isPlaceholderPickupLabel(_pickupAddress) &&
          detected.address != _pickupAddress) {
        // ignore: invalid_use_of_protected_member
        setState(() => _pickupAddress = detected.address);
      }
    } catch (_) {
      if (!mounted) return;
      if (isPlaceholderPickupLabel(_pickupAddress)) {
        // ignore: invalid_use_of_protected_member
        setState(() => _pickupAddress = locationOffPickupLabel);
      }
    } finally {
      if (!located.isCompleted) located.complete();
    }
  }

  /// Owner round 1: the quick first position. Puck and camera at once; the
  /// accurate fix ([_bindFirstFix]) takes over when it lands.
  Future<void> _showQuickFix(LatLng point) async {
    if (!mounted || _hasFix) return;
    // ignore: invalid_use_of_protected_member
    setState(() {
      _currentLatLng = point;
      _roughFix = true;
    });
    await _prepareLocationPuckIcons();
    if (!mounted || !_roughFix) return;
    _updateLocationVisuals();
    _cameraHint = point;
    final maps = AppScope.instance.maps;
    // Map not created yet: onMapCreated centres on [_currentLatLng].
    if (_mapParked.value || maps.activeOwner != MapOwners.home) return;
    _quickCameraAt = point;
    await maps.moveCamera(
      GeoPoint(point.latitude, point.longitude),
      zoom: homeOpeningZoom,
    );
  }

  /// The accurate first fix: the pickup point, the puck, live tracking and
  /// the camera. Runs before the address is known.
  Future<void> _bindFirstFix(DetectedLocation detected) async {
    final target = detected.target;
    if (!mounted || target == null) return;
    final wasRough = _roughFix;
    _detectRetryTimer?.cancel();
    _detectRetryTimer = null;
    _detectRetries = 0;
    // ignore: invalid_use_of_protected_member
    setState(() {
      // rider-u114: an approximate fix names no pickup ('set pickup');
      // a precise one is the current location until its address comes.
      _pickupAddress = detected.approximate
          ? detected.address
          : (isPlaceholderPickupLabel(detected.address)
                ? 'Current location'
                : detected.address);
      _pickupLabelAt = target;
      _currentLatLng = target;
      _roughFix = false;
      _locationCtl.clearOverlays();
      _locationHeading = detected.heading;
    });
    final located = _locatedSignal;
    if (located != null && !located.isCompleted) located.complete();
    // The quick puck moves to the accurate point instead of blinking out.
    if (wasRough) _updateLocationVisuals();
    // Called while the geocode still runs: it handles its own errors.
    try {
      await _prepareLocationPuckIcons();
      // rider-u120: Home may have been replaced while the icons were drawn.
      if (!mounted) return;
      await _locationCtl.bindLiveLocation(
        isMounted: () => mounted,
        onFix: (latLng, heading) {
          _currentLatLng = latLng;
          _locationHeading = heading;
          _updateLocationVisuals();
          _refreshPickupLabelIfMoved(latLng);
        },
        onHeading: (heading) {
          _locationHeading = heading;
          _hasCompassHeading = true;
          _updateLocationVisuals();
        },
        onPulse: _updateLocationVisuals,
      );
      // rider-44: a late fix must not glide the map of the screen on top
      // (pickup, Set pickup, Select ride). Home's own map re-centres on
      // [_currentLatLng] when it is created again.
      final maps = AppScope.instance.maps;
      if (!mounted || _mapParked.value || maps.activeOwner != MapOwners.home) {
        return;
      }
      // Owner round 1: the camera already sits on a quick position this
      // close: no jump for a few metres of refinement.
      final quick = _quickCameraAt;
      _quickCameraAt = null;
      if (quick != null &&
          AppScope.instance.location.distanceBetween(
                quick.latitude,
                quick.longitude,
                target.latitude,
                target.longitude,
              ) <=
              HomeLocationController.quickFixRefineMeters) {
        return;
      }
      await maps.animateCamera(
        GeoPoint(target.latitude, target.longitude),
        zoom: homeOpeningZoom,
        follow: true,
      );
    } catch (_) {
      if (!mounted) return;
      if (isPlaceholderPickupLabel(_pickupAddress)) {
        // ignore: invalid_use_of_protected_member
        setState(() => _pickupAddress = locationOffPickupLabel);
      }
    }
  }
}
