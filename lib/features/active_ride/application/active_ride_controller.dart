import 'dart:async';

import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/active_ride/data/active_ride_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';

/// What the server said about a Waiting/in-trip cancel request (D-013).
enum RideCancelOutcome {
  /// The server acknowledged the cancel (or no longer has the ride at all),
  /// and local state has now been committed to cancelled.
  confirmed,

  /// The server could not be reached. Nothing was committed locally — the
  /// ride is still live — and the request sits in the pending-cancel outbox
  /// so the next reconnect or launch retries it with the same key.
  pendingRetry,

  /// The server refused: the ride can no longer be cancelled (for example it
  /// already finished). Nothing was committed locally.
  rejected,

  /// The server refused with `409 version_mismatch` (X7): the trip changed
  /// since it was read. Nothing was committed or re-sent; the screen
  /// refreshes the ride and the rider decides again.
  stale,
}

/// UI-01: an on-board "cancel" is the contract's `end_early` — the trip
/// ends where the rider is and they pay for the distance driven. What the
/// server said the rider pays, for the receipt and History.
class EndedEarlyTrip {
  const EndedEarlyTrip({required this.rideId, this.charged, this.drivenMeters});

  final String rideId;

  /// The trip's `fare` after end-early (contract v0.3.0: the authoritative
  /// amount the rider pays). Null when the server did not send one.
  final Money? charged;

  /// R-O1: how far the trip went with the rider on board, for the receipt.
  /// Contract v0.3.0 has no driven distance on the projection, so this is
  /// the route progress the app tracked from the driver's fixes
  /// (DriverTrackingController.drivenMeters). Null when none was tracked.
  final int? drivenMeters;
}

class ActiveRideController {
  ActiveRideController({ActiveRideRepository? store, ApiClient? api})
    : _store = store ?? ActiveRideRepository(),
      _api = api;
  final ActiveRideRepository _store;
  final ApiClient? _api;

  ApiClient get api => _api ?? AppScope.instance.api;

  /// RC-02/RC-03: ride ids whose queued cancel or end-early the server
  /// refused once it was sent, while the ride goes on.
  static Stream<String> get queuedCancelRefusals => PendingCancelStore
      .outcomes
      .where((outcome) => outcome.result == PendingCancelResult.refused)
      .map((outcome) => outcome.rideId);

  /// Refusals and R-O2 stale drops of a queued cancel or end-early: what
  /// the screen showing the ride tells the rider. `stale`: dropped before
  /// it was sent because the trip moved on; otherwise the server refused.
  static Stream<({String rideId, bool stale})> get queuedCancelNotices =>
      PendingCancelStore.outcomes
          .where(
            (outcome) =>
                outcome.result == PendingCancelResult.refused ||
                outcome.result == PendingCancelResult.stale,
          )
          .map(
            (outcome) => (
              rideId: outcome.rideId,
              stale: outcome.result == PendingCancelResult.stale,
            ),
          );

  /// The untold refusal (false) or stale drop (true) of [rideId]'s queued
  /// cancel, once; null when there is none. A launch flush can answer
  /// before the ride's screen exists (cold restore).
  static bool? takeQueuedCancelNotice(String rideId) {
    final notice = PendingCancelStore.takeNotice(rideId);
    if (notice == null) return null;
    return notice == PendingCancelResult.stale;
  }

  /// Set by [markCancelled] when the confirmed command was end-early.
  EndedEarlyTrip? get endedEarly => _endedEarly;
  EndedEarlyTrip? _endedEarly;

  /// The rider left the ended-early summary: it no longer describes a
  /// ride in hand (History keeps the record).
  void leaveEndedEarlySummary() {
    _endedEarly = null;
    LastCompletedRide.clear();
  }

  void markArriving() {
    AppScope.instance.ride.localTransition(RideStatus.driverArriving);
  }

  /// Cancels a matched or in-trip ride, server first (D-013).
  ///
  /// This used to commit `cancelledByRider` locally, archive the ride, clear
  /// the snapshot and stop realtime, and only then fire one unawaited POST.
  /// If that call failed the rider was on Home while the server ride — and
  /// the driver — kept going. Now the intent is written to the pending-cancel
  /// outbox first, the server is asked (one in-session retry, same key), and
  /// local state is committed only once the server has answered.
  ///
  /// [drivenMeters] is the distance the app tracked on board, shown on the
  /// ended-early receipt (R-O1).
  Future<RideCancelOutcome> markCancelled({
    String? reasonId,
    int? drivenMeters,
  }) async {
    final ride = AppScope.instance.ride;
    final id = ride.rideId?.trim();
    if (id == null || id.isEmpty) {
      // No server identity to cancel against. Be explicit that this is a
      // local-only cancel rather than implying the server was told.
      AppLog.warning(
        'ride.cancel.local_only_no_ride_id',
        extra: {'status': ride.status.name},
      );
      await _commitCancelled(null, reasonId: reasonId);
      return RideCancelOutcome.confirmed;
    }
    final result = await _requestServerCancel(id, reasonId: reasonId);
    if (result.outcome == RideCancelOutcome.confirmed) {
      final endedEarly = result.command == PendingCancelCommand.endEarly
          ? EndedEarlyTrip(
              rideId: id,
              charged: result.charged,
              drivenMeters: drivenMeters,
            )
          : null;
      _endedEarly = endedEarly;
      await _commitCancelled(id, reasonId: reasonId, endedEarly: endedEarly);
    }
    return result.outcome;
  }

  /// Commits a cancel the server has already applied — for example when a
  /// queued outbox request lands and realtime then reports the ride as
  /// `cancelledByRider` while Waiting is still showing it.
  Future<void> completeServerConfirmedCancel() async {
    await _commitCancelled(AppScope.instance.ride.rideId);
  }

  /// D-014: "Go home" from the screen shown when Waiting lost its rideId.
  ///
  /// That used to be a purely local `cancelledByRider` transition, which can
  /// orphan a live server ride. Recover any ride id still on record (the
  /// explicit one, the session, or the persisted snapshot) and ask the server
  /// to cancel it before local state is wiped. A transient failure leaves the
  /// request in the outbox. When no id is recoverable at all there is no way
  /// to cancel server-side; say so in telemetry instead of pretending.
  Future<RideCancelOutcome?> cancelUntrackedRide({String? rideId}) async {
    String? recovered = _clean(rideId) ?? _clean(AppScope.instance.ride.rideId);
    if (recovered == null) {
      final snapshot = await _store.historyCandidate();
      recovered = _clean(snapshot?.rideId);
    }
    if (recovered == null) {
      AppLog.warning(
        'ride.cancel.unrecoverable_ride_id',
        extra: {
          'status': AppScope.instance.ride.status.name,
          'serverCancelled': false,
        },
      );
      return null;
    }
    final outcome = (await _requestServerCancel(recovered)).outcome;
    AppLog.info(
      'ride.cancel.untracked_ride',
      extra: {'rideId': recovered, 'outcome': outcome.name},
    );
    return outcome;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<
    ({RideCancelOutcome outcome, PendingCancelCommand command, Money? charged})
  >
  _requestServerCancel(String id, {String? reasonId}) async {
    // Contract v0.3.0: once the rider is on board the command is
    // `end_early` (pay for the distance driven), not `cancel`. The outbox
    // keeps which one, so a retry after reconnect sends the same (RC-02).
    final onboard = tripRiderOnboardStatuses.contains(
      AppScope.instance.ride.status.tripStatus,
    );
    final command =
        onboard ? PendingCancelCommand.endEarly : PendingCancelCommand.cancel;
    final session = AppScope.instance.ride;
    // R-O2: the trip version this screen last saw. The outbox keeps it, so
    // a retry sends the same request (same key, same body).
    final entry = await PendingCancelStore.enqueue(
      rideId: id,
      reasonId: reasonId,
      command: command,
      expectedVersion: session.projectionVersionOf(id),
    );
    // One in-session retry, only for an unreachable server: a refusal is
    // final and is never sent again (no automatic retry).
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final response = await api.post(
          '/api/v1/rides/$id/${entry.command.pathSegment}',
          body: entry.body(reasonId),
          idempotencyKey: entry.idempotencyKey,
        );
        await PendingCancelStore.remove(id);
        session.observeProjection(response);
        return (
          outcome: RideCancelOutcome.confirmed,
          command: entry.command,
          charged: _chargedFare(response),
        );
      } catch (error) {
        AppLog.warning(
          'ride.cancel.adapter_failed',
          extra: {'rideId': id, 'error': error.toString(), 'attempt': attempt},
        );
        if (isPermanentCancelFailure(error)) {
          await PendingCancelStore.remove(id);
          final apiError = error as ApiError;
          session.observeProjection(apiError.projection);
          // R-O3: the trip is already cancelled by the rider (a repeat
          // after a lost answer, or a server that refuses a second
          // cancel): that is what the rider asked for, quietly.
          if (alreadyCancelledByRider(apiError)) {
            return (
              outcome: RideCancelOutcome.confirmed,
              command: entry.command,
              charged: _chargedFare({'projection': apiError.projection}),
            );
          }
          // 404: the server has no such ride, so there is nothing left to
          // cancel and nothing to orphan. 409/410/422: the server refuses —
          // the ride already ended — so the local ride must not be marked
          // cancelled; realtime reports the real outcome.
          final status = apiError.statusCode;
          return (
            outcome: status == 404
                ? RideCancelOutcome.confirmed
                : apiError.isVersionMismatch
                ? RideCancelOutcome.stale
                : RideCancelOutcome.rejected,
            command: entry.command,
            charged: null,
          );
        }
      }
    }
    return (
      outcome: RideCancelOutcome.pendingRetry,
      command: entry.command,
      charged: null,
    );
  }

  /// The projection's `fare` in a command response (`projection`, or the
  /// pre-v0.3 `ride` alias).
  static Money? _chargedFare(Map<String, dynamic> response) {
    final ride = response['projection'] ?? response['ride'];
    return ride is Map ? Money.fromWire(ride['fare']) : null;
  }

  Future<void> _commitCancelled(
    String? id, {
    String? reasonId,
    EndedEarlyTrip? endedEarly,
  }) async {
    final snapshot = await _store.historyCandidate();
    final ride = AppScope.instance.ride;
    if (ride.status != RideStatus.cancelledByRider && !ride.status.isTerminal) {
      ride.localTransition(RideStatus.cancelledByRider);
    }
    AppScope.instance.rideRealtime.cancelRide();
    _stopSafetyRecording();
    if (endedEarly != null && snapshot != null) {
      // The receipt shown next describes this trip (UI-01).
      LastCompletedRide.remember(
        snapshot,
        charged: endedEarly.charged,
        endedEarly: true,
        drivenMeters: endedEarly.drivenMeters,
      );
    }
    await _archive(
      snapshot,
      RideStatus.cancelledByRider,
      expectedRideId: id,
      cancellationReason: reasonId,
      endedEarly: endedEarly,
    );
    await _store.clear();
  }

  Future<void> resumeSearchingAfterDriverCancel({String? rideId}) async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty) return;
    final ride = AppScope.instance.ride;
    if (ride.rideId?.trim() != id ||
        ride.status != RideStatus.cancelledByDriver) {
      return;
    }

    // cancelledByDriver is a reversible dispatch outcome: the rider still owns
    // the same ride, and the search restarts on its own. Reconcile shared
    // application state synchronously before navigation can reveal the parked
    // Finding route. Snapshot persistence is deliberately not on this critical
    // path: DriverTracking never persisted the terminal driver-drop snapshot,
    // so the existing active snapshot already remains the correct recovery
    // record until realtime publishes the replacement search/assignment.
    ride.backendReconcile(RideStatus.findingDriver, id: id);
  }

  Future<void> markExternalTerminal(RideStatus status) async {
    if (!status.isTerminal ||
        status.isCompletedSurface ||
        status == RideStatus.cancelledByRider ||
        status == RideStatus.closed) {
      throw ArgumentError.value(
        status,
        'status',
        'Expected a non-rider external terminal status.',
      );
    }
    final snapshot = await _store.historyCandidate();
    final ride = AppScope.instance.ride;
    final id = ride.rideId;
    ride.backendReconcile(status, id: id);
    _stopSafetyRecording();
    if (status == RideStatus.cancelledByDriver ||
        status == RideStatus.cancelledBySystem ||
        status == RideStatus.cancelledByAdmin ||
        status == RideStatus.endedByDriver ||
        status == RideStatus.noShow ||
        status == RideStatus.tripFailed) {
      await _archive(snapshot, status, expectedRideId: id);
    }
    await _store.clear();
  }

  Future<void> markCompleted(RideStatus status) async {
    if (!status.isCompletedSurface) {
      throw ArgumentError.value(status, 'status', 'Expected a completed status.');
    }
    final snapshot = await _store.historyCandidate();
    final id = AppScope.instance.ride.rideId;
    AppScope.instance.ride.backendReconcile(status, id: id);
    _stopSafetyRecording();
    if (snapshot == null) return;

    // Keep a restorable completion snapshot until the rider explicitly leaves
    // the completion surface. This protects payment/rating state across reload,
    // crash, PWA eviction and app resume.
    final completed = snapshot.copyWith(
      status: status,
      savedAt: DateTime.now(),
    );
    LastCompletedRide.remember(completed);
    await _archive(completed, status, expectedRideId: id);
    await _store.save(completed);
  }

  Future<void> persistCompletedStatus(
    RideStatus status, {
    required String rideId,
  }) async {
    if (!status.isCompletedSurface) {
      throw ArgumentError.value(status, 'status', 'Expected a completed status.');
    }
    final snapshot = await _store.historyCandidate();
    if (snapshot == null || snapshot.rideId?.trim() != rideId.trim()) return;
    final updated = snapshot.copyWith(
      status: status,
      savedAt: DateTime.now(),
    );
    LastCompletedRide.remember(updated);
    await _store.save(updated);
  }

  Future<void> _archive(
    RideSnapshot? snapshot,
    RideStatus status, {
    String? expectedRideId,
    String? cancellationReason,
    EndedEarlyTrip? endedEarly,
  }) async {
    if (snapshot == null) return;
    final snapshotId = snapshot.rideId?.trim();
    if (expectedRideId != null &&
        expectedRideId.trim().isNotEmpty &&
        snapshotId != expectedRideId.trim()) {
      AppLog.warning(
        'ride.history.snapshot_mismatch',
        extra: {'rideId': expectedRideId, 'snapshotRideId': snapshotId},
      );
      return;
    }
    try {
      await OnDemandRideHistoryStore.archive(
        snapshot,
        terminalStatus: status,
        cancellationReason: cancellationReason,
        endedEarly: endedEarly != null,
        charged: endedEarly?.charged,
      );
    } catch (error) {
      AppLog.warning(
        'ride.history.archive_failed',
        extra: {
          'rideId': snapshot.rideId,
          'status': status.name,
          'error': error.toString(),
        },
      );
    }
  }

  void markClosed() {
    AppScope.instance.ride.localTransition(RideStatus.closed);
    _stopSafetyRecording();
    unawaited(_store.clear());
  }

  /// Finish History archival before clearing the restorable completion record.
  Future<void> closeCompletedRide(String rideId) async {
    final snapshot = await _store.historyCandidate();
    if (snapshot != null && snapshot.rideId?.trim() != rideId.trim()) {
      throw StateError('A different ride is active.');
    }
    if (snapshot != null && snapshot.status.isCompletedSurface) {
      await OnDemandRideHistoryStore.archive(
        snapshot,
        terminalStatus: snapshot.status,
      );
    }
    AppScope.instance.ride.localTransition(RideStatus.closed);
    _stopSafetyRecording();
    await _store.clear();
  }

  /// FLOW-6: a Safety Kit recording belongs to the ride; once the ride is
  /// over the rider can no longer reach Stop audio, so it stops and is
  /// saved here. Best effort, never blocks the ride flow.
  void _stopSafetyRecording() {
    unawaited(SafetyController.stopRecordingForRideEnd());
  }
}
