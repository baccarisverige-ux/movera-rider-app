part of 'finding_driver_controller.dart';

extension _FindingDriverCancel on FindingDriverController {
  Future<SearchCancelResult> _requestServerCancel(
    String id, {
    String? reasonId,
  }) async {
    // R-O2: the trip version this search last saw, kept with the entry so
    // a retry is the same request (same key, same body).
    PendingCancel entry;
    var outboxed = true;
    try {
      entry = await PendingCancelStore.enqueue(
        rideId: id,
        reasonId: reasonId,
        expectedVersion: ride.projectionVersionOf(id),
        whileSearching: true,
      );
    } catch (error) {
      // rider-u98: storage refused the entry (e.g. a full web
      // localStorage). The server is still asked, with a key for this
      // attempt only.
      AppLog.warning(
        'ride.cancel.outbox_write_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
      outboxed = false;
      entry = PendingCancel(
        rideId: id,
        reasonId: reasonId,
        idempotencyKey: newIdempotencyKey('ride-cancel'),
        expectedVersion: ride.projectionVersionOf(id),
        whileSearching: true,
      );
    }
    // One in-session retry, only for an unreachable server: a refusal is
    // final and is never sent again.
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final response = await api.post(
          '/api/v1/rides/$id/cancel',
          body: entry.body(reasonId),
          idempotencyKey: entry.idempotencyKey,
        );
        await FindingDriverController._forgetOutboxEntry(id);
        ride.observeProjection(response);
        return SearchCancelResult.confirmed;
      } catch (error) {
        AppLog.warning(
          'ride.cancel.adapter_failed',
          extra: {'rideId': id, 'error': error.toString(), 'attempt': attempt},
        );
        if (isPermanentCancelFailure(error)) {
          // D-020: retrying can never succeed, so the entry leaves the outbox.
          await FindingDriverController._forgetOutboxEntry(id);
          ride.observeProjection((error as ApiError).projection);
          // R-O3: already cancelled by the rider is what they asked for.
          if (alreadyCancelledByRider(error)) {
            return SearchCancelResult.confirmed;
          }
          final status = error.statusCode;
          if (status == 404) return SearchCancelResult.confirmed;
          if (error.isVersionMismatch) return SearchCancelResult.stale;
          // rider-u99: a 409 means the ride moved on first. Only a matched
          // trip is "a driver already accepted"; one that ended (expired,
          // no driver, an admin or system cancel) can no longer be
          // cancelled, and realtime brings its outcome.
          final projection = error.projection;
          final now = projection == null
              ? null
              : RideStatusWire.fromProjection(projection);
          return status == 409 && (now == null || now.isMatched)
              ? SearchCancelResult.driverAccepted
              : SearchCancelResult.rejected;
        }
      }
    }
    // Still unreachable: the outbox entry, with its key, stays for the
    // reconnect / next-launch flush. Without one nothing would retry it.
    return outboxed ? SearchCancelResult.queued : SearchCancelResult.unsent;
  }

  /// A restored search whose cancel is still in the outbox shows it as
  /// cancelling (RC-03) and tries to send it.
  Future<void> _adoptQueuedCancel(String? rideId) async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty) return;
    PendingCancel? queued;
    try {
      queued = await PendingCancelStore.find(id);
    } catch (_) {
      return;
    }
    if (queued == null ||
        queued.command != PendingCancelCommand.cancel ||
        ownedRideId != id ||
        _cancelled ||
        _cancelInFlight ||
        _terminated ||
        _disposed ||
        _assigned) {
      return;
    }
    _cancelQueued = true;
    _queuedReasonId = queued.reasonId;
    _tick?.cancel();
    _tick = null;
    _onTick?.call(elapsedSeconds);
    _reportQa();
    _flushQueuedCancel();
  }

  void _flushQueuedCancel() {
    unawaited(
      FindingDriverController.flushPendingCancels(api: api).catchError((
        Object error,
      ) {
        AppLog.warning(
          'ride.cancel.flush_failed',
          extra: {'rideId': ownedRideId, 'error': error.toString()},
        );
        return const <String, PendingCancelResult>{};
      }),
    );
  }

  /// The server confirmed the queued cancel: commit it now and leave.
  Future<void> _confirmQueuedCancel() async {
    if (!_cancelQueued || _cancelled || _terminated || _disposed) return;
    _cancelQueued = false;
    await _commitCancelled(reasonId: _queuedReasonId);
    // rider-u102: the entry is done. Left in the outbox, a reason the rider
    // gives next would be attached to it and dropped unsent by the flush,
    // which finds the trip already cancelled.
    final id = ownedRideId;
    if (id != null && id.isNotEmpty) {
      try {
        await PendingCancelStore.remove(id);
      } catch (_) {
        // The flush drops it once it reads the trip cancelled.
      }
    }
    if (_disposed) return;
    final callback = _onTerminal;
    if (callback != null) {
      callback(RideStatus.cancelledByRider);
    } else {
      RideNavigator.home(null, status: RideStatus.cancelledByRider);
    }
  }
}
