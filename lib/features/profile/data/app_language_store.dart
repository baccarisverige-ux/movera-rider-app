import 'package:movera_rider/core/storage/preferences_store.dart';

/// Where the rider's own language choice is kept (owner Q48: it overrides
/// the zone's default). A device setting: Sign in already speaks it.
abstract class AppLanguageStore {
  Future<String?> read();
  Future<void> save(String code);
}

class PrefsAppLanguageStore implements AppLanguageStore {
  const PrefsAppLanguageStore();

  static const key = 'movera_app_language';

  @override
  Future<String?> read() async =>
      (await PreferencesStore.load()).getString(key);

  @override
  Future<void> save(String code) async =>
      (await PreferencesStore.load()).setString(key, code);
}

class MemoryAppLanguageStore implements AppLanguageStore {
  MemoryAppLanguageStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String code) async => value = code;
}
