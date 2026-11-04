import 'dart:async';

import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/application/home_presence.dart';
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
import 'package:movera_rider/core/maps/map_camera_controller.dart'
    show recenterZoom;
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
import 'package:movera_rider/app/deferred_screens.dart';
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
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_edge.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_layout.dart';
import 'package:movera_rider/shared/widgets/horizontal_swipe.dart';
import 'package:movera_rider/features/home/presentation/widgets/advance_booking_card.dart';
import 'package:movera_rider/features/home/presentation/widgets/liquid_glass_nav.dart';
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
import 'package:movera_rider/features/content/presentation/content_banners.dart';

part 'home_address_pickers.dart';
part 'home_collapsed_sheet.dart';
part 'home_location.dart';
part 'home_map_controls.dart';
part 'home_routes.dart';

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

  /// Live test 2026-10-30 (contract v0.18.4 `driverHome.ridersOnline`): a
  /// rider on Home is counted online in his zone by the server.
  late final HomePresence _presence = HomePresence(
    ping: HomePresence.nearbyCars(AppScope.instance.api),
    position: () {
      final at = _currentLatLng;
      return at == null ? null : GeoPoint(at.latitude, at.longitude);
    },
    signedIn: _riderSignedIn,
  );

  /// Only a live build: the demo has no server to count riders.
  void _startPresence() {
    if (AppEnv.current.authRequired) _presence.start();
  }

  /// A live build with a session; the demo never asks the server.
  static Future<bool> _riderSignedIn() async {
    if (!AppEnv.current.authRequired) return false;
    final access = await AppScope.instance.tokens.readAccess();
    return access != null && access.isNotEmpty;
  }

  StreamSubscription<void>? _savedPlacesSubscription;
  bool _showRecenterButton = true;

  /// The rider's pin, one bitmap per camera tilt bucket
  /// ([MoveraRiderPuckMarker.tiltBucket]); 0 is the flat dot.
  final Map<int, BitmapDescriptor> _pins = {};

  /// The grey halo under the pin ([RiderAccuracyHalo]).
  BitmapDescriptor? _halo;
  bool _tiltPinsStarted = false;
  int? _paintedPinBucket;

  // The search card ends around 113 logical px from the top of the sheet.
  // Leave space for the floating navigation bar below it at the collapsed snap.
  static const double _sheetMinHeight = 214;
  static const double _sheetMaxHeight = 294;

  bool _destinationSheetOpen = false;
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

  /// rider-r5-37: the confirmed points of the last route's destination and
  /// stops, with the labels they belong to. Where to? opens with them while
  /// those labels are still the route, so they are not located again.
  ({String address, GeoPoint point})? _destinationFix;
  ({List<String> stops, List<GeoPoint?> points})? _stopFixes;

  GeoPoint? get _routeDestinationPoint {
    final fix = _destinationFix;
    return fix != null && fix.address == _destinationAddress ? fix.point : null;
  }

  List<GeoPoint?> get _routeStopPoints {
    final fixes = _stopFixes;
    return fixes != null && listEquals(fixes.stops, _routeStops)
        ? fixes.points
        : const <GeoPoint?>[];
  }

  set _routeStops(List<String> value) => _places.routeStops = value;
  LatLng? get _currentLatLng => _places.currentLatLng;
  set _currentLatLng(LatLng? value) => _places.currentLatLng = value;

  /// rider-u114: the GPS point a pickup may start from. Null while only
  /// approximate location is allowed: that fix centres the map and draws
  /// the puck, but the rider sets the pickup pin themselves.
  LatLng? get _gpsPickup =>
      _locationCtl.preciseLocationOff || _roughFix ? null : _currentLatLng;

  /// Owner round 1: [_currentLatLng] is only the quick first position (the
  /// OS's cached fix or a coarse one). It draws the puck and centres the
  /// camera, but it is never the pickup and is not the first fix: retries
  /// and an app resume still wait for the accurate one.
  bool _roughFix = false;

  /// Whether the accurate first fix has landed.
  bool get _hasFix => _currentLatLng != null && !_roughFix;

  /// Where a quick position last put the camera; an accurate fix within
  /// [HomeLocationController.quickFixRefineMeters] of it leaves it there.
  LatLng? _quickCameraAt;

  /// Completes when the running detection has its accurate point (before
  /// the address), so the booking flow need not wait for the geocode.
  Completer<void>? _locatedSignal;
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
    _startPresence();
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
      if (_routeFlowOpen) {
        // Plan your ride has just closed and its flow is still deciding
        // (normalising the route, the pickup street): within a frame or so
        // it opens the categories screen and parks Home again. Creating a
        // Google map for that moment cost a whole map per booking (on the
        // web every map lives on in the plugin's registry), so Home waits a
        // little; a slow lookup still gets its map back.
        _routeFlowResumeTimer ??= Timer(routeFlowResumeGrace, () {
          _routeFlowResumeTimer = null;
          if (!mounted || _mapParkingGuard.isParked) return;
          if (_homeIsCurrent && _mapParked.value) _resumeHomeMap();
        });
        return;
      }
      _resumeHomeMap();
    }
  }

  /// How long Home, back on top with its map parked while a route flow is
  /// still running, waits for that flow to open the next screen before it
  /// shows a map again (see [_syncRouteParking]).
  @visibleForTesting
  static Duration routeFlowResumeGrace = const Duration(milliseconds: 1500);
  Timer? _routeFlowResumeTimer;

  void _parkHomeMap() {
    _routeFlowResumeTimer?.cancel();
    _routeFlowResumeTimer = null;
    if (_mapParked.value) return;
    setWebOverlayOpen(false);
    _webOverlayCovering = null;
    _mapParked.value = true;
    _presence.stop();
    _locationCtl.pauseLiveUpdates();
    AppScope.instance.mapLifecycle.park();
    AppScope.instance.maps.detach(owner: MapOwners.home);
  }

  void _resumeHomeMap() {
    if (!_mapParked.value) return;
    AppScope.instance.mapLifecycle.resume();
    _locationCtl.resumeLiveUpdates();
    _mapParked.value = false;
    _startPresence();
    // The sheet may rest open over the map again without moving.
    final offset = _homeSheetController.hasClient
        ? _homeSheetController.metrics?.offset
        : null;
    if (offset != null) _syncWebOverlay(offset);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _locationCtl.pauseLiveUpdates();
      _presence.stop();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // RIDE-14: a parked Home (a ride or another page above it) stays paused;
    // it resumes when the map is unparked.
    if (_mapParked.value) return;
    _locationCtl.resumeLiveUpdates();
    _startPresence();
    // rider-u118: no first fix was ever bound (it failed or is still
    // pending): run the whole first-fix path (puck, label, stream, camera).
    // Restarting only the stream tracked GPS but never drew the puck.
    if (!_hasFix) {
      // rider-43: a resume never prompts again; a rider who allowed
      // location in Settings meanwhile still gets the fix.
      unawaited(_detectCurrentAddress(askPermission: false));
      return;
    }
    // rider-u114: precise location may have been turned on or off in
    // Settings meanwhile.
    unawaited(_recheckPrecision());
    if (_locationCtl.state == HomeLocationState.temporarilyUnavailable) {
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
    _routeFlowResumeTimer?.cancel();
    _detectRetryTimer?.cancel();
    _savedPlacesSubscription?.cancel();
    _presence.dispose();
    _sheetCtl.dispose();
    _locationCtl.dispose();
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

  /// Coarse camera hint from [HomeLocationController.quickCameraFix].
  LatLng? _cameraHint;

  Future<void>? _detectInFlight;

  /// rider-u119: a first fix that failed for a transient reason (the
  /// 16 s timeout of a cold GPS, a platform error) is tried again with
  /// backoff while Home has no fix, instead of waiting for an app resume.
  Timer? _detectRetryTimer;
  int _detectRetries = 0;

  /// rider-u114: the notice's "Turn on" button.
  Future<void> _turnOnPreciseLocation() async {
    final wasOff = _locationCtl.preciseLocationOff;
    await _locationCtl.requestPreciseLocation();
    if (!mounted) return;
    if (!_hasFix) {
      await _detectCurrentAddress(askPermission: false);
    } else if (wasOff != _locationCtl.preciseLocationOff) {
      _applyPrecisionChange();
    }
  }

  /// Detects the rider's location once; a second call while one is running
  /// joins it, so the booking flow can wait for the fix Home already asked
  /// for instead of asking again.
  Future<void> _detectCurrentAddress({bool askPermission = true}) {
    return _detectInFlight ??=
        _runDetectCurrentAddress(askPermission: askPermission).whenComplete(() {
          _detectInFlight = null;
        });
  }

  Future<void> _runDetectCurrentAddress({bool askPermission = true}) async {
    final located = _locatedSignal = Completer<void>();
    if (mounted) setState(() {});
    try {
      Future<void>? binding;
      final detected = await _locationCtl.detectCurrent(
        askPermission: askPermission,
        onQuickFix: (point) => unawaited(_showQuickFix(point)),
        // Owner round 1: puck, pickup point and camera before the address.
        onLocated: (fix) => binding ??= _bindFirstFix(fix),
      );
      if (!mounted) return;
      final target = detected.target;
      if (detected.denied || target == null) {
        // U2: no fix — never call a fallback point "Current location".
        if (isPlaceholderPickupLabel(_pickupAddress)) {
          setState(() => _pickupAddress = locationOffPickupLabel);
        }
        if (detected.failure == HomeLocationFailure.unavailable && !_hasFix) {
          _scheduleDetectRetry();
        }
        return;
      }
      // An approximate fix is named no address; it is bound here.
      await (binding ??= _bindFirstFix(detected));
      if (!mounted) return;
      // The address, once the reverse geocode answers. Never over a pickup
      // set meanwhile (a flow, a dropped pin).
      if (!detected.approximate &&
          _tripPickupLatLng == null &&
          isPlaceholderPickupLabel(_pickupAddress) &&
          detected.address != _pickupAddress) {
        setState(() => _pickupAddress = detected.address);
      }
    } catch (_) {
      if (!mounted) return;
      if (isPlaceholderPickupLabel(_pickupAddress)) {
        setState(() => _pickupAddress = locationOffPickupLabel);
      }
    } finally {
      if (!located.isCompleted) located.complete();
    }
  }

  /// Owner round 1: the quick first position. Puck and camera at once; the
  /// accurate fix ([_bindFirstFix]) takes over when it lands.
  Future<void> _showQuickFix(LatLng point) async {
    if (!mounted || _hasFix) return;
    setState(() {
      _currentLatLng = point;
      _roughFix = true;
    });
    await _prepareLocationPuckIcons();
    if (!mounted || !_roughFix) return;
    _updateLocationVisuals();
    _cameraHint = point;
    final maps = AppScope.instance.maps;
    // Map not created yet: onMapCreated centres on [_currentLatLng].
    if (_mapParked.value || maps.activeOwner != MapOwners.home) return;
    _quickCameraAt = point;
    await maps.moveCamera(
      GeoPoint(point.latitude, point.longitude),
      zoom: homeOpeningZoom,
    );
  }

  /// The accurate first fix: the pickup point, the puck, live tracking and
  /// the camera. Runs before the address is known.
  Future<void> _bindFirstFix(DetectedLocation detected) async {
    final target = detected.target;
    if (!mounted || target == null) return;
    final wasRough = _roughFix;
    _detectRetryTimer?.cancel();
    _detectRetryTimer = null;
    _detectRetries = 0;
    setState(() {
      // rider-u114: an approximate fix names no pickup ('set pickup');
      // a precise one is the current location until its address comes.
      _pickupAddress = detected.approximate
          ? detected.address
          : (isPlaceholderPickupLabel(detected.address)
                ? 'Current location'
                : detected.address);
      _pickupLabelAt = target;
      _currentLatLng = target;
      _roughFix = false;
      _locationCtl.clearOverlays();
      _locationHeading = detected.heading;
    });
    final located = _locatedSignal;
    if (located != null && !located.isCompleted) located.complete();
    // The quick puck moves to the accurate point instead of blinking out.
    if (wasRough) _updateLocationVisuals();
    // Called while the geocode still runs: it handles its own errors.
    try {
      await _prepareLocationPuckIcons();
      // rider-u120: Home may have been replaced while the icons were drawn.
      if (!mounted) return;
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
      if (!mounted || _mapParked.value || maps.activeOwner != MapOwners.home) {
        return;
      }
      // Owner round 1: the camera already sits on a quick position this
      // close: no jump for a few metres of refinement.
      final quick = _quickCameraAt;
      _quickCameraAt = null;
      if (quick != null &&
          AppScope.instance.location.distanceBetween(
                quick.latitude,
                quick.longitude,
                target.latitude,
                target.longitude,
              ) <=
              HomeLocationController.quickFixRefineMeters) {
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
        resolvedPickupPosition = _gpsPickup;
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

  Future<void> _handleDestinationTap({
    String? initialRideId,
  }) => _runRouteFlow(() async {
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
      // rider-u121: a saved place is a new route; stops left by an earlier
      // Where to flow the rider backed out of are not carried into it.
      _routeStops = const <String>[];
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
        case GeocodeFailed():
          // rider-45: offline or the lookup failed; say so, never abort
          // silently.
          if (mounted) {
            MoveraToast.show(context, context.l10n.routeCouldNotReach);
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
            stops: const <String>[],
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
        // A route flow that goes on (Back on the categories screen reopens
        // Plan your ride) gets the grace of [_syncRouteParking] instead of
        // a map for the frame in between.
        if (_homeIsCurrent) {
          if (_routeFlowOpen) {
            _syncRouteParking();
          } else {
            _resumeHomeMap();
          }
        }
      }
    }
  }

  /// RIDE-10: the next booking starts from the rider's current location,
  /// not from the last flow's pickup street.
  int _pickupLabelGeneration = 0;
  LatLng? _pickupLabelAt;

  /// N7: when the pickup label was last asked of the geocoder, so an unnamed
  /// pickup is retried on the live fixes no more than every few seconds.
  DateTime? _pickupLabelAskedAt;

  void _resetPickupLabel() {
    final here = _gpsPickup;
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
    // N7: a coarse fix names no street; the next good fix relabels.
    if (!HomeLocationController.nameable(_locationCtl.lastFixAccuracyMeters)) {
      return;
    }
    _pickupLabelAskedAt = DateTime.now();
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
    final gps = _gpsPickup;
    // rider-u114: an approximate fix still opens the picker near the rider,
    // as a fallback point the rider has to move.
    final initialPosition =
        chosen ?? gps ?? _currentLatLng ?? _initialPosition.target;
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
        title: isDestination
            ? context.l10n.confirmDestination
            : context.l10n.confirmPickupSpot,
        confirmLabel: isDestination
            ? context.l10n.confirmDestination
            : context.l10n.confirmPickup,
        positionIsFallback: positionIsFallback,
        // U6 / D-011: opened at GPS (or the fallback) — take a fresh fix.
        // rider-u114: never re-seeded from an approximate fix.
        refreshCurrentLocation:
            chosen == null && !_locationCtl.preciseLocationOff,
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
    GeoPoint? point, {
    bool throwOnFailure = false,
  }) async {
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
        case GeocodeFailed():
          // rider-45: the lookup failed; the typed pickup is not swapped for
          // GPS either.
          if (throwOnFailure) throw const RouteLookupFailed();
          if (mounted) {
            MoveraToast.show(context, context.l10n.routeCouldNotReach);
          }
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
      position: _currentLatLng ?? _initialPosition.target,
      isFallback: true,
    );
  }

  /// The step after the rider taps a real destination.
  ///
  /// Runs under the address screen, which stays open: a lookup the server
  /// could not answer (offline, a timeout, a 5xx while it wakes) is thrown
  /// as [RouteLookupFailed], so the screen says so with Try again instead
  /// of a toast under it that reads as a silent return to Home.
  Future<Map<String, dynamic>?> _confirmRouteSelection(
    RoutePickerSelection selection, {
    bool scheduled = false,
  }) async {
    // Book now always confirms pickup; GPS only prefills. The confirm step
    // is Set pickup, opened after Book on the categories screen.
    final pickup = await _prefillPickup(
      selection.pickup,
      selection.pickupPoint,
      throwOnFailure: true,
    );
    if (pickup == null || !mounted) return null;
    var destination = selection.destination;
    var destinationPoint = selection.destinationPoint;
    if (destinationPoint == null) {
      final outcome = await _locationCtl.resolvePlace(destination);
      final geocoded = outcome.valueOrNull;
      if (geocoded == null) {
        if (outcome is GeocodeFailed) throw const RouteLookupFailed();
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
      // config names; rider-r4-10: up to the zone's reservation horizon,
      // as on the schedule screen.
      final window = await AppScope.instance.riderConfig.bookingWindowAt(
        pickup.position.latitude,
        pickup.position.longitude,
      );
      if (!mounted) return null;
      // Owner A (v0.18.19): Book later is off in this zone: say so, book
      // nothing (the button stays on screen).
      if (!window.reservationsOn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(context.l10n.resErrZoneOff)));
        return null;
      }
      scheduledAt = await ScheduleDateTimeSelector.choose(
        context,
        timeZone: window.timeZone,
        horizonDays: window.horizonDays,
        freeChangeBeforeMin: window.freeChangeBeforeMin,
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
      // rider-r5-36: the points the rider picked, so no stop is located
      // again from its label.
      'stopPoints': [
        for (var i = 0; i < selection.stops.length; i++)
          i < selection.stopPoints.length ? selection.stopPoints[i] : null,
      ],
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
    };
  }

  Future<void> _showRouteAddressPicker({
    required String initialField,
    EarlyInputCapture? capture,
    bool scheduled = false,
    String? initialRideId,
    GeoPoint? pickupPoint,
  }) async {
    // Either the capture the caller started at tap time, or a fresh one for
    // entry points that open the picker directly.
    final routeCapture = capture ?? (EarlyInputCapture()..start());
    final ownsCapture = capture == null;
    final gps = _gpsPickup;
    // Owner round 1: reopened from the categories screen, the picker starts
    // from the pickup the rider had confirmed, not from GPS.
    final here =
        pickupPoint ??
        (gps == null ? null : GeoPoint(gps.latitude, gps.longitude));
    Map<String, dynamic>? draft;
    try {
      draft = await Navigator.of(context).push<Map<String, dynamic>>(
        BottomToTopTransition(
          RoutePickerPage(
            pickupAddress: _placeOrNull(_pickupAddress),
            destinationAddress: _destinationAddress ?? '',
            destinationPoint: _routeDestinationPoint,
            stops: _stopsSupported ? _routeStops : const <String>[],
            stopPoints: _stopsSupported ? _routeStopPoints : const [],
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
    final rawStopPoints = (draft['stopPoints'] as List<dynamic>? ?? const [])
        .map((point) => point is GeoPoint ? point : null)
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
    final stops = <String>[];
    final stopPoints = <GeoPoint?>[];
    final normalizedStops = normalizedRoute.skip(2).toList();
    for (var i = 0; i < normalizedStops.length; i++) {
      if (normalizedStops[i].isEmpty) continue;
      stops.add(normalizedStops[i]);
      stopPoints.add(i < rawStopPoints.length ? rawStopPoints[i] : null);
    }
    if (!mounted) return;
    final pickupLat = draft['pickupLat'] as double?;
    final pickupLng = draft['pickupLng'] as double?;
    final pickupIsFallback = draft['pickupIsFallback'] == true;
    final exactPickupPosition = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat, pickupLng)
        : (_tripPickupLatLng ?? _gpsPickup);
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
      _stopFixes = (stops: List.of(stops), points: List.of(stopPoints));
      if (destination.isNotEmpty && exactDestinationPosition != null) {
        _destinationFix = (
          address: destination,
          point: GeoPoint(
            exactDestinationPosition.latitude,
            exactDestinationPosition.longitude,
          ),
        );
      }
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
            SnackBar(content: Text(context.l10n.homeChooseValidRoute)),
          );
        }
        return;
      }
      final scheduledAt = DateTime.tryParse(
        draft['scheduledAt'] as String? ?? '',
      );
      // Owner round 1: what tells a plain Back on the categories screen from
      // a booking or a schedule, which leave it another way.
      final rideBefore = AppScope.instance.ride.rideId;
      final statusBefore = AppScope.instance.ride.status;
      var scheduledHere = false;
      // Park the Home map before opening categories. Two Google Maps at once
      // crashes the browser tab on Flutter web.
      final result = await _withParkedHomeMap(() {
        return Navigator.of(context).push<Object?>(
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
              stopPoints: List<GeoPoint?>.from(stopPoints),
              bookingMode: scheduledAt == null
                  ? BookingMode.now
                  : BookingMode.scheduled,
              lockBookingMode: scheduledAt != null,
              initialScheduledFor: scheduledAt,
              // NAV-11: a Home card asked for this category.
              initialRideId: initialRideId,
              onScheduled: (context, id) {
                scheduledHere = true;
                return RideScheduledPage.open(
                  context,
                  reservationId: id,
                  replace: scheduledAt == null,
                  untilHome: scheduledAt != null,
                );
              },
            ),
            settings: const RouteSettings(name: AppRoutes.selectRide),
          ),
        );
      });
      // Owner round 1: Back (the arrow or the system back) on the
      // categories screen returns to the address screen, filled with the
      // same route, instead of Home. Only for a plain Back: Home on top
      // again, no result, nothing booked or scheduled. Each reopen waits
      // for the rider, so this cannot loop.
      final ride = AppScope.instance.ride;
      final backedOut =
          mounted &&
          result == null &&
          !scheduledHere &&
          _homeIsCurrent &&
          ride.rideId == rideBefore &&
          ride.status == statusBefore;
      if (!backedOut) return;
      await _showRouteAddressPicker(
        initialField: 'destination',
        scheduled: scheduled,
        initialRideId: initialRideId,
        pickupPoint: pickupIsFallback
            ? null
            : GeoPoint(pickupPosition.latitude, pickupPosition.longitude),
      );
    }
  }

  Future<void> _openAddPlacePicker() async {
    if (_savedPlaces.length >= _maxCustomPlaces) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.homeMaxCustomPlaces)));
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

  /// A fresh draw each time (no shared in-flight future, so a draw that
  /// never finished cannot hold every later attempt).
  static Future<BitmapDescriptor> _drawPin(int tilt, double ratio) async {
    final visual = await MoveraRiderPuckMarker.createVisual(
      tilt: tilt.toDouble(),
      pixelRatio: ratio,
    );
    visual.image.dispose();
    return visual.icon;
  }

  /// Paints the rider's pin: a screen-fixed bitmap, the same size at every
  /// zoom ("Blue must be same in all zoom steps"). It is round, so the
  /// heading does not turn it (no cone).
  void _updateLocationVisuals() {
    final target = _currentLatLng;
    var bucket = _pinBucket;
    if (_pins[bucket] == null) bucket = 0;
    final icon = _pins[bucket];
    if (!mounted || target == null || icon == null) return;
    _paintedPinBucket = bucket;
    _locationCtl.paintUserPuck(
      target: target,
      icon: icon,
      heading: 0,
      anchor: MoveraRiderPuckMarker.anchorFor(bucket.toDouble()),
      haloIcon: _halo,
    );
  }

  void _handleMapCameraMove(CameraPosition camera) {
    _lastMapZoom = camera.zoom;
    _lastMapTarget = camera.target;
    _locationCtl.noteCameraMove(bearing: camera.bearing, tilt: camera.tilt);
    if (_paintedPinBucket != null && _paintedPinBucket != _pinBucket) {
      _updateLocationVisuals();
    }
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
    if (!mounted) return;
    // rider-47: the glide may have been cut short by a finger on the map,
    // or refused because the rider holds it. Hide the button only when the
    // camera is where a recentre puts it; else the rider has no way back.
    final user = _currentLatLng;
    final target = _locationCtl.lastMapTarget;
    final offRider =
        user != null &&
        AppScope.instance.camera.showRecenter(
          zoom: _locationCtl.lastMapZoom,
          metersFromUser: AppScope.instance.location.distanceBetween(
            target.latitude,
            target.longitude,
            user.latitude,
            user.longitude,
          ),
        );
    setState(() => _showRecenterButton = offRider);
  }

  /// A fresh fix closer than this to the known position does not steer a
  /// running recenter.
  static const double _recenterRefineMeters = 15;

  /// The rider's active promotion, shown as a ticket on top of the sheet.
  /// It is applied only while the sheet rests low, so a promotion arriving
  /// mid-gesture never changes the snaps under the rider's finger.
  RiderPromotion? _promotion;
  Timer? _settleTimer;

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
    // Owner round 1: resting, not passing. A sheet that left its last stop
    // (a drag, a fling) has no settled snap; it gets the promotion when it
    // settles low again (_trackSettledSnap). Before the very first seat the
    // sheet rests at its initial low offset.
    final restingLow =
        offset != null &&
        (previousLow != null
            ? offset <= previousLow + 1.5
            : !_hadFirstSeat && (offset - _sheetMinPixels).abs() <= 1.5);
    final wasLow =
        !_destinationSheetOpen &&
        restingLow &&
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
      if (settled == null) return;
      _trackSettledSnap(settled);
      _syncWebOverlay(settled);
    });

    final expanded = offset > _sheetMidPixels + ResSize.h * 8;
    if (expanded != _destinationSheetOpen) {
      setState(() => _destinationSheetOpen = expanded);
    }
  }

  /// What [setWebOverlayOpen] was last told; null after the map was parked.
  bool? _webOverlayCovering;

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
  Future<void> _openSchedule() async {
    // rider-u124: switched off in this build: say so before the rider
    // picks a destination, a date, a category and a pickup for nothing.
    if (!AppScope.instance.bookLaterAvailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.resErrUnavailable)));
      return;
    }
    await _runRouteFlow(
      () =>
          _showRouteAddressPicker(initialField: 'destination', scheduled: true),
    );
  }

  void _openPayment() => _openTab(HomeTabs.payment);

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

  /// The layout the map was sized for, see [_stableMapHeight].
  Size? _mapLayout;

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final mapHeight = _stableMapHeight(MediaQuery.of(context).size);
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
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: mapHeight,
                        // Owner round 3: the map rises a little (a third of
                        // the way) as the sheet goes up, like the other ride
                        // apps, so the rider's spot stays above the sheet.
                        child: AnimatedBuilder(
                          animation: _homeSheetController,
                          builder: (context, map) => Transform.translate(
                            offset: Offset(0, -_mapLift(mapHeight)),
                            child: map,
                          ),
                          child: RepaintBoundary(
                            child: HomeMapLayer(
                              key: const ValueKey('home-map-layer'),
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
                                  if (!_hasFix) _quickCameraAt = target;
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
                      HomeLocationNotice(
                        location: _locationCtl,
                        bottom: _sheetMinPixels,
                        onRetry: _detectCurrentAddress,
                        onPrecise: _turnOnPreciseLocation,
                      ),
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
                      // Owner round 1: one gap between every section of
                      // the expanded sheet (HomeSheetLayout).
                      Widget premiumSavedPlacesContent(double reveal) => Column(
                        children: [
                          SizedBox(height: HomeSheetLayout.sectionGap),
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
                          // v0.10.0: the admin's rider banners (Content).
                          ContentBanners(controller: AppScope.instance.content),
                          AdvanceBookingCard(onOpenSchedule: _openSchedule),
                          SizedBox(height: HomeSheetLayout.sectionGap),
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
}
