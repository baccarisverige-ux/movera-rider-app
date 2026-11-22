import 'package:movera_rider/features/safety/domain/sos_not_sent_flag.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SosNotSentFlag] kept in the phone's preferences. The key is not a
/// `movera_` key, so a sign-out wipe keeps it (contract v0.18.148: a kept
/// SOS given up on at sign-out is still told after it).
class PrefsSosNotSentFlag implements SosNotSentFlag {
  const PrefsSosNotSentFlag();

  static const prefKey = 'sos_not_sent_notice_v1';

  @override
  Future<void> keep() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, true);
    } catch (_) {
      // No storage: the notice is still shown now, only not after a restart.
    }
  }

  @override
  Future<bool> kept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> forget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefKey);
    } catch (_) {
      // No storage: nothing was kept, so nothing is shown again.
    }
  }
}
