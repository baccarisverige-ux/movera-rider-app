import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('riderMapCamera')
external JSObject? get _layer;

/// The layer is loaded, Maps JavaScript is there and [mapId] is installed.
JSObject? _forMap(int mapId) {
  final layer = _layer;
  if (layer == null) return null;
  if (!layer.callMethod<JSBoolean>('ready'.toJS).toDart) return null;
  if (!layer.callMethod<JSBoolean>('has'.toJS, mapId.toJS).toDart) return null;
  return layer;
}

bool? supports3D(int mapId) => _forMap(
  mapId,
)?.callMethod<JSBoolean?>('supports3D'.toJS, mapId.toJS)?.toDart;

void gestures(int mapId, bool scroll, bool zoom, bool rotate, bool tilt) {
  _forMap(mapId)?.callMethodVarArgs<JSAny?>('gestures'.toJS, [
    mapId.toJS,
    scroll.toJS,
    zoom.toJS,
    rotate.toJS,
    tilt.toJS,
  ]);
}

void tiltFollowsZoom(int mapId, bool enabled) {
  _forMap(
    mapId,
  )?.callMethod<JSAny?>('tiltFollowsZoom'.toJS, mapId.toJS, enabled.toJS);
}

void Function() listen(int mapId, void Function() onGesture) {
  final layer = _forMap(mapId);
  if (layer == null) return () {};
  final remove = layer.callMethod<JSFunction>(
    'listen'.toJS,
    mapId.toJS,
    onGesture.toJS,
  );
  return () => remove.callAsFunction();
}

void claim(int mapId) {
  _forMap(mapId)?.callMethod<JSAny?>('claim'.toJS, mapId.toJS);
}

void release(int mapId) {
  final layer = _forMap(mapId);
  if (layer == null || !layer.has('release')) return;
  layer.callMethod<JSAny?>('release'.toJS, mapId.toJS);
}

({
  int live,
  int created,
  int recycled,
  int pooled,
  int released,
  int contextsReleased,
})?
stats() {
  final layer = _layer;
  if (layer == null || !layer.has('stats')) return null;
  final result = layer.callMethod<JSAny?>('stats'.toJS);
  if (result == null || !result.isA<JSObject>()) return null;
  final object = result as JSObject;
  int read(String key) {
    final value = object.getProperty<JSAny?>(key.toJS);
    return value != null && value.isA<JSNumber>()
        ? (value as JSNumber).toDartInt
        : 0;
  }

  return (
    live: read('live'),
    created: read('created'),
    recycled: read('recycled'),
    pooled: read('pooled'),
    released: read('released'),
    contextsReleased: read('contextsReleased'),
  );
}

Future<bool>? flight(
  int mapId,
  double lat,
  double lng,
  double zoom,
  double heading,
  double tilt,
  int ms,
) => _move('flight', mapId, lat, lng, zoom, heading, tilt, ms);

Future<bool>? glide(
  int mapId,
  double lat,
  double lng,
  double zoom,
  double heading,
  double tilt,
  int ms,
) => _move('glide', mapId, lat, lng, zoom, heading, tilt, ms);

/// Runs the layer's [method] (a flight or a glide); null when the layer, or
/// an older cached copy of it without that method, cannot.
Future<bool>? _move(
  String method,
  int mapId,
  double lat,
  double lng,
  double zoom,
  double heading,
  double tilt,
  int ms,
) {
  final layer = _forMap(mapId);
  if (layer == null || !layer.has(method)) return null;
  final promise = layer.callMethodVarArgs<JSAny?>(method.toJS, [
    mapId.toJS,
    lat.toJS,
    lng.toJS,
    zoom.toJS,
    heading.toJS,
    tilt.toJS,
    ms.toJS,
  ]);
  if (promise == null || !promise.isA<JSPromise>()) return null;
  return (promise as JSPromise<JSBoolean>).toDart.then(
    (landed) => landed.toDart,
  );
}

void retarget(
  int mapId,
  double lat,
  double lng,
  double zoom,
  double heading,
  double tilt,
) {
  _forMap(mapId)?.callMethodVarArgs<JSAny?>('retarget'.toJS, [
    mapId.toJS,
    lat.toJS,
    lng.toJS,
    zoom.toJS,
    heading.toJS,
    tilt.toJS,
  ]);
}

({double lat, double lng, double zoom, double heading, double tilt})?
cancelFlight(int mapId) {
  final at = _forMap(
    mapId,
  )?.callMethod<JSAny?>('cancelFlight'.toJS, mapId.toJS);
  if (at == null || !at.isA<JSObject>()) return null;
  final pose = at as JSObject;
  double? read(String key) {
    final value = pose.getProperty<JSAny?>(key.toJS);
    return value != null && value.isA<JSNumber>()
        ? (value as JSNumber).toDartDouble
        : null;
  }

  final lat = read('lat'), lng = read('lng'), zoom = read('zoom');
  if (lat == null || lng == null || zoom == null) return null;
  return (
    lat: lat,
    lng: lng,
    zoom: zoom,
    heading: read('heading') ?? 0,
    tilt: read('tilt') ?? 0,
  );
}
