import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart'
    show RideSnapshot, RouteChangeController;
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/motion/bearing.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_profile_page.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_call_unavailable_dialog.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_card.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// D-016: how long the driver marker eases towards a new fix. Following the
/// actual interval between fixes (clamped) removes the move-then-stall rhythm
/// a fixed short ease produced at a 2–3 s fix cadence.
@visibleForTesting
Duration driverEaseDuration(Duration? sinceLastFix) {
  const fallback = Duration(milliseconds: 900);
  const shortest = Duration(milliseconds: 400);
  const longest = Duration(milliseconds: 4000);
  if (sinceLastFix == null || sinceLastFix <= Duration.zero) return fallback;
  if (sinceLastFix < shortest) return shortest;
  if (sinceLastFix > longest) return longest;
  return sinceLastFix;
}

/// rider-u58: whether the driver car eases between fixes. On web every
/// marker update makes google_maps_flutter_web convert the car icon to a
/// new blob URL that is never revoked, so a ~20 fps ease for the whole
/// trip leaked thousands of blobs an hour; there the car moves once per
/// fix instead. Native platforms keep the D-016 ease.
@visibleForTesting
bool driverMarkerEases = !kIsWeb;

/// D-018: bounds and uniform padding that frame [a] and [b] above a bottom
/// obstruction (the sheet) instead of padding every side by its height.
///
/// google_maps_flutter 2.13 only offers a single uniform padding for
/// `newLatLngBounds`, so the obstruction is reserved by stretching the bounds
/// southwards: the real points then land in the top
/// `viewportHeight - bottomObstruction` of the map.
@visibleForTesting
({GeoPoint southwest, GeoPoint northeast, double padding}) waitingCameraFit({
  required GeoPoint a,
  required GeoPoint b,
  required double viewportHeight,
  required double bottomObstruction,
  double edgePadding = 48,
}) {
  const minSpan = 0.002; // ~200 m, so driver-at-pickup doesn't zoom to max.
  var south = math.min(a.latitude, b.latitude);
  var north = math.max(a.latitude, b.latitude);
  var west = math.min(a.longitude, b.longitude);
  var east = math.max(a.longitude, b.longitude);
  if (north - south < minSpan) {
    final mid = (north + south) / 2;
    south = mid - minSpan / 2;
    north = mid + minSpan / 2;
  }
  if (east - west < minSpan) {
    final mid = (east + west) / 2;
    west = mid - minSpan / 2;
    east = mid + minSpan / 2;
  }
  final full = math.max(viewportHeight - 2 * edgePadding, 1.0);
  final usable = math.max(
    viewportHeight - bottomObstruction - 2 * edgePadding,
    full * 0.25,
  );
  final span = north - south;
  final stretchedSouth = north - span * (full / usable);
  return (
    southwest: GeoPoint(math.max(stretchedSouth, -85.0), west),
    northeast: GeoPoint(north, east),
    padding: edgePadding,
  );
}

class WaitingForDriver extends StatefulWidget {
  const WaitingForDriver({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupPosition,
    required this.destinationPosition,
    required this.rideType,
    required this.price,
    this.currency = Money.defaultCurrency,
    required this.paymentMethod,
    this.walletAmountMinor = 0,
    this.notes = RideNotes.empty,
    this.stops = const <RouteStop>[],
    this.driver,
    this.realtime,
    this.rideId,
    this.categoryId,
    this.persistRideSnapshot = true,
    this.routeChangeSupported = true,
    this.onTerminal,
    this.onDriverCancelled,
    this.onCompleted,
    this.onCancel,
    this.cancelFeeNote,
    this.controller,
  });

  final String pickupAddress;
  final String destinationAddress;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final String rideType;

  /// The fare in whole units of [currency].
  final double price;

  /// Q7: the trip's currency (its pickup's zone).
  final String currency;
  final String paymentMethod;

  /// The part of the fare booked to the Movera Wallet, in öre.
  final int walletAmountMinor;
  final RideNotes notes;

  /// Stops between the pickup and the destination, in order.
  final List<RouteStop> stops;
  final MatchedDriver? driver;

  /// Optional transport and lifecycle overrides let Scheduled Ride reuse this
  /// exact presentation without touching the on-demand ride session.
  final RideRealtime? realtime;
  final String? rideId;

  /// rider-u44: the trip's own category id, for its waiting terms and the
  /// cancel-fee preview (a reservation's). Null: the Book Now session's
  /// booked category of [rideId], else the stored snapshot's.
  final String? categoryId;
  final bool persistRideSnapshot;

  /// rider-u55: false for a scheduled ride's live page. Its ride id is the
  /// device-local reservation id the server has no route quote for, so
  /// Change route and "change destination instead" can never succeed.
  final bool routeChangeSupported;
  final Future<void> Function(BuildContext context, RideStatus status)?
  onTerminal;
  final Future<void> Function(BuildContext context)? onDriverCancelled;
  final Future<void> Function(BuildContext context, RideStatus status)?
  onCompleted;
  final Future<void> Function(BuildContext context, String? reasonId)? onCancel;

  /// rider-u53: the fee line of the cancel sheet when the trip's cancel
  /// terms are not the live Book Now rule (a reservation's late-cancel
  /// terms). Null: the live rule of the trip's category is previewed.
  final Future<String?> Function()? cancelFeeNote;

  /// Test seam: the controller the cancel and end-early requests go
  /// through (its API client). Production uses the shared one.
  final ActiveRideController? controller;

  @override
  State<WaitingForDriver> createState() => _WaitingForDriverState();
}

class _WaitingForDriverState extends State<WaitingForDriver> {
  late final ActiveRideController _ride =
      widget.controller ?? ActiveRideController();
  late final DriverTrackingController _tracking = DriverTrackingController(
    realtime: widget.realtime,
    pickupLat: widget.pickupPosition.latitude,
    pickupLng: widget.pickupPosition.longitude,
    destinationLat: widget.destinationPosition.latitude,
    destinationLng: widget.destinationPosition.longitude,
    persistRideSnapshot: widget.persistRideSnapshot,
  );
  late final CameraPosition _initialPosition;
  final SheetController _sheetController = SheetController();
  final GlobalKey<_WaitingRideMapState> _mapKey =
      GlobalKey<_WaitingRideMapState>(debugLabel: 'waiting-ride-map');
  bool _leaving = false;
  bool _completedOpened = false;
  bool _arrivalAnnounced = false;

  /// rider-u49: whether the saved "already announced" flag was read yet.
  bool _arrivalFlagRead = false;
  bool _researching = false;
  bool _overlayOn = false;
  bool _mapParked = false;
  bool _modalHandoffInProgress = false;
  bool _arrivedSheetShowing = false;
  Route<Object?>? _arrivedSheetRoute;
  bool _cancelling = false;

  /// rider-29: the cancel or end-early request is out. Back must not pop
  /// this screen meanwhile: the answer would be dropped on `!mounted`, a
  /// confirmed cancel would never go Home and a refused one would leave
  /// the ride with no screen.
  bool _cancelInFlight = false;
  StreamSubscription<({String rideId, bool stale})>? _outboxSub;
  RideStatus? _pendingStageStatus;
  String _sheetSignature = '';

  // The live route: starts from the widget, changes when the rider edits it.
  late String _pickupAddress = widget.pickupAddress;
  late LatLng _pickupPosition = widget.pickupPosition;
  late String _destinationAddress = widget.destinationAddress;
  late LatLng _destinationPosition = widget.destinationPosition;
  late List<RouteStop> _stops = List<RouteStop>.from(widget.stops);
  bool _routeEditOpen = false;

  /// Natural height of the sheet's content; the full stop ends there.
  double? _contentHeight;
  final GlobalKey _headerKey = GlobalKey(debugLabel: 'waiting-header');
  final GlobalKey _panelKey = GlobalKey(debugLabel: 'waiting-panel-body');

  /// The stop the sheet last came to rest at (for haptics and the camera).
  double? _settledSheet;
  Timer? _settleTimer;

  RideRealtime get _realtime =>
      widget.realtime ?? AppScope.instance.rideRealtime;
  String? get _rideId => widget.rideId ?? AppScope.instance.ride.rideId;

  @override
  void initState() {
    super.initState();
    _initialPosition = CameraPosition(target: widget.pickupPosition, zoom: 14);
    _sheetController.addListener(_syncSheetOverlay);
    moveraNavigationEpoch.addListener(_onNavigationChanged);
    setWebOverlayOpen(false);
    _tracking.driver = widget.driver;
    SafetyController.shared.load();
    final realtime = _realtime;
    if (realtime is MockRideRealtime) {
      realtime.destinationLat = _destinationPosition.latitude;
      realtime.destinationLng = _destinationPosition.longitude;
    }
    _outboxSub = ActiveRideController.queuedCancelNotices.listen(
      _onQueuedCancelNotice,
    );
    final rideId = _rideId;
    if (rideId != null && rideId.trim().isNotEmpty) {
      // R-O2: a queued cancel the launch flush refused or dropped before
      // this screen existed (a cold restore) is told now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final stale = ActiveRideController.takeQueuedCancelNotice(
          rideId.trim(),
        );
        if (stale != null) _showQueuedCancelNotice(stale: stale);
      });
    }
    if (rideId != null && rideId.trim().isNotEmpty) {
      _tracking.start(
        rideId: rideId,
        initial: widget.driver,
        initialStatus: _knownStatus(rideId),
        onChange: _onLiveTick,
      );
      RideCheckController.shared.attachTrip(
        _rideCheckTrip(rideId.trim()),
        _rideCheckPlan(),
      );
      _startRideCheckStillTimer(rideId.trim());
      unawaited(_loadWaitingTerms());
      unawaited(_readArrivalAnnounced(rideId.trim()));
    } else {
      // No rideId means nothing will ever subscribe: no driver marker, no
      // status changes, and previously no error either — the screen just
      // sat there silently. Say so explicitly instead.
      _missingRideId = true;
    }
  }

  bool _missingRideId = false;

  /// Q41/Q42: the waiting terms of the trip's category in its zone (free
  /// wait, then the fee per minute), once the zone's config is read.
  RiderCategoryWaiting? _waitingTerms;

  /// rider-u44: the category of this ride only. The on-demand session's
  /// booked category and the stored snapshot describe whatever Book Now
  /// ride ran last, so they count only when they are this ride.
  Future<String?> _tripCategoryId() async {
    final own = widget.categoryId;
    if (own != null && own.trim().isNotEmpty) return own;
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return null;
    final session = AppScope.instance.ride;
    if (session.rideId?.trim() == rideId && session.bookedCategoryId != null) {
      return session.bookedCategoryId;
    }
    final stored = await RouteChangeController.storedRide();
    return stored?.rideId?.trim() == rideId ? stored?.categoryId : null;
  }

  Future<void> _loadWaitingTerms() async {
    try {
      final category = await _tripCategoryId();
      if (category == null) return;
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      final terms = config?.waiting?.forCategory(category);
      if (!mounted || terms == null) return;
      // Never a rate in another currency than the trip's.
      if (terms.perMin.currency != widget.currency) return;
      setState(() => _waitingTerms = terms);
    } catch (_) {
      // No counter without terms.
    }
  }

  /// The live waiting clock while the driver is at the pickup (Q42).
  Widget? _waitingFeeCounter() {
    final terms = _waitingTerms;
    if (terms == null ||
        !terms.perMin.isPositive ||
        _tracking.status != RideStatus.driverWaiting) {
      return null;
    }
    return WaitingFeeCounter(
      // rider-u45: the server's stamp, else one start kept for the whole
      // wait (never "now" again on each rebuild).
      since:
          _tracking.waitingSince ?? (_waitingSinceFallback ??= DateTime.now()),
      freeWaitMin: terms.freeWaitMin,
      perMin: terms.perMin,
      // rider-r4-13: the server's end of the free wait, when it says.
      freeUntil: _tracking.waitingFreeUntil,
    );
  }

  DateTime? _waitingSinceFallback;

  /// RC-02/RC-03: a cancel or end-early that waited offline was refused by
  /// the server once it was sent. The ride goes on; say so.
  void _onQueuedCancelNotice(({String rideId, bool stale}) notice) {
    if (!mounted || _leaving) return;
    if (notice.rideId != _rideId?.trim()) return;
    ActiveRideController.takeQueuedCancelNotice(notice.rideId);
    _showQueuedCancelNotice(stale: notice.stale);
  }

  void _showQueuedCancelNotice({required bool stale}) {
    if (!mounted || _leaving) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          stale
              // R-O2: dropped before it was sent; the trip moved on.
              ? rideJustChangedMessage
              : context.l10n.cancelFailedStillOn,
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// RIDE-7: the stage this ride is already known to be in (a restore seeds
  /// the session from the snapshot), so tracking starts there.
  RideStatus? _knownStatus(String rideId) {
    final session = AppScope.instance.ride;
    if (session.rideId?.trim() != rideId.trim()) return null;
    final status = session.status;
    return status.isMatched ? status : null;
  }

  void _retryTracking() {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    setState(() => _missingRideId = false);
    _tracking.start(
      rideId: rideId,
      initial: widget.driver,
      onChange: _onLiveTick,
    );
  }

  void _retryLiveFeed() {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    _tracking.start(
      rideId: rideId,
      initial: _tracking.driver ?? widget.driver,
      onChange: _onLiveTick,
    );
    _sheetSignature = '';
    setState(() {});
  }

  void _onLiveTick() {
    if (!mounted) return;
    final status = _tracking.status;

    // The arrived sheet is a modal route sitting on top of this screen, so
    // stage navigation deliberately waits for it to close before acting (see
    // _drainStageNavigation's !_routeIsCurrent guard) — otherwise the trip
    // could start and finish entirely behind a sheet the rider hasn't
    // dismissed yet, and dismissing it would then jump straight to "Trip
    // complete" with the in-trip phase never shown. Close it the moment the
    // trip actually starts so the rider sees that phase instead of skipping it.
    //
    // rider-u47: a no-show or other end before the trip (the very moment the
    // arrived sheet is up) closes it too, so the rider sees the ride ended
    // instead of "Your driver has arrived" over a trip that is over.
    if (_arrivedSheetShowing &&
        (DriverEta.isInTrip(status) || status.isTerminal)) {
      _arrivedSheetShowing = false;
      // NAV-9: close the arrived sheet itself, not whatever route is on top
      // (a notification or Safety page pushed above it stays open).
      final route = _arrivedSheetRoute;
      _arrivedSheetRoute = null;
      closeRouteByReference(route);
    }

    // A driver drop is a reversible dispatch event, not the end of the
    // rider's trip. Handle it on the active Waiting owner immediately instead
    // of routing it through the generic terminal queue. The generic queue is
    // intentionally gated on route-current state; that can strand this
    // transient event when Waiting has just replaced the matching stage.
    if (status == RideStatus.cancelledByDriver) {
      if (!_leaving && !_completedOpened) {
        unawaited(_researchAfterDriverCancel());
      }
      return;
    }
    final replaced = _tracking.takeReplacedDriver();
    if (replaced != null) _onDriverReplaced(replaced);

    if (status.isTerminal && !status.isCompletedSurface) {
      _queueStageNavigation(status);
      return;
    }
    _feedRideCheck(status);
    _maybeAnnounceArrival();
    _maybeOpenCompleted();
    _mapKey.currentState?.paintIfDue();
    final signature = _sheetSignatureFor(
      status: status,
      driver: _tracking.driver ?? widget.driver,
      eta: _tracking.eta,
    );
    if (signature == _sheetSignature) return;
    _sheetSignature = signature;
    setState(() {});
  }

  String _sheetSignatureFor({
    required RideStatus status,
    required MatchedDriver? driver,
    required DriverEta? eta,
  }) {
    final headline = eta?.headline(status: status) ?? context.l10n.driverFound;
    final subtitle =
        eta?.subtitle(firstName: driver?.displayFirstName, status: status) ?? '';
    // rider-u48: in the trip the sheet's "Arrive by HH:MM" comes from the
    // live ETA, not from the constant in-trip headline, so it is part of
    // the signature too (else the sheet keeps the first arrival time).
    final arriveBy = _tripHeadline(eta, status) ?? '';
    return '${status.name}|$headline|$subtitle|${driver?.id ?? ''}'
        '|${_tracking.connectionDegraded}|$arriveBy';
  }

  /// rider-u23: the feed went straight from the dropped driver to the next
  /// one. Say so, close the old driver's arrived sheet, and announce the
  /// new driver's arrival when it comes.
  void _onDriverReplaced(MatchedDriver lost) {
    if (_arrivedSheetShowing) {
      _arrivedSheetShowing = false;
      final route = _arrivedSheetRoute;
      _arrivedSheetRoute = null;
      closeRouteByReference(route);
    }
    _arrivalAnnounced = false;
    // The next driver's arrival is news again, after a reload too.
    unawaited(_saveArrivalAnnounced(false));
    showDriverCancelledNotice(context, driverName: lost.firstName);
  }

  /// rider-u49: a reload must not show the arrived sheet the rider already
  /// dismissed, so the flag is kept with the ride's snapshot.
  Future<void> _readArrivalAnnounced(String rideId) async {
    try {
      if (await ActiveRideController.arrivalAnnounced(rideId)) {
        _arrivalAnnounced = true;
      }
    } catch (_) {
      // Unknown: the sheet may show once more, as before.
    }
    _arrivalFlagRead = true;
    if (mounted) _maybeAnnounceArrival();
  }

  Future<void> _saveArrivalAnnounced(bool announced) async {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    try {
      await ActiveRideController.rememberArrivalAnnounced(rideId, announced);
    } catch (_) {
      // Best effort: at worst the sheet shows again after a reload.
    }
  }

  /// The driver reaching pickup is easy to miss on a map the rider is not
  /// watching, so say it once and never again for this ride.
  void _maybeAnnounceArrival() {
    if (!mounted ||
        _leaving ||
        !_arrivalFlagRead ||
        _arrivalAnnounced ||
        _completedOpened ||
        _modalHandoffInProgress ||
        !_routeIsCurrent) {
      return;
    }
    final explicitArrival =
        _tracking.lastSignal == RideRealtimeSignal.driverArrived;
    if (!explicitArrival && _tracking.status != RideStatus.driverWaiting) {
      return;
    }
    _arrivalAnnounced = true;
    unawaited(_saveArrivalAnnounced(true));
    _arrivedSheetShowing = true;
    unawaited(
      showDriverArrivedSheet(
        context,
        driver: _tracking.driver ?? widget.driver,
        onWay: _realtime.supportsRiderSignals ? _sendOnTheWay : null,
        onRoute: (route) => _arrivedSheetRoute = route,
      ).whenComplete(() {
        _arrivedSheetShowing = false;
        _arrivedSheetRoute = null;
      }),
    );
  }

  Future<void> _sendOnTheWay() async {
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    if (!_realtime.supportsRiderSignals) return;
    await _realtime.sendSignal(
      rideId: rideId,
      signal: RideRealtimeSignal.riderOnTheWay,
      message: "I'm on the way",
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.sentOnTheWay),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _onNavigationChanged() {
    if (!mounted) return;
    // Route observer callbacks occur while Navigator is locked. Completion,
    // terminal and arrival surfaces can push sheets/routes, so wait one frame
    // before draining anything that was deferred behind a child route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainStageNavigation();
      if (!_leaving && !_completedOpened) _maybeAnnounceArrival();
    });
  }

  void _queueStageNavigation(RideStatus status) {
    if (!mounted || _completedOpened) return;
    _pendingStageStatus = status;
    // rider-u50: while a cancel or end-early is out the status waits here;
    // a cancel the server refuses replays it (_replayLiveStatus), where it
    // used to be dropped and Waiting stayed on a ride that was over.
    if (_leaving) return;
    _drainStageNavigation();
  }

  /// rider-u50: the cancel did not go through, so the ride goes on from
  /// whatever the live feed reported meanwhile (a completion, a no-show).
  void _replayLiveStatus() {
    if (!mounted || _leaving) return;
    _onLiveTick();
  }

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

  Future<void> _handleExternalTerminal(RideStatus status) async {
    if (!mounted ||
        _leaving ||
        _completedOpened ||
        !status.isTerminal ||
        status.isCompletedSurface) {
      return;
    }
    // A driver dropping the ride before pickup does not end the rider's trip.
    // Dispatch looks again, so say what happened and go back to searching
    // rather than sending them Home to rebook from scratch.
    if (status == RideStatus.cancelledByDriver && !_tracking.status.isCompletedSurface) {
      await _researchAfterDriverCancel();
      return;
    }
    _leaving = true;
    setState(() {});
    _tracking.dispose();

    // rider-u52: `closed` is a finished trip once it is paid and rated (a
    // resync after a long disconnect in trip can jump straight there). It
    // is not an external terminal and gets no error sheet: file it as
    // completed and go Home.
    if (status == RideStatus.closed) {
      final customTerminal = widget.onTerminal;
      if (customTerminal == null) await _ride.markClosedByServer();
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      if (customTerminal != null) {
        await customTerminal(context, status);
      } else {
        RideNavigator.home(context, status: status);
      }
      return;
    }

    // A queued outbox cancel (D-013/D-020) can land after the rider was told
    // the ride is still active. The server then reports cancelledByRider:
    // commit it locally instead of treating it as an external terminal.
    if (status == RideStatus.cancelledByRider && widget.onTerminal == null) {
      await _ride.completeServerConfirmedCancel(
        drivenMeters: _tracking.drivenMeters > 0 ? _tracking.drivenMeters : null,
      );
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      // rider-u51: a queued on-board End trip the outbox delivered is a
      // finished trip with a receipt (UI-01), like the direct path.
      final endedEarly = _ride.endedEarly;
      if (endedEarly != null) {
        _openEndedEarlySummary(endedEarly);
        return;
      }
      RideNavigator.home(context);
      return;
    }

    final customTerminal = widget.onTerminal;
    if (customTerminal != null) {
      await showRideTerminalStateSheet(context, status: status);
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      await customTerminal(context, status);
      return;
    }

    await _ride.markExternalTerminal(status);
    if (!mounted) return;
    await showRideTerminalStateSheet(context, status: status);
    if (!mounted) return;
    await _parkMapForStageChange();
    if (!mounted) return;
    RideNavigator.home(context, status: status);
  }

  Future<void> _researchAfterDriverCancel() async {
    if (_researching) return;
    _researching = true;
    final lostDriver = _tracking.driver ?? widget.driver;
    final byAdmin = _tracking.reassignedByAdmin;
    _tracking.dispose();

    // The rider is not asked anything: their ride is still on, so the search
    // starts again straight away and a short notice says why the driver
    // changed.
    if (!mounted) {
      _researching = false;
      return;
    }
    // Q13: an admin reassign is not the driver's doing; the rider just sees
    // the search, then the next driver assigned.
    if (!byAdmin) {
      showDriverCancelledNotice(context, driverName: lostDriver?.firstName);
    }

    await _parkMapForStageChange();
    if (!mounted) {
      _researching = false;
      return;
    }

    final customDriverCancelled = widget.onDriverCancelled;
    if (customDriverCancelled != null) {
      _leaving = true;
      setState(() {});
      try {
        await customDriverCancelled(context);
      } finally {
        _researching = false;
      }
      return;
    }

    // Same ride, same price, same addresses — only the driver changes.
    // Re-open the shared session before restarting dispatch. The tracking
    // controller already reconciled the driver-drop event as terminal, and
    // without this explicit reversible dispatch transition the parked Finding
    // route observes a stale cancelledByDriver session once the search restarts.
    final redispatchRideId = _rideId;
    await _ride.resumeSearchingAfterDriverCancel(rideId: redispatchRideId);
    if (!mounted) {
      _researching = false;
      return;
    }
    _realtime.researchAfterDriverCancel();
    _leaving = true;
    setState(() {});

    final navigator = Navigator.of(context);
    // Close what Waiting opened on top of itself (driver profile, chat, a
    // sheet) first, so the pop below leaves Waiting and not that page.
    final own = ModalRoute.of(context);
    if (own != null && own.isActive && !own.isCurrent) {
      navigator.popUntil((route) => route == own);
    }
    if (navigator.canPop()) {
      // Normal forward path already has the parked Finding route directly
      // underneath this screen. Return to it instead of stacking another
      // Finding route every time a driver drops the ride.
      _researching = false;
      navigator.pop(true);
      return;
    }

    // Cold restore can put Waiting directly inside RideRestoreGate, with no
    // pushed Finding route underneath. Replace only the gate child so the app
    // root/navigator stays intact.
    final finding = FindingDrivers(
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      pickupPosition: _pickupPosition,
      destinationPosition: _destinationPosition,
      rideType: widget.rideType,
      price: _price,
      currency: widget.currency,
      paymentMethod: widget.paymentMethod,
      walletAmountMinor: widget.walletAmountMinor,
      notes: widget.notes,
      stops: _stops,
    );
    final coordinator = RideRestoreCoordinator.instance;
    if (coordinator.replaceRootSurface(finding, RestoredSurface.finding)) {
      _researching = false;
      return;
    }

    // Widget tests or isolated hosts may not have RideRestoreGate installed.
    _researching = false;
    Navigator.pushReplacement(
      context,
      RideStageTransition(
        finding,
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
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
    await _ride.markCompleted(status);
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
      if (coordinator.replaceRootSurface(
        completed,
        RestoredSurface.complete,
      )) {
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

  /// When this screen first saw the driver accepted: the fallback start of
  /// the live free-cancel window when the projection has no `acceptedAt`.
  /// A reload restarts it, so the preview errs toward "free"; the server's
  /// own `cancellation.fee` is what is charged.
  final DateTime _shownAt = DateTime.now();

  /// Q12: the free-cancel clock counts from the driver's accept, as the
  /// server stamped it (`TripProjection.acceptedAt`), else from [_shownAt].
  DateTime get _acceptedAt => _tracking.acceptedAt ?? _shownAt;

  /// The fee line shown before the rider confirms a cancel (contract
  /// v0.3.0 §5), from the shared calculator and the rider config. Null when
  /// on board (that is end-early: the distance driven) or when no rule
  /// applies.
  Future<String?> _cancelFeeNote() async {
    if (_isInTrip) {
      // UI-01: end-early. The amount is the server's (the trip's `fare`
      // once it ends); the receipt that follows shows it.
      return context.l10n.bookedPriceWholeTrip(formatMoney(Money.fromLegacyMajor(_price, widget.currency), whole: true));
    }
    final ownNote = widget.cancelFeeNote;
    if (ownNote != null) {
      try {
        return await ownNote();
      } catch (_) {
        return null;
      }
    }
    try {
      final category = await _tripCategoryId();
      if (category == null) return null;
      // Q7: the fee rules of the trip's own zone, in its currency.
      final zone = RiderZones.byCurrency(widget.currency) ??
          RiderZones.at(_pickupPosition.latitude, _pickupPosition.longitude);
      final config = await AppScope.instance.riderConfig.forZone(zone.id);
      // Never a fee from another currency's rules.
      if (config.currency != widget.currency) return null;
      final preview = LiveCancelFeePreview.of(
        config,
        categoryId: category,
        fare: Money.fromLegacyMajor(_price, widget.currency),
        acceptedAt: _acceptedAt,
        now: DateTime.now(),
      );
      if (preview == null) return null;
      if (preview.fee.isPositive) {
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
      // Q2: the rider chose to change the destination instead.
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
      final result = await _ride.markCancelled(
        reasonId: outcome.reasonId,
        // R-O1: nothing tracked (for example right after a reload) is
        // shown as the rule, not as "0.0 km".
        drivenMeters: _isInTrip && _tracking.drivenMeters > 0
            ? _tracking.drivenMeters
            : null,
      );
      if (!mounted) return;
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
      if (!mounted) return;
      final endedEarly = _ride.endedEarly;
      if (endedEarly != null) {
        // UI-01: an on-board end is a finished trip with a receipt, not a
        // silent return to Home.
        _openEndedEarlySummary(endedEarly);
        return;
      }
      RideNavigator.home(context);
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
      _ =>
        context.l10n.cancelUnconfirmedOffline,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
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
      // cancelUntrackedRide already logs; a transient failure stays queued
      // in the pending-cancel outbox. Leaving is still what the rider chose.
    }
    if (!mounted) return;
    // rider-r4-25: a refused cancel is not queued; say so rather than
    // going Home as if the ride had been cancelled.
    if (outcome == RideCancelOutcome.rejected ||
        outcome == RideCancelOutcome.stale) {
      _showCancelProblem(outcome!);
    }
    RideNavigator.home(context);
  }

  void _openProfile() {
    final driver = _tracking.driver ?? widget.driver;
    if (driver == null) return;
    Navigator.push(
      context,
      RightToLeftTransition(DriverProfilePage(driver: driver)),
    );
  }

  void _callDriverUnavailable() {
    final driver = _tracking.driver ?? widget.driver;
    SafetyController.shared.record(
      SafetyKind.maskedCall,
      rideId: _rideId,
    );
    unawaited(
      showDriverCallUnavailable(
        context,
        driverName: driver?.displayFirstName,
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
      !_tracking.status.isTerminal &&
      !_completedOpened;

  /// The three dots on the ride card: the route screen with the current
  /// addresses. The pickup can move until the driver is there; the
  /// destination and the stops can change until the trip ends.
  Future<void> _openDetails() => _changeRoute(null, RouteChangeEntry.destination);

  double? _changedPrice;
  double get _price => _changedPrice ?? widget.price;

  /// The ride as the server knows it, for pricing a route change.
  Future<RideSnapshot?> _currentRide() async {
    final stored = await RouteChangeController.storedRide();
    final rideId = _rideId;
    if (stored != null && (rideId == null || stored.rideId == rideId)) {
      return stored.copyWith(
        status: _tracking.status,
        pickupAddress: _pickupAddress,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
        destinationAddress: _destinationAddress,
        destinationLat: _destinationPosition.latitude,
        destinationLng: _destinationPosition.longitude,
        stops: _stops,
        price: _price,
        currency: widget.currency,
      );
    }
    if (rideId == null || rideId.trim().isEmpty) return null;
    return RideSnapshot(
      status: _tracking.status,
      savedAt: DateTime.now(),
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      pickupLat: _pickupPosition.latitude,
      pickupLng: _pickupPosition.longitude,
      destinationLat: _destinationPosition.latitude,
      destinationLng: _destinationPosition.longitude,
      rideType: widget.rideType,
      price: _price,
      currency: widget.currency,
      paymentMethod: widget.paymentMethod,
      rideId: rideId,
      notes: widget.notes,
      stops: _stops,
      driver: _tracking.driver ?? widget.driver,
      walletAmountMinor: widget.walletAmountMinor,
    );
  }

  /// Change the pickup (until the driver is there), the destination or the
  /// stops: the new price is confirmed first, then the driver is told.
  Future<void> _changeRoute(
    BuildContext? sheetContext,
    RouteChangeEntry entry, {
    int? removeStop,
  }) async {
    if (_routeEditOpen || _leaving || !_routeEditable) return;
    _routeEditOpen = true;
    _modalHandoffInProgress = true;
    try {
      if (sheetContext != null) {
        await popCurrentRouteAndWaitForExit(sheetContext);
        if (!mounted) return;
      }
      final ride = await _currentRide();
      if (ride == null || !mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      final updated = removeStop != null
          ? await removeRouteStop(context, ride: ride, index: removeStop)
          : await openRouteChange(
              context,
              ride: ride,
              entry: entry,
              pickupLocked: !_pickupEditable,
              driverAccepted: true,
            );
      if (!mounted) return;
      if (updated != null) _applyRouteChange(updated);
      _mapParked = false;
      setState(() {});
      if (updated != null) {
        showRouteUpdated(
          context,
          driverAssigned: true,
          paymentMethod: widget.paymentMethod,
          // rider-u36: the server's difference, as the sheet showed it.
          differenceKr: lastRouteDifferenceKr ?? updated.price - ride.price,
          currency: updated.currency,
        );
      }
    } finally {
      _routeEditOpen = false;
      _modalHandoffInProgress = false;
    }
  }

  // ---- Ride check (RC1): live positions against the admin's triggers. ----

  bool _rideCheckEnded = false;
  bool _autoShareAsked = false;
  Timer? _rideCheckStillTimer;
  bool _liveFeedWasDown = false;

  /// rider-u56: whether this screen's live feed is down. The polling
  /// transport never errors the tracking stream on a failed poll; it marks
  /// the shared connection failed and backs off, so that state counts too.
  bool get _liveFeedDown =>
      _tracking.connectionDegraded ||
      (widget.realtime == null &&
          AppScope.instance.realtime.state != RealtimeState.connected);

  /// A driver app may stay quiet while the car stands still, so no new fix
  /// comes in to measure the stop. While the trip is under way and the live
  /// feed is up, check the long stop against the clock as well. With the
  /// feed down (the rider's own phone offline) no fix can come, so time
  /// without one says nothing about the car; the stop clock restarts when
  /// the feed is back.
  void _startRideCheckStillTimer(String rideId) {
    _rideCheckStillTimer?.cancel();
    if (!RideCheckController.tripMonitoring) return;
    _rideCheckStillTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      if (_liveFeedDown) {
        _liveFeedWasDown = true;
        return;
      }
      if (_liveFeedWasDown) {
        _liveFeedWasDown = false;
        RideCheckController.shared.liveFeedResumed(rideId);
        return;
      }
      if (!DriverEta.isInTrip(_tracking.status)) return;
      RideCheckController.shared.checkStill(rideId);
    });
  }

  /// "Solna centrum" from "Solna centrum, 171 45 Solna".
  static String _placeName(String address) {
    final first = address.split(',').first.trim();
    return first.isEmpty ? address.trim() : first;
  }

  RideCheckPlan _rideCheckPlan() => RideCheckPlan(
    pickup: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
    destination: GeoPoint(
      _destinationPosition.latitude,
      _destinationPosition.longitude,
    ),
    stops: [for (final stop in _stops) GeoPoint(stop.latitude, stop.longitude)],
    destinationLabel: _placeName(_destinationAddress),
  );

  List<RideCheckPlace> _rideCheckStops() => [
    for (final stop in _stops)
      RideCheckPlace(
        label: stop.address,
        point: GeoPoint(stop.latitude, stop.longitude),
      ),
  ];

  /// Rider, driver and trip details the safety team gets with an alert.
  RideCheckTripContext _rideCheckTrip(String rideId) {
    final driver = _tracking.driver ?? widget.driver;
    String? riderName;
    String? riderPhone;
    try {
      final profile = AppScope.instance.profile.profile;
      riderName = profile.name.trim().isEmpty ? null : profile.name.trim();
      riderPhone = profile.phone.trim().isEmpty ? null : profile.phone.trim();
    } catch (error) {
      // The alert still goes out with the trip and driver.
      AppLog.warning(
        'safety.ridecheck.profile_unavailable',
        extra: {'error': '$error'},
      );
    }
    return RideCheckTripContext(
      rideId: rideId,
      riderName: riderName,
      riderPhone: riderPhone,
      driverId: driver?.id,
      driverName: driver?.hasFirstName == true ? driver!.displayFirstName : null,
      driverPlate: driver?.plate,
      driverVehicle: driver == null || driver.vehicleLabel.isEmpty
          ? null
          : driver.vehicleLabel,
      pickup: RideCheckPlace(
        label: _pickupAddress,
        point: GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      ),
      destination: RideCheckPlace(
        label: _placeName(_destinationAddress),
        point: GeoPoint(
          _destinationPosition.latitude,
          _destinationPosition.longitude,
        ),
      ),
      stops: _rideCheckStops(),
      rideType: widget.rideType,
      status: _tracking.status.name,
    );
  }

  void _feedRideCheck(RideStatus status) {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final rideCheck = RideCheckController.shared;
    final driver = _tracking.driver ?? widget.driver;
    rideCheck.updateTrip(
      rideId,
      (trip) => trip.copyWith(
        status: status.name,
        driverId: driver?.id,
        driverName: driver?.hasFirstName == true ? driver!.displayFirstName : null,
        driverPlate: driver?.plate,
        driverVehicle: driver == null || driver.vehicleLabel.isEmpty
            ? null
            : driver.vehicleLabel,
      ),
    );
    if (DriverEta.isInTrip(status) && !_autoShareAsked) {
      // rider-u217: "Automatically share every ride".
      _autoShareAsked = true;
      unawaited(SafetyController.shared.autoShareRide(rideId));
    }
    final eta = _tracking.eta;
    final lat = eta?.latitude;
    final lng = eta?.longitude;
    final at = eta?.locationAt;
    if (lat == null || lng == null || at == null) return;
    final point = GeoPoint(lat, lng);
    if (DriverEta.isInTrip(status)) {
      rideCheck.addSample(
        rideId,
        RideCheckSample(point: point, at: at, etaSeconds: eta?.seconds),
      );
    } else if (status.isCompletedSurface && !_rideCheckEnded) {
      _rideCheckEnded = true;
      unawaited(rideCheck.tripEnded(rideId, point));
    }
  }

  void _applyRouteChange(RideSnapshot updated) {
    _pickupAddress = updated.pickupAddress;
    _pickupPosition = LatLng(updated.pickupLat, updated.pickupLng);
    _destinationAddress = updated.destinationAddress;
    _destinationPosition = LatLng(updated.destinationLat, updated.destinationLng);
    _stops = List<RouteStop>.from(updated.stops);
    _changedPrice = updated.price;
    _tracking
      ..pickupLat = _pickupPosition.latitude
      ..pickupLng = _pickupPosition.longitude
      ..destinationLat = _destinationPosition.latitude
      ..destinationLng = _destinationPosition.longitude;
    final realtime = _realtime;
    if (realtime is MockRideRealtime) {
      realtime.destinationLat = _destinationPosition.latitude;
      realtime.destinationLng = _destinationPosition.longitude;
      realtime.movePickup(_pickupPosition.latitude, _pickupPosition.longitude);
    }
    final rideId = _rideId?.trim();
    if (rideId != null && rideId.isNotEmpty) {
      RideCheckController.shared
        ..replan(rideId, _rideCheckPlan())
        ..updateTrip(
          rideId,
          (trip) => trip.copyWith(
            destination: RideCheckPlace(
              label: _placeName(_destinationAddress),
              point: GeoPoint(
                _destinationPosition.latitude,
                _destinationPosition.longitude,
              ),
            ),
            stops: _rideCheckStops(),
          ),
        );
    }
    _sheetSignature = '';
  }

  @override
  void dispose() {
    unawaited(_outboxSub?.cancel());
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _sheetController.removeListener(_syncSheetOverlay);
    _settleTimer?.cancel();
    _rideCheckStillTimer?.cancel();
    _sheetController.dispose();
    _tracking.dispose();
    final rideId = _rideId?.trim();
    if (rideId != null && rideId.isNotEmpty) {
      RideCheckController.shared.detachTrip(rideId);
    }
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.waiting);
    super.dispose();
  }

  void _syncSheetOverlay() {
    if (!_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;
    final offset = _sheetController.metrics?.offset;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 140), _onSheetSettled);
    final cover = offset != null && offset > _minSheet(media) + 12;
    if (cover == _overlayOn) return;
    _overlayOn = cover;
    setWebOverlayOpen(cover);
  }

  /// A light haptic when the sheet lands on a stop; the map then reframes
  /// gently so the driver and the pickup stay above the sheet.
  void _onSheetSettled() {
    if (!mounted || !_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    final offset = _sheetController.metrics?.offset;
    if (media == null || offset == null) return;
    for (final snap in _snaps(media)) {
      if ((offset - snap).abs() > 1.5) continue;
      final last = _settledSheet;
      if (last != null && (last - snap).abs() < 1.5) return;
      if (last != null) HapticFeedback.selectionClick();
      setState(() => _settledSheet = snap);
      return;
    }
  }

  List<double> _snaps(MediaQueryData media) {
    final low = _collapsedSheet(media);
    final mid = _minSheet(media);
    final full = _maxSheet(media);
    return [low, mid, if (full > mid + 24) full];
  }

  /// Room the map keeps clear at the bottom: the resting sheet, but never so
  /// much that the route shrinks to a sliver when the sheet is fully up.
  double _cameraClearance(MediaQueryData media) {
    final resting = _settledSheet ?? _minSheet(media);
    return math.min(resting, media.size.height * 0.6);
  }

  /// Reads the natural content height after layout (header + scroll
  /// content), so the full stop ends where the content does.
  void _measureContent() {
    if (!mounted) return;
    final media = MediaQuery.maybeOf(context);
    final body = _panelKey.currentContext;
    if (media == null || body == null) return;
    // The panel is a SingleChildScrollView; its child's own size is the
    // natural content height, whatever room the sheet gives it right now.
    SingleChildScrollView? scrollView;
    Element? content;
    void find(Element element) {
      if (content != null) return;
      final widget = element.widget;
      if (scrollView == null && widget is SingleChildScrollView) {
        scrollView = widget;
      } else if (scrollView != null && identical(widget, scrollView!.child)) {
        content = element;
        return;
      }
      element.visitChildElements(find);
    }

    body.visitChildElements(find);
    final box = content?.renderObject;
    if (box is! RenderBox || !box.hasSize) return;
    final padding =
        scrollView!.padding?.resolve(Directionality.of(context)).vertical ?? 0;
    final header = _headerKey.currentContext?.size?.height ?? 0;
    final needed =
        _handleHeight +
        header +
        box.size.height +
        padding +
        media.padding.bottom;
    final current = _contentHeight;
    if (current != null && (current - needed).abs() < 2) return;
    setState(() => _contentHeight = needed);
  }

  static const double _handleHeight = 22;

  /// Low stop: the handle and one compact row (ETA, driver, plate).
  double _collapsedSheet(MediaQueryData media) => 118 + media.padding.bottom;

  double _minSheet(MediaQueryData media) => 390 + media.padding.bottom;

  double _maxSheet(MediaQueryData media) {
    final minH = _minSheet(media);
    final maxH = media.size.height - media.padding.top - 72;
    final screenMax = maxH < minH + 48 ? minH + 48 : maxH;
    // The full stop ends where the content does: no empty white space.
    final content = _contentHeight;
    if (content == null) return screenMax;
    return content.clamp(minH, screenMax);
  }

  Future<void> _parkMapForStageChange() async {
    if (_mapParked) return;
    _mapParked = true;
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.waiting);
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
  }

  void _recenterMap() {
    final eta = _tracking.eta;
    final target = _isInTrip
        ? (eta?.latitude != null && eta?.longitude != null
              ? GeoPoint(eta!.latitude!, eta.longitude!)
              : GeoPoint(
                  _destinationPosition.latitude,
                  _destinationPosition.longitude,
                ))
        : GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude);
    AppScope.instance.camera.focusOnPickup(target);
  }

  @override
  Widget build(BuildContext context) {
    if (_missingRideId) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F5F1),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MoveraEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: context.l10n.cantTrackRide,
                    message:
                        context.l10n.cantTrackRideBody,
                    actionLabel: context.l10n.retry,
                    onAction: _retryTracking,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cancelling ? null : _leaveUntrackedRide,
                    child: Text(_cancelling ? context.l10n.leaving : context.l10n.goHome),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final driver = _tracking.driver ?? widget.driver;
    final eta = _tracking.eta;
    final headline = _headlineFor(eta, _tracking.status);
    final subtitle =
        eta?.subtitle(firstName: driver?.displayFirstName, status: _tracking.status) ??
        (driver == null
            ? context.l10n.driverDetailsLater
            : context.l10n.etaLeaveNowName(driver.displayFirstName));
    final media = MediaQuery.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureContent());
    return PopScope(
      canPop: _leaving && !_cancelInFlight,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // RC5: an open Ride check card has to be answered first.
        if (RideCheckController.shared.blocks(_rideId)) return;
        if (_isInTrip) {
          await _openDetails();
        } else {
          await _confirmCancel();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F5F1),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: _mapParked
                  ? const ColoredBox(color: Color(0xFFF6F5F1))
                  : _WaitingRideMap(
                      key: _mapKey,
                      initialPosition: _initialPosition,
                      pickupPosition: _pickupPosition,
                      destinationPosition: _destinationPosition,
                      pickupAddress: _pickupAddress,
                      destinationAddress: _destinationAddress,
                      stops: _stops,
                      tracking: _tracking,
                      cameraBottomPadding: _cameraClearance(media),
                      onTripRoute: (points) {
                        final rideId = _rideId?.trim();
                        if (rideId == null || rideId.isEmpty) return;
                        RideCheckController.shared.setPlannedRoute(
                          rideId,
                          points,
                        );
                      },
                    ),
            ),
            Positioned(
              top: media.padding.top + 8,
              left: 12,
              right: 12,
              child: PointerInterceptor(
                child: Row(
                  children: [
                    // Always the cancel action, never "collapse" — the
                    // chevron this used to show pre-trip is Finding's icon
                    // for collapsing its own sheet, and sharing it here made
                    // a rider trying to minimise the sheet land in the
                    // cancel flow instead.
                    MoveraIconButton.round(
                      icon: Icons.close_rounded,
                      onPressed: _confirmCancel,
                      // UI-01: on board this ends the trip early.
                      label: _isInTrip ? context.l10n.endTrip : context.l10n.cancelRide,
                    ),
                    const Spacer(),
                    SafetyKitMapButton(rideId: _rideId),
                  ],
                ),
              ),
            ),
            if (widget.realtime == null || _tracking.connectionDegraded)
              Positioned(
                top: media.padding.top + 62,
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.realtime == null)
                        RealtimeConnectionBanner(
                          connection: AppScope.instance.realtime,
                        ),
                      // D-015: a dead ride feed used to look exactly like a
                      // stationary driver. Say so, and offer to reconnect.
                      if (_tracking.connectionDegraded) ...[
                        if (widget.realtime == null) const SizedBox(height: 8),
                        LiveFeedDegradedBanner(onRetry: _retryLiveFeed),
                      ],
                    ],
                  ),
                ),
              ),
            // The recenter button rides on top of the sheet, and fades away
            // as the sheet rises over the map.
            AnimatedBuilder(
              animation: _sheetController,
              builder: (context, child) {
                final offset = _sheetOffset(media);
                final mid = _minSheet(media);
                final fade = (1 - (offset - mid) / 32).clamp(0.0, 1.0);
                return Positioned(
                  right: 12,
                  bottom: offset + 16,
                  child: IgnorePointer(
                    ignoring: fade < 0.5,
                    child: Opacity(opacity: fade, child: child),
                  ),
                );
              },
              child: PointerInterceptor(
                child: MoveraIconButton.round(
                  icon: Icons.my_location_rounded,
                  onPressed: _recenterMap,
                  label: context.l10n.recenterMap,
                ),
              ),
            ),
            SheetViewport(
              child: Sheet(
                controller: _sheetController,
                initialOffset: SheetOffset.absolute(_minSheet(media)),
                physics: MoveraSheetMotion.physics,
                snapGrid: SheetSnapGrid(
                  snaps: [
                    for (final snap in _snaps(media))
                      SheetOffset.absolute(snap),
                  ],
                  minFlingSpeed: 520,
                ),
                scrollConfiguration: SheetScrollConfiguration.disabled,
                child: PointerInterceptor(
                  child: SizedBox(
                    height: _maxSheet(media),
                    width: double.infinity,
                    child: Material(
                      key: const ValueKey<String>('waiting-panel'),
                      color: Colors.white,
                      elevation: 18,
                      shadowColor: const Color(
                        0xFF162C36,
                      ).withValues(alpha: 0.14),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Column(
                        children: [
                          const SizedBox(
                            width: double.infinity,
                            height: _handleHeight,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xFFE7EBEE),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(99),
                                  ),
                                ),
                                child: SizedBox(width: 36, height: 4),
                              ),
                            ),
                          ),
                          KeyedSubtree(
                            key: ValueKey<String>(
                              'waiting-stage-${_tracking.status.name}',
                            ),
                            child: const SizedBox.shrink(),
                          ),
                          if (!_isInTrip)
                            _reveal(
                              media,
                              start: 0.15,
                              child: KeyedSubtree(
                                key: _headerKey,
                                child: _fixedPickupHeader(
                                  driver,
                                  headline,
                                  subtitle,
                                ),
                              ),
                            ),
                          Expanded(
                            child: KeyedSubtree(
                              key: _panelKey,
                              child: _reveal(
                                media,
                                start: 0.3,
                                child: _panel(driver),
                              ),
                            ),
                          ),
                        ],
                      ),
                          _compactRow(media, driver, headline),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_cancelling)
              Positioned.fill(
                child: PointerInterceptor(
                  child: Semantics(
                    liveRegion: true,
                    label: context.l10n.cancellingYourRideLabel,
                    child: const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: _CancellingCard()),
                    ),
                  ),
                ),
              ),
            // RC3: the island grows into the Ride check card at the top.
            Positioned.fill(child: RideCheckLayer(rideId: _rideId)),
          ],
        ),
      ),
    );
  }

  /// The live arrival time during the trip ("Arrive by 08:19"), or null
  /// while no driver ETA has arrived yet.
  String? _tripHeadline(DriverEta? eta, RideStatus status) {
    final seconds = eta?.seconds;
    if (!DriverEta.isInTrip(status) || seconds == null) return null;
    return context.l10n.arriveBy(clockTime(DateTime.now().add(Duration(seconds: seconds))));
  }

  /// Headline for the sheet: the arrival time during the trip, the stage
  /// name without an ETA, and the driver's ETA to the pickup before it.
  String _headlineFor(DriverEta? eta, RideStatus status) {
    final live = _tripHeadline(eta, status);
    if (live != null) return live;
    if (DriverEta.isInTrip(status)) {
      return status == RideStatus.approachingDropoff
          ? context.l10n.approachingDestination
          : context.l10n.etaRideInProgress;
    }
    return eta?.headline(status: status) ?? context.l10n.driverFound;
  }

  double _sheetOffset(MediaQueryData media) {
    if (!_sheetController.hasClient) return _minSheet(media);
    return _sheetController.metrics?.offset ?? _minSheet(media);
  }

  /// 0 at the low stop, 1 from the middle stop up.
  double _openness(MediaQueryData media) {
    final low = _collapsedSheet(media);
    final mid = _minSheet(media);
    return ((_sheetOffset(media) - low) / (mid - low)).clamp(0.0, 1.0);
  }

  /// Full content fades and slides in as the sheet rises from the low stop,
  /// staggered by [start] so it settles in layers.
  Widget _reveal(
    MediaQueryData media, {
    required double start,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _sheetController,
      builder: (context, child) {
        final open = _openness(media);
        final t = Curves.easeOutCubic.transform(
          ((open - start) / (1 - start)).clamp(0.0, 1.0),
        );
        return IgnorePointer(
          ignoring: open < 0.5,
          child: ExcludeSemantics(
            excluding: open < 0.5,
            child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - t)),
              child: child,
            ),
          ),
          ),
        );
      },
      child: child,
    );
  }

  /// The low stop: one clean row with the ETA, the driver and the plate.
  /// Tapping it brings the sheet back to the middle.
  Widget _compactRow(
    MediaQueryData media,
    MatchedDriver? driver,
    String headline,
  ) {
    final plate = driver?.plate?.trim() ?? '';
    final photo = driver?.photoAsset;
    return Positioned(
      top: _handleHeight,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _sheetController,
        builder: (context, child) {
          final open = _openness(media);
          final t = Curves.easeOutCubic.transform(
            (1 - open / 0.6).clamp(0.0, 1.0),
          );
          // Out of the tree while hidden, so it never doubles the header.
          if (t <= 0.01) return const SizedBox.shrink();
          return IgnorePointer(
            ignoring: t < 0.5,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, -8 * (1 - t)),
                child: child,
              ),
            ),
          );
        },
        child: InkWell(
          key: const ValueKey<String>('waiting-compact-row'),
          onTap: () {
            HapticFeedback.selectionClick();
            _sheetController.animateTo(
              SheetOffset.absolute(_minSheet(media)),
              duration: MoveraDurations.normal,
              curve: Curves.easeOutCubic,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFF3F6FB),
                  backgroundImage: photo != null ? AssetImage(photo) : null,
                  child: photo == null
                      ? Text(
                          driver?.initial ?? '',
                          style: waitingText(15, weight: FontWeight.w700),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: waitingText(17, weight: FontWeight.w700),
                      ),
                      if (driver != null)
                        Text(
                          [
                            driver.displayFirstName,
                            if (driver.vehicleLabel.isNotEmpty)
                              driver.vehicleLabel,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: waitingText(
                            13,
                            color: const Color(0xFF5C656C),
                          ),
                        ),
                    ],
                  ),
                ),
                if (plate.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E7EB)),
                    ),
                    child: Text(
                      plate,
                      style: waitingText(14, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fixedPickupHeader(
    MatchedDriver? driver,
    String headline,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: waitingText(22, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: waitingText(14, color: const Color(0xFF5C656C)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WaitingShareButton(rideId: _rideId),
        ],
      ),
    );
  }

  Widget _panel(MatchedDriver? driver) {
    if (_isInTrip) {
      return RiderInTripPanel(
        headline: _tripHeadline(_tracking.eta, _tracking.status),
        destinationAddress: _destinationAddress,
        rideType: widget.rideType,
        paymentMethod: widget.paymentMethod,
        walletAmountMinor: widget.walletAmountMinor,
        price: _price,
        currency: widget.currency,
        driver: driver,
        rideId: _rideId,
        status: _tracking.status,
        onOpenProfile: _openProfile,
        onCall: _callDriverUnavailable,
        onMore: widget.routeChangeSupported ? _openDetails : null,
        onCancel: _confirmCancel,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaitingDriverCard(
            driver: driver,
            rideId: _rideId,
            onOpenProfile: _openProfile,
            onCall: _callDriverUnavailable,
            onMore: widget.routeChangeSupported ? _openDetails : null,
          ),
          const SizedBox(height: 12),
          if (_waitingFeeCounter() case final counter?) ...[
            counter,
            const SizedBox(height: 12),
          ],
          WaitingRideDetailsCard(
            rideType: widget.rideType,
            pickupAddress: _pickupAddress,
            destinationAddress: _destinationAddress,
            inTrip: _isInTrip,
            paymentMethod: widget.paymentMethod,
            walletAmountMinor: widget.walletAmountMinor,
            price: _price,
            currency: widget.currency,
            onMore: widget.routeChangeSupported ? _openDetails : null,
          ),
          WaitingNotesAndPin(notes: widget.notes, rideId: _rideId),
        ],
      ),
    );
  }
}

class _WaitingRideMap extends StatefulWidget {
  const _WaitingRideMap({
    super.key,
    required this.initialPosition,
    required this.pickupPosition,
    required this.destinationPosition,
    required this.pickupAddress,
    required this.destinationAddress,
    this.stops = const <RouteStop>[],
    required this.tracking,
    this.cameraBottomPadding = 140,
    this.onTripRoute,
  });

  final CameraPosition initialPosition;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final String pickupAddress;
  final String destinationAddress;
  final List<RouteStop> stops;
  final DriverTrackingController tracking;

  /// Approximates the sheet's on-screen clearance so [fitBounds] doesn't
  /// frame the driver and target only to have the bottom sheet cover them.
  final double cameraBottomPadding;

  /// The real road route of the trip, once the map has it (Ride check
  /// measures "off the route" against it).
  final ValueChanged<List<GeoPoint>>? onTripRoute;

  @override
  State<_WaitingRideMap> createState() => _WaitingRideMapState();
}

class _WaitingRideMapState extends State<_WaitingRideMap>
    with SingleTickerProviderStateMixin {
  // U7: the markers live in a notifier so the moving driver only updates the
  // map's marker set. It used to setState + drop the cached map leaf on
  // every animation tick, rebuilding the whole map subtree each frame.
  final ValueNotifier<Set<Marker>> _markerSet =
      ValueNotifier<Set<Marker>>(const <Marker>{});
  Set<Marker> get _markers => _markerSet.value;
  set _markers(Set<Marker> next) => _markerSet.value = next;
  Set<Polyline> _polylines = const <Polyline>{};
  /// Green pickup pin (the rider waits there).
  BitmapDescriptor? _riderPuck;
  BitmapDescriptor? _destinationPin;
  BitmapDescriptor? _driverCar;
  // Pins that carry times: "N min" over the pickup, "Arrive by HH:MM" over
  // the destination. Rebuilt only when the minute changes.
  BitmapDescriptor? _pickupTimePin;
  BitmapDescriptor? _destinationTimePin;
  String? _timePinKey;
  DateTime? _lastPaint;
  Timer? _pendingRepaint;
  DateTime? _lastRouteRefresh;
  bool _mapReady = false;
  String? _routeKey;
  Widget? _leaf;
  bool _approximateRoute = false;

  // M-01/M-02: the driver marker used to teleport to each new fix. Ease
  // between the last displayed position/heading and the new one instead.
  //
  // D-016: the ease used to be a fixed 900 ms while fixes arrive every ~2–3 s,
  // so the car moved for under a second and then stood still. The duration
  // now follows the observed interval between fixes (see driverEaseDuration).
  late final AnimationController _driverAnim = AnimationController(
    vsync: this,
    duration: driverEaseDuration(null),
  )..addListener(() {
      if (!mounted) return;
      // The ease now spans most of each fix interval, so cap marker updates
      // at ~20 fps rather than on every frame for that whole time.
      final now = DateTime.now();
      final last = _lastAnimRebuild;
      if (_driverAnim.isAnimating &&
          last != null &&
          now.difference(last) < const Duration(milliseconds: 50)) {
        return;
      }
      _lastAnimRebuild = now;
      // U7: markers only; the map leaf and the rest of the stack stay put.
      _markers = _buildMarkers();
    });
  DateTime? _lastAnimRebuild;
  DateTime? _lastFixArrivedAt;
  LatLng? _driverAnimFrom;
  LatLng? _driverAnimTo;
  double _driverHeadingFrom = 0;
  double _driverHeadingTo = 0;

  // M-08: last point the camera was fit to, so a fix that hasn't moved the
  // driver meaningfully doesn't re-trigger animateCamera every paint.
  LatLng? _lastFitDriverPoint;
  bool _lastFitInTrip = false;

  bool get _inTrip => DriverEta.isInTrip(widget.tracking.status);

  @override
  void initState() {
    super.initState();
    // rider-u59: a map rebuilt mid-ride (after a route change) starts from
    // the driver's last known fix instead of waiting for the next one,
    // which a driver standing at the pickup may not send for a while.
    _updateDriverAnimation();
    _markers = _buildMarkers();
    unawaited(_prepareMapVisuals());
  }

  @override
  void didUpdateWidget(covariant _WaitingRideMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.cameraBottomPadding - widget.cameraBottomPadding).abs() >
        1) {
      // The sheet came to rest at another stop: reframe gently so the
      // driver and the pickup stay above it.
      _lastFitDriverPoint = null;
      if (_mapReady) _maybeFitCamera();
    }
    if (oldWidget.pickupPosition == widget.pickupPosition &&
        oldWidget.destinationPosition == widget.destinationPosition &&
        oldWidget.pickupAddress == widget.pickupAddress &&
        oldWidget.destinationAddress == widget.destinationAddress &&
        _sameStops(oldWidget.stops, widget.stops) &&
        identical(oldWidget.tracking, widget.tracking)) {
      return;
    }
    _markers = _buildMarkers();
    _polylines = const <Polyline>{};
    _routeKey = null;
    _leaf = null;
    if (_mapReady) {
      unawaited(_refreshRoadRoute(force: true));
    }
  }

  @override
  void dispose() {
    _pendingRepaint?.cancel();
    _driverAnim.dispose();
    _markerSet.dispose();
    super.dispose();
  }

  void paintIfDue() {
    final now = DateTime.now();
    if (_lastPaint != null &&
        now.difference(_lastPaint!) < const Duration(milliseconds: 400)) {
      // M-03: a fix arriving inside the throttle window used to be dropped
      // until the next unrelated event happened to call paintIfDue again.
      // Schedule one for the remainder of this window instead.
      final remaining =
          const Duration(milliseconds: 400) - now.difference(_lastPaint!);
      _pendingRepaint?.cancel();
      _pendingRepaint = Timer(remaining, () {
        if (mounted) paintIfDue();
      });
      return;
    }
    _lastPaint = now;
    _updateDriverAnimation();
    _syncTimePins();

    final next = _buildMarkers();
    final markersChanged = !_sameMarkers(_markers, next);
    if (markersChanged && mounted) {
      // U7: no setState, no new map leaf; the marker listener updates it.
      _markers = next;
    }
    _maybeFitCamera();

    if (_mapReady &&
        (_lastRouteRefresh == null ||
            now.difference(_lastRouteRefresh!) >=
                const Duration(seconds: 10))) {
      unawaited(_refreshRoadRoute());
    }
  }

  /// Feeds a new fix into the from/to pair the animation eases between.
  /// The very first fix snaps (there is nothing to ease from yet).
  void _updateDriverAnimation() {
    final eta = widget.tracking.eta;
    final lat = eta?.latitude;
    final lng = eta?.longitude;
    if (lat == null || lng == null) return;
    final next = LatLng(lat, lng);
    final previousTo = _driverAnimTo;
    if (previousTo != null &&
        previousTo.latitude == next.latitude &&
        previousTo.longitude == next.longitude) {
      return;
    }
    final arrivedAt = DateTime.now();
    final previousArrival = _lastFixArrivedAt;
    _lastFixArrivedAt = arrivedAt;
    if (previousTo == null) {
      // First fix: nothing to animate from.
      _driverAnimFrom = next;
      _driverAnimTo = next;
      _driverHeadingFrom = 0;
      _driverHeadingTo = 0;
      return;
    }
    if (!driverMarkerEases) {
      // rider-u58: one marker update per fix, no in-between positions.
      final heading = _bearingDegrees(previousTo, next) ?? _driverHeadingTo;
      _driverAnim.stop();
      _driverAnimFrom = next;
      _driverAnimTo = next;
      _driverHeadingFrom = heading;
      _driverHeadingTo = heading;
      return;
    }
    _driverAnimFrom = _currentDriverPosition() ?? previousTo;
    _driverAnimTo = next;
    _driverHeadingFrom = _currentDriverHeading();
    _driverHeadingTo = _bearingDegrees(previousTo, next) ?? _driverHeadingFrom;
    _driverAnim
      ..stop()
      ..duration = driverEaseDuration(
        previousArrival == null ? null : arrivedAt.difference(previousArrival),
      )
      ..forward(from: 0);
  }

  LatLng? _currentDriverPosition() {
    final from = _driverAnimFrom;
    final to = _driverAnimTo;
    if (from == null || to == null) return to;
    final t = _driverAnim.value;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  double _currentDriverHeading() {
    if (_driverAnimFrom == null) return _driverHeadingTo;
    return lerpHeading(_driverHeadingFrom, _driverHeadingTo, _driverAnim.value);
  }

  /// Initial bearing from [from] to [to] in degrees, or null when the two
  /// points coincide (no direction to point).
  double? _bearingDegrees(LatLng from, LatLng to) {
    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return null;
    }
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return normalizeHeading(math.atan2(y, x) * 180 / math.pi);
  }

  void _maybeFitCamera() {
    final driver = _currentDriverPosition();
    if (driver == null) return;
    final target = _inTrip ? widget.destinationPosition : widget.pickupPosition;
    final samePoint = _lastFitDriverPoint != null &&
        _lastFitInTrip == _inTrip &&
        _lastFitDriverPoint!.latitude == driver.latitude &&
        _lastFitDriverPoint!.longitude == driver.longitude;
    if (samePoint) return;
    _lastFitDriverPoint = driver;
    _lastFitInTrip = _inTrip;
    // D-018: the sheet's clearance used to be passed as fitBounds' uniform
    // padding, i.e. applied to all four sides, which zoomed far out. Reserve
    // it at the bottom only by extending the framed bounds southwards.
    final fit = waitingCameraFit(
      a: GeoPoint(driver.latitude, driver.longitude),
      b: GeoPoint(target.latitude, target.longitude),
      viewportHeight: MediaQuery.maybeSizeOf(context)?.height ?? 800,
      bottomObstruction: widget.cameraBottomPadding,
    );
    unawaited(
      // A follow update: it leaves a map the rider is holding or has just
      // moved alone (the camera never moves under a finger).
      AppScope.instance.maps.fitBounds(
        fit.southwest,
        fit.northeast,
        padding: fit.padding,
        follow: true,
      ),
    );
  }

  bool _sameMarkers(Set<Marker> current, Set<Marker> next) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    final byId = <String, LatLng>{
      for (final marker in current) marker.markerId.value: marker.position,
    };
    for (final marker in next) {
      final position = byId[marker.markerId.value];
      if (position == null || position != marker.position) return false;
    }
    return true;
  }

  /// Labels for the time pins from the live ETA; new icons only when the
  /// label changes (minute granularity), never on every animation tick.
  void _syncTimePins() {
    final seconds = widget.tracking.eta?.seconds;
    if (seconds == null) return;
    final inTrip = _inTrip;
    final now = DateTime.now();
    final toPickupMin = (seconds / 60).ceil().clamp(1, 999);
    final arrive = inTrip
        ? now.add(Duration(seconds: seconds))
        : now.add(
            Duration(
              minutes:
                  toPickupMin +
                  estimatedRouteMinutes(
                    GeoPoint(
                      widget.pickupPosition.latitude,
                      widget.pickupPosition.longitude,
                    ),
                    [
                      for (final stop in widget.stops)
                        GeoPoint(stop.latitude, stop.longitude),
                    ],
                    GeoPoint(
                      widget.destinationPosition.latitude,
                      widget.destinationPosition.longitude,
                    ),
                  ),
            ),
          );
    final pickupLabel = context.l10n.minLineBreak('$toPickupMin');
    final arriveLabel = context.l10n.arriveBy(clockTime(arrive));
    final key = '$inTrip|$pickupLabel|$arriveLabel';
    if (key == _timePinKey) return;
    _timePinKey = key;
    unawaited(() async {
      final pins = await Future.wait([
        RouteTimeMarker.createIcon(pickup: true, label: pickupLabel),
        RouteTimeMarker.createIcon(pickup: false, label: arriveLabel),
      ]);
      if (!mounted || key != _timePinKey) return;
      _pickupTimePin = pins[0];
      _destinationTimePin = pins[1];
      _markers = _buildMarkers();
    }());
  }

  static bool _sameStops(List<RouteStop> a, List<RouteStop> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Set<Marker> _buildMarkers() {
    final driverPosition = _currentDriverPosition();
    final pickupIcon = _pickupTimePin ?? _riderPuck;
    final destinationIcon = _destinationTimePin ?? _destinationPin;
    return {
      if (!_inTrip && pickupIcon != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickupPosition,
          infoWindow: InfoWindow(title: shortPickupPlace(widget.pickupAddress)),
          icon: pickupIcon,
          anchor: _pickupTimePin != null
              ? RouteTimeMarker.anchor
              : const Offset(0.5, 0.5),
        ),
      ...routeStopMarkers(widget.stops),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationPosition,
        infoWindow: InfoWindow(
          title: shortPickupPlace(widget.destinationAddress),
        ),
        icon:
            destinationIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: _destinationTimePin != null
            ? RouteTimeMarker.anchor
            : const Offset(0.5, 0.5),
      ),
      if (driverPosition != null) _driverMarker(driverPosition),
    };
  }

  /// rider-u61: on the web the car bitmap comes turned (the plugin ignores
  /// rotation there).
  Marker _driverMarker(LatLng position) {
    final look = MoveraVehicleMarker.look(
      _driverCar,
      _currentDriverHeading(),
      onReady: () {
        if (mounted) setState(() {});
      },
    );
    return Marker(
      markerId: const MarkerId('driver'),
      position: position,
      rotation: look.rotation,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon:
          look.icon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
    );
  }

  Future<void> _prepareMapVisuals() async {
    final icons = await Future.wait<BitmapDescriptor>([
      RouteEndpointMarker.createIcon(pickup: true),
      MoveraVehicleMarker.createIcon(),
      RouteEndpointMarker.createIcon(pickup: false),
    ]);
    if (!mounted) return;
    setState(() {
      _riderPuck = icons[0];
      _destinationPin = icons[2];
      _driverCar = icons[1];
      _markers = _buildMarkers();
      _leaf = null;
    });
  }

  /// rider-u62/u63: how many of the trip's stops, in order, the car has
  /// reached (come within [_stopReachedMeters] of). The route from the
  /// driver goes through the rest.
  int _stopsReached = 0;
  static const double _stopReachedMeters = 80;

  void _noteStopsReached(GeoPoint driverPoint) {
    final stops = widget.stops;
    var reached = _stopsReached;
    while (reached < stops.length) {
      final stop = stops[reached];
      final meters = GeoDistance.metersBetween(
        driverPoint.latitude,
        driverPoint.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (meters > _stopReachedMeters) break;
      reached += 1;
    }
    if (reached != _stopsReached) {
      _stopsReached = reached;
      _routeKey = null; // The next refresh draws the remaining legs.
    }
  }

  /// The stops still ahead of the car, in order.
  List<GeoPoint> _remainingStops() {
    final stops = widget.stops;
    final reached = _stopsReached.clamp(0, stops.length);
    return [
      for (final stop in stops.sublist(reached))
        GeoPoint(stop.latitude, stop.longitude),
    ];
  }

  ({GeoPoint from, List<GeoPoint> via, GeoPoint to})? _routeEndpoints() {
    final eta = widget.tracking.eta;
    final driverPoint = eta?.latitude != null && eta?.longitude != null
        ? GeoPoint(eta!.latitude!, eta.longitude!)
        : null;

    if (_inTrip) {
      if (driverPoint != null) _noteStopsReached(driverPoint);
      return (
        from:
            driverPoint ??
            GeoPoint(
              widget.pickupPosition.latitude,
              widget.pickupPosition.longitude,
            ),
        // rider-u62/u63: through the stops still ahead, never straight to
        // the destination past them.
        via: _remainingStops(),
        to: GeoPoint(
          widget.destinationPosition.latitude,
          widget.destinationPosition.longitude,
        ),
      );
    }

    if (driverPoint == null) return null;
    return (
      from: driverPoint,
      via: const <GeoPoint>[],
      to: GeoPoint(
        widget.pickupPosition.latitude,
        widget.pickupPosition.longitude,
      ),
    );
  }

  Future<void> _refreshRoadRoute({bool force = false}) async {
    if (!_mapReady) return;
    final endpoints = _routeEndpoints();
    if (endpoints == null) return;

    String keyFor(GeoPoint point) =>
        '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    final requestKey =
        '${_inTrip ? 'trip' : 'pickup'}:${keyFor(endpoints.from)}>'
        '${endpoints.via.map(keyFor).join('>')}>${keyFor(endpoints.to)}';
    if (!force && requestKey == _routeKey) return;

    _routeKey = requestKey;
    _lastRouteRefresh = DateTime.now();
    final resolved = await roadRoutePolylineVia(
      id: 'active-road-route',
      from: LatLng(endpoints.from.latitude, endpoints.from.longitude),
      via: [
        for (final stop in endpoints.via)
          LatLng(stop.latitude, stop.longitude),
      ],
      to: LatLng(endpoints.to.latitude, endpoints.to.longitude),
      color: RiderRouteStyle.color,
    );
    final route = resolved.route;
    if (!mounted || _routeKey != requestKey || route.points.length < 2) return;

    // A leg falls back to a straight two-point line whenever a real road
    // route can't be resolved. A genuine road route for anything but a
    // trivially short hop has more than two vertices, so this is a
    // reasonable signal to tell the rider the line is approximate rather
    // than implying turn-by-turn accuracy that isn't there.
    final approximate = resolved.approximate;
    if (_inTrip && !approximate) {
      widget.onTripRoute?.call([
        for (final point in route.points)
          GeoPoint(point.latitude, point.longitude),
      ]);
    }
    setState(() {
      _polylines = styledRoute(route);
      _approximateRoute = approximate;
      _leaf = null;
    });
  }

  Widget _buildMap(Set<Marker> markers) {
    return CustomGoogleMap(
      key: const ValueKey('waiting-map'),
      initialPosition: widget.initialPosition,
      markers: markers,
      polylines: _polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      trafficEnabled: true,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false,
      mapType: MapType.normal,
      onMapCreated: (controller) {
        _mapReady = true;
        AppScope.instance.maps.attach(
          controller,
          owner: MapOwners.waiting,
        );
        unawaited(_refreshRoadRoute(force: true));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _leaf ??= RepaintBoundary(
            child: ValueListenableBuilder<Set<Marker>>(
              valueListenable: _markerSet,
              builder: (context, markers, _) => _buildMap(markers),
            ),
          ),
        ),
        if (_approximateRoute)
          Positioned(
            left: 12,
            bottom: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  context.l10n.approximateRoute,
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CancellingCard extends StatelessWidget {
  const _CancellingCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                context.l10n.findCancelling,
                style: waitingText(15, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// D-015: shown when the ride's realtime stream itself errored or closed, so
/// the driver marker is frozen rather than the driver standing still.
class LiveFeedDegradedBanner extends StatelessWidget {
  const LiveFeedDegradedBanner({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: context.l10n.livePaused,
      child: DecoratedBox(
        key: const ValueKey('waiting-live-feed-degraded'),
        decoration: BoxDecoration(
          color: const Color(0xF71D252C),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              const Icon(
                Icons.portable_wifi_off_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    context.l10n.livePaused,
                    style: waitingText(12.5, color: Colors.white),
                  ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
