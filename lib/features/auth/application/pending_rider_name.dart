import 'package:movera_rider/core/storage/preferences_store.dart';

/// rider-u74: a new rider whose session exists but who has not given a
/// name yet. Kept on the device (a `movera_` key, so a sign-out wipe drops
/// it), so a reload or a kill on 'What should we call you?' asks again
/// instead of opening Home with no name; the server will not say
/// `isNewRider` a second time.
abstract final class PendingRiderName {
  static const key = 'movera_rider_name_pending';

  /// The name to prefill (an Apple or Google name, else empty).
  static Future<void> mark(String? initialName) async {
    try {
      final prefs = await PreferencesStore.load();
      await prefs.setString(key, initialName?.trim() ?? '');
    } catch (_) {
      // Best effort: without storage the screen still shows this time.
    }
  }

  /// The prefill when a name is still owed; null when none is.
  static Future<String?> read() async {
    try {
      return (await PreferencesStore.load()).getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await (await PreferencesStore.load()).remove(key);
    } catch (_) {
      // Nothing more to do.
    }
  }
}
