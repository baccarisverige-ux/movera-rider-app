import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Owner 2026-11-17 ("Make Max zoom out like that not all planet"): the
/// widest any Movera map may go. About Sweden, Norway, Denmark and the
/// Baltic on one phone screen; never the whole planet. A zoom level, not a
/// region lock: panning stays free in every country.
const double kMapMinZoom = 4.5;

/// The zoom range every map is built with: zoom-out stops at [kMapMinZoom],
/// for pinch and for programmatic camera moves and fits (native and web).
const MinMaxZoomPreference kMapZoomPreference = MinMaxZoomPreference(
  kMapMinZoom,
  null,
);

/// [zoom] never wider than [kMapMinZoom].
double clampMapZoom(double zoom) => zoom < kMapMinZoom ? kMapMinZoom : zoom;
