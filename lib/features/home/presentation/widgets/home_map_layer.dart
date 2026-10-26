import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.location.removeListener(_onChange);
    widget.parked.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      onCameraMove: widget.onCameraMove,
      onMapCreated: widget.onMapCreated,
      onTap: (LatLng position) {},
    );
    return _cached!;
  }
}
