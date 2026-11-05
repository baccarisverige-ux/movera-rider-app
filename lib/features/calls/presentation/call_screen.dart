import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.38 §62 (fix job 8, owner G15 2026-11-05 "In-app calls only",
/// "Just 'Call failed'"): the in-app call with the driver. Calling… →
/// In call (mute, speaker, end); an incoming call shows Answer / Decline.
/// A failure shows only "Call failed" and the screen closes.
class TripCallScreen extends StatefulWidget {
  const TripCallScreen({super.key, required this.session, this.name});

  final TripCallSession session;

  /// A button that can no longer be used (the call is over or failed).
  static const Color disabledColor = Color(0xFF3A3A3A);

  /// The driver's first name, when known.
  final String? name;

  /// Opens the screen over [context]'s navigator.
  static Future<void> open(
    BuildContext context,
    TripCallSession session, {
    String? name,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => TripCallScreen(session: session, name: name),
    ),
  );

  @override
  State<TripCallScreen> createState() => _TripCallScreenState();
}

class _TripCallScreenState extends State<TripCallScreen> {
  Timer? _close;
  Timer? _tick;
  DateTime? _since;

  TripCallSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_s.state == TripCallState.connected && _since == null) {
      _since = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (_s.over && _close == null) {
      _tick?.cancel();
      _close = Timer(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _close?.cancel();
    _tick?.cancel();
    // Leaving the screen (back) hangs up a call still going on.
    if (!_s.over) unawaited(_s.hangUp());
    super.dispose();
  }

  String get _line => switch (_s.state) {
    TripCallState.calling => L10n.current.callCalling,
    TripCallState.ringing => L10n.current.callIncomingFromDriver,
    TripCallState.connecting => L10n.current.callConnecting,
    TripCallState.connected => _clock(),
    TripCallState.ended => L10n.current.callEnded,
    TripCallState.failed => L10n.current.callFailed,
  };

  String _clock() {
    final since = _since;
    if (since == null) return L10n.current.callConnected;
    final s = DateTime.now().difference(since).inSeconds;
    return '${L10n.current.callConnected} · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _round({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = const Color(0xFF2B2B2B),
    bool on = false,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: onTap == null
            ? TripCallScreen.disabledColor
            : (on ? Colors.white : color),
        shape: const CircleBorder(),
        child: IconButton(
          key: key,
          iconSize: 30,
          padding: const EdgeInsets.all(18),
          tooltip: label,
          icon: Icon(
            icon,
            color: onTap == null
                ? Colors.white38
                : (on ? Colors.black : Colors.white),
          ),
          onPressed: onTap,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        style: TextStyle(
          color: onTap == null ? Colors.white38 : Colors.white70,
          fontSize: 13,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final ringing = _s.state == TripCallState.ringing;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const CircleAvatar(
              radius: 44,
              backgroundColor: Color(0xFF2B2B2B),
              child: Icon(Icons.person, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 16),
            if (widget.name != null)
              Text(
                widget.name!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _line,
              key: const ValueKey<String>('call-state'),
              style: TextStyle(
                color: _s.state == TripCallState.failed
                    ? const Color(0xFFFF6B6B)
                    : Colors.white70,
                fontSize: 17,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: ringing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _round(
                          key: const ValueKey<String>('call-decline'),
                          icon: Icons.call_end,
                          label: L10n.current.callDecline,
                          color: const Color(0xFFE53935),
                          onTap: _s.decline,
                        ),
                        _round(
                          key: const ValueKey<String>('call-answer'),
                          icon: Icons.call,
                          label: L10n.current.callAnswer,
                          color: const Color(0xFF2E7D32),
                          onTap: _s.answer,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _round(
                          key: const ValueKey<String>('call-mute'),
                          icon: _s.muted ? Icons.mic_off : Icons.mic,
                          label: L10n.current.callMute,
                          on: _s.muted,
                          onTap: _s.over ? null : _s.toggleMute,
                        ),
                        _round(
                          key: const ValueKey<String>('call-end'),
                          icon: Icons.call_end,
                          label: L10n.current.callEnd,
                          color: const Color(0xFFE53935),
                          onTap: _s.over ? null : _s.hangUp,
                        ),
                        _round(
                          key: const ValueKey<String>('call-speaker'),
                          icon: Icons.volume_up,
                          label: L10n.current.callSpeaker,
                          on: _s.speaker,
                          onTap: _s.over ? null : _s.toggleSpeaker,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
