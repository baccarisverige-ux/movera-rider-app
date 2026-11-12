import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';

/// Home's live map. Reuses the same map widget until markers, circles,
/// polygons or padding actually change.
///
/// While [parked] (a page covers Home): on native (G25 step A) a map that
/// exists stays mounted, frozen as it was, and [onMapResumed] gives it back
/// to Home when Home is on top again: no new platform map, no flash, no
/// camera jump. On the web, and before any map was made, a plain
/// placeholder shows instead (the web's map pool keeps its own parking).
class HomeMapLayer extends StatefulWidget {
  const HomeMapLayer({
    super.key,
    required this.location,
    required this.parked,
    required this.padding,
    required this.initialPosition,
    required this.mapStyle,
    required this.onCameraMove,
    required this.onMapCreated,
    this.onMapResumed,
    this.birthCamera,
  });

  final HomeLocationController location;
  final ValueNotifier<bool> parked;
  final EdgeInsets padding;
  final CameraPosition initialPosition;
  final String mapStyle;
  final void Function(CameraPosition) onCameraMove;
  final void Function(GoogleMapController) onMapCreated;

  /// G25: the map kept while parked is shown again (native only).
  final void Function(GoogleMapController)? onMapResumed;

  /// Owner decision "Home map start" (2026-11-07): read each time a new map
  /// is made (the first one, and again after being parked), so the map is
  /// born where the rider is now. Null: [initialPosition].
  final CameraPosition Function()? birthCamera;

  /// How long the map box must stay at its new size before the map is told
  /// to redraw (a mobile browser's toolbar animates over a few frames).
  static const Duration redrawSettle = Duration(milliseconds: 250);

  /// Times the map was told to redraw after its box grew (tests).
  @visibleForTesting
  static int debugRedrawRequests = 0;

  /// Times the "map is ready" path scheduled its redraw (tests).
  @visibleForTesting
  static int debugMapReadyRedraws = 0;

  @override
  State<HomeMapLayer> createState() => HomeMapLayerState();
}

class HomeMapLayerState extends State<HomeMapLayer> {
  Widget? _cached;
  Set<Marker>? _markers;
  Set<Circle>? _circles;
  Set<Polygon>? _polygons;
  EdgeInsets? _padding;
  bool? _parked;
  GoogleMapController? _controller;
  CameraPosition? _camera;

  /// The camera the current map was born with.
  CameraPosition? _bornWith;
  Size? _size;
  Timer? _redrawTimer;

  /// A redraw asked while the map was not created yet (or parked). 2026-11-07
  /// (owner's iPhone, grey band after a trip): it used to be dropped.
  bool _redrawPending = false;

  /// G25: the live map stays mounted (frozen) while parked.
  bool _held = false;

  /// G25: the kept map's platform view came up while Home was covered; Home
  /// is told when it is on top again, not under the cover.
  bool _createdWhileParked = false;

  @override
  void initState() {
    super.initState();
    widget.location.addListener(_onChange);
    widget.parked.addListener(_onParkedChange);
  }

  bool get _hasLiveMap => _cached != null && _parked == false;

  void _onParkedChange() {
    if (widget.parked.value) {
      _held = ParkableMap.keepsMapWhileParked && _hasLiveMap;
    } else if (_held) {
      _held = false;
      final controller = _controller;
      if (_createdWhileParked && controller != null) {
        _createdWhileParked = false;
        widget.onMapCreated(controller);
        _mapReady();
      } else if (controller != null) {
        widget.onMapResumed?.call(controller);
      }
      if (_redrawPending) {
        _redrawTimer?.cancel();
        _redrawTimer = Timer(HomeMapLayer.redrawSettle, _redraw);
      }
    }
    _onChange();
  }

  @override
  void didUpdateWidget(HomeMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      oldWidget.location.removeListener(_onChange);
      widget.location.addListener(_onChange);
    }
    if (oldWidget.parked != widget.parked) {
      oldWidget.parked.removeListener(_onParkedChange);
      widget.parked.addListener(_onParkedChange);
    }
  }

  /// Owner decision (rider map, 2026-10-30): the map must always fill the
  /// screen behind the sheet. iOS Safari grows the visual viewport when its
  /// toolbar collapses; Home then grows the map box, but the cached map
  /// widget is reused and Google Maps can keep its old, shorter tiles,
  /// leaving a flat grey band above the sheet. So when the box grows, once
  /// the size has settled the map is moved to its own camera again, which
  /// makes Google Maps measure its element and draw the new area.
  void _noteSize(Size size) {
    final last = _size;
    _size = size;
    if (last == null) return;
    if (size.height <= last.height && size.width <= last.width) return;
    _redrawTimer?.cancel();
    _redrawTimer = Timer(HomeMapLayer.redrawSettle, _redraw);
  }

  void _redraw() {
    if (!mounted) return;
    if (widget.parked.value) {
      _redrawPending = true;
      return;
    }
    HomeMapLayer.debugRedrawRequests++;
    final controller = _controller;
    if (controller == null) {
      // 2026-11-07: after a trip Home builds the map again while the panel
      // shrinks; the box can grow before Google Maps is ready. Keep the
      // request and send it once the map exists (see _mapReady).
      _redrawPending = true;
      return;
    }
    _redrawPending = false;
    RiderMapBridge.redraw(controller.mapId);
    final camera = _camera ?? _bornWith ?? widget.initialPosition;
    controller
        .moveCamera(CameraUpdate.newCameraPosition(camera))
        .catchError((Object _) {});
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    if (widget.parked.value) {
      _createdWhileParked = true;
      return;
    }
    widget.onMapCreated(controller);
    _mapReady();
  }

  /// 2026-11-07 (owner decision "Oui, corriger"): once the map exists it is
  /// redrawn one time after the size settles, so a box that grew while the
  /// map was being created (or a kept request) is drawn in full on Safari.
  void _mapReady() {
    HomeMapLayer.debugMapReadyRedraws++;
    _redrawPending = false;
    _redrawTimer?.cancel();
    _redrawTimer = Timer(HomeMapLayer.redrawSettle, _redraw);
  }

  /// Runs the "map is ready" path without a platform map (tests).
  @visibleForTesting
  void debugMapReady() => _mapReady();

  /// True while a redraw waits for the map (tests).
  @visibleForTesting
  bool get debugRedrawPending => _redrawPending;

  void _onCameraMove(CameraPosition camera) {
    _camera = camera;
    widget.onCameraMove(camera);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _redrawTimer?.cancel();
    widget.location.removeListener(_onChange);
    widget.parked.removeListener(_onParkedChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight && constraints.hasBoundedWidth) {
          _noteSize(constraints.biggest);
        }
        return _buildMap();
      },
    );
  }

  Widget _buildMap() {
    if (widget.parked.value) {
      // G25: the kept map, as it was: no overlay or padding updates while
      // it is hidden (Home also stops its location and camera work).
      if (_held && _hasLiveMap) return _cached!;
      const parked = ColoredBox(color: Color(0xFFEEF1E8));
      _cached = parked;
      _parked = true;
      return parked;
    }
    if (_cached != null &&
        _parked == false &&
        identical(_markers, widget.location.markers) &&
        identical(_circles, widget.location.locationCircles) &&
        identical(_polygons, widget.location.locationDirection) &&
        _padding == widget.padding) {
      return _cached!;
    }
    // A new map (none yet, or the parked placeholder before): born on the
    // camera of now. An existing one keeps its own camera.
    if (_parked != false || _bornWith == null) {
      _bornWith = widget.birthCamera?.call() ?? widget.initialPosition;
      _camera = null;
    }
    _parked = false;
    _markers = widget.location.markers;
    _circles = widget.location.locationCircles;
    _polygons = widget.location.locationDirection;
    _padding = widget.padding;
    _cached = CustomGoogleMap(
      key: const ValueKey('home-map'),
      initialPosition: _bornWith,
      markers: widget.location.markers,
      circles: widget.location.locationCircles,
      polygons: widget.location.locationDirection,
      padding: widget.padding,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: true,
      indoorViewEnabled: false,
      mapType: MapType.normal,
      customMapStyle: widget.mapStyle,
      onCameraMove: _onCameraMove,
      onMapCreated: _onMapCreated,
      onTap: (LatLng position) {},
    );
    return _cached!;
  }
}
