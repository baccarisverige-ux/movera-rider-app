import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('moveraStartHeading')
external JSPromise<JSBoolean> _startHeading();

@JS('moveraStopHeading')
external void _stopHeading();

@JS('moveraArmHeadingFromGesture')
external void _armHeading();

/// Whether this platform has a compass source at all.
const bool headingTrackingSupported = true;

Future<bool> startHeadingTracking() async {
  try {
    final ok = (await _startHeading().toDart).toDart;
    globalContext.setProperty('moveraDartStartResult'.toJS, ok.toJS);
    return ok;
  } catch (error) {
    globalContext.setProperty(
      'moveraDartStartError'.toJS,
      error.toString().toJS,
    );
    return false;
  }
}

double? currentHeading() {
  try {
    final value = globalContext.getProperty('moveraDeviceHeading'.toJS);
    if (value.isUndefined || value.isNull) return null;
    return (value as JSNumber).toDartDouble;
  } catch (_) {
    return null;
  }
}

/// Owner 2026-11-07 (item 10): iOS asks Motion & Orientation only on the
/// rider's "my position" tap. web/index.html asks on the rest of the tap
/// that calls this (its touchend / click are trusted gestures).
void armHeadingPrompt() {
  try {
    _armHeading();
  } catch (_) {
    // An older page without the function: no prompt.
  }
}

void stopHeadingTracking() {
  try {
    _stopHeading();
  } catch (_) {
    // Web interop: nothing to stop when the JS bridge is absent.
  }
}
