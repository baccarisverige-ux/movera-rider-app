import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/sound/app_tones.dart';
import 'package:movera_rider/features/calls/domain/trip_call_session.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.38 §62 (fix job 8, owner G15 2026-11-05 "In-app calls only",
/// "Just 'Call failed'"): the in-app call with the driver. Calling… →
/// In call (mute, speaker, end); an incoming call shows Answer / Decline.
/// A failure shows only "Call failed" and the screen closes; when the
/// connect time limit ran out, a hint under it (v0.18.66 §87). An incoming
/// call rings (Movera's `call_ring.wav`, looped) until it is answered,
/// declined, missed or failed.
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

  CallRingtone? _ring;

  TripCallSession get _s => widget.session;

  bool get _ringing => _s.state == TripCallState.ringing && !_s.over;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    if (!_s.outgoingCall) _ring = CallRingtone()..update(_ringing);
    // 2026-11-11 owner phone test: a screen opened on a call that was
    // already over (missed / ended before the screen came up) never got a
    // change and stayed forever with grey buttons. Close it as well.
    if (_s.over) _scheduleClose();
  }

  void _scheduleClose() {
    if (_close != null) return;
    _tick?.cancel();
    _close = Timer(const Duration(seconds: 2), _leave);
  }

  /// Leaves the call screen (back to the trip). A call still going on is
  /// hung up in [dispose], or declined while it still rings.
  void _leave() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _hangUpAndLeave() async {
    await _s.hangUp();
    _leave();
  }

  void _changed() {
    _ring?.update(_ringing);
    if (!mounted) return;
    if (_s.state == TripCallState.connected && _since == null) {
      _since = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (_s.over) _scheduleClose();
    setState(() {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _ring?.dispose();
    _close?.cancel();
    _tick?.cancel();
    // Leaving the screen (back) hangs up a call still going on; a driver's
    // call still ringing is declined (admin "how it ended"; driver G27).
    if (!_s.over) unawaited(_ringing ? _s.decline() : _s.hangUp());
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

  Widget _buttons() {
    final ringing = _s.state == TripCallState.ringing && !_s.over;
    final children = ringing
        ? [
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
          ]
        : [
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
              onTap: _s.over ? null : _hangUpAndLeave,
            ),
            _round(
              key: const ValueKey<String>('call-speaker'),
              icon: Icons.volume_up,
              label: L10n.current.callSpeaker,
              on: _s.speaker,
              onTap: _s.over ? null : _s.toggleSpeaker,
            ),
          ];
    // 2026-11-11 owner phone test (tablet, landscape): the third button was
    // cut off at the right edge. The buttons sit close together in the
    // middle and wrap to a new line when the screen is too narrow.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 40,
      runSpacing: 16,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final short = box.maxHeight < 520;
            return Stack(
              children: [
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: box.maxHeight,
                      minWidth: box.maxWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        short ? 56 : 72,
                        24,
                        short ? 16 : 40,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              CircleAvatar(
                                radius: short ? 32 : 44,
                                backgroundColor: const Color(0xFF2B2B2B),
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: short ? 36 : 48,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (widget.name != null)
                                Text(
                                  widget.name!,
                                  textAlign: TextAlign.center,
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
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _s.state == TripCallState.failed
                                      ? const Color(0xFFFF6B6B)
                                      : Colors.white70,
                                  fontSize: 17,
                                ),
                              ),
                              // v0.18.66 §87 (owner 2026-11-11 "Add hint"):
                              // only when the connect time limit ran out.
                              if (_s.state == TripCallState.failed &&
                                  _s.connectTimedOut) ...[
                                const SizedBox(height: 8),
                                Text(
                                  L10n.current.callConnectFailedHint,
                                  key: const ValueKey<String>(
                                    'call-failed-hint',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: short ? 24 : 48),
                          _buttons(),
                        ],
                      ),
                    ),
                  ),
                ),
                // Always a way out: back to the trip. A call still going
                // on is hung up when the screen goes (see dispose).
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    key: const ValueKey<String>('call-close'),
                    tooltip: L10n.current.close,
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _leave,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
