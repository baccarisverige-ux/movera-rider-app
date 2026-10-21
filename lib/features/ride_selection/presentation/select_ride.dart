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
import 'package:movera_rider/features/promotions/presentation/promotion_ticket.dart';
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
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/application/scheduled_ride_checkout.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_filter.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/ride_selection/presentation/widgets/select_ride_route_canvas.dart';
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
      initialScheduledFor: origin.pickupWallTime.add(
        const Duration(hours: 3),
      ),
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
    with SingleTickerProviderStateMixin {
  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFE7EBEE);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _accentSoft = Color(0xFFEAF2F8);
  static const Color _field = Color(0xFFF6F5F1);
  static const Color _cta = Color(0xFF11181D);

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

  SelectRideFilter _filter = SelectRideFilter.recommended;
  late final bool _ownsSelection = widget.selection == null;
  late final RideSelectionController _selection =
      widget.selection ??
      RideSelectionController(
        bookingMode: widget.bookingMode,
        lockBookingMode: widget.lockBookingMode,
        paymentStore: AppScope.instance.defaultPayment,
      );
  bool _mapReady = false;
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

  /// The rider's promotion (admin panel), shown on top of the list.
  RiderPromotion? get _promotion => AppScope.instance.promotion.active;

  ReservationController get _reservations =>
      widget.reservations ?? AppScope.instance.reservations;

  @override
  void initState() {
    super.initState();
    _pickupAddress = widget.pickupAddress;
    _pickupPosition = widget.pickupPosition;
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
        List.generate(ids.length, (i) => ids[i] == _catalogIds[i])
            .every((same) => same);
    setState(() {
      _catalogIds = ids;
      _selection.ensureCatalogSelection();
    });
    if (!sameIds) unawaited(_loadQuotes());
  }

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

  void _scheduleExpiryRequote() {
    _expiryRequote?.cancel();
    _expiryRequote = null;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.refreshingPrice)),
    );
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('select-ride-price-updated'),
        title: Text(context.l10n.priceUpdated, style: _text(18, weight: FontWeight.w600)),
        content: Text(
          context.l10n.priceUpdatedBody(_kr(next), _kr(shown)),
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
            child: Text(context.l10n.bookForPrice(_kr(next))),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  @override
  void dispose() {
    _expiryRequote?.cancel();
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

  void _syncSheetOverlay() {
    final cover = _sheetSlide.value > 0.05;
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

  List<_RideOption> get _visibleRides => orderRidesForFilter(
    _allRides,
    _filter,
    etaMin: (ride) => ride.etaMin,
    price: (ride) => ride.price,
  );

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

  double _headerHeight() =>
      64 + (_promotion == null ? 0 : PromotionTicket.height + 10);

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

  void _snapSheetTo(double target) {
    final media = _media;
    if (media == null || !_sheetController.isAttached) return;
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
    final pixels = (_sheetController.pixels - details.primaryDelta!).clamp(
      _minSheet(media),
      _maxSheet(media),
    );
    _sheetController.jumpTo(_fractionOf(pixels, media));
  }

  void _onHeaderDragEnd(DragEndDetails details, MediaQueryData media) {
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
    if (n is! ScrollEndNotification) return false;
    final v = _sheetSlide.value;
    final stops = <double>[0, _midValue(media), 1];
    final nearest = stops.reduce(
      (a, b) => (a - v).abs() <= (b - v).abs() ? a : b,
    );
    if ((nearest - v).abs() > 0.02 || nearest == _settledStop) return false;
    _settledStop = nearest;
    HapticFeedback.selectionClick();
    unawaited(_fitRoute());
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
      return clockTime(scheduled.add(Duration(minutes: _tripMinutes())));
    }
    return clockTime(
      DateTime.now().add(Duration(minutes: ride.etaMin + _tripMinutes())),
    );
  }

  /// Row line under the ride name: "8 min · Arrive 23:48" now, or
  /// "Pickup 06:55 · Arrive 07:15" for a scheduled ride.
  String _timesFor(_RideOption ride) {
    final scheduled = _scheduledPickup;
    if (scheduled != null) {
      return context.l10n.pickupAtArriveAt(clockTime(scheduled), _arrivalFor(ride));
    }
    return context.l10n.etaMinArriveAt('${ride.etaMin}', _arrivalFor(ride));
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

  Future<void> _fitRoute() async {
    if (!mounted) return;
    final pickup = _pickupPosition;
    final destination = widget.destinationPosition;
    final media = MediaQuery.of(context);
    final samePoint =
        (pickup.latitude - destination.latitude).abs() < 0.00008 &&
        (pickup.longitude - destination.longitude).abs() < 0.00008;
    try {
      if (samePoint) {
        await AppScope.instance.maps.animateCamera(
          GeoPoint(pickup.latitude, pickup.longitude),
          zoom: 14.4,
        );
        return;
      }
      // D-009: the map sits behind the (initially expanded) sheet, so frame
      // both pins in the part of the map the sheet leaves visible.
      final minSheet = _minSheet(media);
      final sheetHeight =
          minSheet + (_maxSheet(media) - minSheet) * _sheetSlide.value;
      final fit = selectRideCameraFit(
        pickup: GeoPoint(pickup.latitude, pickup.longitude),
        destination: GeoPoint(destination.latitude, destination.longitude),
        mapHeight: media.size.height - minSheet,
        bottomObstruction: sheetHeight - minSheet,
      );
      await AppScope.instance.maps.fitBounds(
        fit.southwest,
        fit.northeast,
        padding: fit.padding,
      );
    } catch (_) {
      // The map may be gone or not laid out yet; the camera stays put.
    }
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
    final saved =
        await AppScope.instance.walletController.saveUseWalletFirst(value);
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
            when.isAfter(
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
        SetPickupResult? spot;
        if (!_pickupConfirmed) {
          // Same Set pickup sheet as Book now, ending in "Confirm and
          // schedule" instead of a search.
          final ride = _selectedRideOrNull;
          if (ride == null) return;
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
          _pickupConfirmed = true;
          _notes = _notes.withBagLevel(spot.bagLevel);
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
    if (_expiryRequote == null) _scheduleExpiryRequote();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.noRideCategory),
        ),
      );
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
      initialIsCurrentLocation:
          !_pickupConfirmed && !widget.pickupIsFallback,
      positionIsFallback:
          widget.pickupIsFallback && !_pickupConfirmed,
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
    for (final address in widget.stops) {
      final clean = address.trim();
      if (clean.isEmpty) continue;
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
        quote.signedPayload == null ||
        quote.signedPayload!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.fareChangedRefreshing),
        ),
      );
      _releaseBookingLock();
      unawaited(_loadQuotes());
      return;
    }
    final paymentItem = _selection.selectedPaymentItem();
    if (paymentItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noPaymentMethod)),
      );
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
          final card = await AddCardPage.open(context);
          if (card == null || !mounted) return;
          final index = _selection.payments().indexWhere(
            (p) => p.brand == card.methodBrand,
          );
          if (index < 0) return;
          setState(() => _selection.selectPayment(index));
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

        // Book the price Set pickup showed, not the one from before it.
        final bookable = await _quoteAfterPickup(selected);
        if (!mounted) return;
        if (bookable == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.priceUnavailableRefreshing),
            ),
          );
          unawaited(_loadQuotes());
          return;
        }
        final quote = bookable.quote;
        final authoritativePrice = bookable.price;
        final shown = spot.fareTotalKr;
        if (shown != null &&
            _selection.moneyOf(shown).amountMinor != quote.totalMinor &&
            !await _acceptNewPrice(shown, authoritativePrice)) {
          if (!mounted) return;
          setState(() {});
          // rider-79: the other categories are priced from the confirmed
          // pickup too.
          unawaited(_loadQuotes());
          return;
        }
        if (!mounted) return;
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
                    ? CustomGoogleMap(
                        key: const ValueKey('select-ride-map'),
                        initialPosition: CameraPosition(
                          target: _pickupPosition,
                          zoom: 13.2,
                        ),
                        markers: {
                          if ((_pickupTimePin ?? _pickupPin) != null)
                            Marker(
                              markerId: const MarkerId('pickup'),
                              position: _pickupPosition,
                              icon: (_pickupTimePin ?? _pickupPin)!,
                              anchor: _pickupTimePin != null
                                  ? RouteTimeMarker.anchor
                                  : const Offset(0.5, 0.5),
                            ),
                          if ((_destinationTimePin ?? _destinationPin) != null)
                            Marker(
                              markerId: const MarkerId('destination'),
                              position: widget.destinationPosition,
                              icon: (_destinationTimePin ?? _destinationPin)!,
                              anchor: _destinationTimePin != null
                                  ? RouteTimeMarker.anchor
                                  : const Offset(0.5, 0.5),
                            ),
                          // UI-08: the stops are on the map while booking.
                          ...routeStopMarkers(_locatedStops),
                        },
                        polylines: styledRoute(
                          routePolyline(
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
                        // Green free-flow traffic hides the Waze road palette;
                        // traffic stays on the active-trip map only.
                        trafficEnabled: false,
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
                            if (mounted) unawaited(_fitRoute());
                          });
                        },
                      )
                    : const SelectRideRouteCanvas(),
              ),
            ),
            Positioned(
              top: media.padding.top + 8,
              left: 16,
              right: 16,
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
                      child: AnimatedBuilder(
                        animation: _sheetSlide,
                        builder: (context, _) {
                          final mid = _midValue(media);
                          final v = _sheetSlide.value;
                          // 0 at the low stop → 1 at the middle: the other
                          // rides come in.
                          final listReveal = mid <= 0
                              ? 1.0
                              : (v / mid).clamp(0.0, 1.0);
                          // 0 at the middle → 1 at full: descriptions and
                          // badges.
                          final detail = mid >= 1
                              ? 0.0
                              : Curves.easeOutCubic.transform(
                                  ((v - mid) / (1 - mid)).clamp(0.0, 1.0),
                                );
                          final showFilters = v > 0.92;
                          final selectedRide = _selectedRideOrNull;
                          final promotion = _promotion;
                          return Column(
                            children: [
                              // Title, promotion and filters stay put while
                              // the rides scroll under them; dragging here
                              // still moves the sheet.
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (details) =>
                                    _onHeaderDragUpdate(details, media),
                                onVerticalDragEnd: (details) =>
                                    _onHeaderDragEnd(details, media),
                                child: Column(
                                  children: [
                                    Semantics(
                                      button: true,
                                      label: v > 0.98
                                          ? context.l10n.showFewerRides
                                          : context.l10n.showAllRides,
                                      child: GestureDetector(
                                        key: const ValueKey(
                                          'select-ride-sheet-handle',
                                        ),
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
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        4,
                                        16,
                                        8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              context.l10n.chooseYourRide,
                                              style: _text(
                                                22,
                                                weight: FontWeight.w700,
                                                letterSpacing: -0.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (promotion != null)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          10,
                                        ),
                                        child: PromotionTicket(
                                          promotion: promotion,
                                          onTap: () =>
                                              _openPromotionDetails(promotion),
                                        ),
                                      ),
                                    // Filters fade and slide in once the sheet
                                    // is fully up, and away again as it leaves.
                                    ClipRect(
                                      child: AnimatedSize(
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        alignment: Alignment.topCenter,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          heightFactor: showFilters ? 1 : 0,
                                          child: AnimatedOpacity(
                                            opacity: showFilters ? 1 : 0,
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            child: AnimatedSlide(
                                              offset: showFilters
                                                  ? Offset.zero
                                                  : const Offset(0, -0.35),
                                              duration: const Duration(
                                                milliseconds: 240,
                                              ),
                                              curve: Curves.easeOutCubic,
                                              child: IgnorePointer(
                                                ignoring: !showFilters,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        20,
                                                        2,
                                                        20,
                                                        8,
                                                      ),
                                                  child: _filterRow(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Opacity(
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
                                        itemCount: _visibleRides.length,
                                        itemBuilder: (context, index) =>
                                            _rideTile(
                                              _visibleRides[index],
                                              detail: detail,
                                            ),
                                      ),
                                    ),
                                    // At the low stop only the chosen ride
                                    // shows.
                                    if (listReveal < 1 && selectedRide != null)
                                      Positioned(
                                        left: 14,
                                        right: 14,
                                        top: 2,
                                        child: IgnorePointer(
                                          ignoring: listReveal > 0.5,
                                          child: Opacity(
                                            opacity: 1 - listReveal,
                                            child: ColoredBox(
                                              color: Colors.white,
                                              child: _rideTile(
                                                selectedRide,
                                                detail: 0,
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
                        },
                      ),
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
              child: PointerInterceptor(child: _footer(media.padding.bottom)),
            ),
          ],
        ),
      ),
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

  Widget _filterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(
            label: context.l10n.filterRecommended,
            selected: _filter == SelectRideFilter.recommended,
            onTap: () => setState(() => _filter = SelectRideFilter.recommended),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: context.l10n.filterFaster,
            icon: Icons.schedule_rounded,
            selected: _filter == SelectRideFilter.faster,
            onTap: () => setState(() => _filter = SelectRideFilter.faster),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: context.l10n.filterCheaper,
            icon: Icons.payments_outlined,
            selected: _filter == SelectRideFilter.cheaper,
            onTap: () => setState(() => _filter = SelectRideFilter.cheaper),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accentSoft : _field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _accent : _line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? _accent : _muted),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: _text(
                13,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _rideTile(_RideOption ride, {required double detail}) {
    final selected = ride.id == _selection.selectedRideId;
    final price = _priceFor(ride);
    final discount = _discountFor(ride);
    return Padding(
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
                color: selected ? _accent : Colors.transparent,
                width: 1.2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF162C36).withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 58,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          excludeFromSemantics: true,
                          ride.image,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          cacheWidth: 216,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.directions_car_filled_rounded,
                            color: _muted,
                            size: 36,
                          ),
                        ),
                      ),
                      if (ride.glyph != null)
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: _accentSoft,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(ride.glyph, size: 14, color: _accent),
                          ),
                        ),
                    ],
                  ),
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
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: _muted,
                                ),
                                Flexible(
                                  child: Text(
                                    '${ride.seats}',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: _text(12.5, color: _muted),
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
                                color: _accent,
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
                              style: _text(12.5, color: _muted),
                            ),
                          ),
                          if (discount > 0)
                            _fitPrice(
                              context,
                              Text(
                                _kr(price + discount),
                                // UI-6: was 0xFF8A9399 (3.13:1 on white).
                                style: _text(12, color: MoveraTokens.subtleOnFill)
                                    .copyWith(
                                      decoration: TextDecoration.lineThrough,
                                    ),
                              ),
                            ),
                        ],
                      ),
                      if (selected &&
                          _selection
                              .walletSplitFor(
                                _selection.moneyOf(price).amountMinor,
                              )
                              .usesWallet)
                        _walletLine(price),
                      if (selected && _walletOtherCurrency)
                        _walletCurrencyNote(),
                      // Description and badge come in as the sheet opens fully.
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topLeft,
                          heightFactor: detail,
                          child: Opacity(
                            opacity: detail,
                            child: Column(
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
                                        color: selected
                                            ? Colors.white
                                            : _accent,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
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
      context.l10n.walletWrongCurrency(_selection.walletCurrency, _selection.currency),
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
                    context.l10n.walletSplit(split.walletLabel, split.remainderLabel),
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
        onTap: _showPaymentPicker,
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
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _ink,
                          size: 20,
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
