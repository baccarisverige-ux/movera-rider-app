import 'dart:async';
import 'dart:js_interop';

import 'package:movera_rider/core/web/web_reload.dart';
import 'package:web/web.dart' as web;

const _key = 'movera_part_reload_at';

/// True while a reload waits for the fresh app shell, so a second tap or a
/// second failing screen does not start another one.
bool _reloading = false;

/// A web publish overwrites the screen parts (`main.dart.js_N.part.js`) under
/// the same names. A page opened before the publish still runs the old
/// `main.dart.js`, and its hash check rejects the new part. Only a fresh page
/// recovers. The time of the last automatic reload is kept in sessionStorage
/// so a part that keeps failing for another reason cannot loop.
bool webReloadPageOnce() {
  try {
    if (_reloading) return true;
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
    if (_reloading) return true;
    if (!web.window.navigator.onLine) return false;
    return _reload(DateTime.now().millisecondsSinceEpoch);
  } catch (_) {
    return false;
  }
}

/// First downloads the app shell fresh (`cache: 'reload'` writes it into the
/// browser cache), so the reloaded page runs the new `main.dart.js` and not
/// the cached one (GitHub Pages: `max-age=600`). Then reloads; the query
/// string defeats a cached index.html (as index.html's own
/// `moveraBootFailed` does); the app ignores it.
bool _reload(int now) {
  _reloading = true;
  unawaited(
    refreshThenReload(
      refresh: _refreshAppShell,
      reload: () {
        final url = Uri.parse(web.window.location.href);
        final query = Map<String, String>.of(url.queryParameters)
          ..['reload'] = '$now';
        web.window.location.replace(
          url.replace(queryParameters: query).toString(),
        );
      },
    ),
  );
  return true;
}

Future<void> _refreshAppShell() async {
  final base = Uri.parse(web.document.baseURI);
  await Future.wait([
    for (final url in webAppShellUrls(base))
      web.window
          .fetch(url.toString().toJS, web.RequestInit(cache: 'reload'))
          .toDart
          // Read the body so the whole file lands in the cache.
          .then((response) => response.arrayBuffer().toDart),
  ]);
}
