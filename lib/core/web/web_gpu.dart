import 'package:movera_rider/core/web/web_gpu_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/web_gpu_web.dart'
    as impl;

/// WebGL context losses the page has seen (index.html counts them at the
/// window, where the browser's own canvases report them). Safari evicts
/// the oldest context when a page holds more than about 16, and drops them
/// under memory pressure; Flutter then rebuilds its surface, which the
/// rider sees as the screen going blank and coming back. Zero off the web.
({int lost, int restored}) webGlContextEvents() => impl.webGlContextEvents();
