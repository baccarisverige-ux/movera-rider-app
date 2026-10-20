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

bool? supports3D(int mapId) => _forMap(mapId)
    ?.callMethod<JSBoolean?>('supports3D'.toJS, mapId.toJS)
    ?.toDart;

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
  _forMap(mapId)?.callMethod<JSAny?>(
    'tiltFollowsZoom'.toJS,
    mapId.toJS,
    enabled.toJS,
  );
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
