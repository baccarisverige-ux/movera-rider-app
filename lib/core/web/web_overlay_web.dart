import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:movera_rider/core/web/web_standalone.dart';
import 'package:web/web.dart' as web;

bool _homeLockInstalled = false;

void webSetOverlayOpen(bool open) {
  web.document.body?.classList.toggle('movera-overlay-open', open);
}

void webSetHomeLock(bool lock) {
  _applyHomeLockCss(lock);

  // Browser tabs need a Back guard so a horizontal overscroll or Back on Home
  // does not leave the site. Installed Home Screen apps do not have that
  // browser-navigation model. On iOS, relying only on display-mode can miss the
  // installed state, while navigator.standalone is still true. Use the shared
  // detector here so standalone never gets a popstate guard that can
  // desynchronise Flutter navigation (Finding, Cancel, modal sheets, Wallet).
  if (isInstalledWebApp()) return;

  _installHomeLock();
  final fn = globalContext.getProperty('moveraSetHomeLock'.toJS);
  if (fn.isA<JSFunction>()) {
    (fn as JSFunction).callAsFunction(globalContext, lock.toJS);
  }
}

void _applyHomeLockCss(bool lock) {
  web.document.documentElement?.classList.toggle('movera-home-lock', lock);
  try {
    (web.document.documentElement as web.HTMLElement?)?.style.setProperty(
      'overscroll-behavior-x',
      'none',
    );
    web.document.body?.style.setProperty('overscroll-behavior', 'none');
    web.document.body?.style.setProperty('overscroll-behavior-x', 'none');
  } catch (_) {
    // Web interop: older browsers ignore these style properties.
  }
}

void _installHomeLock() {
  if (_homeLockInstalled) return;
  _homeLockInstalled = true;
  if (web.document.getElementById('movera-home-lock-js') != null) return;
  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..id = 'movera-home-lock-js'
    ..text = r'''
(function() {
  // This Back guard is browser-tab-only. Dart checks the shared installed-app
  // detector before this script is installed, so there is no second,
  // potentially inconsistent standalone detector here.
  if (history.scrollRestoration) history.scrollRestoration = 'manual';
  // Flutter's web engine (SingleEntryBrowserHistory) owns exactly two
  // entries: the origin entry ({origin: true}) and its flutter entry
  // ({flutter: true}) on top. Back from the flutter entry lands on the origin
  // entry, the engine re-pushes its flutter entry and sends popRoute, which at
  // Home-at-root exits the site. This lock never adds, replaces or tags
  // entries (an extra or retagged entry makes the engine go(-1) on every
  // popstate and loop against a re-push, and grows history per Home visit).
  // Instead, while Home is locked, a capture listener (it runs before the
  // engine's listener on window) swallows that origin popstate and restores
  // the flutter entry exactly as the engine would, minus the popRoute.
  window._moveraHomeLock = false;
  window._moveraHomeUrl = null;
  window.moveraSetHomeLock = function(lock) {
    window._moveraHomeLock = !!lock;
    try {
      document.documentElement.classList.toggle('movera-home-lock', !!lock);
    } catch (_) { /* best effort */ }
    if (lock) window._moveraHomeUrl = location.href;
  };
  window.addEventListener('popstate', function(event) {
    if (!window._moveraHomeLock) return;
    var state = event.state;
    if (!state || state.origin !== true) return;
    event.stopImmediatePropagation();
    try {
      history.pushState({ flutter: true }, 'flutter', window._moveraHomeUrl || location.href);
    } catch (_) { /* best effort */ }
  }, true);
})();
''';
  web.document.head?.appendChild(script);
}
