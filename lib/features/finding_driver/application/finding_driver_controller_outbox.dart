part of 'finding_driver_controller.dart';

// The pending-cancel outbox replay behind
// [FindingDriverController.flushPendingCancels] (Rule 25 split, no
// behaviour change).

Future<Map<String, PendingCancelResult>> _flushPendingCancels(
  ApiClient client,
) async {
  final results = <String, PendingCancelResult>{};
  final session = FindingDriverController._flushSession;
  bool over() => session != FindingDriverController._flushSession;
  final pending = await PendingCancelStore.all();
  if (pending.isEmpty) return results;
  for (var cancel in pending) {
    if (over()) return results;
    if (cancel.idempotencyKey == null) {
      // Entry from before D-020: mint its one key now and keep it.
      cancel = cancel.withKey(newIdempotencyKey('ride-cancel'));
      await PendingCancelStore.add(cancel);
    }
    // R-O2: read the trip again before replaying a command queued while
    // offline. The rider tapped on a screen that may be long out of date.
    final current = await _rereadForReplay(client, cancel);
    if (over()) return results;
    if (current == null) continue; // Still unreachable: kept for later.
    PendingCancelResult? result = current.result;
    // rider-u32: what the server answered a delivered command with.
    Map<String, dynamic>? answered = current.projection;
    final reread = current.projection;
    RideStatus? endedAs = result == PendingCancelResult.ended && reread != null
        ? RideStatusWire.fromProjection(reread)
        : null;
    if (result == null) {
      final version = current.version;
      if (version != null && version != cancel.expectedVersion) {
        // Still applies on a newer trip: sent for the version it is at now,
        // so it is not refused as stale for a change that does not matter.
        cancel = cancel.forVersion(version);
        await PendingCancelStore.add(cancel);
      }
      try {
        final response = await client.post(
          client.tripPath(cancel.rideId, cancel.command.pathSegment),
          body: cancel.body(),
          idempotencyKey: cancel.idempotencyKey,
        );
        if (over()) return results;
        AppScope.instance.ride.observeProjection(response);
        answered = tripProjectionOf(response);
        result = PendingCancelResult.sent;
      } catch (error) {
        if (!isPermanentCancelFailure(error)) {
          AppLog.warning(
            'ride.cancel.flush_failed',
            extra: {'rideId': cancel.rideId, 'error': error.toString()},
          );
          continue;
        }
        if (over()) return results;
        final refusal = await _refusalResult(client, cancel, error);
        if (over()) return results;
        result = refusal.result;
        endedAs = refusal.endedAs;
        answered = (error as ApiError).projection;
      }
    }
    await PendingCancelStore.remove(cancel.rideId);
    results[cancel.rideId] = result;
    final sent = result == PendingCancelResult.sent;
    PendingCancelStore.report(
      PendingCancelOutcome(
        rideId: cancel.rideId,
        command: cancel.command,
        result: result,
        reasonId: cancel.reasonId,
        charged:
            sent &&
                answered != null &&
                cancel.command == PendingCancelCommand.endEarly
            ? Money.fromWire(answered['fare'])
            : null,
        fee: sent && answered != null
            ? RideProjection.cancellationFee(answered)
            : null,
        endedAs: endedAs,
      ),
    );
  }
  return results;
}

/// R-O2: the trip as it is now, before a queued command is replayed.
/// Null when it cannot be read (offline): the entry waits. A [result]
/// means the command is not sent at all: the trip is gone, already
/// cancelled by the rider (R-O3: that is what they asked for), over, or
/// at a stage where the command no longer applies (dropped as stale and
/// the rider is told). Otherwise [version] is the version to send.
Future<
  ({
    PendingCancelResult? result,
    int? version,
    Map<String, dynamic>? projection,
  })?
>
_rereadForReplay(ApiClient client, PendingCancel cancel) async {
  Map<String, dynamic>? projection;
  try {
    projection = tripProjectionOf(
      await client.get('/api/v1/rides/${cancel.rideId}'),
    );
  } on ApiError catch (error) {
    if (error.statusCode == 404 || error.statusCode == 410) {
      AppLog.warning(
        'ride.cancel.flush_dropped_permanent',
        extra: {'rideId': cancel.rideId, 'error': error.toString()},
      );
      return (
        result: PendingCancelResult.gone,
        version: null,
        projection: null,
      );
    }
    AppLog.warning(
      'ride.cancel.flush_reread_failed',
      extra: {'rideId': cancel.rideId, 'error': error.toString()},
    );
    return null;
  } catch (error) {
    AppLog.warning(
      'ride.cancel.flush_reread_failed',
      extra: {'rideId': cancel.rideId, 'error': error.toString()},
    );
    return null;
  }
  AppScope.instance.ride.observeProjection(projection);
  final status = TripStatusWire.parse(projection?['status']);
  final rawVersion = projection?['version'];
  final version = rawVersion is num ? rawVersion.toInt() : null;
  // A projection without a readable status says nothing about the stage:
  // the command is replayed as it was queued.
  if (status == null) {
    return (result: null, version: null, projection: projection);
  }
  if (status == TripStatus.cancelledByRider) {
    return (
      result: PendingCancelResult.sent,
      version: version,
      projection: projection,
    );
  }
  if (status.isTerminal) {
    // rider-r4-24: closed by the server or someone else, not the rider.
    return (
      result: PendingCancelResult.ended,
      version: version,
      projection: projection,
    );
  }
  // rider-u103 (RC-03): a driver accepted before a cancel queued during
  // the search reached the server. It was free when the rider tapped;
  // replayed now it would cancel the matched ride and charge the live
  // fee. It is dropped as stale and the rider decides again.
  if (cancel.whileSearching &&
      cancel.command == PendingCancelCommand.cancel &&
      tripDriverAssignedStatuses.contains(status)) {
    AppLog.warning(
      'ride.cancel.flush_dropped_overtaken_by_match',
      extra: {'rideId': cancel.rideId, 'status': status.wireName},
    );
    return (
      result: PendingCancelResult.stale,
      version: version,
      projection: projection,
    );
  }
  final command = switch (cancel.command) {
    PendingCancelCommand.cancel => 'cancel',
    PendingCancelCommand.endEarly => 'end_early',
  };
  final applies =
      TripStateMachine.apply(
        status,
        command,
        TripActor.rider,
        kind: TripKindWire.parse(projection?['kind']) ?? TripKind.live,
      ) !=
      null;
  if (!applies) {
    AppLog.warning(
      'ride.cancel.flush_dropped_stale',
      extra: {
        'rideId': cancel.rideId,
        'command': cancel.command.pathSegment,
        'status': status.wireName,
      },
    );
    return (
      result: PendingCancelResult.stale,
      version: version,
      projection: projection,
    );
  }
  return (result: null, version: version, projection: projection);
}

/// A permanent refusal: 404/410 means the ride is gone. For 409/422 the
/// ride is read again, since "a driver accepted first" and "already
/// over" both refuse (RC-03). A ride that is still live is a refusal the
/// rider must hear about; it is logged as an error, not dropped quietly.
Future<({PendingCancelResult result, RideStatus? endedAs})> _refusalResult(
  ApiClient client,
  PendingCancel cancel,
  Object error,
) async {
  final apiError = error as ApiError;
  AppScope.instance.ride.observeProjection(apiError.projection);
  // R-O3: the rider already cancelled it; nothing more to do.
  if (alreadyCancelledByRider(apiError)) {
    return (result: PendingCancelResult.sent, endedAs: null);
  }
  final status = apiError.statusCode;
  if (status == 404 || status == 410) {
    AppLog.warning(
      'ride.cancel.flush_dropped_permanent',
      extra: {'rideId': cancel.rideId, 'error': error.toString()},
    );
    return (result: PendingCancelResult.gone, endedAs: null);
  }
  RideStatus? current;
  try {
    final json = await client.get('/api/v1/rides/${cancel.rideId}');
    final projection = tripProjectionOf(json);
    if (projection != null) {
      current = RideStatusWire.fromProjection(projection);
    }
  } catch (readError) {
    AppLog.warning(
      'ride.cancel.flush_reread_failed',
      extra: {'rideId': cancel.rideId, 'error': readError.toString()},
    );
  }
  if (current == RideStatus.cancelledByRider) {
    return (result: PendingCancelResult.sent, endedAs: null);
  }
  if (current == null || !current.tripStatus.isTerminal) {
    // Live, or unknown: treated as live, so the ride stays on screen and
    // realtime shows how it really stands.
    AppLog.error(
      'ride.cancel.flush_refused_ride_live',
      extra: {
        'rideId': cancel.rideId,
        'command': cancel.command.pathSegment,
        'status': current?.name ?? 'unknown',
        'error': error.toString(),
      },
    );
    // R-O2: the trip changed between the re-read and the replay.
    return (
      result: apiError.isVersionMismatch
          ? PendingCancelResult.stale
          : PendingCancelResult.refused,
      endedAs: null,
    );
  }
  AppLog.warning(
    'ride.cancel.flush_dropped_permanent',
    extra: {'rideId': cancel.rideId, 'error': error.toString()},
  );
  // rider-r4-24: the server ended the trip some other way.
  return (result: PendingCancelResult.ended, endedAs: current);
}
