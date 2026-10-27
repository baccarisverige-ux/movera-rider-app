# Audit Phase 7 (rider): performance, measured

Date: 2026-10-27. Branch `audit/phase-7`. Plan: `movera-contracts/docs/audit/AUDIT_PLAN.md`, Phase 7.

Where the numbers come from: release web builds in headless Chromium (Playwright 1.56, SwiftShader WebGL, a 390x844 touch viewport) on the audit container (4 cores, no GPU, no Google Maps key, so maps fall back to raster and show Google's "no key" dialog). Times are the container's, not an iPhone's: compare them with each other and with later runs of the same scripts, not with a phone. Device numbers (real frame rate, CPU, battery) are on the owner's list (`movera-server/docs/audit/device-checklist.md`).

## Measured

### Start (5 cold loads, median; `flutter build web --release`, served locally without compression)

| Build | first Flutter frame | Home built (`moveraHomeBuilt`) | main thread quiet (no long task for 500 ms) | requests | JS heap after GC |
|---|---:|---:|---:|---:|---:|
| demo (`lib/main.dart`) | 1,445 ms | 2,220 ms | 2,669 ms | 22 | 25.0 MB |

`main.dart.js` of the production build: 5,885,576 bytes, 1,671,896 bytes after gzip -9. CanvasKit (`canvaskit/chromium/canvaskit.wasm`) comes on top.

### Frames

- Select ride sheet, 10 drags up and down (`tool/select_ride_sheet_probe.mjs --drags 10 --multi-surface --raster`): Flutter's own frame time p50 6.2 ms, p95 12.8 ms, **2 of 1,265 frames over 32 ms**. The browser's rAF deltas in the same window were p50 33 ms / p95 117 ms: that is SwiftShader compositing the map platform view in this container, not Dart work. Idle on Select ride: 19 Flutter frames in 2 s, p95 10.9 ms.
- Each screen sitting still for 2.5 s (lifecycle probe, new `frameCost` per snapshot): Home 46 frame callbacks p95 4 ms; Select ride 52, p95 3.1 ms; Finding 7, p95 20.7 ms; Waiting 7 (one of 151 ms when the screen opens).
- Rider Home, one minute with a moving position (1 fix a second, `--gps-minute`): 906 frame callbacks, p50 0.8 ms, p95 5.5 ms, 2 over 32 ms; main thread busy 5.8 s of the minute (CDP TaskDuration), script 4.2 s. Phase 6 counted 1,653 puck repaints a minute in the widget test; on the web build they cost under 1 ms each at p50.
- Rebuild counts: not measured on the web build (a release build has no build timeline). The widget tests pin them: `test/performance/phase104_performance_test.dart` (Waiting moves the driver without rebuilding the map leaf), `test/performance/gps_update_budget_test.dart` (one minute of GPS).

### Memory over 10 bookings (the iPhone reload issue)

`node tool/web_lifecycle_probe.mjs --cycles 10 --mode cancel --multi-surface --raster` (book, search, cancel, back on Home; JS heap after a forced GC through CDP):

| Home after booking | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| JS heap MB | 40.8 | 42.7 | 44.1 | 45.2 | 45.8 | 46.2 | 46.8 | 47.4 | 48.0 | 48.5 |
| DOM nodes (incl. detached) | 919 | 956 | 987 | 1,023 | 1,055 | 1,086 | 1,117 | 1,137 | 1,156 | 1,175 |
| listeners | 470 | 472 | 471 | 475 | 475 | 474 | 476 | 476 | 477 | 478 |

Before the first booking: 30.5 MB, 565 nodes. The map layer created 2 `google.maps.Map` objects for the whole run and reused them 39 times; no WebGL context was lost. **Not flat, but close:** after booking 1 the heap grows 0.86 MB a booking on average (1.9 MB at first, about 0.5 MB from booking 5), listeners are flat, the attached DOM grows by one Flutter text-editing `<form>` a booking (a DOM census at Home after bookings 2 and 4: 359 → 366 elements). Before the Phase 6 map pool the same probe grew about 4 MB, 870 listeners and 5 maps a booking. The remaining slope is too small to explain a reload on its own; the owner's Safari check stays on the device list.

### API calls per minute per screen (live staging build against the e2e server)

A `main_staging` build pointed at a local https origin that serves the app and forwards `/api` to the e2e harness server (real Postgres); sign-in with +46 70 174 06 08 / 1234; the trip booked and driven by harness clients; requests counted on the server per minute:

| Screen | before | after this branch |
|---|---:|---:|
| Home, signed in, idle | 0 | 0 |
| Finding (searching) | 46: ride poll 30, telemetry 10, messages 6 | **36**: ride poll 30, messages 6 |
| Waiting (driver accepted) | 54: ride poll 30, telemetry 18, messages 6 | **36** |
| On trip | 54: ride poll 30, telemetry 18, messages 6 | **36** |

## Findings

| Id | Sev | Finding | Fix | Test / evidence |
|---|---|---|---|---|
| P7-R1 | S3 | Every answered API call was also sent as a `POST /telemetry/logs` line (`api.GET … status 200`), so the trip screens' 2 s ride poll cost a second request (18 a minute) and used up the 20-a-minute routine cap meant for real events. | `HttpObservabilitySink` no longer sends routine `api.*` lines with a status below 400; failed calls (400 and up, timeouts) and every other line still go out. The server logs each request with its requestId anyway. | `test/performance/telemetry_request_budget_test.dart` fails before, passes after; live count 54 → 36 a minute (table above). |
| P7-R2 | S4 | The trip screens poll `GET /rides/{id}` every 2 s (30 a minute per rider) and `GET /trips/{id}/messages` every 10 s, although the server offers `GET /trips/{id}/events` (SSE). | Not changed: moving the rider to the event stream is a larger change than Phase 7 allows. Recommended for later. | Live count above. |
| P7-R3 | S4 | A trip booked from another session is not noticed on Home until the app is reloaded (Home checks `/rider/trips/active` at start only). | Not changed (rare; the app's own bookings are fine). | Live run: no request in 60 s after a booking elsewhere. |
| P7-R4 | — | Home after a full trip (`--mode trip`): about 200 Google Maps rAF callbacks a second (`poa.show` in Maps' `common.js`) while idle; after a cancelled search: none. | Not changed: in this container Maps runs without a key and keeps showing its error dialog, so this may be the dialog. To check on a phone with a key (device list). | Lifecycle probe with a rAF caller census. |

## Budgets added (CI)

- `tool/check_web_budget.py`, CI job "Web release builds": production `main.dart.js` at most 6,500,000 bytes raw and 1,850,000 bytes gzip (baseline 5,885,576 / 1,671,896, plus about 10 %).
- New CI job "Web memory over repeated bookings" (required by the gate): demo build with QA hooks, `tool/web_lifecycle_probe.mjs --cycles 6 --mode cancel`, then `tool/check_memory_budget.py`: heap growth at most 2.0 MB a booking from booking 1 on, listeners +40 at most, at most 2 maps created, no WebGL context lost. Locally: 0.86 MB a booking over 9 bookings, 1.30 over 4.
- `test/performance/telemetry_request_budget_test.dart`: a minute of answered ride polls sends no telemetry.
- The lifecycle probe now records frame-callback cost per screen (`frameCost`) and has `--gps-minute`.

## Not measured here

Real frame rates, CPU and battery on an iPhone or Android, vector maps with a key, Safari's memory limit and reloads: owner device checklist.
