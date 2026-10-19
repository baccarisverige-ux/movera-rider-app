import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';

class ReservationController extends ChangeNotifier {
  ReservationController({
    ReservationRepository? store,
    DateTime Function()? clock,
    AppEnv environment = AppEnv.current,
    ReservationDispatch? mockDispatch,
    ScheduledRideRulesSource? rulesSource,
    ScheduledRideRules rules = ScheduledRideRules.defaults,
    RiderAppConfig? config,
    Future<RiderAppConfig> Function()? configLoader,
  }) : _store = store ?? LocalReservationRepository(),
       _clock = clock ?? DateTime.now,
       _environment = environment,
       _mockDispatch = mockDispatch,
       _rulesSource = rulesSource,
       _rules = rules,
       _config = config,
       _configLoader = configLoader;

  final ReservationRepository _store;
  final DateTime Function() _clock;
  final AppEnv _environment;

  /// Admin-set rider rules for scheduled rides (free-cancel window, late
  /// fee, when the driver shows). Defaults until [refreshRules] reads them.
  final ScheduledRideRulesSource? _rulesSource;
  ScheduledRideRules _rules;

  /// The zone's rider config (CONTRACT.md §6). Its reservation cancel fees
  /// are per category (X3) and take precedence over [_rules]' single fee.
  RiderAppConfig? _config;
  final Future<RiderAppConfig> Function()? _configLoader;

  /// Simulated dispatch (Batch 10 Phase 109). Composed in `di.dart` only for
  /// mock-transport builds, and additionally ignored here unless the
  /// environment allows mock transport, so a backend build can never
  /// self-assign a driver even if one were passed by mistake. When null the
  /// lifecycle is exactly the pre-Phase-109 one.
  final ReservationDispatch? _mockDispatch;

  ReservationDispatch? get _dispatch =>
      _environment.allowsMockTransport ? _mockDispatch : null;

  // Phase 134: create/update/cancel had no in-flight tracking, so a rapid
  // double-tap (or two independent callers) could race two store mutations
  // against the same reservation. Concurrent calls are coalesced onto the
  // same in-flight Future instead of issuing a second mutation - callers
  // still get a real Reservation back, just the already-in-flight one's
  // result, rather than being silently dropped.
  Future<Reservation>? _pendingCreate;
  final Map<String, Future<Reservation>> _pendingUpdateByReservationId = {};
  final Map<String, Future<Reservation>> _pendingCancelByReservationId = {};
  // Note: update and cancel are tracked separately, since a concurrent
  // update-then-cancel (or vice versa) on the same reservation are distinct
  // operations, not a double-tap of the same one.

  bool get usesMockDriverAssignment => _environment.allowsMockTransport;

  List<Reservation> get all => _store.cached;

  ReservationPolicy get policy => _store.policy;

  ScheduledRideRules get rules => _rules;

  /// Reads the current rules. When they cannot be read, the ones already
  /// held stay in force.
  Future<void> refreshRules() async {
    await _refreshConfig();
    final source = _rulesSource;
    if (source == null) return;
    try {
      final next = await source.fetch();
      if (next == null || next == _rules) return;
      _rules = next;
      notifyListeners();
    } catch (error, stackTrace) {
      AppLog.error(
        'reservation.rules.refresh_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _refreshConfig() async {
    final loader = _configLoader;
    if (loader == null) return;
    try {
      final next = await loader();
      if (identical(next, _config)) return;
      _config = next;
      notifyListeners();
    } catch (error, stackTrace) {
      AppLog.error(
        'reservation.config.refresh_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// What cancelling [ride] costs the rider right now: the zone's rule for
  /// the ride's category when the config has one (X3), else [rules].
  ReservationCancelTerms cancelTermsFor(Reservation ride, {DateTime? now}) =>
      _rules.cancelTermsFor(
        ride,
        now ?? _clock(),
        categoryRule: _config?.reservationFeeFor(ride.categoryId),
      );

  /// Whether the rider sees [ride]'s driver: from the moment a driver
  /// accepts, or only once on the way when admin turned that off.
  bool showsDriverOf(Reservation ride) => _rules.showsDriverOf(ride);

  List<Reservation> upcoming() =>
      _store.cached.where((item) => item.status.isUpcoming).toList();

  List<Reservation> completed() =>
      _store.cached.where((item) => item.status.isCompleted).toList();

  List<Reservation> cancelled() =>
      _store.cached.where((item) => item.status.isCancelled).toList();

  Reservation? byId(String reservationId) {
    for (final item in _store.cached) {
      if (item.reservationId == reservationId) return item;
    }
    return null;
  }

  Future<void> hydrate() async {
    await _store.hydrate();
    notifyListeners();
  }

  /// Forgets the signed-out rider's reservations in memory. A simulated trip
  /// still running stops at its next step, since its ride is gone.
  void clearLocal() {
    _store.clearLocal();
    notifyListeners();
  }

  Future<Reservation> create(ReservationDraft draft) {
    final pending = _pendingCreate;
    if (pending != null) return pending;
    final future = _createNow(draft);
    _pendingCreate = future;
    // The caller gets the error from [future]; the cleanup's own copy of it
    // must not surface again as an uncaught error.
    future.whenComplete(() => _pendingCreate = null).ignore();
    return future;
  }

  Future<Reservation> _createNow(ReservationDraft draft) async {
    final created = await _store.createReservation(draft);
    notifyListeners();
    return created;
  }

  Future<Reservation> update(String reservationId, ReservationPatch patch) {
    final pending = _pendingUpdateByReservationId[reservationId];
    if (pending != null) return pending;
    final future = _updateNow(reservationId, patch);
    _pendingUpdateByReservationId[reservationId] = future;
    future
        .whenComplete(() => _pendingUpdateByReservationId.remove(reservationId))
        .ignore();
    return future;
  }

  Future<Reservation> _updateNow(
    String reservationId,
    ReservationPatch patch,
  ) async {
    final updated = await _store.updateReservation(reservationId, patch);
    notifyListeners();
    return updated;
  }

  /// Cancels for the rider. [fee] is the late-cancel fee the rider was
  /// shown and agreed to ([cancelTermsFor]); null when it was free.
  Future<Reservation> cancel(
    String reservationId, {
    String? reason,
    Money? fee,
  }) {
    final pending = _pendingCancelByReservationId[reservationId];
    if (pending != null) return pending;
    final future = _cancelNow(reservationId, reason: reason, fee: fee);
    _pendingCancelByReservationId[reservationId] = future;
    future
        .whenComplete(() => _pendingCancelByReservationId.remove(reservationId))
        .ignore();
    return future;
  }

  Future<Reservation> _cancelNow(
    String reservationId, {
    String? reason,
    Money? fee,
  }) async {
    final updated = await _store.cancelReservation(
      reservationId,
      reason: reason,
      fee: fee,
    );
    notifyListeners();
    return updated;
  }

  /// The assigned driver drops a scheduled ride before pickup.
  ///
  /// Distinct from [cancel], which is the rider ending their own reservation.
  /// Here the reservation stands — its time, route and price are unchanged —
  /// and it returns to waiting for a driver rather than being cancelled.
  Future<Reservation> driverCancelled(String reservationId) async {
    final current = await _store.getReservation(reservationId);
    if (current == null) {
      throw StateError('No reservation $reservationId to reassign.');
    }
    if (!current.status.isUpcoming || !current.status.hasDriver) {
      // Nothing assigned to drop, or the ride is already over.
      return current;
    }
    final updated = await _store.assignDriver(reservationId, driver: null);
    notifyListeners();
    return updated;
  }

  /// Applies an authoritative driver assignment from backend/realtime.
  ///
  /// This is intentionally separate from [assignMockDriver]: production
  /// transports may call this method, while local/demo code remains gated by
  /// the app environment.
  Future<Reservation> applyDriverAssignment(
    String reservationId, {
    required ReservationDriver driver,
  }) async {
    final updated = await _store.assignDriver(reservationId, driver: driver);
    notifyListeners();
    return updated;
  }

  /// Applies an authoritative driver cancellation from backend/realtime.
  Future<Reservation> applyDriverCancellation(String reservationId) {
    return driverCancelled(reservationId);
  }

  Future<Reservation> assignMockDriver(
    String reservationId, {
    ReservationDriver? driver,
  }) async {
    if (!_environment.allowsMockTransport) {
      throw StateError(
        'Mock driver assignment is forbidden for ${_environment.flavor.name}.',
      );
    }
    final updated = await _store.assignDriver(reservationId, driver: driver);
    notifyListeners();
    return updated;
  }

  /// How long after the scheduled pickup time a reservation may sit without
  /// a driver before the client stops showing "searching" and tells the rider
  /// honestly that no driver was found.
  ///
  /// Client-side mitigation only (Batch 9 Phase 106 / U4): reservations are
  /// local-only today and nothing assigns a driver, so without this a due
  /// ride stays in [ReservationStatus.driverAssignmentPending] forever. The
  /// real fix is server-driven dispatch with explicit no_driver_found /
  /// expired states.
  static const noDriverFoundAfter = Duration(minutes: 5);

  /// Reason recorded when the rider resolves a reservation that timed out
  /// without a driver.
  static const noDriverFoundReason = 'no_driver_found';

  /// Whether [ride] has passed its pickup time by [noDriverFoundAfter] and
  /// still has no driver assigned.
  bool isNoDriverFound(Reservation ride, {DateTime? now}) {
    final status = ride.status;
    if (status != ReservationStatus.scheduled &&
        status != ReservationStatus.driverAssignmentPending) {
      return false;
    }
    if (ride.driver != null) return false;
    final currentTime = now ?? _clock();
    return !currentTime.isBefore(
      ride.scheduledPickupAt.add(noDriverFoundAfter),
    );
  }

  /// Upcoming reservations currently in the "No driver found" state.
  List<Reservation> noDriverFound({DateTime? now}) =>
      upcoming().where((ride) => isNoDriverFound(ride, now: now)).toList();

  /// Cancels a reservation that timed out without a driver, recording why.
  Future<Reservation> resolveNoDriverFound(String reservationId) {
    return cancel(reservationId, reason: noDriverFoundReason);
  }

  Future<void> startLiveIfDue({DateTime? now}) async {
    final currentTime = now ?? _clock();
    final dispatch = _dispatch;
    var changed = false;
    for (final listed in upcoming()) {
      var ride = listed;
      final untilPickup = ride.scheduledPickupAt.difference(currentTime);

      if (dispatch != null) {
        if (ride.revealsDriver) {
          // Already on the road (possibly restored after a restart): make
          // sure the simulated trip is running. Idempotent.
          _driveMockTrip(dispatch, ride);
          continue;
        }
        final acceptAfter = dispatch.acceptAfterBooking;
        final acceptsNow =
            untilPickup <= dispatch.assignmentLead ||
            (acceptAfter != null &&
                !currentTime.isBefore(ride.createdAt.add(acceptAfter)));
        if (acceptsNow &&
            ride.driver == null &&
            (ride.status == ReservationStatus.scheduled ||
                ride.status == ReservationStatus.driverAssignmentPending) &&
            // Never resurrect a ride the rider has already been told has
            // no driver.
            !isNoDriverFound(ride, now: currentTime)) {
          final driver = dispatch.driverFor(ride);
          if (driver != null) {
            ride = await assignMockDriver(ride.reservationId, driver: driver);
            changed = true;
          }
        } else if (ride.status == ReservationStatus.driverAssigned &&
            ride.driver != null &&
            untilPickup > dispatch.assignmentLead) {
          // Simulated driver change: the repository keeps the driver who
          // handed the ride over, and the rider sees the new one.
          final next = dispatch.handoverFor(ride, currentTime);
          if (next != null) {
            ride = await assignMockDriver(ride.reservationId, driver: next);
            changed = true;
          }
        }
      }

      if (untilPickup > const Duration(minutes: 2)) continue;

      if (ride.status == ReservationStatus.scheduled) {
        // Starting assignment is a lifecycle transition; a missing payload
        // stays pending and never invents driver identity.
        await _store.assignDriver(ride.reservationId);
        changed = true;
        continue;
      }

      if (ride.status == ReservationStatus.driverAssigned &&
          ride.driver != null) {
        // Preserve the established contract: a real assigned driver becomes
        // en-route when the pickup window opens. The clock changes status
        // only; it never creates identity, movement or cancellation.
        final enRoute = await _store.updateReservation(
          ride.reservationId,
          const ReservationPatch(status: ReservationStatus.driverEnRoute),
        );
        changed = true;
        if (dispatch != null) _driveMockTrip(dispatch, enRoute);
      }
    }
    if (changed) notifyListeners();
  }

  void _driveMockTrip(ReservationDispatch dispatch, Reservation ride) {
    final id = ride.reservationId;
    dispatch.driveTrip(id, ride.status, (from, to) async {
      final current = byId(id);
      // The rider cancelled, the driver dropped, or anything else moved the
      // ride on: the simulation stops rather than overwrite it.
      if (current == null || current.status != from || current.driver == null) {
        return false;
      }
      await update(id, ReservationPatch(status: to));
      return true;
    });
  }

  @override
  void dispose() {
    _mockDispatch?.dispose();
    super.dispose();
  }

  Future<Reservation> planReturn(
    Reservation origin, {
    required DateTime scheduledPickupAt,
    DateTime? estimatedDropoffAt,
    ReservationPlace? pickup,
    ReservationPlace? destination,
    String? paymentMethod,
    double? price,
    String? categoryId,
    String? categoryName,
    String? categoryImage,
    int? passengerCount,
    String? note,
  }) {
    return create(
      ReservationDraft(
        scheduledPickupAt: scheduledPickupAt,
        estimatedDropoffAt: estimatedDropoffAt,
        pickup: pickup ?? origin.destination,
        destination: destination ?? origin.pickup,
        categoryId: categoryId ?? origin.categoryId,
        categoryName: categoryName ?? origin.categoryName,
        categoryImage: categoryImage ?? origin.categoryImage,
        passengerCount: passengerCount ?? origin.passengerCount,
        price: price ?? origin.price,
        currency: origin.currency,
        paymentMethod: paymentMethod ?? origin.paymentMethod,
        note: note ?? origin.note,
        parentReservationId: origin.reservationId,
      ),
    );
  }
}
