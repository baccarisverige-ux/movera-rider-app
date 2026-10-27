# Audit Phase 6 (rider): maps, GPS, address search, routing

Date: 2026-10-27. Branch `audit/phase-6`. Plan: `movera-contracts/docs/audit/AUDIT_PLAN.md`, Phase 6. Owner notes N2, N6, N7 (`MOVERA_HANDOFF.md`).

No Google Maps key exists for CI or this container, so nothing here was checked on a real Google map, in Safari or on an iPhone. Every finding below comes from reading the code and from Flutter tests with a fake maps platform, plus the node harness for the web gesture layer where it applies.

## What earlier rounds had already fixed (checked again, left as is)

- **N6, Select ride street-level wedge** (#413): a route fit never zooms past 17 (`routeFitMaxZoom`), also on the plain bounds fit; pickup and destination within ~9 m frame the point at zoom 14.4; Select ride, Finding and the trip map are flat (`tiltWithZoom: false`, `tiltGesturesEnabled: false`). Tests: `camera_tilt_test`, `phase101_select_ride_test`. That covers tilt 0, the zoom cap and a minimum span for tiny routes.
- **N7, wrong address after sign-in** (#413, #415): see "N7" below. No code change needed.
- **N5, traffic layer** (#413): off on every map.
- **Address search**: one request per typing pause (300 ms debounce, rider-u86), an answer for an older text is dropped (`query != _activeController.text`), keystrokes typed before the search field is focused are kept (`early_input_capture_test`). The request already sent is not aborted, only ignored. Tests: `audit_fix_route_picker_test`, `phase100_destination_input_test`, `early_input_capture_test`.
- **Location states**: permission denied, permanently denied, services off, temporarily unavailable with retry/backoff, approximate-only, "Live updates paused. Driver position may be out of date." on the trip. All three languages. Tests in `test/home/location_controller_test.dart`, `audit_fix_location_recovery_test.dart`, `audit_fix_live_tracking_test.dart`.

## Findings fixed on this branch

| Id | Sev | Finding | Fix | Test |
|---|---|---|---|---|
| P6-R1 (N6) | S3 | The web plugin reports zoom 0 and a (0, 0) centre when Maps has no value yet; the rider map took that as the camera pose, so the next app move started from a world view. | `MapCameraReport.isFrame`; `CustomGoogleMap` drops such reports, as the driver app does since #380. | `custom_google_map_release_test` |
| P6-R2 (N6) | S3 | On Select ride the camera snapped back after a pinch: the road route answers late (sleeping server, slow router) and its refit took the camera back. | No refit once the rider moved the map by hand (`GoogleMapProvider.movedByHand`). The road is still drawn. | `select_ride_road_route_test` |
| P6-R3 (N2) | S3 | Without OSRM the server answers `POST /routes` with its two-point straight line, and Select ride and Finding drew it like a road. | The trip map's "Approximate route" label now also shows on Select ride and Finding (`ApproximateRouteBadge`). | `select_ride_road_route_test`, `n2_approximate_route_test` |
| P6-R4 | S3 | If Maps JavaScript never loads (no network, a blocked or refused script), the map stayed blank grey for good. | After 12 s the placeholder says "Map unavailable. Check your connection, then reopen Movera." (en/fr/sv). | `map_unavailable_message_test` |

Each test fails before its fix and passes after.

### Steps to reproduce (before the fixes)
- P6-R2: open Select ride while `/routes` is slow (Render cold start), pinch the map, wait for the road line: the camera flies back to the overview.
- P6-R3: run the server without `OSRM_URL` and book: the straight green line on Select ride and Finding has no label.
- P6-R4: block `maps.googleapis.com` in the browser and open the web app: grey map, no message.
- P6-R1: not seen directly; it comes from reading google_maps_flutter_web 0.5.14+2 (`convert.dart`, `_gmViewportToCameraPosition`).

## N7 (verified, no change)
Traced: the quick first position (the OS's cached fix, or a low-accuracy one within 1 km) only draws the puck and moves the camera (`_showQuickFix`, `_roughFix`). The pickup label stays "Current location", and only an accurate fix (≤ 150 m) is reverse geocoded. A default point is never looked up. New test `n7_coarse_first_fix_test` (cached-position case) passes on main, so it guards the current behaviour; it does not reproduce a bug.

## N2 (verified)
The rider draws the server's `points` whenever `/routes` gives three or more. A two-point answer is the server's estimate (provider `estimate`), and it is now labelled on every map that draws it. The web demo build alone fills in from the public OSRM (owner decision 11). With stops, Select ride and Finding draw the straight pickup → stops → destination line, and it is **not labelled** yet (open).

## GPS budget (new test `test/performance/gps_update_budget_test.dart`)
One minute on Home: one fix a second at 14 m/s, a compass that jitters ±0.8°, the puck pulse on.
Measured: **1653 puck repaints** (the 420 ms glide on painted frames, about 27.5 per fix), 3 heading repaints, 71 pulse ticks, **0 network requests** from the controller. Home asks for a new address only after a 75 m move, which is about 11 a minute at 14 m/s (from the code, not measured).
Budgets: 28 repaints per fix, 4 heading repaints per second, one pulse per 850 ms, no request per fix. Each puck repaint is a new marker set and a marker update. Phase 7 should measure what this costs on the web.

## N6 pinch faults: what is still open
- The "crash" on pinch was not reproduced. The likely causes (losing the WebGL context on iOS Safari, the page being killed) need an iPhone. The `map.web_created` log line has `webglLost` / `webglRestored` to check this.
- "Route line very thin": the rider route has a fixed width (a 4 px line on an 8 px casing, nothing per zoom), so the driver's zoom-0 cause does not apply here. Not reproduced.
- Not checked without a key: real Google gestures, vector tilt, `fitBounds` padding, iOS Safari.

## Needs a real device / a Maps key
Pinch on Select ride, Finding and the trip map on an iPhone (Safari and the PWA); the map-unavailable text with a revoked key; the approximate label with the server running without `OSRM_URL`.
