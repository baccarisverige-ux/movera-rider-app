import 'dart:async';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/core/maps/camera_mode.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart' show recenterZoom;
import 'package:movera_rider/core/maps/map_camera_motion.dart' show mapViewOf;
import 'package:movera_rider/core/maps/map_lifecycle.dart';
import 'package:movera_rider/core/performance/route_transition_metrics.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/application/home_sheet_controller.dart';
import 'package:movera_rider/features/home/presentation/home_map_style.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_map_layer.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/ride_booking/application/home_search_interrupted.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_location_notice.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_tab_page.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_scroll.dart';
import 'package:movera_rider/shared/widgets/horizontal_swipe.dart';
import 'package:movera_rider/features/home/presentation/widgets/advance_booking_card.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_bottom_nav_item.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_top_actions.dart';
import 'package:movera_rider/features/home/presentation/widgets/saved_places_row.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_ticket.dart';
import 'package:movera_rider/features/home/presentation/widgets/premium_route_location_badge.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:movera_rider/l10n/l10n.dart';

typedef _SavedPlaceData = SavedPlaceData;

/// Home's opening camera: the whole local area (about 10 km across a phone)
/// around the rider, before and after the first location fix.
const double homeOpeningZoom = 11.7;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  final SheetController _homeSheetController = SheetController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final HomeSheetController _sheetCtl = HomeSheetController(
    controller: _homeSheetController,
    minPixels: () => _sheetMinPixels,
    midPixels: () => _sheetMidPixels,
  );
  late final HomeLocationController _locationCtl = HomeLocationController(
    location: AppScope.instance.location,
    geocoding: AppScope.instance.geocoding,
    motion: AppScope.instance.motion,
  );
  late final HomePlacesController _places = HomePlacesController();
  StreamSubscription<void>? _savedPlacesSubscription;
  bool _showRecenterButton = true;
  BitmapDescriptor? _locationPuckCompact;
  BitmapDescriptor? _locationPuckExpanded;
  ui.Image? _puckCompactImage;
  ui.Image? _puckExpandedImage;
  int _webPuckPaintGen = 0;
  final RotatedPuckCache _webPuckCache = RotatedPuckCache();

  // The search card ends around 113 logical px from the top of the sheet.
  // Leave space for the floating navigation bar below it at the collapsed snap.
  static const double _sheetMinHeight = 214;
  static const double _sheetMaxHeight = 294;

  bool _destinationSheetOpen = false;
  bool get _locationPulseExpanded => _locationCtl.pulseExpanded;
  double get _locationHeading => _locationCtl.heading;
  set _locationHeading(double value) => _locationCtl.heading = value;
  set _hasCompassHeading(bool value) => _locationCtl.hasCompassHeading = value;
  set _lastMapZoom(double value) => _locationCtl.lastMapZoom = value;
  set _lastMapTarget(LatLng value) => _locationCtl.lastMapTarget = value;
  String? get _pickupAddress => _places.pickupAddress;
  set _pickupAddress(String? value) => _places.pickupAddress = value;
  String? get _destinationAddress => _places.destinationAddress;
  set _destinationAddress(String? value) => _places.destinationAddress = value;
  String? get _homeAddress => _places.homeAddress;
  String? get _workAddress => _places.workAddress;
  List<String> get _routeStops => _places.routeStops;
  set _routeStops(List<String> value) => _places.routeStops = value;
  LatLng? get _currentLatLng => _places.currentLatLng;
  set _currentLatLng(LatLng? value) => _places.currentLatLng = value;
  LatLng? get _tripPickupLatLng => _places.tripPickupLatLng;
  set _tripPickupLatLng(LatLng? value) => _places.tripPickupLatLng = value;
  List<String> get _recentAddresses => _places.recentAddresses;
  List<_SavedPlaceData> get _savedPlaces => _places.savedPlaces;

  static const int _maxCustomPlaces = HomePlacesController.maxCustom;

  /// Shown at the owner's request while the app is being built. Stops are not
  /// yet carried by the quote, booking or driver app (see LATER_JOB.md, B1).
  static const bool _stopsSupported = true;

  final ValueNotifier<bool> _mapParked = ValueNotifier(false);
  final MapParkingGuard _mapParkingGuard = MapParkingGuard();

  /// NAV-3: Home's own route, and whether an opaque page fully covers it.
  /// The map stays parked while anything is above Home, not only for the
  /// flows Home opens itself (a page can replace the parked one, or be
  /// pushed by a widget that does not go through [_withParkedHomeMap]).
  ModalRoute<Object?>? _homeRoute;
  bool _homeHidden = false;
  bool get _homeIsCurrent => _homeRoute?.isCurrent ?? true;

  /// RIDE-9: one route flow (Where to, Schedule, a saved place, a tab) at a
  /// time, so a double tap cannot open two pickers.
  bool _routeFlowOpen = false;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(59.3293, 18.0686),
    zoom: homeOpeningZoom,
  );

  static const Color _premiumInk = Color(0xFF1D252C);
  static const Color _premiumMuted = Color(0xFF5C656C);
  static const Color _premiumLine = Color(0xFFE7EBEE);
  static const Color _premiumAccent = Color(0xFF2D5878);
  static const Color _premiumAccentSoft = Color(0xFFEAF2F8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reportHomeBuilt();
    _homeSheetController.addListener(_syncHomeSheetState);
    AppScope.instance.promotion.addListener(_onPromotionChanged);
    unawaited(AppScope.instance.promotion.refresh());
    _loadMarkers();
    _savedPlacesSubscription = _places.changes.listen((_) async {
      await _places.load();
      if (mounted) setState(() {});
    });
    _restoreAddressData();
    _startHeadingTracking();
    _announceInterruptedSearch();
  }

  /// A reload during Finding Driver drops the search. Landing on an empty Home
  /// with no explanation reads as though the ride was never requested, so say
  /// what happened.
  void _announceInterruptedSearch() {
    // rider-u117: a ride that is still stored (and about to be resumed) was
    // not interrupted; see takeHomeSearchInterrupted.
    final interrupted = takeHomeSearchInterrupted();
    if (interrupted is bool) {
      if (interrupted) _showSearchInterrupted();
      return;
    }
    unawaited(
      interrupted.then((value) {
        if (!value || !mounted) return;
        _showSearchInterrupted();
        WidgetsBinding.instance.ensureVisualUpdate();
      }),
    );
  }

  void _showSearchInterrupted() {
    // Let the first frame settle so the messenger has a Scaffold to put this
    // in, and leave it up long enough to actually be read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MoveraToast.show(
        context,
        context.l10n.homeSearchInterrupted,
        duration: const Duration(seconds: 8),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeRoute = ModalRoute.of(context);
    final hidden = !TickerMode.valuesOf(context).enabled;
    final changed = hidden != _homeHidden;
    _homeHidden = hidden;
    // Parked while covered: resume once Home is the current route again.
    if (changed || (_mapParked.value && _homeIsCurrent)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncRouteParking());
    }
  }

  void _syncRouteParking() {
    if (!mounted || _mapParkingGuard.isParked) return;
    if (_homeHidden && !_mapParked.value) {
      _parkHomeMap();
    } else if (_homeIsCurrent && _mapParked.value) {
      _resumeHomeMap();
    }
  }

  void _parkHomeMap() {
    if (_mapParked.value) return;
    setWebOverlayOpen(false);
    _mapParked.value = true;
    _locationCtl.pauseLiveUpdates();
    AppScope.instance.mapLifecycle.park();
    AppScope.instance.maps.detach(owner: MapOwners.home);
  }

  void _resumeHomeMap() {
    if (!_mapParked.value) return;
    AppScope.instance.mapLifecycle.resume();
    _locationCtl.resumeLiveUpdates();
    _mapParked.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _locationCtl.pauseLiveUpdates();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // RIDE-14: a parked Home (a ride or another page above it) stays paused;
    // it resumes when the map is unparked.
    if (_mapParked.value) return;
    _locationCtl.resumeLiveUpdates();
    // rider-u118: no first fix was ever bound (it failed or is still
    // pending): run the whole first-fix path (puck, label, stream, camera).
    // Restarting only the stream tracked GPS but never drew the puck.
    if (_currentLatLng == null) {
      unawaited(_detectCurrentAddress());
    } else if (_locationCtl.state == HomeLocationState.temporarilyUnavailable) {
      _locationCtl.recoverLiveLocation(
        isMounted: () => mounted,
        onFix: (latLng, heading) {
          _currentLatLng = latLng;
          _locationHeading = heading;
          _updateLocationVisuals();
          _refreshPickupLabelIfMoved(latLng);
        },
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppScope.instance.promotion.removeListener(_onPromotionChanged);
    _settleTimer?.cancel();
    _detectRetryTimer?.cancel();
    _savedPlacesSubscription?.cancel();
    _sheetCtl.dispose();
    _locationCtl.dispose();
    _puckCompactImage?.dispose();
    _puckExpandedImage?.dispose();
    _mapParked.dispose();
    AppScope.instance.maps.detach(owner: MapOwners.home);
    setWebOverlayOpen(false);
    _homeSheetController
      ..removeListener(_syncHomeSheetState)
      ..dispose();
    super.dispose();
  }

  Future<void> _restoreAddressData() async {
    unawaited(_centerCameraOnQuickFix());
    await _places.load();
    if (mounted) setState(() {});
    await _detectCurrentAddress();
  }

  Future<void> _persistAddressData() => _places.persist();

  /// Coarse camera hint from [HomeLocationController.quickCameraFix].
  LatLng? _cameraHint;

  /// Batch 10 Phase 110: centre the camera on a fast cached fix while the
  /// accurate one is fetched. Camera only — pickup, the puck and
  /// [_currentLatLng] stay owned by [_detectCurrentAddress], whose accurate
  /// fix still moves the camera when it lands.
  Future<void> _centerCameraOnQuickFix() async {
    final hint = await _locationCtl.quickCameraFix();
    if (!mounted || hint == null || _currentLatLng != null) return;
    _cameraHint = hint;
    final maps = AppScope.instance.maps;
    // Map not created yet: onMapCreated picks the hint up.
    if (maps.activeOwner != MapOwners.home) return;
    await maps.moveCamera(
      GeoPoint(hint.latitude, hint.longitude),
      zoom: homeOpeningZoom,
    );
  }

  Future<void>? _detectInFlight;

  /// rider-u119: a first fix that failed for a transient reason (the
  /// 16 s timeout of a cold GPS, a platform error) is tried again with
  /// backoff while Home has no fix, instead of waiting for an app resume.
  Timer? _detectRetryTimer;
  int _detectRetries = 0;

  void _scheduleDetectRetry() {
    _detectRetryTimer?.cancel();
    // 2, 4, 8, 16, then 30 s: the live stream's resubscribe backoff.
    final delay = Duration(
      seconds: math.min(30, 2 << _detectRetries.clamp(0, 4)),
    );
    _detectRetries += 1;
    _detectRetryTimer = Timer(delay, () {
      _detectRetryTimer = null;
      if (!mounted || _currentLatLng != null) return;
      // Parked under a ride screen or in the background: keep waiting (the
      // booking flow and an app resume ask for their own fix).
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (_mapParked.value ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        _scheduleDetectRetry();
        return;
      }
      unawaited(_detectCurrentAddress());
    });
  }

  /// Detects the rider's location once; a second call while one is running
  /// joins it, so the booking flow can wait for the fix Home already asked
  /// for instead of asking again.
  Future<void> _detectCurrentAddress() {
    return _detectInFlight ??= _runDetectCurrentAddress().whenComplete(() {
      _detectInFlight = null;
    });
  }

  /// Waits briefly for a location fix when none has landed yet (first fix
  /// still coming, permission prompt open). Null when there is still none.
  Future<LatLng?> _awaitCurrentFix() async {
    final known = _tripPickupLatLng ?? _currentLatLng;
    if (known != null) return known;
    final hint = Timer(const Duration(milliseconds: 700), () {
      if (mounted) MoveraToast.show(context, context.l10n.homeFindingLocation);
    });
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    try {
      // Two tries: the first may only join Home's own request, which can be
      // about to time out (the prompt kept it waiting); the second starts
      // fresh once permission is granted.
      for (var attempt = 0; attempt < 2; attempt++) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        await _detectCurrentAddress().timeout(left, onTimeout: () {});
        if (!mounted) return null;
        final fix = _tripPickupLatLng ?? _currentLatLng;
        if (fix != null) return fix;
      }
    } catch (_) {
      // No fix: the caller falls back to a placeholder point.
    } finally {
      hint.cancel();
    }
    return _tripPickupLatLng ?? _currentLatLng;
  }

  Future<void> _runDetectCurrentAddress() async {
    if (mounted) setState(() {});
    try {
      final detected = await _locationCtl.detectCurrent();
      if (!mounted) return;
      final target = detected.target;
      if (detected.denied || target == null) {
        // U2: no fix — never call a fallback point "Current location".
        if (isPlaceholderPickupLabel(_pickupAddress)) {
          setState(() => _pickupAddress = locationOffPickupLabel);
        }
        if (detected.failure == HomeLocationFailure.unavailable &&
            _currentLatLng == null) {
          _scheduleDetectRetry();
        }
        return;
      }
      _detectRetryTimer?.cancel();
      _detectRetryTimer = null;
      _detectRetries = 0;
      setState(() {
        _pickupAddress = detected.address;
        _pickupLabelAt = target;
        _currentLatLng = target;
        _locationCtl.clearOverlays();
        _locationHeading = detected.heading;
      });
      await _prepareLocationPuckIcons();
      await _locationCtl.bindLiveLocation(
        isMounted: () => mounted,
        onFix: (latLng, heading) {
          _currentLatLng = latLng;
          _locationHeading = heading;
          _updateLocationVisuals();
          _refreshPickupLabelIfMoved(latLng);
        },
        onHeading: (heading) {
          _locationHeading = heading;
          _hasCompassHeading = true;
          _updateLocationVisuals();
        },
        onPulse: _updateLocationVisuals,
      );
      // rider-44: a late fix must not glide the map of the screen on top
      // (pickup, Set pickup, Select ride). Home's own map re-centres on
      // [_currentLatLng] when it is created again.
      final maps = AppScope.instance.maps;
      if (!mounted ||
          _mapParked.value ||
          maps.activeOwner != MapOwners.home) {
        return;
      }
      await maps.animateCamera(
        GeoPoint(target.latitude, target.longitude),
        zoom: homeOpeningZoom,
        follow: true,
      );
    } catch (_) {
      if (!mounted) return;
      if (isPlaceholderPickupLabel(_pickupAddress)) {
        setState(() => _pickupAddress = locationOffPickupLabel);
      }
    }
  }

  String _shortAddress(String? address, {int maxLength = 24}) {
    final value = L10n.place(address?.trim() ?? '');
    if (value.isEmpty) return context.l10n.setLocation;
    return value.length <= maxLength
        ? value
        : '${value.substring(0, maxLength - 1)}…';
  }

  String _targetTitle(String target, String? customType) {
    switch (target) {
      case 'pickup':
        return context.l10n.choosePickup;
      case 'home':
        return context.l10n.setHomeAddress;
      case 'work':
        return context.l10n.setWorkAddress;
      case 'custom':
        return context.l10n.setPlaceAddress(_placeLabel(customType ?? 'other'));
      default:
        return context.l10n.whereTo;
    }
  }

  String? _existingAddressFor(String target) => _places.existingFor(target);

  Future<String> _normaliseAddress(String input, {int? generation}) {
    return _locationCtl.normaliseAddress(input, generation: generation);
  }

  Future<void> _moveMapToAddress(String address) async {
    final target = await _locationCtl.geocodeLatLng(address);
    if (target == null) return;
    await AppScope.instance.maps.animateCamera(
      GeoPoint(target.latitude, target.longitude),
      zoom: 15,
    );
  }

  void _rememberAddress(String address) {
    // D-004: raw "lat, lng" strings and placeholders are not places; never
    // offer them back as Recents.
    if (isRawCoordinateLabel(address) || isPlaceholderPickupLabel(address)) {
      return;
    }
    _places.remember(address);
  }

  Future<String> _bookingPickup(String label, LatLng position) =>
      bookingPickupAddress(
        label: label,
        position: position,
        reverse: (point) => AppScope.instance.geocoding.reverse(
          GeoPoint(point.latitude, point.longitude),
        ),
      );

  Future<void> _saveAddressFor(
    String target,
    String address, {
    String? customType,
    String? placeId,
  }) async {
    final resolved = await _normaliseAddress(address);
    if (resolved.isEmpty || !mounted) return;

    LatLng? resolvedPickupPosition;
    if (target == 'pickup') {
      if (resolved.toLowerCase() == 'current location') {
        resolvedPickupPosition = _currentLatLng;
      } else {
        final geocodedPickup = await _locationCtl.geocodeLatLng(resolved);
        if (geocodedPickup != null) {
          resolvedPickupPosition = geocodedPickup;
        }
      }
    }
    if (!mounted) return;

    setState(() {
      _places.applyResolved(
        target: target,
        address: resolved,
        pickupPosition: resolvedPickupPosition,
        customType: customType,
        placeId: placeId,
      );
      if (target == 'destination') {
        AppScope.instance.destinationMemory.remember(address: resolved);
      }
    });
    await _persistAddressData();
    if (target == 'pickup' || target == 'destination') {
      await _moveMapToAddress(resolved);
    }
  }

  Future<void> _handleDestinationTap({String? initialRideId}) =>
      _runRouteFlow(() async {
    // Capture from the tap itself: the sheet sequencing below takes long enough
    // that anything typed in the meantime would otherwise be lost.
    final capture = EarlyInputCapture()..start();
    try {
      if (!_destinationSheetOpen) {
        await _openDestinationSheet();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await _showRouteAddressPicker(
        initialField: 'destination',
        capture: capture,
        initialRideId: initialRideId,
      );
    } finally {
      capture.stop();
    }
  });

  /// A saved place that only says "Current location" was never really set.
  String? _placeOrNull(String? address) {
    final value = address?.trim() ?? '';
    if (value.isEmpty || value == 'Current location') return null;
    return value;
  }

  /// Long-press on Home / Work / a custom place: change its address.
  Future<void> _editSavedPlace(String target, {String? customType}) =>
      _showAddressPicker(target: target, customType: customType);

  /// rider-41: a custom place is edited by its id; another place of the
  /// same kind is left alone.
  Future<void> _editCustomPlace(_SavedPlaceData place) => _showAddressPicker(
    target: 'custom',
    customType: place.type,
    placeId: place.id,
  );

  Future<void> _useSavedPlaceAsDestination(
    String? savedAddress, {
    required String target,
    String? customType,
  }) => _runRouteFlow(() async {
    final address = _placeOrNull(savedAddress) ?? '';
    if (address.isEmpty) {
      await _showAddressPicker(target: target, customType: customType);
      return;
    }

    final destination = await _normaliseAddress(address);
    if (destination.isEmpty || !mounted) return;

    setState(() {
      _destinationAddress = destination;
      _rememberAddress(destination);
    });
    await _persistAddressData();
    await _withParkedHomeMap(() async {
      final pickupResult = await _prefillPickup(
        _pickupAddress ?? 'Current location',
        null,
      );
      if (pickupResult == null || !mounted) return null;
      final pickupPosition = pickupResult.position;
      final bookingAddress = pickupResult.isFallback
          ? pickupResult.address
          : await _bookingPickup(pickupResult.address, pickupPosition);
      if (!mounted) return null;
      setState(() {
        _pickupAddress = bookingAddress;
        _tripPickupLatLng = pickupResult.position;
      });
      if (!mounted) return null;
      final confirmedPickupPosition = pickupPosition;
      var resolvedDestination = destination;
      LatLng? destinationPosition;
      switch (await _locationCtl.resolvePlace(destination)) {
        case GeocodeFound(:final value):
          resolvedDestination = value.address;
          destinationPosition = value.point;
        case GeocodeStale():
          // RIDE-18: a newer flow owns the geocode; stop without an error.
          return null;
        case GeocodeNotFound():
          if (mounted) {
            MoveraToast.show(context, context.l10n.homeChooseValidDestination);
          }
          return null;
      }
      final confirmedDestinationPosition = destinationPosition;
      if (!mounted) return null;
      return Navigator.of(context).push(
        RideStageTransition(
          SelectRide(
            pickupAddress: bookingAddress,
            destinationAddress: resolvedDestination,
            pickupPosition: confirmedPickupPosition,
            pickupIsFallback: pickupResult.isFallback,
            destinationPosition: confirmedDestinationPosition,
            stops: List<String>.from(_routeStops),
            bookingMode: BookingMode.now,
            onScheduled: (context, id) => RideScheduledPage.open(
              context,
              reservationId: id,
              replace: true,
            ),
          ),
          settings: const RouteSettings(name: AppRoutes.selectRide),
        ),
      );
    });
  });

  Future<T?> _withParkedHomeMap<T>(Future<T?> Function() action) async {
    final parkedNow = _mapParkingGuard.enter();
    final rideBefore = AppScope.instance.ride.rideId;
    final statusBefore = AppScope.instance.ride.status;
    try {
      if (parkedNow) {
        final parkingWatch = Stopwatch()..start();
        _parkHomeMap();
        // Let Flutter remove the platform map for one rendered frame before
        // the next map-heavy ride screen mounts.
        await WidgetsBinding.instance.endOfFrame;
        parkingWatch.stop();
        RouteTransitionMetrics.homeMapParking(parkingWatch.elapsed);
        if (!mounted) return null;
      }
      return await action();
    } finally {
      final resumeNow = _mapParkingGuard.exit();
      if (resumeNow && mounted) {
        // U6: a finished (or abandoned) booking flow must not leave its
        // pickup behind as the next booking's starting point.
        _tripPickupLatLng = null;
        // A ride that ended or was cancelled in this flow starts the next
        // booking from "Where to?", not from the last trip's destination.
        final ride = AppScope.instance.ride;
        final changed =
            ride.rideId != rideBefore || ride.status != statusBefore;
        if (changed &&
            (ride.status.isTerminal || ride.status.isCompletedSurface)) {
          _destinationAddress = null;
          _routeStops = const <String>[];
        }
        _closeDestinationSheet();
        // NAV-3: the flow's page can be replaced by another one (Book for
        // later -> Ride scheduled). Stay parked until Home is on top again.
        if (_homeIsCurrent) _resumeHomeMap();
      }
    }
  }

  /// RIDE-10: the next booking starts from the rider's current location,
  /// not from the last flow's pickup street.
  int _pickupLabelGeneration = 0;
  LatLng? _pickupLabelAt;

  void _resetPickupLabel() {
    final here = _currentLatLng;
    final generation = ++_pickupLabelGeneration;
    _pickupLabelAt = here;
    setState(() {
      // U6: the label and the point go together; neither outlives the flow.
      _tripPickupLatLng = null;
      _pickupAddress = here == null
          ? locationOffPickupLabel
          : 'Current location';
    });
    if (here == null) return;
    unawaited(() async {
      String? address;
      try {
        address = await AppScope.instance.geocoding.reverse(
          GeoPoint(here.latitude, here.longitude),
        );
      } catch (_) {
        return;
      }
      final clean = address?.trim() ?? '';
      if (!mounted ||
          generation != _pickupLabelGeneration ||
          clean.isEmpty ||
          isRawCoordinateLabel(clean) ||
          _routeFlowOpen ||
          _mapParkingGuard.isParked ||
          !isPlaceholderPickupLabel(_pickupAddress)) {
        return;
      }
      setState(() => _pickupAddress = clean);
    }());
  }

  /// RIDE-9: runs one route flow at a time; a second tap while one is
  /// opening or open does nothing. RIDE-10: when the flow ends, the pickup
  /// label goes back to the rider's current location.
  Future<void> _runRouteFlow(Future<void> Function() flow) async {
    if (_routeFlowOpen) return;
    _routeFlowOpen = true;
    try {
      await flow();
    } finally {
      _routeFlowOpen = false;
      if (mounted) _resetPickupLabel();
    }
  }

  /// RIDE-10: a live fix far from where the pickup label was resolved
  /// makes that label wrong; derive it again from the new point.
  void _refreshPickupLabelIfMoved(LatLng fix) {
    final at = _pickupLabelAt;
    if (at == null) {
      _pickupLabelAt = fix;
      return;
    }
    // Not during a flow, and never over a pickup the rider chose.
    if (_routeFlowOpen ||
        _mapParkingGuard.isParked ||
        _tripPickupLatLng != null) {
      return;
    }
    final moved = AppScope.instance.location.distanceBetween(
      at.latitude,
      at.longitude,
      fix.latitude,
      fix.longitude,
    );
    if (moved > 75) _resetPickupLabel();
  }

  Future<PickupMapResult?> _openPickupMapPicker(
    String address, {
    bool isDestination = false,
  }) async {
    var cleanAddress = address.trim();
    // U6: only text the rider actually typed is forward-geocoded. The stored
    // pickup label came from GPS, a dropped pin or an earlier booking, and a
    // raw coordinate string is not a place — geocoding either one moved the
    // picker to wherever the *previous* trip's address resolved to.
    final storedLabel = _pickupAddress?.trim() ?? '';
    final typedByRider =
        !isPlaceholderPickupLabel(cleanAddress) &&
        !isUnusablePickupLabel(cleanAddress) &&
        cleanAddress != storedLabel;
    // This booking's own confirmed pickup (cleared when the flow ends).
    LatLng? chosen = _tripPickupLatLng;
    if (typedByRider || isDestination) {
      final geocoded = await _locationCtl.geocodeLatLng(cleanAddress);
      if (geocoded != null) chosen = geocoded;
    }
    final gps = _currentLatLng;
    final initialPosition = chosen ?? gps ?? _initialPosition.target;
    // D-002: with no fix and no chosen pickup the picker opens on a default
    // map point; it must not be confirmable as if it were the rider's spot.
    final positionIsFallback = chosen == null && gps == null;
    if (chosen == null) {
      cleanAddress = gps != null ? 'Current location' : locationOffPickupLabel;
    }
    if (!mounted) return null;
    return _withParkedHomeMap(() async {
      final result = await ConfirmPickupSpot.open(
        context,
        initialPosition: initialPosition,
        initialAddress: cleanAddress.isEmpty
            ? (_pickupAddress ?? 'Current location')
            : cleanAddress,
        title: isDestination ? context.l10n.confirmDestination : context.l10n.confirmPickupSpot,
        confirmLabel: isDestination ? context.l10n.confirmDestination : context.l10n.confirmPickup,
        positionIsFallback: positionIsFallback,
        // U6 / D-011: opened at GPS (or the fallback) — take a fresh fix.
        refreshCurrentLocation: chosen == null,
      );
      if (result == null) return null;
      return PickupMapResult(
        address: result.address,
        position: result.position,
      );
    });
  }

  /// The pickup the categories screen starts from: a point the rider chose,
  /// an address they typed, or else their current location. Only with no
  /// location at all does the map picker open here.
  Future<PickupMapResult?> _prefillPickup(
    String address,
    GeoPoint? point,
  ) async {
    final clean = address.trim();
    if (point != null) {
      return PickupMapResult(
        address: clean,
        position: LatLng(point.latitude, point.longitude),
      );
    }
    final typedByRider =
        !isPlaceholderPickupLabel(clean) &&
        !isUnusablePickupLabel(clean) &&
        clean != (_pickupAddress?.trim() ?? '');
    if (typedByRider) {
      switch (await _locationCtl.resolveLatLng(clean)) {
        case GeocodeFound(:final value):
          return PickupMapResult(address: clean, position: value);
        case GeocodeStale():
          // RIDE-18: superseded — never swap the typed pickup for GPS.
          return null;
        case GeocodeNotFound():
          break;
      }
    }
    // No fix yet (Safari's permission prompt, a slow first fix): wait for it
    // rather than sending the rider to the old map picker.
    final here = await _awaitCurrentFix();
    if (!mounted) return null;
    if (here != null) {
      return PickupMapResult(
        address: typedByRider ? 'Current location' : clean,
        position: here,
      );
    }
    // Still nothing: the categories screen opens as usual and Set location
    // starts on a placeholder point the rider has to move (or allow
    // location) before it can be confirmed.
    return PickupMapResult(
      address: locationOffPickupLabel,
      position: _initialPosition.target,
      isFallback: true,
    );
  }

  /// The step after the rider taps a real destination.
  Future<Map<String, dynamic>?> _confirmRouteSelection(
    RoutePickerSelection selection, {
    bool scheduled = false,
  }) async {
    // Book now always confirms pickup; GPS only prefills. The confirm step
    // is Set pickup, opened after Book on the categories screen.
    final pickup = await _prefillPickup(
      selection.pickup,
      selection.pickupPoint,
    );
    if (pickup == null || !mounted) return null;
    var destination = selection.destination;
    var destinationPoint = selection.destinationPoint;
    if (destinationPoint == null) {
      final outcome = await _locationCtl.resolvePlace(destination);
      final geocoded = outcome.valueOrNull;
      if (geocoded == null) {
        if (mounted && outcome is GeocodeNotFound) {
          MoveraToast.show(context, context.l10n.homeChooseValidDestination);
        }
        return null;
      }
      destination = geocoded.address;
      destinationPoint = GeoPoint(
        geocoded.point.latitude,
        geocoded.point.longitude,
      );
    }
    DateTime? scheduledAt;
    if (scheduled) {
      if (!mounted) return null;
      // Q9: times are the pickup zone's local time, in the time zone its
      // config names.
      final timeZone = await AppScope.instance.riderConfig.timeZoneAt(
        pickup.position.latitude,
        pickup.position.longitude,
      );
      if (!mounted) return null;
      scheduledAt = await ScheduleDateTimeSelector.choose(
        context,
        timeZone: timeZone,
        tripMinutes: estimatedTripMinutes(
          GeoPoint(pickup.position.latitude, pickup.position.longitude),
          destinationPoint,
        ),
      );
      // Backing out of the time picker returns to Where to.
      if (scheduledAt == null || !mounted) return null;
    }
    return {
      'pickup': pickup.address,
      'pickupLat': pickup.position.latitude,
      'pickupLng': pickup.position.longitude,
      'pickupIsFallback': pickup.isFallback,
      'destination': destination,
      'destinationLat': destinationPoint.latitude,
      'destinationLng': destinationPoint.longitude,
      'stops': selection.stops,
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
    };
  }

  Future<void> _showRouteAddressPicker({
    required String initialField,
    EarlyInputCapture? capture,
    bool scheduled = false,
    String? initialRideId,
  }) async {
    // Either the capture the caller started at tap time, or a fresh one for
    // entry points that open the picker directly.
    final routeCapture = capture ?? (EarlyInputCapture()..start());
    final ownsCapture = capture == null;
    final gps = _currentLatLng;
    final here = gps == null ? null : GeoPoint(gps.latitude, gps.longitude);
    Map<String, dynamic>? draft;
    try {
      draft = await Navigator.of(context).push<Map<String, dynamic>>(
        BottomToTopTransition(
          RoutePickerPage(
            pickupAddress: _placeOrNull(_pickupAddress),
            destinationAddress: _destinationAddress ?? '',
            stops: _stopsSupported ? _routeStops : const <String>[],
            stopsSupported: _stopsSupported,
            initialField: initialField,
            capture: routeCapture,
            here: here,
            homeAddress: _placeOrNull(_homeAddress),
            workAddress: _placeOrNull(_workAddress),
            savedPlaces: _places.savedPlaces,
            recent: _recentAddresses,
            onSetFavourite: (target) async {
              await _showAddressPicker(target: target);
              return _placeOrNull(
                target == 'home' ? _homeAddress : _workAddress,
              );
            },
            onPickOnMap: ({required pickup, required address}) async {
              final result = await _openPickupMapPicker(
                address,
                isDestination: !pickup,
              );
              if (result == null) return null;
              return RoutePickerMapPick(
                address: result.address,
                point: GeoPoint(
                  result.position.latitude,
                  result.position.longitude,
                ),
              );
            },
            onFinish: (selection) =>
                _confirmRouteSelection(selection, scheduled: scheduled),
          ),
        ),
      );
    } finally {
      if (ownsCapture) routeCapture.stop();
    }

    if (draft == null || !mounted) return;
    final rawPickup = draft['pickup'] as String? ?? '';
    final rawDestination = draft['destination'] as String? ?? '';
    final rawStops = (draft['stops'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .toList();
    final routePreparationWatch = Stopwatch()..start();
    final normaliseBatch = _locationCtl.beginNormalisationBatch();
    final normalizedRoute = await Future.wait<String>([
      _normaliseAddress(rawPickup, generation: normaliseBatch),
      _normaliseAddress(rawDestination, generation: normaliseBatch),
      ...rawStops.map(
        (stop) => _normaliseAddress(stop, generation: normaliseBatch),
      ),
    ]);
    routePreparationWatch.stop();
    RouteTransitionMetrics.routePreparation(
      routePreparationWatch.elapsed,
      stopCount: rawStops.length,
    );
    var pickup = normalizedRoute[0];
    final destination = normalizedRoute[1];
    final stops = normalizedRoute
        .skip(2)
        .where((address) => address.isNotEmpty)
        .toList();
    if (!mounted) return;
    final pickupLat = draft['pickupLat'] as double?;
    final pickupLng = draft['pickupLng'] as double?;
    final pickupIsFallback = draft['pickupIsFallback'] == true;
    final exactPickupPosition = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat, pickupLng)
        : (_tripPickupLatLng ?? _currentLatLng);
    if (exactPickupPosition != null) {
      pickup = await _bookingPickup(pickup, exactPickupPosition);
      if (!mounted) return;
    }
    final destinationLat = draft['destinationLat'] as double?;
    final destinationLng = draft['destinationLng'] as double?;
    final exactDestinationPosition =
        destinationLat != null && destinationLng != null
        ? LatLng(destinationLat, destinationLng)
        : null;
    setState(() {
      if (pickup.isNotEmpty) _pickupAddress = pickup;
      if (exactPickupPosition != null) {
        _tripPickupLatLng = exactPickupPosition;
      }
      _destinationAddress = destination.isEmpty
          ? _destinationAddress
          : destination;
      _routeStops = stops;
      if (pickup.isNotEmpty) _rememberAddress(pickup);
      if (destination.isNotEmpty) _rememberAddress(destination);
      for (final stop in stops) {
        _rememberAddress(stop);
      }
    });
    await _persistAddressData();
    if (destination.isNotEmpty) {
      final pickupPosition = exactPickupPosition;
      final destinationPosition = exactDestinationPosition;
      if (pickupPosition == null || destinationPosition == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.homeChooseValidRoute),
            ),
          );
        }
        return;
      }
      final scheduledAt = DateTime.tryParse(
        draft['scheduledAt'] as String? ?? '',
      );
      // Park the Home map before opening categories. Two Google Maps at once
      // crashes the browser tab on Flutter web.
      await _withParkedHomeMap(() {
        return Navigator.of(context).push(
          RideStageTransition(
            SelectRide(
              pickupAddress: pickup.isNotEmpty
                  ? pickup
                  : (_pickupAddress ?? 'Current location'),
              destinationAddress: destination,
              pickupPosition: pickupPosition,
              pickupIsFallback: pickupIsFallback,
              destinationPosition: destinationPosition,
              stops: List<String>.from(stops),
              bookingMode: scheduledAt == null
                  ? BookingMode.now
                  : BookingMode.scheduled,
              lockBookingMode: scheduledAt != null,
              initialScheduledFor: scheduledAt,
              // NAV-11: a Home card asked for this category.
              initialRideId: initialRideId,
              onScheduled: (context, id) => RideScheduledPage.open(
                context,
                reservationId: id,
                replace: scheduledAt == null,
                untilHome: scheduledAt != null,
              ),
            ),
            settings: const RouteSettings(name: AppRoutes.selectRide),
          ),
        );
      });
    }
  }

  Future<void> _showAddressPicker({
    required String target,
    String? customType,
    String? placeId,
  }) async {
    final initialAddress = _existingAddressFor(target);
    final controller = TextEditingController(
      text: initialAddress == 'Current location' ? '' : initialAddress ?? '',
    );
    final focusNode = FocusNode();
    var query = controller.text;
    // Started before the sheet opens; see EarlyInputCapture.
    final capture = EarlyInputCapture()..start();
    capture.attach(controller, focusNode);
    String? selected;
    try {
      selected = await MoveraSheet.show<String>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.24),
        builder: (sheetContext) {
          return MoveraSheetDisposables(
            disposables: [controller, focusNode],
            child: PointerInterceptor(
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  capture.onChanged = (value) {
                    AppScope.instance.destinationSearch.type(value, (text) {
                      // RIDE-20: the sheet's own context, not Home's — the
                      // debounce can fire after the sheet has closed.
                      if (!context.mounted) return;
                      setModalState(() => query = text);
                    });
                  };
                  final filteredRecent = _recentAddresses
                      .where(
                        (address) =>
                            query.trim().isEmpty ||
                            address.toLowerCase().contains(
                              query.trim().toLowerCase(),
                            ),
                      )
                      .take(6)
                      .toList();
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.78,
                      ),
                      padding: EdgeInsets.fromLTRB(
                        ResSize.w * 18,
                        ResSize.h * 11,
                        ResSize.w * 18,
                        ResSize.h * 20,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: ResSize.w * 42,
                            height: ResSize.h * 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCED4D8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          16.height,
                          Row(
                            children: [
                              Expanded(
                                child: TextWidget(
                                  text: _targetTitle(target, customType),
                                  color: _premiumInk,
                                  fontSize: 18,
                                  fontWeight: fwBold,
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                                color: _premiumInk,
                                tooltip: context.l10n.close,
                              ),
                            ],
                          ),
                          10.height,
                          TextField(
                            controller: controller,
                            focusNode: focusNode,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              AppScope.instance.destinationSearch.type(value, (
                                text,
                              ) {
                                if (!context.mounted) return;
                                setModalState(() => query = text);
                              });
                            },
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                Navigator.pop(sheetContext, value.trim());
                              }
                            },
                            style: TextStyle(
                              color: _premiumInk,
                              fontSize: ResSize.setSp(15),
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: context.l10n.searchOrEnterAddress,
                              hintStyle: TextStyle(
                                color: _premiumMuted.withValues(alpha: 0.72),
                                fontSize: ResSize.setSp(14),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _premiumInk.withValues(alpha: 0.72),
                              ),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        controller.clear();
                                        setModalState(() => query = '');
                                      },
                                      tooltip: context.l10n.clear,
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                              filled: true,
                              fillColor: const Color(0xFFF5F7F7),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResSize.w * 15,
                                vertical: ResSize.h * 15,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          12.height,
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              // Save the real street address, never the
                              // words "Current location".
                              onTap: _placeOrNull(_pickupAddress) == null
                                  ? null
                                  : () => Navigator.pop(
                                      sheetContext,
                                      _placeOrNull(_pickupAddress),
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResSize.w * 13,
                                  vertical: ResSize.h * 11,
                                ),
                                decoration: BoxDecoration(
                                  color: _premiumAccentSoft.withValues(
                                    alpha: 0.62,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.my_location_rounded,
                                      color: _premiumAccent,
                                      size: ResSize.h * 20,
                                    ),
                                    11.width,
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          TextWidget(
                                            text: context.l10n.useCurrentLocation,
                                            color: _premiumInk,
                                            fontSize: 12.5,
                                            fontWeight: fwSemiBold,
                                          ),
                                          2.height,
                                          TextWidget(
                                            text:
                                                _placeOrNull(_pickupAddress) ==
                                                    null
                                                ? context.l10n.findingYourAddress
                                                : _shortAddress(
                                                    _pickupAddress,
                                                    maxLength: 38,
                                                  ),
                                            color: _premiumMuted,
                                            fontSize: 9,
                                            fontWeight: fwNormal,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (filteredRecent.isNotEmpty) ...[
                            16.height,
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextWidget(
                                text: context.l10n.recentAddresses,
                                color: _premiumMuted,
                                fontSize: 10.5,
                                fontWeight: fwSemiBold,
                              ),
                            ),
                            6.height,
                            Flexible(
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const BouncingScrollPhysics(),
                                itemCount: filteredRecent.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: Color(0xFFE7EBEE),
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final address = filteredRecent[index];
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: ResSize.w * 4,
                                    ),
                                    leading: Icon(
                                      Icons.history_rounded,
                                      color: _premiumMuted,
                                      size: ResSize.h * 20,
                                    ),
                                    title: TextWidget(
                                      text: address,
                                      color: _premiumInk,
                                      fontSize: 11,
                                      fontWeight: fwMedium,
                                    ),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, address),
                                  );
                                },
                              ),
                            ),
                          ],
                          if (query.trim().isNotEmpty) ...[
                            14.height,
                            Material(
                              color: _premiumAccent,
                              borderRadius: BorderRadius.circular(17),
                              child: InkWell(
                                onTap: () => Navigator.pop(
                                  sheetContext,
                                  controller.text.trim(),
                                ),
                                borderRadius: BorderRadius.circular(17),
                                child: SizedBox(
                                  height: ResSize.h * 46,
                                  width: double.infinity,
                                  child: Center(
                                    child: TextWidget(
                                      text: context.l10n.useThisAddress,
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: fwSemiBold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    } finally {
      capture.stop();
    }
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    await _saveAddressFor(
      target,
      selected,
      customType: customType,
      placeId: placeId,
    );
  }

  Future<void> _openAddPlacePicker() async {
    if (_savedPlaces.length >= _maxCustomPlaces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.homeMaxCustomPlaces)),
      );
      return;
    }
    const placeTypes = <String>[
      'gym',
      'mall',
      'school',
      'airport',
      'family',
      'restaurant',
      'other',
    ];
    final type = await MoveraSheet.show<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (sheetContext) {
        return PointerInterceptor(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              ResSize.w * 18,
              ResSize.h * 12,
              ResSize.w * 18,
              ResSize.h * 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ResSize.w * 42,
                  height: ResSize.h * 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCED4D8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                18.height,
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextWidget(
                    text: context.l10n.homeWhatPlaceToSave,
                    color: _premiumInk,
                    fontSize: 17,
                    fontWeight: fwBold,
                  ),
                ),
                16.height,
                Wrap(
                  spacing: ResSize.w * 9,
                  runSpacing: ResSize.h * 9,
                  children: placeTypes.map((placeType) {
                    return Material(
                      color: const Color(0xFFF5F7F7),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => Navigator.pop(sheetContext, placeType),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResSize.w * 13,
                            vertical: ResSize.h * 11,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _placeIcon(placeType),
                                size: ResSize.h * 18,
                                color: _premiumAccent,
                              ),
                              7.width,
                              TextWidget(
                                text: _placeLabel(placeType),
                                color: _premiumInk,
                                fontSize: 11,
                                fontWeight: fwSemiBold,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (type == null || !mounted) return;
    await _showAddressPicker(target: 'custom', customType: type);
  }

  String _placeLabel(String type) {
    switch (type) {
      case 'gym':
        return context.l10n.placeGym;
      case 'mall':
        return context.l10n.placeMall;
      case 'school':
        return context.l10n.placeSchool;
      case 'airport':
        return context.l10n.placeAirport;
      case 'family':
        return context.l10n.placeFamily;
      case 'restaurant':
        return context.l10n.placeRestaurant;
      default:
        return context.l10n.placeOther;
    }
  }

  IconData _placeIcon(String type) {
    switch (type) {
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'mall':
        return Icons.local_mall_outlined;
      case 'school':
        return Icons.school_outlined;
      case 'airport':
        return Icons.flight_takeoff_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      default:
        return Icons.place_outlined;
    }
  }

  Future<BitmapDescriptor> _buildLocationPuckIcon(bool expanded) async {
    final visual = await MoveraRiderPuckMarker.createVisual(expanded: expanded);
    // The rotated bitmaps were drawn from the old source images.
    _webPuckCache.clear();
    if (expanded) {
      _puckExpandedImage?.dispose();
      _puckExpandedImage = visual.image;
    } else {
      _puckCompactImage?.dispose();
      _puckCompactImage = visual.image;
    }
    return visual.icon;
  }

  Future<void> _prepareLocationPuckIcons() async {
    _locationPuckCompact ??= await _buildLocationPuckIcon(false);
    _locationPuckExpanded ??= await _buildLocationPuckIcon(true);
  }

  Future<BitmapDescriptor?> _webRotatedPuck({
    required bool expanded,
    required double heading,
  }) async {
    final src = expanded ? _puckExpandedImage : _puckCompactImage;
    if (src == null) return null;
    // U7: one bitmap per 5° bucket and pulse state, built once and reused,
    // instead of toImage + PNG encode on every heading sample and pulse.
    final bucket = _webPuckCache.bucketFor(heading);
    final cached = _webPuckCache.lookup(expanded: expanded, bucket: bucket);
    if (cached != null) return cached;
    final icon = await _rasteriseRotatedPuck(
      src,
      _webPuckCache.headingFor(bucket),
    );
    if (icon != null &&
        identical(src, expanded ? _puckExpandedImage : _puckCompactImage)) {
      _webPuckCache.store(expanded: expanded, bucket: bucket, icon: icon);
    }
    return icon;
  }

  Future<BitmapDescriptor?> _rasteriseRotatedPuck(
    ui.Image src,
    double heading,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = src.width * 0.5;
    final cy = src.height * 0.66;
    canvas
      ..translate(cx, cy)
      ..rotate(heading * math.pi / 180)
      ..translate(-cx, -cy)
      ..drawImage(src, Offset.zero, Paint());
    final image = await recorder.endRecording().toImage(src.width, src.height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    // The size given up front: the web plugin otherwise loads every new
    // marker bitmap into an extra image just to measure it.
    return BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: src.width.toDouble(),
      height: src.height.toDouble(),
    );
  }

  void _updateLocationVisuals() {
    final target = _currentLatLng;
    final expanded = _locationPulseExpanded;
    final icon = expanded ? _locationPuckExpanded : _locationPuckCompact;
    if (!mounted || target == null || icon == null) return;
    final heading = _locationHeading;
    if (kIsWeb) {
      // The web bitmap is turned on screen, not on the ground: take the
      // map's own bearing off, or a rotated map turns the arrow twice.
      _paintWebPuck(
        target: target,
        expanded: expanded,
        heading: heading - _locationCtl.lastMapBearing,
      );
      return;
    }
    _locationCtl.paintUserPuck(target: target, icon: icon, heading: heading);
  }

  Future<void> _paintWebPuck({
    required LatLng target,
    required bool expanded,
    required double heading,
  }) async {
    final gen = ++_webPuckPaintGen;
    final rotated = await _webRotatedPuck(expanded: expanded, heading: heading);
    if (!mounted || gen != _webPuckPaintGen) return;
    _locationCtl.paintUserPuck(
      target: target,
      icon:
          rotated ?? (expanded ? _locationPuckExpanded : _locationPuckCompact)!,
      heading: rotated == null ? heading : 0,
    );
  }

  Future<bool> _startHeadingTracking() {
    return _locationCtl.startHeading(
      isMounted: () => mounted,
      onHeading: (heading) {
        _locationHeading = heading;
        _hasCompassHeading = true;
        _updateLocationVisuals();
      },
    );
  }

  void _handleMapCameraMove(CameraPosition camera) {
    _lastMapZoom = camera.zoom;
    _lastMapTarget = camera.target;
    _locationCtl.noteCameraMove(bearing: camera.bearing);
    final user = _currentLatLng;
    if (user == null) return;
    final shouldShow = AppScope.instance.camera.followOrFree(
      zoom: camera.zoom,
      cameraTarget: GeoPoint(camera.target.latitude, camera.target.longitude),
      user: GeoPoint(user.latitude, user.longitude),
    );
    if (shouldShow != _showRecenterButton && mounted) {
      setState(() => _showRecenterButton = shouldShow);
    }
  }

  Future<void> _recenterOnUser() async {
    unawaited(_startHeadingTracking());
    AppScope.instance.maps.mode = CameraMode.followUser;
    final known = _currentLatLng;
    // Like the driver app: the camera leaves at once, a smooth glide to
    // street zoom leaning with the tilt of that zoom (tiltForZoom), to the
    // position the live stream already has. It used to wait for a fresh
    // high-accuracy fix first (up to latestFixTimeout, 9 s) before moving.
    final flight = known == null ? null : _flyToUser(known, follow: false);
    LatLng? fresh;
    try {
      fresh = await _locationCtl.latestFix();
      if (fresh != null && mounted) {
        _currentLatLng = fresh;
        _locationHeading = _locationCtl.heading;
        _updateLocationVisuals();
      }
    } catch (_) {
      // No fresh fix: the glide to the known position stands.
    }
    if (!mounted) return;
    if (fresh != null &&
        (known == null ||
            AppScope.instance.location.distanceBetween(
                  known.latitude,
                  known.longitude,
                  fresh.latitude,
                  fresh.longitude,
                ) >
                _recenterRefineMeters)) {
      // The fresh fix is somewhere else: steer there. Before it the camera
      // had nowhere to go; after the first glide it is only a correction,
      // which leaves a map the rider has taken back by hand alone.
      await _flyToUser(fresh, follow: known != null);
    } else {
      await flight;
    }
    if (mounted) setState(() => _showRecenterButton = false);
  }

  /// A fresh fix closer than this to the known position does not steer a
  /// running recenter.
  static const double _recenterRefineMeters = 15;

  /// North-up, like the driver app's Home locate: the map does not turn
  /// with the compass; the puck shows the heading.
  Future<void> _flyToUser(LatLng target, {required bool follow}) {
    return AppScope.instance.maps.animateCamera(
      GeoPoint(target.latitude, target.longitude),
      zoom: recenterZoom,
      bearing: 0,
      follow: follow,
    );
  }

  void _loadMarkers() {
    _locationCtl.clearOverlays();
  }

  /// The rider's active promotion, shown as a ticket on top of the sheet.
  /// It is applied only while the sheet rests low, so a promotion arriving
  /// mid-gesture never changes the snaps under the rider's finger.
  RiderPromotion? _promotion;
  Timer? _settleTimer;

  /// Room the promotion ticket takes at the low and middle snaps.
  double get _promotionExtra =>
      _promotion == null ? 0 : PromotionTicket.height + ResSize.h * 10;

  double get _sheetMinPixels => ResSize.h * _sheetMinHeight + _promotionExtra;

  double get _sheetMidPixels => ResSize.h * _sheetMaxHeight + _promotionExtra;

  /// Set once the sheet settles fully open; a swipe down from there goes all
  /// the way to the low snap instead of stopping at the middle.
  bool _skipMiddleSnap = false;
  double? _lastSettledSnap;
  bool _hadFirstSeat = false;

  void _onPromotionChanged() {
    if (!mounted) return;
    // Only re-seat a sheet resting at its low stop; never pull back a sheet
    // the rider (or "Where to?") is opening.
    final previousLow = _lastSettledSnap;
    final offset = _homeSheetController.hasClient
        ? _homeSheetController.metrics?.offset
        : null;
    final wasLow =
        !_destinationSheetOpen &&
        offset != null &&
        offset <= (previousLow ?? offset) + 1.5 &&
        offset < _sheetMidPixels - ResSize.h * 20;
    if (!wasLow && _homeSheetController.hasClient) return;
    final firstSeat = _lastSettledSnap == null;
    setState(() => _promotion = AppScope.instance.promotion.active);
    if (!wasLow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_homeSheetController.hasClient) return;
      if (_destinationSheetOpen) return;
      unawaited(
        _animateHomeSheetTo(
          SheetOffset.absolute(_sheetMinPixels),
          // Right after launch the sheet simply opens at the right height.
          duration: firstSeat
              ? const Duration(milliseconds: 1)
              : MoveraDurations.normal,
        ),
      );
    });
  }

  /// Light haptic at each stop, and remember whether the sheet came down from
  /// the top (then the middle stop is skipped).
  void _trackSettledSnap(double offset) {
    final metrics = _homeSheetController.metrics;
    if (metrics == null) return;
    final full = metrics.maxOffset;
    for (final snap in <double>[_sheetMinPixels, _sheetMidPixels, full]) {
      if ((offset - snap).abs() > 1.5) continue;
      final last = _lastSettledSnap;
      if (last != null && (last - snap).abs() < 1.5) return;
      _lastSettledSnap = snap;
      // Not on the very first seat at launch: only a sheet the rider moved.
      if (last != null || _hadFirstSeat) HapticFeedback.selectionClick();
      _hadFirstSeat = true;
      if (snap == _sheetMinPixels &&
          _promotion != AppScope.instance.promotion.active) {
        _onPromotionChanged();
      }
      final skip = snap == full;
      if (skip != _skipMiddleSnap && (skip || snap == _sheetMinPixels)) {
        setState(() => _skipMiddleSnap = skip);
      }
      return;
    }
    final last = _lastSettledSnap;
    if (last != null && (offset - last).abs() > 6) _lastSettledSnap = null;
  }

  bool get _isSheetAtMiddle => _sheetCtl.isAtMiddle;

  void _cancelSheetIdleTimer() => _sheetCtl.cancelIdleTimer();

  void _scheduleSheetIdleClose() {
    _sheetCtl.scheduleIdleClose(
      accessibleNavigation:
          MediaQuery.maybeOf(context)?.accessibleNavigation ?? false,
      isMounted: () => mounted,
    );
  }

  void _syncHomeSheetState() {
    if (!mounted || !_homeSheetController.hasClient) return;
    final offset = _homeSheetController.metrics?.offset;
    if (offset == null) return;

    if (_isSheetAtMiddle) {
      _scheduleSheetIdleClose();
    } else {
      _cancelSheetIdleTimer();
    }

    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || !_homeSheetController.hasClient) return;
      final settled = _homeSheetController.metrics?.offset;
      if (settled != null) _trackSettledSnap(settled);
    });

    final expanded = offset > _sheetMidPixels + ResSize.h * 8;
    if (expanded != _destinationSheetOpen) {
      setState(() => _destinationSheetOpen = expanded);
    }
    final covering = offset > _sheetMinPixels + 12;
    setWebOverlayOpen(covering);
  }

  Future<void> _animateHomeSheetTo(
    SheetOffset target, {
    Duration duration = MoveraDurations.large,
    Curve curve = MoveraCurves.open,
  }) => _sheetCtl.animateTo(target, duration: duration, curve: curve);

  Future<void> _openDestinationSheet() async {
    if (!_destinationSheetOpen) setState(() => _destinationSheetOpen = true);
    await _sheetCtl.open();
  }

  void _closeDestinationSheet() {
    if (_destinationSheetOpen) setState(() => _destinationSheetOpen = false);
    _sheetCtl.close();
  }

  void _toggleHomeSheet() => _sheetCtl.toggle(expandedThreshold: ResSize.h * 8);

  /// Book for later: the same Where to as Book now, then the date and time,
  /// then the categories in scheduled mode (Set pickup comes after Schedule).
  Future<void> _openSchedule() => _runRouteFlow(
    () => _showRouteAddressPicker(initialField: 'destination', scheduled: true),
  );

  void _openPayment() => _openTab(HomeTabs.payment);

  /// Opens a bottom-bar tab over Home. A horizontal swipe on that page
  /// hands back the neighbouring tab's index, so the rider can slide
  /// Home → Payment → Account and back without tapping. Schedule ride is a
  /// booking flow, not a page, so the swipe skips it (NAV-5).
  void _openTab(int first) {
    unawaited(
      _runRouteFlow(() => _withParkedHomeMap<void>(() async {
        var current = HomeTabs.home;
        int? next = first;
        while (next != null && next != HomeTabs.home && mounted) {
          final forward = next > current;
          current = next;
          final page = HomeTabPage(
            tab: next,
            child: next == HomeTabs.payment
                ? const WalletAndPaymentsScreen(initialTab: 1)
                : const AccountHomePage(),
          );
          next = await Navigator.of(context).push<int>(
            forward ? RightToLeftTransition(page) : LeftToRightTransition(page),
          );
        }
      })),
    );
  }

  /// The full-screen menu, with Home's map parked underneath like the
  /// other full-screen pages.
  void _openMenu() {
    unawaited(() async {
      // NAV-6: the menu's Where to / Later leave the menu first; Home runs
      // the chosen flow only after the menu's park scope has finished, so
      // its cleanup cannot close the sheet the flow just opened.
      Future<void> Function()? then;
      await _withParkedHomeMap(() {
        return RiderMenuPage.open(
          context,
          onStartBooking: () => then = _handleDestinationTap,
          onSchedule: () => then = _openSchedule,
        );
      });
      if (!mounted) return;
      await then?.call();
    }());
  }

  void _openAccount() => _openTab(HomeTabs.account);

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final topInset = MediaQuery.of(context).padding.top + ResSize.h * 8;
    final fullSheetPixels = viewportHeight - topInset;

    return PopScope(
      canPop: !_destinationSheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_destinationSheetOpen) {
          _closeDestinationSheet();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFEEF1E8),
        extendBody: true,
        body: FocusTraversalGroup(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _cancelSheetIdleTimer(),
            onPointerUp: (_) => _scheduleSheetIdleClose(),
            onPointerCancel: (_) => _scheduleSheetIdleClose(),
            child: Stack(
              children: [
                SizedBox(
                  height: viewportHeight,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: HomeMapLayer(
                            location: _locationCtl,
                            parked: _mapParked,
                            padding: EdgeInsets.only(bottom: _sheetMinPixels),
                            initialPosition: _initialPosition,
                            mapStyle: homeMapStyle,
                            onCameraMove: _handleMapCameraMove,
                            onMapCreated: (GoogleMapController controller) {
                              AppScope.instance.maps.attach(
                                controller,
                                owner: MapOwners.home,
                              );
                              final view = mapViewOf(controller);
                              _locationCtl.mapBusy = () =>
                                  view.touching || view.easing;
                              AppScope.instance.mapLifecycle.created();
                              final target = _currentLatLng ?? _cameraHint;
                              if (target != null) {
                                AppScope.instance.maps.animateCamera(
                                  GeoPoint(target.latitude, target.longitude),
                                  zoom: homeOpeningZoom,
                                  follow: true,
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      if (_showRecenterButton && _currentLatLng != null)
                        Positioned(
                          right: ResSize.w * 18,
                          bottom: _sheetMinPixels + ResSize.h * 14,
                          child: PointerInterceptor(
                            child: Tooltip(
                              message: context.l10n.homeRecenterMap,
                              child: Semantics(
                                button: true,
                                label: context.l10n.homeRecenterMap,
                                child: Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  elevation: 8,
                                  shadowColor: Colors.black26,
                                  child: InkWell(
                                    onTap: _recenterOnUser,
                                    customBorder: const CircleBorder(),
                                    child: const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(
                                        Icons.near_me_outlined,
                                        color: _premiumInk,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      HomeLocationNotice(location: _locationCtl, bottom: _sheetMinPixels, onRetry: _detectCurrentAddress),
                      if (_destinationSheetOpen)
                        Positioned.fill(
                          // UI-13: a plain 5% white wash. The 1.4 sigma
                          // backdrop blur over the platform map was costly
                          // (web, low-end Android) and almost invisible.
                          child: IgnorePointer(
                            key: const ValueKey('home-sheet-open-wash'),
                            child: ColoredBox(
                              color: AppColor.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                      Positioned(
                        left: screenHorizPadding,
                        top: ResSize.h * 60,
                        child: HomeReservationChrono(
                          onRebook: () => unawaited(_openSchedule()),
                          openRoute: _withParkedHomeMap,
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            screenHorizPadding,
                            ResSize.h * 50,
                            screenHorizPadding,
                            0,
                          ),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Builder(
                              builder: (drawerContext) => PremiumTopActions(
                                onMenuTap: _openMenu,
                                onAccountTap: _openAccount,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SheetViewport(
                  child: Builder(
                    builder: (context) {
                      // These four pieces never depend on the drag animation
                      // itself - only on state that changes via setState (the
                      // destination/saved-places data, not the sheet offset).
                      // Building them once per real rebuild, instead of inside
                      // the AnimatedBuilder's per-frame builder below, avoids
                      // reconstructing this subtree on every drag tick.
                      final premiumToggleHandle = Semantics(
                        button: true,
                        label: context.l10n.homeTogglePanel,
                        child: Tooltip(
                          message: context.l10n.homeTogglePanel,
                          child: InkWell(
                            onTap: _toggleHomeSheet,
                            borderRadius: BorderRadius.circular(14),
                            // UI-4: 48 x 44 target (was 48 x 32). It starts
                            // 6 px higher and the gap below is 6 px shorter,
                            // so the bar and the content stay where they were.
                            child: SizedBox(
                              width: 48,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: ResSize.w * 42,
                                  height: ResSize.h * 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCED4D8),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      final premiumWhereToCard = WhereToCard(
                        destinationAddress: _destinationAddress,
                        onDestinationTap: _handleDestinationTap,
                        onOpenSchedule: _openSchedule,
                      );
                      Widget premiumSavedPlacesContent(double reveal) => Column(
                        children: [
                          15.height,
                          SavedPlacesRow(
                            homeAddress: _placeOrNull(_homeAddress),
                            workAddress: _placeOrNull(_workAddress),
                            savedPlaces: _savedPlaces,
                            reveal: reveal,
                            onUseSavedPlace: _useSavedPlaceAsDestination,
                            onEditSavedPlace: _editSavedPlace,
                            onEditCustomPlace: _editCustomPlace,
                            onAddPlace: _openAddPlacePicker,
                          ),
                        ],
                      );
                      final premiumDetailContent = Column(
                        children: [
                          AdvanceBookingCard(onOpenSchedule: _openSchedule),
                          12.height,
                          HomeJourneySection(
                            onDestinationTap: _handleDestinationTap,
                            onOpenSchedule: _openSchedule,
                            onRideTypeTap: (rideId) =>
                                _handleDestinationTap(initialRideId: rideId),
                          ),
                        ],
                      );
                      return Sheet(
                        controller: _homeSheetController,
                        initialOffset: SheetOffset.absolute(_sheetMinPixels),
                        physics: MoveraSheetMotion.physics,
                        snapGrid: SheetSnapGrid(
                          snaps: [
                            SheetOffset.absolute(_sheetMinPixels),
                            if (!_skipMiddleSnap)
                              SheetOffset.absolute(_sheetMidPixels),
                            const SheetOffset(1),
                          ],
                          minFlingSpeed: 520,
                        ),
                        scrollConfiguration: const SheetScrollConfiguration(),
                        child: PointerInterceptor(
                          child: SizedBox(
                            height: fullSheetPixels,
                            width: double.infinity,
                            child: AnimatedBuilder(
                              animation: _homeSheetController,
                              builder: (context, child) {
                                final sheetHeight =
                                    _homeSheetController.hasClient
                                    ? (_homeSheetController.metrics?.offset ??
                                          _sheetMinPixels)
                                    : _sheetMinPixels;
                                final sheetProgress =
                                    ((sheetHeight - _sheetMinPixels) /
                                            (_sheetMidPixels - _sheetMinPixels))
                                        .clamp(0.0, 1.0);
                                final rawDetailProgress =
                                    ((sheetHeight - _sheetMidPixels) /
                                            (fullSheetPixels - _sheetMidPixels))
                                        .clamp(0.0, 1.0);
                                final detailProgress = Curves.easeInCubic
                                    .transform(rawDetailProgress);
                                return _premiumCollapsedSheet(
                                  sheetProgress,
                                  detailProgress,
                                  sheetHeight,
                                  toggleHandle: premiumToggleHandle,
                                  whereToCard: premiumWhereToCard,
                                  savedPlacesContent: premiumSavedPlacesContent,
                                  detailContent: premiumDetailContent,
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _premiumCollapsedSheet(
    double sheetProgress,
    double detailProgress,
    double sheetHeight, {
    required Widget toggleHandle,
    required Widget whereToCard,
    required Widget Function(double reveal) savedPlacesContent,
    required Widget detailContent,
  }) {
    final promotion = _promotion;
    // Content keeps its full size and slides/fades in instead of being cut.
    final placesReveal = Curves.easeOutCubic.transform(
      ((sheetProgress - 0.25) / 0.75).clamp(0.0, 1.0),
    );
    final detailReveal = Curves.easeOutCubic.transform(
      ((detailProgress - 0.15) / 0.85).clamp(0.0, 1.0),
    );
    final ticketVisible = 1 - Curves.easeOutCubic.transform(detailProgress);
    // UI-4: the toggle handle's target is 12 px taller than the 32 px it
    // used to be; half comes out of the padding above, half out of the gap.
    final handleLift = math.min(6.0, ResSize.h * 11);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(34),
          topRight: Radius.circular(34),
        ),
      ),
      child: HorizontalSwipe(
        onSwipeLeft: _openPayment,
        child: SafeArea(
          top: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              HomeSheetScroll(child: Padding(
                padding: EdgeInsets.fromLTRB(
                  ResSize.w * 18,
                  ResSize.h * 11 - handleLift,
                  ResSize.w * 18,
                  ResSize.h * 7,
                ),
                child: Column(
                  children: [
                    toggleHandle,
                    SizedBox(
                      height: math.max(0.0, ResSize.h * 12 + handleLift - 12),
                    ),
                    if (promotion != null)
                      IgnorePointer(
                        ignoring: ticketVisible < 0.6,
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: ticketVisible,
                          child: Opacity(
                            opacity: ticketVisible,
                            child: Transform.translate(
                              offset: Offset(0, -10 * (1 - ticketVisible)),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: ResSize.h * 10,
                                ),
                                child: PromotionTicket(promotion: promotion),
                              ),
                            ),
                          ),
                        ),
                      ),
                    whereToCard,
                    IgnorePointer(
                      ignoring: sheetProgress < 0.92,
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: sheetProgress,
                        child: savedPlacesContent(placesReveal),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: detailProgress < 0.92,
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: detailProgress,
                        child: Opacity(
                          opacity: detailReveal,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - detailReveal)),
                            child: Padding(
                              padding: EdgeInsets.only(top: ResSize.h * 24),
                              child: detailContent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
              Positioned(
                left: ResSize.w * (18 + (12 * (1 - sheetProgress))),
                right: ResSize.w * (18 + (12 * (1 - sheetProgress))),
                top:
                    sheetHeight - ResSize.h * (63 + (30 * (1 - sheetProgress))),
                child: Transform.scale(
                  scale: 0.84 + (0.16 * sheetProgress),
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    // UI-4: the vertical padding is passed to the items as
                    // hitSlop, so the targets reach the bar's edges.
                    padding: EdgeInsets.symmetric(
                      horizontal: ResSize.w * (4 * (1 - sheetProgress)),
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.white,
                      borderRadius: BorderRadius.circular(
                        32 * (1 - sheetProgress),
                      ),
                      border: Border.all(
                        color: _premiumLine.withValues(
                          alpha: 1 - sheetProgress,
                        ),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.14 * (1 - sheetProgress),
                          ),
                          blurRadius: 28 * (1 - sheetProgress),
                          offset: Offset(0, 10 * (1 - sheetProgress)),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: sheetProgress,
                          child: const Divider(
                            color: Color(0xFFE7EBEE),
                            thickness: 0.8,
                            height: 1,
                          ),
                        ),
                        SizedBox(height: ResSize.h * (9 * sheetProgress)),
                        Row(
                          children: [
                            Expanded(
                              child: PremiumBottomNavItem(
                                iconAsset: AppAssets.solarHome,
                                label: context.l10n.navHome,
                                active: true,
                                floatingFraction: 1 - sheetProgress,
                                hitSlop: ResSize.h * (5 * (1 - sheetProgress)),
                                onTap: () => _animateHomeSheetTo(
                                  SheetOffset.absolute(_sheetMinPixels),
                                ),
                              ),
                            ),
                            Expanded(
                              child: PremiumBottomNavItem(
                                iconAsset: AppAssets.solarWallet,
                                label: context.l10n.navPayment,
                                floatingFraction: 1 - sheetProgress,
                                hitSlop: ResSize.h * (5 * (1 - sheetProgress)),
                                onTap: _openPayment,
                              ),
                            ),
                            Expanded(
                              child: PremiumBottomNavItem(
                                iconAsset: AppAssets.solarCalendar,
                                label: context.l10n.navScheduleRide,
                                floatingFraction: 1 - sheetProgress,
                                hitSlop: ResSize.h * (5 * (1 - sheetProgress)),
                                onTap: _openSchedule,
                              ),
                            ),
                            Expanded(
                              child: PremiumBottomNavItem(
                                iconAsset: AppAssets.solarUser,
                                label: context.l10n.navAccount,
                                floatingFraction: 1 - sheetProgress,
                                hitSlop: ResSize.h * (5 * (1 - sheetProgress)),
                                onTap: _openAccount,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
