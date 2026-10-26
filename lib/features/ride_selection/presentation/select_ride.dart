import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';

export 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

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

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _RideOption {
  const _RideOption({
    required this.id,
    required this.image,
    required this.name,
    required this.note,
    required this.arrival,
    required this.etaMin,
    required this.price,
    required this.seats,
    this.badge,
    this.glyph,
    this.glyphKey,
    this.currency = Money.defaultCurrency,
  });

  final String id;
  final String image;
  final String name;
  final String note;
  final String arrival;
  final int etaMin;
  final double price;

  /// The list price's currency ([RideCatalogItem.currency]).
  final String currency;
  final int seats;
  final String? badge;
  final IconData? glyph;

  /// The catalog's glyph key ([RidePicture] picks what stands beside the car).
  final String? glyphKey;
}

class _PaymentOption {
  const _PaymentOption({
    required this.brand,
    required this.name,
    required this.detail,
  });

  final String brand;
  final String name;
  final String detail;
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
        // rider-77: the built-in notes and badges in the rider's language.
        note: rideNoteFor(ride.note),
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

  /// rider-r4-29: [requoteSpent] (a booking flow just released the lock)
  /// prices again right away when a quote ran out meanwhile: the expiry
  /// timer skipped it while the flow was open.
  void _scheduleExpiryRequote({bool requoteSpent = false}) {
    _expiryRequote?.cancel();
    _expiryRequote = null;
    final spent = _selection.discardExpiredQuotes();
    if (spent && requoteSpent) {
      unawaited(_loadQuotes());
      return;
    }
    final next = _selection.nextQuoteExpiry;
    if (next == null) return;
    final wait = next.difference(ServerClock.now());
    // A quote that arrived already spent is not chased in a loop; Book
    // refreshes it.
    if (wait.isNegative) return;
    _expiryRequote = Timer(wait, _onQuotesExpired);
  }

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

  /// Set location moved the pin: price [ride] again from that exact point
  /// and adopt the quote, so Confirm books the price shown there. Goes
  /// through the selection, which keeps only the latest pin's answer.
  Future<SetPickupFare?> _requoteFromPin(_RideOption ride, LatLng pin) async {
    final stops = await _routeStops();
    final pending = _selection.quoteFromPin(
      stops: stops,
      rideId: ride.id,
      distanceMeters: straightLineMeters(pin, widget.destinationPosition),
      pickup: coordinatePickupAddress(pin),
      destination: widget.destinationAddress,
      pickupPoint: _geoPoint(pin),
      destinationPoint: _geoPoint(widget.destinationPosition),
    );
    _pinQuote = pending;
    final quote = await pending;
    if (quote == null || !mounted) return null;
    _pinQuoteAdopted = true;
    return _fareFor(quote);
  }

  SetPickupFare _fareFor(RideQuote quote) {
    final total = Money(quote.totalMinor, quote.currency).major;
    final discount = Money(quote.discountMinor, quote.currency).major;
    return SetPickupFare(
      totalKr: total,
      discountKr: discount,
      promotionPercent: discount > 0 ? _promotion?.percentOff : null,
      walletKr: Money(
        _selection.walletSplitFor(quote.totalMinor).walletMinor,
        quote.currency,
      ).major,
      currency: quote.currency,
    );
  }

  /// A quote that is still good for the next [_quoteMargin], or null.
  static const _quoteMargin = Duration(seconds: 10);

  ({RideQuote quote, double price})? _bookableQuote(String rideId) {
    final soon = ServerClock.now().add(_quoteMargin);
    final price = _selection.authoritativePriceFor(rideId, now: soon);
    final quote = _selection.authoritativeQuotes[rideId];
    if (price == null || quote == null) return null;
    // rider-79: a quote priced at another point than the confirmed pickup
    // (a category not re-priced after the pin moved, or a pin re-quote
    // that failed) is priced again from it.
    if (!_selection.quoteIsAt(rideId, _geoPoint(_pickupPosition))) {
      return null;
    }
    return (quote: quote, price: price);
  }

  /// After the steps the rider controls (Add card, Set pickup): the quote
  /// to book is the one the selection holds now, never the one captured
  /// before them (RIDE-1). A quote that expired meanwhile is refreshed in
  /// place from the confirmed pickup (RIDE-2). Returns null when no price
  /// can be had.
  Future<({RideQuote quote, double price})?> _quoteAfterPickup(
    _RideOption ride,
  ) async {
    final pending = _pinQuote;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed pin quote keeps the price shown.
      }
    }
    if (!mounted) return null;
    final current = _bookableQuote(ride.id);
    if (current != null) return current;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.refreshingPrice)));
    try {
      final stops = await _routeStops();
      await _selection.quoteFromPin(
        stops: stops,
        rideId: ride.id,
        distanceMeters: straightLineMeters(
          _pickupPosition,
          widget.destinationPosition,
        ),
        pickup: _pickupAddress,
        destination: widget.destinationAddress,
        pickupPoint: _geoPoint(_pickupPosition),
        destinationPoint: _geoPoint(widget.destinationPosition),
      );
    } catch (_) {
      // Reported below.
    }
    if (!mounted) return null;
    return _bookableQuote(ride.id);
  }

  /// The price to book differs from the one Set pickup showed: the rider
  /// agrees to the new one first.
  Future<bool> _acceptNewPrice(double shown, double next) async {
    // rider-r4-33: the dialog opens on any öre difference, so it shows the
    // öre ("254,20 kr, was 254,40 kr"), never two equal whole kronor.
    String exact(double value) => formatMoney(_selection.moneyOf(value));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('select-ride-price-updated'),
        title: Text(
          context.l10n.priceUpdated,
          style: _text(18, weight: FontWeight.w600),
        ),
        content: Text(
          context.l10n.priceUpdatedBody(exact(next), exact(shown)),
          style: _text(14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.notNow),
          ),
          FilledButton(
            key: const ValueKey('select-ride-price-accept'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.bookForPrice(exact(next))),
          ),
        ],
      ),
    );
    return accepted == true;
  }

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

  /// The cars are asked for while the live map shows this screen, the app is
  /// in front and no booking step covers it; they follow the pickup.
  void _syncNearbyWatch() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final visible =
        _mapReady &&
        !_mapParked &&
        !_bookingInFlight &&
        _appInForeground &&
        (route?.isCurrent ?? true);
    if (visible) {
      _nearby.watch(
        GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
      );
    } else {
      _nearby.pause();
    }
  }

  bool _nearbySyncScheduled = false;

  /// [_syncNearbyWatch] after this frame: build decides what shows, and the
  /// controller must not notify while the tree builds.
  void _scheduleNearbySync() {
    if (_nearbySyncScheduled) return;
    _nearbySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nearbySyncScheduled = false;
      _syncNearbyWatch();
    });
  }

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

  /// The nearby cars as map markers, under the route's pins.
  Set<Marker> _nearbyCarMarkers() {
    final icons = _carIcons;
    if (icons == null) return const <Marker>{};
    return {
      for (final car in _nearby.frames())
        () {
          final pose = NearbyCarMarker.pose(car.heading);
          return Marker(
            markerId: MarkerId('nearby-car-${car.key}'),
            position: LatLng(car.latitude, car.longitude),
            icon: pose.mirrored ? icons.left : icons.right,
            rotation: pose.rotation,
            anchor: const Offset(0.5, 0.6),
            zIndexInt: 1,
            consumeTapEvents: true,
          );
        }(),
    };
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

  _RideOption? get _selectedRideOrNull {
    final id = _selection.selectedRideId;
    for (final ride in _allRides) {
      if (ride.id == id) return ride;
    }
    return null;
  }

  double _priceFor(_RideOption ride) =>
      _selection.priceFor(ride.id, ride.price);

  /// Whether [ride] has a price in this pickup's currency yet (a list price
  /// in kronor is never shown for a pickup priced in euros or dinars).
  bool _hasPrice(_RideOption ride) =>
      _selection.hasPriceFor(ride.id, catalogCurrency: ride.currency);

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
  };

  List<_RideOption> get _visibleRides {
    final rides = _allRides;
    return [
      for (final ride in rides)
        if (!_premiumGroup.contains(ride.id)) ride,
      for (final ride in rides)
        if (_premiumGroup.contains(ride.id)) ride,
    ];
  }

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

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  String _compactAddress(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return context.l10n.unknownPlace;
    return shortenPlace(cleaned);
  }

  /// [value] whole units of this pickup's currency, as the fare is shown.
  String _kr(double value) =>
      formatMoney(_selection.moneyOf(value), whole: true);

  /// UI-10: a price never takes more than 30% of the screen width; at large
  /// text it shrinks to fit instead of pushing the ride row off screen.
  Widget _fitPrice(BuildContext context, Widget price) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.3,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: price,
    ),
  );

  static const double _rowHeight = 78;

  double _footerHeight(MediaQueryData media) => 134 + media.padding.bottom;

  /// The sheet's fixed top: the handle (22), the promotion line or the
  /// title, and the line under them.
  static const double _titleHeight = 42;
  static const double _promotionLineHeight = 44;

  double _headerHeight() =>
      22 + (_promotion == null ? _titleHeight : _promotionLineHeight) + 1;

  /// Low stop: only the chosen ride above the payment block.
  double _minSheet(MediaQueryData media) =>
      (_headerHeight() + _rowHeight + 12 + _footerHeight(media)).clamp(
        240.0,
        math.max(240.0, media.size.height * 0.62),
      );

  double _maxSheet(MediaQueryData media) =>
      math.max(selectRideMaxSheetHeight(media), _minSheet(media) + 120);

  /// Middle stop: about three short rows.
  double _midSheet(MediaQueryData media) =>
      math.min(_minSheet(media) + _rowHeight * 2 + 4, _maxSheet(media) - 60);

  double _midValue(MediaQueryData media) {
    final range = _maxSheet(media) - _minSheet(media);
    if (range <= 0) return 1;
    return ((_midSheet(media) - _minSheet(media)) / range).clamp(0.0, 1.0);
  }

  /// The sheet's height as a fraction of the screen, which is how the
  /// draggable sheet measures its stops.
  double _fractionOf(double pixels, MediaQueryData media) =>
      (pixels / media.size.height).clamp(0.0, 1.0);

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

  void _snapSheetTo(double target) {
    final media = _media;
    if (media == null || !_sheetController.isAttached) return;
    _fitSlideTarget = target;
    unawaited(_fitRoute());
    final minSheet = _minSheet(media);
    final pixels = minSheet + (_maxSheet(media) - minSheet) * target;
    unawaited(
      _sheetController.animateTo(
        _fractionOf(pixels, media),
        duration: MoveraMotion.of(context, MoveraDurations.large),
        curve: MoveraCurves.snap,
      ),
    );
  }

  /// The fixed header is outside the list, so its drags move the sheet by
  /// hand and settle on the nearest stop (a fling moves one stop).
  void _onHeaderDragUpdate(DragUpdateDetails details, MediaQueryData media) {
    if (!_sheetController.isAttached) return;
    _sheetDragging = true;
    final pixels = (_sheetController.pixels - details.primaryDelta!).clamp(
      _minSheet(media),
      _maxSheet(media),
    );
    _sheetController.jumpTo(_fractionOf(pixels, media));
  }

  void _onHeaderDragEnd(DragEndDetails details, MediaQueryData media) {
    _sheetDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetSlide.value;
    final stops = <double>[0, _midValue(media), 1];
    double target;
    if (velocity < -480) {
      target = stops.firstWhere((s) => s > current + 0.01, orElse: () => 1);
    } else if (velocity > 480) {
      target = stops.lastWhere((s) => s < current - 0.01, orElse: () => 0);
    } else {
      target = stops.reduce(
        (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
      );
    }
    _snapSheetTo(target);
  }

  void _toggleSheet(MediaQueryData media) {
    _snapSheetTo(_sheetSlide.value > 0.98 ? _midValue(media) : 1);
  }

  /// A tick when the sheet lands on a new stop, and the route re-framed
  /// above it.
  bool _onSheetScroll(ScrollNotification n, MediaQueryData media) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _sheetDragging = true;
    }
    if (n is! ScrollEndNotification) return false;
    if (_sheetDragging) {
      _sheetDragging = false;
      _syncSheetOverlay();
    }
    final v = _sheetSlide.value;
    final stops = <double>[0, _midValue(media), 1];
    final nearest = stops.reduce(
      (a, b) => (a - v).abs() <= (b - v).abs() ? a : b,
    );
    if ((nearest - v).abs() > 0.02 || nearest == _settledStop) return false;
    _settledStop = nearest;
    _fitSlideTarget = null;
    HapticFeedback.selectionClick();
    _fits.settled();
    return false;
  }

  int _tripMinutes() => estimatedTripMinutes(
    GeoPoint(_pickupPosition.latitude, _pickupPosition.longitude),
    GeoPoint(
      widget.destinationPosition.latitude,
      widget.destinationPosition.longitude,
    ),
  );

  /// The chosen pickup time of a scheduled ride, or null for "now".
  DateTime? get _scheduledPickup =>
      _selection.isScheduled ? _selection.scheduledFor : null;

  /// "Arrive 23:48" for [ride]: driver to pickup, then the trip. A scheduled
  /// ride is picked up at its chosen time, so only the trip counts.
  String _arrivalFor(_RideOption ride) {
    final scheduled = _scheduledPickup;
    if (scheduled != null) {
      // rider-r5-9: the trip's real time in the pickup zone (as the date
      // picker estimates it), so it holds across a clock change.
      return clockTime(
        ZoneClock.wallAfter(
          _pickupSchedule.timeZone,
          scheduled,
          Duration(minutes: _tripMinutes()),
        ),
      );
    }
    return clockTime(
      DateTime.now().add(Duration(minutes: ride.etaMin + _tripMinutes())),
    );
  }

  /// Row line under the ride name: "23:48 · 8 min" now, or
  /// "Pickup 06:55 · Arrive 07:15" for a scheduled ride.
  String _timesFor(_RideOption ride) {
    final scheduled = _scheduledPickup;
    if (scheduled != null) {
      return context.l10n.pickupAtArriveAt(
        clockTime(scheduled),
        _arrivalFor(ride),
      );
    }
    // Owner round 2, like the other ride apps: "07:14 · 8 min" (when you
    // arrive · how far the car is).
    return context.l10n.arriveEtaMin(_arrivalFor(ride), '${ride.etaMin}');
  }

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

  /// Frames the route above the sheet. [force] flies an unchanged framing
  /// too (a newly created map starts from its own camera).
  Future<void> _fitRoute({bool force = false}) => _fits.fit(force: force);

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

  /// rider-74: the wallet alone cannot pay a fare above its balance. Says
  /// so and returns true when the wallet is the chosen method for it.
  bool _walletCannotPay(double priceKr) {
    if (_selection.selectedPaymentItem()?.brand != 'wallet' ||
        _selection.walletCovers(priceKr)) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.walletTooLowChooseAnother)),
    );
    return true;
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

  /// Phase 114/136: a return ride arrives with a prefilled pickup
  /// (origin + 3 h) that nobody validated. Before it can be booked it must
  /// satisfy the same [StockholmSchedule] rules the scheduling picker
  /// enforces (30-minute lead, 5-minute slots) — lead time alone isn't
  /// enough, since a prefill can be legal but still off-grid (e.g. 21:07).
  /// The main Schedule flow already picked its time in that picker, so it is
  /// not re-checked here.
  bool get _returnTimeNeedsPicker {
    if (widget.parentReservationId == null) return false;
    final when = _selection.scheduledFor;
    return when != null &&
        (!_pickupSchedule.isLegalPickup(when) ||
            !StockholmSchedule.isOnGrid(when) ||
            // rider-r4-10: nor past the zone's reservation horizon.
            ZoneClock.wall(when).isAfter(
              _pickupSchedule.latestPickup(_pickupSchedule.horizonDays),
            ));
  }

  /// Q9: Book later times are the pickup zone's wall-clock time.
  PickupSchedule get _pickupSchedule => PickupSchedule.at(
    _pickupPosition.latitude,
    _pickupPosition.longitude,
    config: _zoneConfig,
  );

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

  @override
  Widget build(BuildContext context) {
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

  /// The sheet's content. Built with the screen, not with the sheet's
  /// position: the parts that follow the position (the list fading in
  /// above the low stop, the descriptions growing in towards the full stop,
  /// the handle's label and the chosen ride shown at the low stop) each
  /// listen to [_sheetSlide] on their own, so a drag tick rebuilds no row.
  /// Owner (iPhone PWA): rebuilding every row, its fonts and its times on
  /// each tick of the drag was most of the frame
  /// (docs/select-ride-sheet-performance.md).
  Widget _sheetBody(MediaQueryData media, ScrollController scroll) {
    final mid = _midValue(media);
    // 0 at the low stop → 1 at the middle: the other rides come in.
    final listReveal = _sheetSlide.drive(_ListReveal(mid));
    // 0 at the middle → 1 at full: descriptions and badges.
    final detail = _sheetSlide.drive(_DetailReveal(mid));
    final selectedRide = _selectedRideOrNull;
    final promotion = _promotion;
    final entries = _listEntries;
    return Column(
      children: [
        // Title, promotion and filters stay put while the rides scroll
        // under them; dragging here still moves the sheet.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) =>
              _onHeaderDragUpdate(details, media),
          onVerticalDragEnd: (details) => _onHeaderDragEnd(details, media),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _sheetSlide,
                builder: (context, child) => Semantics(
                  button: true,
                  label: _sheetSlide.value > 0.98
                      ? context.l10n.showFewerRides
                      : context.l10n.showAllRides,
                  child: child,
                ),
                child: GestureDetector(
                  key: const ValueKey('select-ride-sheet-handle'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSheet(media),
                  child: SizedBox(
                    width: double.infinity,
                    height: 22,
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Owner round 2: a teal "promotion applied" line like the
              // other ride apps; without one, the title.
              if (promotion != null)
                _promotionLine(promotion)
              else
                SizedBox(
                  height: _titleHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.l10n.chooseYourRide,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          20,
                          weight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1, thickness: 1, color: _line),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              FadeTransition(
                opacity: listReveal,
                child: ListView.builder(
                  key: const ValueKey('select-ride-list'),
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(
                    14,
                    2,
                    14,
                    _footerHeight(media) + 8,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final ride = entry.ride;
                    if (ride != null) {
                      return _rideTile(ride, detail: detail);
                    }
                    return _groupHeading(
                      entry.heading!,
                      detail: detail,
                      first: index == 0,
                    );
                  },
                ),
              ),
              // At the low stop only the chosen ride shows.
              if (selectedRide != null)
                AnimatedBuilder(
                  animation: listReveal,
                  builder: (context, child) {
                    final reveal = listReveal.value;
                    return Positioned(
                      left: 14,
                      right: 14,
                      top: 2,
                      child: Offstage(
                        offstage: reveal >= 1,
                        child: IgnorePointer(
                          ignoring: reveal > 0.5,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: FadeTransition(
                    opacity: ReverseAnimation(listReveal),
                    // Owner round 3: a swipe on the chosen ride moves the
                    // sheet too.
                    child: GestureDetector(
                      key: const ValueKey('select-ride-low-row-drag'),
                      onVerticalDragUpdate: (d) =>
                          _onHeaderDragUpdate(d, media),
                      onVerticalDragEnd: (d) => _onHeaderDragEnd(d, media),
                      child: ColoredBox(
                        color: Colors.white,
                        child: _rideTile(
                          selectedRide,
                          detail: const AlwaysStoppedAnimation<double>(0),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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

  Widget _searchBar() {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF162C36).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: _ink),
              tooltip: context.l10n.back,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _compactAddress(widget.destinationAddress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(15, weight: FontWeight.w500),
                  ),
                  // UI-08: the stops the price includes.
                  if (viaStopsLine(_locatedStops.map((s) => s.address))
                      case final via?)
                    Text(
                      via,
                      key: const ValueKey('select-ride-via-stops'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(12, color: _muted),
                    ),
                  if (_stopsNotice case final notice?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        notice,
                        key: const ValueKey('select-ride-stops-left-out'),
                        style: _text(
                          12,
                          weight: FontWeight.w500,
                          color: const Color(0xFFB42318),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_stopsRetry)
              TextButton(
                key: const ValueKey('select-ride-stops-retry'),
                onPressed: _retryStops,
                child: Text(
                  context.l10n.tryAgain,
                  style: _text(13, weight: FontWeight.w600, color: _ink),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  static const Color _teal = Color(0xFF1DA298);

  /// The promotion's text colour: teal dark enough to read on white.
  static const Color _tealText = Color(0xFF117C74);

  /// "30 % promotion applied ⓘ" in teal; tap for the details.
  Widget _promotionLine(RiderPromotion promotion) {
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('select-ride-promotion-line'),
        onTap: () => _openPromotionDetails(promotion),
        child: SizedBox(
          height: _promotionLineHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_offer_rounded, size: 17, color: _teal),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    context.l10n.promotionApplied('${promotion.percentOff}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      15.5,
                      weight: FontWeight.w600,
                      color: _tealText,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: _tealText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Rides for you" / "Premium": shown once the sheet is fully up.
  Widget _groupHeading(
    String text, {
    required Animation<double> detail,
    required bool first,
  }) {
    return _reveal(
      detail,
      Padding(
        padding: EdgeInsets.fromLTRB(8, first ? 10 : 18, 8, 8),
        child: Semantics(
          header: true,
          child: Text(
            text,
            key: ValueKey('select-ride-heading-$text'),
            style: _text(19, weight: FontWeight.w700, letterSpacing: -0.3),
          ),
        ),
      ),
    );
  }

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

  /// Every category's price before and after the promotion, from the quotes
  /// we have right now; categories still waiting for a quote are left out.
  Map<String, PromotionPrice> _promotionPrices() {
    final prices = <String, PromotionPrice>{};
    for (final ride in _allRides) {
      final quote = _selection.authoritativeQuotes[ride.id];
      if (quote == null) continue;
      final discounted = Money(quote.totalMinor, quote.currency).major;
      prices[ride.id] = (
        original: Money(
          quote.totalMinor + quote.discountMinor,
          quote.currency,
        ).major,
        discounted: discounted,
      );
    }
    return prices;
  }

  /// The promo ticket opens the details with this screen's current prices.
  Future<void> _openPromotionDetails(RiderPromotion promotion) {
    return PromotionDetailsSheet.open(
      context,
      promotion,
      categories: [
        for (final ride in _allRides)
          PromotionCategory(id: ride.id, name: ride.name),
      ],
      prices: _promotionPrices(),
      currency: _selection.currency,
    );
  }

  /// The quote's discount for [ride], in kr (0 when none).
  double _discountFor(_RideOption ride) {
    final quote = _selection.authoritativeQuotes[ride.id];
    if (quote == null || quote.discountMinor <= 0) return 0;
    return Money(quote.discountMinor, quote.currency).major;
  }

  Widget _rideTile(_RideOption ride, {required Animation<double> detail}) {
    final selected = ride.id == _selection.selectedRideId;
    final price = _priceFor(ride);
    final discount = _discountFor(ride);
    // rider-u191: the category that will be booked is announced.
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectRide(ride.id),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: _rowHeight - 4),
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _selectedOutline : Colors.transparent,
                  width: 2,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF162C36,
                          ).withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // Owner round 2: the white car like the other ride
                  // apps, with what tells the type apart beside it.
                  RidePicture(
                    rideId: ride.id,
                    glyph: ride.glyphKey,
                    glyphIcon: ride.glyph,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    flex: 5,
                                    child: Text(
                                      ride.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _text(16, weight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Icon(
                                    Icons.person_rounded,
                                    size: 14,
                                    color: _ink,
                                  ),
                                  Flexible(
                                    child: Text(
                                      '${ride.seats}',
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: _text(13, color: _ink),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (discount > 0) ...[
                              const Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.local_offer_rounded,
                                  size: 14,
                                  color: _teal,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            _fitPrice(
                              context,
                              Text(
                                // No quote yet for a pickup outside the
                                // list's currency: no price, not a wrong one.
                                _hasPrice(ride) ? _kr(price) : '…',
                                style: _text(16, weight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _timesFor(ride),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  13.5,
                                  color: _ink,
                                  weight: FontWeight.w400,
                                ),
                              ),
                            ),
                            if (discount > 0)
                              _fitPrice(
                                context,
                                Text(
                                  _kr(price + discount),
                                  // UI-6: was 0xFF8A9399 (3.13:1 on white).
                                  style:
                                      _text(
                                        12,
                                        color: MoveraTokens.subtleOnFill,
                                      ).copyWith(
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        // rider-80: no split worked out from a list price
                        // the tile itself does not show ('…').
                        if (selected &&
                            _hasPrice(ride) &&
                            _selection
                                .walletSplitFor(
                                  _selection.moneyOf(price).amountMinor,
                                )
                                .usesWallet)
                          _walletLine(price),
                        if (selected && _walletOtherCurrency)
                          _walletCurrencyNote(),
                        // Description and badge come in as the sheet opens
                        // fully.
                        _reveal(
                          detail,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                ride.note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  12.5,
                                  color: _muted,
                                  weight: FontWeight.w400,
                                ),
                              ),
                              if (ride.badge != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected ? _accent : _accentSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ride.badge!,
                                    style: _text(
                                      9.5,
                                      weight: FontWeight.w700,
                                      color: selected ? Colors.white : _accent,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Under the selected ride: what the wallet covers and what is left to
  /// pay. The list price itself stays the real fare.
  /// The rider has wallet money and wants it used, but it is in another
  /// currency than this trip: it is not used (no conversion).
  bool get _walletOtherCurrency =>
      _selection.useWalletFirst &&
      _selection.walletBalance > 0 &&
      !_selection.walletMatchesTrip &&
      _selection.walletEnabled;

  Widget _walletCurrencyNote() => Padding(
    key: const ValueKey('select-ride-wallet-currency-note'),
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      context.l10n.walletWrongCurrency(
        _selection.walletCurrency,
        _selection.currency,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _text(12, color: _muted),
    ),
  );

  Widget _walletLine(double price) {
    final split = _selection.walletSplitFor(
      _selection.moneyOf(price).amountMinor,
    );
    const green = Color(0xFF079A60);
    return Padding(
      key: const ValueKey('select-ride-wallet-line'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 13,
            color: green,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: split.paidByWallet
                ? Text(
                    context.l10n.paidByWallet,
                    style: _text(12, weight: FontWeight.w600, color: green),
                  )
                : Text(
                    context.l10n.walletSplit(
                      split.walletLabel,
                      split.remainderLabel,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(12, weight: FontWeight.w500, color: green),
                  ),
          ),
        ],
      ),
    );
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
                              : _selection.bookingMode.ctaLabel(selected.name),
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

  Widget _paymentButton() {
    final item = _selection.selectedPaymentItem();
    final method = item == null
        ? _PaymentOption(brand: 'cash', name: context.l10n.payCash, detail: '')
        : _PaymentOption(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
          );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        // rider-u189: Set pickup changes the method of a booking under way.
        onTap: _bookingInFlight ? null : _showPaymentPicker,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              const SizedBox(width: 4),
              _brandMark(method.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            paymentNameFor(method.brand, method.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(15, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      paymentDetailFor(method.brand, method.detail),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        11.5,
                        weight: FontWeight.w500,
                        color: method.brand == 'cash' ? _accent : _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _ink, size: 22),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _accent : _line),
        ),
        child: Row(
          children: [
            Icon(icon, color: _ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _text(16, weight: FontWeight.w600)),
                  Text(subtitle, style: _text(13, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandMark(String brand) {
    Widget logo;
    Color background = Colors.white;
    final savedCard = _selection.savedCardFor(brand);
    if (savedCard != null) {
      logo = Image.asset(
        excludeFromSemantics: true,
        savedCard.brand == 'mastercard' ? AppAssets.mastercard : AppAssets.visa,
        fit: BoxFit.contain,
      );
    } else if (brand == 'apple') {
      logo = SvgPicture.asset(
        'assets/images/apple_pay_brand.svg',
        fit: BoxFit.contain,
      );
    } else if (brand == 'google') {
      logo = Transform.scale(
        scale: 1.18,
        child: Image.asset(
          excludeFromSemantics: true,
          'assets/images/google_pay_brand.png',
          fit: BoxFit.contain,
        ),
      );
    } else if (brand == 'cards') {
      logo = Row(
        children: [
          Expanded(
            child: Image.asset(
              excludeFromSemantics: true,
              AppAssets.visa,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Image.asset(
              excludeFromSemantics: true,
              AppAssets.mastercard,
              fit: BoxFit.contain,
            ),
          ),
        ],
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

/// 0 at the low stop → 1 at the middle stop ([mid] on the slide): the other
/// rides come in.
class _ListReveal extends Animatable<double> {
  const _ListReveal(this.mid);

  final double mid;

  @override
  double transform(double t) => mid <= 0 ? 1.0 : (t / mid).clamp(0.0, 1.0);
}

/// 0 at the middle stop → 1 at full: descriptions and badges.
class _DetailReveal extends Animatable<double> {
  const _DetailReveal(this.mid);

  final double mid;

  @override
  double transform(double t) => mid >= 1
      ? 0.0
      : Curves.easeOutCubic.transform(((t - mid) / (1 - mid)).clamp(0.0, 1.0));
}
