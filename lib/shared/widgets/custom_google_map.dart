import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/web/map_touch.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/core/web/web_gpu.dart';
import 'package:movera_rider/core/web/web_maps_available.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../styles/reference_map_style.dart';

export '../styles/reference_map_style.dart' show moveraReferenceMapStyle;

/// Google Cloud Map ID (cloud-based styling) baked in at build time with
/// `--dart-define=MOVERA_GOOGLE_MAP_ID=...`. Empty means no Map ID: the map
/// keeps the in-app [moveraReferenceMapStyle].
const String moveraGoogleMapId = String.fromEnvironment('MOVERA_GOOGLE_MAP_ID');

class CustomGoogleMap extends StatefulWidget {
  final CameraPosition? initialPosition;
  final Set<Marker>? markers;
  final Set<Polyline>? polylines;
  final Set<Circle>? circles;
  final Set<Polygon>? polygons;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool mapToolbarEnabled;
  final bool compassEnabled;
  final bool buildingsEnabled;
  final bool indoorViewEnabled;
  final bool scrollGesturesEnabled;
  final bool zoomGesturesEnabled;
  final bool tiltGesturesEnabled;
  final bool rotateGesturesEnabled;
  final MapType mapType;
  final void Function(GoogleMapController)? onMapCreated;
  final void Function(LatLng)? onTap;
  final void Function(LatLng)? onLongPress;
  final void Function(CameraPosition)? onCameraMove;
  final void Function()? onCameraIdle;
  final void Function()? onCameraMoveStarted;
  final EdgeInsets padding;
  final String? customMapStyle;

  /// Cloud Map ID. When non-empty the cloud style wins, so no inline JSON
  /// style is passed (Google ignores it alongside a Map ID).
  final String cloudMapId;

  /// Lean the camera towards the horizon as the rider zooms in
  /// ([tiltForZoom], the driver app's curve), live during a pinch on the
  /// web. Screens that read the pickup from a screen-centred pin with
  /// flat-map maths pass false and stay flat.
  final bool tiltWithZoom;

  const CustomGoogleMap({
    super.key,
    this.initialPosition,
    this.markers,
    this.polylines,
    this.circles,
    this.polygons,
    this.myLocationEnabled = true,
    this.myLocationButtonEnabled = false,
    this.zoomControlsEnabled = false,
    this.mapToolbarEnabled = false,
    this.compassEnabled = false,
    this.buildingsEnabled = true,
    this.indoorViewEnabled = false,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
    this.mapType = MapType.normal,
    this.onMapCreated,
    this.onTap,
    this.onLongPress,
    this.onCameraMove,
    this.onCameraIdle,
    this.onCameraMoveStarted,
    this.padding = EdgeInsets.zero,
    this.customMapStyle,
    this.cloudMapId = moveraGoogleMapId,
    this.tiltWithZoom = true,
  });

  /// rider-r4-20: whether a map built before the Maps engine is available
  /// keeps checking for it. On the web the Maps script loads `async` and can
  /// land after the first build; screens such as Home cache this widget, so
  /// nothing else would rebuild the placeholder. Null: the web only.
  @visibleForTesting
  static bool? debugWaitForMaps;

  /// Tests: the keys of every map widget mounted so far, in order. On the
  /// web each mount is a new Google map the page keeps, so screens must
  /// not mount one for a moment they are about to park again.
  @visibleForTesting
  static final List<Key?> debugMounted = <Key?>[];

  @override
  State<CustomGoogleMap> createState() => _CustomGoogleMapState();
}

class _CustomGoogleMapState extends State<CustomGoogleMap> {
  GoogleMapController? _mapController;

  // Stockholm is the Rider-wide fallback for screens that do not supply a
  // camera position explicitly.
  static const CameraPosition _defaultPosition = CameraPosition(
    target: LatLng(59.3293, 18.0686),
    zoom: 13.0,
  );

  // Fingers on the map: Flutter pointers on phones, page events on the web
  // (where the map is a browser element Flutter's pointers never reach).
  int _fingers = 0;
  MapTouchSubscription? _webTouch;
  void Function()? _stopWebGestures;
  bool _settleOnRelease = false;
  Size? _viewport;

  // Native pointers, to tell a pan or pinch from a tap (the web gesture
  // layer reports its own).
  final Map<int, Offset> _pointerOrigins = <int, Offset>{};

  @override
  void initState() {
    super.initState();
    assert(() {
      CustomGoogleMap.debugMounted.add(widget.key);
      return true;
    }());
    _webTouch = watchMapTouch(onDown: _fingerDown, onUp: _fingerUp);
  }

  Timer? _mapsPoll;

  /// rider-r4-20: rebuild once the Maps engine turns up.
  void _waitForMaps() {
    if (_mapsPoll != null || !(CustomGoogleMap.debugWaitForMaps ?? kIsWeb)) {
      return;
    }
    _mapsPoll = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!googleMapsAvailable()) return;
      timer.cancel();
      _mapsPoll = null;
      if (mounted) setState(() {});
    });
  }

  MapView? get _view {
    final controller = _mapController;
    return controller == null ? null : mapViewOf(controller);
  }

  bool get _tiltsWithZoom => widget.tiltWithZoom;

  void _syncView() {
    final controller = _mapController;
    final view = _view;
    if (controller == null || view == null) return;
    view.size = _viewport;
    view.tiltWithZoom = _tiltsWithZoom;
    _syncTiltSupport(view);
    final id = view.mapId;
    if (id != null) {
      RiderMapBridge.gestures(
        id,
        scroll: widget.scrollGesturesEnabled,
        zoom: widget.zoomGesturesEnabled,
        rotate: widget.rotateGesturesEnabled,
        tilt: widget.tiltGesturesEnabled,
      );
      RiderMapBridge.tiltFollowsZoom(id, _tiltsWithZoom);
    }
  }

  /// Raster web maps ignore tilt; vector maps and phones use it. The web
  /// gesture layer knows the renderer Google picked; before it does, a Map
  /// ID means vector.
  void _syncTiltSupport(MapView view) {
    if (!kIsWeb) {
      view.supportsTilt = true;
      return;
    }
    final id = view.mapId;
    view.supportsTilt =
        (id == null ? null : RiderMapBridge.supports3D(id)) ??
        widget.cloudMapId.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant CustomGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncView();
  }

  void _fingerDown() {
    _fingers += 1;
    // The camera never moves under a finger.
    _view?.touching = true;
  }

  void _fingerUp() {
    if (_fingers == 0) return;
    _fingers -= 1;
    if (_fingers > 0) return;
    _view?.touching = false;
    if (_settleOnRelease) _settleTilt();
  }

  /// The rider moved the map by hand: it is theirs for a while
  /// ([MapView.followHold]) and its tilt settles to the zoom once let go.
  void _movedByHand() {
    final view = _view;
    if (view == null) return;
    view.movedByHandAt = MapView.now();
    // The rider's own move wins over any app ease still running (a wheel
    // zoom has no finger to stop it).
    if (view.easing) view.interrupt();
  }

  void _onMoveStarted() => widget.onCameraMoveStarted?.call();

  void _onMove(CameraPosition position) {
    final view = _view;
    // While the app glides the camera, the echoes of its own frames are
    // late copies of poses it already knows: they must not become the
    // origin of the next frame.
    if (view != null && !view.easing && !view.isLateEcho(position)) {
      view.pose = position;
    }
    widget.onCameraMove?.call(position);
  }

  void _onIdle() {
    _settleTilt();
    widget.onCameraIdle?.call();
  }

  /// The camera stopped after the rider zoomed or panned it: tilt it to
  /// match their zoom ([tiltForZoom]), so a zoom out flattens it and a zoom
  /// in leans it towards the horizon. Maps reports idle whenever the camera
  /// pauses, also under a finger that holds a pinch: nothing moves until
  /// the map is let go, or the ease would pull the zoom back from under the
  /// rider's fingers. Only the tilt moves; the target and zoom are the
  /// latest ones, never an older pose. (On the web the gesture layer
  /// already tilts with the zoom on every pinch frame, so there this
  /// usually has nothing left to do.)
  void _settleTilt() {
    if (_fingers > 0) {
      _settleOnRelease = true;
      return;
    }
    _settleOnRelease = false;
    final controller = _mapController;
    final view = _view;
    final pose = view?.pose;
    if (controller == null || view == null || pose == null) return;
    if (view.movedByHandAt == null || view.easing) return;
    _syncTiltSupport(view);
    if (!view.tiltWithZoom || !view.supportsTilt) return;
    final tilt = view.tiltFor(pose.zoom);
    if ((tilt - pose.tilt).abs() < 1) return;
    unawaited(easeTiltTo(controller, tilt));
  }

  void _pointerDown(PointerDownEvent event) {
    _pointerOrigins[event.pointer] = event.position;
    if (_pointerOrigins.length > 1) _movedByHand();
    _fingerDown();
  }

  void _pointerMove(PointerMoveEvent event) {
    final origin = _pointerOrigins[event.pointer];
    if (origin != null && (event.position - origin).distance >= 6) {
      _movedByHand();
    }
  }

  void _pointerUp(PointerEvent event) {
    if (_pointerOrigins.remove(event.pointer) == null) return;
    _fingerUp();
  }

  @override
  Widget build(BuildContext context) {
    // Render the real Google Map immediately. The exact Movera style is passed
    // during creation, so there is no separate loading-color cover or reveal
    // timer delaying the first visible map frame.
    // On the web without the Maps JavaScript API, a GoogleMap throws while
    // building; show a calm map-coloured surface instead of an error.
    if (!googleMapsAvailable()) {
      _waitForMaps();
      return const ColoredBox(
        key: ValueKey('map-unavailable'),
        color: Color(0xFFE9EEF1),
        child: SizedBox.expand(),
      );
    }
    final String mapId = widget.cloudMapId.trim();
    final bool hasMapId = mapId.isNotEmpty;
    // The map opens with the tilt of its zoom, so the first frame is
    // already the pose the camera keeps (no tilt correction afterwards).
    final requested = widget.initialPosition ?? _defaultPosition;
    final initial = _tiltsWithZoom && (!kIsWeb || hasMapId)
        ? withZoomTilt(requested)
        : requested;
    final map = GoogleMap(
      initialCameraPosition: initial,
      markers: widget.markers ?? {},
      polylines: widget.polylines ?? {},
      circles: widget.circles ?? {},
      polygons: widget.polygons ?? {},
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: widget.myLocationButtonEnabled,
      zoomControlsEnabled: widget.zoomControlsEnabled,
      mapToolbarEnabled: widget.mapToolbarEnabled,
      compassEnabled: widget.compassEnabled,
      // Owner, live test 2026-10-26 (N5): Google's live traffic layer
      // (green/red/yellow roads) never rides over the Movera map style; the
      // cloud Map ID is the only styling on every map.
      trafficEnabled: false,
      buildingsEnabled: widget.buildingsEnabled,
      indoorViewEnabled: widget.indoorViewEnabled,
      scrollGesturesEnabled: widget.scrollGesturesEnabled,
      zoomGesturesEnabled: widget.zoomGesturesEnabled,
      tiltGesturesEnabled: widget.tiltGesturesEnabled,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      mapType: widget.mapType,
      padding: widget.padding,
      cloudMapId: hasMapId ? mapId : null,
      style: hasMapId ? null : widget.customMapStyle ?? moveraReferenceMapStyle,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        final view = mapViewOf(controller);
        view.pose ??= initial;
        if (kIsWeb) {
          view.mapId = controller.mapId;
          _stopWebGestures?.call();
          _stopWebGestures = RiderMapBridge.listen(
            controller.mapId,
            _movedByHand,
          );
          _logWebMapCreated(controller.mapId);
        }
        _syncView();

        if (kDebugMode) {
          controller.getStyleError().then((String? styleError) {
            if (styleError != null) {
              debugPrint('Movera Google Maps style error: $styleError');
            }
          });
        }

        if (widget.onMapCreated != null) {
          widget.onMapCreated!(controller);
        }
      },
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onCameraMove: _onMove,
      onCameraIdle: _onIdle,
      onCameraMoveStarted: _onMoveStarted,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
          _viewport = Size(
            (constraints.maxWidth - widget.padding.horizontal).clamp(
              0.0,
              double.infinity,
            ),
            (constraints.maxHeight - widget.padding.vertical).clamp(
              0.0,
              double.infinity,
            ),
          );
          _view?.size = _viewport;
        }
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: kIsWeb ? null : _pointerDown,
          onPointerMove: kIsWeb ? null : _pointerMove,
          onPointerUp: kIsWeb ? null : _pointerUp,
          onPointerCancel: kIsWeb ? null : _pointerUp,
          onPointerSignal: kIsWeb ? null : (_) => _movedByHand(),
          child: map,
        );
      },
    );
  }

  GoogleMapController? get mapController => _mapController;

  /// Evidence for the web lifecycle: how many maps the page holds and
  /// whether the browser has taken WebGL contexts away (see
  /// docs/web-lifecycle-investigation.md). One line per map, info level.
  void _logWebMapCreated(int mapId) {
    final stats = RiderMapBridge.stats();
    final gpu = webGlContextEvents();
    AppLog.info(
      'map.web_created',
      extra: {
        'mapId': mapId,
        'liveMaps': stats?.live,
        'createdMaps': stats?.created,
        'recycledMaps': stats?.recycled,
        'releasedMaps': stats?.released,
        'releasedContexts': stats?.contextsReleased,
        'webglLost': gpu.lost,
        'webglRestored': gpu.restored,
      },
    );
  }

  @override
  void dispose() {
    // GoogleMap owns and disposes its platform controller. Disposing the same
    // web controller again here races the platform view teardown and throws a
    // generic browser page error when a map screen is popped (for example when
    // confirming the exact pickup before SelectRide opens).
    _mapsPoll?.cancel();
    _mapsPoll = null;
    _webTouch?.cancel();
    _webTouch = null;
    _stopWebGestures?.call();
    _stopWebGestures = null;
    // A map replaced under a finger must not leave its camera held.
    if (_fingers > 0) _view?.touching = false;
    final controller = _mapController;
    _mapController = null;
    // The web layer takes the map back for the next screen once Flutter has
    // removed its element; the plugin itself never does. Only the web (and
    // a test standing in for the layer) wants the id: phone tests hand in
    // bare fakes.
    if (controller != null && RiderMapBridge.wantsRelease) {
      RiderMapBridge.release(controller.mapId);
    }
    super.dispose();
  }
}
