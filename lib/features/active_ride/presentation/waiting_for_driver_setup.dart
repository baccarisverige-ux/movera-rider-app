// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingSetup on _WaitingForDriverState {
  Future<void> _loadWaitingTerms() async {
    unawaited(_loadRouteChangeRules());
    try {
      final category = await _tripCategoryId();
      if (category == null) return;
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      final rideId = _rideId?.trim();
      if (config != null && rideId != null && rideId.isNotEmpty) {
        RideCheckController.shared.setZoneRideCheck(rideId, config.rideCheck);
      }
      final terms = config?.waiting?.forCategory(category);
      if (!mounted || terms == null) return;
      // Never a rate in another currency than the trip's.
      if (terms.perMin.currency != widget.currency) return;
      setState(() {
        _waitingTerms = terms;
        _zoneConfig = config;
        _categoryIdNow = category;
      });
    } catch (_) {
      // No counter without terms.
    }
  }

  Future<void> _loadRouteChangeRules() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
        fresh: true,
      );
      if (!mounted || config == null) return;
      final rideId = _rideId?.trim();
      if (rideId != null && rideId.isNotEmpty) {
        RideCheckController.shared.setZoneRideCheck(rideId, config.rideCheck);
      }
      setState(() => _changeBeforePickup = config.routeChangeBeforePickup);
    } catch (_) {
      // The server refuses (route_change_before_pickup_off) if it must.
    }
  }

  /// RC-02/RC-03: a cancel or end-early that waited offline was refused by
  /// the server once it was sent. The ride goes on; say so.
  void _onQueuedCancelNotice(({String rideId, bool stale}) notice) {
    if (!mounted || _leaving) return;
    if (notice.rideId != _rideId?.trim()) return;
    ActiveRideController.takeQueuedCancelNotice(notice.rideId);
    _showQueuedCancelNotice(stale: notice.stale);
  }

  void _retryTracking() {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    setState(() => _missingRideId = false);
    _tracking.start(
      rideId: rideId,
      initial: widget.driver,
      onChange: _onLiveTick,
    );
  }

  /// G6: `GET /trips/{id}/pin` when the trip needs a PIN and the
  /// projection did not carry it (same value as `pickupPin`).
  void _maybeFetchPin() {
    if (_pinFetchStarted) return;
    if (!_tracking.pinRequired || _tracking.pinVerified) return;
    if (_tracking.pickupPin != null) return;
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    final api = AppScope.instance.api;
    if (!api.contractWire) return;
    _pinFetchStarted = true;
    unawaited(
      fetchTripPin(api, rideId).then((answer) {
        if (!mounted) return;
        if (answer.over) {
          _tracking.clearPin();
        } else if (answer.pin case final pin?) {
          _tracking.setFetchedPin(pin);
        } else {
          return;
        }
        setState(() {});
      }),
    );
  }
}
