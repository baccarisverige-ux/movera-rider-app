import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Compact transport-status surface for ride-critical screens.
///
/// It never changes ride state and offers no fake retry outcome. It only
/// reflects the shared realtime connection source so the future backend can
/// drive the same UI without changing presentation code.
///
/// The connection tells its listeners at once (a sync stream), and a screen
/// that opens starts following its trip in `initState`, which is inside a
/// build. A change that arrives while the tree builds is therefore shown
/// right after that frame: marking this banner dirty during another
/// widget's build is a framework error ("setState() called during build").
class RealtimeConnectionBanner extends StatefulWidget {
  const RealtimeConnectionBanner({
    super.key,
    required this.connection,
    this.hidden,
  });

  final RealtimeConnection connection;

  /// Read on every connection change: true when the screen no longer
  /// follows a trip (a committed cancel lets the transport go, which is no
  /// lost connection to tell the rider about).
  final bool Function()? hidden;

  @override
  State<RealtimeConnectionBanner> createState() =>
      _RealtimeConnectionBannerState();
}

class _RealtimeConnectionBannerState extends State<RealtimeConnectionBanner> {
  StreamSubscription<RealtimeState>? _changes;

  /// A change came while the tree was building; one rebuild is queued.
  bool _rebuildQueued = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.connection.states.listen(_onChange);
  }

  @override
  void didUpdateWidget(RealtimeConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.connection, widget.connection)) return;
    unawaited(_changes?.cancel());
    _changes = widget.connection.states.listen(_onChange);
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  void _onChange(RealtimeState _) {
    if (!mounted) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    // Build, layout or paint is running (a screen's initState subscribed
    // to its trip): rebuild once that frame is done.
    if (_rebuildQueued) return;
    _rebuildQueued = true;
    scheduler.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always the connection's own state: nothing is copied or delayed here.
    final state = widget.connection.state;
    final spec = (widget.hidden?.call() ?? false) ? null : _spec(state);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: spec == null
          ? const SizedBox.shrink(key: ValueKey('realtime-connected'))
          : Semantics(
              key: ValueKey('realtime-${state.name}'),
              liveRegion: true,
              label: spec.semantics,
              // rider-j8-16: the label above says it once.
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xF71D252C),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F162C36),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(spec.icon, size: 18, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                spec.title,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                spec.subtitle,
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFFD9E0E4),
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state == RealtimeState.connecting ||
                            state == RealtimeState.reconnecting) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  _ConnectionSpec? _spec(RealtimeState state) {
    switch (state) {
      case RealtimeState.connected:
        return null;
      case RealtimeState.connecting:
        return _ConnectionSpec(
          icon: Icons.sync_rounded,
          title: L10n.current.rtConnecting,
          subtitle: L10n.current.rtConnectingBody,
          semantics:
              '${L10n.current.rtConnecting}. ${L10n.current.rtConnectingBody}',
        );
      case RealtimeState.reconnecting:
        return _ConnectionSpec(
          icon: Icons.sync_rounded,
          title: L10n.current.rtReconnecting,
          subtitle: L10n.current.rtReconnectingBody,
          semantics:
              '${L10n.current.rtReconnecting}. ${L10n.current.rtReconnectingBody}',
        );
      case RealtimeState.disconnected:
        return _ConnectionSpec(
          icon: Icons.wifi_off_rounded,
          title: L10n.current.rtLost,
          subtitle: L10n.current.rtLostBody,
          semantics: '${L10n.current.rtLost}. ${L10n.current.rtLostBody}',
        );
      case RealtimeState.failed:
        return _ConnectionSpec(
          icon: Icons.cloud_off_outlined,
          title: L10n.current.rtProblem,
          subtitle: L10n.current.rtProblemBody,
          semantics: '${L10n.current.rtProblem}. ${L10n.current.rtProblemBody}',
        );
    }
  }
}

class _ConnectionSpec {
  const _ConnectionSpec({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semantics,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String semantics;
}
