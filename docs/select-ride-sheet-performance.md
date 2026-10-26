# Select ride: the sheet is slow to slide (iPhone web app)

Owner report (installed home-screen web app, iPhone): "the sheet on the
categories screen is slow when you slide it." The categories screen is
Select ride (`lib/features/ride_selection/presentation/select_ride.dart`):
a `DraggableScrollableSheet` with the ride rows over the Google map, three
stops (low, middle, full), dragged by its title, by the rows or by the
payment block.

This note records what a drag cost, where the cost was, what was changed
and what the same measurement says afterwards. The measuring tool is
checked in (`tool/select_ride_sheet_probe.mjs`) and can be re-run.

## Summary

**Confirmed, with numbers: every tick of the drag rebuilt the whole sheet.**
The sheet's content sat inside one `AnimatedBuilder` on the sheet's
position, so each pointer move rebuilt the title, the promotion line, the
`ListView` and every ride row in it: each row's `GoogleFonts` text styles,
its "arrive · eta" times (`DateTime.now()` and the locale formatter), the
price formatting, the wallet split, the car picture. That was half of
Flutter's frame: in Chromium, Dart build time (widgets, layout, paint
recording) was **8.6 ms at the median and 19.7 ms at p95 per drag frame**
(10 / 23.5 ms when dragging on the rows), against 2 to 3 ms for CanvasKit's
raster. On the phone the same Dart runs in JavaScriptCore, which is slower
than V8, and at 120 Hz a frame has 8.3 ms.

**Also confirmed: the nearby cars redrew the map under the finger.** Every
server answer (every 5 to 6 s) starts a 1.4 s glide at 80 ms ticks; each
tick rebuilt the map widget, and on the web each tick re-applies the
options of every car marker, which Google answers by rebuilding the
marker's DOM (the probe saw JS event listeners swing between 800 and
16,000 and DOM nodes between 660 and 1,700 during the drag runs, all
transient). About a quarter of any drag landed on glide ticks.

**Not the cause (ruled out by measurement):**

- Camera updates during the drag: none. The route is re-framed once, when
  the finger lets go and the sheet snaps (by design, so the map moves with
  the sheet), through `RouteFitScheduler`, which skips an unchanged framing.
  Pinned by a test now.
- Platform-view overlays: the drag never changes the overlay count. Two
  Flutter canvases (base and one overlay above the map), six platform views
  (the map and five invisible `PointerInterceptor`s), one `.gm-style` root,
  flat for the whole drag. The sheet's own `PointerInterceptor` is resized
  every frame, which costs the browser one layout per frame (about 0.2 ms:
  955 layouts, 349 ms, over 1,689 frames).
- Google's own painting: hiding the map's DOM (`--blank-map`) changed
  nothing (build 9.2 / 22.5 ms). Leaving the Maps script out altogether
  (`--no-maps`, no map platform view at all) is in the table below.
- Backdrop filters: none on this screen. The only blurs are the car
  pictures' ground shadows (a `CustomPaint` inside each row, which the row's
  repaint boundary keeps cached) and the sheet's `Material` shadow.
- `MediaQuery` or layout changes: the map's box is fixed
  (`bottom: minSheet`), so the map is not laid out again while the sheet
  moves; the search bar moves only in the top fifth of the slide.
- Image decoding: the car pictures are decoded once; nothing decodes per
  frame.

## How it was measured

`tool/select_ride_sheet_probe.mjs` serves a `flutter build web` output,
drives Chromium (Playwright, iPhone viewport 390×844 at 2×, touch,
`--multi-surface` for Safari's `MultiSurfaceRasterizer`, `--raster` for
raster map tiles since the sandbox has no Maps key) through Home → Plan
your ride → Select ride, then drags the sheet by its title (`--grip title`)
or by the rows (`--grip list`) with CDP touch events, 28 moves 16 ms apart
per drag: ten times up to the full stop and down to the middle stop with a
settle after each ("drags"), then ten back-to-back without settles
("finger-only"). Over each window it records:

- `requestAnimationFrame` deltas (p50 / p95 / max, frames over 16.7 ms and
  over 32 ms);
- Flutter's own frame timings, build and raster per frame, through a QA
  hook added for this (`window.moveraFrameTimings()`, installed only with
  `--dart-define=MOVERA_QA=true`, from `SchedulerBinding.addTimingsCallback`);
- the browser's layout and style-recalculation counts and durations and its
  script time (CDP `Performance.getMetrics`);
- the Flutter canvases, platform views and `.gm-style` roots in the DOM,
  sampled every twelve frames;
- with `--trace`, a CDP trace summed by event name.

Run, from the repository root after a QA build
(`flutter build web --release -t lib/main_demo.dart --dart-define=MOVERA_FLAVOR=demo --dart-define=MOVERA_QA=true ...`):

```
node tool/select_ride_sheet_probe.mjs --dir build/web --drags 10 --multi-surface --raster --out probe.json
node tool/select_ride_sheet_probe.mjs --dir build/web --drags 10 --multi-surface --raster --grip list
node tool/select_ride_sheet_probe.mjs --dir build/web --drags 10 --multi-surface --raster --no-maps
```

One thing to know when reading the `requestAnimationFrame` numbers: the
sandbox's Chromium draws WebGL with SwiftShader (software), and a CDP trace
of the drag showed the GPU process busy 64 % of the wall time (`GPUTask`
16.4 s of 25.7 s) compositing Flutter's 780×1688 canvases. That is what
bounds the rAF cadence here (p50 16.7 ms, p95 67 to 83 ms, before and
after alike) and it is not what the phone does: the iPhone composites on
its GPU. The numbers that transfer are Flutter's build and raster times
and the browser's script time, which are main-thread work the phone does
as well, in a slower JavaScript engine.

## Before

Flutter frame timings per drag frame, Chromium, Safari's rasterizer path,
raster map, ten drags up and down. "> 32" is the number of Flutter frames
whose build + raster span passed 32 ms.

| window | grip | frames | build p50 / p95 ms | raster p50 / p95 ms | frame p50 / p95 ms | > 32 ms | script ms |
|---|---|---:|---:|---:|---:|---:|---:|
| drags (with settles) | title | 1,177 | 8.6 / 19.7 | 2.5 / 7.2 | 11.7 / 25.4 | 9 | 16,280 |
| finger-only | title | 766 | 8.0 / 19.3 | 3.4 / 8.7 | 12.2 / 28.2 | 16 | 11,386 |
| drags (with settles) | rows | 1,182 | 10.0 / 23.5 | 2.9 / 8.3 | 13.9 / 30.6 | 48 | 19,107 |
| finger-only | rows | 762 | 8.7 / 27.2 | 4.1 / 13.7 | 14.5 / 37.9 | 74 | 15,786 |
| idle 30 s (glide ticks only) | – | 115 | 2.1 / 3.0 | 3.3 / 5.3 | 6.6 / 9.0 | 0 | 1,536 |

Attribution runs (title grip, "drags" window):

| variant | build p50 / p95 ms | frame p50 / p95 ms | > 32 ms |
|---|---:|---:|---:|
| map shown | 8.6 / 19.7 | 11.7 / 25.4 | 9 |
| map DOM hidden (`--blank-map`) | 9.2 / 22.5 | 12.8 / 29.2 | 34 |
| no Maps script, no map platform view (`--no-maps`) | 9.5 / 22.8 | 12.2 / 27.9 | 24 |

Without the map the build is no cheaper (9.5 / 22.8 ms): the sheet, not
the platform view, was the main-thread cost. What the map does cost is on
the compositing side: with no map there is one Flutter canvas instead of
two, five platform views instead of six, and the sandbox's software GPU
produced 601 long rAF frames instead of 757 over the same drags.

The CDP trace of four drags (title grip): `RunTask` 36.9 s of main-thread
busy time over 25.7 s wall (tasks overlap in the sum), `FunctionCall`
8.9 s, `FireAnimationFrame` 8.6 s, `EventDispatch` 0.5 s (730 touch
events), `Commit` 0.47 s, browser `Layout` 0.18 s (411), `UpdateLayoutTree`
0.18 s (757), `Paint` 0.13 s. The browser's own layout, style and paint
work is small next to the script.

## What was changed

1. **`select_ride.dart` — the sheet's content is built with the screen, not
   with the slide.** The `AnimatedBuilder` around the whole sheet body is
   gone (`_sheetBody`). The four things that follow the sheet's position
   now listen to `_sheetSlide` on their own, each rebuilding only itself:
   - the rides list fades in above the low stop through a `FadeTransition`
     on a derived animation (`_ListReveal`: 0 at the low stop, 1 at the
     middle), which is a layer-only update, no rebuild;
   - each row's description and badge grow in towards the full stop
     through `_reveal` (`_DetailReveal`: the same ease as before), an
     `AnimatedBuilder` that rebuilds just the `ClipRect` / `Align` wrapper
     and a `FadeTransition`; the row itself, its texts, fonts and times are
     built once;
   - the chosen ride shown at the low stop keeps its drag handler and fades
     with `ReverseAnimation(_ListReveal)`; its `Positioned` / `Offstage` /
     `IgnorePointer` wrapper is the only thing rebuilt per tick, with the
     row prebuilt as the builder's `child`;
   - the handle's accessibility label ("Show all rides" / "Show fewer
     rides") flips through a small `AnimatedBuilder` of its own.
   The look is the same: same stops, same fades, same ease, same `ClipRect`
   / `Align(topLeft)` growth.
2. **`select_ride.dart` — the gliding cars wait for the finger.** While a
   finger moves the sheet (`_sheetDragging`) a new nearby-cars answer and
   the 80 ms glide ticks no longer bump `_carTick`, so the map widget is
   not rebuilt and no marker options reach Google under the drag; the
   ticker keeps running and the cars catch up on the first tick after the
   finger lets go (at most 1.4 s of glide is skipped).
3. **`google_map_provider.dart`** gets a `debugOnFitBounds` test seam next
   to `debugOnCameraCommand`, so a test can pin that no fit is asked for
   while the finger is down.
4. **`web_qa_hooks_web.dart`, `bootstrap.dart`** — `window.moveraFrameTimings()`
   (QA builds only) hands the probe Flutter's build / raster timings. It
   also lets the owner read them on the phone: Web Inspector →
   `JSON.parse(moveraFrameTimings())` after a drag.
5. **`tool/select_ride_sheet_probe.mjs`** — the measurement above.

Tests (`test/ride_selection/select_ride_sheet_performance_test.dart`):
a drag up towards the full stop and down past the middle leaves the
`CustomGoogleMap`, the `ListView` and the first row's `RidePicture` widgets
identical (no rebuild) while the sheet moves by more than 100 px; the
descriptions still grow in at full and the chosen ride's low row still
shows at the low stop with the list faded to 0; no camera command or fit
while the finger moves, exactly one fit when it settles; with a car that
moves on every answer, no map rebuild while the sheet is dragged and one as
soon as the finger lets go.

## After

Same probe, same build flags, on this branch:

| window | grip | frames | build p50 / p95 ms | raster p50 / p95 ms | frame p50 / p95 ms | > 32 ms | script ms |
|---|---|---:|---:|---:|---:|---:|---:|
| drags (with settles) | title | 1,095 | 4.1 / 10.2 | 2.6 / 6.9 | 7.9 / 16.7 | 0 | 11,297 |
| finger-only | title | 715 | 3.7 / 9.5 | 3.5 / 8.5 | 8.2 / 17.2 | 6 | 7,564 |
| drags (with settles) | rows | 1,133 | 4.4 / 11.0 | 2.7 / 7.5 | 8.3 / 17.2 | 1 | 11,918 |
| finger-only | rows | 747 | 3.5 / 9.7 | 3.8 / 9.9 | 8.3 / 18.8 | 3 | 7,675 |

Attribution runs (title grip, "drags" window):

| variant | build p50 / p95 ms | frame p50 / p95 ms | > 32 ms |
|---|---:|---:|---:|
| map shown | 4.1 / 10.2 | 7.9 / 16.7 | 0 |
| map DOM hidden (`--blank-map`) | 4.0 / 11.1 | 7.7 / 17.7 | 3 |
| no Maps script, no map platform view (`--no-maps`) | 4.0 / 10.8 | 7.3 / 16.9 | 2 |

Build time per drag frame is halved at the median and at p95 (8.6 → 4.1,
19.7 → 10.2 ms by the title; 10.0 → 4.4, 23.5 → 11.0 ms by the rows), the
whole Flutter frame goes from 11.7 / 25.4 to 7.9 / 16.7 ms, the Flutter
frames over 32 ms go from 9 to 0 (title) and from 48 to 1 (rows), and the
browser's script time over the same twenty drags drops by a third (16.3 →
11.3 s). The ten back-to-back drags by the rows, which the CDP touch
dispatcher paces on the main thread, took 58 s before and 35 s after.
Canvases, platform views and map roots stay at 2 / 6 / 1 throughout, as
before: the composition is unchanged, the sheet's own work is what shrank.

What is left per frame is the sheet itself: the `DraggableScrollableSheet`
re-laying out its `FractionallySizedBox`, the `Material`'s shadow and
anti-aliased clip, and, between the middle and full stops, the rows
growing (a layout of each visible row). That is the sheet's look.

## Still open

- The phone was not measured. `moveraFrameTimings()` is in the QA build
  for that: on the iPhone, Web Inspector → Console →
  `JSON.parse(moveraFrameTimings())` right after a drag gives build and
  raster per frame; if build is now small and the drag still stutters,
  the cost is Safari's compositing of the canvases around the map
  platform view, which only fewer or smaller overlay canvases (or `--wasm`
  with skwasm's single offscreen context) would change.
- The web plugin re-applies every marker option on each change, so the
  car glide still costs Google a marker rebuild per car per 80 ms tick
  when no finger is on the sheet. Slowing the glide, or moving the cars
  only on the web layer's side (`web/rider_map_camera.js`), would cut
  that; not done here since it does not touch the drag any more.
