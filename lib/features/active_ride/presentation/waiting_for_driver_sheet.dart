part of 'waiting_for_driver.dart';

extension _WaitingSheet on _WaitingForDriverState {
  /// The arrival time during the trip ("Arrive by 08:19"): the live ETA,
  /// else (G26 / G-S6, owner 2026-11-17) the planned time from the trip
  /// start, so the title does not jump when the first ETA arrives.
  String? _tripHeadline(DriverEta? eta, RideStatus status) {
    if (!DriverEta.isInTrip(status)) return null;
    final now = DateTime.now();
    final at = tripArrivalAt(
      status: status,
      liveSeconds: eta?.seconds,
      plannedFrom: _tripStartedAt ??= now,
      pickup: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      stops: [for (final s in _stops) GeoPoint(s.latitude, s.longitude)],
      destination: GeoPoint(
        _destinationPosition.latitude,
        _destinationPosition.longitude,
      ),
      now: now,
    );
    return at == null ? null : context.l10n.arriveBy(clockTime(at));
  }

  /// Headline for the sheet: the arrival time during the trip, the stage
  /// name without an ETA, and the driver's ETA to the pickup before it.
  String _headlineFor(DriverEta? eta, RideStatus status) {
    // N10: once the trip is over the sheet behind the end sheet says how it
    // ended, never the driver's last distance ("Driver is almost there").
    if (status.isTerminal && !status.isCompletedSurface) {
      return RideTerminalStateSpec.fromStatus(status).title;
    }
    final live = _tripHeadline(eta, status);
    if (live != null) return live;
    if (DriverEta.isInTrip(status)) {
      return status == RideStatus.approachingDropoff
          ? context.l10n.approachingDestination
          : context.l10n.etaRideInProgress;
    }
    return eta?.headline(status: status) ?? context.l10n.driverFound;
  }

  double _sheetOffset(MediaQueryData media) {
    if (!_sheetController.hasClient) return _minSheet(media);
    return _sheetController.metrics?.offset ?? _minSheet(media);
  }

  /// 0 at the low stop, 1 from the middle stop up.
  double _openness(MediaQueryData media) {
    final low = _collapsedSheet(media);
    final mid = _minSheet(media);
    return ((_sheetOffset(media) - low) / (mid - low)).clamp(0.0, 1.0);
  }

  /// Full content fades and slides in as the sheet rises from the low stop,
  /// staggered by [start] so it settles in layers.
  Widget _reveal(
    MediaQueryData media, {
    required double start,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _sheetController,
      builder: (context, child) {
        final open = _openness(media);
        final t = Curves.easeOutCubic.transform(
          ((open - start) / (1 - start)).clamp(0.0, 1.0),
        );
        return IgnorePointer(
          ignoring: open < 0.5,
          child: ExcludeSemantics(
            excluding: open < 0.5,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - t)),
                child: child,
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }

  Widget _fixedPickupHeader(
    MatchedDriver? driver,
    String headline,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: waitingText(22, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: waitingText(14, color: const Color(0xFF5C656C)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WaitingShareButton(
            rideId: _rideId,
            status: _tracking.status,
            driverShown: driver != null,
          ),
        ],
      ),
    );
  }

  Widget _panel(MatchedDriver? driver) {
    if (_isInTrip) {
      return RiderInTripPanel(
        headline: _tripHeadline(_tracking.eta, _tracking.status),
        destinationAddress: _destinationAddress,
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        walletAmountMinor: widget.walletAmountMinor,
        price: _price,
        currency: widget.currency,
        driver: driver,
        rideId: _rideId,
        status: _tracking.status,
        onOpenProfile: _openProfile,
        onCall: _callDriver,
        // v0.18.9 (G7 decision 3): the destination and the stops change
        // on board too (the server prices it, the driver answers).
        // Owner 2026-11-23: the menu is always there (end-trip row).
        onMore: _openDetails,
        stopNote: _stops.isEmpty || _tracking.terms == null
            ? null
            : TripTermsLines.stopWaitLine(_tracking.terms!),
        // v0.18.108 (contract.json#autoArrive.stops, job C9b): the stop
        // wait stands still while the driver is away from the stop.
        stopPaused: _tracking.stopAway,
        onCancel: _confirmCancel,
      );
    }

    return SingleChildScrollView(
      // The sheet's own scroll controller, so the drag is shared.
      primary: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner 2026-11-23 (APPROVED-driver-coming.html): the approved
          // animation at the top of the panel.
          const Center(child: DriverComingAnimation()),
          const SizedBox(height: 8),
          // v0.18.155 (contract.json#driverProfile, owner 2026-11-20 "Add
          // card like that"): the new card in the same place; a tap opens
          // the profile sheet. Zone switch off: the old block, as before.
          if (DriverProfileSettings.current.on)
            DriverOnWayCard(
              driver: driver,
              rideId: _rideId,
              onOpenProfile: _openProfile,
              onCall: _callDriver,
              onMore: _moreAction,
            )
          else
            WaitingDriverCard(
              driver: driver,
              rideId: _rideId,
              onOpenProfile: _openProfile,
              onCall: _callDriver,
              onMore: _moreAction,
            ),
          const SizedBox(height: 12),
          _locationTools(driver),
          if (_tracking.showPin) ...[
            TripPinCard(pin: _tracking.pickupPin!),
            const SizedBox(height: 12),
          ],
          if (_waitingFeeCounter() case final counter?) ...[
            counter,
            const SizedBox(height: 12),
          ],
          WaitingRideDetailsCard(
            rideType: widget.rideType,
            pickupAddress: _pickupAddress,
            destinationAddress: _destinationAddress,
            inTrip: _isInTrip,
            paymentMethod: widget.paymentMethod,
            walletAmountMinor: widget.walletAmountMinor,
            price: _price,
            currency: widget.currency,
            onMore: _rideCardMore,
          ),
          if (_termsLines() case final lines?) ...[
            const SizedBox(height: 12),
            TripTermsNote(lines: lines),
          ],
          WaitingNotesAndPin(notes: widget.notes, rideId: _rideId),
          // Owner 2026-11-23: the games row at the bottom of this sheet too
          // (stops when the trip starts or ends).
          const SizedBox(height: 16),
          SearchGamesRow(active: !_tracking.status.isTerminal),
        ],
      ),
    );
  }
}
