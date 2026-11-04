part of 'waiting_for_driver.dart';

extension _WaitingLive on _WaitingForDriverState {
  /// The live waiting clock while the driver is at the pickup (Q42): the
  /// TIME only (group 6 decision 4); the prices are in the Terms. The
  /// trip's own `terms` (v0.18.7) first, the zone's served config before
  /// a projection carried them.
  Widget? _waitingFeeCounter() {
    final tripTerms = _tracking.terms;
    final free = tripTerms?.freeWaitMin.round() ?? _waitingTerms?.freeWaitMin;
    final perMin = tripTerms?.waitPerMin ?? _waitingTerms?.perMin;
    if (free == null ||
        perMin == null ||
        !perMin.isPositive ||
        _tracking.status != RideStatus.driverWaiting) {
      return null;
    }
    return WaitingFeeCounter(
      // rider-u45: the server's stamp, else one start kept for the whole
      // wait (never "now" again on each rebuild).
      since:
          _tracking.waitingSince ?? (_waitingSinceFallback ??= DateTime.now()),
      freeWaitMin: free,
      perMin: perMin,
      // rider-r4-13: the server's end of the free wait, when it says.
      freeUntil: _tracking.waitingFreeUntil,
    );
  }

  /// v0.18.7: the waiting and cancel rules in words, from the trip's
  /// `terms`, else from the zone's served config (never the app's own
  /// numbers). Null until either is known.
  TripTermsLines? _termsLines() {
    final tripTerms = _tracking.terms;
    if (tripTerms != null) return TripTermsLines.fromTerms(tripTerms);
    final config = _zoneConfig;
    if (config == null || config.currency != widget.currency) return null;
    return TripTermsLines.fromConfig(config, categoryId: _categoryIdNow);
  }

  void _showQueuedCancelNotice({required bool stale}) {
    if (!mounted || _leaving) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stale
              // R-O2: dropped before it was sent; the trip moved on.
              ? rideJustChangedMessage
              : context.l10n.cancelFailedStillOn,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// RIDE-7: the stage this ride is already known to be in (a restore seeds
  /// the session from the snapshot), so tracking starts there.
  RideStatus? _knownStatus(String rideId) {
    final session = AppScope.instance.ride;
    if (session.rideId?.trim() != rideId.trim()) return null;
    final status = session.status;
    return status.isMatched ? status : null;
  }

  String _sheetSignatureFor({
    required RideStatus status,
    required MatchedDriver? driver,
    required DriverEta? eta,
  }) {
    final headline = eta?.headline(status: status) ?? context.l10n.driverFound;
    final subtitle =
        eta?.subtitle(firstName: driver?.displayFirstName, status: status) ??
        '';
    // rider-u48: in the trip the sheet's "Arrive by HH:MM" comes from the
    // live ETA, not from the constant in-trip headline, so it is part of
    // the signature too (else the sheet keeps the first arrival time).
    final arriveBy = _tripHeadline(eta, status) ?? '';
    return '${status.name}|$headline|$subtitle|${driver?.id ?? ''}'
        '|${_tracking.connectionDegraded}|$arriveBy';
  }

  /// rider-u23: the feed went straight from the dropped driver to the next
  /// one. Say so, close the old driver's arrived sheet, and announce the
  /// new driver's arrival when it comes.
  void _onDriverReplaced(MatchedDriver lost) {
    if (_arrivedSheetShowing) {
      _arrivedSheetShowing = false;
      final route = _arrivedSheetRoute;
      _arrivedSheetRoute = null;
      closeRouteByReference(route);
    }
    _arrivalAnnounced = false;
    // The next driver's arrival is news again, after a reload too.
    unawaited(_saveArrivalAnnounced(false));
    showDriverCancelledNotice(context, driverName: lost.firstName);
  }

  /// rider-u49: a reload must not show the arrived sheet the rider already
  /// dismissed, so the flag is kept with the ride's snapshot.
  Future<void> _readArrivalAnnounced(String rideId) async {
    try {
      if (await ActiveRideController.arrivalAnnounced(rideId)) {
        _arrivalAnnounced = true;
      }
    } catch (_) {
      // Unknown: the sheet may show once more, as before.
    }
    _arrivalFlagRead = true;
    if (mounted) _maybeAnnounceArrival();
  }

  Future<void> _saveArrivalAnnounced(bool announced) async {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    try {
      await ActiveRideController.rememberArrivalAnnounced(rideId, announced);
    } catch (_) {
      // Best effort: at worst the sheet shows again after a reload.
    }
  }

  /// The driver reaching pickup is easy to miss on a map the rider is not
  /// watching, so say it once and never again for this ride.
  void _maybeAnnounceArrival() {
    if (!mounted ||
        _leaving ||
        !_arrivalFlagRead ||
        _arrivalAnnounced ||
        _completedOpened ||
        _modalHandoffInProgress ||
        !_routeIsCurrent) {
      return;
    }
    final explicitArrival =
        _tracking.lastSignal == RideRealtimeSignal.driverArrived;
    if (!explicitArrival && _tracking.status != RideStatus.driverWaiting) {
      return;
    }
    _arrivalAnnounced = true;
    unawaited(_saveArrivalAnnounced(true));
    _arrivedSheetShowing = true;
    final token = ++_arrivedSheetToken;
    unawaited(
      showDriverArrivedSheet(
        context,
        driver: _tracking.driver ?? widget.driver,
        onWay: _realtime.supportsRiderSignals ? _sendOnTheWay : null,
        pin: _tracking.showPin ? _tracking.pickupPin : null,
        // The builder runs again while a closed sheet animates out.
        onRoute: (route) {
          if (token == _arrivedSheetToken) _arrivedSheetRoute = route;
        },
      ).whenComplete(() {
        if (token != _arrivedSheetToken) return;
        _arrivedSheetShowing = false;
        _arrivedSheetRoute = null;
      }),
    );
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _queueStageNavigation(RideStatus status) {
    if (!mounted || _completedOpened) return;
    _pendingStageStatus = status;
    // rider-u50: while a cancel or end-early is out the status waits here;
    // a cancel the server refuses replays it (_replayLiveStatus), where it
    // used to be dropped and Waiting stayed on a ride that was over.
    if (_leaving) return;
    _drainStageNavigation();
  }

  /// rider-u50: the cancel did not go through, so the ride goes on from
  /// whatever the live feed reported meanwhile (a completion, a no-show).
  void _replayLiveStatus() {
    if (!mounted || _leaving) return;
    _onLiveTick();
  }
}
