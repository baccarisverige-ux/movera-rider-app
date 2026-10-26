import 'dart:js_interop';
import 'dart:js_interop_unsafe';

({int lost, int restored}) webGlContextEvents() {
  try {
    final counters = globalContext.getProperty<JSAny?>('moveraGpu'.toJS);
    if (counters == null || !counters.isA<JSObject>()) {
      return (lost: 0, restored: 0);
    }
    final object = counters as JSObject;
    int read(String key) {
      final value = object.getProperty<JSAny?>(key.toJS);
      return value != null && value.isA<JSNumber>()
          ? (value as JSNumber).toDartInt
          : 0;
    }
    return (lost: read('lost'), restored: read('restored'));
  } catch (_) {
    return (lost: 0, restored: 0);
  }
}
