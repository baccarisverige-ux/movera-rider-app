enum MapLifecycle { idle, created, parked, disposed }

class MapLifecycleController {
  MapLifecycle state = MapLifecycle.idle;

  void created() => state = MapLifecycle.created;

  void park() => state = MapLifecycle.parked;

  void resume() {
    if (state == MapLifecycle.parked) state = MapLifecycle.created;
  }

  void dispose() => state = MapLifecycle.disposed;

  bool get isLive => state == MapLifecycle.created;
}

/// Re-entrant guard for map-heavy route handoffs.
///
/// Nested flows (for example Home -> pickup confirmation -> Select Ride) must
/// park the platform map once at the outer boundary and resume it once after
/// the entire nested flow returns.
class MapParkingGuard {
  int _depth = 0;

  int get depth => _depth;
  bool get isParked => _depth > 0;

  /// Returns true only for the outermost park boundary.
  bool enter() {
    _depth += 1;
    return _depth == 1;
  }

  /// Returns true only when the outermost parked flow has fully returned.
  bool exit() {
    if (_depth == 0) return false;
    _depth -= 1;
    return _depth == 0;
  }
}
