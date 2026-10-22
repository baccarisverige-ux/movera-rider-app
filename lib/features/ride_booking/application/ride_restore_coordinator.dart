import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/web/web_search_interrupted.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/search_interrupted_notice.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';

enum RestoredSurface { home, finding, waiting, complete }

class RideRestoreCoordinator {
  RideRestoreCoordinator({
    RideSnapshotStoreReader? reader,
    bool Function()? skipRestore,
    RideRealtimeResync? resync,
    bool Function()? authRequired,
    Future<bool> Function()? hasSession,
    SearchInterruptedNotice? interruptedNotice,
    Future<PendingCancel?> Function(String rideId)? pendingCancel,
    Future<PendingCancelResult?> Function(String rideId)? flushCancel,
    Future<RideSnapshot?> Function()? serverActiveTrip,
  }) : _reader = reader ?? RideSnapshotStore.read,
       _flushCancel = flushCancel ?? _defaultFlushCancel,
       _serverActiveTrip = serverActiveTrip ?? _defaultServerActiveTrip,
       _pendingCancel = pendingCancel ?? PendingCancelStore.find,
       _skipRestore = skipRestore ?? defaultSkipRestore,
       _resync = resync ?? _defaultResync,
       _authRequired = authRequired ?? _defaultAuthRequired,
       _hasSession = hasSession ?? _defaultHasSession,
       _interruptedNotice = interruptedNotice ?? SearchInterruptedNotice();

  final Future<RideSnapshot?> Function() _reader;
  final bool Function() _skipRestore;
  final RideRealtimeResync _resync;
  final bool Function() _authRequired;
  final Future<bool> Function() _hasSession;
  final SearchInterruptedNotice _interruptedNotice;
  final Future<PendingCancel?> Function(String rideId) _pendingCancel;
  final Future<PendingCancelResult?> Function(String rideId) _flushCancel;
  final Future<RideSnapshot?> Function() _serverActiveTrip;

  /// How long a cold restore waits for the server's answer to a queued
  /// cancel before it shows the ride as still cancelling.
  static const queuedCancelWait = Duration(seconds: 4);

  /// rider-u174: how long a cold start with no ride on this device waits
  /// for the server's active trip before it shows Home. A hanging network
  /// used to hold a blank screen for the client's full timeout (about
  /// 30 s); a trip that comes back later still opens.
  static const serverTripWait = Duration(seconds: 2);

  static Future<PendingCancelResult?> _defaultFlushCancel(String rideId) =>
      FindingDriverController.flushPendingCancels()
          .then<PendingCancelResult?>((results) => results[rideId])
          .timeout(queuedCancelWait, onTimeout: () => null);

  static Future<RideSnapshot?> _defaultServerActiveTrip() =>
      AppScope.instance.activeTrips.fetchActive();

  /// ARCH-12: when this device holds no live ride, asks the server for the
  /// rider's active trip (contract C-5) and, if there is one, saves it as
  /// the snapshot so restore and push taps can open it. [expectedRideId]
  /// limits it to that ride. Never replaces a snapshot this device has, and
  /// returns null on any failure: restore then behaves as before.
  Future<RideSnapshot?> adoptServerActiveTrip({String? expectedRideId}) async {
    try {
      if (await _reader() != null) return null;
      final trip = await _serverActiveTrip();
      final id = trip?.rideId?.trim();
      if (trip == null || id == null || id.isEmpty || trip.status.isTerminal) {
        return null;
      }
      if (expectedRideId != null && id != expectedRideId.trim()) return null;
      // The lookup may have been slow: a ride this device started meanwhile
      // keeps its own snapshot.
      if (await _reader() != null) return null;
      await RideSnapshotStore.save(trip);
      AppLog.info('ride.restore.server_active_trip', extra: {
        'rideId': id,
        'status': trip.status.name,
      });
      return await _reader() ?? trip;
    } catch (error) {
      AppLog.warning(
        'restore.active_trip_failed',
        extra: {'error': '$error'},
      );
      return null;
    }
  }

  /// NAV-15: completes once the first [root] call has resolved, so a
  /// notification opener on a cold start does not race the gate's own
  /// restore. Already complete when no [root] call ever started (hosts
  /// without a gate).
  Completer<void>? _firstRoot;
  Future<void> get firstRootResolved =>
      _firstRoot?.future ?? Future<void>.value();

  /// PR-3 follow-up: a reload while the rider's cancel was still on its way
  /// leaves the snapshot behind with the cancel queued in the outbox.
  ///
  /// RC-03: the queued cancel is sent first and only the server's answer
  /// ends the ride here. Confirmed (or the ride is gone): archive it, drop
  /// the snapshot and restore Home. Refused (a driver accepted first) or no
  /// answer yet (offline): the ride is restored, and a restored search shows
  /// the cancel as still on its way until the server answers.
  Future<RideSnapshot?> _dropIfCancelQueued(RideSnapshot? snapshot) async {
    final id = snapshot?.rideId?.trim();
    if (snapshot == null || id == null || id.isEmpty) return snapshot;
    // A mounted search that owns this ride is waiting for the server's
    // answer itself (a 409 must still be able to move it to Waiting).
    if (FindingDriverController.active?.ownedRideId == id) return snapshot;
    PendingCancel? queued;
    try {
      queued = await _pendingCancel(id);
    } catch (_) {
      return snapshot;
    }
    if (queued == null) return snapshot;
    PendingCancelResult? answer;
    try {
      answer = await _flushCancel(id);
    } catch (error) {
      AppLog.warning(
        'ride.restore.cancel_flush_failed',
        extra: {'rideId': id, 'error': '$error'},
      );
    }
    AppLog.info('ride.restore.cancel_queued', extra: {
      'rideId': id,
      'answer': answer?.name ?? 'none',
    });
    // An end-early that went through ends the trip, it does not cancel it:
    // the restored trip resyncs and shows how the server closed it. So does
    // a trip the server had already closed some other way (rider-r4-24:
    // `ended`, e.g. no driver found), which is not the rider's cancel.
    if (queued.command != PendingCancelCommand.cancel ||
        (answer != PendingCancelResult.sent &&
            answer != PendingCancelResult.gone)) {
      return snapshot;
    }
    final session = AppScope.instance.ride;
    if (session.rideId == null || session.rideId == id) {
      session.backendReconcile(RideStatus.cancelledByRider, id: id);
    }
    try {
      await OnDemandRideHistoryStore.archiveCancelledThenClear(
        snapshot: snapshot,
        reasonId: queued.reasonId,
      );
    } catch (_) {
      await RideSnapshotStore.clear();
    }
    // The rider's own cancel went through: nothing was interrupted
    // (rider-u117).
    clearSearchLive();
    return null;
  }

  static Future<void> _defaultResync(String rideId) =>
      AppScope.instance.rideRealtime.reconnectAndResync(rideId);

  static bool _defaultAuthRequired() => AppEnv.current.authRequired;

  static Future<bool> _defaultHasSession() async {
    final access = await AppScope.instance.tokens.readAccess();
    final refresh = await AppScope.instance.tokens.readRefresh();
    return access?.isNotEmpty == true && refresh?.isNotEmpty == true;
  }

  Future<bool> _shouldRequireSignIn(RideSnapshot? snapshot) async {
    if (!_authRequired()) return false;
    if (await _hasSession()) return false;
    // The snapshot is kept. A missing session is often not a sign-out: web
    // reloads lose tokens that only lived in memory, and an expired refresh
    // ends the session mid-ride. Sign-in is still required first, and
    // [resumeIfNeeded] refuses to restore while signed out; after sign-in the
    // ride is re-read from the server, which owns it. Wiping a previous
    // rider's data on sign-out / account switch belongs to the sign-out flow.
    return true;
  }

  Widget _gatedHome() {
    if (!_authRequired()) return const Home();
    return _AuthenticatedHomeGate(hasSession: _hasSession);
  }
  RestoredSurface showing = RestoredSurface.home;
  int restores = 0;
  void Function(Widget page)? onReplaceRoot;

  /// True while the root gate shows Sign in or the new-rider name step.
  /// Ride surfaces, notifications and Safety must not open over it.
  bool authRootShowing = false;

  /// Reads the interrupted-search notice and clears it, so the rider is told
  /// once.
  bool takeSearchInterrupted() => _interruptedNotice.take();

  /// Record that a live ride was dropped rather than resumed.
  void noteSearchInterrupted() => _interruptedNotice.note();

  void _noteDropped(RestoredSurface surface) {
    if (surface == RestoredSurface.finding ||
        surface == RestoredSurface.waiting) {
      noteSearchInterrupted();
    }
  }

  /// Tests: pretend Profile/Wallet is open so resume must not navigate.
  bool Function()? debugAtRoot;

  static final instance = RideRestoreCoordinator(
    interruptedNotice: SearchInterruptedNotice.shared,
  );

  /// A live ride in this browser must survive reload, crash, PWA eviction
  /// and Safari tab recovery. localStorage is per-browser, so a stranger
  /// tapping the public link never sees someone else's trip.
  static bool defaultSkipRestore() => false;

  void goHome({bool replaceRoot = true}) {
    // Deliberately back to Home: nothing to explain on the next load.
    clearSearchLive();
    showing = RestoredSurface.home;
    reportRestoreSurface(RestoredSurface.home.name);
    unawaited(() async {
      try {
        await RideSnapshotStore.clear();
      } catch (error) {
        AppLog.warning(
          'restore.snapshot_clear_failed',
          extra: {'error': '$error'},
        );
      }
    }());
    // Normal pushed ride flows already reveal the existing Home when the
    // navigator pops to root. Rebuilding the root Home again causes a visible
    // double transition and unnecessary map/controller churn. Cold-restored
    // ride surfaces still need an explicit root replacement.
    if (replaceRoot) onReplaceRoot?.call(_gatedHome());
  }

  /// Swaps the root gate's child. Returns false when no gate is mounted (the
  /// gate clears [onReplaceRoot] when it is disposed), so callers can fall
  /// back to the navigator instead of believing an invisible swap happened.
  bool replaceRootSurface(Widget page, RestoredSurface surface) {
    final replace = onReplaceRoot;
    if (replace == null) return false;
    showing = surface;
    reportRestoreSurface(surface.name);
    replace(page);
    return true;
  }

  /// Chrome Refresh / bfcache leave fires pagehide. The live snapshot stays
  /// so a crash or reload can reopen the same trip.
  void onPageHide() {
    unawaited(() async {
      try {
        await RideSnapshotStore.touchCurrent();
      } catch (error) {
        AppLog.warning(
          'restore.snapshot_touch_failed',
          extra: {'error': '$error'},
        );
      }
    }());
  }

  RestoredSurface surfaceFor(RideSnapshot? snapshot) {
    if (snapshot == null || snapshot.status.isTerminal || !snapshot.isFresh) {
      return RestoredSurface.home;
    }
    switch (snapshot.status) {
      case RideStatus.findingDriver:
      case RideStatus.searchDelayed:
      case RideStatus.bookingRequested:
        return RestoredSurface.finding;
      case RideStatus.driverAssigned:
      case RideStatus.driverArriving:
      case RideStatus.driverWaiting:
      case RideStatus.tripStarted:
      case RideStatus.tripInProgress:
      case RideStatus.approachingDropoff:
        return RestoredSurface.waiting;
      default:
        if (snapshot.status.isCompletedSurface) {
          return RestoredSurface.complete;
        }
        return RestoredSurface.home;
    }
  }

  Widget pageFor(RideSnapshot? snapshot) {
    final surface = surfaceFor(snapshot);
    showing = surface;
    restores += 1;
    reportRestoreSurface(surface.name);
    if (snapshot == null || surface == RestoredSurface.home) {
      return const Home();
    }
    // Rebuilding the screen is not enough: the ride's identity lives in
    // AppScope, and a cold restore starts with it empty. Without this the
    // restored search has no rideId, so Cancel reaches no ride to cancel and
    // raising the offer refuses because it cannot name the ride it belongs to.
    // Phase 135: seed authoritativeVersion from the snapshot's own ordering
    // number so a subsequent lower-versioned event - like the findingDriver
    // reset a freshly-reconnected mock transport unconditionally emits - is
    // correctly rejected as stale instead of silently regressing this
    // restore. Without a persisted version there is nothing to protect
    // against; that gap is closed as soon as the first live event persists
    // one (see DriverTrackingController._persistLiveStatus).
    // ARCH-1: only server-issued ordering may seed the session. savedAt is
    // the device clock at the last local save; used as the server time it
    // made a driver assignment from just before the reload look stale.
    final session = AppScope.instance.ride;
    session.backendReconcile(
      snapshot.status,
      id: snapshot.rideId,
      version: snapshot.version,
      updatedAt: snapshot.serverUpdatedAt,
    );
    _adoptBookingIds(snapshot);
    final pickup = LatLng(snapshot.pickupLat, snapshot.pickupLng);
    final drop = LatLng(snapshot.destinationLat, snapshot.destinationLng);
    if (surface == RestoredSurface.waiting) {
      // Phase 135: this is the other half of the fix. Only this call site
      // actually knows the restore is genuine (a normal live continuation
      // never goes through pageFor), so priming happens here rather than in
      // WaitingForDriver itself, which cannot tell a real restore apart from
      // a screen mounting fresh mid-session with an already-matched status.
      final realtime = AppScope.instance.rideRealtime;
      if (realtime is MockRideRealtime && snapshot.status.isMatched) {
        realtime.primeResume(
          status: snapshot.status,
          driver: snapshot.driver,
          version: snapshot.version,
          // rider-24: the driver approaches this trip's pickup.
          pickupLat: snapshot.pickupLat,
          pickupLng: snapshot.pickupLng,
        );
      }
    }
    switch (surface) {
      case RestoredSurface.finding:
        return FindingDrivers(
          pickupAddress: snapshot.pickupAddress,
          destinationAddress: snapshot.destinationAddress,
          pickupPosition: pickup,
          destinationPosition: drop,
          rideType: snapshot.rideType,
          price: snapshot.price,
          currency: snapshot.currency,
          paymentMethod: snapshot.paymentMethod,
          walletAmountMinor: snapshot.walletAmountMinor,
          notes: snapshot.notes,
          stops: snapshot.stops,
          searchStartedAt: snapshot.searchStart,
          createdAt: snapshot.createdAt,
        );
      case RestoredSurface.waiting:
        return WaitingForDriver(
          pickupAddress: snapshot.pickupAddress,
          destinationAddress: snapshot.destinationAddress,
          pickupPosition: pickup,
          destinationPosition: drop,
          rideType: snapshot.rideType,
          price: snapshot.price,
          currency: snapshot.currency,
          paymentMethod: snapshot.paymentMethod,
          walletAmountMinor: snapshot.walletAmountMinor,
          notes: snapshot.notes,
          stops: snapshot.stops,
          driver: snapshot.driver,
        );
      case RestoredSurface.complete:
        // Cold restore rebuilds this in-memory completion context from the
        // still-owned snapshot so driver/vehicle/route/booked-price cards are
        // truthful after reload or process death.
        LastCompletedRide.remember(snapshot);
        return RideCompleted(
          status: snapshot.status,
          rideId: snapshot.rideId,
        );
      case RestoredSurface.home:
        return const Home();
    }
  }

  void _adoptBookingIds(RideSnapshot snapshot) {
    final session = AppScope.instance.ride;
    if (session.rideId != snapshot.rideId) return;
    session.bookedCategoryId = snapshot.categoryId ?? session.bookedCategoryId;
    session.bookedPaymentMethodId =
        snapshot.paymentMethodId ?? session.bookedPaymentMethodId;
    session.bookedMaxOfferMinor =
        snapshot.maxOfferMinor ?? session.bookedMaxOfferMinor;
  }

  Future<Widget> root() async {
    final first = _firstRoot ??= Completer<void>();
    try {
      return await _root();
    } finally {
      // On the event queue, so the gate's own `.then` (which shows the page
      // and sets [authRootShowing]) has run before a waiting opener resumes.
      Timer.run(() {
        if (!first.isCompleted) first.complete();
      });
    }
  }

  Future<Widget> _root() async {
    reportRestoreSurface('hold');
    if (_skipRestore()) {
      RideSnapshot? snapshot;
      try {
        snapshot = await _reader();
        _noteDropped(surfaceFor(snapshot));
      } catch (error) {
        AppLog.warning(
          'restore.snapshot_read_failed',
          extra: {'error': '$error'},
        );
      }
      showing = RestoredSurface.home;
      reportRestoreSurface(RestoredSurface.home.name);
      unawaited(RideSnapshotStore.clear());
      if (await _shouldRequireSignIn(snapshot) ||
          AppEnv.current.authPreview && snapshot == null) {
        return const SignIn();
      }
      return const Home();
    }
    try {
      final snapshot = await _dropIfCancelQueued(await _reader());
      AppLog.info(
        'ride.restore.cold',
        extra: {'status': snapshot?.status.name ?? 'none'},
      );
      if (await _shouldRequireSignIn(snapshot)) {
        showing = RestoredSurface.home;
        reportRestoreSurface('signIn');
        return const SignIn();
      }
      if (snapshot == null && AppEnv.current.authPreview) {
        reportRestoreSurface('signInPreview');
        return const SignIn();
      }
      return pageFor(snapshot ?? await _serverTripForColdStart());
    } catch (error) {
      AppLog.error('ride.restore.corrupt', extra: {'reason': error.toString()});
      showing = RestoredSurface.home;
      reportRestoreSurface(RestoredSurface.home.name);
      if ((_authRequired() && !await _hasSession()) ||
          AppEnv.current.authPreview) {
        return const SignIn();
      }
      return const Home();
    }
  }

  /// The server's active trip when it answers within [serverTripWait];
  /// otherwise null (Home shows), and a trip that arrives later replaces
  /// the root while the rider is still on Home.
  Future<RideSnapshot?> _serverTripForColdStart() {
    final lookup = adoptServerActiveTrip();
    return lookup.timeout(
      serverTripWait,
      onTimeout: () {
        AppLog.info('ride.restore.server_active_trip_slow');
        unawaited(lookup.then(_openLateServerTrip));
        return null;
      },
    );
  }

  void _openLateServerTrip(RideSnapshot? trip) {
    if (trip == null ||
        showing != RestoredSurface.home ||
        authRootShowing ||
        !atRoot) {
      // Kept as the snapshot: the next resume opens it.
      return;
    }
    if (surfaceFor(trip) == RestoredSurface.home) return;
    onReplaceRoot?.call(pageFor(trip));
  }

  bool get atRoot {
    final override = debugAtRoot;
    if (override != null) return override();
    try {
      final nav = moveraNavigatorKey.currentState;
      if (nav == null) return true;
      return !nav.canPop();
    } catch (_) {
      return true;
    }
  }

  /// Immediately gives a newly created on-demand ride a visible owner when
  /// the Select Ride surface disappears before it can push Finding.
  ///
  /// This is a post-create recovery path, not normal resume. The backend ride
  /// already exists, so silently waiting for a later app lifecycle event would
  /// leave a live orphan ride.
  Future<bool> recoverCreatedFinding(
    String rideId, {
    RideRealtime? realtime,
  }) async {
    final expectedId = rideId.trim();
    if (expectedId.isEmpty) return false;

    final snapshot = await _reader();
    if (snapshot == null ||
        snapshot.rideId?.trim() != expectedId ||
        snapshot.status.isTerminal ||
        !snapshot.isFresh) {
      return false;
    }

    AppScope.instance.ride.backendReconcile(
      snapshot.status,
      id: expectedId,
      version: snapshot.version,
      updatedAt: snapshot.serverUpdatedAt,
    );
    _adoptBookingIds(snapshot);

    final finding = FindingDrivers(
      pickupAddress: snapshot.pickupAddress,
      destinationAddress: snapshot.destinationAddress,
      pickupPosition: LatLng(snapshot.pickupLat, snapshot.pickupLng),
      destinationPosition: LatLng(
        snapshot.destinationLat,
        snapshot.destinationLng,
      ),
      rideType: snapshot.rideType,
      price: snapshot.price,
      currency: snapshot.currency,
      paymentMethod: snapshot.paymentMethod,
      walletAmountMinor: snapshot.walletAmountMinor,
      notes: snapshot.notes,
      stops: snapshot.stops,
      searchStartedAt: snapshot.searchStart,
      createdAt: snapshot.createdAt,
      realtime: realtime,
    );

    final nav = moveraNavigatorKey.currentState;
    final replace = onReplaceRoot;
    if (replace != null) {
      // Default app topology: remove Home's platform map for one full frame
      // before the recovered Finding map mounts.
      showing = RestoredSurface.finding;
      reportRestoreSurface('recoveringFinding');
      replace(const _RideRecoveryBarrier());
      if (nav != null && nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
      }
      await WidgetsBinding.instance.endOfFrame;
      replace(finding);
      reportRestoreSurface(RestoredSurface.finding.name);
      return true;
    }

    // Isolated hosts/tests may not mount RideRestoreGate. The navigator is
    // still a valid immediate recovery owner in that topology.
    if (nav == null) return false;
    showing = RestoredSurface.finding;
    reportRestoreSurface(RestoredSurface.finding.name);
    unawaited(
      nav.push<void>(
        RideStageTransition(
          finding,
          settings: const RouteSettings(name: AppRoutes.findingDriver),
        ),
      ),
    );
    return true;
  }

  Future<Widget?> resumeIfNeeded() async {
    if (_skipRestore()) {
      unawaited(RideSnapshotStore.clear());
      if (showing == RestoredSurface.finding ||
          showing == RestoredSurface.waiting) {
        _noteDropped(showing);
        goHome();
      } else {
        showing = RestoredSurface.home;
      }
      return null;
    }
    // Never draw a ride over Sign in: the rider has to sign in first, and
    // enterMoveraApp resumes the kept ride afterwards.
    if (authRootShowing) return null;
    if (_authRequired() && !await _hasSession()) return null;
    var snapshot = await _reader();
    final id = snapshot?.rideId;
    if (id != null) {
      try {
        await _resync(id);
      } catch (error) {
        AppLog.warning('restore.resync_failed', extra: {'error': '$error'});
      }
      try {
        snapshot = await _reader();
      } catch (error) {
        AppLog.warning(
          'restore.snapshot_read_failed',
          extra: {'error': '$error'},
        );
      }
    }
    snapshot = await _dropIfCancelQueued(snapshot);
    if (!atRoot) return null;
    // rider-67: the flag belongs to the ride that ended on this device. A
    // snapshot of another ride (one a push tap just adopted from the
    // server) is not that ride and is opened.
    final session = AppScope.instance.ride;
    if (session.suppressRestore &&
        snapshot?.rideId?.trim() == session.rideId?.trim()) {
      unawaited(RideSnapshotStore.clear());
      return null;
    }
    final next = surfaceFor(snapshot);
    if (next == showing) return null;
    final page = next == RestoredSurface.home ? _gatedHome() : pageFor(snapshot);
    onReplaceRoot?.call(page);
    return page;
  }
}

typedef RideSnapshotStoreReader = Future<RideSnapshot?> Function();
typedef RideRealtimeResync = Future<void> Function(String rideId);


class _RideRecoveryBarrier extends StatelessWidget {
  const _RideRecoveryBarrier();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF6F5F1),
      child: Center(
        child: Semantics(
          // rider-68: in the app language.
          label: L10n.current.restoringRide,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}


class _AuthenticatedHomeGate extends StatefulWidget {
  const _AuthenticatedHomeGate({required this.hasSession});

  final Future<bool> Function() hasSession;

  @override
  State<_AuthenticatedHomeGate> createState() => _AuthenticatedHomeGateState();
}

/// UI-14: secure storage is read once per gate, not on every rebuild.
class _AuthenticatedHomeGateState extends State<_AuthenticatedHomeGate> {
  late final Future<bool> _session = widget.hasSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _session,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true ? const Home() : const SignIn();
      },
    );
  }
}
