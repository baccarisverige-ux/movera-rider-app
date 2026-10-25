import 'dart:async';

/// One camera move: [key] names the framing it produces, so the same
/// framing is not flown twice.
typedef RouteFitPlan = ({String key, Future<void> Function() move});

/// Owner (iPhone PWA): every sheet settle started a new camera flight and
/// tile load, and sliding many times made Safari reload the tab. Settles
/// are debounced, an unchanged framing is skipped and only one flight runs
/// at a time (a request during it runs once after it lands).
class RouteFitScheduler {
  RouteFitScheduler({
    required RouteFitPlan? Function() plan,
    this.settleDelay = const Duration(milliseconds: 300),
    this.flightLimit = const Duration(seconds: 4),
  }) : _plan = plan;

  final RouteFitPlan? Function() _plan;
  final Duration settleDelay;

  /// A flight that never reports back must not block later fits.
  final Duration flightLimit;

  Timer? _settled;
  bool _flying = false;
  bool _again = false;
  bool _againForced = false;
  bool _disposed = false;
  String? _lastKey;

  /// The sheet landed on a stop: fit once it has rested [settleDelay].
  void settled() {
    _settled?.cancel();
    _settled = Timer(settleDelay, () {
      _settled = null;
      unawaited(fit());
    });
  }

  /// Fits now. [force] flies an unchanged framing too (a new map starts
  /// from its own camera).
  Future<void> fit({bool force = false}) async {
    if (_disposed) return;
    if (_flying) {
      _again = true;
      _againForced = _againForced || force;
      return;
    }
    final plan = _plan();
    if (plan == null || (!force && plan.key == _lastKey)) return;
    _lastKey = plan.key;
    _flying = true;
    try {
      await plan.move().timeout(flightLimit, onTimeout: () {});
    } catch (_) {
      // The camera stayed put: the next request flies again.
      _lastKey = null;
    } finally {
      _flying = false;
    }
    if (_again && !_disposed) {
      final forced = _againForced;
      _again = false;
      _againForced = false;
      await fit(force: forced);
    }
  }

  void dispose() {
    _disposed = true;
    _settled?.cancel();
    _settled = null;
  }
}
