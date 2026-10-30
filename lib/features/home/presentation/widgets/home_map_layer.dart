import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Home's live map. Shows a plain placeholder while [parked], and otherwise
/// reuses the same map widget until markers, circles, polygons or padding
/// actually change.
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
  });

  final HomeLocationController location;
  final ValueNotifier<bool> parked;
  final EdgeInsets padding;
  final CameraPosition initialPosition;
  final String mapStyle;
  final void Function(CameraPosition) onCameraMove;
  final void Function(GoogleMapController) onMapCreated;

  /// How long the map box must stay at its new size before the map is told
  /// to redraw (a mobile browser's toolbar animates over a few frames).
  static const Duration redrawSettle = Duration(milliseconds: 250);

  /// Times the map was told to redraw after its box grew (tests).
  @visibleForTesting
  static int debugRedrawRequests = 0;

  @override
  State<HomeMapLayer> createState() => _HomeMapLayerState();
}

class _HomeMapLayerState extends State<HomeMapLayer> {
  Widget? _cached;
  Set<Marker>? _markers;
  Set<Circle>? _circles;
  Set<Polygon>? _polygons;
  EdgeInsets? _padding;
  bool? _parked;
  GoogleMapController? _controller;
  CameraPosition? _camera;
  Size? _size;
  Timer? _redrawTimer;

  @override
  void initState() {
    super.initState();
    widget.location.addListener(_onChange);
    widget.parked.addListener(_onChange);
  }

  @override
  void didUpdateWidget(HomeMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      oldWidget.location.removeListener(_onChange);
      widget.location.addListener(_onChange);
    }
    if (oldWidget.parked != widget.parked) {
      oldWidget.parked.removeListener(_onChange);
      widget.parked.addListener(_onChange);
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
    if (!mounted || widget.parked.value) return;
    HomeMapLayer.debugRedrawRequests++;
    final controller = _controller;
    if (controller == null) return;
    RiderMapBridge.redraw(controller.mapId);
    final camera = _camera ?? widget.initialPosition;
    controller
        .moveCamera(CameraUpdate.newCameraPosition(camera))
        .catchError((Object _) {});
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    widget.onMapCreated(controller);
  }

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
    widget.parked.removeListener(_onChange);
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
    _parked = false;
    _markers = widget.location.markers;
    _circles = widget.location.locationCircles;
    _polygons = widget.location.locationDirection;
    _padding = widget.padding;
    _cached = CustomGoogleMap(
      key: const ValueKey('home-map'),
      initialPosition: widget.initialPosition,
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
