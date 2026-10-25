import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/auth/web_session_token_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// iOS Keychain / Android Keystore via flutter_secure_storage.
/// Web: this tab's sessionStorage (see [webSessionTokenStore]) so a reload
/// keeps the session; not equivalent to Keychain/Keystore.
/// Tests and Linux CI: memory only.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({TokenStore? override}) : _override = override;

  final TokenStore? _override;
  final MemoryTokenStore _memory = MemoryTokenStore();
  late final TokenStore? _web = kIsWeb ? webSessionTokenStore() : null;
  /// One entry holding both tokens as JSON (native).
  static const sessionKey = 'movera_session';

  /// Two-key format of older builds; still read, deleted on the next save.
  static const accessKey = 'movera_access_token';
  static const refreshKey = 'movera_refresh_token';

  bool get _nativeSecure {
    if (kIsWeb) return false;
    try {
      WidgetsBinding.instance;
    } catch (_) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  TokenStore get _active {
    final override = _override;
    if (override != null) return override;
    final web = _web;
    if (web != null) return web;
    if (!_nativeSecure) return _memory;
    return NativeSecureTokenStore(
      const _FlutterSecureKeyValue(
        FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        ),
      ),
    );
  }

  @override
  Future<void> save({required String access, required String refresh}) async {
    if (kIsWeb) {
      AppLog.info(
        'auth.token.web',
        extra: {'note': 'web storage is not Keychain/Keystore'},
      );
    }
    try {
      await _active.save(access: access, refresh: refresh);
    } catch (error, stackTrace) {
      AppLog.error('auth.token.secure_save_failed', error: error, stackTrace: stackTrace);
      await _memory.save(access: access, refresh: refresh);
    }
  }

  @override
  Future<String?> readAccess() async {
    try {
      return await _active.readAccess();
    } catch (error, stackTrace) {
      AppLog.error('auth.token.secure_read_access_failed', error: error, stackTrace: stackTrace);
      return _memory.readAccess();
    }
  }

  @override
  Future<String?> readRefresh() async {
    try {
      return await _active.readRefresh();
    } catch (error, stackTrace) {
      AppLog.error('auth.token.secure_read_refresh_failed', error: error, stackTrace: stackTrace);
      return _memory.readRefresh();
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _active.clear();
    } catch (error, stackTrace) {
      AppLog.error('auth.token.secure_clear_failed', error: error, stackTrace: stackTrace);
      await _memory.clear();
    }
  }
}

/// The few calls [NativeSecureTokenStore] makes on Keychain/Keystore.
abstract class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterSecureKeyValue implements SecureKeyValue {
  const _FlutterSecureKeyValue(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Both tokens live in one entry ([SecureTokenStore.sessionKey]), so a kill
/// between two writes can no longer pair a new access token with the
/// refresh token the server just rotated away. Sessions saved by older
/// builds under two keys are still read; the next save moves them over.
/// Reads never write, so a read racing a rotation cannot put old tokens
/// back.
class NativeSecureTokenStore implements TokenStore {
  NativeSecureTokenStore(this._storage);
  final SecureKeyValue _storage;

  @override
  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(
      SecureTokenStore.sessionKey,
      jsonEncode({'access': access, 'refresh': refresh}),
    );
    await _dropLegacy();
  }

  @override
  Future<String?> readAccess() async => (await _read())?.access;

  @override
  Future<String?> readRefresh() async => (await _read())?.refresh;

  @override
  Future<void> clear() async {
    await _storage.delete(SecureTokenStore.sessionKey);
    await _dropLegacy();
  }

  Future<({String access, String refresh})?> _read() async {
    final raw = await _storage.read(SecureTokenStore.sessionKey);
    if (raw != null) return _decode(raw);
    final access = await _storage.read(SecureTokenStore.accessKey);
    final refresh = await _storage.read(SecureTokenStore.refreshKey);
    if (access != null && refresh != null) {
      return (access: access, refresh: refresh);
    }
    // A save may have moved the old pair over between the reads above.
    final moved = await _storage.read(SecureTokenStore.sessionKey);
    return moved == null ? null : _decode(moved);
  }

  static ({String access, String refresh})? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded['access'] is String &&
          decoded['refresh'] is String) {
        return (
          access: decoded['access'] as String,
          refresh: decoded['refresh'] as String,
        );
      }
    } on FormatException {
      // Unreadable entry: treated as no session, like a missing one.
    }
    return null;
  }

  Future<void> _dropLegacy() async {
    await _storage.delete(SecureTokenStore.accessKey);
    await _storage.delete(SecureTokenStore.refreshKey);
  }
}
