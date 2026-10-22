import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';

/// rider-u17: the iOS Keychain keeps the access and refresh tokens (and the
/// ride PIN) after the app is uninstalled, while SharedPreferences goes with
/// the app. Without this, the first launch of a new install found the
/// previous owner's session and opened Home as that rider.
///
/// A marker in SharedPreferences records that this install has started
/// once. When it is missing and no other `movera_` preference exists either,
/// this is a new install: the secure-storage session and PIN are left over
/// from an earlier one and are cleared before anything reads them. An
/// update from a version without the marker still has its preferences
/// (onboarding, the rider fingerprint, ...), so its rider stays signed in.
abstract final class FreshInstallReset {
  static const markerKey = 'movera_install_seen';

  /// Returns true when it cleared a leftover session.
  static Future<bool> run({
    required TokenStore tokens,
    SecureRidePinStore pin = const SecureRidePinStore(),
  }) async {
    try {
      final prefs = await PreferencesStore.load();
      if (prefs.getBool(markerKey) == true) return false;
      final earlierInstall = prefs.getKeys().any(
        (key) => key.startsWith('movera_'),
      );
      if (!earlierInstall) {
        await tokens.clear();
        await pin.clear();
        AppLog.info('auth.fresh_install_reset');
      }
      await prefs.setBool(markerKey, true);
      return !earlierInstall;
    } catch (error) {
      AppLog.warning(
        'auth.fresh_install_reset_failed',
        extra: {'error': '$error'},
      );
      return false;
    }
  }
}
