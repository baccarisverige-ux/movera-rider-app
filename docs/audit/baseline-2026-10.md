# Rider app — Phase 1 baseline audit (2026-10)

Audited: `main` @ c1063fb8. Documentation only; no source/test/workflow changes.
**Branch status (verified):** `rider-live-fixes-1` (tip `166fc8ab`) was squash-merged into `main` as
`c1063fb8` "Rider live test fixes 1 … (#413)" on 2026-10-26 13:02 +0100. `git diff --stat origin/main origin/rider-live-fixes-1`
is empty, i.e. the branch tree equals `main`. Everything the branch addresses is therefore already in the audited code;
HANDOFF.md §4.2 ("NOT merged") is out of date for the rider app.

## Progress
- [x] 1. Structure and architecture
- [ ] 2. Dependencies
- [x] 3. CI
- [ ] 4. Baseline run
- [ ] 5. Coverage of critical logic
- [ ] 6. Screen inventory
- [ ] 7. Code quality findings
- [ ] 8. Known issues N3–N10
- [ ] 9. Untested features and risks
- [ ] 10. Summary


## 1. Structure and architecture

Size: 491 Dart files / 92 952 lines in `lib/`; 560 `*_test.dart` files in `test/` (`find … | wc -l`).

- **Feature folders:** `lib/features/<feature>/{presentation,application,data,domain}` — 29 features (active_ride, auth, booking,
  destination, destination_search, driver_arriving, fare, finding_driver, history, home, messages, notifications, onboarding,
  payments, pickup, profile, promotions, ratings, reservations, ride_booking, ride_complete, ride_selection, safety,
  saved_places, scheduled_rides, support, trips, wallet). Cross-cutting code in `lib/core/` (api, auth, realtime, maps, web,
  location, payments, notifications, observability, contracts, …), UI kit in `lib/shared/`, app shell in `lib/app/`.
- **State management:** plain `ChangeNotifier` controllers (no provider/riverpod/bloc/get_it in pubspec). Canonical owners are
  listed in `ARCHITECTURE.md` (RideSession, BookingCoordinator, FindingDriverController, ActiveRideController, …).
- **DI / composition:** a hand-written service locator singleton `AppScope` (`lib/app/di.dart:85`, 407 lines) builds every
  service. Release guards: `TransportComposition.validate` (`lib/app/config/transport_composition.dart`) refuses mock
  api/realtime/payments/push/logging and a `.invalid`/non-https `MOVERA_API_BASE_URL` in staging/production;
  `RepositoryComposition.validate` (`lib/app/config/repository_composition.dart:26`) refuses device-only repositories.
- **API layer:** `ApiClient` (`lib/core/api/api_client.dart`, 371 lines; `X-Api-Version 0.5`, 30 s live timeout,
  15 s mock timeout). In demo/dev/test the default HTTP client is `InProcessMockClient` (`lib/core/api/in_process_mock_client.dart`,
  **2 787 lines**). Important: `ApiClient.contractWire` (`api_client.dart` ~line 53) is true only for staging/production; demo,
  dev and **test** builds speak the mock's *older dialect* (`rideType`, `{quote}`, `{ride}`). So most tests exercise a wire format
  the live server does not speak (see §9).
  Live vs demo data sources: `api_quote_repository` / `mock_quote_repository`, `local_reservation_repository` /
  `disabled_reservation_repository` / `mock_reservation_dispatch`, `api_payment_method_repository` / `local_payment_repository`,
  `synced_profile_repository`, `api_trip_messages`.
- **Navigation:** imperative `Navigator` with a global `moveraNavigatorKey` (`lib/app/app.dart:34`); route *names* only in
  `lib/app/router/routes.dart` (11 names); 60 `push*` call sites in `lib/`. `RideNavigator` (`lib/app/router/ride_navigator.dart`)
  and `RideRestoreCoordinator` handle restore after reload (snapshot key `flutter.movera_active_ride`).
- **Realtime:** not a socket/SSE stream. `ApiRideRealtime` (`lib/core/realtime/api_ride_realtime.dart`, 588 lines) **polls**
  each active trip every 2 s (`pollInterval`, line 29; `Timer.periodic` line 110), dedups by `eventId`, orders by `version`,
  backs off to 8 s, pauses after 3×404. `MockRideRealtime` (1 047 lines) simulates drivers in demo/test.
  `RealtimeConnection` + `realtime_connection_banner.dart` drive the "connection lost" banner.
- **Maps:** `CustomGoogleMap` (`lib/shared/widgets/custom_google_map.dart`, 443 lines) over `google_maps_flutter`; camera logic in
  `lib/core/maps/` (`camera_tilt.dart`, `map_camera_motion.dart` 647 lines, `route_polyline.dart`, `routing_service.dart`,
  `map_lifecycle.dart`). On web a JS bridge `web/rider_map_camera.js` (789 lines, loaded by `web/index.html:180`) reuses one
  Google map across screens (PR #411); Dart side in `lib/core/web/rider_map_bridge*_web.dart` plus page-hide, WebGPU, overlay and
  splash shims (conditional `_io`/`_web` imports).
- **l10n:** `flutter gen-l10n` (`l10n.yaml`, template `app_en.arb`), en/fr/sv each with **1 427** keys (equal counts);
  `rider-l10n.yml` workflow and `tool/gen_l10n_messages.py`.
- Also in repo: `backend/` (frozen unused Node mock, still booted by phase74/78/80 workflows per ARCHITECTURE.md),
  `contracts/` (synced contract copy, `tool/sync_contract.sh`), `integration_test/`.


## 3. CI

25 workflows in `.github/workflows/`. Run times below are from `gh run list -L 100` (runs created 2026-10-26 10:44Z onward;
created→updated wall time, includes queueing). Workflows with no run in that window show "–".

| Workflow | Trigger | What it runs | timeout | median / max min |
|---|---|---|---|---|
| architecture-gates | push main, PR | `flutter analyze` (not `--fatal-infos`), **full `flutter test`**, TZ (Stockholm / New York) reruns of zone tests | **none** | 10.6 / 11.1 |
| backend-readiness-gate | PR | `analyze --no-fatal-infos --no-fatal-warnings`, ~10 contract/arch test files | 60 | 13.8 / 21.8 |
| batch4-final-runtime-certification | PR | analyze, **full `flutter test`**, ride tests, linux integration_test `ride_flow_test` (xvfb) | 60 | 13.0 / 19.4 |
| batch5-phase69-test-integrity | push main, PR | `flutter test test/journeys` + integrity scripts | none | 1.2 / 1.7 |
| batch6-phase72/73/74/78/79/80 | PR (path-filtered) | analyze, a few test files, `flutter build web --release` (production flavor, fake defines) or `build apk --debug` | 35 | 2.5–2.8 |
| batch7-phase81/82/83/84 | PR (path-filtered) | analyze + 2–5 test files | 30–35 | 1.4–1.6 |
| batch7-phase85-final-certification | PR | analyze, matrices, **full `flutter test`**, 2 linux integration tests | 55 (each of 2 jobs) | 12.7 / 29.4 |
| deep-safe-recertification | PR | analyze, **full `flutter test`**, ride/perf files, linux integration test | 60 | 12.7 / 23.5 |
| global-e2e-uat | push main, PR | **full `flutter test`**, 4 linux integration tests | none | 12.1 / 19.6 |
| rider-l10n | push main, PR | `flutter test test/l10n` | none | 1.1 / 1.5 |
| publish-web-live | push main, dispatch | build web (demo + `/live/` against `MOVERA_LIVE_API_URL`), deploy to gh-pages | none | 2.8 |
| qa-critical-rider-flow / qa-live-rider-flow / qa-book-now-e2e / qa-device-pwa-responsive | push main (critical also PR) | wait for the Pages deploy, then Chromium/WebKit browser scripts against the **published** site | none | 4.8 / 3.2 / 5.5 / 9.5 |
| live-rider-browser-audit | dispatch, PR, push main | browser audit | none | last run 2026-10-20 |
| android-release-signing | dispatch | signed `build apk --release` | none | – |

**Current state (verified, `gh run list -w <file> -b main -L 5`):** all four `qa-*` workflows **fail on `main`** at `c1063fb8`.
`qa-live-rider-flow`, `qa-book-now-e2e` and `qa-device-pwa-responsive` failed on all 5 latest `main` pushes; `qa-critical-rider-flow`
passed at `7e3f1aa6` and has failed since `39677d69` (#411, map reuse). Failing steps: "Payment, Finding to Waiting, standalone
Cancel, and standalone Wallet"; "Exercise actual live Rider flow"; "Book now with GPS on and GPS off"; "Certify responsive,
keyboard, touch, standalone, resume and WebKit". Failure messages: **NOT VERIFIED** — `gh run view --log-failed` returns 403
from the log host through this machine's proxy. The red QA runs did not stop merges, so they are not required checks.

**Gaps vs AUDIT_PLAN Phase 2 table:**
- Lockfile: **no** workflow uses `pub get --enforce-lockfile` (0 matches).
- Format: no `dart format --set-exit-if-changed` anywhere (and 519 files would change, §4).
- Static analysis: everywhere `flutter analyze` without `--fatal-infos`; backend-readiness-gate even passes `--no-fatal-warnings`.
- Coverage: none collected or reported.
- Security: no secret scan, no `pub outdated`/advisory step.
- Caching: `subosito/flutter-action` `cache: true` is used; no pub-cache key on the lockfile. Flutter is `channel: stable`
  with **no pinned `flutter-version`** (architecture-gates.yml:26), so CI's SDK drifts.
- Timeouts: 11 of 25 workflows have no `timeout-minutes` (default 360 min): android-release-signing, architecture-gates,
  batch5-phase69, global-e2e-uat, live-rider-browser-audit, publish-web-live, the 4 qa-*, rider-l10n.
- Duplication: the full `flutter test` suite runs **5 times per PR** (architecture-gates, batch4, batch7-phase85, deep-safe,
  global-e2e), ~10–13 min each; `ride_flow_test` integration runs in 4 workflows.
- Required checks / branch protection: **NOT VERIFIED** (no admin API access checked); the red qa-* on main suggest none of
  those is required.
- No iOS no-codesign build; APK release only on manual dispatch.
