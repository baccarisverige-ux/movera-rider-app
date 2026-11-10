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
import 'package:movera_rider/features/messages/domain/trip_messages_transport.dart';
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
part 'waiting_for_driver_cancel.dart';
part 'waiting_for_driver_changes.dart';
part 'waiting_for_driver_chat.dart';
part 'waiting_for_driver_compact_row.dart';
part 'waiting_for_driver_details.dart';
part 'waiting_for_driver_feed.dart';
part 'waiting_for_driver_layout.dart';
part 'waiting_for_driver_live.dart';
part 'waiting_for_driver_map.dart';
part 'waiting_for_driver_research.dart';
part 'waiting_for_driver_screen.dart';
part 'waiting_for_driver_setup.dart';
part 'waiting_for_driver_sheet.dart';
part 'waiting_for_driver_stages.dart';
part 'waiting_for_driver_terminal.dart';
part 'waiting_for_driver_trip.dart';
part 'waiting_for_driver_widgets.dart';

/// What the trip screen's three dots open
/// ([WaitingForDriver.detailsAction]).
enum DetailsAction { routeScreen, movePickup, refused }

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

  /// The trip chat on the live wire: read once, then kept current by the
  /// trip stream's `message` events (v0.18.56 §78 `chat.stream`) so the
  /// Message button's unread badge follows. Null in the demo, which has no
  /// chat server.
  MessagesController? _messages;

  /// Unread messages last seen, so only a NEW one opens the sheet.
  int _seenUnread = 0;

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
        _startTripChat(rideId, transport);
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

  RiderAppConfig? _zoneConfig;
  String? _categoryIdNow;

  DateTime? _waitingSinceFallback;

  bool _pinFetchStarted = false;

  /// When this screen first saw the driver accepted: the fallback start of
  /// the live free-cancel window when the projection has no `acceptedAt`.
  /// A reload restarts it, so the preview errs toward "free"; the server's
  /// own `cancellation.fee` is what is charged.
  final DateTime _shownAt = DateTime.now();

  /// Q12: the free-cancel clock counts from the driver's accept, as the
  /// server stamped it (`TripProjection.acceptedAt`), else from [_shownAt].
  /// Whether the last live preview of [_cancelFeeNote] was a fee.
  bool _cancelFeeChargedNow = false;

  double? _changedPrice;

  bool _pickupMoveOpen = false;

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

  @override
  void dispose() {
    unawaited(_outboxSub?.cancel());
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _sheetController.removeListener(_syncSheetOverlay);
    _settleTimer?.cancel();
    _rideCheckStillTimer?.cancel();
    _messages?.removeListener(_onTripChatChanged);
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
