import 'package:movera_rider/core/auth/browser_token_store.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:web/web.dart' as web;

/// The sign-in lives in localStorage; sessionStorage is only read to move
/// over a session saved by an earlier build (see `web_session_token_store.dart`).
TokenStore? createWebSessionTokenStore() => BrowserTokenStore(
  persistent: _WebStorage(() => web.window.localStorage),
  legacy: _WebStorage(() => web.window.sessionStorage),
);

class _WebStorage implements BrowserStorage {
  const _WebStorage(this._storage);

  /// Looked up on each call: reaching a blocked storage throws, and the
  /// throw belongs inside the caller's error handling.
  final web.Storage Function() _storage;

  @override
  String? getItem(String key) => _storage().getItem(key);

  @override
  void setItem(String key, String value) => _storage().setItem(key, value);

  @override
  void removeItem(String key) => _storage().removeItem(key);
}
