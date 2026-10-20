import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
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
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/finding_driver/presentation/still_looking_card.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart'
    show RideSnapshot;
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
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

class FindingDrivers extends StatefulWidget {
  const FindingDrivers({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupPosition,
    required this.destinationPosition,
    required this.rideType,
    required this.price,
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
  final double price;
  final String paymentMethod;
  final RideNotes notes;
  final RideRealtime? realtime;

  /// Test seam (for example a controller on a fake API); production builds
  /// its own from [realtime].
  final FindingDriverController? controller;

  @override
  State<FindingDrivers> createState() => _FindingDriversState();
}

class _FindingDriversState extends State<FindingDrivers> {
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  late final FindingDriverController _match =
      widget.controller ?? FindingDriverController(realtime: widget.realtime);
  bool _mapParked = false;
  bool _mapReady = false;
  bool _leaving = false;
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
    // R-O2: a queued cancel the launch flush refused or dropped before this
    // screen existed (a cold restore) is told now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = (_match.ownedRideId ?? AppScope.instance.ride.rideId)?.trim();
      if (!mounted || id == null || id.isEmpty) return;
      final stale = ActiveRideController.takeQueuedCancelNotice(id);
      if (stale == true) {
        _showCancelNotice(rideJustChangedMessage);
      } else if (stale == false) {
        _showCancelNotice(
          'A driver already accepted your ride, so it wasn’t cancelled.',
        );
      }
    });
  }

  void _startMatching({
    double? price,
    DateTime? searchStartedAt,
    DateTime? createdAt,
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
      paymentMethod: widget.paymentMethod,
      walletAmountMinor: widget.walletAmountMinor,
      notes: widget.notes,
      stops: _stops,
      searchStartedAt: searchStartedAt,
      createdAt: createdAt,
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
              : 'A driver already accepted your ride, so it wasn’t cancelled.',
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
    _leaving = false;
    _cancelSheetOpen = false;
    _driverMatched.value = false;
    _pickupEditOpen = false;
    _overlayOn = false;
    _nearbyPaintKey = 0;
    setWebOverlayOpen(false);
    setState(() => _mapParked = false);
    // A new dispatch round: its own "still looking" mark.
    _startMatching(price: effectivePrice, searchStartedAt: DateTime.now());
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
    final canRetry = status == RideStatus.noDriverFound &&
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
    final choice = await showNoDriverFoundSheet(context);
    if (!mounted) return;
    if (choice == NoDriverChoice.tryAgain && await _requestAgain(ended)) {
      return;
    }
    if (!mounted) return;
    RideNavigator.home(context, status: status);
  }

  /// Requests the same route, category and payment again as a new booking
  /// (a new ride, so a new idempotency key). True when the new search runs.
  Future<bool> _requestAgain(RideSnapshot ended) async {
    String rideId;
    try {
      rideId = await (widget.booking ?? BookingController()).submitFinding(
        pickupAddress: ended.pickupAddress,
        destinationAddress: ended.destinationAddress,
        pickupLat: ended.pickupLat,
        pickupLng: ended.pickupLng,
        destinationLat: ended.destinationLat,
        destinationLng: ended.destinationLng,
        rideType: ended.categoryId!,
        price: ended.price,
        paymentMethod: ended.paymentMethodId!,
        rideTypeLabel: widget.rideType,
        paymentMethodLabel: widget.paymentMethod,
        notes: widget.notes,
        stops: ended.stops,
        useWalletFirst: widget.walletAmountMinor > 0,
        walletAmountMinor: widget.walletAmountMinor,
      );
    } catch (_) {
      _showCancelNotice(
        'We couldn’t request a new ride. Choose your route and try again.',
      );
      return false;
    }
    if (!mounted || rideId.trim().isEmpty) return false;
    final booked = await _match.storedRide(rideId: rideId);
    if (!mounted) return false;
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
    return true;
  }

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
      for (final vehicle in _match.nearby)
        Marker(
          markerId: MarkerId('nearby-${vehicle.id}'),
          position: LatLng(vehicle.latitude, vehicle.longitude),
          rotation: vehicle.bearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon:
              _driverCar ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        ),
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
      GeoPoint(
        _destinationPosition.latitude,
        _destinationPosition.longitude,
      ),
    );
    final icons = await Future.wait<BitmapDescriptor>([
      // While searching the pins carry the estimate; the live driver ETA
      // takes over once a driver is found.
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: true)
          : RouteTimeMarker.createIcon(pickup: true, label: '$eta\nmin'),
      MoveraVehicleMarker.createIcon(),
      eta == null
          ? RouteEndpointMarker.createIcon(pickup: false)
          : RouteTimeMarker.createIcon(
              pickup: false,
              label:
                  'Arrive by ${clockTime(DateTime.now().add(Duration(minutes: eta + tripMinutes)))}',
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
    final route = await roadRoutePolyline(
      id: 'route',
      from: _pickupPosition,
      to: _destinationPosition,
      color: RiderRouteStyle.color,
    );
    if (!mounted || route.points.length < 2) return;
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
    final result = request == null ? null : await request;
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
      _showCancelNotice(
        'We couldn’t reach Movera. We’ll cancel your ride as soon as '
        'you’re back online.',
      );
    } else if (result == SearchCancelResult.driverAccepted) {
      _showCancelNotice(
        'A driver already accepted your ride, so it wasn’t cancelled.',
      );
    } else if (result == SearchCancelResult.rejected) {
      _showCancelNotice('This ride can no longer be cancelled.');
    } else if (result == SearchCancelResult.stale) {
      // R-O2 (owner's words): the trip changed just before the tap.
      _showCancelNotice(rideJustChangedMessage);
    } else if (_matchedPending || _match.matchCount > 0) {
      _showCancelNotice('A driver accepted your ride.');
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
        differenceKr: updated.price - ride.price,
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
    _destinationPosition = LatLng(updated.destinationLat, updated.destinationLng);
    _stops = List<RouteStop>.from(updated.stops);
    _roadRoutePoints = null;
    _loadMapBits();
    if (_mapReady) unawaited(_refreshRoadRoute());
  }

  void _showEditFeedback({
    required bool success,
    required String fallback,
  }) {
    if (!mounted) return;
    final message = _match.editFeedback ?? fallback;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// The three dots on the ride card: the route screen with the current
  /// addresses, where the rider adjusts the pickup, the destination or
  /// the stops.
  Future<void> _openDetails() => _changeRoute(null, RouteChangeEntry.destination);


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

  double _minSheet(MediaQueryData media) {
    final base = _match.showPriceBump ? 520.0 : 332.0;
    return base + media.padding.bottom;
  }

  double _maxSheet(MediaQueryData media) {
    final minH = _minSheet(media);
    final maxH = media.size.height - media.padding.top - 72;
    return maxH < minH + 48 ? minH + 48 : maxH;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final copy = _match.copy;
    final progress = (_match.elapsedSeconds / 90).clamp(0.08, 0.86);
    const mapReserve = 300.0;
    return PopScope(
      canPop: _leaving,
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
                        // Green free-flow traffic hides the Waze road palette;
                        // traffic stays on the active-trip map only.
                        trafficEnabled: false,
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
                      label: 'Cancel request',
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
                        label: 'Collapse',
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
                  label: 'Recenter map',
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
                scrollConfiguration: SheetScrollConfiguration.disabled,
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
                              padding: const EdgeInsets.only(
                                top: 2,
                                bottom: 6,
                              ),
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
          ],
        ),
      ),
    );
  }

  Widget _panelBody(double progress, String headline, String subtitle) {
    return SingleChildScrollView(
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
              busy: _match.editInFlight,
              steps: const [50, 100, 150, 200],
              onConfirm: (kr) async {
                final updated = await _match.confirmPriceIncrease(kr);
                if (!mounted) return;
                setState(() {});
                _showEditFeedback(
                  success: updated,
                  fallback: updated
                      ? 'Offer updated'
                      : 'Couldn’t update offer. Try again.',
                );
              },
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
                        'Meet at ${_shortPlace(_pickupAddress)}',
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
                          paymentMethod: widget.paymentMethod,
                          priceKr: _match.currentPrice,
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
                  tooltip: 'Ride details',
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
