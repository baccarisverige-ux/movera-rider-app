import 'package:movera_rider/features/payments/presentation/card_brand_label.dart';

import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart'
    show routeStopMarkers;
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/maps/straight_line.dart';
import 'package:movera_rider/core/performance/route_transition_metrics.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/payments/domain/saved_card.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/application/scheduled_ride_checkout.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/ride_selection/application/nearby_cars_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_picture.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_fit_scheduler.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/ride_selection/presentation/widgets/select_ride_route_canvas.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/features/ride_selection/presentation/not_here_view.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/approximate_route_badge.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';

export 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

part 'select_ride_options.dart';
part 'select_ride_quotes.dart';
part 'select_ride_reveal.dart';
part 'select_ride_sheet_control.dart';
part 'select_ride_tiles.dart';

class SelectRide extends StatefulWidget {
  const SelectRide({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupPosition,
    required this.destinationPosition,
    this.stops = const <String>[],
    this.stopPoints = const <GeoPoint?>[],
    this.bookingMode = BookingMode.now,
    this.lockBookingMode = false,
    this.initialScheduledFor,
    this.initialRideId,
    this.initialPaymentMethod,
    this.parentReservationId,
    this.editingReservationId,
    this.note,
    this.reservations,
    this.onScheduled,
    this.selection,
    this.booking,
    this.realtime,
    this.pickupAlreadyConfirmed = false,
    this.pickupIsFallback = false,
    this.geocoding,
    this.nearbyCars,
    this.activeTrips,
  });

  /// Whether [origin] has the exact points a return ride needs (CODE-5).
  static bool canPlanReturn(Reservation origin) =>
      origin.pickup.lat != null &&
      origin.pickup.lng != null &&
      origin.destination.lat != null &&
      origin.destination.lng != null;

  /// Return-ride entry: same category cards, scheduled mode, reverse route.
  /// Needs both points of [origin] ([canPlanReturn]); CODE-5: it used to
  /// invent nearby points (or the Stockholm centre) when they were missing.
  factory SelectRide.forReturnRide(
    Reservation origin, {
    Key? key,
    ReservationController? reservations,
    Future<void> Function(BuildContext context, String reservationId)?
    onScheduled,
  }) {
    if (!canPlanReturn(origin)) {
      throw ArgumentError.value(
        origin.reservationId,
        'origin',
        L10n.current.selectReturnNeedsPoints,
      );
    }
    final returnPickup = LatLng(
      origin.destination.lat!,
      origin.destination.lng!,
    );
    final returnDest = LatLng(origin.pickup.lat!, origin.pickup.lng!);
    return SelectRide(
      key: key,
      pickupAddress: origin.destination.label,
      destinationAddress: origin.pickup.label,
      pickupPosition: returnPickup,
      destinationPosition: returnDest,
      bookingMode: BookingMode.scheduled,
      lockBookingMode: true,
      initialScheduledFor: origin.pickupWallTime.add(const Duration(hours: 3)),
      initialRideId: origin.categoryId,
      initialPaymentMethod: origin.paymentMethod,
      parentReservationId: origin.reservationId,
      note: origin.note,
      reservations: reservations,
      onScheduled: onScheduled,
    );
  }

  final String pickupAddress;
  final String destinationAddress;
  final LatLng pickupPosition;
  final LatLng destinationPosition;
  final List<String> stops;

  /// rider-r5-36: the point of each of [stops] the rider picked (a
  /// suggestion or a map pin), same order; null where it must be located
  /// from its address.
  final List<GeoPoint?> stopPoints;
  final BookingMode bookingMode;
  final bool lockBookingMode;
  final DateTime? initialScheduledFor;
  final String? initialRideId;
  final String? initialPaymentMethod;
  final String? parentReservationId;
  final String? editingReservationId;
  final String? note;
  final ReservationController? reservations;
  final Future<void> Function(BuildContext context, String reservationId)?
  onScheduled;

  /// Optional seams are used by behavioral certification; production keeps
  /// the same AppScope-backed defaults.
  final RideSelectionController? selection;
  final BookingController? booking;
  final RideRealtime? realtime;
  final bool pickupAlreadyConfirmed;

  /// True when [pickupPosition] is only a default map point because the app
  /// had no location fix: Set location opens with its button disabled until
  /// the rider moves the pin or their location arrives.
  final bool pickupIsFallback;

  /// Looks the stops up; defaults to the app's geocoder.
  final GeocodingRepository? geocoding;

  /// The free cars drawn around the pickup (contract v0.5.2 §13); defaults
  /// to the server's `GET /rider/nearby-vehicles`.
  final NearbyCarsSource? nearbyCars;

  /// The rider's live trip on the server; defaults to the app's
  /// `GET /rider/trips/active`.
  final ActiveTripRepository? activeTrips;

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFE7EBEE);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _accentSoft = Color(0xFFEAF2F8);

  static const Color _cta = Color(0xFF11181D);

  /// Owner round 2: the chosen ride's strong outline.
  static const Color _selectedOutline = Color(0xFF0F1B2D);

  List<_RideOption> get _allRides {
    return _selection.rides().map((ride) {
      return _RideOption(
        id: ride.id,
        image: ride.image,
        name: ride.name,
        // v0.7.1: the admin's sub-line in the rider's language; else
        // (rider-77) the built-in note in the rider's language.
        note: ride.lineIn(L10n.current.localeName) ?? rideNoteFor(ride.note),
        arrival: ride.arrival,
        etaMin: ride.etaMin,
        price: ride.price,
        currency: ride.currency,
        seats: ride.seats,
        badge: ride.badge == null ? null : rideBadgeFor(ride.badge!),
        glyph: _glyphIcon(ride.glyph),
        glyphKey: ride.glyph,
      );
    }).toList();
  }

  /// The small badge drawn over the category picture, by the catalog's
  /// glyph key. Unknown keys draw nothing.
  static IconData? _glyphIcon(String? key) => switch (key) {
    'bolt' => Icons.bolt_rounded,
    'pets' => Icons.pets_rounded,
    'car' => Icons.directions_car_rounded,
    'van' => Icons.airport_shuttle_rounded,
    'wheelchair' => Icons.accessible_rounded,
    'briefcase' => Icons.work_rounded,
    'plane' => Icons.flight_takeoff_rounded,
    'child' => Icons.child_care_rounded,
    'person' => Icons.person_rounded,
    'parcel' => Icons.inventory_2_rounded,
    _ => null,
  };

  /// Owner round 2: the free cars around the pickup, gliding between the
  /// server's answers.
  late final NearbyCarsController _nearby = NearbyCarsController(
    source:
        widget.nearbyCars ??
        NearbyCarsController.apiSource(AppScope.instance.api),
  );
  Timer? _glideTicker;
  ({BitmapDescriptor right, BitmapDescriptor left})? _carIcons;
  bool _appInForeground = true;
  late final bool _ownsSelection = widget.selection == null;
  late final RideSelectionController _selection =
      widget.selection ??
      RideSelectionController(
        bookingMode: widget.bookingMode,
        lockBookingMode: widget.lockBookingMode,
        paymentStore: AppScope.instance.defaultPayment,
      );
  bool _mapReady = false;

  /// uat-r1: the road for the pickup → destination leg, drawn in place of
  /// the straight first-paint line once the routing seam answers.
  List<LatLng>? _roadRoutePoints;
  Stopwatch? _nextMapReadyWatch;
  bool _mapMountScheduled = false;
  bool _mapParked = false;
  bool _overlayOn = false;
  bool _pickupConfirmed = false;
  bool _bookingInFlight = false;
  // The driver-notes block was removed (owner request); bags are asked
  // on Set pickup instead.
  RideNotes _notes = RideNotes.empty;
  late String _pickupAddress;
  late LatLng _pickupPosition;
  // ignore: unused_field
  GoogleMapController? _mapController;
  late final AnimationController _sheetSlide;
  BitmapDescriptor? _pickupPin;
  BitmapDescriptor? _destinationPin;
  BitmapDescriptor? _pickupTimePin;
  BitmapDescriptor? _destinationTimePin;
  String? _timePinKey;
  bool _openedAtMiddle = false;
  // One scrollable drives both the sheet and the list: dragging anywhere on
  // the sheet moves it between its stops, and once it is fully up the same
  // finger keeps scrolling the rides.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  MediaQueryData? _media;
  double? _settledStop;

  late final RouteFitScheduler _fits = RouteFitScheduler(plan: _routeFitPlan);

  /// True while a finger moves the sheet; the web overlay waits for the
  /// settle instead of toggling mid-drag.
  bool _sheetDragging = false;

  /// The rider's promotion (admin panel), shown on top of the list.
  RiderPromotion? get _promotion => AppScope.instance.promotion.active;

  ReservationController get _reservations =>
      widget.reservations ?? AppScope.instance.reservations;

  @override
  void initState() {
    super.initState();
    _pickupAddress = widget.pickupAddress;
    _pickupPosition = widget.pickupPosition;
    unawaited(_refreshRoadRoute());
    _nextMapReadyWatch = Stopwatch()..start();
    _pickupConfirmed = widget.pickupAlreadyConfirmed;
    // Q7: the pickup's zone decides the currency of every price here.
    _selection.currency = RiderZones.at(
      _pickupPosition.latitude,
      _pickupPosition.longitude,
    ).currency;
    _sheetSlide = AnimationController(
      vsync: this,
      duration: MoveraDurations.sheetOpen,
      value: 1,
    );
    _sheetSlide.addListener(_syncSheetOverlay);
    _sheetController.addListener(_syncSheetSlide);
    _syncSheetOverlay();
    WidgetsBinding.instance.addObserver(this);
    _nearby.addListener(_onNearbyCars);
    unawaited(_loadCarIcons());
    if (widget.initialRideId != null) {
      final ride = _selection.rideByIdOrNull(widget.initialRideId!);
      if (ride != null) {
        _selection.selectRide(
          ride.id,
          ride.price,
          catalogCurrency: ride.currency,
        );
      }
    }
    _selection.ensureCatalogSelection();
    _catalogIds = _selection.rides().map((ride) => ride.id).toList();
    // Fresh categories from the server, without blocking: the known list
    // shows at once and the sheet rebuilds when the answer lands.
    _selection.catalogChanges?.addListener(_onCatalogChanged);
    unawaited(_selection.refreshCatalog());
    final paymentName =
        widget.initialPaymentMethod ??
        (widget.editingReservationId == null
            ? null
            : _reservations.byId(widget.editingReservationId!)?.paymentMethod);
    _selection.selectPaymentNamed(paymentName);
    unawaited(_loadSavedCards(paymentName));
    if (widget.initialScheduledFor != null) {
      _selection.scheduleFor(widget.initialScheduledFor);
    } else if (widget.bookingMode == BookingMode.scheduled) {
      _selection.setBookingMode(BookingMode.scheduled);
    }
    _loadQuotes();
    unawaited(_loadRoutePins());
    unawaited(_loadWalletBalance());
    unawaited(_loadZoneConfig());
  }

  /// The pickup zone's config: its payment methods (Q7) and time zone (Q9).
  RiderAppConfig? _zoneConfig;

  Future<void> _loadZoneConfig() async {
    try {
      final config = await AppScope.instance.riderConfig.forTrip(
        currency: _selection.currency,
        pickupLat: _pickupPosition.latitude,
        pickupLng: _pickupPosition.longitude,
      );
      if (!mounted || config == null) return;
      setState(() {
        _zoneConfig = config;
        _selection.setZonePaymentMethods(config.paymentMethods);
        _selection.setPaymentOptions(config.paymentOptions);
      });
    } catch (error) {
      AppLog.warning(
        'select_ride.zone_config_failed',
        extra: {'error': '$error'},
      );
    }
  }

  Future<void> _loadRoutePins() async {
    final pins = await Future.wait([
      RouteEndpointMarker.createIcon(pickup: true),
      RouteEndpointMarker.createIcon(pickup: false),
    ]);
    if (!mounted) return;
    setState(() {
      _pickupPin = pins[0];
      _destinationPin = pins[1];
    });
  }

  /// Saved cards first (they are payment methods too), then the remembered
  /// default when nothing was handed in.
  Future<void> _loadSavedCards(String? paymentName) async {
    try {
      await _selection.loadSavedCards();
      if (paymentName != null) {
        _selection.selectPaymentNamed(paymentName);
      } else {
        await _selection.restoreDefaultPayment();
      }
    } catch (error) {
      AppLog.warning(
        'select_ride.payment_load_failed',
        extra: {'error': '$error'},
      );
    }
    if (mounted) setState(() {});
  }

  /// Ids of the catalog the sheet currently shows; a server answer with a
  /// different set (a category added in the admin panel) needs quotes for
  /// the new ids too.
  List<String> _catalogIds = const [];

  void _onCatalogChanged() {
    if (!mounted) return;
    final ids = _selection.rides().map((ride) => ride.id).toList();
    final sameIds =
        ids.length == _catalogIds.length &&
        List.generate(
          ids.length,
          (i) => ids[i] == _catalogIds[i],
        ).every((same) => same);
    setState(() {
      _catalogIds = ids;
      _selection.ensureCatalogSelection();
    });
    if (sameIds) return;
    // rider-u187: while a booking flow is open the list prices the
    // unconfirmed pickup and would replace the pin's price; the lock's
    // release prices the new ids.
    if (_bookingInFlight) {
      _catalogRequoteDeferred = true;
      return;
    }
    unawaited(_loadQuotes());
  }

  bool _catalogRequoteDeferred = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheetSlide.duration = MoveraMotion.of(context, MoveraDurations.sheetOpen);
    if (!_openedAtMiddle) {
      // Opens at the middle stop: the route and about three rides.
      _openedAtMiddle = true;
      _sheetSlide.value = _midValue(MediaQuery.of(context));
    }
    if (!_mapMountScheduled) {
      _mapMountScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_mountMapWhenRouteSettles());
      });
    }
  }

  /// uat-r1 (owner's iPhone report): this map drew its own straight
  /// pickup → destination line and never asked the routing seam for the
  /// road. The straight line is only the first paint now; the road route
  /// replaces it when the provider answers, also when it answers late. A
  /// provider failure keeps the straight line and never reaches the
  /// screen. With stops the straight line stays, as on Finding.
  Future<void> _refreshRoadRoute() async {
    if (_locatedStops.isNotEmpty) return;
    final from = _pickupPosition;
    final to = widget.destinationPosition;
    final Polyline route;
    try {
      route = await roadRoutePolyline(
        id: 'route',
        from: from,
        to: to,
        color: RiderRouteStyle.color,
      );
    } catch (_) {
      return;
    }
    if (!mounted || route.points.length < 2) return;
    // The pickup moved (or stops arrived) while this answer was on its
    // way: the newer request draws the line.
    if (from != _pickupPosition || _locatedStops.isNotEmpty) return;
    setState(() => _roadRoutePoints = route.points);
    // Owner N6: a road that answers after the rider pinched or panned the
    // map leaves their camera alone (it snapped back to the overview).
    if (AppScope.instance.maps.movedByHand) return;
    // The road may reach past the straight line: frame it.
    unawaited(_fitRoute());
  }

  /// Height of the back-and-address bar over the map, under the status bar.
  static const double _searchBarObstruction = 76;

  Future<void> _mountMapWhenRouteSettles() async {
    final navigationBarrierWatch = Stopwatch()..start();
    await waitForCurrentRouteToSettle(context);
    navigationBarrierWatch.stop();
    RouteTransitionMetrics.navigationBarrier(navigationBarrierWatch.elapsed);
    if (!mounted) return;
    setState(() => _mapReady = true);
  }

  Future<void> _loadQuotes() async {
    final generation = _selection.beginQuotes();
    // Quotes include the stops (audit finding B7, contract §3), so the price
    // shown is the price of the route booked.
    final stops = await _routeStops();
    if (!mounted) return;
    await _selection.loadQuotes(
      stops: stops,
      generation: generation,
      pickup: _pickupAddress,
      destination: widget.destinationAddress,
      distanceMeters: straightLineMeters(
        _pickupPosition,
        widget.destinationPosition,
      ),
      pickupPoint: _geoPoint(_pickupPosition),
      destinationPoint: _geoPoint(widget.destinationPosition),
    );
    if (!mounted) return;
    setState(() {});
    _scheduleExpiryRequote();
  }

  /// rider-u185: prices the rides again when their quotes run out, so the
  /// list never sits on a fare that is no longer offered.
  Timer? _expiryRequote;

  void _onQuotesExpired() {
    _expiryRequote = null;
    // While Set pickup is open the booking refreshes its own quote, and a
    // list load must not replace the pin's price; the lock's release
    // schedules again.
    if (!mounted || _bookingInFlight) return;
    setState(() {});
    unawaited(_loadQuotes());
  }

  /// ARCH-8: quotes carry the points, so the server prices the route itself.
  static GeoPoint _geoPoint(LatLng point) =>
      GeoPoint(point.latitude, point.longitude);

  /// The latest pin re-quote still in flight, so booking can wait for it.
  Future<RideQuote?>? _pinQuote;

  /// A pin quote was adopted for a point the rider has not confirmed yet.
  bool _pinQuoteAdopted = false;

  /// A quote that is still good for the next [_quoteMargin], or null.
  static const _quoteMargin = Duration(seconds: 10);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _glideTicker?.cancel();
    _nearby.removeListener(_onNearbyCars);
    _nearby.dispose();
    _carTick.dispose();
    _expiryRequote?.cancel();
    _fits.dispose();
    _selection.catalogChanges?.removeListener(_onCatalogChanged);
    if (_ownsSelection) _selection.dispose();
    _sheetSlide.removeListener(_syncSheetOverlay);
    _sheetController.removeListener(_syncSheetSlide);
    _sheetController.dispose();
    _sheetSlide.dispose();
    _mapController = null;
    setWebOverlayOpen(false);
    AppScope.instance.maps.detach(owner: MapOwners.selectRide);
    super.dispose();
  }

  Future<void> _loadCarIcons() async {
    try {
      final icons = await NearbyCarMarker.icons();
      if (mounted) setState(() => _carIcons = icons);
    } catch (error) {
      AppLog.warning(
        'select_ride.car_icons_failed',
        extra: {'error': '$error'},
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncNearbyWatch();
  }

  bool _nearbySyncScheduled = false;

  /// Ticks the map (only the map) to redraw the nearby cars.
  final ValueNotifier<int> _carTick = ValueNotifier<int>(0);

  /// A new answer: redraw, and keep redrawing while the cars glide. A
  /// finger moving the sheet gets every frame: the cars wait and catch up
  /// when it lets go (each redraw re-applies every car marker in the
  /// browser, which is DOM work on top of the drag's own frame).
  void _onNearbyCars() {
    if (!mounted) return;
    if (!_sheetDragging) _carTick.value++;
    _glideTicker?.cancel();
    _glideTicker = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_sheetDragging) return;
      final still = !_nearby.gliding();
      _carTick.value++;
      if (still) {
        timer.cancel();
        if (identical(_glideTicker, timer)) _glideTicker = null;
      }
    });
  }

  void _syncSheetOverlay() {
    if (_sheetDragging) return;
    // Hysteresis around the low stop, so a sheet resting near it does not
    // flip the map's pointer events back and forth.
    final v = _sheetSlide.value;
    final cover = _overlayOn ? v > 0.02 : v > 0.05;
    if (cover == _overlayOn) return;
    _overlayOn = cover;
    setWebOverlayOpen(cover);
  }

  void _selectRide(String id) {
    // rider-u189: the booking under way has captured its ride.
    if (_bookingInFlight) return;
    _RideOption? selected;
    for (final ride in _allRides) {
      if (ride.id == id) {
        selected = ride;
        break;
      }
    }
    if (selected == null) return;
    setState(() {
      _selection.selectRide(
        selected!.id,
        selected.price,
        catalogCurrency: selected.currency,
      );
    });
  }

  /// Owner round 2: two groups like the other ride apps, each in catalog
  /// order: the everyday rides first, then the premium and special ones.
  static const _premiumGroup = {
    'premium',
    'business',
    'electric',
    'pet',
    'kids',
    'child_seat',
  };

  /// The list as it is drawn: the two headings (only when both groups have
  /// rides) and the rides under them.
  List<({String? heading, _RideOption? ride})> get _listEntries {
    final rides = _visibleRides;
    final premium = rides.where((r) => _premiumGroup.contains(r.id)).toList();
    final everyday = rides.where((r) => !_premiumGroup.contains(r.id)).toList();
    final headed = premium.isNotEmpty && everyday.isNotEmpty;
    return [
      if (headed) (heading: context.l10n.ridesForYou, ride: null),
      for (final ride in everyday) (heading: null, ride: ride),
      if (headed) (heading: context.l10n.ridesPremium, ride: null),
      for (final ride in premium) (heading: null, ride: ride),
    ];
  }

  static const double _rowHeight = 78;

  /// The sheet's fixed top: the handle (22), the promotion line or the
  /// title, and the line under them.
  static const double _titleHeight = 42;
  static const double _promotionLineHeight = 44;

  /// Mirrors the sheet's position onto [_sheetSlide] (0 = low stop, 1 = full),
  /// which the list, the filters, the map framing and the web overlay follow.
  void _syncSheetSlide() {
    final media = _media;
    if (media == null || !_sheetController.isAttached) return;
    final minSheet = _minSheet(media);
    final range = _maxSheet(media) - minSheet;
    if (range <= 0) return;
    _sheetSlide.value = ((_sheetController.pixels - minSheet) / range).clamp(
      0.0,
      1.0,
    );
  }

  /// Owner round 3: while the sheet snaps to a stop, the camera already
  /// frames the route for that stop, so the map moves with the sheet
  /// instead of after it.
  double? _fitSlideTarget;

  /// Pins carry the chosen ride's times; rebuilt when the choice changes.
  void _syncTimePins() {
    final ride = _selectedRideOrNull;
    if (ride == null) return;
    final scheduled = _scheduledPickup;
    final pickupLabel = scheduled != null
        ? clockTime(scheduled)
        : '${ride.etaMin}\nmin';
    final key = '${ride.id}|$pickupLabel|${_arrivalFor(ride)}';
    if (key == _timePinKey) return;
    _timePinKey = key;
    unawaited(() async {
      final pins = await Future.wait([
        RouteTimeMarker.createIcon(pickup: true, label: pickupLabel),
        RouteTimeMarker.createIcon(
          pickup: false,
          label: context.l10n.arriveBy(_arrivalFor(ride)),
        ),
      ]);
      if (!mounted || key != _timePinKey) return;
      setState(() {
        _pickupTimePin = pins[0];
        _destinationTimePin = pins[1];
      });
    }());
  }

  RouteFitPlan? _routeFitPlan() {
    if (!mounted) return null;
    final pickup = _pickupPosition;
    final destination = widget.destinationPosition;
    final media = MediaQuery.of(context);
    final samePoint =
        (pickup.latitude - destination.latitude).abs() < 0.00008 &&
        (pickup.longitude - destination.longitude).abs() < 0.00008;
    if (samePoint) {
      return (
        key: 'point|${pickup.latitude}|${pickup.longitude}',
        move: () => AppScope.instance.maps.animateCamera(
          GeoPoint(pickup.latitude, pickup.longitude),
          zoom: 14.4,
        ),
      );
    }
    // D-009: the map sits behind the (initially expanded) sheet, so frame
    // both pins in the part of the map the sheet leaves visible.
    final minSheet = _minSheet(media);
    final slide = _fitSlideTarget ?? _sheetSlide.value;
    final sheetHeight = minSheet + (_maxSheet(media) - minSheet) * slide;
    final fit = selectRideCameraFit(
      pickup: GeoPoint(pickup.latitude, pickup.longitude),
      destination: GeoPoint(destination.latitude, destination.longitude),
      mapHeight: media.size.height - minSheet,
      bottomObstruction: sheetHeight - minSheet,
      // Owner round 4: the search bar at the top and the road's own
      // points, so neither the line nor a time bubble is cut.
      topObstruction: media.padding.top + _searchBarObstruction,
      route: [
        for (final p in _roadRoutePoints ?? const <LatLng>[])
          GeoPoint(p.latitude, p.longitude),
      ],
    );
    return (
      // What decides the framing: the points, the road and the sheet's
      // height to ~10 px (a settle lands within a few px of its stop).
      key: [
        pickup.latitude,
        pickup.longitude,
        destination.latitude,
        destination.longitude,
        identityHashCode(_roadRoutePoints),
        media.size.width.round(),
        media.size.height.round(),
        media.padding.top.round(),
        ((sheetHeight - minSheet) / 10).round(),
      ].join('|'),
      // The map may be gone or not laid out yet; the scheduler keeps the
      // camera where it is and flies again on the next request.
      move: () => AppScope.instance.maps.fitBounds(
        fit.southwest,
        fit.northeast,
        padding: fit.padding,
      ),
    );
  }

  Future<void> _withParkedMap(Future<void> Function() action) async {
    if (!_mapParked) {
      setState(() => _mapParked = true);
      AppScope.instance.maps.detach(owner: MapOwners.selectRide);
      _mapController = null;
      // Dispose the current platform map for one frame before mounting the
      // next ride stage. This prevents overlapping maps without a visible
      // arbitrary 90 ms pause.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    try {
      await action();
    } finally {
      final routeIsCurrent =
          mounted && (ModalRoute.of(context)?.isCurrent ?? false);
      if (routeIsCurrent) setState(() => _mapParked = false);
    }
  }

  Future<void> _chooseLater({DateTime? initial}) async {
    await _withParkedMap(() async {
      if (!mounted) return;
      final when = await ScheduleDateTimeSelector.choose(
        context,
        initial: initial,
        tripMinutes: _tripMinutes(),
        timeZone: _pickupSchedule.timeZone,
        horizonDays: _pickupSchedule.horizonDays,
        freeChangeBeforeMin:
            _zoneConfig?.freeChangeBeforeMin ??
            RiderAppConfig.defaultFreeChangeBeforeMin,
      );
      if (when == null || !mounted) return;
      // Only the time here; the pickup is set once, on Set pickup after
      // Schedule.
      setState(() => _selection.scheduleFor(when));
    });
  }

  Future<void> _showBookingPicker() async {
    if (_bookingInFlight) return;
    if (widget.lockBookingMode) {
      await _chooseLater();
      return;
    }
    var chooseLaterAfterClose = false;
    await MoveraSheet.show<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.whenDoYouWantToRide,
                    style: _text(20, weight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                _sheetChoice(
                  icon: Icons.bolt_rounded,
                  title: context.l10n.bookNow,
                  subtitle: context.l10n.bookNowBody,
                  selected: _selection.bookingMode == BookingMode.now,
                  onTap: () {
                    setState(() => _selection.setBookingMode(BookingMode.now));
                    Navigator.pop(sheetContext);
                  },
                ),
                _sheetChoice(
                  icon: Icons.calendar_month_rounded,
                  title: context.l10n.bookForLater,
                  subtitle: context.l10n.bookForLaterBody,
                  selected: _selection.bookingMode == BookingMode.scheduled,
                  onTap: () {
                    chooseLaterAfterClose = true;
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chooseLaterAfterClose && mounted) {
      await _chooseLater();
    }
  }

  Future<void> _showPaymentPicker() async {
    final current = _selection.selectedPaymentItem();
    final ride = _selectedRideOrNull;
    final brand = await PayWithPage.open(
      context,
      methods: [
        for (final item in _selection.payments())
          PayWithMethod(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
          ),
        // v0.18.10 (owner G8 item 2): on in admin, not taken yet.
        for (final item in _selection.comingSoonPayments())
          PayWithMethod(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
            comingSoon: true,
          ),
      ],
      selectedBrand: current?.brand,
      walletBalance: _selection.walletBalance,
      walletCurrency: _selection.walletCurrency,
      walletCoversFare:
          ride == null || _selection.walletCovers(_priceFor(ride)),
      promotion: _promotion,
      brandMark: _brandMark,
      useWalletFirst: _selection.useWalletFirst,
      onWalletFirstChanged: (value) {
        if (!mounted) return;
        setState(() => _selection.useWalletFirst = value);
        unawaited(_saveWalletFirst(value));
      },
    );
    if (brand == null || !mounted) return;
    final index = _selection.payments().indexWhere((p) => p.brand == brand);
    if (index < 0) return;
    setState(() => _selection.selectPayment(index));
  }

  /// v0.18.10 `finish.paymentMethods.booking`: the server refused the
  /// trip's payment method. A box says why (`texts[reason]`), cash is
  /// chosen when it is taken, and the payment choice opens.
  Future<void> _paymentMethodRefused(String reason) async {
    final l10n = context.l10n;
    final text = switch (reason) {
      'payment_method_off' => l10n.paymentMethodOff,
      'payment_method_coming_soon' => l10n.paymentMethodComingSoon,
      _ => l10n.paymentMethodNotAvailable,
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('payment-method-refused'),
        semanticLabel: text,
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.gotIt),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _selection.selectPaymentByBrand('cash'));
    await _showPaymentPicker();
  }

  Future<void> _loadWalletBalance() async {
    try {
      // Q8: the balance of this trip's currency (one wallet per currency).
      final wallet = AppScope.instance.walletController.forCurrency(
        _selection.currency,
      );
      final balance = await wallet.loadBalance();
      final walletFirst = await wallet.loadUseWalletFirst();
      if (!mounted) return;
      setState(() {
        _selection.useWalletFirst = walletFirst;
        _selection.walletCurrency = wallet.currency;
        _selection.setWalletBalance(balance);
      });
    } catch (error) {
      AppLog.warning(
        'select_ride.wallet_load_failed',
        extra: {'error': '$error'},
      );
    }
  }

  Future<void> _saveWalletFirst(bool value) async {
    final saved = await AppScope.instance.walletController.saveUseWalletFirst(
      value,
    );
    // CODE-16: a toggle that was not saved must not keep showing the change.
    if (!saved && mounted && _selection.useWalletFirst == value) {
      setState(() => _selection.useWalletFirst = !value);
    }
  }

  Future<void> _bookScheduled() async {
    try {
      final pickupConfirmedBefore = _pickupConfirmed;
      if (_selection.scheduledFor == null) {
        await _chooseLater();
      } else if (_returnTimeNeedsPicker) {
        // Route the rider through the shared validated picker, which opens on
        // the prefill clamped to the next legal slot.
        await _chooseLater(initial: _selection.scheduledFor);
      }
      if (_selection.scheduledFor == null || !mounted) return;
      // Still stale after the picker: the rider dismissed it, so book nothing.
      // Unless the pickup spot was confirmed in that same pass - then the
      // chosen time went stale on the pickup screen, and the re-pick below
      // must ask again rather than silently dropping the booking.
      if (_returnTimeNeedsPicker && _pickupConfirmed == pickupConfirmedBefore) {
        return;
      }
      await _withParkedMap(() async {
        if (!mounted) return;
        // rider-r4-34: as Book now, the generic Card row needs a saved card
        // first; a reservation is never paid by "Card" with none behind it.
        final method = _selection.selectedPaymentItem();
        if (method?.brand == 'cards' && !_selection.hasSavedCard) {
          if (await _addCardFirst() == null || !mounted) return;
        }
        SetPickupResult? spot;
        if (!_pickupConfirmed) {
          // Same Set pickup sheet as Book now, ending in "Confirm and
          // schedule" instead of a search.
          final ride = _selectedRideOrNull;
          if (ride == null) return;
          // rider-r4-30: the date picker can outlast the quote; Set pickup
          // shows a live quote, never the list price it falls back to.
          if (_bookableQuote(ride.id) == null) {
            final fresh = await _quoteAfterPickup(ride);
            if (!mounted) return;
            if (fresh == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.priceUnavailableRefreshing),
                ),
              );
              unawaited(_loadQuotes());
              return;
            }
          }
          _pinQuote = null;
          _pinQuoteAdopted = false;
          spot = await _openSetPickup(
            ride,
            confirmLabel: context.l10n.confirmAndSchedule,
            scheduledPickup: _selection.scheduledFor,
          );
          if (!mounted) return;
          if (spot == null) {
            // rider-u188: as Book now, the pin's price belongs to a point
            // the rider did not confirm.
            if (_pinQuoteAdopted) unawaited(_loadQuotes());
            return;
          }
          _pickupAddress = spot.address;
          _pickupPosition = spot.position;
          _roadRoutePoints = null;
          unawaited(_refreshRoadRoute());
          _pickupConfirmed = true;
          _notes = _notes.withBagLevel(spot.bagLevel);
          // rider-r3-6: Card may have been picked on Set pickup.
          if (_selection.selectedPaymentItem()?.brand == 'cards' &&
              !_selection.hasSavedCard) {
            if (await _addCardFirst() == null || !mounted) return;
          }
        }
        if (_returnTimeNeedsPicker) {
          // The prefill went stale while the rider confirmed the pickup spot.
          final when = await ScheduleDateTimeSelector.choose(
            context,
            initial: _selection.scheduledFor,
            // rider-89: Arrive by needs the trip estimate here too.
            tripMinutes: _tripMinutes(),
            timeZone: _pickupSchedule.timeZone,
            horizonDays: _pickupSchedule.horizonDays,
            freeChangeBeforeMin:
                _zoneConfig?.freeChangeBeforeMin ??
                RiderAppConfig.defaultFreeChangeBeforeMin,
          );
          if (when == null || !mounted) return;
          _selection.scheduleFor(when);
        }
        final booked = _selectedRideOrNull;
        if (booked == null) return;
        // rider-79: as Book now, the price booked is the confirmed
        // pickup's: a pin price still loading is waited for, and a quote
        // from another point is priced again.
        final bookable = await _quoteAfterPickup(booked);
        if (!mounted) return;
        if (bookable == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
          );
          unawaited(_loadQuotes());
          return;
        }
        final shown = spot?.fareTotalKr;
        if (shown != null &&
            _selection.moneyOf(shown).amountMinor !=
                bookable.quote.totalMinor &&
            !await _acceptNewPrice(shown, bookable.price)) {
          if (!mounted) return;
          setState(() {});
          unawaited(_loadQuotes());
          return;
        }
        if (!mounted) return;
        if (_walletCannotPay(bookable.price)) return;
        // rider-r4-28: the stops the price was quoted for are booked too.
        final stops = await _routeStops();
        if (!mounted) return;
        final Reservation? created;
        try {
          created = await ScheduledRideCheckout.run(
            context,
            reservations: _reservations,
            selection: _selection,
            pickup: ReservationPlace(
              label: _pickupAddress,
              lat: _pickupPosition.latitude,
              lng: _pickupPosition.longitude,
            ),
            destination: ReservationPlace(
              label: widget.destinationAddress,
              lat: widget.destinationPosition.latitude,
              lng: widget.destinationPosition.longitude,
            ),
            pickupPosition: _pickupPosition,
            note: _driverNote(widget.note),
            parentReservationId: widget.parentReservationId,
            editingReservationId: widget.editingReservationId,
            original: widget.editingReservationId == null
                ? null
                : _reservations.byId(widget.editingReservationId!),
            // rider-63: the zone the time was picked in.
            timeZone: _pickupSchedule.timeZone,
            stops: [
              for (final stop in stops)
                ReservationPlace(
                  label: stop.address,
                  lat: stop.latitude,
                  lng: stop.longitude,
                ),
            ],
            // rider-r4-35: the quote ran out on Review changes.
            requote: (reviewed) => _requoteReviewed(booked, reviewed),
          );
        } catch (error, stack) {
          final action = widget.editingReservationId == null
              ? ReservationAction.book
              : ReservationAction.edit;
          AppScope.instance.crashes.record(
            error,
            stack,
            operation: 'reservation.${action.name}',
          );
          if (mounted) {
            MoveraToast.show(context, reservationErrorMessage(error, action));
          }
          return;
        }
        if (!mounted || created == null) return;
        final opener = widget.onScheduled;
        if (opener != null) {
          await opener(context, created.reservationId);
          return;
        }
        Navigator.pop(context, created);
      });
    } finally {
      _releaseBookingLock();
    }
  }

  /// rider-r4-35: prices [ride] again after Review changes outlasted its
  /// quote; a different price is agreed to first. Null: nothing to save.
  Future<double?> _requoteReviewed(_RideOption ride, double reviewed) async {
    final bookable = await _quoteAfterPickup(ride);
    if (!mounted) return null;
    if (bookable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
      );
      return null;
    }
    if (_selection.moneyOf(reviewed).amountMinor != bookable.quote.totalMinor &&
        !await _acceptNewPrice(reviewed, bookable.price)) {
      return null;
    }
    return mounted ? bookable.price : null;
  }

  String? _driverNote(String? extra) {
    final parts = <String>[
      if (extra != null && extra.trim().isNotEmpty) extra.trim(),
      ..._notes.selected,
    ];
    if (parts.isEmpty) return extra;
    return parts.join(' · ');
  }

  void _releaseBookingLock() {
    _bookingInFlight = false;
    if (!mounted) return;
    setState(() {});
    if (_catalogRequoteDeferred) {
      _catalogRequoteDeferred = false;
      unawaited(_loadQuotes());
      return;
    }
    if (_expiryRequote == null) _scheduleExpiryRequote(requoteSpent: true);
  }

  void _releaseRouteWork() {
    _bookingInFlight = false;
    _expiryRequote?.cancel();
    _expiryRequote = null;
    _selection.cancelPendingQuotes();
  }

  void _onRoutePop(bool didPop, Object? _) {
    if (!didPop) return;
    _releaseRouteWork();
  }

  void _book() {
    if (_bookingInFlight) return;

    final selected = _selectedRideOrNull;
    if (selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noRideCategory)));
      return;
    }
    if (!_selection.quoteIsAvailable(selected.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
      );
      unawaited(_loadQuotes());
      return;
    }
    if (_walletCannotPay(_priceFor(selected))) return;

    _bookingInFlight = true;
    setState(() {});
    if (_selection.bookingMode == BookingMode.scheduled) {
      _bookScheduled();
      return;
    }
    _bookNow();
  }

  /// Where the rider's Home is, so Set pickup can offer a "Near Home" spot.
  /// Best effort: no Home, or a slow lookup, simply means no such spot.
  Future<LatLng?> _homePosition() async {
    try {
      final places = AppScope.instance.savedPlaces;
      await places.hydrate().timeout(const Duration(milliseconds: 600));
      final home = places.shortcuts().where((p) => p.kind == 'home');
      if (home.isEmpty) return null;
      final found = await AppScope.instance.geocoding
          .geocodeAddress(home.first.subtitle)
          .timeout(const Duration(milliseconds: 900));
      if (found == null) return null;
      return LatLng(found.point.latitude, found.point.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<SetPickupResult?> _openSetPickup(
    _RideOption ride, {
    String? confirmLabel,
    DateTime? scheduledPickup,
  }) async {
    final home = await _homePosition();
    if (!mounted) return null;
    final quote = _selection.authoritativeQuotes[ride.id];
    final promotion = _promotion;
    SetPickupPayment paymentLine() {
      final item = _selection.selectedPaymentItem();
      return SetPickupPayment(
        brand: item?.brand ?? 'cash',
        name: item?.name ?? context.l10n.payCash,
        detail: item?.detail ?? '',
      );
    }

    return SetPickupPage.open(
      context,
      initialPosition: _pickupPosition,
      initialAddress: _pickupAddress,
      destinationAddress: widget.destinationAddress,
      destinationPosition: widget.destinationPosition,
      stops: [for (final stop in _locatedStops) stop.address],
      ride: SetPickupRide(
        name: ride.name,
        image: ride.image,
        seats: ride.seats,
        etaMin: ride.etaMin,
        tripMinutes: _tripMinutes(),
      ),
      fare: SetPickupFare(
        totalKr: _priceFor(ride),
        walletKr: _selection.walletAppliedKr(_priceFor(ride)),
        discountKr: _discountFor(ride),
        promotionPercent: quote != null && quote.discountMinor > 0
            ? promotion?.percentOff
            : null,
        currency: _selection.currency,
      ),
      payment: paymentLine(),
      brandMark: _brandMark,
      onChangePayment: () async {
        await _showPaymentPicker();
        return paymentLine();
      },
      onRequote: (pin) => _requoteFromPin(ride, pin),
      fareAfterPaymentChange: (fare) => SetPickupFare(
        totalKr: fare.totalKr,
        discountKr: fare.discountKr,
        promotionPercent: fare.promotionPercent,
        walletKr: _selection.walletAppliedKr(fare.totalKr),
        currency: fare.currency,
      ),
      initialBagLevel: _notes.bagLevel,
      home: home,
      initialIsCurrentLocation: !_pickupConfirmed && !widget.pickupIsFallback,
      positionIsFallback: widget.pickupIsFallback && !_pickupConfirmed,
      confirmLabel: confirmLabel,
      scheduledPickup: scheduledPickup,
    );
  }

  Future<List<RouteStop>>? _stopsLookup;

  /// [_locateStops], looked up once per screen and shared by quoting and
  /// booking so both price the same route.
  Future<List<RouteStop>> _routeStops() {
    if (widget.stops.every((stop) => stop.trim().isEmpty)) {
      return Future.value(const <RouteStop>[]);
    }
    return _stopsLookup ??= _locateStops();
  }

  /// The stops that made it into the quote, for the map and the header.
  List<RouteStop> _locatedStops = const [];

  /// The stops the rider typed on Plan your ride, with their map points;
  /// an address that cannot be found is left out rather than blocking the
  /// booking — and the rider is told (UI-04), never silently.
  Future<List<RouteStop>> _locateStops() async {
    final located = <RouteStop>[];
    final notFound = <String>[];
    final failed = <String>[];
    for (var i = 0; i < widget.stops.length; i++) {
      final clean = widget.stops[i].trim();
      if (clean.isEmpty) continue;
      final point = i < widget.stopPoints.length ? widget.stopPoints[i] : null;
      if (point != null) {
        located.add(
          RouteStop(
            address: clean,
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        );
        continue;
      }
      try {
        final found = await (widget.geocoding ?? AppScope.instance.geocoding)
            .forward(clean);
        if (found == null) {
          notFound.add(clean);
          continue;
        }
        located.add(
          RouteStop(
            address: clean,
            latitude: found.point.latitude,
            longitude: found.point.longitude,
          ),
        );
      } catch (_) {
        // Left out of this price; the rider can try the lookup again.
        failed.add(clean);
      }
    }
    if (mounted) {
      setState(() {
        _locatedStops = List.unmodifiable(located);
        // uat-r1: with stops the line goes through them, not along the
        // road from pickup straight to the destination.
        if (located.isNotEmpty) _roadRoutePoints = null;
        _stopsNotice = _stopsLeftOutNotice(notFound: notFound, failed: failed);
        _stopsRetry = failed.isNotEmpty;
      });
    }
    return located;
  }

  /// UI-04: which stops the price leaves out, said where the stops are
  /// shown (under the destination), so it never covers Book.
  String? _stopsNotice;
  bool _stopsRetry = false;

  static String? _stopsLeftOutNotice({
    required List<String> notFound,
    required List<String> failed,
  }) {
    String quoted(List<String> stops) =>
        stops.map((stop) => '“${shortenPlace(stop)}”').join(', ');
    if (failed.isNotEmpty) {
      return L10n.current.stopLookupFailed(quoted(failed));
    }
    if (notFound.isNotEmpty) {
      return L10n.current.stopNotFound(quoted(notFound));
    }
    return null;
  }

  void _retryStops() {
    setState(() {
      _stopsNotice = null;
      _stopsRetry = false;
    });
    // Look the stops up again and price the new route.
    _stopsLookup = null;
    unawaited(_loadQuotes());
  }

  void _bookNow() {
    final selected = _selectedRideOrNull;
    if (selected == null) {
      _releaseBookingLock();
      return;
    }
    final quote = _selection.quoteForBooking(selected.id);
    if (quote == null ||
        _selection.authoritativePriceFor(selected.id) == null ||
        !quote.bookable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fareChangedRefreshing)),
      );
      _releaseBookingLock();
      unawaited(_loadQuotes());
      return;
    }
    final paymentItem = _selection.selectedPaymentItem();
    if (paymentItem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noPaymentMethod)));
      _releaseBookingLock();
      return;
    }
    var payment = _PaymentOption(
      brand: paymentItem.brand,
      name: paymentItem.name,
      detail: paymentItem.detail,
    );
    _withParkedMap(() async {
      try {
        if (!mounted) return;
        if (FindingDriverController.active != null) return;
        // A card needs to be saved first: Add card opens before Set pickup
        // and the new card becomes the chosen method.
        if (payment.brand == 'cards' && !_selection.hasSavedCard) {
          final card = await _addCardFirst();
          if (card == null || !mounted) return;
          payment = _PaymentOption(
            brand: card.methodBrand,
            name: card.displayName,
            detail: context.l10n.cardExpires(card.expiryLabel),
          );
        }
        // Set pickup every time; the current location is preselected.
        _pinQuote = null;
        _pinQuoteAdopted = false;
        final spot = await _openSetPickup(selected);
        if (!mounted) return;
        if (spot == null) {
          // The pin's price belongs to a point the rider did not confirm.
          if (_pinQuoteAdopted) unawaited(_loadQuotes());
          return;
        }
        _pickupAddress = spot.address;
        _pickupPosition = spot.position;
        _roadRoutePoints = null;
        unawaited(_refreshRoadRoute());
        _pickupConfirmed = true;
        _notes = _notes.withBagLevel(spot.bagLevel);
        final chosen = _selection.selectedPaymentItem();
        if (chosen != null) {
          payment = _PaymentOption(
            brand: chosen.brand,
            name: chosen.name,
            detail: chosen.detail,
          );
        }
        // rider-r3-6: the generic Card row picked on Set pickup needs a
        // saved card too, as it does before Set pickup.
        if (payment.brand == 'cards' && !_selection.hasSavedCard) {
          final card = await _addCardFirst();
          if (card == null || !mounted) return;
          payment = _PaymentOption(
            brand: card.methodBrand,
            name: card.displayName,
            detail: context.l10n.cardExpires(card.expiryLabel),
          );
        }

        // Book the price Set pickup showed, not the one from before it.
        var bookable = await _quoteAfterPickup(selected);
        if (!mounted) return;
        var shown = spot.fareTotalKr;
        while (bookable != null &&
            shown != null &&
            _selection.moneyOf(shown).amountMinor !=
                bookable.quote.totalMinor) {
          if (!await _acceptNewPrice(shown, bookable.price)) {
            if (!mounted) return;
            setState(() {});
            // rider-79: the other categories are priced from the confirmed
            // pickup too.
            unawaited(_loadQuotes());
            return;
          }
          if (!mounted) return;
          // rider-u190: the dialog has no time limit. A quote that ran out
          // while it was open is priced again; a new price is asked again.
          shown = bookable.price;
          bookable = await _quoteAfterPickup(selected);
          if (!mounted) return;
        }
        if (bookable == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.priceUnavailableRefreshing)),
          );
          unawaited(_loadQuotes());
          return;
        }
        final quote = bookable.quote;
        final authoritativePrice = bookable.price;
        if (_walletCannotPay(authoritativePrice)) return;
        // The wallet part the rider was shown travels with the booking.
        final walletSplit = _selection.walletSplitFor(quote.totalMinor);

        final stops = await _routeStops();
        if (!mounted) return;

        String rideId;
        try {
          rideId = await (widget.booking ?? BookingController()).submitFinding(
            stops: stops,
            pickupAddress: _pickupAddress,
            destinationAddress: widget.destinationAddress,
            pickupLat: _pickupPosition.latitude,
            pickupLng: _pickupPosition.longitude,
            destinationLat: widget.destinationPosition.latitude,
            destinationLng: widget.destinationPosition.longitude,
            rideType: selected.id,
            price: authoritativePrice,
            paymentMethod: payment.brand,
            quoteId: quote.id,
            quoteSignedPayload: quote.signedPayload,
            quoteExpiresAt: quote.expiresAt,
            quoteTotalMinor: quote.totalMinor,
            quoteCurrency: quote.currency,
            rideTypeLabel: selected.name,
            paymentMethodLabel: payment.name,
            notes: _notes,
            useWalletFirst: _selection.useWalletFirst,
            walletAmountMinor: walletSplit.walletMinor,
          );
          if (rideId.trim().isEmpty) {
            throw StateError('Booking response did not contain a ride id.');
          }
        } catch (error) {
          if (!mounted) return;
          if (error is ApiError && error.detail == 'active_trip_exists') {
            await _openRideAlreadyGoing();
            return;
          }
          // v0.18.10 (owner G8 item 2): a payment method the server does
          // not take is said plainly, then back to the payment choice;
          // never a silent return to Select Ride.
          // G16-1: a paused account cannot book; it is said plainly.
          if (error is ApiError && error.detail == 'account_suspended') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: const ValueKey('booking-account-suspended'),
                content: Text(context.l10n.accountSuspended),
              ),
            );
            return;
          }
          if (error is ApiError && error.detail.startsWith('payment_method_')) {
            await _paymentMethodRefused(error.detail);
            return;
          }
          // RC-09: a booking that may exist on the server is not "refused".
          final uncertain = BookingController.mayHaveBooked(error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uncertain
                    ? context.l10n.bookingUncertain
                    : context.l10n.bookingFailed,
              ),
            ),
          );
          unawaited(_loadQuotes());
          return;
        }

        if (!mounted) {
          await RideRestoreCoordinator.instance.recoverCreatedFinding(
            rideId,
            realtime: widget.realtime,
          );
          return;
        }

        final existingOwner = FindingDriverController.active;
        if (existingOwner != null) {
          final authoritativeRideId =
              await (widget.booking ?? BookingController())
                  .reconcileCreatedFinding(rideId);
          if (!mounted) {
            if (authoritativeRideId == rideId) {
              await RideRestoreCoordinator.instance.recoverCreatedFinding(
                rideId,
                realtime: widget.realtime,
              );
            }
            return;
          }

          final ownerAfterReconcile = FindingDriverController.active;
          if (authoritativeRideId != rideId ||
              ownerAfterReconcile?.ownedRideId == rideId) {
            return;
          }
        }

        SheetCoordinator.instance.open(RideSheet.finding);
        try {
          await Navigator.push(
            context,
            RideStageTransition(
              FindingDrivers(
                pickupAddress: _pickupAddress,
                destinationAddress: widget.destinationAddress,
                pickupPosition: _pickupPosition,
                destinationPosition: widget.destinationPosition,
                rideType: selected.name,
                price: authoritativePrice,
                currency: quote.currency,
                paymentMethod: payment.name,
                walletAmountMinor: walletSplit.walletMinor,
                notes: _notes,
                stops: stops,
                realtime: widget.realtime,
                etaMinutes: selected.etaMin,
              ),
              settings: const RouteSettings(name: AppRoutes.findingDriver),
            ),
          );
        } finally {
          SheetCoordinator.instance.close(RideSheet.finding);
        }
      } finally {
        _releaseBookingLock();
      }
    });
  }

  /// Live test 2026-10-26: the server keeps one live ride per rider and
  /// refuses a booking with `active_trip_exists` while one is still going,
  /// for example a ride this device lost track of. That ride is opened
  /// instead of the "check the fare" message, which sent the rider back to
  /// a price that was never the problem.
  Future<void> _openRideAlreadyGoing() async {
    final trip = await (widget.booking ?? BookingController())
        .adoptRideAlreadyGoing(activeTrips: widget.activeTrips);
    if (!mounted) return;
    final coordinator = RideRestoreCoordinator.instance;
    final surface = coordinator.surfaceFor(trip);
    if (trip == null ||
        (surface != RestoredSurface.finding &&
            surface != RestoredSurface.waiting)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.rideAlreadyGoing)));
      unawaited(_loadQuotes());
      return;
    }
    AppLog.info('booking.opened_active_trip', extra: {'rideId': trip.rideId});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.rideAlreadyGoingOpened)),
    );
    final finding = surface == RestoredSurface.finding;
    if (finding) SheetCoordinator.instance.open(RideSheet.finding);
    try {
      await Navigator.push(
        context,
        RideStageTransition(
          coordinator.pageFor(trip),
          settings: RouteSettings(
            name: finding
                ? AppRoutes.findingDriver
                : AppRoutes.waitingForDriver,
          ),
        ),
      );
    } finally {
      if (finding) SheetCoordinator.instance.close(RideSheet.finding);
    }
  }

  @override
  Widget build(BuildContext context) {
    // v0.11.0 §21: outside every open zone there is nothing to book.
    if (_selection.notServed ||
        !RiderZones.serves(
          _pickupPosition.latitude,
          _pickupPosition.longitude,
        )) {
      return const NotHereView();
    }
    final media = MediaQuery.of(context);
    _media = media;
    _settledStop ??= _midValue(media);
    _syncTimePins();
    _scheduleNearbySync();
    final showLiveMap = _mapReady && !_mapParked;
    final minSheet = _minSheet(media);
    return PopScope(
      onPopInvokedWithResult: _onRoutePop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F5F1),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: minSheet,
              child: RepaintBoundary(
                child: showLiveMap
                    // The nearby cars redraw only the map while they glide.
                    ? ValueListenableBuilder<int>(
                        valueListenable: _carTick,
                        builder: (context, _, __) => CustomGoogleMap(
                          key: const ValueKey('select-ride-map'),
                          // Owner, live test 2026-10-26 (N6): the booking and trip maps stay
                          // flat; the route is read from above, never along a tilted horizon.
                          tiltWithZoom: false,
                          initialPosition: CameraPosition(
                            target: _pickupPosition,
                            zoom: 13.2,
                          ),
                          markers: {
                            // Owner round 2: the free cars around, under
                            // the route's pins.
                            ..._nearbyCarMarkers(),
                            if ((_pickupTimePin ?? _pickupPin) != null)
                              Marker(
                                markerId: const MarkerId('pickup'),
                                position: _pickupPosition,
                                icon: (_pickupTimePin ?? _pickupPin)!,
                                anchor: _pickupTimePin != null
                                    ? RouteTimeMarker.anchor
                                    : const Offset(0.5, 0.5),
                                zIndexInt: 2,
                              ),
                            if ((_destinationTimePin ?? _destinationPin) !=
                                null)
                              Marker(
                                markerId: const MarkerId('destination'),
                                position: widget.destinationPosition,
                                icon: (_destinationTimePin ?? _destinationPin)!,
                                anchor: _destinationTimePin != null
                                    ? RouteTimeMarker.anchor
                                    : const Offset(0.5, 0.5),
                                zIndexInt: 2,
                              ),
                            // UI-08: the stops are on the map while booking.
                            ...routeStopMarkers(_locatedStops),
                          },
                          polylines: styledRoute(
                            _roadRoutePoints != null
                                ? resolvedRoutePolyline(
                                    id: 'route',
                                    points: _roadRoutePoints!,
                                    color: RiderRouteStyle.color,
                                  )
                                : routePolyline(
                                    id: 'route',
                                    from: _pickupPosition,
                                    to: widget.destinationPosition,
                                    color: RiderRouteStyle.color,
                                  ),
                          ),
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          compassEnabled: false,
                          buildingsEnabled: false,
                          indoorViewEnabled: false,
                          tiltGesturesEnabled: false,
                          rotateGesturesEnabled: false,
                          onMapCreated: (controller) {
                            final nextMapReadyWatch = _nextMapReadyWatch;
                            if (nextMapReadyWatch != null) {
                              nextMapReadyWatch.stop();
                              RouteTransitionMetrics.nextMapReady(
                                nextMapReadyWatch.elapsed,
                              );
                              _nextMapReadyWatch = null;
                            }
                            _mapController = controller;
                            AppScope.instance.maps.attach(
                              controller,
                              owner: MapOwners.selectRide,
                            );
                            AppScope.instance.map.drawRoute(
                              'select',
                              GeoPoint(
                                _pickupPosition.latitude,
                                _pickupPosition.longitude,
                              ),
                              GeoPoint(
                                widget.destinationPosition.latitude,
                                widget.destinationPosition.longitude,
                              ),
                            );
                            AppScope.instance.map.upsertMarker(
                              'pickup',
                              GeoPoint(
                                _pickupPosition.latitude,
                                _pickupPosition.longitude,
                              ),
                            );
                            AppScope.instance.map.upsertMarker(
                              'destination',
                              GeoPoint(
                                widget.destinationPosition.latitude,
                                widget.destinationPosition.longitude,
                              ),
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) unawaited(_fitRoute(force: true));
                            });
                          },
                        ),
                      )
                    : const SelectRideRouteCanvas(),
              ),
            ),
            // Owner N2: no road route, only the direct line: say so.
            if (showLiveMap &&
                ApproximateRouteBadge.isStraight(_roadRoutePoints))
              Positioned(
                left: 12,
                bottom: minSheet + 12,
                child: const ApproximateRouteBadge(),
              ),
            // Owner round 2: the address bar slides up out of the way when
            // the sheet is fully up, and comes back as it goes down.
            AnimatedBuilder(
              animation: _sheetSlide,
              builder: (context, child) {
                final hide = ((_sheetSlide.value - 0.8) / 0.2).clamp(0.0, 1.0);
                return Positioned(
                  top: media.padding.top + 8 - hide * (media.padding.top + 90),
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    ignoring: hide > 0.5,
                    child: Opacity(opacity: 1 - hide, child: child),
                  ),
                );
              },
              child: PointerInterceptor(child: _searchBar()),
            ),
            Positioned.fill(
              child: DraggableScrollableSheet(
                key: const ValueKey('select-ride-sheet'),
                controller: _sheetController,
                initialChildSize: _fractionOf(_midSheet(media), media),
                minChildSize: _fractionOf(minSheet, media),
                maxChildSize: _fractionOf(_maxSheet(media), media),
                snap: true,
                snapSizes: [_fractionOf(_midSheet(media), media)],
                snapAnimationDuration: MoveraMotion.of(
                  context,
                  MoveraDurations.large,
                ),
                builder: (context, scroll) => PointerInterceptor(
                  child: Material(
                    color: Colors.white,
                    elevation: 18,
                    shadowColor: const Color(
                      0xFF162C36,
                    ).withValues(alpha: 0.16),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) => _onSheetScroll(n, media),
                      child: _sheetBody(media, scroll),
                    ),
                  ),
                ),
              ),
            ),
            // The payment block and Book button stay put while the sheet moves.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // Owner round 3: the payment block moves the sheet too.
              child: PointerInterceptor(
                child: GestureDetector(
                  key: const ValueKey('select-ride-footer-drag'),
                  onVerticalDragUpdate: (d) => _onHeaderDragUpdate(d, media),
                  onVerticalDragEnd: (d) => _onHeaderDragEnd(d, media),
                  child: _footer(media.padding.bottom),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [child] grows in from the top and fades in as [detail] goes 0 → 1;
  /// only this wrapper follows the sheet, [child] is built once.
  static Widget _reveal(Animation<double> detail, Widget child) {
    return AnimatedBuilder(
      animation: detail,
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          heightFactor: detail.value,
          child: child,
        ),
      ),
      child: FadeTransition(opacity: detail, child: child),
    );
  }

  static const Color _teal = Color(0xFF1DA298);

  /// The promotion's text colour: teal dark enough to read on white.
  static const Color _tealText = Color(0xFF117C74);

  /// Add card for the generic Card row (no saved card yet): the new card
  /// becomes the chosen method. Null: no card was added.
  Future<SavedCard?> _addCardFirst() async {
    final card = await AddCardPage.open(context);
    if (card == null || !mounted) return null;
    final index = _selection.payments().indexWhere(
      (p) => p.brand == card.methodBrand,
    );
    if (index < 0) return null;
    setState(() => _selection.selectPayment(index));
    return card;
  }

  /// The fixed bottom block: one thin payment line, then Book.
  Widget _footer(double bottomInset) {
    final selected = _selectedRideOrNull;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 6, 16, 12 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _line)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF162C36).withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // LOW 12: the booking summary says the free change / cancel rule.
          if (_scheduledPickup != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                ReservationFormat.freeRule(
                  _zoneConfig?.freeChangeBeforeMin ??
                      RiderAppConfig.defaultFreeChangeBeforeMin,
                ),
                key: const ValueKey<String>('select-ride-free-rule'),
                textAlign: TextAlign.center,
                style: _text(11.5, weight: FontWeight.w500, color: _muted),
              ),
            ),
          _paymentButton(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: _cta,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _bookingInFlight ? null : _book,
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 54,
                      child: Center(
                        child: Text(
                          selected == null
                              ? context.l10n.noRidesAvailable
                              : _selection.bookingMode.ctaLabel(
                                  rideNameFor(selected.name),
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(
                            16,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // UI-5: the icon-only button has a name for screen readers.
              Semantics(
                button: true,
                label: context.l10n.bookNowOrLater,
                child: Material(
                  color: _cta,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _showBookingPicker,
                    child: const SizedBox(
                      width: 54,
                      height: 54,
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _brandMark(String brand) {
    Widget logo;
    Color background = Colors.white;
    final savedCard = _selection.savedCardFor(brand);
    if (savedCard != null) {
      logo = CardBrandLabel(savedCard.brand);
    } else if (brand == 'apple' || brand == 'cards') {
      // Owner rules: no other company's logo (Apple Pay is named as text).
      logo = const Icon(
        Icons.credit_card_rounded,
        color: Color(0xFF11181D),
        size: 22,
      );
    } else if (brand == 'cash') {
      background = const Color(0xFFEEF6F0);
      logo = const Icon(
        Icons.directions_car_filled_outlined,
        color: Color(0xFF1F7A4D),
        size: 20,
      );
    } else {
      logo = Image.asset(
        excludeFromSemantics: true,
        AppAssets.wallet,
        color: _ink,
        fit: BoxFit.contain,
      );
    }
    return Container(
      width: 42,
      height: 38,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: background == Colors.white ? _line : background,
        ),
      ),
      child: logo,
    );
  }
}
