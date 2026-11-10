// Step 74 split: these State members moved verbatim out of
// waiting_for_driver.dart into an extension, where `setState` is protected.
// ignore_for_file: invalid_use_of_protected_member
part of 'waiting_for_driver.dart';

extension _WaitingCancel on _WaitingForDriverState {
  static void _showCancelFee(ScaffoldMessengerState? messenger, String? text) {
    if (messenger == null || text == null || !messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('cancel-fee-outcome'),
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _confirmCancel() async {
    if (_leaving) return;
    final feeNote = await _cancelFeeNote();
    if (!mounted || _leaving) return;
    final inTripAtOpen = _isInTrip;
    final outcome = await showCancelRideSheet(
      context,
      takingLonger: false,
      phase: inTripAtOpen ? CancelPhase.inTrip : CancelPhase.matched,
      feeNote: feeNote,
      offerDestinationChange: _routeEditable,
    );
    if (!mounted) return;
    if (outcome.changeDestination) {
      // Q2: the rider chose to change the destination instead. G7: the
      // zone's switch is read again, as for the three dots.
      if (await _routeChangeOffBeforePickup()) {
        if (mounted) _showRouteBeforePickupOff();
        return;
      }
      if (!mounted) return;
      await _changeRoute(null, RouteChangeEntry.destination);
      return;
    }
    if (!outcome.cancelled) return;
    if (inTripAtOpen != _isInTrip) {
      // rider-u54: the trip started (or ended) while the sheet was open.
      // What the rider confirmed ("Cancel ride?", free) is not what the
      // command would now do (end-early, charged for the distance): ask
      // again for the stage they are in, and send nothing on this answer.
      if (_tracking.status.isTerminal) return;
      return _confirmCancel();
    }
    if (!_isInTrip && widget.cancelFeeNote == null) {
      // rider-r5-11: the sheets wait on the rider with no time limit, and
      // the server prices the cancel when it gets it. When the free window
      // closed meanwhile (or the fee changed), show the fee and ask again.
      final noteNow = await _cancelFeeNote();
      if (!mounted || _leaving) return;
      if (noteNow != feeNote && _cancelFeeChargedNow) {
        if (_tracking.status.isTerminal) return;
        return _confirmCancel();
      }
    }
    _leaving = true;
    _cancelInFlight = true;
    setState(() {});

    try {
      final customCancel = widget.onCancel;
      if (customCancel != null) {
        // Tracking is only torn down once the custom handler has actually
        // taken over the ride; if it throws, live updates must still work.
        await customCancel(context, outcome.reasonId);
        if (!mounted) return;
        _cancelInFlight = false;
        _tracking.dispose();
        await _parkMapForStageChange();
        return;
      }

      // D-013: the server is asked first; local state only commits once it
      // has answered. Show that the request is in flight meanwhile.
      setState(() => _cancelling = true);
      // G5 live test: the stream's cancelled_by_rider can take the app Home
      // (this screen gone) before the cancel answer lands; the fee notice
      // is shown on the app's messenger all the same.
      final appMessenger = ScaffoldMessenger.maybeOf(context);
      final result = await _ride.markCancelled(
        reasonId: outcome.reasonId,
        // R-O1: nothing tracked (for example right after a reload) is
        // shown as the rule, not as "0.0 km".
        drivenMeters: _isInTrip && _tracking.drivenMeters > 0
            ? _tracking.drivenMeters
            : null,
      );
      if (!mounted) {
        if (result == RideCancelOutcome.confirmed && _ride.endedEarly == null) {
          _showCancelFee(appMessenger, riderCancelFeeText(_ride.lastCancelFee));
        }
        return;
      }
      _cancelInFlight = false;
      if (result != RideCancelOutcome.confirmed) {
        setState(() {
          _cancelling = false;
          _leaving = false;
        });
        _showCancelProblem(result);
        _replayLiveStatus();
        return;
      }
      _tracking.dispose();
      await _parkMapForStageChange();
      if (!mounted) {
        if (_ride.endedEarly == null) {
          _showCancelFee(appMessenger, riderCancelFeeText(_ride.lastCancelFee));
        }
        return;
      }
      final endedEarly = _ride.endedEarly;
      if (endedEarly != null) {
        // UI-01: an on-board end is a finished trip with a receipt, not a
        // silent return to Home.
        _openEndedEarlySummary(endedEarly);
        return;
      }
      // v0.18.7 (Q2/Q6): the rider sees the fee and its kind, never a
      // silent amount on the next quote.
      final feeText = riderCancelFeeText(_ride.lastCancelFee);
      final messenger = ScaffoldMessenger.maybeOf(context) ?? appMessenger;
      RideNavigator.home(context);
      _showCancelFee(messenger, feeText);
    } catch (error, stack) {
      final scheduled = widget.onCancel != null;
      AppScope.instance.crashes.record(
        error,
        stack,
        rideId: _rideId,
        operation: scheduled ? 'reservation.cancel' : 'ride.cancel',
      );
      if (!mounted) return;
      setState(() {
        _cancelInFlight = false;
        _cancelling = false;
        _leaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scheduled
                ? reservationErrorMessage(error, ReservationAction.cancel)
                : context.l10n.cancelFailedTryAgain,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _replayLiveStatus();
    }
  }

  /// D-014: leaving the context.l10n.cantTrackRide screen must not silently
  /// orphan a live server ride. Try a real server cancel with any ride id
  /// still on record first; only then wipe local state and go Home.
  Future<void> _leaveUntrackedRide() async {
    if (_leaving) return;
    setState(() {
      _leaving = true;
      _cancelling = true;
    });
    RideCancelOutcome? outcome;
    try {
      outcome = await _ride.cancelUntrackedRide(rideId: _rideId);
    } catch (_) {
      // rider-r5-21: nothing is known to be sent or queued.
      outcome = RideCancelOutcome.unsent;
    }
    if (!mounted) return;
    // rider-r5-21: a cancel neither sent nor queued would leave the server
    // ride and the driver going with nothing to retry it: stay and say so.
    if (outcome == RideCancelOutcome.unsent) {
      setState(() {
        _leaving = false;
        _cancelling = false;
      });
      _showCancelProblem(outcome!);
      return;
    }
    // rider-r4-25: a refused cancel is not queued; say so rather than
    // going Home as if the ride had been cancelled.
    if (outcome == RideCancelOutcome.rejected ||
        outcome == RideCancelOutcome.stale) {
      _showCancelProblem(outcome!);
    }
    RideNavigator.home(context);
  }
}
