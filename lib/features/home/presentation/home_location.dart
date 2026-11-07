part of 'home.dart';

extension _HomeLocation on _HomeState {
  Future<void> _persistAddressData() => _places.persist();

  /// Batch 10 Phase 110: centre the camera on a fast cached fix while the
  /// accurate one is fetched. Camera only — pickup, the puck and
  /// [_currentLatLng] stay owned by [_detectCurrentAddress], whose accurate
  /// fix still moves the camera when it lands.
  Future<void> _centerCameraOnQuickFix() async {
    final hint = await _locationCtl.quickCameraFix();
    if (!mounted) return;
    // Owner decision "Home map start": the map opens right here.
    if (hint != null) _openMapAt(_currentLatLng ?? hint);
    if (hint == null || _currentLatLng != null) return;
    _cameraHint = hint;
    final maps = AppScope.instance.maps;
    // Map not created yet: onMapCreated picks the hint up.
    if (maps.activeOwner != MapOwners.home) return;
    _quickCameraAt = hint;
    await maps.moveCamera(
      GeoPoint(hint.latitude, hint.longitude),
      zoom: homeOpeningZoom,
    );
  }

  void _scheduleDetectRetry() {
    _detectRetryTimer?.cancel();
    // 2, 4, 8, 16, then 30 s: the live stream's resubscribe backoff.
    final delay = Duration(
      seconds: math.min(30, 2 << _detectRetries.clamp(0, 4)),
    );
    _detectRetries += 1;
    _detectRetryTimer = Timer(delay, () {
      _detectRetryTimer = null;
      if (!mounted || _hasFix) return;
      // Parked under a ride screen or in the background: keep waiting (the
      // booking flow and an app resume ask for their own fix).
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_mapParked.value ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        _scheduleDetectRetry();
        return;
      }
      unawaited(_detectCurrentAddress());
    });
  }

  /// rider-u114: reads the accuracy grant again; when it changed, the
  /// pickup label follows (the 'set pickup' state, or the current location
  /// again). Never over a pickup the rider chose or during a flow.
  Future<void> _recheckPrecision() async {
    final changed = await _locationCtl.recheckPrecision();
    if (changed) _applyPrecisionChange();
  }

  void _applyPrecisionChange() {
    if (!mounted ||
        _routeFlowOpen ||
        _mapParkingGuard.isParked ||
        _tripPickupLatLng != null) {
      return;
    }
    _resetPickupLabel();
  }

  /// Waits briefly for a location fix when none has landed yet (first fix
  /// still coming, permission prompt open). Null when there is still none.
  Future<LatLng?> _awaitCurrentFix() async {
    final known = _tripPickupLatLng ?? _gpsPickup;
    if (known != null) return known;
    // rider-u114: an approximate fix is no pickup; waiting brings no better.
    if (_locationCtl.preciseLocationOff) return null;
    final hint = Timer(const Duration(milliseconds: 700), () {
      if (mounted) MoveraToast.show(context, context.l10n.homeFindingLocation);
    });
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    try {
      // Two tries: the first may only join Home's own request, which can be
      // about to time out (the prompt kept it waiting); the second starts
      // fresh once permission is granted.
      for (var attempt = 0; attempt < 2; attempt++) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        // rider-43: only the first try may show the permission prompt; the
        // second never asks again right after a "Deny".
        final detecting = _detectCurrentAddress(askPermission: attempt == 0);
        // Owner round 1: the accurate point is enough; the address it is
        // still being named with fills in on its own.
        final located = _locatedSignal?.future;
        await (located == null
                ? detecting
                : Future.any<void>([detecting, located]))
            .timeout(left, onTimeout: () {});
        if (!mounted) return null;
        final fix = _tripPickupLatLng ?? _gpsPickup;
        if (fix != null) return fix;
      }
    } catch (_) {
      // No fix: the caller falls back to a placeholder point.
    } finally {
      hint.cancel();
    }
    return _tripPickupLatLng ?? _gpsPickup;
  }

  String _shortAddress(String? address, {int maxLength = 24}) {
    final value = L10n.place(address?.trim() ?? '');
    if (value.isEmpty) return context.l10n.setLocation;
    return value.length <= maxLength
        ? value
        : '${value.substring(0, maxLength - 1)}…';
  }

  String _targetTitle(String target, String? customType) {
    switch (target) {
      case 'pickup':
        return context.l10n.choosePickup;
      case 'home':
        return context.l10n.setHomeAddress;
      case 'work':
        return context.l10n.setWorkAddress;
      case 'custom':
        return context.l10n.setPlaceAddress(_placeLabel(customType ?? 'other'));
      default:
        return context.l10n.whereTo;
    }
  }

  String? _existingAddressFor(String target) => _places.existingFor(target);

  Future<String> _normaliseAddress(String input, {int? generation}) {
    return _locationCtl.normaliseAddress(input, generation: generation);
  }

  Future<void> _moveMapToAddress(String address) async {
    final target = await _locationCtl.geocodeLatLng(address);
    if (target == null) return;
    await AppScope.instance.maps.animateCamera(
      GeoPoint(target.latitude, target.longitude),
      zoom: 15,
    );
  }

  void _rememberAddress(String address) {
    // D-004: raw "lat, lng" strings and placeholders are not places; never
    // offer them back as Recents.
    if (isRawCoordinateLabel(address) || isPlaceholderPickupLabel(address)) {
      return;
    }
    _places.remember(address);
  }

  Future<String> _bookingPickup(String label, LatLng position) =>
      bookingPickupAddress(
        label: label,
        position: position,
        reverse: (point) => AppScope.instance.geocoding.reverse(
          GeoPoint(point.latitude, point.longitude),
        ),
      );
}
