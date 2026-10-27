import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/domain/nearby_vehicle.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/finding_driver/presentation/still_looking_card.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart'
    show RideSnapshot;
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/realtime_connection_banner.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/approximate_route_badge.dart';

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
  });

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

class _FindingDriversState extends State<FindingDrivers> {
  /// The trip's currency: the one the search holds once it started (a
  /// restored or re-requested trip keeps its own), else the widget's.
  String get _currency => _match.ownershipSnapshot?.currency ?? widget.currency;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  late final FindingDriverController _match =
      widget.controller ?? FindingDriverController(realtime: widget.realtime);
  bool _mapParked = false;
  bool _mapReady = false;
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

  late String _pickupAddress;
  late LatLng _pickupPosition;
  late String _destinationAddress;
  late LatLng _destinationPosition;
  late List<RouteStop> _stops;

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
    _startMatching(
      price: widget.price,
      searchStartedAt: widget.searchStartedAt,
      createdAt: widget.createdAt,
    );
    unawaited(_loadZoneConfig());
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
    _leaving = false;
    _cancelSheetOpen = false;
    _driverMatched.value = false;
    _pickupEditOpen = false;
    _overlayOn = false;
    _nearbyPaintKey = 0;
    setWebOverlayOpen(false);
    setState(() => _mapParked = false);
    // A new dispatch round: its own "still looking" mark.
    _startMatching(
      price: effectivePrice,
      searchStartedAt: DateTime.now(),
      maxOfferMinor: maxOfferMinor,
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
        useWalletFirst: widget.walletAmountMinor > 0,
        walletAmountMinor: widget.walletAmountMinor,
      );
    } catch (error) {
      // RC-09: a timeout or dropped connection may still have booked it.
      if (BookingController.mayHaveBooked(error)) return _Rebook.uncertain;
      _rebookQuote = null;
      _showCancelNotice(L10n.current.rebookFailed);
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

  /// rider-u61: on the web the car bitmap comes turned (the plugin ignores
  /// rotation there).
  Marker _nearbyMarker(NearbyVehicle vehicle) {
    final look = MoveraVehicleMarker.look(
      _driverCar,
      vehicle.bearing,
      onReady: () {
        if (mounted) setState(_loadMapBits);
      },
    );
    return Marker(
      markerId: MarkerId('nearby-${vehicle.id}'),
      position: LatLng(vehicle.latitude, vehicle.longitude),
      rotation: look.rotation,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon:
          look.icon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
    );
  }

  void _loadMapBits() {
    final routePoints = _roadRoutePoints;
    _markers = {
      if (_riderPuck != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupPosition,
          infoWindow: InfoWindow(title: _pickupAddress),
          icon: _riderPuck!,
          anchor: _pinAnchor,
        ),
      ...routeStopMarkers(_stops),
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationPosition,
        infoWindow: InfoWindow(title: _destinationAddress),
        icon:
            _destinationPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: _pinAnchor,
      ),
      for (final vehicle in _match.nearby) _nearbyMarker(vehicle),
    };
    _polylines = styledRoute(
      routePoints != null && routePoints.length >= 2
          ? routePolyline(
              id: 'route',
              from: routePoints.first,
              to: routePoints.last,
              color: RiderRouteStyle.color,
              routing: _ResolvedRoute(routePoints),
            )
          : _stops.isNotEmpty
          ? routePolyline(
              id: 'route',
              from: _pickupPosition,
              to: _destinationPosition,
              color: RiderRouteStyle.color,
              routing: _ResolvedRoute(
                routeWithStops(
                  pickup: _pickupPosition,
                  stops: _stops,
                  destination: _destinationPosition,
                ),
              ),
            )
          : routePolyline(
              id: 'route',
              from: _pickupPosition,
              to: _destinationPosition,
              color: RiderRouteStyle.color,
            ),
    );
  }

  Future<void> _prepareMapVisuals() async {
    final eta = widget.etaMinutes;
    final tripMinutes = estimatedTripMinutes(
      GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      GeoPoint(_destinationPosition.latitude, _destinationPosition.longitude),
    );
    final icons = await Future.wait<BitmapDescriptor>([
      // While searching the pins carry the estimate; the live driver ETA
      // takes over once a driver is found.
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: true)
          : RouteTimeMarker.createIcon(
              pickup: true,
              label: context.l10n.minLineBreak('$eta'),
            ),
      MoveraVehicleMarker.createIcon(),
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: false)
          : RouteTimeMarker.createIcon(
              pickup: false,
              label: context.l10n.arriveBy(
                clockTime(
                  DateTime.now().add(Duration(minutes: eta + tripMinutes)),
                ),
              ),
            ),
    ]);
    if (!mounted) return;
    _riderPuck = icons[0];
    _destinationPin = icons[2];
    _driverCar = icons[1];
    _pinAnchor = eta == null ? const Offset(0.5, 0.5) : RouteTimeMarker.anchor;
    _loadMapBits();
    setState(() {});
  }

  Future<void> _refreshRoadRoute() async {
    // With stops the straight pickup → stops → destination line is drawn.
    if (_stops.isNotEmpty) return;
    final from = _pickupPosition;
    final to = _destinationPosition;
    final route = await roadRoutePolyline(
      id: 'route',
      from: from,
      to: to,
      color: RiderRouteStyle.color,
    );
    if (!mounted || route.points.length < 2) return;
    // rider-35: the route changed while this answer was on its way; the
    // newer request draws the line.
    if (from != _pickupPosition ||
        to != _destinationPosition ||
        _stops.isNotEmpty) {
      return;
    }
    _roadRoutePoints = route.points;
    _loadMapBits();
    setState(() {});
  }

  Future<void> _openWaiting() async {
    if (!mounted || _leaving) return;
    _leaving = true;

    // Freeze and detach this map before the next map-heavy ride stage. Keeping
    // Finding alive but parked prevents SelectRide/Home from resuming their maps
    // underneath the active ride.
    _match.dispose();
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.finding);
    if (mounted) setState(() => _mapParked = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

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
  Future<void> _openDetails() =>
      _changeRoute(null, RouteChangeEntry.destination);

  @override
  void dispose() {
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _sheetController.removeListener(_syncSheetOverlay);
    _sheetController.dispose();
    _driverMatched.dispose();
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
    final show = _match.showPriceBump && !_match.showStillLooking;
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
                child: _mapParked
                    ? const ColoredBox(color: Color(0xFFF6F5F1))
                    : CustomGoogleMap(
                        key: const ValueKey('finding-map'),
                        // Owner, live test 2026-10-26 (N6): the booking and trip maps stay
                        // flat; the route is read from above, never along a tilted horizon.
                        tiltWithZoom: false,
                        initialPosition: CameraPosition(
                          target: _pickupPosition,
                          zoom: 14.0,
                        ),
                        markers: _markers,
                        polylines: _polylines,
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
                          AppScope.instance.maps.attach(
                            controller,
                            owner: MapOwners.finding,
                          );
                          unawaited(_refreshRoadRoute());
                        },
                      ),
              ),
            ),
            // Owner N2: no road route, only the direct line: say so.
            if (!_mapParked &&
                ApproximateRouteBadge.isStraight(_roadRoutePoints))
              Positioned(
                left: 12,
                bottom: mapReserve + 24,
                child: const ApproximateRouteBadge(),
              ),
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
                        child: SafetyKitMapButton(rideId: _match.ride.rideId),
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
                  ),
                ),
              ),
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
                    child: Material(
                      color: Colors.white,
                      elevation: 18,
                      shadowColor: const Color(
                        0xFF162C36,
                      ).withValues(alpha: 0.14),
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
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 6),
                              child: Image.asset(
                                excludeFromSemantics: true,
                                AppAssets.scheduleRideCar,
                                height: 88,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
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

  /// The pickup zone's config (Q6 raise steps), once read.
  RiderAppConfig? _zoneConfig;

  Future<void> _loadZoneConfig() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: _currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      if (!mounted || config == null) return;
      setState(() => _zoneConfig = config);
    } catch (_) {
      // The seed's steps stay.
    }
  }

  /// The enabled raise steps of the trip's zone in [currency], whole units;
  /// the built-in seed's until the zone's config is read.
  List<int> _raiseSteps(String currency) =>
      PriceBumpCard.stepsFor(_zoneConfig, currency);

  Widget _panelBody(double progress, String headline, String subtitle) {
    return SingleChildScrollView(
      // N4: the sheet's own scroll controller, so the drag is shared.
      primary: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1D252C),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF5C656C),
            ),
          ),
          if (_match.offerConfirmation != null) ...[
            const SizedBox(height: 10),
            Text(
              _match.offerConfirmation!,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2D5878),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFEAF2F8),
              color: const Color(0xFF2D5878),
            ),
          ),
          if (_match.showStillLooking) ...[
            const SizedBox(height: 16),
            StillLookingCard(
              onKeepSearching: () {
                _match.keepSearching();
                setState(() {});
              },
              onCancel: _confirmCancel,
            ),
          ],
          if (_match.showPriceBump && !_match.showStillLooking) ...[
            const SizedBox(height: 16),
            PriceBumpCard(
              currentPrice: _match.currentPrice,
              maxPrice: _match.maxOfferPrice,
              currency: _match.currency,
              busy: _match.editInFlight,
              // Q6: the zone's raise steps, in the trip's currency.
              steps: _raiseSteps(_match.currency),
              onConfirm: (kr) => _raiseOffer(_match.confirmPriceIncrease(kr)),
              onConfirmIncrease: (increase) =>
                  _raiseOffer(_match.confirmPriceIncreaseBy(increase)),
              onKeepWaiting: () {
                _match.dismissPriceBump();
                setState(() {});
              },
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7EBEE)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.rideType,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF5C656C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.meetAt(_shortPlace(_pickupAddress)),
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1D252C),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bookedPaymentLine(
                          // rider-u231: the method in the app language.
                          paymentMethod: paymentLabelFor(widget.paymentMethod),
                          priceKr: _match.currentPrice,
                          currency: _match.currency,
                          walletMinor: widget.walletAmountMinor,
                          separator: '  ·  ',
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2D5878),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openDetails,
                  icon: const Icon(Icons.more_horiz_rounded),
                  tooltip: context.l10n.rideDetails,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SafetyKitSheetRow(rideId: _match.ride.rideId),
        ],
      ),
    );
  }
}

class _ResolvedRoute implements RoutingService {
  const _ResolvedRoute(this.points);

  final List<LatLng> points;

  @override
  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) => [
    for (final point in points) GeoPoint(point.latitude, point.longitude),
  ];
}

/// A booking asked again is priced again: a price other than the one the
/// rider last saw (a surge, their own raise) is booked only once they accept
/// it (rider-u107). Used after "No driver found" and by "Search again".
Future<bool> showRebookPriceDialog(
  BuildContext context, {
  required Money shown,
  required Money next,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('rebook-price-updated'),
      title: Text(context.l10n.priceUpdated),
      content: Text(
        context.l10n.priceUpdatedBody(formatMoney(next), formatMoney(shown)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.l10n.notNow),
        ),
        FilledButton(
          key: const ValueKey('rebook-price-accept'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.l10n.bookForPrice(formatMoney(next))),
        ),
      ],
    ),
  );
  return accepted == true;
}
