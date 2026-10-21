import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/web/map_touch.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The map point [pixelsAboveCentre] above the camera [target] on screen,
/// at [zoom] (Web Mercator). The map fills the screen like every other map
/// screen; the pin sits a third of the way down, so the pickup is this far
/// north of the camera centre. Works the same on phones and on the web.
LatLng setPickupPointAbove(LatLng target, double zoom, double pixelsAboveCentre) {
  final metersPerPixel =
      156543.03392 * math.cos(target.latitude * math.pi / 180) / math.pow(2, zoom);
  final degreesPerPixel = metersPerPixel / 111320.0;
  return LatLng(
    (target.latitude + pixelsAboveCentre * degreesPerPixel).clamp(-85.0, 85.0),
    target.longitude,
  );
}

/// The camera centre that puts [pickup] at the pin (inverse of
/// [setPickupPointAbove]).
LatLng setPickupCameraFor(LatLng pickup, double zoom, double pixelsAboveCentre) {
  final metersPerPixel =
      156543.03392 * math.cos(pickup.latitude * math.pi / 180) / math.pow(2, zoom);
  final degreesPerPixel = metersPerPixel / 111320.0;
  return LatLng(
    (pickup.latitude - pixelsAboveCentre * degreesPerPixel).clamp(-85.0, 85.0),
    pickup.longitude,
  );
}

/// "Current location" and other stand-ins that are not a real address.
bool _isPlaceholder(String? label) {
  final clean = label?.trim().toLowerCase() ?? '';
  return clean.isEmpty ||
      clean == 'current location' ||
      clean.startsWith('location off');
}

/// The ride the rider picked on the categories screen, as Set pickup shows it.
class SetPickupRide {
  const SetPickupRide({
    required this.name,
    required this.image,
    required this.seats,
    required this.etaMin,
    required this.tripMinutes,
  });

  final String name;
  final String image;
  final int seats;

  /// Minutes until the driver reaches the pickup.
  final int etaMin;

  /// Minutes from pickup to destination.
  final int tripMinutes;
}

/// The fare from the server quote. [discountKr] is 0 without a promotion.
class SetPickupFare {
  const SetPickupFare({
    required this.totalKr,
    this.discountKr = 0,
    this.promotionPercent,
    this.walletKr = 0,
    this.currency = Money.defaultCurrency,
  });

  /// Amounts are whole units of [currency] (the pickup's zone, Q7).
  final double totalKr;
  final double discountKr;
  final int? promotionPercent;

  /// The part of the total taken first from the Movera Wallet balance of
  /// [currency] (Q8).
  final double walletKr;

  /// ISO-4217 code of every amount above.
  final String currency;

  double get remainderKr => totalKr - walletKr;

  /// The same split in minor units, for display: its parts add up to the
  /// total. Q8: the wallet part is the balance of the fare's currency.
  WalletSplit get split => WalletSplit.booked(
    totalMinor: Money.fromLegacyMajor(totalKr, currency).amountMinor,
    walletMinor: Money.fromLegacyMajor(walletKr, currency).amountMinor,
    currency: currency,
  );

  /// [major] whole units of [currency], as the fare is shown.
  String format(double major) =>
      formatMoney(Money.fromLegacyMajor(major, currency), whole: true);
}

/// The payment line at the bottom of the sheet.
class SetPickupPayment {
  const SetPickupPayment({
    required this.brand,
    required this.name,
    required this.detail,
  });

  final String brand;
  final String name;
  final String detail;
}

class SetPickupResult {
  const SetPickupResult({
    required this.position,
    required this.address,
    required this.bagLevel,
    this.fareTotalKr,
  });

  final LatLng position;
  final String address;

  /// The total Set pickup showed when the rider confirmed, so the caller
  /// can tell when the price it is about to book differs from it.
  final double? fareTotalKr;

  /// 0 = no bags, 1 = 1–2 bags, 2 = 3 or more.
  final int bagLevel;
}

/// "Set pickup": shown every time after Book, with the current location
/// preselected. The rider drags the map under a fixed pin; the map never
/// moves by itself (only a spot chip or My location glides it). The sheet
/// slides between all details and a short pickup + Confirm view.
class SetPickupPage extends StatefulWidget {
  const SetPickupPage({
    super.key,
    required this.initialPosition,
    required this.initialAddress,
    required this.destinationAddress,
    required this.destinationPosition,
    required this.ride,
    required this.fare,
    required this.payment,
    required this.brandMark,
    this.onChangePayment,
    this.onRequote,
    this.fareAfterPaymentChange,
    this.initialBagLevel = 0,
    this.home,
    this.spotsController,
    this.initialIsCurrentLocation = true,
    this.positionIsFallback = false,
    this.confirmLabel,
    this.scheduledPickup,
    this.geocoding,
    this.stops = const <String>[],
  });

  static Future<SetPickupResult?> open(
    BuildContext context, {
    required LatLng initialPosition,
    required String initialAddress,
    required String destinationAddress,
    required LatLng destinationPosition,
    required SetPickupRide ride,
    required SetPickupFare fare,
    required SetPickupPayment payment,
    required Widget Function(String brand) brandMark,
    Future<SetPickupPayment?> Function()? onChangePayment,
    Future<SetPickupFare?> Function(LatLng pin)? onRequote,
    SetPickupFare Function(SetPickupFare fare)? fareAfterPaymentChange,
    int initialBagLevel = 0,
    LatLng? home,
    PickupSpotsController? spotsController,
    bool initialIsCurrentLocation = true,
    bool positionIsFallback = false,
    String? confirmLabel,
    DateTime? scheduledPickup,
    List<String> stops = const <String>[],
  }) async {
    final route = RightToLeftTransition<SetPickupResult>(
      SetPickupPage(
        initialPosition: initialPosition,
        initialAddress: initialAddress,
        destinationAddress: destinationAddress,
        destinationPosition: destinationPosition,
        ride: ride,
        fare: fare,
        payment: payment,
        brandMark: brandMark,
        onChangePayment: onChangePayment,
        onRequote: onRequote,
        fareAfterPaymentChange: fareAfterPaymentChange,
        initialBagLevel: initialBagLevel,
        home: home,
        spotsController: spotsController,
        initialIsCurrentLocation: initialIsCurrentLocation,
        positionIsFallback: positionIsFallback,
        confirmLabel: confirmLabel,
        scheduledPickup: scheduledPickup,
        stops: stops,
      ),
      settings: const RouteSettings(name: AppRoutes.confirmPickup),
    );
    final result = await Navigator.of(context).push<SetPickupResult>(route);
    await route.completed;
    return result;
  }

  final LatLng initialPosition;
  final String initialAddress;
  final String destinationAddress;
  final LatLng destinationPosition;

  /// UI-08: the stops on the way, shown under the destination.
  final List<String> stops;
  final SetPickupRide ride;
  final SetPickupFare fare;
  final SetPickupPayment payment;
  final Widget Function(String brand) brandMark;
  final Future<SetPickupPayment?> Function()? onChangePayment;

  /// Prices the ride again from the exact pin after the rider moves it.
  /// Returns the new fare, or null to keep the one shown; a throw keeps it
  /// too. Without this the fare never changes.
  final Future<SetPickupFare?> Function(LatLng pin)? onRequote;

  /// The fare's wallet part for the method chosen in Change payment (the
  /// wallet split depends on it), so the split shown is the one booked.
  final SetPickupFare Function(SetPickupFare fare)? fareAfterPaymentChange;
  final int initialBagLevel;

  /// The rider's Home, when known: a "Near Home" spot appears when the
  /// pickup is within a few hundred metres of it.
  final LatLng? home;

  /// Suggests the pickup spots; the app's own controller when null.
  final PickupSpotsController? spotsController;
  final bool initialIsCurrentLocation;

  /// Button text: "Confirm and search" now, "Confirm and schedule" later.
  final String? confirmLabel;

  /// For a ride booked for later: the chosen pickup time. The pin and the
  /// header then show that time instead of the driver's minutes.
  final DateTime? scheduledPickup;

  /// The start point is a default map point, not the rider: Confirm waits
  /// until the pin is moved or a real location arrives.
  final bool positionIsFallback;

  /// Looks up the pin's address; the app's own geocoder when null.
  final AppGeocoding? geocoding;

  /// Where the pin's tip sits, as a share of the screen height.
  static const pinFraction = 0.34;

  @override
  State<SetPickupPage> createState() => _SetPickupPageState();
}

class _SetPickupPageState extends State<SetPickupPage>
    with TickerProviderStateMixin {
  static const _ink = Color(0xFF1D252C);
  static const _muted = Color(0xFF5C656C);
  static const _line = Color(0xFFE7EBEE);
  static const _accent = Color(0xFF2D5878);
  static const _field = Color(0xFFF6F8FA);
  static const _cta = Color(0xFF11181D);

  /// How far a drag must travel to move the sheet from open to short.
  static const _dragRange = 340.0;

  // Opens short (pickup + Confirm); the handle or a drag up shows the rest.
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 0,
  );
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 520),
  );
  late final PickupMapController _pickup = PickupMapController(
    location: AppScope.instance.location,
    geocoding: widget.geocoding ?? AppScope.instance.geocoding,
  );
  late final PickupSpotsController _spotsController =
      widget.spotsController ?? AppScope.instance.pickupSpots;

  // Spots for the address under the pin. They reload (debounced, and only
  // the newest request lands) when the pin settles on a new point.
  List<PickupSpot> _spots = const <PickupSpot>[];
  PickupSpot? _selectedSpot;
  // The street the chips belong to; the label reads "<street> – <spot>".
  String _spotStreet = '';
  Timer? _spotsTimer;
  int _spotsGeneration = 0;

  GoogleMapController? _map;
  late LatLng _center = widget.initialPosition;
  late LatLng _routeStart = widget.initialPosition;
  late String _address = widget.initialAddress;
  late bool _atCurrentLocation = widget.initialIsCurrentLocation;
  late bool _usable = !widget.positionIsFallback;
  late int _bags = widget.initialBagLevel;
  late SetPickupPayment _payment = widget.payment;
  late SetPickupFare _fare = widget.fare;
  bool _requoting = false;
  int _requoteGeneration = 0;
  bool _mapReady = false;
  bool _mapMountScheduled = false;
  bool _moving = false;
  bool _fingerDown = false;
  MapTouchSubscription? _mapTouch;
  // Screen geometry of the pin: how far above the map centre it sits, and
  // the current zoom, so camera positions convert to the pickup point.
  double _pinAboveCentrePx = 0;
  double _zoom = 16.2;
  bool _resolving = false;
  bool _confirming = false;

  /// [_address] does not (yet) name the point under the pin: the pin moved
  /// and its lookup has not answered, or the lookup failed.
  late bool _addressIsStale =
      _isPlaceholder(_address) || needsDroppedPinLabel(_address);
  int _resolveGeneration = 0;
  Future<void>? _resolveTask;
  Future<void>? _requoteTask;

  /// Confirm was tapped while the address or the price was still loading;
  /// the button shows a spinner for at most [confirmWait].
  bool _confirmWaiting = false;

  /// How long Confirm waits for the pin's address and price before booking
  /// with what is known (a dropped-pin label, the fare shown).
  static const confirmWait = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    setWebOverlayOpen(false);
    _mapTouch = watchMapTouch(onDown: _onMapFingerDown, onUp: _onMapFingerUp);
    if (_isPlaceholder(_address) || isUnusablePickupLabel(_address)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAddress());
    }
    _scheduleSpots(immediately: true);
  }

  /// Loads the spots for the point under the pin. Debounced so a series of
  /// small moves asks once; a generation counter drops answers for points
  /// the pin has already left.
  void _scheduleSpots({bool immediately = false}) {
    _spotsTimer?.cancel();
    final generation = ++_spotsGeneration;
    _spotsTimer = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 350),
      () => unawaited(_loadSpots(generation)),
    );
  }

  Future<void> _loadSpots(int generation) async {
    final at = _center;
    final address = _address;
    List<PickupSpot> spots;
    try {
      spots = await _spotsController.forAddress(
        at: at,
        address: address,
        home: widget.home,
      );
    } catch (_) {
      spots = const <PickupSpot>[];
    }
    if (!mounted || generation != _spotsGeneration) return;
    setState(() {
      _spots = spots;
      if (_selectedSpot == null) _spotStreet = pickupSpotStreet(_address);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mapMountScheduled) return;
    _mapMountScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_mountMapWhenRouteSettles());
    });
  }

  Future<void> _mountMapWhenRouteSettles() async {
    await waitForCurrentRouteToSettle(context);
    if (!mounted) return;
    setState(() => _mapReady = true);
  }

  @override
  void dispose() {
    _spotsTimer?.cancel();
    _mapTouch?.cancel();
    _sheet.dispose();
    _lift.dispose();
    _pickup.dispose();
    AppScope.instance.maps.detach(owner: MapOwners.pickup);
    super.dispose();
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  String get _arriveClock {
    final scheduled = widget.scheduledPickup;
    final at = scheduled != null
        ? scheduled.add(Duration(minutes: widget.ride.tripMinutes))
        : DateTime.now().add(
            Duration(minutes: widget.ride.etaMin + widget.ride.tripMinutes),
          );
    return _clock(at);
  }

  /// "Driver arrives in 8 min · Arrive 08:19", or for a scheduled ride
  /// "Pickup 07:05 · Arrive 08:19".
  String get _timesLine {
    final scheduled = widget.scheduledPickup;
    if (scheduled != null) {
      return context.l10n.pickupAtArriveAt(_clock(scheduled), _arriveClock);
    }
    return context.l10n.driverArrivesInArriveAt('${widget.ride.etaMin}', _arriveClock);
  }

  bool _isAwayFrom(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() > 0.00015 ||
      (a.longitude - b.longitude).abs() > 0.00015;

  // ---- Pin: lifts while the map moves, drops with a small bounce. ----

  // The pin lifts while a finger holds the map and drops when it lets go.
  // On phones the map reports the drag itself. On the web the map is a
  // browser element, so the finger is watched on the page instead
  // (_mapTouch) and the lift never runs while the map itself is sliding:
  // animating over a moving map re-renders every canvas on each frame, and
  // iPhone Safari ran out of graphics memory doing that and reloaded.
  void _onMoveStarted() {
    _moving = true;
    if (!kIsWeb) _lift.forward();
  }

  void _onMapFingerDown() {
    _fingerDown = true;
    _lift.forward();
  }

  void _onMapFingerUp() {
    if (!_fingerDown) return;
    _fingerDown = false;
    // Still gliding: drop once the map settles.
    if (!_moving) _lift.reverse();
  }

  void _onCameraIdle() {
    if (!_moving) return;
    _moving = false;
    if (!_fingerDown) _lift.reverse();
    if (_isAwayFrom(_center, _routeStart)) {
      HapticFeedback.lightImpact();
      setState(() {
        _routeStart = _center;
        _usable = true;
        _addressIsStale = true;
        _atCurrentLocation =
            widget.initialIsCurrentLocation &&
            !_isAwayFrom(_center, widget.initialPosition);
        _deselectSpot();
      });
      unawaited(_resolveAddress());
      _scheduleSpots();
      unawaited(_requote());
    }
  }

  /// The pin left the chosen spot: the chip lets go and the label returns
  /// to the plain street until the new address resolves.
  void _deselectSpot() {
    if (_selectedSpot == null) return;
    _selectedSpot = null;
    if (_spotStreet.isNotEmpty) _address = _spotStreet;
  }

  /// A fresh price from the exact pin. The latest move wins: an older answer
  /// that arrives late is ignored. A failed quote keeps the price shown.
  Future<void> _requote() {
    final task = _requoteNow();
    _requoteTask = task;
    return task;
  }

  Future<void> _requoteNow() async {
    final requote = widget.onRequote;
    if (requote == null) return;
    final generation = ++_requoteGeneration;
    setState(() => _requoting = true);
    SetPickupFare? fare;
    try {
      fare = await requote(_center);
    } catch (_) {
      fare = null;
    }
    if (!mounted || generation != _requoteGeneration) return;
    setState(() {
      _requoting = false;
      if (fare != null) _fare = fare;
    });
  }

  Future<void> _resolveAddress() {
    final task = _resolveAddressNow();
    _resolveTask = task;
    return task;
  }

  Future<void> _resolveAddressNow() async {
    final at = _center;
    final generation = ++_resolveGeneration;
    setState(() => _resolving = true);
    final address = await _pickup.reverse(at);
    if (!mounted || generation != _resolveGeneration) return;
    if (_isAwayFrom(at, _center)) return;
    setState(() {
      _resolving = false;
      if (!isUnusablePickupLabel(address)) {
        _address = address!.trim();
        _addressIsStale = false;
      } else if (_addressIsStale || _isPlaceholder(_address)) {
        // No street for this point: say it is a dropped pin rather than
        // keep the previous street or a placeholder (AUD-2).
        _address = droppedPinPickupAddress(at);
        _addressIsStale = false;
      }
      if (_selectedSpot == null) _spotStreet = pickupSpotStreet(_address);
    });
  }

  LatLng _cameraFor(LatLng pickup) =>
      setPickupCameraFor(pickup, _zoom, _pinAboveCentrePx);

  /// Chips and My location are the only things that move the map.
  Future<void> _glideTo(
    LatLng target, {
    String? address,
    bool here = false,
    PickupSpot? spot,
  }) async {
    HapticFeedback.selectionClick();
    // The camera target depends on the zoom; until the map has moved once,
    // _zoom is only the requested value (the web map may round it), so ask
    // the map. Otherwise the pin lands a little off the spot and the chip
    // would let go at once.
    try {
      final zoom = await _map?.getZoomLevel();
      if (zoom != null) _zoom = zoom;
    } catch (_) {
      // The map is not ready; the requested zoom stands in.
    }
    if (!mounted) return;
    setState(() {
      _center = target;
      _routeStart = target;
      _usable = true;
      _atCurrentLocation = here;
      if (spot != null) {
        _selectedSpot = spot;
      } else {
        _deselectSpot();
      }
      if (address != null && address.trim().isNotEmpty) {
        _address = address.trim();
        _addressIsStale = false;
        // A lookup still running for an earlier point must not replace it.
        _resolveGeneration += 1;
        _resolving = false;
      } else {
        _addressIsStale = true;
      }
    });
    // A new place gets its own spots; a spot keeps the row it came from.
    if (spot == null) _scheduleSpots();
    if (!kIsWeb) {
      _lift.forward().then((_) {
        if (mounted) _lift.reverse();
      });
    }
    try {
      await _map?.animateCamera(CameraUpdate.newLatLng(_cameraFor(target)));
    } catch (_) {
      // The map is gone or not ready; the pin still moved.
    }
    if (address == null) unawaited(_resolveAddress());
    unawaited(_requote());
  }

  Future<void> _useCurrentLocation() async {
    final at = _center;
    final result = await _pickup.currentPosition();
    if (!mounted) return;
    // rider-u134: the rider moved the pin while the fix was coming; a late
    // answer must not glide it away from there.
    if (result.position != null && (_moving || _isAwayFrom(at, _center))) {
      return;
    }
    final position = result.position;
    if (position == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.l10n.locationUnavailableMoveMap),
        ),
      );
      return;
    }
    await _glideTo(position, here: true);
  }

  Future<void> _useSpot(PickupSpot spot) async {
    if (_selectedSpot?.id == spot.id) return;
    final street = _spotStreet.isNotEmpty ? _spotStreet : pickupSpotStreet(_address);
    if (_spotStreet.isEmpty) _spotStreet = street;
    await _glideTo(
      spot.position,
      address: pickupSpotLabel(street, spot),
      spot: spot,
    );
  }

  Future<void> _searchAddress() async {
    final controller = TextEditingController();
    final query = await MoveraSheet.show<String>(
      context: context,
      // rider-u139: MoveraSheet already lifts the sheet over the keyboard;
      // padding by the inset again here doubled it.
      builder: (sheetContext) => PointerInterceptor(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.pickupAddress, style: _text(18, weight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) => Navigator.pop(sheetContext, value),
                decoration: InputDecoration(
                  hintText: context.l10n.searchAddress,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: _field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    final text = query?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    final found = await _pickup.search(text);
    if (!mounted) return;
    if (found == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.addressNotFoundMoveMap)),
      );
      return;
    }
    await _glideTo(found.position, address: found.address ?? text);
  }

  Future<void> _changePayment() async {
    final change = widget.onChangePayment;
    if (change == null) return;
    final next = await change();
    if (!mounted) return;
    final refresh = widget.fareAfterPaymentChange;
    setState(() {
      if (next != null) _payment = next;
      if (refresh != null) _fare = refresh(_fare);
    });
  }

  /// Books the point under the pin. While its address or price is still
  /// loading, waits a moment (bounded by [confirmWait]) so the street and
  /// the fare confirmed are the pin's own (RIDE-12). If the street is still
  /// unknown then, the pickup is a labelled dropped pin with its
  /// coordinates, never the previous street or "Pickup location" (AUD-2).
  Future<void> _confirm() async {
    if (_confirming || !_usable) return;
    _confirming = true;
    HapticFeedback.mediumImpact();
    final at = _center;
    final pending = <Future<void>>[
      if (_resolving && _resolveTask != null) _resolveTask!,
      if (_requoting && _requoteTask != null) _requoteTask!,
    ];
    if (pending.isNotEmpty) {
      setState(() => _confirmWaiting = true);
      try {
        await Future.wait(pending).timeout(confirmWait);
      } catch (_) {
        // Book with what is known.
      }
      if (!mounted) return;
      setState(() => _confirmWaiting = false);
      if (_isAwayFrom(at, _center)) {
        // The pin moved while waiting: the rider confirms again.
        _confirming = false;
        return;
      }
    }
    final address = _addressIsStale || needsDroppedPinLabel(_address)
        ? droppedPinPickupAddress(_center)
        : confirmedPickupAddress(_address, _center);
    // Next time this address comes up, the spot is offered as "Previously
    // used". Fire and forget: confirming never waits on storage.
    unawaited(_spotsController.remember(position: _center, address: address));
    Navigator.pop(
      context,
      SetPickupResult(
        position: _center,
        address: address,
        bagLevel: _bags,
        fareTotalKr: _fare.totalKr,
      ),
    );
  }

  // ---- Sheet: drag anywhere on it, soft landing + haptic. ----

  bool _sheetDragging = false;

  void _onSheetDragStart(DragStartDetails details) {
    _sheetDragging = true;
  }

  void _onSheetDrag(DragUpdateDetails details) {
    if (!_sheetDragging) return;
    _sheet.value -= (details.primaryDelta ?? 0) / _dragRange;
  }

  void _onSheetDragEnd(DragEndDetails details) {
    if (!_sheetDragging) return;
    _sheetDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity.abs() > 420 ? velocity < 0 : _sheet.value > 0.5;
    _settleSheet(open);
  }

  void _settleSheet(bool open) {
    final target = open ? 1.0 : 0.0;
    if (_sheet.value != target) HapticFeedback.selectionClick();
    _sheet.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
  }) => GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.25,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height;
    final pinY = height * SetPickupPage.pinFraction;
    // The map fills the screen like every other map screen, on every
    // platform. The pin sits a third of the way down, so the pickup is the
    // point that far above the camera centre (plain map maths, no map
    // padding, no map drawn larger than the screen: the oversized map
    // crashed the live web app in Safari on touch). The sheet never
    // resizes the map, so the map never moves on its own.
    _pinAboveCentrePx = height / 2 - pinY;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: _mapReady
                ? _liveMap()
                : const ColoredBox(color: Color(0xFFE9EEF1)),
          ),
          Positioned(
            top: pinY - _PickupPin.tipOffset,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: _PickupPin(
                  key: const ValueKey('set-pickup-pin'),
                  lift: _lift,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _topBar(),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _sheetView(media)),
        ],
      ),
    );
  }

  Widget _liveMap() {
    return CustomGoogleMap(
      key: const ValueKey('set-pickup-map'),
      initialPosition: CameraPosition(target: _cameraFor(_center), zoom: _zoom),
      // The pin sits above the centre and its ground point is worked out
      // with flat-map maths, which a tilted camera would throw off.
      tiltWithZoom: false,
      // Only the map and the pin: the route and the times live in the sheet.
      myLocationEnabled: true,
      onMapCreated: (controller) {
        _map = controller;
        AppScope.instance.maps.attach(controller, owner: MapOwners.pickup);
      },
      onCameraMoveStarted: _onMoveStarted,
      onCameraMove: (position) {
        if (!_moving) _onMoveStarted();
        _zoom = position.zoom;
        _center = setPickupPointAbove(
          position.target,
          position.zoom,
          _pinAboveCentrePx,
        );
      },
      onCameraIdle: _onCameraIdle,
    );
  }

  Widget _topBar() {
    return PointerInterceptor(
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.only(left: 4, right: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A11181D),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: context.l10n.back,
                icon: const Icon(Icons.arrow_back_rounded, color: _ink),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.destinationAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(16, weight: FontWeight.w500),
                    ),
                    if (viaStopsLine(widget.stops) case final via?)
                      Text(
                        via,
                        key: const ValueKey('set-pickup-via-stops'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(12.5, color: _muted),
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

  Widget _sheetView(MediaQueryData media) {
    return PointerInterceptor(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
            child: MoveraIconButton.round(
              icon: Icons.my_location_rounded,
              onPressed: _useCurrentLocation,
              label: context.l10n.myLocation,
              iconSize: 20,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onSheetDragStart,
            onVerticalDragUpdate: _onSheetDrag,
            onVerticalDragEnd: _onSheetDragEnd,
            onVerticalDragCancel: () => _sheetDragging = false,
            child: Container(
              key: const ValueKey('set-pickup-sheet'),
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: media.size.height * 0.72),
              padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + media.padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1411181D),
                    blurRadius: 24,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: GestureDetector(
                        key: const ValueKey('set-pickup-handle'),
                        onTap: () => _settleSheet(_sheet.value < 0.5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
                          color: Colors.transparent,
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _line,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _reveal(0.0, 0.55, _rideHeader()),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.pickupSpot,
                            style: _text(13.5, weight: FontWeight.w600, color: _muted),
                          ),
                        ),
                        _shortBagsChip(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _pickupCard(),
                    _spotChips(),
                    _reveal(0.25, 0.85, _bagsRow()),
                    _reveal(0.35, 0.95, _priceBox()),
                    _reveal(0.45, 1.0, _paymentLine()),
                    const SizedBox(height: 14),
                    _confirmButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Folds a section away as the sheet slides down; staggered by [start].
  Widget _reveal(double start, double end, Widget child) {
    final curve = CurvedAnimation(
      parent: _sheet,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: AnimatedBuilder(
          animation: curve,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 10 * (1 - curve.value)),
            child: child,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _rideHeader() {
    final ride = widget.ride;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 46,
            child: Image.asset(
              ride.image,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.directions_car_filled_rounded,
                color: _muted,
                size: 34,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ride.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(19, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.person_outline_rounded, size: 16, color: _muted),
                    Text('${ride.seats}', style: _text(13.5, weight: FontWeight.w600, color: _muted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_timesLine, style: _text(13, color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupCard() {
    final spot = _selectedSpot;
    final subtitle = _resolving
        ? context.l10n.findingTheAddress
        : spot != null
        ? spot.subtitle
        : _atCurrentLocation
        ? context.l10n.yourCurrentLocation
        : context.l10n.dragMapToAdjust;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _searchAddress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _accent, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: RiderRouteStyle.pickup, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _address,
                        key: ValueKey(_address),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(15.5, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: _text(12.5, color: _accent)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(context.l10n.change, style: _text(14, weight: FontWeight.w600, color: _accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    String label,
    VoidCallback onTap, {
    IconData? icon,
    bool selected = false,
    Key? key,
  }) {
    final fg = selected ? Colors.white : _ink;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _cta : _field,
        shape: StadiumBorder(side: BorderSide(color: selected ? _cta : _line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(label, style: _text(13.5, weight: FontWeight.w500, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _spotIcon(PickupSpotKind kind) => switch (kind) {
    PickupSpotKind.entrance => Icons.door_front_door_rounded,
    PickupSpotKind.parking => Icons.local_parking_rounded,
    PickupSpotKind.previous => Icons.history_rounded,
    PickupSpotKind.home => Icons.home_rounded,
  };

  /// Spots for the address under the pin, then "On map" to place the pin
  /// by hand. The chosen spot is filled black.
  Widget _spotChips() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        key: const ValueKey('set-pickup-spots'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final spot in _spots)
              Semantics(
                button: true,
                selected: _selectedSpot?.id == spot.id,
                label: '${spot.title}, ${spot.subtitle}',
                child: _chip(
                  spot.title,
                  () => _useSpot(spot),
                  icon: _spotIcon(spot.kind),
                  selected: _selectedSpot?.id == spot.id,
                  key: ValueKey('set-pickup-spot-${spot.id}'),
                ),
              ),
            _chip(context.l10n.onMap, () => _settleSheet(false), icon: Icons.add_rounded),
          ],
        ),
      ),
    );
  }

  List<String> get _bagLabels => [context.l10n.bagsNone, '1–2', '3+'];

  /// On the short sheet the bags sit at the top right; a tap cycles
  /// No → 1–2 → 3+. The chip fades away as the sheet opens, where the full
  /// Bags row takes over.
  Widget _shortBagsChip() {
    return AnimatedBuilder(
      animation: _sheet,
      builder: (context, child) {
        final visible = (1 - _sheet.value * 2).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: visible < 0.5,
          child: Opacity(opacity: visible, child: child),
        );
      },
      child: Semantics(
        button: true,
        label: context.l10n.bagsLabel(_bagLabels[_bags]),
        child: GestureDetector(
          key: const ValueKey('set-pickup-bags-chip'),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _bags = (_bags + 1) % _bagLabels.length);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(
              color: _bags == 0 ? const Color(0xFFF3F5F6) : _accent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _bags == 0 ? _line : _accent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.luggage_rounded,
                  size: 16,
                  color: _bags == 0 ? _accent : Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  _bags == 0 ? context.l10n.notesBags : context.l10n.bagsCount(_bagLabels[_bags]),
                  style: _text(
                    12.5,
                    weight: FontWeight.w600,
                    color: _bags == 0 ? _ink : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bagsRow() {
    final labels = _bagLabels;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const Icon(Icons.luggage_rounded, color: _accent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(context.l10n.bagsQuestion, style: _text(15, weight: FontWeight.w600))),
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: Semantics(
                selected: _bags == i,
                button: true,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _bags = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _bags == i ? _accent : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _bags == i ? _accent : _line),
                    ),
                    child: Text(
                      labels[i],
                      style: _text(
                        13.5,
                        weight: FontWeight.w600,
                        color: _bags == i ? Colors.white : _ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool bold = false,
    Color color = _ink,
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: _text(14.5, weight: bold ? FontWeight.w700 : FontWeight.w400, color: color),
            ),
          ),
          Text(
            value,
            style: _text(14.5, weight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Widget _priceBox() {
    final fare = _fare;
    final hasDiscount = fare.discountKr > 0;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          if (hasDiscount) ...[
            _priceRow(context.l10n.ridePrice, fare.format(fare.totalKr + fare.discountKr)),
            _priceRow(
              fare.promotionPercent == null
                  ? context.l10n.promotion
                  : context.l10n.promotionPercent('${fare.promotionPercent}'),
              '-${fare.format(fare.discountKr)}',
              color: _accent,
            ),
            const Divider(height: 12, color: _line),
          ],
          _priceRow(context.l10n.total, fare.format(fare.totalKr), bold: true),
          if (fare.split.usesWallet) ...[
            const Divider(height: 12, color: _line),
            _priceRow(
              context.l10n.moveraWallet,
              '-${fare.split.walletLabel}',
              color: _walletGreen,
              key: const ValueKey('set-pickup-wallet-part'),
            ),
            _priceRow(
              fare.split.paidByWallet ? context.l10n.nothingMoreToPay : _payment.name,
              fare.split.remainderLabel,
              key: const ValueKey('set-pickup-remainder'),
            ),
          ],
          if (_requoting)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                context.l10n.updatingPrice,
                key: const ValueKey('set-pickup-requoting'),
                style: _text(12.5, color: _muted),
              ),
            ),
        ],
      ),
    );
  }

  static const Color _walletGreen = Color(0xFF079A60);

  Widget _paymentLine() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onChangePayment == null ? null : _changePayment,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 40, height: 32, child: Center(child: widget.brandMark(_payment.brand))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_payment.name, style: _text(14.5, weight: FontWeight.w600)),
                    if (_payment.detail.trim().isNotEmpty)
                      Text(_payment.detail, style: _text(12.5, color: _muted)),
                  ],
                ),
              ),
              if (widget.onChangePayment != null)
                Text(context.l10n.changeArrow, style: _text(14, weight: FontWeight.w600, color: _accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        key: const ValueKey('set-pickup-confirm'),
        onPressed: _usable ? () => unawaited(_confirm()) : null,
        style: FilledButton.styleFrom(
          backgroundColor: _cta,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _confirmWaiting
            ? const SizedBox(
                key: ValueKey('set-pickup-confirm-waiting'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.confirmLabel ?? context.l10n.confirmAndSearch,
                style: _text(16, weight: FontWeight.w600, color: Colors.white),
              ),
      ),
    );
  }
}

/// The fixed centre pin: a green "N min" bubble on a stem. It lifts while the
/// map moves (its shadow spreads) and drops back with a small bounce.
class _PickupPin extends StatelessWidget {
  const _PickupPin({super.key, required this.lift});

  final Animation<double> lift;

  static const _bubble = 34.0;
  static const _stem = 14.0;

  /// From the top of the widget to the pin's tip.
  static const tipOffset = _bubble + _stem + 4;

  @override
  Widget build(BuildContext context) {
    final drop = CurvedAnimation(
      parent: lift,
      curve: Curves.easeOut,
      reverseCurve: Curves.bounceIn,
    );
    return AnimatedBuilder(
      animation: drop,
      builder: (context, _) {
        final t = drop.value;
        return SizedBox(
          width: 80,
          height: tipOffset + 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Shadow on the ground: grows and softens as the pin rises.
              Positioned(
                top: tipOffset - 4,
                child: Container(
                  width: 10 + 14 * t,
                  height: 6 + 3 * t,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28 - 0.12 * t),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -14 * t),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _bubble,
                      height: _bubble,
                      decoration: BoxDecoration(
                        color: RiderRouteStyle.pickup,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: RiderRouteStyle.pickup.withValues(alpha: 0.35),
                            blurRadius: 10 + 8 * t,
                            offset: Offset(0, 4 + 6 * t),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 3, height: _stem, color: RiderRouteStyle.pickup),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: RiderRouteStyle.pickup,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
