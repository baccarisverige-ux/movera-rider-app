import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final bool trafficEnabled;
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
    this.trafficEnabled = false,
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
  });

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

  @override
  Widget build(BuildContext context) {
    // Render the real Google Map immediately. The exact Movera style is passed
    // during creation, so there is no separate loading-color cover or reveal
    // timer delaying the first visible map frame.
    // On the web without the Maps JavaScript API, a GoogleMap throws while
    // building; show a calm map-coloured surface instead of an error.
    if (!googleMapsAvailable()) {
      return const ColoredBox(
        key: ValueKey('map-unavailable'),
        color: Color(0xFFE9EEF1),
        child: SizedBox.expand(),
      );
    }
    final String mapId = widget.cloudMapId.trim();
    final bool hasMapId = mapId.isNotEmpty;
    return GoogleMap(
      initialCameraPosition: widget.initialPosition ?? _defaultPosition,
      markers: widget.markers ?? {},
      polylines: widget.polylines ?? {},
      circles: widget.circles ?? {},
      polygons: widget.polygons ?? {},
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: widget.myLocationButtonEnabled,
      zoomControlsEnabled: widget.zoomControlsEnabled,
      mapToolbarEnabled: widget.mapToolbarEnabled,
      compassEnabled: widget.compassEnabled,
      trafficEnabled: widget.trafficEnabled,
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
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
      onCameraMoveStarted: widget.onCameraMoveStarted,
    );
  }

  GoogleMapController? get mapController => _mapController;

  @override
  void dispose() {
    // GoogleMap owns and disposes its platform controller. Disposing the same
    // web controller again here races the platform view teardown and throws a
    // generic browser page error when a map screen is popped (for example when
    // confirming the exact pickup before SelectRide opens).
    _mapController = null;
    super.dispose();
  }
}
