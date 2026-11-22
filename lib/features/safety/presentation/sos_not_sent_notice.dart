import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/features/safety/domain/sos_not_sent_flag.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.148 (`sosPressTime.apps`; owner 2026-11-20 "after 30 min or
/// any refusal ... SOS not sent, call 112"): a kept SOS that was given up on
/// (refused, too old, signed out) is told to the rider in a dialog that stays
/// until Close. The flag is kept on the phone (not a `movera_` key, so a
/// sign-out wipe keeps it), so a locked phone, the background or a restart
/// still shows it on the next resume or start. Texts: `sosNotSent` (new,
/// owner to confirm: the driver app's approved words) and `close`.
class SosNotSentNotice with WidgetsBindingObserver {
  SosNotSentNotice._();

  static final SosNotSentNotice instance = SosNotSentNotice._();

  /// Where the notice is kept across a restart (the data layer's store,
  /// given by the app's start-up); null: shown now only.
  SosNotSentFlag? flag;

  /// Where the dialog opens (the app's navigator); null: none yet.
  BuildContext? Function()? context;

  bool _open = false;
  bool _observing = false;
  bool _raisedWhileOpen = false;

  /// Starts showing a kept notice on each resume.
  void attach(BuildContext? Function() where, {SosNotSentFlag? flag}) {
    context = where;
    if (flag != null) this.flag = flag;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    unawaited(showIfPending());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(showIfPending());
  }

  /// An SOS was given up on: kept, then shown.
  Future<void> raise() async {
    if (_open) _raisedWhileOpen = true;
    await flag?.keep();
    await showIfPending(force: true);
  }

  Future<bool> pending() async => await flag?.kept() ?? false;

  Future<void> showIfPending({bool force = false}) async {
    if (_open) return;
    _open = true;
    var again = false;
    try {
      if (!force && !await pending()) return;
      final where = context?.call();
      if (where == null || !where.mounted) return;
      _raisedWhileOpen = false;
      try {
        await showDialog<void>(
          context: where,
          barrierDismissible: false,
          builder: (dialog) => AlertDialog(
            key: const ValueKey('sos-not-sent-notice'),
            content: Text(L10n.current.sosNotSent),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: Text(L10n.current.close),
              ),
            ],
          ),
        );
      } catch (_) {
        // Not shown (no navigator now): kept for the next resume.
        return;
      }
      again = _raisedWhileOpen;
      _raisedWhileOpen = false;
      if (!again) await flag?.forget();
    } finally {
      _open = false;
    }
    if (again) await showIfPending(force: true);
  }

  @visibleForTesting
  void resetForTesting() {
    _open = false;
    _raisedWhileOpen = false;
    context = null;
    flag = null;
  }
}
