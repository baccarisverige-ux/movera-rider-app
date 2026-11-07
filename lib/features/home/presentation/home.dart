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
part 'home_location_detect.dart';
part 'home_map_controls.dart';
part 'home_route_flow.dart';
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

  /// RIDE-10: the next booking starts from the rider's current location,
  /// not from the last flow's pickup street.
  int _pickupLabelGeneration = 0;
  LatLng? _pickupLabelAt;

  /// N7: when the pickup label was last asked of the geocoder, so an unnamed
  /// pickup is retried on the live fixes no more than every few seconds.
  DateTime? _pickupLabelAskedAt;

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
