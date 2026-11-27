part of 'finding_driver_controller.dart';

extension _FindingDriverOutcome on FindingDriverController {
  /// rider-32: the driver who had accepted dropped the ride before Waiting
  /// took over. Forget the deferred match and keep the same search going.
  void _backToSearching(String id) {
    _assignmentPending = false;
    matchedDriver = null;
    ride.backendReconcile(RideStatus.findingDriver, id: id);
    _realtime.researchAfterDriverCancel();
    _onTick?.call(elapsedSeconds);
  }

  void _completeAssigned() {
    if (_assigned || _cancelled || _terminated || _disposed) return;
    if (_editInFlight || _cancelInFlight) {
      // A cancel waiting on the server decides first: if it is confirmed
      // this match is dropped; if the server refuses because the driver
      // accepted, the match completes as soon as the answer arrives.
      _assignmentPending = true;
      return;
    }
    _assignmentPending = false;
    if (_cancelQueued) {
      // RC-03: a driver accepted before the queued cancel reached the
      // server. The rider is told and moved on; the stale request leaves
      // the outbox so it cannot cancel the matched ride later.
      _cancelQueued = false;
      final id = ownedRideId;
      if (id != null) unawaited(PendingCancelStore.remove(id));
      AppLog.info(
        'ride.cancel.queued_overtaken_by_match',
        extra: {'rideId': id},
      );
      _lastRefusalStale = false;
      _onCancelRefused?.call();
    }
    _assigned = true;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    final snapshot = _snapshot;
    final matched = _onMatched;
    if (_cancelled || _terminated || _disposed) return;
    Analytics.driverFound(rideId: ride.rideId);
    if (_cancelled || _disposed) {
      if (!ride.status.isTerminal) {
        ride.localTransition(RideStatus.cancelledByRider);
      }
      unawaited(_store.clear());
      return;
    }
    if (_terminated) return;
    unawaited(_persistAssigned(snapshot, matched));
  }

  Future<void> _persistAssigned(
    RideSnapshot? snapshot,
    void Function()? matched,
  ) async {
    if (snapshot != null) {
      await _store.save(
        _ordered(snapshot).copyWith(
          status: ride.status.isMatched
              ? ride.status
              : RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          rideId: ride.rideId,
          driver: matchedDriver,
        ),
      );
    }
    if (_terminated) {
      await _store.clear();
      return;
    }
    if (_cancelled || _disposed) {
      if (!ride.status.isTerminal) {
        ride.localTransition(RideStatus.cancelledByRider);
      }
      await _store.clear();
      return;
    }
    _reportQa();
    matched?.call();
  }

  Future<void> _completeTerminal(RideStatus status) async {
    if (_terminated || _cancelled || _disposed || !status.isTerminal) return;
    _terminated = true;
    _assignmentPending = false;
    // The ride is over; this screen no longer owns a live search, so a new
    // request ("Try again") is not refused as a duplicate.
    if (identical(FindingDriverController.active, this)) {
      FindingDriverController.active = null;
    }
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _onMatched = null;
    _tick?.cancel();
    _tick = null;
    // Not awaited (as in _commitCancelled): the flags above already drop any
    // later event, and a broadcast cancel's future belongs to the root zone.
    unawaited(_sub?.cancel());
    _sub = null;
    final snapshot = _snapshot;
    if (snapshot != null &&
        (status == RideStatus.cancelledByDriver ||
            status == RideStatus.cancelledBySystem ||
            status == RideStatus.cancelledByAdmin ||
            status == RideStatus.tripFailed ||
            // RIDE-5: a search the server ended is kept in History too.
            status == RideStatus.noDriverFound ||
            status == RideStatus.bookingExpired)) {
      await _archiveTerminalRide(snapshot, status);
    }
    await _store.clear();
    _reportQa();
    if (_disposed) return;
    final callback = _onTerminal;
    if (callback != null) {
      callback(status);
    } else {
      RideNavigator.home(null, status: status);
    }
  }

  /// 2026-11-27 (stuck Finding): the trip was accepted and finished while
  /// the app was away, so the first status seen here is a completed one
  /// (`RideStatusX.isCompletedSurface`). Finding stops, keeps the ride
  /// saved with that status (the completion surface restores from it; it
  /// is never archived as cancelled) and hands over to Ride completed.
  Future<void> _completeCompleted(RideStatus status) async {
    if (_terminated || _cancelled || _disposed || _assigned) return;
    if (!status.isCompletedSurface) return;
    _terminated = true;
    _assignmentPending = false;
    _cancelQueued = false;
    if (identical(FindingDriverController.active, this)) {
      FindingDriverController.active = null;
    }
    _editEpoch += 1;
    _nearbyRequestEpoch += 1;
    _pickupUpdateEpoch += 1;
    _onMatched = null;
    _tick?.cancel();
    _tick = null;
    unawaited(_sub?.cancel());
    _sub = null;
    final id = ownedRideId;
    if (id != null) unawaited(PendingCancelStore.remove(id));
    AppLog.info(
      'ride.finding.completed_while_away',
      extra: {'rideId': id, 'status': status.name},
    );
    final snapshot = _snapshot;
    if (snapshot != null) {
      try {
        await _store.save(
          _ordered(snapshot).copyWith(
            status: status,
            savedAt: DateTime.now(),
            rideId: ride.rideId ?? snapshot.rideId,
            driver: matchedDriver ?? snapshot.driver,
          ),
        );
      } catch (error) {
        AppLog.warning(
          'ride.finding.completed_save_failed',
          extra: {'rideId': id, 'error': error.toString()},
        );
      }
    }
    _reportQa();
    if (_disposed) return;
    final callback = _onCompleted;
    if (callback != null) {
      callback(status);
    } else {
      _onTerminal?.call(status);
    }
  }

  Future<void> _archiveTerminalRide(
    RideSnapshot snapshot,
    RideStatus status,
  ) async {
    final writer =
        _historyArchiveWriter ??
        (
          RideSnapshot candidate,
          RideStatus terminalStatus,
          String? cancellationReason,
        ) => OnDemandRideHistoryStore.archive(
          candidate,
          terminalStatus: terminalStatus,
          cancellationReason: cancellationReason,
        );

    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        await writer(snapshot, status, null);
        return;
      } catch (error) {
        AppLog.warning(
          'ride.history.archive_failed',
          extra: {
            'rideId': snapshot.rideId,
            'status': status.name,
            'attempt': attempt,
            'error': error.toString(),
          },
        );
        if (attempt == 2) return;
      }
    }
  }
}
