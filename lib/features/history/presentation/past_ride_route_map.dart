import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_zoom_limit.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/features/history/application/trip_path.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/styles/route_style.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart'
    show RouteEndpointMarker;

/// BQ-V16 (owner driver-g11.md:6, "must be for all apps live trip or
/// history including admin"): the past ride's map in History.
///
/// Live (contract wire) it draws `GET /trips/{tripId}/path`: the driven
/// line, or the server's planned route for an old ride (said under the
/// map). When the path cannot be read it shows the pickup and drop-off
/// pins only (contract.json#tripPath.apps), or nothing when the ride has
/// no saved points: a live past ride never gets a made-up line. The demo
/// keeps its drawing ([ReservationRoutePreview]).
class PastRideRouteMap extends StatefulWidget {
  const PastRideRouteMap({
    super.key,
    required this.tripId,
    required this.pickup,
    required this.destination,
    this.height = 132,
    this.loader,
  });

  final String tripId;
  final ReservationPlace pickup;
  final ReservationPlace destination;
  final double height;

  /// `GET /trips/{tripId}/path` (tests give their own).
  final Future<TripPath?> Function(String tripId)? loader;

  /// Tests: true draws the live map, false the demo drawing. Null: the
  /// app's transport decides (the contract wire is live).
  @visibleForTesting
  static bool? debugLive;

  @override
  State<PastRideRouteMap> createState() => _PastRideRouteMapState();
}

class _PastRideRouteMapState extends State<PastRideRouteMap> {
  late final bool _live =
      PastRideRouteMap.debugLive ?? AppScope.instance.api.contractWire;
  bool _loading = true;
  TripPath? _path;
  BitmapDescriptor? _pickupPin;
  BitmapDescriptor? _dropoffPin;

  @override
  void initState() {
    super.initState();
    if (!_live) return;
    _load();
    _loadPins();
  }

  Future<void> _load() async {
    final path = await (widget.loader ?? TripPath.load)(widget.tripId);
    if (!mounted) return;
    setState(() {
      _path = path;
      _loading = false;
    });
  }

  Future<void> _loadPins() async {
    try {
      final pins = await Future.wait([
        RouteEndpointMarker.createIcon(pickup: true),
        RouteEndpointMarker.createIcon(pickup: false),
      ]);
      if (!mounted) return;
      setState(() {
        _pickupPin = pins[0];
        _dropoffPin = pins[1];
      });
    } catch (_) {
      // The plugin's default pins stay.
    }
  }

  static GeoPoint? _saved(ReservationPlace place) {
    final lat = place.lat;
    final lng = place.lng;
    if (lat == null || lng == null) return null;
    final p = GeoPoint(lat, lng);
    return p.isValid ? p : null;
  }

  static LatLng _ll(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context) {
    if (!_live) {
      return ReservationRoutePreview(
        pickup: widget.pickup.label,
        destination: widget.destination.label,
        height: widget.height,
      );
    }
    if (_loading) {
      return _frame(
        const ColoredBox(
          key: ValueKey('history-route-loading'),
          color: Color(0xFFEFF2F4),
        ),
      );
    }
    final path = _path;
    final pickup = path?.pickup ?? _saved(widget.pickup);
    final dropoff = path?.dropoff ?? _saved(widget.destination);
    if (pickup == null || dropoff == null) return const SizedBox.shrink();
    final line = path?.points ?? const <GeoPoint>[];
    final extent = [pickup, ...?path?.stops, ...line, dropoff];
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _ll(pickup),
        icon:
            _pickupPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 0.5),
      ),
      for (final (i, stop) in (path?.stops ?? const <GeoPoint>[]).indexed)
        Marker(
          markerId: MarkerId('stop-$i'),
          position: _ll(stop),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      Marker(
        markerId: const MarkerId('destination'),
        position: _ll(dropoff),
        icon:
            _dropoffPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
      ),
    };
    final polylines = line.length >= 2
        ? styledRoute(
            resolvedRoutePolyline(
              id: 'past-route',
              points: [for (final p in line) _ll(p)],
              color: RiderRouteStyle.color,
            ),
          )
        : const <Polyline>{};
    final bounds = _bounds(extent);
    final map = _frame(
      CustomGoogleMap(
        key: const ValueKey('history-route-map'),
        initialPosition: CameraPosition(
          target: LatLng(
            (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
            (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
          ),
          zoom: pastRideFitZoom(bounds),
        ),
        markers: markers,
        polylines: polylines,
        myLocationEnabled: false,
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        tiltGesturesEnabled: false,
        rotateGesturesEnabled: false,
        tiltWithZoom: false,
        onMapCreated: (controller) async {
          try {
            await controller.moveCamera(
              CameraUpdate.newLatLngBounds(bounds, 28),
            );
          } catch (_) {
            // The first camera (centre and zoom of the same box) stays.
          }
        },
      ),
    );
    if (path?.source != TripPathSource.planned) return map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        map,
        const SizedBox(height: 6),
        Text(
          context.l10n.historyPlannedRoute,
          key: const ValueKey('history-route-planned'),
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C656C)),
        ),
      ],
    );
  }

  Widget _frame(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: child,
    ),
  );

  static LatLngBounds _bounds(List<GeoPoint> points) {
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final p in points) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }
}

/// A zoom that fits the box before the map can measure it; never wider
/// than [kMapMinZoom] (owner 2026-11-17, max zoom-out).
double pastRideFitZoom(LatLngBounds b) {
  final span = math.max(
    b.northeast.latitude - b.southwest.latitude,
    b.northeast.longitude - b.southwest.longitude,
  );
  if (span <= 0) return 15;
  return (math.log(360 / span) / math.ln2 - 1)
      .clamp(kMapMinZoom, 16)
      .toDouble();
}
