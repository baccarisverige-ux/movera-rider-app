import 'dart:js_interop';

import 'package:movera_rider/core/observability/restart_watch.dart';
import 'package:web/web.dart' as web;

class _PageStore implements RestartMarkerStore {
  @override
  String? read() => web.window.localStorage.getItem(RestartWatch.storageKey);

  @override
  void write(String value) =>
      web.window.localStorage.setItem(RestartWatch.storageKey, value);
}

/// Starts the restart diagnostic on this page: the marker in
/// `localStorage`, the page's visibility, `pagehide` / `pageshow`, and
/// `webglcontextlost` on its canvases. Never throws; null if the page
/// cannot be watched.
RestartWatch? startRestartWatch({required RestartReport report}) {
  try {
    final watch = RestartWatch(store: _PageStore(), report: report);
    final document = web.document;
    bool visible() => document.visibilityState != 'hidden';
    document.addEventListener(
      'visibilitychange',
      ((web.Event _) => watch.setVisible(visible())).toJS,
    );
    web.window.addEventListener(
      'pagehide',
      ((web.Event _) => watch.pageHide()).toJS,
    );
    web.window.addEventListener(
      'pageshow',
      ((web.PageTransitionEvent event) {
        if (event.persisted) watch.pageShow();
      }).toJS,
    );
    final lost = ((web.Event _) => watch.contextLost()).toJS;
    // The event does not bubble: listen in the capture phase, and on each
    // canvas (also those inside Flutter's shadow roots) as it appears.
    document.addEventListener('webglcontextlost', lost, true.toJS);
    watch.onBeat = () => _watchCanvases(document, lost);
    watch.start(visible: visible());
    return watch;
  } catch (_) {
    return null;
  }
}

const _watched = 'data-movera-gl-watch';

void _watchCanvases(web.Document document, JSFunction lost) {
  void scan(web.NodeList canvases) {
    for (var i = 0; i < canvases.length; i++) {
      final node = canvases.item(i);
      if (node == null || !node.isA<web.Element>()) continue;
      final canvas = node as web.Element;
      if (canvas.hasAttribute(_watched)) continue;
      canvas.setAttribute(_watched, '');
      canvas.addEventListener('webglcontextlost', lost);
    }
  }

  scan(document.querySelectorAll('canvas'));
  final hosts = document.querySelectorAll('flutter-view, flt-glass-pane');
  for (var i = 0; i < hosts.length; i++) {
    final host = hosts.item(i);
    if (host == null || !host.isA<web.Element>()) continue;
    final root = (host as web.Element).shadowRoot;
    if (root != null) scan(root.querySelectorAll('canvas'));
  }
}
