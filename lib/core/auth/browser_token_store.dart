import 'package:movera_rider/core/auth/token_store.dart';

/// The calls [BrowserTokenStore] makes on a browser Storage
/// (`window.localStorage` or `window.sessionStorage`). Plain Dart, so the
/// store's rules run under `flutter test`.
abstract class BrowserStorage {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
}

/// The web sign-in, kept in [persistent] (localStorage) so it survives
/// closing the tab or the Home-screen app. Why: see
/// `web_session_token_store.dart`.
///
/// Builds before 2026-10-26 kept the same two keys in [legacy]
/// (sessionStorage). A session found only there is moved over on the first
/// read, so a rider signed in before the update stays signed in. [clear]
/// (sign-out, session expiry) removes the keys from both.
class BrowserTokenStore implements TokenStore {
  BrowserTokenStore({required this.persistent, required this.legacy});

  final BrowserStorage persistent;
  final BrowserStorage legacy;

  static const accessKey = 'movera_access_token';
  static const refreshKey = 'movera_refresh_token';
  static const _keys = [accessKey, refreshKey];

  @override
  Future<void> save({required String access, required String refresh}) async {
    try {
      persistent.setItem(accessKey, access);
      persistent.setItem(refreshKey, refresh);
    } catch (_) {
      // localStorage refused the write (a full origin, Private Browsing on
      // older iOS): keep the session for this tab, as builds before did,
      // rather than lose it on the next read.
      _tryDrop(persistent);
      legacy.setItem(accessKey, access);
      legacy.setItem(refreshKey, refresh);
      return;
    }
    _tryDrop(legacy);
  }

  @override
  Future<String?> readAccess() async => _source().getItem(accessKey);

  @override
  Future<String?> readRefresh() async => _source().getItem(refreshKey);

  @override
  Future<void> clear() async {
    // Both storages are tried even when one throws, so sign-out never
    // leaves a copy behind; the first failure is then reported.
    Object? failure;
    StackTrace? trace;
    for (final storage in [persistent, legacy]) {
      try {
        _drop(storage);
      } catch (error, stackTrace) {
        failure ??= error;
        trace ??= stackTrace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }

  /// Where the session lives now. localStorage wins whenever it holds one;
  /// a copy left in sessionStorage is then stale and removed.
  BrowserStorage _source() {
    if (_holdsSession(persistent)) {
      _tryDrop(legacy);
      return persistent;
    }
    if (!_holdsSession(legacy)) return persistent;
    // Signed in before this change: move the session to localStorage.
    try {
      for (final key in _keys) {
        final value = legacy.getItem(key);
        if (value != null) persistent.setItem(key, value);
      }
    } catch (_) {
      // localStorage refuses writes: read the tab's copy, as before.
      _tryDrop(persistent);
      return legacy;
    }
    _tryDrop(legacy);
    return persistent;
  }

  static bool _holdsSession(BrowserStorage storage) =>
      _keys.any((key) => storage.getItem(key) != null);

  static void _drop(BrowserStorage storage) {
    for (final key in _keys) {
      storage.removeItem(key);
    }
  }

  static void _tryDrop(BrowserStorage storage) {
    try {
      _drop(storage);
    } catch (_) {
      // Best effort: the next read or clear tries again.
    }
  }
}
