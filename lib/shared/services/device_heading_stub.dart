// Native (Android/iOS) and VM builds have no compass heading source.
//
// The web build reads DeviceOrientation through web/index.html
// (device_heading_web.dart). Android and iOS would need a native sensor
// plugin (for example flutter_compass or sensors_plus), which the app does not
// ship. Until one is added the puck on a phone turns only with the GPS course
// (`Position.heading`, which needs movement); this stub never invents a
// heading, so a stationary rider sees no direction rather than a wrong one.

/// Whether this platform has a compass source at all.
const bool headingTrackingSupported = false;

Future<bool> startHeadingTracking() async => false;

double? currentHeading() => null;

void stopHeadingTracking() {}

/// The web asks the motion permission on the tap that calls this; nothing
/// to ask here.
void armHeadingPrompt() {}
