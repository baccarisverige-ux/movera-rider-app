import 'dart:async';
import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_point.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/bearing.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/utils/stale_guard.dart';
import 'package:movera_rider/features/pickup/application/pickup_address.dart'
    show isDroppedPinLabel, locationOffPickupLabel, pickupLocationFallbackLabel;
import 'package:movera_rider/core/location/location_access_issue.dart';
import 'package:movera_rider/shared/services/device_heading.dart'
    as heading_service;

export 'package:movera_rider/features/pickup/application/pickup_address.dart'
    show locationOffPickupLabel;

/// U7: Home used to re-rasterise the puck (toImage, PNG encode, new
/// BitmapDescriptor) on every heading sample and pulse tick. Headings are
/// snapped to [stepDegrees] buckets and each rotated bitmap is built once per
/// (pulse state, bucket) and reused.
class RotatedPuckCache {
  RotatedPuckCache({this.stepDegrees = 5});

  final int stepDegrees;
  final Map<(bool, int), BitmapDescriptor> _icons = {};

  int get bucketCount => (360 / stepDegrees).ceil();

  /// The bucket [heading] falls into (nearest step, wrapping at 360°).
  int bucketFor(double heading) {
    if (!heading.isFinite) return 0;
    final normalised = heading % 360;
    return (normalised / stepDegrees).round() % bucketCount;
  }

  /// The heading the bitmap for [bucket] is drawn at.
  double headingFor(int bucket) => (bucket * stepDegrees).toDouble();

  BitmapDescriptor? lookup({required bool expanded, required int bucket}) =>
      _icons[(expanded, bucket)];

  void store({
    required bool expanded,
    required int bucket,
    required BitmapDescriptor icon,
  }) {
    _icons[(expanded, bucket)] = icon;
  }

  int get length => _icons.length;

  /// Drops every bitmap, e.g. when the source puck images are rebuilt.
  void clear() => _icons.clear();
}

/// Whether [label] is a placeholder rather than a real address, so it must
/// not be forward-geocoded or saved.
bool isPlaceholderPickupLabel(String? label) {
  final clean = label?.trim().toLowerCase() ?? '';
  return clean.isEmpty ||
      clean == 'current location' ||
      clean == locationOffPickupLabel.toLowerCase();
}

/// The result of a Home geocode. A stale call (a newer one superseded it)
/// is not "not found": its flow should stop quietly, without an error.
sealed class GeocodeOutcome<T> {
  const GeocodeOutcome();

  T? get valueOrNull => switch (this) {
    GeocodeFound<T>(:final value) => value,
    _ => null,
  };
}

final class GeocodeFound<T> extends GeocodeOutcome<T> {
  const GeocodeFound(this.value);
  final T value;
}

final class GeocodeNotFound<T> extends GeocodeOutcome<T> {
  const GeocodeNotFound();
}

final class GeocodeStale<T> extends GeocodeOutcome<T> {
  const GeocodeStale();
}

/// The lookup itself failed (offline, a timeout, a server error), as
/// opposed to finding nothing (rider-45).
final class GeocodeFailed<T> extends GeocodeOutcome<T> {
  const GeocodeFailed();
}

/// Whether [text] is a raw "lat, lng" coordinate string (D-004).
bool isRawCoordinateLabel(String? text) => RegExp(
  r'^\s*-?\d{1,3}(\.\d+)?\s*,\s*-?\d{1,3}(\.\d+)?\s*$',
).hasMatch(text ?? '');

/// Owner round 1: the location question comes before the push primer.
/// Signing in [expect]s Home's first location request; the primer waits
/// for [answered]. A request that is never answered keeps the primer away
/// for the session. With nothing expected, [answered] resolves at once.
abstract final class LocationPromptGate {
  static Completer<void>? _pending;

  /// A location request is about to be made (Home opens after sign-in).
  static void expect() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) return;
    _pending = Completer<void>();
  }

  /// The location request was answered, or needed no prompt.
  static void markAnswered() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Completes once the expected location request has been answered.
  static Future<void> answered() => _pending?.future ?? Future<void>.value();

  @visibleForTesting
  static void reset() => _pending = null;
}

enum HomeLocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

enum HomeLocationState {
  initializing,
  permissionRequired,
  servicesDisabled,
  acquiringFix,
  live,
  temporarilyUnavailable,
  recovering,
}

class DetectedLocation {
  const DetectedLocation({
    required this.target,
    required this.address,
    required this.heading,
    this.failure,
    this.approximate = false,
  });

  /// rider-u114: [target] is an approximate-only fix: map and puck only,
  /// never the pickup.
  final bool approximate;

  final LatLng? target;
  final String address;
  final double heading;
  final HomeLocationFailure? failure;

  bool get denied =>
      failure == HomeLocationFailure.permissionDenied ||
      failure == HomeLocationFailure.permissionDeniedForever;
  bool get unavailable => failure != null;
}

/// Owns GPS, motion, heading blend, reverse geocode, and map overlay sets.
/// Home only paints. Overlay changes notify so the map layer can rebuild
/// without the rest of the Home tree.
class HomeLocationController extends ChangeNotifier {
  HomeLocationController({
    required this.location,
    required this.geocoding,
    required this.motion,
    Future<bool> Function()? startCompass,
    double? Function()? readCompass,
    void Function()? stopCompass,
    bool? compassSupported,
    DateTime Function()? clock,
    bool? pulseAnimates,
  }) : _now = clock ?? DateTime.now,
       _pulseAnimates = pulseAnimates ?? !kIsWeb,
       _startCompass = startCompass ?? heading_service.startHeadingTracking,
       _readCompass = readCompass ?? heading_service.currentHeading,
       _stopCompass = stopCompass ?? heading_service.stopHeadingTracking,
       _compassSupported =
           compassSupported ??
           (startCompass != null || heading_service.headingTrackingSupported);

  final LocationRepository location;
  final GeocodingRepository geocoding;
  final MotionEngine motion;
  final Future<bool> Function() _startCompass;
  final double? Function() _readCompass;
  final void Function() _stopCompass;
  final DateTime Function() _now;

  /// rider-u116: false on the web. Each pulse swaps the puck between two
  /// bitmaps, and the web map plugin turns every swapped bitmap into a new
  /// blob URL it never revokes (one every 850 ms while Home is open). The
  /// web puck therefore stays in its compact state instead of pulsing.
  final bool _pulseAnimates;

  /// UI-12: a compass sample repaints the puck only when it turned at least
  /// this far since the last repaint, or [headingRepaintInterval] has passed.
  static const double headingRepaintDegrees = 2;
  static const Duration headingRepaintInterval = Duration(milliseconds: 250);
  double? _deliveredHeading;
  DateTime? _deliveredAt;

  /// The puck stays as it is while the map camera moves (a pinch, a pan, a
  /// recenter glide) and for this long after its last move. Each repaint
  /// rebuilds the map widget, swaps the marker bitmap (a new blob URL and
  /// image decode on the web) and makes a vector map redraw: done every
  /// pulse and heading sample, that stuttered every gesture. The pulse and
  /// the compass pick up again as soon as the camera rests.
  static const Duration cameraQuietPeriod = Duration(milliseconds: 300);
  DateTime? _cameraMovedAt;

  /// Bearing of the map camera (degrees) as last reported.
  double lastMapBearing = 0;

  /// The map camera moved (an onCameraMove report).
  void noteCameraMove({double bearing = 0}) {
    _cameraMovedAt = _now();
    lastMapBearing = bearing.isFinite ? bearing : 0;
  }

  /// Whether a finger holds the map or an app glide is running (set by
  /// Home from the live map's view).
  bool Function()? mapBusy;

  /// Whether the camera moved within [cameraQuietPeriod], or the map is
  /// held or gliding ([mapBusy]).
  bool get cameraMoving {
    if (mapBusy?.call() ?? false) return true;
    final at = _cameraMovedAt;
    return at != null && _now().difference(at) < cameraQuietPeriod;
  }

  /// False on Android/iOS, which have no compass source (CODE-19): the puck
  /// then turns only with the GPS course and no heading poller runs.
  final bool _compassSupported;

  final StaleGuard _normaliseGuard = StaleGuard();
  final StaleGuard _pointGuard = StaleGuard();
  final StaleGuard _placeGuard = StaleGuard();
  final StaleGuard _detectGuard = StaleGuard();
  StreamSubscription<Position>? _positionSub;
  Timer? _resubscribeTimer;

  /// rider-20: the scheduled frame of the running puck glide.
  int? _glideFrameId;

  /// rider-u120: after [dispose], nothing starts GPS, compass or pulse.
  bool _disposed = false;
  int _resubscribeAttempts = 0;
  bool Function()? _trackingMounted;
  void Function(LatLng latLng, double heading)? _trackingOnFix;
  bool _resumeRefreshInFlight = false;

  /// Accuracy (metres) of the last fix the puck was painted from, so a
  /// low-accuracy fix is shown with its uncertainty circle (U2).
  double? lastFixAccuracyMeters;

  static const detectFixTimeout = Duration(seconds: 16);
  static const latestFixTimeout = Duration(seconds: 9);

  /// Owner round 1: how long [detectCurrent] waits for a quick coarse fix
  /// (when the OS has no cached one) before it leaves the first position to
  /// the accurate fix alone.
  static const quickFixTimeout = Duration(seconds: 3);

  /// Owner round 1: an accurate fix this close to where the quick fix put
  /// the camera does not move the camera again.
  static const quickFixRefineMeters = 30.0;

  /// Owner, live test 2026-10-26: a quick fix less sure than this (metres)
  /// is not shown. In Safari on iPhone the quick low-accuracy answer can be
  /// a Wi-Fi or network estimate kilometres off (the puck landed in the sea
  /// south of Södertälje and the map centred there); the accurate fix comes
  /// a moment later and is the first position shown instead.
  static const quickFixMaxMeters = 1000.0;

  /// Owner, live test 2026-10-26 (N7): a first fix this uncertain (metres)
  /// is not named. Right after sign-in the phone's first "accurate" fix is
  /// often a cached or network one hundreds of metres off; its reverse
  /// geocode showed a wrong street for a second until the live stream's
  /// first good fix moved the label. Puck and camera still use the fix; the
  /// pickup stays "Current location" until a fix within this lands.
  static const nameableFixMeters = 150.0;

  /// Whether a fix of [accuracyMeters] may be named with a street.
  static bool nameable(double? accuracyMeters) =>
      accuracyMeters == null ||
      !accuracyMeters.isFinite ||
      accuracyMeters <= nameableFixMeters;

  /// Backoff before re-subscribing after a transient stream failure.
  @visibleForTesting
  static Duration resubscribeDelay(int attempt) {
    final seconds = 2 << attempt.clamp(0, 4); // 2, 4, 8, 16, 32
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }

  Timer? _headingTimer;
  Timer? _pulseTimer;
  bool Function()? _headingMounted;
  void Function(double heading)? _onHeading;
  Future<bool>? _headingStartInFlight;
  bool _compassStarted = false;
  bool hasCompassHeading = false;
  double heading = 0;
  double lastMapZoom = 13.0;
  LatLng lastMapTarget = const LatLng(59.3293, 18.0686);
  bool pulseExpanded = false;
  bool _livePaused = false;
  HomeLocationState state = HomeLocationState.initializing;
  Set<Marker> markers = {};
  Set<Circle> locationCircles = {};
  Set<Polygon> locationDirection = {};

  /// Opens one staleness scope for every address normalisation belonging to a
  /// single user action. Concurrent calls share one generation so siblings do
  /// not invalidate each other, while a newer route confirmation invalidates
  /// the whole older batch.
  int beginNormalisationBatch() => _normaliseGuard.next();

  Future<String> normaliseAddress(String input, {int? generation}) async {
    final clean = input.trim();
    // rider-39: a placeholder or dropped-pin label names no place; a fuzzy
    // geocoder would swap it for some other place's name.
    if (isPlaceholderPickupLabel(clean) ||
        clean == pickupLocationFallbackLabel ||
        isDroppedPinLabel(clean)) {
      return clean;
    }
    final scope = generation ?? _normaliseGuard.next();
    PlaceResult? result;
    try {
      result = await geocoding.forward(clean);
    } catch (_) {
      // rider-45: normalising only tidies the text; a failed lookup keeps
      // what the rider chose instead of aborting the flow.
      return clean;
    }
    if (!_normaliseGuard.isCurrent(scope)) return clean;
    return result?.address.trim().isNotEmpty == true
        ? result!.address.trim()
        : clean;
  }

  Future<LatLng?> geocodeLatLng(String address) async =>
      (await resolveLatLng(address)).valueOrNull;

  Future<({LatLng point, String address})?> geocodePlace(
    String address,
  ) async => (await resolvePlace(address)).valueOrNull;

  /// [geocodeLatLng], but says whether a null meant "not found" or "a newer
  /// call superseded this one" (RIDE-18).
  Future<GeocodeOutcome<LatLng>> resolveLatLng(String address) async {
    final generation = _pointGuard.next();
    final PlaceResult? result;
    try {
      result = await geocoding.forward(address);
    } catch (_) {
      if (!_pointGuard.isCurrent(generation)) return const GeocodeStale();
      return const GeocodeFailed();
    }
    if (!_pointGuard.isCurrent(generation)) return const GeocodeStale();
    if (result == null) return const GeocodeNotFound();
    return GeocodeFound(LatLng(result.point.latitude, result.point.longitude));
  }

  /// [geocodePlace], but says whether a null meant "not found" or "a newer
  /// call superseded this one" (RIDE-18).
  Future<GeocodeOutcome<({LatLng point, String address})>> resolvePlace(
    String address,
  ) async {
    final generation = _placeGuard.next();
    final PlaceResult? result;
    try {
      result = await geocoding.forward(address);
    } catch (_) {
      if (!_placeGuard.isCurrent(generation)) return const GeocodeStale();
      return const GeocodeFailed();
    }
    if (!_placeGuard.isCurrent(generation)) return const GeocodeStale();
    if (result == null) return const GeocodeNotFound();
    return GeocodeFound((
      point: LatLng(result.point.latitude, result.point.longitude),
      address: result.address.trim().isNotEmpty
          ? result.address.trim()
          : address,
    ));
  }

  bool _permissionBlocked = false;

  /// What the location notice on Home should explain, or null while location
  /// works (UI-16). Derived from [state] so it clears on the next good fix.
  LocationAccessIssue? get accessIssue => switch (state) {
    HomeLocationState.servicesDisabled => LocationAccessIssue.servicesOff,
    HomeLocationState.permissionRequired =>
      _permissionBlocked
          ? LocationAccessIssue.deniedForever
          : LocationAccessIssue.denied,
    _ => _preciseOff ? LocationAccessIssue.approximate : null,
  };

  bool _preciseOff = false;

  /// rider-u114: the rider allowed only approximate location. The fix still
  /// centres the map and draws the puck, but it is never the pickup: Home
  /// shows the 'set pickup' state until precise location is on.
  bool get preciseLocationOff => _preciseOff;

  void _setPreciseOff(bool off) {
    if (_preciseOff == off) return;
    _preciseOff = off;
    notifyListeners();
  }

  /// rider-u114: reads the accuracy grant again (an app resume, after the
  /// "Turn on" button). Resolves with whether it changed.
  Future<bool> recheckPrecision() async {
    final off = await location.isApproximateOnly();
    if (_disposed || off == _preciseOff) return false;
    _setPreciseOff(off);
    return true;
  }

  /// rider-u114: the notice's "Turn on" button.
  Future<void> requestPreciseLocation() async {
    await location.requestPreciseLocation();
    if (_disposed) return;
    await recheckPrecision();
  }

  void _setState(HomeLocationState next) {
    if (state == next) return;
    state = next;
    notifyListeners();
  }

  bool _accurateFixSeen = false;

  /// Batch 10 Phase 110: a fast, coarse position for Home's map **camera
  /// only**, while [detectCurrent] fetches the accurate fix.
  ///
  /// Layered: the OS's last known position (Android/iOS), else the app's own
  /// last good fix (all platforms, incl. web). Returns null — so Home keeps
  /// today's default view — when services are off, permission is not already
  /// granted, nothing is cached, or the accurate fix has already landed.
  /// Never requests permission, never changes [state], the puck or pickup.
  Future<LatLng?> quickCameraFix() async {
    try {
      if (!await location.isLocationServiceEnabled()) return null;
      // Read-only: the permission prompt stays owned by detectCurrent().
      final permission = await location.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final hint =
          await location.lastKnownFix() ?? await location.readLastGoodFix();
      if (hint == null || _accurateFixSeen) return null;
      return LatLng(hint.latitude, hint.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Told about every good fix (the app language follows the pickup
  /// zone's default, Q48). Set once at start-up.
  static void Function(GeoPoint point)? onGoodFix;

  void _rememberGoodFix(Position position) {
    final point = GeoPoint(position.latitude, position.longitude);
    unawaited(location.saveLastGoodFix(point));
    onGoodFix?.call(point);
  }

  /// Owner round 1: the first position Home can show at once, while the
  /// accurate fix is still coming. The OS's cached last position, else a
  /// quick low-accuracy fix within [quickFixTimeout]. Null when neither
  /// answers in time. Puck and camera only, never a pickup.
  Future<LatLng?> _quickPosition() async {
    try {
      final cached = await location.lastKnownFix();
      if (cached != null && cached.isValid) {
        return LatLng(cached.latitude, cached.longitude);
      }
    } catch (_) {
      // No cached fix: ask for a quick one below.
    }
    try {
      // D-003: the Dart-side timeout bounds the web plugin as well.
      final position = await location
          .getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: quickFixTimeout,
            ),
          )
          .timeout(quickFixTimeout);
      if (position.accuracy.isFinite && position.accuracy > quickFixMaxMeters) {
        return null;
      }
      final point = GeoPoint(position.latitude, position.longitude);
      return point.isValid ? LatLng(point.latitude, point.longitude) : null;
    } catch (_) {
      return null;
    }
  }

  /// rider-43: [askPermission] false never shows the system prompt (an app
  /// resume, a second try right after the rider answered it); a denied
  /// permission then reads as denied.
  ///
  /// Owner round 1: [onQuickFix] gets a fast first position (see
  /// [_quickPosition]) while the accurate fix is fetched; it is not called
  /// once the accurate fix has landed or failed. [onLocated] gets a precise
  /// accurate fix as soon as it lands, before the reverse geocode, so the
  /// puck and the pickup point never wait for the address; the returned
  /// location then carries the address too.
  Future<DetectedLocation> detectCurrent({
    bool askPermission = true,
    void Function(LatLng point)? onQuickFix,
    void Function(DetectedLocation located)? onLocated,
  }) async {
    _setState(HomeLocationState.initializing);
    try {
      if (!await location.isLocationServiceEnabled()) {
        LocationPromptGate.markAnswered();
        _setState(HomeLocationState.servicesDisabled);
        return const DetectedLocation(
          target: null,
          address: locationOffPickupLabel,
          heading: 0,
          failure: HomeLocationFailure.servicesDisabled,
        );
      }
      var permission = await location.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
        permission = await location.requestPermission();
      }
      // Owner round 1: the location question is answered (or needed no
      // prompt); the push primer may follow now.
      LocationPromptGate.markAnswered();
      if (permission == LocationPermission.deniedForever) {
        _permissionBlocked = true;
        _setState(HomeLocationState.permissionRequired);
        return const DetectedLocation(
          target: null,
          address: locationOffPickupLabel,
          heading: 0,
          failure: HomeLocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        _permissionBlocked = false;
        _setState(HomeLocationState.permissionRequired);
        return const DetectedLocation(
          target: null,
          address: locationOffPickupLabel,
          heading: 0,
          failure: HomeLocationFailure.permissionDenied,
        );
      }
      _setState(HomeLocationState.acquiringFix);
      // D-003: geolocator_web passes timeLimit in microseconds to a JS API
      // that expects milliseconds (15 s becomes ~4 h). The Dart-side
      // timeout guarantees the fallback path still runs.
      final accurate = location
          .getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          )
          .timeout(detectFixTimeout);
      var accurateSettled = false;
      if (onQuickFix != null) {
        unawaited(
          _quickPosition().then((point) {
            if (point == null || accurateSettled || _disposed) return;
            onQuickFix(point);
          }),
        );
      }
      final Position position;
      try {
        position = await accurate;
      } finally {
        accurateSettled = true;
      }
      _accurateFixSeen = true;
      final generation = _detectGuard.next();
      // rider-u114: read after the fix, so the fix's own timeout still
      // bounds the whole detection.
      final approximate = await location.isApproximateOnly();
      if (approximate) {
        // rider-u114: a fix that may be hundreds of metres off names no
        // pickup and is not kept as a good fix; it still centres the map.
        onGoodFix?.call(GeoPoint(position.latitude, position.longitude));
        heading = position.heading.isFinite && position.heading >= 0
            ? position.heading
            : 0;
        _setPreciseOff(true);
        _setState(HomeLocationState.live);
        return DetectedLocation(
          target: LatLng(position.latitude, position.longitude),
          address: locationOffPickupLabel,
          heading: heading,
          approximate: true,
        );
      }
      _setPreciseOff(false);
      _rememberGoodFix(position);
      lastFixAccuracyMeters = position.accuracy;
      // Owner round 1: the point first, the address when it comes.
      onLocated?.call(
        DetectedLocation(
          target: LatLng(position.latitude, position.longitude),
          address: 'Current location',
          heading: position.heading.isFinite && position.heading >= 0
              ? position.heading
              : 0,
        ),
      );
      if (!nameable(position.accuracy)) {
        // N7: a coarse first fix is not named; the live stream's first
        // good fix names the pickup (Home relabels on it).
        _setState(HomeLocationState.live);
        return DetectedLocation(
          target: LatLng(position.latitude, position.longitude),
          address: 'Current location',
          heading: position.heading.isFinite && position.heading >= 0
              ? position.heading
              : 0,
        );
      }
      String? detected;
      try {
        detected = await geocoding.reverse(
          GeoPoint(position.latitude, position.longitude),
        );
      } catch (_) {
        // Address enrichment must never invalidate an already acquired GPS fix.
        // The rider puck and live stream are coordinate-driven, not geocoder-driven.
        detected = null;
      }
      if (!_detectGuard.isCurrent(generation)) {
        return DetectedLocation(
          target: LatLng(position.latitude, position.longitude),
          address: 'Current location',
          heading: position.heading.isFinite && position.heading >= 0
              ? position.heading
              : 0,
        );
      }
      final address = detected?.trim().isNotEmpty == true
          ? detected!.trim()
          : 'Current location';
      heading = position.heading.isFinite && position.heading >= 0
          ? position.heading
          : 0;
      _setState(HomeLocationState.live);
      return DetectedLocation(
        target: LatLng(position.latitude, position.longitude),
        address: address,
        heading: heading,
      );
    } catch (_) {
      LocationPromptGate.markAnswered();
      _setState(HomeLocationState.temporarilyUnavailable);
      return const DetectedLocation(
        target: null,
        address: locationOffPickupLabel,
        heading: 0,
        failure: HomeLocationFailure.unavailable,
      );
    }
  }

  void startTracking({
    required bool Function() isMounted,
    required void Function(LatLng latLng, double heading) onFix,
  }) {
    if (_disposed) return;
    _positionSub?.cancel();
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _trackingMounted = isMounted;
    _trackingOnFix = onFix;
    final settings = LocationSettings(
      accuracy: kIsWeb
          ? LocationAccuracy.high
          : LocationAccuracy.bestForNavigation,
      distanceFilter: kIsWeb ? 20 : 8,
    );
    _positionSub = location
        .getPositionStream(locationSettings: settings)
        .listen(
          (position) {
            if (!isMounted() || _livePaused) return;
            _resubscribeAttempts = 0;
            _deliverFix(position, onFix);
          },
          onError: (Object error) {
            _positionSub?.cancel();
            _positionSub = null;
            // U2: only a permission or services problem stops tracking; any
            // other failure re-subscribes with backoff instead of freezing
            // the puck until the app is backgrounded.
            if (error is PermissionDeniedException) {
              _setState(HomeLocationState.permissionRequired);
              return;
            }
            if (error is LocationServiceDisabledException) {
              _setState(HomeLocationState.servicesDisabled);
              return;
            }
            _setState(HomeLocationState.temporarilyUnavailable);
            _scheduleResubscribe();
          },
          onDone: () {
            if (_positionSub == null) return;
            _positionSub = null;
            _setState(HomeLocationState.temporarilyUnavailable);
            _scheduleResubscribe();
          },
        );
  }

  void _scheduleResubscribe() {
    final isMounted = _trackingMounted;
    final onFix = _trackingOnFix;
    if (isMounted == null || onFix == null || !isMounted()) return;
    _resubscribeTimer?.cancel();
    final delay = resubscribeDelay(_resubscribeAttempts);
    _resubscribeAttempts += 1;
    _resubscribeTimer = Timer(delay, () {
      _resubscribeTimer = null;
      if (!isMounted()) return;
      _setState(HomeLocationState.recovering);
      startTracking(isMounted: isMounted, onFix: onFix);
    });
  }

  /// rider-20: steps the puck along [MotionEngine]'s glide to the latest
  /// fix on painted frames (no timer), so it moves instead of jumping.
  void _glideTo(
    DateTime glideStart,
    void Function(LatLng latLng, double heading) onFix,
  ) {
    _cancelGlide();
    Duration? first;
    void step(Duration frame) {
      _glideFrameId = null;
      final isMounted = _trackingMounted;
      if (isMounted == null || !isMounted() || _livePaused) return;
      first ??= frame;
      final next = motion.poseAt(glideStart.add(frame - first!));
      if (next == null) return;
      onFix(LatLng(next.position.latitude, next.position.longitude), heading);
      if (next.progress < 1) {
        _glideFrameId = SchedulerBinding.instance.scheduleFrameCallback(step);
      }
    }

    _glideFrameId = SchedulerBinding.instance.scheduleFrameCallback(step);
  }

  void _cancelGlide() {
    final id = _glideFrameId;
    _glideFrameId = null;
    if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
  }

  void _deliverFix(
    Position position,
    void Function(LatLng latLng, double heading) onFix,
  ) {
    _setState(HomeLocationState.live);
    final glideStart = DateTime.now();
    final pose = motion.ingest(
      LocationPoint(
        point: GeoPoint(position.latitude, position.longitude),
        timestamp: position.timestamp,
        accuracyMeters: position.accuracy,
        speedMps: position.speed,
        heading: position.heading,
      ),
      now: glideStart,
    );
    if (pose != null && pose.progress < 1) _glideTo(glideStart, onFix);
    final latLng = pose == null
        ? LatLng(position.latitude, position.longitude)
        : LatLng(pose.position.latitude, pose.position.longitude);
    lastFixAccuracyMeters = pose?.cone.accuracy ?? position.accuracy;
    if (!hasCompassHeading &&
        position.heading.isFinite &&
        position.heading >= 0) {
      heading = position.heading;
      reportPuckHeading(heading, compass: false);
    }
    onFix(latLng, heading);
  }

  /// Requests compass permission, then polls heading. Returns whether the
  /// compass actually started. GPS course remains the fallback if this fails.
  Future<bool> startHeading({
    required bool Function() isMounted,
    required void Function(double heading) onHeading,
  }) async {
    if (_disposed) return false;
    _headingMounted = isMounted;
    _onHeading = onHeading;
    final granted = await _ensureCompassStarted();
    // Web keeps polling after a refusal: a later tap can still grant motion.
    if (granted || _compassSupported) _ensureHeadingPoller();
    return granted;
  }

  Future<bool> _ensureCompassStarted() {
    if (_compassStarted) return Future.value(true);
    return _headingStartInFlight ??= _openCompass();
  }

  Future<bool> _openCompass() async {
    try {
      final granted = await _startCompass();
      _compassStarted = granted;
      if (!granted) _headingStartInFlight = null;
      return granted;
    } catch (_) {
      _compassStarted = false;
      _headingStartInFlight = null;
      return false;
    }
  }

  void _ensureHeadingPoller() {
    if (_headingTimer != null) return;
    _headingTimer = Timer.periodic(Duration(milliseconds: kIsWeb ? 250 : 100), (
      _,
    ) {
      if (_livePaused) return;
      pollHeading();
    });
  }

  /// Applies one compass sample. Public for tests so heading can be verified
  /// without waiting on a real timer.
  @visibleForTesting
  void pollHeading() {
    final mounted = _headingMounted;
    if (mounted != null && !mounted()) return;
    final next = _readCompass();
    if (next == null || !next.isFinite) return;
    final blended = blendHeading(heading, next);
    if ((blended - heading).abs() < 0.01 && hasCompassHeading) return;
    hasCompassHeading = true;
    heading = blended;
    reportPuckHeading(heading, compass: true);
    // UI-12: each delivery builds a new marker set and an update over the
    // platform channel, so small turns are batched.
    // Not under a moving camera: the next sample after it rests repaints.
    if (cameraMoving) return;
    final now = _now();
    final last = _deliveredHeading;
    final lastAt = _deliveredAt;
    if (last != null &&
        lastAt != null &&
        shortestTurn(last, heading).abs() < headingRepaintDegrees &&
        now.difference(lastAt) < headingRepaintInterval) {
      return;
    }
    _deliveredHeading = heading;
    _deliveredAt = now;
    _onHeading?.call(heading);
  }

  Future<LatLng?> latestFix() async {
    // D-003: explicit Dart-side timeout (see detectFixTimeout).
    final position = await location
        .getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 8),
          ),
        )
        .timeout(latestFixTimeout);
    _accurateFixSeen = true;
    // rider-u114: an approximate-only fix is not kept as a good fix.
    if (!_preciseOff) _rememberGoodFix(position);
    final target = LatLng(position.latitude, position.longitude);
    if (!hasCompassHeading &&
        position.heading.isFinite &&
        position.heading >= 0) {
      heading = position.heading;
      reportPuckHeading(heading, compass: false);
    }
    return target;
  }

  void startPulse({
    required bool Function() isMounted,
    required void Function() onTick,
  }) {
    if (_disposed) return;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    pulseExpanded = false;
    onTick();
    if (!_pulseAnimates) return;
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!isMounted() || _livePaused || cameraMoving) return;
      pulseExpanded = !pulseExpanded;
      onTick();
    });
  }

  Future<void> bindLiveLocation({
    required bool Function() isMounted,
    required void Function(LatLng latLng, double heading) onFix,
    required void Function(double heading) onHeading,
    required void Function() onPulse,
  }) async {
    if (_disposed) return;
    startTracking(isMounted: isMounted, onFix: onFix);
    startPulse(isMounted: isMounted, onTick: onPulse);
    await startHeading(isMounted: isMounted, onHeading: onHeading);
  }

  void clearOverlays() {
    markers = {};
    locationCircles = {};
    locationDirection = {};
    notifyListeners();
  }

  double? _paintedAccuracy;

  void paintUserPuck({
    required LatLng target,
    required BitmapDescriptor icon,
    required double heading,
  }) {
    if (_livePaused) return;
    final accuracy = lastFixAccuracyMeters;
    // UI-12: the same puck again changes nothing, so it does not notify (a
    // new set identity rebuilds the map widget).
    final painted = markers.length == 1 ? markers.first : null;
    if (painted != null &&
        painted.markerId == const MarkerId('live_user_location') &&
        painted.position == target &&
        identical(painted.icon, icon) &&
        painted.rotation == heading &&
        _paintedAccuracy == accuracy) {
      return;
    }
    _paintedAccuracy = accuracy;
    // U2: a low-accuracy fix is shown with its uncertainty, not hidden.
    locationCircles = accuracy != null && accuracy.isFinite && accuracy > 30
        ? {
            Circle(
              circleId: const CircleId('live_user_accuracy'),
              center: target,
              radius: accuracy.clamp(30, 2000).toDouble(),
              fillColor: const Color(0x1F2D5878),
              strokeColor: const Color(0x592D5878),
              strokeWidth: 1,
            ),
          }
        : {};
    locationDirection = {};
    markers = {
      Marker(
        markerId: const MarkerId('live_user_location'),
        position: target,
        icon: icon,
        anchor: const Offset(0.5, 0.66),
        rotation: heading,
        flat: true,
        zIndexInt: 20,
      ),
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _cancelGlide();
    _resubscribeTimer?.cancel();
    _resubscribeTimer = null;
    _trackingMounted = null;
    _trackingOnFix = null;
    _headingTimer?.cancel();
    _headingTimer = null;
    _pulseTimer?.cancel();
    _normaliseGuard.dispose();
    _pointGuard.dispose();
    _placeGuard.dispose();
    _detectGuard.dispose();
    _stopCompass();
    _compassStarted = false;
    _headingStartInFlight = null;
    hasCompassHeading = false;
    super.dispose();
  }

  void pauseLiveUpdates() {
    _livePaused = true;
  }

  void resumeLiveUpdates() {
    final wasPaused = _livePaused;
    _livePaused = false;
    // U2: fixes were dropped while paused, and a stationary rider may not
    // produce a new stream event for a long time. Ask for one fresh fix.
    if (wasPaused) unawaited(_refreshAfterResume());
  }

  Future<void> _refreshAfterResume() async {
    final isMounted = _trackingMounted;
    final onFix = _trackingOnFix;
    if (isMounted == null || onFix == null || _resumeRefreshInFlight) return;
    _resumeRefreshInFlight = true;
    try {
      final target = await latestFix();
      if (target == null || !isMounted() || _livePaused) return;
      _setState(HomeLocationState.live);
      onFix(target, heading);
      // rider-u115: a revoke or services-off error ended the stream without
      // a resubscribe. A fresh fix means location works again, so follow
      // the rider again instead of freezing the puck on this one fix.
      if (_positionSub == null && _resubscribeTimer == null) {
        startTracking(isMounted: isMounted, onFix: onFix);
      }
    } catch (_) {
      // No fresh fix: keep the last one; the stream will deliver the next.
    } finally {
      _resumeRefreshInFlight = false;
    }
  }

  void recoverLiveLocation({
    required bool Function() isMounted,
    required void Function(LatLng latLng, double heading) onFix,
  }) {
    if (_livePaused) return;
    _setState(HomeLocationState.recovering);
    startTracking(isMounted: isMounted, onFix: onFix);
  }
}
