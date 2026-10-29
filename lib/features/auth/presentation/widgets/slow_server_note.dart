import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// Owner 2026-10-29, decision 1 (contract v0.15.0 `auth.slowStart`): a
/// sleeping server answers its first sign-in call after about 50 s. While
/// [busy] has lasted [showAfter], the line "Starting the server…" says why
/// the rider waits; it goes when the call ends.
class SlowServerNote extends StatefulWidget {
  const SlowServerNote({
    super.key,
    required this.busy,
    this.showAfter = defaultShowAfter,
  });

  /// `contract.json#auth.slowStart.showAfterSeconds`.
  static const defaultShowAfter = Duration(seconds: 5);

  final bool busy;
  final Duration showAfter;

  @override
  State<SlowServerNote> createState() => _SlowServerNoteState();
}

class _SlowServerNoteState extends State<SlowServerNote> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _start();
  }

  @override
  void didUpdateWidget(SlowServerNote old) {
    super.didUpdateWidget(old);
    if (widget.busy && !old.busy) _start();
    if (!widget.busy && old.busy) {
      _timer?.cancel();
      _show = false;
    }
  }

  void _start() {
    _timer?.cancel();
    _show = false;
    _timer = Timer(widget.showAfter, () {
      if (mounted && widget.busy) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('auth-slow-server'),
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AuthColors.muted,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.l10n.startingServer,
                textAlign: TextAlign.center,
                style: AuthText.cardSub(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
