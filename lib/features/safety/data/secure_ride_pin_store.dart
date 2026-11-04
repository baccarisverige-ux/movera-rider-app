import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// Keeps the ride-verification PIN digits out of the plaintext
/// SharedPreferences safety cache.
///
/// - iOS/Android: Keychain / Keystore (mirrors core/auth/secure_token_store).
/// - Web (Batch 9 Phase 107, P-06): memory only. Browser storage is readable
///   by any script on the origin and persists across sessions, so the digits
///   are never written there. SafetyStore.load() already refuses to display
///   a cached PIN and re-fetches it from `/api/v1/safety/pin`, so losing the
///   in-memory copy on reload costs nothing but that fetch.
/// - Desktop / tests: unchanged no-op; the PIN stays in the caller's cache.
class SecureRidePinStore {
  const SecureRidePinStore()
    : _forceNativeSecure = null,
      _fakeStorage = null,
      _forceWeb = null;

  /// Test-only: exercises the same scrub/restore logic against an in-memory
  /// map instead of the real Keychain/Keystore plugin, which has no
  /// platform-channel handler under `flutter test` and hangs rather than
  /// failing fast.
  @visibleForTesting
  SecureRidePinStore.fake()
    : _forceNativeSecure = true,
      _fakeStorage = <String, String>{},
      _forceWeb = false;

  /// Test-only: behaves as the web build does (memory-only PIN).
  @visibleForTesting
  const SecureRidePinStore.web()
    : _forceNativeSecure = false,
      _fakeStorage = null,
      _forceWeb = true;

  static const _key = 'movera_ride_pin';
  final bool? _forceNativeSecure;
  final Map<String, String>? _fakeStorage;
  final bool? _forceWeb;

  /// Web PIN holder: lives for the page session only, never persisted.
  static final Map<String, String> _webMemory = <String, String>{};

  @visibleForTesting
  static void debugResetWebMemory() => _webMemory.clear();

  bool get _nativeSecure {
    if (_forceNativeSecure != null) return _forceNativeSecure;
    if (kIsWeb) return false;
    try {
      WidgetsBinding.instance;
    } catch (_) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool get isNativeSecure => _nativeSecure;

  bool get _webMemoryOnly => !_nativeSecure && (_forceWeb ?? kIsWeb);

  /// Whether the PIN digits are held outside the plaintext prefs cache
  /// (native secure storage, or memory on web). When true, callers must
  /// persist only a placeholder in that cache.
  bool get keepsPinOutOfPreferences => _nativeSecure || _webMemoryOnly;

  Future<String?> read() async {
    if (_webMemoryOnly) return _webMemory[_key];
    if (!_nativeSecure) return null;
    final fake = _fakeStorage;
    if (fake != null) return fake[_key];
    try {
      return await const FlutterSecureStorage(
        aOptions: // B9 (v10): data kept by the old EncryptedSharedPreferences
            // setting is moved to v10 storage on first read, so a signed-in
            // rider stays signed in.
            AndroidOptions(migrateOnAlgorithmChange: true),
      ).read(key: _key);
    } catch (_) {
      return null;
    }
  }

  /// Removes the PIN (end of a rider's session).
  Future<void> clear() async {
    _webMemory.remove(_key);
    if (!_nativeSecure) return;
    final fake = _fakeStorage;
    if (fake != null) {
      fake.remove(_key);
      return;
    }
    try {
      await const FlutterSecureStorage(
        aOptions: // B9 (v10): data kept by the old EncryptedSharedPreferences
            // setting is moved to v10 storage on first read, so a signed-in
            // rider stays signed in.
            AndroidOptions(migrateOnAlgorithmChange: true),
      ).delete(key: _key);
    } catch (error) {
      AppLog.warning('safety.pin_delete_failed', extra: {'error': '$error'});
    }
  }

  Future<void> write(String pin) async {
    if (_webMemoryOnly) {
      _webMemory[_key] = pin;
      return;
    }
    if (!_nativeSecure) return;
    final fake = _fakeStorage;
    if (fake != null) {
      fake[_key] = pin;
      return;
    }
    try {
      await const FlutterSecureStorage(
        aOptions: // B9 (v10): data kept by the old EncryptedSharedPreferences
            // setting is moved to v10 storage on first read, so a signed-in
            // rider stays signed in.
            AndroidOptions(migrateOnAlgorithmChange: true),
      ).write(key: _key, value: pin);
    } catch (error) {
      AppLog.warning('safety.pin_write_failed', extra: {'error': '$error'});
    }
  }
}
