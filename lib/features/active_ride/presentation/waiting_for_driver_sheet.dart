part of 'waiting_for_driver.dart';

extension _WaitingSheet on _WaitingForDriverState {
  /// The live arrival time during the trip ("Arrive by 08:19"), or null
  /// while no driver ETA has arrived yet.
  String? _tripHeadline(DriverEta? eta, RideStatus status) {
    final seconds = eta?.seconds;
    if (!DriverEta.isInTrip(status) || seconds == null) return null;
    return context.l10n.arriveBy(
      clockTime(DateTime.now().add(Duration(seconds: seconds))),
    );
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
          WaitingShareButton(rideId: _rideId),
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
        onMore: widget.routeChangeSupported ? _openDetails : null,
        stopNote: _stops.isEmpty || _tracking.terms == null
            ? null
            : TripTermsLines.stopWaitLine(_tracking.terms!),
        onCancel: _confirmCancel,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaitingDriverCard(
            driver: driver,
            rideId: _rideId,
            onOpenProfile: _openProfile,
            onCall: _callDriver,
            onMore: _moreAction,
          ),
          const SizedBox(height: 12),
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
        ],
      ),
    );
  }
}
