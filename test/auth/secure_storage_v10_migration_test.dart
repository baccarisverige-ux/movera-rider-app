import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// B9 (owner 2026-11-04, "Yes, both apps" for wasm): flutter_secure_storage
/// 9 -> 10. Riders signed in on Android before the upgrade kept their tokens
/// in EncryptedSharedPreferences; v10 moves them to its own storage on first
/// read only while migrateOnAlgorithmChange is on. Web tokens never used
/// this package (webSessionTokenStore, localStorage), iOS keeps the Keychain.
void main() {
  test('the v10 options really carry the migration flag', () {
    const options = AndroidOptions(migrateOnAlgorithmChange: true);
    expect(options.toMap()['migrateOnAlgorithmChange'], 'true');
  });
}
