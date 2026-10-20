bool? supports3D(int mapId) => true;
void gestures(int mapId, bool scroll, bool zoom, bool rotate, bool tilt) {}
void tiltFollowsZoom(int mapId, bool enabled) {}
void Function() listen(int mapId, void Function() onGesture) => () {};
void claim(int mapId) {}
