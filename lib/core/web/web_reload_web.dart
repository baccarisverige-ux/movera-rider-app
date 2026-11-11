import 'package:movera_rider/core/web/web_reload.dart' show webReloadGuard;
import 'package:web/web.dart' as web;

const _key = 'movera_part_reload_at';

/// A web publish overwrites the screen parts (`main.dart.js_N.part.js`) under
/// the same names. A page opened before the publish still runs the old
/// `main.dart.js`, and its hash check rejects the new part. Only a fresh page
/// recovers. The time of the last automatic reload is kept in sessionStorage
/// so a part that keeps failing for another reason cannot loop.
bool webReloadPageOnce() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(web.window.sessionStorage.getItem(_key) ?? '');
    if (last != null && now - last < webReloadGuard.inMilliseconds) {
      return false;
    }
    if (!web.window.navigator.onLine) return false;
    web.window.sessionStorage.setItem(_key, '$now');
    return _reload(now);
  } catch (_) {
    // Storage blocked (private mode): no guard, so no automatic reload.
    return false;
  }
}

bool webReloadPageNow() {
  try {
    if (!web.window.navigator.onLine) return false;
    return _reload(DateTime.now().millisecondsSinceEpoch);
  } catch (_) {
    return false;
  }
}

/// The query string defeats a cached index.html (as index.html's own
/// `moveraBootFailed` does); the app ignores it.
bool _reload(int now) {
  final url = Uri.parse(web.window.location.href);
  final query = Map<String, String>.of(url.queryParameters)
    ..['reload'] = '$now';
  web.window.location.replace(url.replace(queryParameters: query).toString());
  return true;
}
