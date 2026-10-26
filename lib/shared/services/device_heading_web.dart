import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('moveraStartHeading')
external JSPromise<JSBoolean> _startHeading();

@JS('moveraStopHeading')
external void _stopHeading();

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

void stopHeadingTracking() {
  try {
    _stopHeading();
  } catch (_) {
    // Web interop: nothing to stop when the JS bridge is absent.
  }
}
