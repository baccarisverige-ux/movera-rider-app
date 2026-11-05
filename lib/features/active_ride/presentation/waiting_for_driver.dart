import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
    show RideSnapshot, RouteChangeController, RouteChangeException;
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/core/location/location_repository.dart';
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
import 'package:movera_rider/features/active_ride/application/pickup_move_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/cancel_fee_texts.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_profile_page.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_pin_card.dart';
import 'package:movera_rider/features/active_ride/application/trip_pin.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/messages/presentation/trip_call.dart';
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
import 'package:movera_rider/core/contracts/on_trip.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_pending_card.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';

part 'waiting_for_driver_camera.dart';
part 'waiting_for_driver_changes.dart';
part 'waiting_for_driver_compact_row.dart';
part 'waiting_for_driver_live.dart';
part 'waiting_for_driver_map.dart';
part 'waiting_for_driver_sheet.dart';
part 'waiting_for_driver_stages.dart';
part 'waiting_for_driver_trip.dart';
part 'waiting_for_driver_widgets.dart';

/// What the trip screen's three dots open
/// ([WaitingForDriver.detailsAction]).
enum DetailsAction { routeScreen, movePickup, refused }

class WaitingForDriver extends StatefulWidget {
  /// G7 live fix: how long "the driver refused / you withdrew / accepted"
  /// stays (a close button ends it sooner); the default 4 s was too short.
  /// G7: what the three dots open. With `routeChange.beforePickup` off
  /// before boarding only the destination and the stops are refused: the
  /// pickup still moves while the driver is on the way (owner decision).
  static DetailsAction detailsAction({
    required bool beforePickupOff,
    required bool pickupEditable,
  }) {
    if (!beforePickupOff) return DetailsAction.routeScreen;
    return pickupEditable ? DetailsAction.movePickup : DetailsAction.refused;
  }

  static const routeOutcomeNoticeDuration = Duration(seconds: 10);

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
    this.location,
    this.pickupMove,
  });

  final String pickupAddress;
  final String destinationAddress;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final String rideType;

  /// Where the rider's phone is, for a Ride check at the end of a trip the
  /// live wire reports without a driver position (tests pass a fake). The
  /// app's own repository when null.
  final LocationRepository? location;

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

  /// v0.18.7 (item 4): moves the pickup on the server (`PATCH
  /// /trips/{tripId}`), on the contract wire; the demo's route screen
  /// otherwise. Tests pass their own.
  final PickupMoveController? pickupMove;

  /// Test seam: the clock the live cancel fee preview is worked out with.
  @visibleForTesting
  static DateTime Function() cancelFeeClock = DateTime.now;

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

  /// rider-r5-26: which arrived sheet [_arrivedSheetShowing] is about. A
  /// replaced driver's sheet closes after the new one opened; its close
  /// must not clear the new one's state.
  int _arrivedSheetToken = 0;
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

  /// v0.18.9: a withdraw of the pending route change is on its way.
  bool _routeWithdrawing = false;
  String? _routeChangeShown;

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

  /// The trip chat on the live wire, polled while this screen shows the
  /// ride so the Message button's unread badge is current (contract
  /// v0.5.4; the live transport never reads the event stream). Null in the
  /// demo, which has no chat server.
  MessagesController? _messages;

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
      AppScope.instance.ride.observeBookedPickup(
        rideId,
        widget.pickupPosition.latitude,
        widget.pickupPosition.longitude,
      );
      unawaited(_readArrivalAnnounced(rideId.trim()));
      if (AppScope.instance.tripMessages case final transport?) {
        _messages = MessagesController.forRide(rideId, transport: transport)
          ..startPolling(MessagesController.tripPollInterval);
      }
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

  /// v0.18.9 `routeChange.beforePickup` of the trip zone (default on).
  bool _changeBeforePickup = true;

  Future<void> _loadWaitingTerms() async {
    unawaited(_loadRouteChangeRules());
    try {
      final category = await _tripCategoryId();
      if (category == null) return;
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      final rideId = _rideId?.trim();
      if (config != null && rideId != null && rideId.isNotEmpty) {
        RideCheckController.shared.setZoneRideCheck(rideId, config.rideCheck);
      }
      final terms = config?.waiting?.forCategory(category);
      if (!mounted || terms == null) return;
      // Never a rate in another currency than the trip's.
      if (terms.perMin.currency != widget.currency) return;
      setState(() {
        _waitingTerms = terms;
        _zoneConfig = config;
        _categoryIdNow = category;
      });
    } catch (_) {
      // No counter without terms.
    }
  }

  Future<void> _loadRouteChangeRules() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: widget.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
        fresh: true,
      );
      if (!mounted || config == null) return;
      final rideId = _rideId?.trim();
      if (rideId != null && rideId.isNotEmpty) {
        RideCheckController.shared.setZoneRideCheck(rideId, config.rideCheck);
      }
      setState(() => _changeBeforePickup = config.routeChangeBeforePickup);
    } catch (_) {
      // The server refuses (route_change_before_pickup_off) if it must.
    }
  }

  RiderAppConfig? _zoneConfig;
  String? _categoryIdNow;

  DateTime? _waitingSinceFallback;

  /// RC-02/RC-03: a cancel or end-early that waited offline was refused by
  /// the server once it was sent. The ride goes on; say so.
  void _onQueuedCancelNotice(({String rideId, bool stale}) notice) {
    if (!mounted || _leaving) return;
    if (notice.rideId != _rideId?.trim()) return;
    ActiveRideController.takeQueuedCancelNotice(notice.rideId);
    _showQueuedCancelNotice(stale: notice.stale);
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

  bool _pinFetchStarted = false;

  /// G6: `GET /trips/{id}/pin` when the trip needs a PIN and the
  /// projection did not carry it (same value as `pickupPin`).
  void _maybeFetchPin() {
    if (_pinFetchStarted) return;
    if (!_tracking.pinRequired || _tracking.pinVerified) return;
    if (_tracking.pickupPin != null) return;
    final rideId = _rideId;
    if (rideId == null || rideId.trim().isEmpty) return;
    final api = AppScope.instance.api;
    if (!api.contractWire) return;
    _pinFetchStarted = true;
    unawaited(
      fetchTripPin(api, rideId).then((answer) {
        if (!mounted) return;
        if (answer.over) {
          _tracking.clearPin();
        } else if (answer.pin case final pin?) {
          _tracking.setFetchedPin(pin);
        } else {
          return;
        }
        setState(() {});
      }),
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
    // G6 (owner decision 6): one short message per waiting alert, no sound.
    for (final kind in _tracking.takeNewAlerts()) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: ValueKey('waiting-alert-$kind'),
            content: Text(waitingAlertText(context.l10n, kind)),
          ),
        );
    }
    _maybeFetchPin();
    _onTripG7();
    // v0.18.7 (item 4): the server moved the pickup (`pickup_moved`).
    if (_tracking.takeMovedPickup() case final moved?) {
      final changed =
          GeoDistance.metersBetween(
            _pickupPosition.latitude,
            _pickupPosition.longitude,
            moved.lat,
            moved.lng,
          ) >
          1;
      if (changed) {
        _applyMovedPickup(
          address: moved.address,
          lat: moved.lat,
          lng: moved.lng,
        );
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.pickupMoved)));
      }
    }

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
    // The chat ends with the trip: no more polling for its messages.
    if (status.isTerminal || status.isCompletedSurface) {
      _messages?.stopPolling();
      // Contract v0.13.0 §22: the chat closes at drop-off.
      MessagesController.closeRide(_rideId ?? '');
    }
    final replaced = _tracking.takeReplacedDriver();
    if (replaced != null) _onDriverReplaced(replaced);

    if (status.isTerminal && !status.isCompletedSurface) {
      // The driver ended the trip with the rider on board: for Ride check
      // that is the trip's end too (was the rider left far from the
      // drop-off?), decided before the "trip ended" sheet.
      final rideId = _rideId?.trim();
      if (status == RideStatus.endedByDriver &&
          _rideCheckOnBoard &&
          rideId != null &&
          rideId.isNotEmpty) {
        _rideCheckTripEnded(rideId);
      }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

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
    if (status == RideStatus.cancelledByDriver &&
        !_tracking.status.isCompletedSurface) {
      await _researchAfterDriverCancel();
      return;
    }
    _leaving = true;
    setState(() {});
    // "Search again" after a driver's end starts where the car stopped
    // (the server's last position on the trip), so read it before the
    // tracker lets go.
    final carStop =
        _tracking.eta?.latitude != null && _tracking.eta?.longitude != null
        ? GeoPoint(_tracking.eta!.latitude!, _tracking.eta!.longitude!)
        : null;
    _tracking.dispose();
    if (status == RideStatus.endedByDriver) {
      final rideId = _rideId?.trim();
      if (rideId != null && rideId.isNotEmpty) await _awaitRideCheck(rideId);
      if (!mounted) return;
    }

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
        drivenMeters: _tracking.drivenMeters > 0
            ? _tracking.drivenMeters
            : null,
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

    // N10 (owner, 2026-10-26): after a no-show or a driver's end the same
    // sheet offers "Search again" first, "Back to Home" second. The trip is
    // read before the session files it as over.
    final again = canSearchAgainAfter(status)
        ? _searchAgainTrip(status == RideStatus.endedByDriver ? carStop : null)
        : null;
    await _ride.markExternalTerminal(status);
    if (!mounted) return;
    if (again != null) {
      final searchAgain = await showRideEndedSearchAgainSheet(
        context,
        status: status,
        // v0.18.7 (Q6): a no-show says its fee (or "No fee").
        feeLine: status == RideStatus.noShow
            ? riderCancelFeeText(_tracking.cancellation)
            : null,
      );
      if (!mounted) return;
      await _parkMapForStageChange();
      if (!mounted) return;
      if (searchAgain && await _searchAgain(again)) return;
      if (!mounted) return;
      RideNavigator.home(context, status: status);
      return;
    }
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

  /// When this screen first saw the driver accepted: the fallback start of
  /// the live free-cancel window when the projection has no `acceptedAt`.
  /// A reload restarts it, so the preview errs toward "free"; the server's
  /// own `cancellation.fee` is what is charged.
  final DateTime _shownAt = DateTime.now();

  /// Q12: the free-cancel clock counts from the driver's accept, as the
  /// server stamped it (`TripProjection.acceptedAt`), else from [_shownAt].
  /// Whether the last live preview of [_cancelFeeNote] was a fee.
  bool _cancelFeeChargedNow = false;

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

  void _openProfile() {
    final driver = _tracking.driver ?? widget.driver;
    if (driver == null) return;
    Navigator.push(
      context,
      RightToLeftTransition(DriverProfilePage(driver: driver)),
    );
  }

  /// Contract v0.13.0 §22: the masked call, never the driver's number.
  void _callDriver() {
    SafetyController.shared.record(SafetyKind.maskedCall, rideId: _rideId);
    unawaited(
      callTripPeer(
        context,
        rideId: _rideId,
        transport: AppScope.instance.tripCall,
      ),
    );
  }

  /// The three dots on the ride card: the route screen with the current
  /// addresses. The pickup can move until the driver is there; the
  /// destination and the stops can change until the trip ends.
  Future<void> _openDetails() async {
    if (_routeEditOpen || _leaving) return;
    // G7 live fix: before boarding, read the zone's switch again (the admin
    // may have changed it since this screen opened). `beforePickup` covers
    // only the destination and the stops: with it off, the pickup can still
    // move (owner decision), so the three dots open the pickup move.
    final off = await _routeChangeOffBeforePickup();
    if (!mounted) return;
    switch (WaitingForDriver.detailsAction(
      beforePickupOff: off,
      pickupEditable: _pickupEditable,
    )) {
      case DetailsAction.routeScreen:
        await _changeRoute(null, RouteChangeEntry.destination);
      case DetailsAction.movePickup:
        await _movePickup();
      case DetailsAction.refused:
        _showRouteBeforePickupOff();
    }
  }

  double? _changedPrice;

  bool _pickupMoveOpen = false;

  Future<void> _movePickup() async {
    if (_pickupMoveOpen || _leaving) return;
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!_pickupEditable) {
      messenger?.showSnackBar(
        SnackBar(content: Text(context.l10n.pickupMoveFixedAfterArrival)),
      );
      return;
    }
    _pickupMoveOpen = true;
    _modalHandoffInProgress = true;
    try {
      await _parkMapForStageChange();
      if (!mounted) return;
      final picked = await ConfirmPickupSpot.open(
        context,
        initialPosition: _pickupPosition,
        initialAddress: _pickupAddress,
        title: context.l10n.movePickup,
        confirmLabel: context.l10n.confirmPickup,
      );
      if (!mounted) return;
      _mapParked = false;
      setState(() {});
      if (picked == null) return;
      final to = GeoPoint(picked.position.latitude, picked.position.longitude);
      final controller =
          widget.pickupMove ??
          PickupMoveController(
            api: AppScope.instance.api,
            session: AppScope.instance.ride,
          );
      final maxMeters =
          _tracking.terms?.maxPickupMoveMeters ??
          _zoneConfig?.maxPickupMoveMeters ??
          await _maxPickupMoveFromConfig();
      if (!mounted) return;
      try {
        final projection = await controller.move(
          tripId: rideId,
          address: picked.address,
          to: to,
          bookedPickup: _bookedPickup,
          maxMeters: maxMeters,
        );
        if (!mounted) return;
        final pickup = projection['pickup'];
        final lat = pickup is Map && pickup['lat'] is num
            ? (pickup['lat'] as num).toDouble()
            : to.latitude;
        final lng = pickup is Map && pickup['lng'] is num
            ? (pickup['lng'] as num).toDouble()
            : to.longitude;
        final address = pickup is Map && pickup['address'] is String
            ? (pickup['address'] as String)
            : picked.address;
        _applyMovedPickup(address: address, lat: lat, lng: lng);
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.pickupMoved)));
      } on PickupMoveException catch (error) {
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      _pickupMoveOpen = false;
      _modalHandoffInProgress = false;
    }
  }

  /// The pickup the server now has (the rider's own move, or a
  /// `pickup_moved` event): the route, the marker and the tracking follow.
  void _applyMovedPickup({
    required String address,
    required double lat,
    required double lng,
  }) {
    if (address.trim().isNotEmpty) _pickupAddress = address.trim();
    _pickupPosition = LatLng(lat, lng);
    _tracking
      ..pickupLat = lat
      ..pickupLng = lng;
    final realtime = _realtime;
    if (realtime is MockRideRealtime) realtime.movePickup(lat, lng);
    final rideId = _rideId?.trim();
    if (rideId != null && rideId.isNotEmpty) {
      RideCheckController.shared.replan(rideId, _rideCheckPlan());
    }
    // The device copy is not rewritten here: a restore reads the trip
    // from the server, whose projection carries the moved pickup.
    if (mounted) setState(() {});
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
          ? await removeRouteStop(
              context,
              ride: ride,
              index: removeStop,
              onProposed: _onRouteProposed,
            )
          : await openRouteChange(
              context,
              ride: ride,
              entry: entry,
              pickupLocked: !_pickupEditable,
              driverAccepted: true,
              onProposed: _onRouteProposed,
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

  /// Whether this screen saw the rider on board: a driver's end of the trip
  /// after that is a trip end for Ride check.
  bool _rideCheckOnBoard = false;

  /// The end-of-trip Ride check being decided (the phone may be asked).
  Future<void>? _rideCheckEnding;

  /// The longest the phone gets for a fix at the end of the trip.
  static const rideCheckOwnFixTimeout = Duration(seconds: 8);
  bool _autoShareAsked = false;
  Timer? _rideCheckStillTimer;
  bool _liveFeedWasDown = false;

  /// "Solna centrum" from "Solna centrum, 171 45 Solna".
  static String _placeName(String address) {
    final first = address.split(',').first.trim();
    return first.isEmpty ? address.trim() : first;
  }

  Future<GeoPoint?> _whereThePhoneIs() async {
    try {
      final here = await (widget.location ?? AppScope.instance.location)
          .getCurrentPosition()
          .timeout(rideCheckOwnFixTimeout);
      final point = GeoPoint(here.latitude, here.longitude);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Contract v0.18.9 (driver group 7): on trip. ----

  /// The confirmed change waits for the driver (the card says so).
  void _onRouteProposed(TripRouteChange change) {
    if (!mounted) return;
    setState(() => _tracking.routeChange = change);
  }

  /// The server's ride check (G7 decision 1) opens the Ride check card; a
  /// route change the driver answered (decision 3) is told once.
  void _onTripG7() {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty) return;
    final check = _tracking.rideCheck;
    final trigger = parseRideCheckTrigger(check?.trigger);
    if (check != null &&
        trigger != null &&
        check.openForRider(DateTime.now().toUtc())) {
      unawaited(
        RideCheckController.shared.openServer(
          rideId: rideId,
          checkId: check.checkId,
          trigger: trigger,
          askedAt: check.askedAt,
        ),
      );
    }
    // The pending card follows the projection (a change from another
    // device, an answer): rebuild when its state moved.
    final shownKey =
        '${_tracking.routeChange?.changeId}:'
        '${_tracking.routeChange?.status}';
    if (shownKey != _routeChangeShown) {
      _routeChangeShown = shownKey;
      setState(() {});
    }
    final outcome = _tracking.takeRouteChangeOutcome();
    if (outcome == null) return;
    final String text;
    if (outcome.accepted) {
      text = context.l10n.g7RouteAccepted;
      unawaited(_adoptAcceptedRoute(outcome));
    } else if (outcome.status == 'withdrawn') {
      text = context.l10n.g7RouteWithdrawn;
    } else if (outcome.status == 'expired') {
      // Deep-fix 2026-11-02: no answer in time is not a refusal.
      text = context.l10n.g7RouteExpired;
    } else {
      text = context.l10n.g7RouteRefused;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey('route-change-${outcome.status}'),
          content: Text(text),
          // G7 live fix: long enough to read, and closable.
          duration: WaitingForDriver.routeOutcomeNoticeDuration,
          showCloseIcon: true,
        ),
      );
  }

  Future<void> _adoptAcceptedRoute(TripRouteChange change) async {
    final ride = await _currentRide();
    if (ride == null || !mounted) return;
    final updated = await RouteChangeController.adoptAccepted(ride, change);
    if (!mounted) return;
    setState(() => _applyRouteChange(updated));
  }

  Future<void> _withdrawRouteChange(TripRouteChange change) async {
    final rideId = _rideId?.trim();
    if (rideId == null || rideId.isEmpty || _routeWithdrawing) return;
    setState(() => _routeWithdrawing = true);
    try {
      final after = await RouteChangeController(
        api: AppScope.instance.api,
        geocoding: AppScope.instance.geocoding,
        session: AppScope.instance.ride,
      ).withdraw(tripId: rideId, changeId: change.changeId);
      if (!mounted) return;
      _tracking.routeChange = after ?? _tracking.routeChange;
      _onTripG7();
    } on RouteChangeException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _routeWithdrawing = false);
    }
  }

  @override
  void dispose() {
    unawaited(_outboxSub?.cancel());
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _sheetController.removeListener(_syncSheetOverlay);
    _settleTimer?.cancel();
    _rideCheckStillTimer?.cancel();
    _messages?.dispose();
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
                    message: context.l10n.cantTrackRideBody,
                    actionLabel: context.l10n.retry,
                    onAction: _retryTracking,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cancelling ? null : _leaveUntrackedRide,
                    child: Text(
                      _cancelling ? context.l10n.leaving : context.l10n.goHome,
                    ),
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
        eta?.subtitle(
          firstName: driver?.displayFirstName,
          status: _tracking.status,
        ) ??
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
                      label: _isInTrip
                          ? context.l10n.endTrip
                          : context.l10n.cancelRide,
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
                      // N10: a trip that is over has no live feed to lose;
                      // no "connection lost" over its end sheet.
                      if (widget.realtime == null && !_leaving)
                        RealtimeConnectionBanner(
                          connection: AppScope.instance.realtime,
                        ),
                      // D-015: a dead ride feed used to look exactly like a
                      // stationary driver. Say so, and offer to reconnect.
                      if (_tracking.connectionDegraded && !_leaving) ...[
                        if (widget.realtime == null) const SizedBox(height: 8),
                        LiveFeedDegradedBanner(onRetry: _retryLiveFeed),
                      ],
                    ],
                  ),
                ),
              ),
            // v0.18.9: the confirmed route change waits for the driver.
            if (_tracking.routeChange case final change?
                when change.pending && !_leaving)
              Positioned(
                top:
                    media.padding.top +
                    (widget.realtime == null || _tracking.connectionDegraded
                        ? 130
                        : 62),
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  child: RouteChangePendingCard(
                    change: change,
                    withdrawing: _routeWithdrawing,
                    onWithdraw: () => _withdrawRouteChange(change),
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
}
