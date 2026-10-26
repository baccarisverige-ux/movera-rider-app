# Web lifecycle investigation: "crash, blank, back on Home" on the iPhone

Owner report (installed home-screen web app, iPhone, Safari, the `/live/`
build): at many points of a booking — picking an address, dropping the pin,
the categories screen, searching for a driver, during the trip — "the web
crashes and goes back to the home page", and sometimes "crashes and loses the
display, then comes back".

This document records what was measured, what is confirmed, what is ruled
out, what was changed, and what the phone can still tell us. The measuring
tool is checked in (`tool/web_lifecycle_probe.mjs`) and can be re-run.

## Summary

**Confirmed, with numbers: every Google map the app shows is kept alive for
the life of the page, and a booking shows five or six of them.** Each screen
of the flow (Home, Select ride, Set pickup, Finding, Waiting, Home again)
builds its own `CustomGoogleMap`; the previous one is parked and disposed.
On the web `google.maps.Map` has no `destroy()`, the Maps script keeps an
internal list of every map container, and `google_maps_flutter_web` keeps
every map's element in Flutter's platform-view registry for the life of the
page. Nothing of a disposed map is collected: measured in Chromium with
forced garbage collection, one booking left behind about **1,400 DOM nodes,
870 event listeners, 5 whole `google.maps.Map` objects with their tile
canvases and ~8 MB of JS heap** (plus the tile bitmaps, which the JS heap
does not count). After ten bookings that is fifty maps. iOS kills the page
under memory pressure, Safari reloads it, and the app comes up on Home (no
fresh ride snapshot) or on the trip screen (a snapshot): that is the
"crash, back on the home page".

On the live build the maps are **vector maps** (a cloud Map ID), and a
vector map owns a **WebGL context**. WebKit allows about 16 WebGL contexts
per page and, past that, loses the oldest one — often Flutter's own
rendering surface. Flutter then rebuilds its surface: the screen is blank
and comes back. That is the "loses the display, then comes back", and it is
reproducible in Chromium: when the Maps script tried to create vector maps,
the browser logged "Too many active WebGL contexts. Oldest context will be
lost" during the first booking, and Flutter and Maps between them created
79 contexts in one booking while 66 were lost.

**Fixed in this branch:** the web layer now takes a disposed map back and
gives it to the next screen (Google's own advice: create a map once, reuse
it), Home no longer creates a map for the one frame between Plan your ride
closing and the categories screen opening, the plugin's dispose asks the
layer explicitly, the app logs how many maps the page holds and whether the
browser took WebGL contexts away, and a stale index.html after a deploy
retries once instead of showing an empty page. Measured over three bookings:
Google maps really created **2 instead of 15**, DOM nodes at Home
**992 instead of 4,727**, listeners **475 instead of 2,895**, map canvases
alive **2 instead of 16**; the growth per booking is gone.

**Ruled out:** the service worker (none is registered; Flutter 3.47 writes
a self-unregistering stub), Flutter's own WebGL use (four contexts, flat),
the pointer interceptors (invisible platform views, no overlay surfaces),
the software keyboard on the address screen (Home's map is parked under it,
measured), a code path that navigates Home on an error, and browser back /
edge swipe (nothing pops more than one route, and the installed app has no
history gestures).

## How it was measured

`tool/web_lifecycle_probe.mjs` serves a `flutter build web` output, drives
Chromium (Playwright, iPhone viewport, touch) through Home → Plan your ride →
Select ride → Set pickup ("Confirm and search") → Finding → cancel (or, with
`--mode trip`, driver assigned → trip → Done), and after each screen forces
two garbage collections and records:

- `<canvas>` elements in the DOM (Flutter's, inside its shadow root, and
  Google's), live `flt-platform-view`s and `.gm-style` roots;
- every WebGL context ever created (a hook on `getContext`), who created it
  (Flutter or the Maps script), whether its canvas is still alive after GC,
  still in the DOM, and whether it was lost;
- every `google.maps.Map` constructed (a Proxy on the constructor) and
  whether the Map object and its container are still alive after GC;
- JS heap, DOM nodes, JS event listeners (CDP `Performance.getMetrics`),
  active intervals and pending `requestAnimationFrame`s;
- the app's own `window.moveraMapOwner` and the web layer's
  `riderMapCamera.stats()`.

Two switches matter for reading the numbers:

- `--multi-surface` forces Flutter's `MultiSurfaceRasterizer`, which is what
  Flutter uses on **Safari and Firefox** (`isSafari || isFirefox` in the
  engine's `canvaskit/renderer.dart`): one WebGL context per display canvas.
  Chromium otherwise gets one offscreen context and `bitmaprenderer`
  canvases, which hides the problem the iPhone has.
- `--raster` strips the cloud Map ID so Google draws raster tiles. The
  sandbox has no Maps API key, so vector maps fail here anyway
  ("ApiProjectMapError… Falling back to Raster"); with `--raster` the
  Flutter contexts can be counted cleanly. On the phone the maps are vector.

Run, from the repository root after `flutter build web` (the demo flavour
with `--dart-define=MOVERA_QA=true` for `--mode trip`):

```
node tool/web_lifecycle_probe.mjs --dir build/web --cycles 3 --mode cancel --multi-surface --raster --out probe.json --shots shots/
```

## What the lifecycle costs, screen by screen (before the fix)

Chromium, Safari's rasterizer path, raster maps, three booking + cancel
cycles, numbers after forced GC. "maps" is `google.maps.Map` objects created
/ still alive / alive but out of the DOM.

| step | screen | maps | map canvases alive | DOM nodes | listeners | JS heap MB | platform views |
|---:|---|---|---:|---:|---:|---:|---:|
| 1 | Home | 1 / 1 / 0 | 0 | 560 | 283 | 30.8 | 3 |
| 2 | Plan your ride | 1 / 1 / 1 | 0 | 559 | 293 | 33.4 | 2 |
| 3 | Select ride | 2 / 2 / 1 | 3 | 994 | 569 | 44.1 | 6 |
| 4 | Set pickup | 3 / 3 / 2 | 3 | 1,277 | 734 | 46.2 | 8 |
| 5 | Finding | 4 / 4 / 3 | 6 | 1,642 | 976 | 48.3 | 10 |
| 6 | Home (after cancel) | 5 / 5 / 4 | 6 | 1,940 | 1,143 | 46.9 | 3 |
| 11 | Home (after booking 2) | 10 / 10 / 9 | 11 | 3,333 | 2,016 | 51.2 | 3 |
| 16 | Home (after booking 3) | 15 / 15 / 14 | 16 | 4,727 | 2,895 | 54.6 | 3 |

Every map ever created is still alive after GC. The growth per booking is
about +5 maps, +1,390 nodes, +870 listeners, +4 MB heap (and the tiles).
Flutter's own WebGL contexts stayed at 4 the whole time (2 in the DOM, 2 in
the engine's canvas cache); Google's raster maps used none.

A full trip (`--mode trip`: driver assigned, pickup, trip, Done) costs the
same five maps per booking (Home, Select ride, Set pickup, Finding, Waiting)
and reaches 14 live platform views on the Waiting screen.

### Where the maps come from

Six `CustomGoogleMap`s are mounted per booking, five of them per trip:

1. Home's map, parked (replaced by a plain box) whenever a page covers it.
2. Home's map **again**, for the moment between Plan your ride closing and
   Select ride opening: Home becomes current, `_syncRouteParking` resumes
   the map, and `_withParkedHomeMap` parks it a frame later for the
   categories screen. Visible in the probe as map #3 at Select ride.
3. Select ride's map.
4. Set pickup's map (Select ride parks its own while the pin screen is up).
5. Finding's map.
6. Waiting's map (Finding parks its own first).

The screens already hand over cleanly — at most one live map at a time,
exactly as `test/home/audit_fix_map_parking_test.dart` pins — but a disposed
map is not gone.

### Why a disposed map stays alive

Two retainers, both confirmed:

- `google_maps_flutter_web` 0.5.14+2 registers one platform-view factory per
  map (`plugins.flutter.io/google_maps_<id>`) whose closure returns the
  map's `<div>`; the engine's `PlatformViewManager._factories` is never
  pruned (only a debug reset clears it). After `dispose()` the controller,
  its `<div>` and whatever hangs off the `<div>` stay reachable.
- The Maps script itself keeps every map. A V8 heap snapshot taken after a
  disposed map's children were removed and its listeners cleared (the
  experiment in this investigation) shows the `google.maps.Map` object held
  through `Array.prototype` → a Maps closure (`Ja`) → its scope → an array
  (`an`) → the map's inner `<div>` → a `WeakMap` entry from that div to the
  Map. Deleting the div's expandos and nulling the Map's own properties
  changed nothing. There is no public way to release a Map; Google's
  guidance is to create one and reuse it.

So gutting a dead map's DOM and losing its WebGL context (tried first) frees
GPU memory but not the JS objects, listeners or nodes. Creating fewer maps is
the only fix that works.

### Flutter's part

On Safari the engine renders with one WebGL context per display canvas
(base canvas + one overlay per visible platform view, up to
`canvasKitMaximumSurfaces` = 8) and keeps every canvas it ever needed in a
cache that never shrinks. With one map on screen that is 2 contexts in use
and 2 cached — 4 in total, flat across all screens. `PointerInterceptor`s
are *invisible* platform views and the composition optimiser skips them: the
Waiting screen has 14 platform views and still 2 Flutter canvases.

The engine's reaction to a lost context matters for the symptom: it acquires
a new canvas and context at once (`CkSurface.onContextLost`). When a page is
at the browser's limit, every new context evicts the oldest one, so one loss
becomes a storm (Chromium, first run with vector-map attempts: 79 contexts
created, 66 lost, during one booking). On the phone that storm is the
flicker/blank; the leaked vector maps are what fills the limit.

## After the fix

Same run (`--multi-surface --raster`, three booking + cancel cycles) on the
build from this branch:

| step | screen | Maps created / reused | map canvases alive | DOM nodes | listeners | JS heap MB |
|---:|---|---|---:|---:|---:|---:|
| 1 | Home | 1 / 0 | 0 | 563 | 285 | 30.9 |
| 3 | Select ride | 1 / 1 | 3 | 674 | 396 | 42.2 |
| 4 | Set pickup | 1 / 2 | 1 | 601 | 292 | 41.3 |
| 5 | Finding | 2 / 2 | 4 | 969 | 534 | 44.7 |
| 6 | Home (after cancel) | 2 / 3 | 2 | 925 | 472 | 42.7 |
| 11 | Home (after booking 2) | 2 / 7 | 2 | 957 | 471 | 45.1 |
| 16 | Home (after booking 3) | 2 / 11 | 2 | 992 | 475 | 46.9 |

Two `google.maps.Map` objects exist for the whole session (one on screen,
one in the pool for the hand-over), the per-booking growth in nodes and
listeners is gone, map canvases stay at 2, and the remaining heap drift is
small. Two full trips (`--mode trip`: Waiting with its traffic layer and
driver marker, the trip, Done) give the same picture: 2 Maps created and 9
reused, DOM nodes 563 → 949 → 1,020 at Home, listeners 285 → 471 → 476,
against 5 new maps and +1,400 nodes per trip before. Screenshots of the reused maps on each screen (route and pins on
Select ride, the plain pin map on Set pickup, the route on Finding, the puck
on Home) show no overlay left behind from the previous owner.

## What was changed

1. **`web/rider_map_camera.js` — map reuse.** The layer already wraps
   `google.maps.Map`. A map whose element Flutter has removed is now taken
   back: its instance listeners are cleared, its markers, lines, shapes and
   traffic layer are removed (tracked through the constructors and
   `setMap`), its container leaves the dead plugin element, and it waits in
   a pool of two. The next plugin element gets the same Map with its
   container moved inside and the new options applied; the gesture state
   moves with it. Beyond the pool a map is gutted (listeners cleared, WebGL
   context given back with `WEBGL_lose_context`, DOM dropped). The teardown
   fires on the element leaving the DOM (also for a map that lived only a
   frame) and when Dart asks.
2. **`CustomGoogleMap.dispose` asks the layer** (`RiderMapBridge.release`)
   and logs `map.web_created` with the layer's counts and the page's WebGL
   losses; `AppLifecycleObserver` adds the same counts to `app.lifecycle`.
   `web/index.html` counts `webglcontextlost` / `webglcontextrestored` at the
   window (`window.moveraGpu`), read by `lib/core/web/web_gpu.dart`.
3. **Home** keeps its map parked for up to 1.5 s while a route flow is still
   running (Plan your ride closed, the categories screen about to open, or
   Back from the categories screen reopening Plan your ride), instead of
   mounting a Google map for that frame; a flow that ends gives the map back
   at once, and a slow lookup still gets it after the grace.
4. **`web/index.html`** retries the page once, with a fresh query string, if
   `flutter_bootstrap.js` fails to load — a stale index.html after a deploy
   otherwise shows the boot screen and then an empty page.
5. **Workflow** (`publish-web-live.yml`): the bootstrap tag matcher follows
   the new tag, and the service-worker situation is written down where the
   build is (see below).

Tests: `test/maps/custom_google_map_release_test.dart` (a disposed map is
released by its map id; a map that never came up releases nothing; mounts
are recorded), `test/home/home_route_flow_map_test.dart` (Plan your ride to
Select ride and Back again mounts no Home map in between; closing Plan your
ride gives Home its map back at once). The probe above is the check for the
JavaScript side.

## The other suspects

### Service worker / stale build mix

- `web/flutter_bootstrap.js` calls `_flutter.loader.load()` with no
  `serviceWorkerSettings`: Flutter never registers its worker. `index.html`
  unregisters any surviving worker (except Firebase's) and clears caches on
  every boot. Flutter 3.47 still writes `flutter_service_worker.js`, but it
  is a stub that unregisters itself; `--pwa-strategy` is deprecated and only
  changes the default bootstrap, which this project does not use. Ruled out
  as a mid-session reload source.
- What remains is the HTTP cache. GitHub Pages serves with
  `Cache-Control: max-age=600`; the `<meta http-equiv="Cache-Control">` in
  index.html does not change that. The bundle is fingerprinted
  (`main.<sha>.dart.js`, `flutter_bootstrap.<sha>.js`) and the previous
  files vanish with each deploy, so a phone holding a ten-minute-old
  index.html gets a 404 for its bundle: boot screen for 20 s, then an empty
  page — not Home. A running app is not affected (no deferred parts, fonts
  and CanvasKit are loaded at start). The one-time retry in index.html now
  covers the stale case; deploying less often while someone is testing is
  the other half.

### Memory growth per booking in Dart

Timers and listeners were read through: `Timer.periodic`s in Home's
controller, Finding, Waiting, Select ride, the poll and the mock transport
all cancel in `dispose`; the probe shows active intervals at 2–3 and no
pending animation frames at rest, and JS event listeners flat after the fix.
`RideSnapshotStore` is one key. The marker bitmaps are rasterised once per
screen. Nothing on the Dart side grows per booking in the numbers above;
the growth was the maps.

### Uncaught errors

`FlutterError.onError` presents and records; `PlatformDispatcher.onError`
logs and returns true; `runZonedGuarded` records and logs. No handler
rebuilds the root or navigates. A throwing `build` shows the grey error box
in that subtree, not Home. The only white screen in the app's own code is
`RideRestoreGate` before `root()` resolves (the first second of a cold
start). Ruled out as a cause of "back on Home"; what it does explain is that
a page the system reloaded shows Home when no fresh ride snapshot exists and
the trip screen when one does (`RideRestoreCoordinator.surfaceFor`).

Note on sign-in: on the web the session tokens live in `sessionStorage`
(`web_session_token_store_web.dart`), which survives a reload of the same
page but not a fresh launch of the home-screen app. A rider who lands on
Sign in after a crash was relaunched; one who lands on Home was reloaded.

### Browser back / edge swipe

The installed app has no history gestures. In a Safari tab an edge swipe is
history back: Flutter pops one route (Set pickup → categories, categories →
Plan your ride by design, Plan your ride → Home); on Finding a back opens
the cancel sheet (`PopScope(canPop: _leaving)`); the root gate swallows the
last back on the web (`PopScope(canPop: !kIsWeb)`), and the browser-tab Home
lock keeps the site from exiting. Nothing jumps to Home from a ride screen.

### Keyboard and viewport

The address screen has no map and Home's map is parked under it (probe:
0 maps, 2 platform views on Plan your ride), so the software keyboard's
viewport change relays out text, not a map. Home keeps its map height
stable through browser-bar changes (`_stableMapHeight`). Ruled out.

## What the phone can settle

1. **Does the MOVERA boot bar appear before Home?** If yes, the page was
   reloaded (killed by iOS or by a lost renderer). If Home appears with no
   boot bar, it was an in-app navigation and the log will say why.
2. **Web Inspector** (Mac + cable; iPhone: Settings → Safari → Advanced →
   Web Inspector; Safari on the Mac: Develop → iPhone → Movera). After a
   reload the console starts with `app.start`, then `ride.restore.cold
   {status}`; while riding, `map.web_created {createdMaps, recycledMaps,
   webglLost}` should show `createdMaps` staying at 1–2 across bookings
   with this branch (it climbed by five per booking before), and
   `app.lifecycle {webglLost}` should stay at 0. A rising `webglLost` with
   this branch means something else is spending contexts.
3. **White, or blank map?** A white flash before Home is a reload. A map
   area that goes blank while the sheet stays is a lost WebGL context being
   rebuilt (Flutter) or Google re-creating its vector map.
4. **After a crash during a trip, does the trip screen come back?** It
   should (the snapshot). Home there means the snapshot was gone or
   terminal; Sign in means the app was relaunched, not reloaded.
5. Safari's "A problem repeatedly occurred" banner is the page being killed
   for memory; with this branch it should not appear in a session of ten
   bookings.

## Still open

- The vector-map WebGL budget could not be measured here (no Maps API key in
  the sandbox; Google falls back to raster). With reuse there are at most two
  Google maps, so at most two map contexts next to Flutter's four; the
  logging above will show it on the phone.
- The structural fix — one shared map under the Navigator that every screen
  configures, which `AppScope.instance.maps` and `MapOwners` were leading
  towards — would remove the hand-over frames and the pool entirely. The
  reuse in the web layer gives the same memory profile without touching the
  screens, which is why it was done first.
- Building for the web with `--wasm` (skwasm renders with a single offscreen
  WebGL context on every browser) would also take Flutter off Safari's
  per-canvas contexts, at the cost of a wasm-GC requirement (iOS 18.4+) and
  a dependency audit; not attempted.
