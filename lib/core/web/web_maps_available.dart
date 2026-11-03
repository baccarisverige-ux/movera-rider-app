import 'package:movera_rider/core/web/web_maps_available_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/web_maps_available_web.dart';

/// Whether the Google Maps engine can draw a map here. On phones, true
/// unless an iOS build has no Maps API key ([NativeMapsConfig]); on the web
/// only once the Maps JavaScript API has loaded — building a map without it
/// throws inside the maps plugin.
bool googleMapsAvailable() => webGoogleMapsAvailable();

/// Web: asks the page to load Maps JavaScript, which it no longer loads at
/// start (owner 2026-11-03, LT-4 "load on open"). Phones: nothing.
void requestGoogleMaps() => webRequestGoogleMaps();
