import 'dart:async';

import 'package:movera_rider/core/web/web_reload_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/web_reload_web.dart';

/// Reloads the page so it picks up the newest published app, at most once
/// per [webReloadGuard]. Returns true when the reload has started (the page
/// is going away); false on phones, when offline, or when a reload already
/// ran in the last [webReloadGuard] (no reload loop).
bool reloadPageForNewVersion() => webReloadPageOnce();

/// Reloads the page now (the person pressed Retry). Returns false on phones
/// and when offline, where reloading would only show the browser's own
/// error page.
bool reloadPageNow() => webReloadPageNow();

/// The shortest time between two automatic reloads.
const Duration webReloadGuard = Duration(minutes: 5);

/// The longest wait for the fresh app shell before the page reloads anyway.
const Duration webReloadRefreshTimeout = Duration(seconds: 4);

/// The app shell: the files that carry the list of screen-part hashes.
/// GitHub Pages serves them under fixed names with `max-age=600`, so a plain
/// reload can run the old ones from the browser cache (reload proof
/// 2026-11-11). The rider builds JavaScript only (no `--wasm`).
const List<String> webAppShellFiles = ['flutter_bootstrap.js', 'main.dart.js'];

/// [webAppShellFiles] resolved against the page's base href.
List<Uri> webAppShellUrls(Uri base) => [
  for (final file in webAppShellFiles) base.resolve(file),
];

/// Waits for [refresh] (the fresh download of the app shell into the browser
/// cache), at most [timeout], then calls [reload]. A failed or slow refresh
/// still reloads: the page is no worse off than a plain reload.
Future<void> refreshThenReload({
  required Future<void> Function() refresh,
  required void Function() reload,
  Duration timeout = webReloadRefreshTimeout,
}) async {
  try {
    await refresh().timeout(timeout);
  } catch (_) {
    // Offline, blocked or slow: reload with what the cache has.
  }
  reload();
}
