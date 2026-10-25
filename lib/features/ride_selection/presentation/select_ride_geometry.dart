import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// The strip of map above the fully opened sheet, under the status bar.
const double selectRideFullTopGap = 52;

/// The expanded ride sheet's height. D-009 kept a third of the map above it;
/// owner round 2 asked for it near the top instead, with the address bar
/// sliding away (large text still gets the full height it needs).
double selectRideMaxSheetHeight(MediaQueryData media) {
  // UI-1: the upper bound must never fall below the lower one, or clamp
  // throws on screens shorter than 625 px.
  final minH = (348 + media.padding.bottom).clamp(
    300.0,
    math.max(300.0, media.size.height * 0.48),
  );
  final largeText = media.textScaler.scale(1) >= 1.6;
  // Owner round 2 (replaces D-009's third of the screen): fully up, the
  // sheet goes near the top like the other ride apps and the address bar
  // slides away; a strip of map stays above it.
  final topClearance = largeText ? 0.0 : selectRideFullTopGap;
  final maxH = media.size.height - media.padding.top - topClearance;
  return maxH < minH + 64 ? minH + 64 : maxH;
}

/// D-009: bounds that frame [pickup] and [destination] inside a map of
/// [mapHeight] whose bottom [bottomObstruction] pixels are covered by the
/// sheet and whose top [topObstruction] pixels sit under the search bar.
/// google_maps_flutter only takes one uniform padding, so the covered bands
/// are reserved by stretching the bounds south and north.
///
/// Owner round 4: [route] (the road line's points, when known) widens the
/// bounds so a road that bulges past the straight line stays on screen, and
/// [edgePadding] leaves room for the time bubbles drawn above the pins
/// (about 110 x 56 px, anchored at their bottom centre).
({GeoPoint southwest, GeoPoint northeast, double padding}) selectRideCameraFit({
  required GeoPoint pickup,
  required GeoPoint destination,
  required double mapHeight,
  required double bottomObstruction,
  double topObstruction = 0,
  List<GeoPoint> route = const [],
  double edgePadding = selectRideEdgePadding,
}) {
  var south = math.min(pickup.latitude, destination.latitude);
  var north = math.max(pickup.latitude, destination.latitude);
  var west = math.min(pickup.longitude, destination.longitude);
  var east = math.max(pickup.longitude, destination.longitude);
  for (final point in route) {
    south = math.min(south, point.latitude);
    north = math.max(north, point.latitude);
    west = math.min(west, point.longitude);
    east = math.max(east, point.longitude);
  }
  final full = math.max(mapHeight - 2 * edgePadding, 1.0);
  final bottom = math.max(bottomObstruction, 0.0);
  final top = math.max(topObstruction, 0.0);
  final usable = math.max(
    mapHeight - bottom - top - 2 * edgePadding,
    full * 0.2,
  );
  final span = north - south;
  final stretchedSouth = south - span * (bottom / usable);
  final stretchedNorth = north + span * (top / usable);
  return (
    southwest: GeoPoint(math.max(stretchedSouth, -85.0), west),
    northeast: GeoPoint(math.min(stretchedNorth, 85.0), east),
    padding: edgePadding,
  );
}

/// Room kept around the route on Select Ride: the time bubble above a pin
/// is about 110 px wide and 56 px tall, so half its width plus a margin.
const double selectRideEdgePadding = 76;

/// Rough trip minutes from the straight-line distance, until the server sends
/// the route duration (LATER_JOB B4): ×1.35 for roads, 40 km/h average.
int estimatedTripMinutes(GeoPoint from, GeoPoint to) =>
    estimatedRouteMinutes(from, const [], to);

/// [estimatedTripMinutes] over pickup → each of [stops] in order →
/// destination (rider-u60: a stop the rider added moves the arrival).
int estimatedRouteMinutes(GeoPoint from, List<GeoPoint> stops, GeoPoint to) {
  final points = [from, ...stops, to];
  var km = 0.0;
  for (var i = 1; i < points.length; i++) {
    km += _greatCircleKm(points[i - 1], points[i]);
  }
  return math.max(3, (km * 1.35 / 40 * 60).round());
}

double _greatCircleKm(GeoPoint from, GeoPoint to) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(to.latitude - from.latitude);
  final dLng = rad(to.longitude - from.longitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(from.latitude)) *
          math.cos(rad(to.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// "23:48"
String clockTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
