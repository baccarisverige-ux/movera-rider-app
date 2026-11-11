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
