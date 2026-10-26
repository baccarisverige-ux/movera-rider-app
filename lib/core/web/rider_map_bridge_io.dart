bool? supports3D(int mapId) => true;
void gestures(int mapId, bool scroll, bool zoom, bool rotate, bool tilt) {}
void tiltFollowsZoom(int mapId, bool enabled) {}
void Function() listen(int mapId, void Function() onGesture) => () {};
void claim(int mapId) {}
void release(int mapId) {}
({int live, int created, int recycled, int pooled, int released, int contextsReleased})?
    stats() => null;
Future<bool>? flight(int mapId, double lat, double lng, double zoom,
        double heading, double tilt, int ms) =>
    null;
Future<bool>? glide(int mapId, double lat, double lng, double zoom,
        double heading, double tilt, int ms) =>
    null;
void retarget(int mapId, double lat, double lng, double zoom, double heading,
    double tilt) {}
/// No web layer: nothing was flying.
({double lat, double lng, double zoom, double heading, double tilt})?
    cancelFlight(int mapId) => null;
