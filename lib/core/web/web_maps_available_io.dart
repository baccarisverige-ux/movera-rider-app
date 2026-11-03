import 'package:movera_rider/core/maps/native_maps_config.dart';

/// On phones: true unless iOS reported that the build has no Maps key.
bool webGoogleMapsAvailable() => NativeMapsConfig.hasMapsKey;

/// Phones have the Maps engine built in: nothing to load.
void webRequestGoogleMaps() {}
