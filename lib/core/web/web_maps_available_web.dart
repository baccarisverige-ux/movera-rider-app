import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool webGoogleMapsAvailable() {
  final google = globalContext.getProperty<JSAny?>('google'.toJS);
  if (google == null || !google.isA<JSObject>()) return false;
  final maps = (google as JSObject).getProperty<JSAny?>('maps'.toJS);
  return maps != null && maps.isA<JSObject>();
}

/// Owner 2026-11-03 (LT-4): web/index.html loads Maps JavaScript only when
/// the first map asks for it. Safe to call often; the page loads it once.
void webRequestGoogleMaps() {
  try {
    globalContext.callMethod<JSAny?>('moveraLoadGoogleMaps'.toJS);
  } catch (_) {
    // No loader (an older page): the map waits and says it is unavailable.
  }
}
