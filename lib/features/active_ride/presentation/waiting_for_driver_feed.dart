// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingFeed on _WaitingForDriverState {
  void _retryLiveFeed() {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    _tracking.start(
      rideId: rideId,
      initial: _tracking.driver ?? widget.driver,
      onChange: _onLiveTick,
    );
    _sheetSignature = '';
    setState(() {});
  }

  void _onLiveTick() {
    if (!mounted) return;
    final status = _tracking.status;
    // G6 (owner decision 6): one short message per waiting alert, no sound.
    for (final kind in _tracking.takeNewAlerts()) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: ValueKey('waiting-alert-$kind'),
            content: Text(waitingAlertText(context.l10n, kind)),
          ),
        );
    }
    _maybeFetchPin();
    _onTripG7();
    // v0.18.7 (item 4): the server moved the pickup (`pickup_moved`).
    if (_tracking.takeMovedPickup() case final moved?) {
      final changed =
          GeoDistance.metersBetween(
            _pickupPosition.latitude,
            _pickupPosition.longitude,
            moved.lat,
            moved.lng,
          ) >
          1;
      if (changed) {
        _applyMovedPickup(
          address: moved.address,
          lat: moved.lat,
          lng: moved.lng,
        );
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.pickupMoved)));
      }
    }

    // The arrived sheet is a modal route sitting on top of this screen, so
    // stage navigation deliberately waits for it to close before acting (see
    // _drainStageNavigation's !_routeIsCurrent guard) — otherwise the trip
    // could start and finish entirely behind a sheet the rider hasn't
    // dismissed yet, and dismissing it would then jump straight to "Trip
    // complete" with the in-trip phase never shown. Close it the moment the
    // trip actually starts so the rider sees that phase instead of skipping it.
    //
    // rider-u47: a no-show or other end before the trip (the very moment the
    // arrived sheet is up) closes it too, so the rider sees the ride ended
    // instead of "Your driver has arrived" over a trip that is over.
    if (_arrivedSheetShowing &&
        (DriverEta.isInTrip(status) || status.isTerminal)) {
      _arrivedSheetShowing = false;
      // NAV-9: close the arrived sheet itself, not whatever route is on top
      // (a notification or Safety page pushed above it stays open).
      final route = _arrivedSheetRoute;
      _arrivedSheetRoute = null;
      closeRouteByReference(route);
    }

    // A driver drop is a reversible dispatch event, not the end of the
    // rider's trip. Handle it on the active Waiting owner immediately instead
    // of routing it through the generic terminal queue. The generic queue is
    // intentionally gated on route-current state; that can strand this
    // transient event when Waiting has just replaced the matching stage.
    if (status == RideStatus.cancelledByDriver) {
      if (!_leaving && !_completedOpened) {
        unawaited(_researchAfterDriverCancel());
      }
      return;
    }
    // The chat ends with the trip: no more polling for its messages.
    if (status.isTerminal || status.isCompletedSurface) {
      _messages?.stopPolling();
      // Contract v0.13.0 §22: the chat closes at drop-off.
      MessagesController.closeRide(_rideId ?? '');
    }
    final replaced = _tracking.takeReplacedDriver();
    if (replaced != null) _onDriverReplaced(replaced);

    if (status.isTerminal && !status.isCompletedSurface) {
      // The driver ended the trip with the rider on board: for Ride check
      // that is the trip's end too (was the rider left far from the
      // drop-off?), decided before the "trip ended" sheet.
      final rideId = _rideId?.trim();
      if (status == RideStatus.endedByDriver &&
          _rideCheckOnBoard &&
          rideId != null &&
          rideId.isNotEmpty) {
        _rideCheckTripEnded(rideId);
      }
      _queueStageNavigation(status);
      return;
    }
    _feedRideCheck(status);
    _maybeAnnounceArrival();
    _maybeOpenCompleted();
    _mapKey.currentState?.paintIfDue();
    final signature = _sheetSignatureFor(
      status: status,
      driver: _tracking.driver ?? widget.driver,
      eta: _tracking.eta,
    );
    if (signature == _sheetSignature) return;
    _sheetSignature = signature;
    setState(() {});
  }

  Future<void> _sendOnTheWay() async {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    if (!_realtime.supportsRiderSignals) return;
    await _realtime.sendSignal(
      rideId: rideId,
      signal: RideRealtimeSignal.riderOnTheWay,
      message: "I'm on the way",
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.sentOnTheWay),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _onNavigationChanged() {
    if (!mounted) return;
    // Route observer callbacks occur while Navigator is locked. Completion,
    // terminal and arrival surfaces can push sheets/routes, so wait one frame
    // before draining anything that was deferred behind a child route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainStageNavigation();
      if (!_leaving && !_completedOpened) _maybeAnnounceArrival();
    });
  }
}
