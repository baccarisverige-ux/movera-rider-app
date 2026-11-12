import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A ride-stage map that a covering screen "parks".
///
/// G25 step A (BrowserStack screen-switch G-S1/G-S5, 2026-11-12): parking
/// used to swap the map for [placeholder], which destroyed the Google map
/// (a new Android SurfaceView on the way back: a plain flash, then a camera
/// jump). On native the map now stays mounted while [parked]: the last
/// [child] is kept as it was (no marker, polyline or camera updates reach
/// it) and its tickers are muted. The screen still detaches its map owner
/// when it parks, so no camera command moves the hidden map. Back on top,
/// [onResumed] runs once after the frame so the screen can take its map
/// back (attach the owner again, repaint).
///
/// The web keeps its own parking (every map lives on in the plugin's
/// registry, and the pool reuses them): there [placeholder] replaces the
/// map as before and a new map attaches itself when it is created.
class ParkableMap extends StatefulWidget {
  const ParkableMap({
    super.key,
    required this.parked,
    required this.placeholder,
    required this.child,
    this.onResumed,
  });

  final bool parked;
  final Widget placeholder;
  final Widget child;

  /// A kept map is shown again (native only; never after a new map).
  final VoidCallback? onResumed;

  /// Tests: overrides whether a parked map stays mounted (default: not on
  /// the web).
  @visibleForTesting
  static bool? debugKeepWhileParked;

  /// Whether a parked map stays mounted on this platform.
  static bool get keepsMapWhileParked => debugKeepWhileParked ?? !kIsWeb;

  @override
  State<ParkableMap> createState() => _ParkableMapState();
}

class _ParkableMapState extends State<ParkableMap> {
  /// The map as it was when parked; null while none is kept.
  Widget? _kept;

  @override
  void didUpdateWidget(ParkableMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parked && !widget.parked && _kept != null) {
      _kept = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.parked) widget.onResumed?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.parked) {
      return TickerMode(enabled: true, child: widget.child);
    }
    if (!ParkableMap.keepsMapWhileParked) {
      _kept = null;
      return widget.placeholder;
    }
    // The identical widget: Flutter skips the subtree, so the hidden map
    // gets no updates while it is covered.
    final kept = _kept ??= widget.child;
    return TickerMode(enabled: false, child: kept);
  }
}
