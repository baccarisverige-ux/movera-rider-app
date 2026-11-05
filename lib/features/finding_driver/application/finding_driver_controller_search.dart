part of 'finding_driver_controller.dart';

extension _FindingDriverSearch on FindingDriverController {
  void _startTick() {
    _tick?.cancel();
    // rider-u100: the tick stops while a cancel is in flight or queued. A
    // refused cancel picks the search up at its real elapsed time, not at
    // the value it froze at.
    final behind = _sinceSearchStart() - elapsedSeconds;
    if (behind > 0) {
      elapsedSeconds += behind;
      _evaluatePhase();
      _afterElapsed(behind);
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed || _assigned || _cancelled || _terminated) {
        timer.cancel();
        return;
      }
      // rider-u94: timers stop while the app is in the background (and
      // browsers throttle hidden tabs), so each tick reads the clock: a
      // resumed tick catches up at once instead of counting from where the
      // timer was paused.
      final next = math.max(elapsedSeconds + 1, _sinceSearchStart());
      final step = next - elapsedSeconds;
      elapsedSeconds = next;
      _evaluatePhase();
      _afterElapsed(step);
      _onTick?.call(elapsedSeconds);
    });
  }

  /// Whole seconds since this search started (ARCH-3 / RIDE-5).
  int _sinceSearchStart() {
    final start = _snapshot?.searchStart;
    if (start == null) return 0;
    final since = _now().difference(start);
    return since.isNegative ? 0 : since.inSeconds;
  }

  /// The search-timeout mark and the periodic server check after it.
  void _afterElapsed(int step) {
    if (elapsedSeconds < searchTimeout.inSeconds) return;
    if (!_stillLooking) {
      _reachSearchTimeout();
      return;
    }
    final every = serverCheckEvery.inSeconds;
    if (every <= 0) return;
    final past = elapsedSeconds - searchTimeout.inSeconds;
    // A check is due whenever this step crossed a multiple of [every].
    if (past ~/ every != (past - step) ~/ every) {
      unawaited(checkServerSearchState());
    }
  }

  /// True when the rider's cancel of [id] is queued (adopted now from the
  /// outbox if the restore has not done it yet), so a server status of
  /// cancelled by rider is that cancel landing.
  Future<bool> _adoptCancelThatLanded(String id) async {
    if (_cancelQueued) return true;
    PendingCancel? queued;
    try {
      queued = await PendingCancelStore.find(id);
    } catch (_) {
      return false;
    }
    if (queued == null ||
        queued.command != PendingCancelCommand.cancel ||
        _cancelled ||
        _terminated ||
        _disposed) {
      return _cancelQueued;
    }
    _cancelQueued = true;
    _queuedReasonId ??= queued.reasonId;
    return true;
  }

  /// The snapshot with the server ordering the session holds for its ride.
  RideSnapshot _ordered(RideSnapshot snapshot) {
    final session = ride;
    if (session.rideId == null || session.rideId != snapshot.rideId) {
      return snapshot;
    }
    return snapshot.copyWith(
      version: session.authoritativeVersion,
      serverUpdatedAt: session.authoritativeUpdatedAt?.toUtc(),
    );
  }

  void _evaluatePhase() {
    if (_assigned || _cancelled || _terminated || _disposed) return;
    if (!isDelayed) return;
    if (!_delayedLogged) {
      _delayedLogged = true;
      timeoutLogs += 1;
      if (ride.status == RideStatus.findingDriver) {
        ride.localTransition(RideStatus.searchDelayed);
      }
      final snapshot = _snapshot;
      if (snapshot != null) {
        _store.save(
          _ordered(
            snapshot,
          ).copyWith(status: RideStatus.searchDelayed, savedAt: DateTime.now()),
        );
      }
      AppLog.info(
        'ride.finding.delayed',
        extra: {'rideId': _snapshot?.rideId, 'elapsed': elapsedSeconds},
      );
    }
    _reportQa();
  }

  Future<void> _loadNearby(String rideId) async {
    final requestEpoch = ++_nearbyRequestEpoch;
    // Audit Phase 5 (P5-R2): `/rides/{id}/nearby` is not in the contract and
    // movera-server answers 404 on every search; the contract wire does not
    // ask and the search shows no cars around the pickup.
    if (api.contractWire) {
      nearby = const [];
      return;
    }
    try {
      final json = await api.get('/api/v1/rides/$rideId/nearby');
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      final raw = json['vehicles'];
      if (raw is! List) return;
      final nextNearby = raw
          .whereType<Map>()
          .map(
            (item) => NearbyVehicle.fromJson(Map<String, dynamic>.from(item)),
          )
          .whereType<NearbyVehicle>()
          .toList();
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      nearby = nextNearby;
      _onTick?.call(elapsedSeconds);
    } catch (_) {
      if (_disposed ||
          _assigned ||
          _assignmentPending ||
          _cancelled ||
          _terminated ||
          requestEpoch != _nearbyRequestEpoch) {
        return;
      }
      nearby = const [];
      _onTick?.call(elapsedSeconds);
    }
  }
}
