import 'package:movera_rider/core/storage/preferences_store.dart';

/// Shared default-payment brand (`apple`, `cash`, …).
///
/// Wallet already used this key. Ride selection and the payment repository
/// now read/write the same slot so the choice survives relaunch (R10).
abstract class DefaultPaymentStore {
  Future<String?> read();
  Future<void> save(String brand);
}

class PrefsDefaultPaymentStore implements DefaultPaymentStore {
  const PrefsDefaultPaymentStore();

  static const key = 'movera_default_payment';

  @override
  Future<String?> read() async {
    final prefs = await PreferencesStore.load();
    return prefs.getString(key);
  }

  @override
  Future<void> save(String brand) async {
    final prefs = await PreferencesStore.load();
    await prefs.setString(key, brand);
  }
}

class MemoryDefaultPaymentStore implements DefaultPaymentStore {
  MemoryDefaultPaymentStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String brand) async {
    value = brand;
  }
}
