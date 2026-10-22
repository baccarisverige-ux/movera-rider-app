import 'dart:async';

import 'package:movera_rider/core/web/web_search_interrupted.dart';
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
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';
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

  /// rider-u49: whether "Your driver has arrived" was already shown for
  /// [rideId]'s current driver, as saved with the ride's snapshot.
  static Future<bool> arrivalAnnounced(String rideId) async {
    final saved = await RideSnapshotStore.read();
    return saved?.rideId?.trim() == rideId.trim() &&
        saved!.arrivalAnnounced;
  }

  /// rider-u49: saves [announced] for [rideId] (a new driver clears it).
  static Future<void> rememberArrivalAnnounced(
    String rideId,
    bool announced,
  ) async {
    final saved = await RideSnapshotStore.read();
    if (saved == null || saved.rideId?.trim() != rideId.trim()) return;
    if (saved.arrivalAnnounced == announced) return;
    await RideSnapshotStore.save(saved.copyWith(arrivalAnnounced: announced));
  }

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
      await _commitCancelled(
        id,
        reasonId: reasonId,
        endedEarly: endedEarly,
        cancellationFee: result.fee,
      );
    }
    return result.outcome;
  }

  /// Commits a cancel the server has already applied — for example when a
  /// queued outbox request lands and realtime then reports the ride as
  /// `cancelledByRider` while Waiting is still showing it.
  ///
  /// rider-u51: once the rider is on board the only rider command that
  /// reaches `cancelled_by_rider` is `end_early` (contract v0.3.0), so a
  /// server cancel of a trip whose stored stage is on board is an ended
  /// trip: [endedEarly] is set for the summary and History reads "Ended
  /// early". [drivenMeters] is the distance the app tracked on board.
  ///
  /// rider-u32: when it was this device's queued command that the outbox
  /// delivered, the reason the rider gave and what the server answered
  /// (the fare after an end-early, a cancel's fee) go on the receipt and
  /// the History record; the projection alone does not say.
  Future<void> completeServerConfirmedCancel({int? drivenMeters}) async {
    final id = _clean(AppScope.instance.ride.rideId);
    final delivered = id == null ? null : PendingCancelStore.takeDelivered(id);
    final snapshot = await _store.historyCandidate();
    final onboard = id != null &&
        snapshot != null &&
        _clean(snapshot.rideId) == id &&
        tripRiderOnboardStatuses.contains(snapshot.status.tripStatus);
    final endedEarly =
        id != null &&
            (onboard || delivered?.command == PendingCancelCommand.endEarly)
        ? EndedEarlyTrip(
            rideId: id,
            charged: delivered?.charged,
            drivenMeters: drivenMeters,
          )
        : null;
    _endedEarly = endedEarly;
    await _commitCancelled(
      id,
      reasonId: delivered?.reasonId,
      endedEarly: endedEarly,
      cancellationFee: endedEarly == null ? delivered?.fee : null,
    );
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
    final result = await _requestServerCancel(recovered);
    final outcome = result.outcome;
    AppLog.info(
      'ride.cancel.untracked_ride',
      extra: {'rideId': recovered, 'outcome': outcome.name},
    );
    // rider-r4-25: like every other cancel path, keep the ride (and any
    // fee) in History and stop realtime before Home clears the snapshot.
    // The session is not this ride's (it lost the id), so it is left to
    // RideNavigator.home to reset.
    if (outcome == RideCancelOutcome.confirmed) {
      AppScope.instance.rideRealtime.cancelRide();
      await _archive(
        await _store.historyCandidate(),
        RideStatus.cancelledByRider,
        expectedRideId: recovered,
        cancellationFee: result.fee,
      );
    }
    return outcome;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<
    ({
      RideCancelOutcome outcome,
      PendingCancelCommand command,
      Money? charged,
      Money? fee,
    })
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
          fee: _cancellationFee(response),
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
            final projection = {'projection': apiError.projection};
            return (
              outcome: RideCancelOutcome.confirmed,
              command: entry.command,
              charged: _chargedFare(projection),
              fee: _cancellationFee(projection),
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
            fee: null,
          );
        }
      }
    }
    return (
      outcome: RideCancelOutcome.pendingRetry,
      command: entry.command,
      charged: null,
      fee: null,
    );
  }

  /// The projection's `fare` in a command response (`projection`, or the
  /// pre-v0.3 `ride` alias).
  static Money? _chargedFare(Map<String, dynamic> response) {
    final ride = response['projection'] ?? response['ride'];
    return ride is Map ? Money.fromWire(ride['fare']) : null;
  }

  /// rider-u33: the fee the server charged for a cancel (contract §6
  /// `cancellation.fee`) in a command response (`projection`, or the
  /// pre-v0.3 `ride` alias). Null when free or absent.
  static Money? _cancellationFee(Map<String, dynamic> response) {
    final ride = response['projection'] ?? response['ride'];
    return ride is Map
        ? RideProjection.cancellationFee(Map<String, dynamic>.from(ride))
        : null;
  }

  Future<void> _commitCancelled(
    String? id, {
    String? reasonId,
    EndedEarlyTrip? endedEarly,
    Money? cancellationFee,
  }) async {
    final candidate = await _store.historyCandidate();
    // rider-r4-8: an ended-early receipt's "Date and time" is when the trip
    // ended, not the snapshot's last save (savedAt), as markCompleted does
    // for a finished trip (rider-25).
    final snapshot = endedEarly != null && candidate?.completedAt == null
        ? candidate?.copyWith(completedAt: DateTime.now())
        : candidate;
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
      // rider-u178: the summary says "You pay X"; a wallet-paid trip (or
      // its wallet part) is debited X here. Without the server's amount
      // nothing is known to debit.
      final charged = endedEarly.charged;
      if (charged != null && _clean(snapshot.rideId) == id) {
        await _chargeWallet(snapshot, fare: charged);
      }
    } else if (snapshot != null &&
        cancellationFee != null &&
        cancellationFee.amountMinor > 0 &&
        _clean(snapshot.rideId) == id) {
      // rider-r5-12: History says the cancel fee was paid with the ride's
      // method; a wallet ride (or its wallet part) is debited it here,
      // once per ride like a completed trip.
      await _chargeWallet(snapshot, fare: cancellationFee);
    }
    await _archive(
      snapshot,
      RideStatus.cancelledByRider,
      expectedRideId: id,
      cancellationReason: reasonId,
      endedEarly: endedEarly,
      cancellationFee: cancellationFee,
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
        status == RideStatus.tripFailed ||
        // rider-u34: the trip was driven and completed; only its payment
        // failed. History keeps it as a completed trip that says so.
        status == RideStatus.paymentFailed) {
      await _archive(snapshot, status, expectedRideId: id);
    }
    await _store.clear();
    clearSearchLive(); // rider-r5-18: ended, not interrupted.
  }

  /// rider-u52: the server reports the trip `closed` (completed, paid and
  /// rated) to a screen that never saw it complete, for example a resync
  /// after a long disconnect in trip. Not an external terminal: the trip
  /// happened, so History keeps it as completed, and the snapshot clears.
  Future<void> markClosedByServer() async {
    final snapshot = await _store.historyCandidate();
    final ride = AppScope.instance.ride;
    final id = ride.rideId;
    ride.backendReconcile(RideStatus.closed, id: id);
    _stopSafetyRecording();
    await _archive(snapshot, RideStatus.closed, expectedRideId: id);
    await _store.clear();
    clearSearchLive(); // rider-r5-18: ended, not interrupted.
  }

  Future<void> markCompleted(RideStatus status) async {
    if (!status.isCompletedSurface) {
      throw ArgumentError.value(status, 'status', 'Expected a completed status.');
    }
    final snapshot = await _store.historyCandidate();
    final id = AppScope.instance.ride.rideId;
    AppScope.instance.ride.backendReconcile(status, id: id);
    _stopSafetyRecording(keepRideCheck: true);
    if (snapshot == null) return;

    // Keep a restorable completion snapshot until the rider explicitly leaves
    // the completion surface. This protects payment/rating state across reload,
    // crash, PWA eviction and app resume.
    final now = DateTime.now();
    final completed = snapshot.copyWith(
      status: status,
      savedAt: now,
      // rider-25: a repeat (a resync on the summary) keeps the first time.
      completedAt: snapshot.completedAt ?? now,
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
    Money? cancellationFee,
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
        // rider-25: a later archive (Done on the summary) keeps the
        // completion time, not the time the rider left.
        endedAt: snapshot.completedAt,
        cancellationReason: cancellationReason,
        endedEarly: endedEarly != null,
        charged: endedEarly?.charged,
        cancellationFee: cancellationFee,
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

  /// rider-u179: the card was declined after the trip completed (the
  /// server reports `completed` with payment `failed`). The session holds
  /// paymentFailed, History files the trip with "Payment failed" rather
  /// than as an ordinary completed ride, and the completion snapshot is
  /// dropped: it no longer describes a ride to restore, and leaving later
  /// never re-files it as completed nor debits the wallet for it.
  Future<void> markCompletedPaymentFailed(String rideId) async {
    final id = rideId.trim();
    final ride = AppScope.instance.ride;
    if (_clean(ride.rideId) == id && ride.status != RideStatus.paymentFailed) {
      ride.backendReconcile(RideStatus.paymentFailed, id: id);
    }
    final snapshot = await _store.historyCandidate();
    if (snapshot == null || _clean(snapshot.rideId) != id) return;
    await _archive(snapshot, RideStatus.paymentFailed, expectedRideId: id);
    await _store.clear();
    // rider-r5-18: the trip is over, not interrupted; a reload on this
    // screen must not say the search was.
    clearSearchLive();
  }

  /// rider-r5-3: a declined payment the server retried and authorized or
  /// captured (contract paymentTransitions `failed -> authorized`). The
  /// completion snapshot was dropped at the decline, so the trip the
  /// summary remembers is re-filed in History with its new payment status,
  /// and a captured wallet trip is debited now.
  Future<void> markPaymentRetried(String rideId, RideStatus status) async {
    if (status != RideStatus.paymentProcessing &&
        status != RideStatus.paymentFinalized) {
      return;
    }
    final id = rideId.trim();
    final remembered = LastCompletedRide.forRide(id);
    if (remembered == null) return;
    final snapshot = remembered.copyWith(status: status);
    await _archive(snapshot, status, expectedRideId: id);
    if (status == RideStatus.paymentFinalized) await _chargeWallet(snapshot);
  }

  /// Finish History archival before clearing the restorable completion record.
  ///
  /// rider-72: leaving never fails once the ride is this one. A session
  /// the server already moved to a terminal status (a paymentFailed
  /// reconciled during the Waiting handoff) is kept as it is instead of
  /// throwing InvalidRideTransition, and a History write that keeps losing
  /// its slot is logged; either used to trap the rider on the summary.
  /// Throws only when the stored snapshot belongs to a different ride.
  Future<void> closeCompletedRide(String rideId) async {
    final snapshot = await _store.historyCandidate();
    if (snapshot != null && snapshot.rideId?.trim() != rideId.trim()) {
      throw StateError('A different ride is active.');
    }
    final ride = AppScope.instance.ride;
    if (snapshot != null && snapshot.status.isCompletedSurface) {
      // A decline whose own filing is still on its way keeps its label.
      final declined = ride.status == RideStatus.paymentFailed;
      await _archive(
        snapshot,
        declined ? RideStatus.paymentFailed : snapshot.status,
        expectedRideId: rideId,
      );
      // rider-u180/u181: the rider may leave before the payment is final
      // (Done and Back work at every completion status). No screen then
      // sees paymentFinalized and the snapshot is about to go, so a
      // wallet ride is debited here. The local wallet exists only in
      // demo/dev builds, whose transport always settles a completed trip;
      // a decline already dropped the snapshot (rider-u179).
      if (!declined) await _chargeWallet(snapshot);
    }
    if (canTransition(ride.status, RideStatus.closed)) {
      ride.localTransition(RideStatus.closed);
    }
    _stopSafetyRecording();
    await _store.clear();
  }

  /// D-022: debits a wallet ride the completion screen saw reach
  /// paymentFinalized. See [_chargeWallet].
  Future<void> chargeCompletedWallet(String rideId) async {
    final id = rideId.trim();
    try {
      await AppScope.instance.walletController.chargeCompletedRideById(id);
    } catch (error) {
      AppLog.warning(
        'wallet.ride_charge_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
    }
  }

  /// D-022: the local wallet debit of a finished ride. It is made here,
  /// with the ride's lifecycle, rather than by a screen the rider may have
  /// left already. WalletController keeps the ids it charged, so every
  /// call after the first for a ride is a no-op. Never blocks the flow.
  Future<void> _chargeWallet(RideSnapshot snapshot, {Money? fare}) async {
    final id = _clean(snapshot.rideId);
    if (id == null) return;
    try {
      await AppScope.instance.walletController.chargeCompletedRide(
        snapshot,
        rideId: id,
        fare: fare,
      );
    } catch (error) {
      AppLog.warning(
        'wallet.ride_charge_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
    }
  }

  /// FLOW-6: a Safety Kit recording belongs to the ride; once the ride is
  /// over the rider can no longer reach Stop audio, so it stops and is
  /// saved here. Best effort, never blocks the ride flow.
  /// rider-u35: [keepRideCheck] on completion, whose summary still shows
  /// an open Ride check card and its Stop control.
  /// rider-u205: the ride's live trip share stops here too.
  void _stopSafetyRecording({bool keepRideCheck = false}) {
    unawaited(
      SafetyController.stopRecordingForRideEnd(keepRideCheck: keepRideCheck),
    );
    unawaited(
      SafetyController.stopShareForRideEnd(AppScope.instance.ride.rideId),
    );
  }
}
