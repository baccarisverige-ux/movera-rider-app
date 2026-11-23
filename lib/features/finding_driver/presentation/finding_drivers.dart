import 'package:movera_rider/core/contracts/search_step.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_radar.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_services.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_map_marks.dart';
import 'package:movera_rider/features/finding_driver/presentation/share_location_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/pickup_edit_card.dart';
import 'package:movera_rider/features/saved_places/presentation/saved_places.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart'
    show RouteChangeQuote;
import 'package:movera_rider/core/app_update/ride_live_signal.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/cancel_preview_note.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/domain/nearby_vehicle.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/finding_driver/presentation/rebook_price_dialog.dart';
export 'package:movera_rider/features/finding_driver/presentation/rebook_price_dialog.dart'
    show showRebookPriceDialog;
import 'package:movera_rider/features/finding_driver/presentation/still_looking_card.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart'
    show RideSnapshot;
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/application/trip_route_line.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';
import 'package:movera_rider/shared/widgets/ride_stage_map.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/wallet/domain/rider_debt.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/approximate_route_badge.dart';

part 'finding_drivers_map_panel.dart';
part 'finding_drivers_pickup_edit.dart';

class FindingDrivers extends StatefulWidget {
  const FindingDrivers({
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
    this.realtime,
    this.etaMinutes,
    this.searchStartedAt,
    this.createdAt,
    @visibleForTesting this.controller,
    @visibleForTesting this.booking,
    @visibleForTesting this.riderLocation,
    @visibleForTesting this.pickupEditor,
  });

  /// Owner 2026-11-23: where the rider is (their marker); tests fake it.
  final SearchingRiderLocation? riderLocation;

  /// Owner 2026-11-23 ("Justera"): the pickup edit services; tests fake it.
  final SearchingPickupEditor? pickupEditor;

  /// v0.18.152: the clock a booked ride's cancel line is read at (the
  /// server's preview is a clock compare); tests move it.
  @visibleForTesting
  static DateTime Function() cancelFeeClock = DateTime.now;

  /// When this ride's search started, for a restored search (ARCH-3: the
  /// "still looking" mark is not restarted by a reload). Null: now.
  final DateTime? searchStartedAt;

  /// When the ride was created, for a restored search. Null: now.
  final DateTime? createdAt;

  /// Test seam for "Try again" after no driver was found (RIDE-19).
  final BookingController? booking;

  /// The part of the fare booked to the Movera Wallet, in öre.
  final int walletAmountMinor;

  /// Stops between the pickup and the destination, in order.
  final List<RouteStop> stops;

  /// The chosen ride's estimated minutes to the pickup, for the time pins
  /// while searching. Null (for example after a restore) shows plain pins.
  final int? etaMinutes;

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
  final RideNotes notes;
  final RideRealtime? realtime;

  /// Test seam (for example a controller on a fake API); production builds
  /// its own from [realtime].
  final FindingDriverController? controller;

  @override
  State<FindingDrivers> createState() => _FindingDriversState();
}

/// How a "Try again" after no driver found ended.
enum _Rebook {
  /// The new search runs.
  started,

  /// Refused or failed: no new ride exists.
  failed,

  /// No answer (timeout, dropped connection): the ride may exist (RC-09).
  uncertain,

  /// rider-u107: the price changed and the rider chose not to book it.
  declined,
}

class _FindingDriversState extends State<FindingDrivers>
    with RideScreenLive<FindingDrivers> {
  /// The trip's currency: the one the search holds once it started (a
  /// restored or re-requested trip keeps its own), else the widget's.
  String get _currency => _match.ownershipSnapshot?.currency ?? widget.currency;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  late final FindingDriverController _match =
      widget.controller ?? FindingDriverController(realtime: widget.realtime);
  bool _mapParked = false;
  bool _mapReady = false;

  /// G25: the map's controller, so a map kept while parked (native) is
  /// attached again when this screen is back on top.
  GoogleMapController? _mapController;

  /// G25 step B: this screen's place in the one trip map (handed to
  /// Waiting at "driver found", taken back after a driver drop).
  final RideStageSeat _mapSeat = RideStageSeat();
  bool _leaving = false;

  /// rider-u106: "Try again" is creating the new booking. The screen must
  /// not be left meanwhile, or the new live search has no owner.
  bool _rebooking = false;

  /// rider-u107: the quote the rider confirmed for "Try again", kept while
  /// an uncertain booking is retried so it is not asked again.
  RideQuote? _rebookQuote;
  bool _cancelSheetOpen = false;
  bool _pickupEditOpen = false;
  final bool _detailsSheetOpen = false;
  bool _matchedPending = false;

  /// Tells an open "Cancel ride?" sheet that a driver accepted (RIDE-15).
  final ValueNotifier<bool> _driverMatched = ValueNotifier<bool>(false);
  RideStatus? _terminalPending;
  bool _overlayOn = false;

  /// Whether the sheet is pulled up past its resting height; the collapse
  /// chevron is only offered then (AUD-3).
  bool _sheetExpanded = false;
  int _nearbyPaintKey = 0;
  final SheetController _sheetController = SheetController();

  /// Green pickup pin (the rider waits there).
  BitmapDescriptor? _riderPuck;
  BitmapDescriptor? _destinationPin;
  Offset _pinAnchor = const Offset(0.5, 0.5);
  BitmapDescriptor? _driverCar;
  List<LatLng>? _roadRoutePoints;
  bool _roadApproximate = false;

  late String _pickupAddress;
  late LatLng _pickupPosition;
  late String _destinationAddress;
  late LatLng _destinationPosition;
  late List<RouteStop> _stops;

  // Owner 2026-11-23 (search screen): the rider's marker.
  late final SearchingRiderLocation _riderLocation =
      widget.riderLocation ?? const SearchingRiderLocation();
  GeoPoint? _riderFix;
  BitmapDescriptor? _riderKnownIcon;
  final List<BitmapDescriptor?> _riderOffIcons = List.filled(4, null);
  int _pulseStep = 0;
  Timer? _pulseTimer;
  bool _shareSheetOpen = false;

  // Owner 2026-11-23 ("Justera"): the locked pickup and its edit mode.
  late final SearchingPickupEditor _pickupEditor =
      widget.pickupEditor ?? const SearchingPickupEditor();
  BitmapDescriptor? _adjustIcon;
  bool _editingPickup = false;
  LatLng _editTarget = const LatLng(0, 0);
  String _editAddress = '';
  RouteChangeQuote? _editQuote;
  bool _editBusy = false;
  int _editSeq = 0;

  @override
  void initState() {
    super.initState();
    _pickupAddress = widget.pickupAddress;
    _pickupPosition = widget.pickupPosition;
    _destinationAddress = widget.destinationAddress;
    _destinationPosition = widget.destinationPosition;
    _stops = List<RouteStop>.from(widget.stops);
    _sheetController.addListener(_syncSheetOverlay);
    moveraNavigationEpoch.addListener(_onNavigationChanged);
    setWebOverlayOpen(false);
    _loadMapBits();
    unawaited(_prepareMapVisuals());
    unawaited(_prepareSearchMarks());
    unawaited(_readRiderFix());
    _startMatching(
      price: widget.price,
      searchStartedAt: widget.searchStartedAt,
      createdAt: widget.createdAt,
    );
    unawaited(_loadZoneConfig());
    // v0.18.6 (G4-E4): a new rider config version (config_published, e.g.
    // the admin changed the raise limit) or a refused raise reads the
    // zone's config again.
    final source = AppScope.instance.riderConfig;
    _configSource = source;
    if (source case final Listenable listenable) {
      listenable.addListener(_onConfigChanged);
    }
    _match.onRaiseLimitRefused = _onRaiseLimitRefused;
    // R-O2: a queued cancel the launch flush refused or dropped before this
    // screen existed (a cold restore) is told now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = (_match.ownedRideId ?? AppScope.instance.ride.rideId)?.trim();
      if (!mounted || id == null || id.isEmpty) return;
      final stale = ActiveRideController.takeQueuedCancelNotice(id);
      if (stale == true) {
        _showCancelNotice(rideJustChangedMessage);
      } else if (stale == false) {
        _showCancelNotice(context.l10n.driverAlreadyAccepted);
      }
    });
  }

  void _startMatching({
    double? price,
    DateTime? searchStartedAt,
    DateTime? createdAt,
    int? maxOfferMinor,
    int? bookedFareMinor,
  }) {
    final effectivePrice =
        price ?? (_match.currentPrice > 0 ? _match.currentPrice : widget.price);
    _match.startFrom(
      pickupAddress: _pickupAddress,
      destinationAddress: _destinationAddress,
      pickupLat: _pickupPosition.latitude,
      pickupLng: _pickupPosition.longitude,
      destinationLat: _destinationPosition.latitude,
      destinationLng: _destinationPosition.longitude,
      rideType: widget.rideType,
      price: effectivePrice,
      currency: _currency,
      paymentMethod: widget.paymentMethod,
      walletAmountMinor: widget.walletAmountMinor,
      notes: widget.notes,
      stops: _stops,
      searchStartedAt: searchStartedAt,
      createdAt: createdAt,
      maxOfferMinor: maxOfferMinor,
      bookedFareMinor: bookedFareMinor,
      onTick: (_) {
        if (!mounted) return;
        final nearbyKey = Object.hashAll(
          _match.nearby.map((vehicle) => '${vehicle.id}:${vehicle.latitude}'),
        );
        if (nearbyKey != _nearbyPaintKey) {
          _nearbyPaintKey = nearbyKey;
          _loadMapBits();
        }
        setState(() {});
        _syncSheetOverlay();
        _openSheetForPriceBump();
      },
      onMatched: () {
        if (!mounted || _leaving) return;
        _matchedPending = true;
        _driverMatched.value = true;
        _drainDeferredNavigation();
      },
      onTerminal: (status) {
        if (!mounted || _leaving) return;
        _terminalPending = status;
        _drainDeferredNavigation();
      },
      onCancelRefused: () {
        if (!mounted) return;
        setState(() {});
        final id = _match.ownedRideId;
        if (id != null) ActiveRideController.takeQueuedCancelNotice(id);
        _showCancelNotice(
          _match.lastRefusalWasStale
              // R-O2: the queued cancel was dropped; the trip moved on.
              ? rideJustChangedMessage
              : context.l10n.driverAlreadyAccepted,
        );
      },
    );
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _onNavigationChanged() {
    if (!mounted) return;
    // NavigatorObserver notifications fire while Navigator is still locked.
    // A deferred match/terminal may need to push a route, so drain it only
    // after the current push/pop has fully committed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainDeferredNavigation();
    });
  }

  void _drainDeferredNavigation() {
    if (!mounted ||
        _leaving ||
        !_routeIsCurrent ||
        _cancelSheetOpen ||
        _pickupEditOpen ||
        _shareSheetOpen ||
        _detailsSheetOpen) {
      return;
    }

    final terminal = _terminalPending;
    if (terminal != null) {
      _terminalPending = null;
      _matchedPending = false;
      unawaited(_handleTerminal(terminal));
      return;
    }

    if (_matchedPending) {
      _matchedPending = false;
      unawaited(_openWaiting());
    }
  }

  Future<void> _resumeFindingAfterDriverCancel() async {
    if (!mounted) return;
    // RIDE-8: a route change made on Waiting is saved to the ride snapshot
    // (and the server), not handed back here. Search again with the ride's
    // current route and price, not the ones this screen started with.
    // G25 step B (supervisor F2): take the trip map back before any await, so
    // it is never left without a seat while Waiting's route leaves.
    _takeTripMapBack();
    setState(() => _mapParked = false);
    final current = await _match.storedRide();
    if (!mounted) return;
    if (current != null) _adoptRoute(current);
    final effectivePrice = current != null
        ? current.price
        : (_match.currentPrice > 0 ? _match.currentPrice : widget.price);
    // rider-u93: and the offer ceiling that route change set, not the one
    // the session kept from booking.
    final maxOfferMinor =
        current?.maxOfferMinor ?? _match.ownershipSnapshot?.maxOfferMinor;
    final bookedFareMinor =
        current?.bookedFareMinor ?? _match.ownershipSnapshot?.bookedFareMinor;
    _leaving = false;
    _cancelSheetOpen = false;
    _driverMatched.value = false;
    _pickupEditOpen = false;
    _overlayOn = false;
    _nearbyPaintKey = 0;
    setWebOverlayOpen(false);
    // G25 step B: the trip map came back from Waiting above (before the
    // await); its owner is attached again once it is shown (_onKeptMapResumed).
    // A new dispatch round: its own "still looking" mark.
    _startMatching(
      price: effectivePrice,
      searchStartedAt: DateTime.now(),
      maxOfferMinor: maxOfferMinor,
      bookedFareMinor: bookedFareMinor,
    );
    _loadMapBits();
  }

  Future<void> _handleTerminal(RideStatus status) async {
    if (!mounted || _leaving) return;
    if (status == RideStatus.cancelledByRider && _match.cancelled) {
      // RC-03: the server confirmed a cancel that was waiting offline.
      await _finishCommittedCancel();
      return;
    }
    _leaving = true;
    setState(() {});
    final ended = _match.ownershipSnapshot;
    final canRetry =
        status == RideStatus.noDriverFound &&
        ended != null &&
        ended.categoryId != null &&
        ended.paymentMethodId != null;
    if (!canRetry) {
      await showRideTerminalStateSheet(context, status: status);
      if (!mounted) return;
      RideNavigator.home(context, status: status);
      return;
    }
    // RIDE-19: the server found no driver. Offer the same request again, or
    // a different route from "Where to?".
    var choice = await showNoDriverFoundSheet(context);
    while (mounted && choice == NoDriverChoice.tryAgain) {
      final outcome = await _requestAgain(ended);
      if (outcome == _Rebook.started) return;
      if (!mounted) break;
      if (outcome == _Rebook.declined) {
        // rider-u107: "Not now" on the new price; the rider decides again.
        choice = await showNoDriverFoundSheet(context);
        continue;
      }
      if (outcome != _Rebook.uncertain) break;
      // rider-u108: the new ride may exist on the server. The rider stays
      // here and may send the same booking again (same key, so never a
      // second ride) rather than being sent Home with a live ride unseen.
      choice = await showNoDriverFoundSheet(
        context,
        message: context.l10n.bookingUncertain,
      );
    }
    if (!mounted) return;
    RideNavigator.home(context, status: status);
  }

  /// Requests the same route, category and payment again as a new booking
  /// (a new ride, so a new idempotency key; a retry after an uncertain
  /// answer reuses it).
  Future<_Rebook> _requestAgain(RideSnapshot ended) async {
    String rideId;
    final booking = widget.booking ?? BookingController();
    // rider-u107: price the route again first. A price other than the one
    // the rider last saw (a surge, or their raise from the last search) is
    // booked only once they accept it, as on Select Ride.
    var quote = _rebookQuote;
    if (quote == null) {
      setState(() => _rebooking = true);
      try {
        quote = await booking.freshQuote(
          rideType: ended.categoryId!,
          pickupAddress: ended.pickupAddress,
          destinationAddress: ended.destinationAddress,
          pickupLat: ended.pickupLat,
          pickupLng: ended.pickupLng,
          destinationLat: ended.destinationLat,
          destinationLng: ended.destinationLng,
          stops: ended.stops,
        );
      } catch (_) {
        _showCancelNotice(L10n.current.rebookFailed);
        return _Rebook.failed;
      } finally {
        if (mounted) setState(() => _rebooking = false);
      }
      if (!mounted) return _Rebook.failed;
      final next = Money(quote.totalMinor, quote.currency);
      if (next != ended.fare && !await _acceptNewPrice(ended.fare, next)) {
        return _Rebook.declined;
      }
      if (!mounted) return _Rebook.failed;
      _rebookQuote = quote;
    }
    setState(() => _rebooking = true);
    try {
      rideId = await booking.submitFinding(
        pickupAddress: ended.pickupAddress,
        destinationAddress: ended.destinationAddress,
        pickupLat: ended.pickupLat,
        pickupLng: ended.pickupLng,
        destinationLat: ended.destinationLat,
        destinationLng: ended.destinationLng,
        rideType: ended.categoryId!,
        price: Money(quote.totalMinor, quote.currency).major,
        quoteId: quote.id,
        quoteSignedPayload: quote.signedPayload,
        quoteExpiresAt: quote.expiresAt,
        quoteTotalMinor: quote.totalMinor,
        quoteCurrency: quote.currency,
        paymentMethod: ended.paymentMethodId!,
        rideTypeLabel: widget.rideType,
        paymentMethodLabel: widget.paymentMethod,
        notes: widget.notes,
        stops: ended.stops,
        // J10 (v0.18.84 debtModel.walletSwitch): on while the rider owes.
        useWalletFirst:
            widget.walletAmountMinor > 0 ||
            RiderOutstanding.current.value.inCurrency(quote.currency) != null,
        walletAmountMinor: widget.walletAmountMinor,
      );
    } catch (error) {
      // RC-09: a timeout or dropped connection may still have booked it.
      if (BookingController.mayHaveBooked(error)) return _Rebook.uncertain;
      _rebookQuote = null;
      // J10 (v0.18.84): 409 rider_debt_above_max says what is owed.
      _showCancelNotice(
        RiderDebtRefusal.messageOf(error) ?? L10n.current.rebookFailed,
      );
      return _Rebook.failed;
    } finally {
      if (mounted) setState(() => _rebooking = false);
    }
    _rebookQuote = null;
    if (rideId.trim().isEmpty) return _Rebook.failed;
    if (!mounted) {
      // The new ride exists on the server: it gets a screen now.
      await RideRestoreCoordinator.instance.recoverCreatedFinding(
        rideId,
        realtime: widget.realtime,
      );
      return _Rebook.started;
    }
    final booked = await _match.storedRide(rideId: rideId);
    if (!mounted) return _Rebook.failed;
    if (booked != null) _adoptRoute(booked);
    _leaving = false;
    _terminalPending = null;
    _matchedPending = false;
    _driverMatched.value = false;
    _nearbyPaintKey = 0;
    setState(() {});
    _startMatching(
      price: booked?.price ?? ended.price,
      searchStartedAt: booked?.searchStart,
      createdAt: booked?.createdAt,
    );
    _loadMapBits();
    return _Rebook.started;
  }

  /// rider-u107: the same "Price updated" question Select Ride asks.
  Future<bool> _acceptNewPrice(Money shown, Money next) =>
      showRebookPriceDialog(context, shown: shown, next: next);

  /// Takes over [ride]'s route on this screen (without telling the server,
  /// which already has it).
  void _adoptRoute(RideSnapshot ride) {
    _pickupAddress = ride.pickupAddress;
    _pickupPosition = LatLng(ride.pickupLat, ride.pickupLng);
    _destinationAddress = ride.destinationAddress;
    _destinationPosition = LatLng(ride.destinationLat, ride.destinationLng);
    _stops = List<RouteStop>.from(ride.stops);
    _roadRoutePoints = null;
    _loadMapBits();
    if (_mapReady) unawaited(_refreshRoadRoute());
  }

  /// G25 step B: take the trip map back from Waiting. A map that is gone
  /// (Waiting built a new one) is replaced by a new one here, whose
  /// onMapCreated attaches it.
  void _takeTripMapBack() {
    if (!_mapSeat.handedOn) return;
    final back = _mapSeat.reclaim();
    _mapController = back;
    _mapReady = back != null;
  }

  /// G25: the map kept under a covering screen is this screen's again.
  void _onKeptMapResumed() {
    final controller = _mapController;
    if (controller == null || _mapParked) return;
    AppScope.instance.maps.attach(controller, owner: MapOwners.finding);
    unawaited(_refreshRoadRoute());
  }

  Future<void> _openWaiting() async {
    if (!mounted || _leaving) return;
    _leaving = true;
    _editingPickup = false;

    // Freeze and detach this map before the next map-heavy ride stage. Keeping
    // Finding alive but parked prevents SelectRide/Home from resuming their maps
    // underneath the active ride.
    _match.dispose();
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.finding);
    // G25 step B: on a phone this map becomes Waiting's in Waiting's first
    // frame (no new map at "driver found"), so the push follows at once.
    final handedOn = _mapSeat.handOn();
    if (mounted) setState(() => _mapParked = true);
    if (!handedOn) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final researchDriver = await Navigator.push<bool>(
      context,
      RideStageTransition(
        WaitingForDriver(
          pickupAddress: _pickupAddress,
          destinationAddress: _destinationAddress,
          pickupPosition: _pickupPosition,
          destinationPosition: _destinationPosition,
          rideType: widget.rideType,
          price: _match.currentPrice,
          currency: _match.currency,
          paymentMethod: widget.paymentMethod,
          walletAmountMinor: widget.walletAmountMinor,
          notes: widget.notes,
          stops: _stops,
          driver: _match.matchedDriver,
          realtime: widget.realtime,
        ),
        settings: const RouteSettings(name: AppRoutes.waitingForDriver),
      ),
    );
    if (!mounted || researchDriver != true) return;
    await _resumeFindingAfterDriverCancel();
  }

  /// Cancel-first (CODE-3): Cancel request commits the cancel once the
  /// server confirms it — History archived, snapshot cleared — and only then
  /// offers the optional why-sheet, whose reason is sent as feedback. A
  /// reload while that sheet is open therefore lands on Home. Offline the
  /// request waits in the outbox and the search shows "Cancelling…" until
  /// the server answers (RC-03). If the server says a driver already accepted (RIDE-4), nothing is
  /// cancelled and the deferred match moves the rider on to Waiting.
  Future<void> _confirmCancel() async {
    if (_leaving || _cancelSheetOpen) return;
    if (_match.matchCount > 0) {
      _drainDeferredNavigation();
      return;
    }
    _cancelSheetOpen = true;
    Future<SearchCancelResult>? request;
    await showCancelSearchSheet(
      context,
      takingLonger: _match.isDelayed,
      driverMatched: _driverMatched,
      feeNote: _bookedCancelNote(),
      commit: () async {
        final result = await (request ??= _match.cancelSearch());
        return _isCommitted(result);
      },
    );
    // A system back can close the sheet while the request is still out;
    // the server's answer decides, not the sheet.
    SearchCancelResult? result;
    try {
      result = request == null ? null : await request;
    } catch (_) {
      // rider-u98: a failed request must not leave the sheet marked open,
      // which would hold every later navigation back.
      result = SearchCancelResult.unsent;
    }
    if (!mounted) {
      _cancelSheetOpen = false;
      return;
    }
    if (result != null && _isCommitted(result)) {
      await _finishCommittedCancel();
      return;
    }
    _cancelSheetOpen = false;
    if (result == SearchCancelResult.queued) {
      // RC-03: offline. Nothing is cancelled yet; the search shows
      // "Cancelling…" until the server confirms it or a driver accepted.
      setState(() {});
      _showCancelNotice(context.l10n.cancelOfflineQueued);
    } else if (result == SearchCancelResult.driverAccepted) {
      _showCancelNotice(context.l10n.driverAlreadyAccepted);
    } else if (result == SearchCancelResult.rejected) {
      _showCancelNotice(context.l10n.cancelNoLonger);
    } else if (result == SearchCancelResult.unsent) {
      _showCancelNotice(context.l10n.routeCouldNotReach);
    } else if (result == SearchCancelResult.stale) {
      // R-O2 (owner's words): the trip changed just before the tap.
      _showCancelNotice(rideJustChangedMessage);
    } else if (_matchedPending || _match.matchCount > 0) {
      _showCancelNotice(context.l10n.driverAccepted);
    }
    _drainDeferredNavigation();
  }

  /// v0.18.152 (contract.json#bookedRideSeen.searchSeen.riderApp): a booked
  /// ride being searched cancels by the booked rules — the server's
  /// preview line ("Cancelling now costs …" under 1 h before the pickup);
  /// without a preview no line at all, never "free". A live search: none.
  String? _bookedCancelNote() {
    if (!_match.booked) return null;
    final preview = _match.cancelPreview;
    if (preview == null) return null;
    return cancelPreviewNote(preview, FindingDrivers.cancelFeeClock()).text;
  }

  static bool _isCommitted(SearchCancelResult result) =>
      result == SearchCancelResult.confirmed;

  Future<void> _finishCommittedCancel() async {
    // The ride is over; nothing deferred may navigate from here on.
    _leaving = true;
    _terminalPending = null;
    _matchedPending = false;
    setState(() {});
    final feedback = await showCancelReasonSheet(
      context,
      phase: CancelPhase.searching,
      committed: true,
      publishedReasons: _zoneConfig?.cancelReasons.map((r) => r.code),
    );
    final reason = feedback.reasonId;
    if (reason != null) unawaited(_match.sendCancelReason(reason));
    if (!mounted) return;
    RideNavigator.home(context);
  }

  void _showCancelNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  /// Change the destination or the stops while searching: the new price is
  /// confirmed first, then the matching continues with the new route.
  Future<void> _changeRoute(
    BuildContext? sheetContext,
    RouteChangeEntry entry, {
    int? removeStop,
  }) async {
    if (_pickupEditOpen || _leaving) return;
    final ride = _match.ownershipSnapshot;
    if (ride == null) return;
    AppScope.instance.maps.detach(owner: MapOwners.finding);
    if (!mounted) return;
    setState(() {
      _mapParked = true;
      _pickupEditOpen = true;
    });
    if (sheetContext != null) {
      await popCurrentRouteAndWaitForExit(sheetContext);
      if (!mounted) return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final updated = removeStop != null
        ? await removeRouteStop(context, ride: ride, index: removeStop)
        : await openRouteChange(
            context,
            ride: ride,
            entry: entry,
            pickupLocked: _match.matchCount > 0,
            driverAccepted: _match.matchCount > 0,
          );
    if (!mounted) return;
    _applyRouteChange(updated);
    setState(() {
      _mapParked = false;
      _pickupEditOpen = false;
    });
    if (updated != null) {
      showRouteUpdated(
        context,
        driverAssigned: _match.matchCount > 0,
        paymentMethod: widget.paymentMethod,
        // rider-u36: the server's difference, as the sheet showed it.
        differenceKr: lastRouteDifferenceKr ?? updated.price - ride.price,
        currency: updated.currency,
        newPrice: updated.price,
      );
    }
    if (_match.matchCount == 1) _matchedPending = true;
    _drainDeferredNavigation();
  }

  void _applyRouteChange(RideSnapshot? updated) {
    if (updated == null) return;
    _match.adoptRouteChange(updated);
    _pickupAddress = updated.pickupAddress;
    _pickupPosition = LatLng(updated.pickupLat, updated.pickupLng);
    _destinationAddress = updated.destinationAddress;
    _destinationPosition = LatLng(
      updated.destinationLat,
      updated.destinationLng,
    );
    _stops = List<RouteStop>.from(updated.stops);
    _roadRoutePoints = null;
    _loadMapBits();
    if (_mapReady) unawaited(_refreshRoadRoute());
  }

  Future<void> _raiseOffer(Future<bool> raise) async {
    final updated = await raise;
    if (!mounted) return;
    setState(() {});
    _showEditFeedback(
      success: updated,
      fallback: updated
          ? context.l10n.offerUpdated
          : context.l10n.editOfferFailed,
    );
  }

  void _showEditFeedback({required bool success, required String fallback}) {
    if (!mounted) return;
    final message = _match.editFeedback ?? fallback;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// The three dots on the ride card: the route screen with the current
  /// addresses, where the rider adjusts the pickup, the destination or
  /// the stops.
  /// v0.18.143 (approved mockup screen 2): the ride card's three dots open
  /// Ride details with the price; the pencils and "+" open the route
  /// screen. The pickup pencil shows only while no driver has accepted.
  Future<void> _openDetails() async {
    if (_pickupEditOpen || _leaving) return;
    final searching = _match.matchCount == 0;
    await MoveraSheet.show<void>(
      context: context,
      builder: (sheet) => RideDetailsSheet(
        pickupAddress: _pickupAddress,
        destinationAddress: _destinationAddress,
        stops: _stops,
        rideType: widget.rideType,
        price: _match.currentPrice > 0 ? _match.currentPrice : widget.price,
        currency: _match.currency,
        paymentMethod: widget.paymentMethod,
        notes: widget.notes,
        onCancelTrip: () {
          Navigator.pop(sheet);
          unawaited(_confirmCancel());
        },
        onEditPickup: searching
            ? () => _changeRoute(sheet, RouteChangeEntry.pickup)
            : null,
        onEditDestination: () =>
            _changeRoute(sheet, RouteChangeEntry.destination),
        onAddStop: () => _changeRoute(sheet, RouteChangeEntry.newStop),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    if (_configSource case final Listenable source) {
      source.removeListener(_onConfigChanged);
    }
    _match.onRaiseLimitRefused = null;
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _sheetController.removeListener(_syncSheetOverlay);
    _sheetController.dispose();
    _driverMatched.dispose();
    _mapSeat.dispose();
    // Widget teardown is not a rider business action. Navigation, hot
    // reload, restoration, or parent replacement may dispose this surface
    // while the ride is still active; cancellation must happen only through
    // the explicit cancel flow.
    _match.dispose();
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.finding);
    super.dispose();
  }

  void _syncSheetOverlay() {
    if (!_sheetController.hasClient) return;
    final media = MediaQuery.maybeOf(context);
    if (media == null) return;
    final offset = _sheetController.metrics?.offset;
    final expanded = offset != null && offset > _minSheet(media) + 12;
    if (expanded != _sheetExpanded) _setSheetExpanded(expanded);
    final cover = expanded || _match.showPriceBump;
    if (cover == _overlayOn) return;
    _overlayOn = cover;
    setWebOverlayOpen(cover);
  }

  /// N4: the raise card is taller than the sheet's resting height (on a
  /// 390 × 844 screen "Set new price" and "Keep waiting" sat below the
  /// screen edge); when it appears the sheet opens to its top once, so the
  /// whole card is in reach. The rider can still pull the sheet down.
  bool _sheetOpenedForBump = false;

  void _openSheetForPriceBump() {
    final show = _match.showPriceBumpCard;
    if (!show) {
      _sheetOpenedForBump = false;
      return;
    }
    if (_sheetOpenedForBump) return;
    _sheetOpenedForBump = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetController.hasClient) return;
      final media = MediaQuery.maybeOf(context);
      if (media == null) return;
      _sheetController.animateTo(
        SheetOffset.absolute(_maxSheet(media)),
        duration: MoveraDurations.large,
        curve: MoveraCurves.open,
      );
    });
  }

  void _setSheetExpanded(bool expanded) {
    // Sheet metrics can change mid-layout; never rebuild during a frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheetExpanded != expanded) {
          setState(() => _sheetExpanded = expanded);
        }
      });
      return;
    }
    if (mounted) setState(() => _sheetExpanded = expanded);
  }

  String _shortPlace(String value) => shortenPlace(value);

  /// rider-u110: the sheet never rises over the top bar (Cancel and Safety
  /// Kit sit at padding.top + 8, 48 px tall) or past the screen top; on a
  /// short viewport the panel body scrolls instead.
  double _sheetCeiling(MediaQueryData media) =>
      media.size.height - media.padding.top - 64;

  double _minSheet(MediaQueryData media) {
    final base = _match.showPriceBump ? 520.0 : 332.0;
    return math.min(base + media.padding.bottom, _sheetCeiling(media));
  }

  double _maxSheet(MediaQueryData media) {
    final minH = _minSheet(media);
    final maxH = media.size.height - media.padding.top - 72;
    final wanted = maxH < minH + 48 ? minH + 48 : maxH;
    return math.max(minH, math.min(wanted, _sheetCeiling(media)));
  }

  Future<void> _answerStep({required bool wait}) async {
    setState(() {});
    final ok = await _match.answerKeepWaiting(wait: wait);
    if (!mounted) return;
    setState(() {});
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.searchStepAnswerFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final copy = _match.copy;
    final progress = (_match.elapsedSeconds / 90).clamp(0.08, 0.86);
    const mapReserve = 300.0;
    return PopScope(
      canPop: _leaving && !_rebooking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F5F1),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: mapReserve,
              child: RepaintBoundary(
                // G25 step A: on native the parked map stays mounted.
                child: ParkableMap(
                  parked: _mapParked,
                  placeholder: const ColoredBox(color: Color(0xFFF6F5F1)),
                  onResumed: _onKeptMapResumed,
                  // G25 step B: the one trip map (Waiting takes it over).
                  child: RideStageMapSlot(
                    seat: _mapSeat,
                    placeholder: const ColoredBox(color: Color(0xFFF6F5F1)),
                    onAdopted: (controller) {
                      _mapReady = true;
                      _mapController = controller;
                      if (_mapParked) return;
                      _onKeptMapResumed();
                    },
                    builder: (context, sharedKey) => CustomGoogleMap(
                      key: sharedKey ?? const ValueKey('finding-map'),
                      // Owner, live test 2026-10-26 (N6): the booking and trip maps stay
                      // flat; the route is read from above, never along a tilted horizon.
                      tiltWithZoom: false,
                      initialPosition: CameraPosition(
                        target: _pickupPosition,
                        zoom: 14.0,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      circles: _editCircles,
                      polygons: _editPolygons,
                      onCameraMove: _onEditCameraMove,
                      onCameraIdle: () => unawaited(_onEditCameraIdle()),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      buildingsEnabled: false,
                      indoorViewEnabled: false,
                      tiltGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      mapType: MapType.normal,
                      onMapCreated: (controller) {
                        _mapReady = true;
                        _mapController = controller;
                        _mapSeat.noteCreated(controller);
                        AppScope.instance.maps.attach(
                          controller,
                          owner: MapOwners.finding,
                        );
                        unawaited(_refreshRoadRoute());
                      },
                    ),
                  ),
                ),
              ),
            ),
            // Owner N2/A14: a leg without road (direct line): say so.
            if (!_mapParked &&
                !_editingPickup &&
                _roadRoutePoints != null &&
                _roadApproximate)
              Positioned(
                left: 12,
                bottom: mapReserve + 24,
                child: const ApproximateRouteBadge(),
              ),
            if (_editingPickup) ..._editLayers(media, mapReserve),
            if (!_editingPickup)
              Positioned(
                top: media.padding.top + 8,
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  child: Row(
                    children: [
                      // AUD-3: cancelling has its own labelled control; the
                      // chevron only ever collapses the sheet.
                      MoveraIconButton.round(
                        icon: Icons.close_rounded,
                        onPressed: _confirmCancel,
                        label: context.l10n.cancelRequest,
                      ),
                      if (_sheetExpanded) ...[
                        const SizedBox(width: 8),
                        MoveraIconButton.round(
                          icon: Icons.keyboard_arrow_down_rounded,
                          onPressed: () {
                            if (!_sheetController.hasClient) return;
                            _sheetController.animateTo(
                              SheetOffset.absolute(_minSheet(media)),
                              duration: MoveraDurations.large,
                              curve: MoveraCurves.close,
                            );
                          },
                          label: context.l10n.collapse,
                        ),
                      ],
                      // UI-10: the Safety Kit button gets the rest of the row
                      // (right-aligned) and never pushes past the screen edge.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SafetyKitMapButton(
                            rideId: _match.ride.rideId,
                            // G14: no driver yet, no trip: Call 112 only.
                            driverAssigned: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // The banner follows the trip's live connection; once the
            // search is over (a committed cancel on its way Home) the
            // transport lets go of the trip, which is not a lost
            // connection to tell the rider about.
            if (!_leaving)
              Positioned(
                top: media.padding.top + 62,
                left: 12,
                right: 12,
                child: PointerInterceptor(
                  child: RealtimeConnectionBanner(
                    connection: AppScope.instance.realtime,
                    // proof5: the cancel commits under the sheet, before
                    // _leaving; the transport's release is no lost link.
                    hidden: () => _leaving || _match.cancelled,
                  ),
                ),
              ),
            if (!_editingPickup)
              Positioned(
                right: 12,
                bottom: mapReserve + 16,
                child: PointerInterceptor(
                  child: MoveraIconButton.round(
                    icon: Icons.my_location_rounded,
                    onPressed: () {
                      AppScope.instance.camera.focusOnPickup(
                        GeoPoint(
                          _pickupPosition.latitude,
                          _pickupPosition.longitude,
                        ),
                      );
                    },
                    label: context.l10n.recenterMap,
                  ),
                ),
              ),
            if (!_editingPickup)
              SheetViewport(
                child: Sheet(
                  controller: _sheetController,
                  initialOffset: SheetOffset.absolute(_minSheet(media)),
                  physics: MoveraSheetMotion.physics,
                  snapGrid: SheetSnapGrid(
                    snaps: [
                      SheetOffset.absolute(_minSheet(media)),
                      SheetOffset.absolute(_maxSheet(media)),
                    ],
                    minFlingSpeed: 520,
                  ),
                  // N4: a drag on the sheet body moves the sheet (and scrolls
                  // the body once the sheet is up). Disabled, the body's scroll
                  // view swallowed every swipe and only the 22 px handle could
                  // open the sheet, so the raise card's Confirm stayed off
                  // screen.
                  scrollConfiguration: const SheetScrollConfiguration(),
                  child: PointerInterceptor(
                    child: SizedBox(
                      height: _maxSheet(media),
                      width: double.infinity,
                      // Owner 2026-11-23: full width, 28 px top, a soft
                      // upward shadow.
                      child: DecoratedBox(
                        key: const ValueKey('finding-sheet-card'),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x1F162C36),
                              blurRadius: 24,
                              offset: Offset(0, -6),
                            ),
                          ],
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              const SizedBox(
                                width: double.infinity,
                                height: 22,
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
                              if (!_match.showPriceBump)
                                // Owner 2026-11-23: the approved radar in the
                                // car picture's place (same 96 px).
                                const SearchingRadar(),
                              Expanded(
                                child: _panelBody(
                                  progress,
                                  copy.headline,
                                  copy.subtitle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_rebooking)
              const Positioned.fill(
                child: ColoredBox(
                  key: ValueKey('finding-rebooking'),
                  color: Color(0x33FFFFFF),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF2D5878)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The pickup zone's config (Q6 raise steps, v0.18.6 raise limit), once
  /// read.
  RiderAppConfig? _zoneConfig;

  /// The config repository listened to for new versions.
  RiderConfigRepository? _configSource;

  Future<void> _loadZoneConfig() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: _currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      if (!mounted || config == null) return;
      // v0.18.6 (G4-E4): the zone's raise limit (raisePrice.maxFactor).
      _match.raiseMaxFactor = config.raiseMaxFactor;
      setState(() => _zoneConfig = config);
    } catch (_) {
      // The seed's steps and the default limit stay.
    }
  }

  void _onConfigChanged() {
    if (!mounted) return;
    unawaited(_loadZoneConfig());
  }

  /// v0.18.6 (G4-E4): the server refused a raise as above the limit (the
  /// admin lowered it): the zone's document is asked for again.
  void _onRaiseLimitRefused() {
    final source = _configSource;
    if (source is ApiRiderConfigRepository) {
      final zoneId = _zoneConfig?.zoneId;
      if (zoneId != null && zoneId.isNotEmpty) {
        unawaited(source.refresh(zoneId).then((_) => _onConfigChanged()));
        return;
      }
    }
    _onConfigChanged();
  }

  /// The enabled raise steps of the trip's zone in [currency], whole units;
  /// the built-in seed's until the zone's config is read.
  List<int> _raiseSteps(String currency) =>
      PriceBumpCard.stepsFor(_zoneConfig, currency);
}
