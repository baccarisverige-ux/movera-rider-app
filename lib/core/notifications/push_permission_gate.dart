import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the rider said about ride-update notifications.
enum PushConsent {
  /// Never asked: the in-app explanation has not been shown yet.
  unknown,

  /// Accepted the explanation; the OS prompt may run and push registers.
  accepted,

  /// Chose "Not now" in the explanation. The OS prompt never ran.
  declined,

  /// Accepted, but the OS permission is refused; only Settings can fix it.
  blockedBySystem,
}

enum PushOptInResult { registered, blockedBySystem, failed }

/// Keeps the OS notification prompt behind an in-app explanation (UI-17,
/// FLOW-19).
///
/// Sign-in and session restore call [registerIfConsented], which never
/// shows the OS prompt to a rider who has not accepted the explanation.
/// [accept] runs from the explanation's "Turn on" button and records a
/// system refusal so the app can offer Settings instead of asking again.
class PushPermissionGate {
  PushPermissionGate({required PushService push, required this.enabled})
    : _push = push;

  final PushService _push;

  /// False where push is a mock (demo/dev/test): nothing is offered.
  final bool enabled;

  static const String storageKey = 'movera.push_consent.v1';

  Future<PushConsent> consent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(storageKey);
      return PushConsent.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => PushConsent.unknown,
      );
    } catch (_) {
      return PushConsent.unknown;
    }
  }

  Future<void> _store(PushConsent value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, value.name);
    } catch (error) {
      AppLog.warning('push.consent_store_failed', extra: {'error': '$error'});
    }
  }

  /// Whether the explanation should be shown now.
  Future<bool> shouldOffer() async =>
      enabled && await consent() == PushConsent.unknown;

  /// Registers push only for a rider who accepted the explanation before.
  /// Never shows the OS prompt to anyone else.
  ///
  /// rider-r4-40: a rider whose OS refused is asked again here too. They
  /// accepted the explanation, the OS answers with the current setting
  /// (iOS never prompts twice), and a rider who has since allowed
  /// notifications in Settings registers and is back to accepted.
  Future<void> registerIfConsented({required String logEvent}) async {
    if (!enabled) {
      // Mock transport: registering is a no-op that never prompts.
      await _register(logEvent);
      return;
    }
    final current = await consent();
    if (current != PushConsent.accepted &&
        current != PushConsent.blockedBySystem) {
      return;
    }
    await _register(logEvent);
  }

  Future<PushOptInResult> _register(String logEvent) async {
    try {
      await _push.register();
      if (enabled && await consent() == PushConsent.blockedBySystem) {
        await _store(PushConsent.accepted);
      }
      return PushOptInResult.registered;
    } on PushPermissionDeniedException {
      await _store(PushConsent.blockedBySystem);
      AppLog.warning(logEvent, extra: const {'reason': 'permission_denied'});
      return PushOptInResult.blockedBySystem;
    } catch (error) {
      AppLog.warning(logEvent, extra: {'error': error.runtimeType.toString()});
      return PushOptInResult.failed;
    }
  }

  /// "Turn on notifications" in the explanation (or "Try again" after the
  /// rider changed Settings): records consent, then shows the OS prompt.
  Future<PushOptInResult> accept() async {
    await _store(PushConsent.accepted);
    return _register('push.opt_in_failed');
  }

  /// "Not now" in the explanation.
  Future<void> decline() => _store(PushConsent.declined);
}
