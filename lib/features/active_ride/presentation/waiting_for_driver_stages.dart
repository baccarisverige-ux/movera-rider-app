part of 'waiting_for_driver.dart';

extension _WaitingStages on _WaitingForDriverState {
  void _drainStageNavigation() {
    if (!mounted ||
        _leaving ||
        _completedOpened ||
        _modalHandoffInProgress ||
        !_routeIsCurrent) {
      return;
    }
    final status = _pendingStageStatus;
    if (status == null) return;
    _pendingStageStatus = null;

    if (status.isTerminal && !status.isCompletedSurface) {
      unawaited(_handleExternalTerminal(status));
      return;
    }
    if (status.isCompletedSurface) {
      unawaited(_openCompleted(status));
    }
  }

  void _maybeOpenCompleted() {
    if (!mounted || _completedOpened) return;
    final status = _tracking.status;
    if (!status.isCompletedSurface) return;
    _queueStageNavigation(status);
  }

  /// The trip to ask for again, or null when its category or payment is not
  /// known (an old snapshot): then only "Back to Home" is offered. After a
  /// driver's end it starts where the car stopped ([carStop]); after a
  /// no-show at the same pickup.
  _SearchAgainTrip? _searchAgainTrip(GeoPoint? carStop) {
    final session = AppScope.instance.ride;
    final categoryId = widget.categoryId ?? session.bookedCategoryId;
    final paymentMethodId = session.bookedPaymentMethodId;
    if (categoryId == null || paymentMethodId == null) return null;
    return _SearchAgainTrip(
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      pickupAddress: carStop == null ? _pickupAddress : '',
      pickup: carStop == null
          ? _pickupPosition
          : LatLng(carStop.latitude, carStop.longitude),
      destinationAddress: _destinationAddress,
      destination: _destinationPosition,
      stops: List<RouteStop>.from(_stops),
      fare: Money.fromLegacyMajor(_price, widget.currency),
    );
  }

  /// Books [trip] again as a new ride, priced again (a different price is
  /// asked first, as after "No driver found"), and opens the search. False
  /// when it did not happen; the caller then goes Home.
  Future<bool> _searchAgain(_SearchAgainTrip trip) async {
    final booking = BookingController();
    final navigator =
        moveraNavigatorKey.currentState ??
        Navigator.of(context, rootNavigator: true);
    try {
      final pickupAddress = await bookingPickupAddress(
        label: trip.pickupAddress,
        position: trip.pickup,
        reverse: (p) => AppScope.instance.geocoding.reverse(
          GeoPoint(p.latitude, p.longitude),
        ),
      );
      final quote = await booking.freshQuote(
        rideType: trip.categoryId,
        pickupAddress: pickupAddress,
        destinationAddress: trip.destinationAddress,
        pickupLat: trip.pickup.latitude,
        pickupLng: trip.pickup.longitude,
        destinationLat: trip.destination.latitude,
        destinationLng: trip.destination.longitude,
        stops: trip.stops,
      );
      final next = Money(quote.totalMinor, quote.currency);
      if (!mounted) return false;
      if (next != trip.fare &&
          !await showRebookPriceDialog(context, shown: trip.fare, next: next)) {
        return false;
      }
      await booking.submitFinding(
        pickupAddress: pickupAddress,
        destinationAddress: trip.destinationAddress,
        pickupLat: trip.pickup.latitude,
        pickupLng: trip.pickup.longitude,
        destinationLat: trip.destination.latitude,
        destinationLng: trip.destination.longitude,
        rideType: trip.categoryId,
        price: next.major,
        quoteId: quote.id,
        quoteSignedPayload: quote.signedPayload,
        quoteExpiresAt: quote.expiresAt,
        quoteTotalMinor: quote.totalMinor,
        quoteCurrency: quote.currency,
        paymentMethod: trip.paymentMethodId,
        rideTypeLabel: widget.rideType,
        paymentMethodLabel: widget.paymentMethod,
        notes: widget.notes,
        stops: trip.stops,
        useWalletFirst: widget.walletAmountMinor > 0,
        walletAmountMinor: widget.walletAmountMinor,
      );
      final finding = FindingDrivers(
        pickupAddress: pickupAddress,
        destinationAddress: trip.destinationAddress,
        pickupPosition: trip.pickup,
        destinationPosition: trip.destination,
        rideType: widget.rideType,
        price: next.major,
        currency: quote.currency,
        paymentMethod: widget.paymentMethod,
        walletAmountMinor: widget.walletAmountMinor,
        notes: widget.notes,
        stops: trip.stops,
      );
      // The new search starts from Home, as a booking from Select ride does:
      // what this trip stacked above Home goes, and a trip restored at the
      // root after a reload gives the root back to the search.
      navigator.popUntil((route) => route.isFirst);
      final coordinator = RideRestoreCoordinator.instance;
      if (coordinator.showing != RestoredSurface.home &&
          coordinator.replaceRootSurface(finding, RestoredSurface.finding)) {
        return true;
      }
      SheetCoordinator.instance.open(RideSheet.finding);
      unawaited(
        navigator
            .push(
              RideStageTransition(
                finding,
                settings: const RouteSettings(name: AppRoutes.findingDriver),
              ),
            )
            .whenComplete(
              () => SheetCoordinator.instance.close(RideSheet.finding),
            ),
      );
      return true;
    } catch (error) {
      AppLog.warning('ride.search_again_failed', extra: {'error': '$error'});
      if (mounted) {
        MoveraToast.show(
          context,
          BookingController.mayHaveBooked(error)
              ? context.l10n.bookingUncertain
              : context.l10n.rebookFailed,
        );
      }
      return false;
    }
  }

  Future<void> _openCompleted(RideStatus status) async {
    if (!mounted || _leaving || _completedOpened) return;
    _completedOpened = true;
    final rideId = _rideId;

    final customCompleted = widget.onCompleted;
    if (customCompleted != null) {
      _tracking.dispose();
      await _parkMapForStageChange();
      if (!mounted) return;
      await customCompleted(context, status);
      return;
    }

    // Keep the live subscription through the navigation barrier. Payment and
    // rating events can arrive while the active map is parking; disposing the
    // tracker before that barrier creates a blind window and can strand the
    // completion UI at tripCompleted.
    // N9: the fare the server settled the trip at (the booked fare, or
    // less when the driver finished before the drop-off).
    await _ride.markCompleted(status, charged: _tracking.fare);
    if (!mounted) return;
    await _parkMapForStageChange();
    if (!mounted) return;
    final trackedStatus = _tracking.status;
    final completionStatus = trackedStatus.isCompletedSurface
        ? trackedStatus
        : status;
    final completed = RideCompleted(
      status: completionStatus,
      rideId: rideId,
      realtime: widget.realtime,
      showConnectionBanner: widget.realtime == null,
    );
    final navigator = Navigator.of(context);

    // A cold restore renders Waiting inside RideRestoreGate on the Navigator
    // root. Replacing that route would dispose the gate, so Done could no
    // longer reveal Home. Swap only the gate child in that topology.
    if (!navigator.canPop()) {
      final coordinator = RideRestoreCoordinator.instance;
      if (coordinator.replaceRootSurface(completed, RestoredSurface.complete)) {
        return;
      }
    }

    // Normal Book Now has Home/Finding underneath Waiting, so replacement is
    // correct here and avoids keeping the active-ride route in the stack.
    navigator.pushReplacement(
      RideStageTransition(
        completed,
        settings: const RouteSettings(name: AppRoutes.rideCompleted),
      ),
    );
  }

  DateTime get _acceptedAt => _tracking.acceptedAt ?? _shownAt;

  /// The fee line shown before the rider confirms a cancel (contract
  /// v0.3.0 §5), from the shared calculator and the rider config. Null when
  /// on board (that is end-early: the distance driven) or when no rule
  /// applies.
  Future<String?> _cancelFeeNote() async {
    _cancelFeeChargedNow = false;
    if (_isInTrip) {
      // UI-01: end-early. The amount is the server's (the trip's `fare`
      // once it ends); the receipt that follows shows it.
      return context.l10n.bookedPriceWholeTrip(
        formatMoney(
          Money.fromLegacyMajor(_price, widget.currency),
          whole: true,
        ),
      );
    }
    // v0.18.13 (deep re-check M5): the server waives the fee while the
    // driver is not heading to the pickup; the preview says so.
    if (_tracking.headingFreeCancel &&
        _tracking.status != RideStatus.driverWaiting) {
      return L10n.current.noFeeToCancel;
    }
    final ownNote = widget.cancelFeeNote;
    if (ownNote != null) {
      try {
        return await ownNote();
      } catch (_) {
        return null;
      }
    }
    // v0.18.7: the trip's own terms (booking snapshot) first: the cancel
    // rule, and after the driver arrived the no-show fee when the zone's
    // switch is on (always free inside the free minutes after accept).
    final terms = _tracking.terms;
    if (terms != null && terms.currency == widget.currency) {
      return _termsCancelNote(terms);
    }
    try {
      final category = await _tripCategoryId();
      if (category == null) return null;
      // Q7: the fee rules of the trip's own zone, in its currency.
      final zone =
          RiderZones.byCurrency(widget.currency) ??
          RiderZones.at(_pickupPosition.latitude, _pickupPosition.longitude);
      final config = await AppScope.instance.riderConfig.forZone(zone.id);
      // Never a fee from another currency's rules.
      if (config.currency != widget.currency) return null;
      final preview = LiveCancelFeePreview.of(
        config,
        categoryId: category,
        fare: Money.fromLegacyMajor(_price, widget.currency),
        acceptedAt: _acceptedAt,
        now: WaitingForDriver.cancelFeeClock(),
      );
      if (preview == null) return null;
      if (preview.fee.isPositive) {
        _cancelFeeChargedNow = true;
        return L10n.current.cancelCostsNow(formatMoney(preview.fee));
      }
      final left = preview.freeMinutesLeft;
      // rider-r4-18: past the window of a zero-fee rule it stays free.
      if (left == 0) return L10n.current.noFeeToCancel;
      return left == 1
          ? L10n.current.cancelFreeUnderMinute
          : L10n.current.cancelFreeMinutes('$left');
    } catch (_) {
      return null;
    }
  }

  /// The cancel line from `TripProjection.terms` (v0.18.7
  /// `pickupWaiting.cancelAfterArrived`).
  String? _termsCancelNote(TripTerms terms) {
    final rule = terms.cancelRule;
    final now = WaitingForDriver.cancelFeeClock();
    final bookedPickupAt = _tracking.bookedPickupAt;
    if (_tracking.booked && bookedPickupAt != null) {
      return _bookedCancelNote(terms, bookedPickupAt, now);
    }
    // Fix job 5 (owner Q3 + Q5): a trip waiting behind the driver's current
    // one, or a late chained trip, cancels free.
    if (_tracking.chainCancelFree(now)) return L10n.current.cancelFreeChained;
    final elapsed = now.difference(_acceptedAt);
    final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
    final fare = Money.fromLegacyMajor(_price, widget.currency);
    final free = rule == null ? 0 : rule.freeMin;
    if (minutes < free) {
      final left = free - minutes;
      return left == 1
          ? L10n.current.cancelFreeUnderMinute
          : L10n.current.cancelFreeMinutes('$left');
    }
    var fee = rule == null
        ? Money(0, widget.currency)
        : CancelFeeCalculator.live(rule, fare, minutes);
    // Checker round 1: the no-show fee only once the free waiting is over
    // (`waiting.freeUntil`, the moment the driver could press no-show).
    final freeUntil =
        _tracking.waitingFreeUntil ??
        _tracking.waitingSince?.add(
          Duration(seconds: (terms.freeWaitMin * 60).round()),
        );
    if (_tracking.status == RideStatus.driverWaiting &&
        terms.cancelAfterArrivedIsNoShow &&
        terms.noShowFee.isPositive &&
        freeUntil != null &&
        !now.isBefore(freeUntil)) {
      fee = terms.noShowFee;
    }
    if (fee.isPositive) {
      _cancelFeeChargedNow = true;
      return L10n.current.cancelCostsNow(formatMoney(fee));
    }
    return L10n.current.noFeeToCancel;
  }

  /// v0.18.51 §73 (bookedRide0_18_51.fees, owner "If rider cancel do
  /// booking fee"): a booked ride's cancel — also after the driver arrived
  /// — costs the booked-ride cancel fee from the trip's reservation cancel
  /// rule (terms.cancelRule: free while minutesBeforePickup >= freeMin),
  /// feeKind cancel; never the no-show fee.
  String _bookedCancelNote(TripTerms terms, DateTime pickupAt, DateTime now) {
    final rule = terms.cancelRule;
    if (rule == null) return L10n.current.noFeeToCancel;
    final fare = Money.fromLegacyMajor(_price, widget.currency);
    // Minutes before the booked pickup time (negative once it has passed,
    // so after the driver arrived at or after it the rule's fee applies).
    final fee = CancelFeeCalculator.reservation(
      rule,
      fare,
      pickupAt.difference(now).inMinutes,
    );
    if (fee.isPositive) {
      _cancelFeeChargedNow = true;
      return L10n.current.cancelCostsNow(formatMoney(fee));
    }
    return L10n.current.noFeeToCancel;
  }

  /// The trip summary after the rider ended the trip on board (UI-01),
  /// placed like the completion screen: replacing Waiting.
  void _openEndedEarlySummary(EndedEarlyTrip trip) {
    final summary = RideCompleted(
      status: RideStatus.cancelledByRider,
      rideId: trip.rideId,
      endedEarly: trip,
      persistOnDemandState: false,
      showConnectionBanner: false,
      onClose: (context) async {
        _ride.leaveEndedEarlySummary();
        RideNavigator.home(context);
      },
    );
    final navigator = Navigator.of(context);
    if (!navigator.canPop() &&
        RideRestoreCoordinator.instance.replaceRootSurface(
          summary,
          RestoredSurface.complete,
        )) {
      return;
    }
    navigator.pushReplacement(
      RideStageTransition(
        summary,
        settings: const RouteSettings(name: AppRoutes.rideCompleted),
      ),
    );
  }

  void _showCancelProblem(RideCancelOutcome result) {
    if (result == RideCancelOutcome.stale) {
      // X7: the trip changed under the cancel. Read it again; the rider
      // decides again from what it shows now (nothing is re-sent).
      final id = _rideId?.trim();
      if (id != null && id.isNotEmpty) {
        unawaited(
          _realtime.reconnectAndResync(id).catchError((Object error) {
            AppLog.warning(
              'ride.cancel.resync_failed',
              extra: {'rideId': id, 'error': error.toString()},
            );
          }),
        );
      }
    }
    final message = switch (result) {
      RideCancelOutcome.rejected => context.l10n.cancelNoLonger,
      // R-O2 (owner's words): the trip changed just before the tap.
      RideCancelOutcome.stale => rideJustChangedMessage,
      // rider-r5-21: neither sent nor queued; nothing will retry it.
      RideCancelOutcome.unsent => context.l10n.cancelFailedTryAgain,
      _ => context.l10n.cancelUnconfirmedOffline,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  bool get _isInTrip => DriverEta.isInTrip(_tracking.status);

  /// The pickup can move until the driver is there; the destination and the
  /// stops can change until the trip ends.
  bool get _pickupEditable =>
      !_isInTrip &&
      _tracking.status != RideStatus.driverWaiting &&
      !_tracking.status.isTerminal;
  bool get _routeEditable =>
      widget.routeChangeSupported &&
      // v0.18.9: before boarding only when the zone allows it.
      (_isInTrip || _changeBeforePickup || !_serverPickupMove) &&
      !_tracking.status.isTerminal &&
      !_completedOpened;
}
