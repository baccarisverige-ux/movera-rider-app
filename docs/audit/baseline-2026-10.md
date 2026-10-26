# Rider app — Phase 1 baseline audit (2026-10)

Audited: `main` @ c1063fb8. Documentation only; no source/test/workflow changes.
**Branch status (verified):** `rider-live-fixes-1` (tip `166fc8ab`) was squash-merged into `main` as
`c1063fb8` "Rider live test fixes 1 … (#413)" on 2026-10-26 13:02 +0100. `git diff --stat origin/main origin/rider-live-fixes-1`
is empty, i.e. the branch tree equals `main`. Everything the branch addresses is therefore already in the audited code;
HANDOFF.md §4.2 ("NOT merged") is out of date for the rider app.

## Progress
- [x] 1. Structure and architecture
- [x] 2. Dependencies
- [x] 3. CI
- [x] 4. Baseline run
- [x] 5. Coverage of critical logic
- [x] 6. Screen inventory
- [x] 7. Code quality findings
- [x] 8. Known issues N3–N10
- [x] 9. Untested features and risks
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


## 6. Screen inventory (input for Phase 5)

48 files under `lib/features` contain a `Scaffold(` (grep). **B** = booking flow. "Test files" = number of files in
`test/` + `integration_test/` that mention the class name (`grep -rlw`), a proxy for widget-test coverage, not proof.
`AuthScaffold`, `AccountScaffold`, `SafetyScaffold` are shared scaffolds, not screens.
Named routes exist only for 11 names (`lib/app/router/routes.dart`); most screens are pushed with `MaterialPageRoute`.

| Screen | File | Lines | Test files | Entry points (pushed from) |
|---|---|---|---|---|
| **B** `WaitingForDriver` | `lib/features/active_ride/presentation/waiting_for_driver.dart` | 3181 | 50 | ride_booking/application/ride_restore_coordinator reservations/presentation/reservation_live_ride finding_driver/presentation/finding_drivers |
| `AddPhoneNumber` | `lib/features/auth/presentation/add_phone.dart` | 180 | 3 | auth/presentation/sign_in |
| `PhoneVerification` | `lib/features/auth/presentation/phone_verify.dart` | 333 | 6 | auth/presentation/sign_in auth/presentation/add_phone |
| `RiderNameScreen` | `lib/features/auth/presentation/rider_name.dart` | 173 | 6 | ride_booking/application/ride_restore_coordinator auth/presentation/phone_verify |
| `SignIn` | `lib/features/auth/presentation/sign_in.dart` | 362 | 9 | app/app ride_booking/application/ride_restore_coordinator auth/presentation/sign_out_flow |
| `AuthScaffold` | `lib/features/auth/presentation/widgets/auth_scaffold.dart` | 299 | 1 | auth/presentation/rider_name auth/presentation/sign_in auth/presentation/add_phone |
| **B** `RoutePickerPage` | `lib/features/destination_search/presentation/route_picker_page.dart` | 1273 | 19 | active_ride/presentation/route_change_flow home/presentation/home |
| **B** `DriverProfilePage` | `lib/features/driver_arriving/presentation/driver_profile_page.dart` | 149 | 1 | active_ride/presentation/waiting_for_driver |
| **B** `FindingDrivers` | `lib/features/finding_driver/presentation/finding_drivers.dart` | 1402 | 22 | ride_booking/application/ride_restore_coordinator ride_selection/presentation/select_ride active_ride/presentation/waiting_for_driver |
| `RideHistory` | `lib/features/history/presentation/ride_history.dart` | 603 | 14 | notifications/presentation/notifications home/presentation/side_menu |
| **B** `Home` | `lib/features/home/presentation/home.dart` | 2858 | 117 | ride_booking/application/ride_restore_coordinator auth/presentation/auth_navigation |
| `RiderMenuPage` | `lib/features/home/presentation/side_menu.dart` | 876 | 14 | (built via a helper / not found by grep) |
| **B** `Chat` | `lib/features/messages/presentation/chat.dart` | 446 | 5 | active_ride/presentation/waiting_sheet_bits |
| `NotificationScreen` | `lib/features/notifications/presentation/notifications.dart` | 224 | 11 | app/bootstrap home/presentation/side_menu |
| `AddCardPage` | `lib/features/payments/presentation/add_card_page.dart` | 557 | 6 | (built via a helper / not found by grep) |
| `PayWithPage` | `lib/features/payments/presentation/pay_with_page.dart` | 296 | 3 | (built via a helper / not found by grep) |
| **B** `ConfirmPickupSpot` | `lib/features/pickup/presentation/confirm_pickup_spot.dart` | 590 | 9 | (built via a helper / not found by grep) |
| **B** `SetPickupPage` | `lib/features/pickup/presentation/set_pickup_page.dart` | 1664 | 26 | (built via a helper / not found by grep) |
| `AccountCheckupPage` | `lib/features/profile/presentation/account_checkup.dart` | 157 | 3 | profile/presentation/account_home |
| `AccountHomePage` | `lib/features/profile/presentation/account_home.dart` | 266 | 10 | home/presentation/home |
| `AccountScaffold` | `lib/features/profile/presentation/account_widgets.dart` | 524 | 0 | profile/presentation/account_checkup profile/presentation/personal_info profile/presentation/privacy |
| `DeleteAccountPage` | `lib/features/profile/presentation/delete_account.dart` | 203 | 2 | profile/presentation/account_home |
| `PersonalInfoPage` | `lib/features/profile/presentation/personal_info.dart` | 203 | 6 | profile/presentation/account_checkup profile/presentation/account_home home/presentation/side_menu |
| `PrivacyPage` | `lib/features/profile/presentation/privacy.dart` | 177 | 3 | profile/presentation/account_home home/presentation/side_menu |
| `ReferAndEarn` | `lib/features/profile/presentation/refer_and_earn.dart` | 104 | 1 | home/presentation/side_menu |
| `SecurityPage` | `lib/features/profile/presentation/security.dart` | 273 | 5 | profile/presentation/account_checkup profile/presentation/account_home home/presentation/side_menu |
| `PlanReturnRidePage` | `lib/features/reservations/presentation/plan_return_ride.dart` | 54 | 3 | reservations/presentation/upcoming_reservation reservations/presentation/ride_scheduled |
| `ReviewChangesPage` | `lib/features/reservations/presentation/review_changes.dart` | 282 | 3 | reservations/application/scheduled_ride_checkout |
| `RideScheduledPage` | `lib/features/reservations/presentation/ride_scheduled.dart` | 325 | 9 | (built via a helper / not found by grep) |
| `ScheduledRideTermsPage` | `lib/features/reservations/presentation/scheduled_ride_terms.dart` | 119 | 3 | (built via a helper / not found by grep) |
| `UpcomingReservationPage` | `lib/features/reservations/presentation/upcoming_reservation.dart` | 781 | 11 | history/presentation/ride_history reservations/presentation/home_reservation_chrono notifications/application/notification_navigation |
| **B** `RideCompleted` | `lib/features/ride_complete/presentation/ride_completed.dart` | 790 | 25 | ride_booking/application/ride_restore_coordinator reservations/presentation/reservation_live_ride active_ride/presentation/waiting_for_driver |
| **B** `SelectRide` | `lib/features/ride_selection/presentation/select_ride.dart` | 3257 | 47 | reservations/presentation/scheduled_category_gate scheduled_rides/presentation/schedule_ride home/presentation/home |
| `EmergencyContactsPage` | `lib/features/safety/presentation/emergency_contacts_page.dart` | 433 | 5 | safety/presentation/safety_hub safety/presentation/trip_share_page |
| `HowMoveraProtectsPage` | `lib/features/safety/presentation/how_movera_protects_page.dart` | 58 | 2 | safety/presentation/safety_hub |
| `PinVerificationPage` | `lib/features/safety/presentation/pin_verification_page.dart` | 157 | 3 | safety/presentation/safety_hub |
| `RideCheckDemoPage` | `lib/features/safety/presentation/ride_check_demo_page.dart` | 159 | 0 | safety/presentation/ride_check_page |
| `RideCheckPage` | `lib/features/safety/presentation/ride_check_page.dart` | 290 | 2 | safety/presentation/safety_hub |
| `SafetyHub` | `lib/features/safety/presentation/safety_hub.dart` | 144 | 2 | app/bootstrap profile/presentation/account_home safety/presentation/ride_safety_kit |
| `SafetyTipsPage` | `lib/features/safety/presentation/safety_tips_page.dart` | 68 | 2 | safety/presentation/safety_hub |
| `SafetyScaffold` | `lib/features/safety/presentation/safety_ui.dart` | 340 | 0 | safety/presentation/ride_check_page safety/presentation/safety_hub safety/presentation/trip_share_page |
| `TripSharePage` | `lib/features/safety/presentation/trip_share_page.dart` | 224 | 4 | safety/presentation/ride_safety_kit safety/presentation/safety_hub active_ride/presentation/waiting_sheet_bits |
| `AddPlace` | `lib/features/saved_places/presentation/add_place.dart` | 319 | 7 | saved_places/presentation/pickup_location saved_places/presentation/saved_places |
| `RiderSearchPickupLocation` | `lib/features/saved_places/presentation/pickup_location.dart` | 542 | 8 | saved_places/presentation/add_place |
| `SavedPlaces` | `lib/features/saved_places/presentation/saved_places.dart` | 258 | 4 | home/presentation/side_menu |
| `ScheduleRide` | `lib/features/scheduled_rides/presentation/schedule_ride.dart` | 852 | 12 | history/presentation/ride_history reservations/presentation/upcoming_reservation reservations/presentation/plan_return_ride |
| `SupportHome` | `lib/features/support/presentation/support.dart` | 1474 | 9 | profile/presentation/account_home home/presentation/side_menu |
| `WalletAndPaymentsScreen` | `lib/features/wallet/presentation/wallet.dart` | 1417 | 5 | home/presentation/side_menu home/presentation/home |

Screens with **0** test files: `RideCheckDemoPage` (ride_check_demo_page.dart). Only 1: `DriverProfilePage`, `ReferAndEarn`.
Booking flow order: Home → RoutePickerPage (destination) → SetPickupPage / ConfirmPickupSpot → SelectRide → FindingDrivers →
WaitingForDriver (assigned/arriving/in-trip, same screen) → RideCompleted.

### Back handlers in the booking flow (grep `PopScope|maybePop|Navigator.pop|popUntil|arrow_back`)
| Screen | Handler |
|---|---|
| Home | `PopScope(canPop: !_destinationSheetOpen …)` home.dart:2389–2391; sheet pops 1556, 1579, 1627, 1724, 1736, 1843 |
| RoutePickerPage | `PopScope(canPop: !_finishing)` route_picker_page.dart:1173; back button `maybePop` 1188, 1198; result pop 516 |
| SetPickupPage | back icon `Navigator.pop(context)` set_pickup_page.dart:983–985; result pops 731, 835; **no PopScope** |
| ConfirmPickupSpot | back icon `Navigator.pop(context)` confirm_pickup_spot.dart:439–440; result pop 337; **no PopScope** |
| SelectRide | `PopScope(onPopInvokedWithResult: _onRoutePop)` select_ride.dart:2140; back icon 2531; dialogs 738/743; sheets 1341/1351; 1640 |
| FindingDrivers | `PopScope(canPop: _leaving && !_rebooking)` finding_drivers.dart:983–985; confirm dialog 1390/1395 |
| WaitingForDriver | `PopScope(canPop: _leaving && !_cancelInFlight)`, async handler waiting_for_driver.dart:1964–1966; `popUntil(isFirst)` 928; `popUntil(route == own)` 1014 |
| RideCompleted | `PopScope(canPop: false)` with async handler ride_completed.dart:355–357; back icon 372 |

Browser Back on web goes through the same `PopScope`s; whether each behaves on iPhone Safari is **NOT VERIFIED** (needs device, N3).


## 7. Code quality findings

**Very large files (>1000 lines, `wc -l`, excl. generated l10n):** select_ride.dart 3 257, waiting_for_driver.dart 3 181,
home.dart 2 858, in_process_mock_client.dart 2 787, finding_driver_controller.dart 2 013, set_pickup_page.dart 1 664,
support.dart 1 474, wallet.dart 1 417, finding_drivers.dart 1 402, ride_check_card.dart 1 322, route_picker_page.dart 1 273,
booking_coordinator.dart 1 062, home_controller.dart 1 061, mock_ride_realtime.dart 1 047. The three booking screens
(SelectRide, WaitingForDriver, Home) hold most of the flow's UI state in one `State` each.

**Business logic / money in widgets (client-side arithmetic, grep):**
- `lib/features/active_ride/presentation/waiting_fee_counter.dart:42` computes the waiting fee live as
  `perMin × overSeconds / 60` (display estimate; uses the server's `waiting.freeUntil` when present, line ~50). Whether the
  settled fee shown afterwards always comes from the server: **NOT VERIFIED**.
- `lib/core/contracts/cancel_fee.dart:62–96` `CancelFeeCalculator` re-implements the contract's `riderCancelFee()`
  (replayed against `fixtures/cancel_fees.json`) — a second implementation that can drift from the server.
- `lib/features/finding_driver/presentation/price_bump_card.dart:117–118,167` computes the raise amount and the 2× cap in the
  widget; `finding_driver_controller.dart:908` builds the new fare `fare + increase` client-side (server re-validates, N4).
- `lib/features/pickup/presentation/set_pickup_page.dart:101–112` wallet split in **`double` kr** (`totalKr - walletKr`), next
  to an integer-minor version in `wallet/domain/wallet_split.dart:55`. Two representations of the same split.
- `select_ride.dart:2681,2837` and `set_pickup_page.dart:1463` show "price before discount" as `total + discount` client-side.
- N9 (early finish shows final server fare) was fixed in #413 (see §8).

**Duplicated logic vs the driver app** (`/home/user/movera-driver-app`, checkout at `5006f6b4`, a WIP branch; line overlap =
distinct trimmed lines ≥12 chars common to both files):
| Rider | Driver | Lines | Common |
|---|---|---|---|
| `web/rider_map_camera.js` | `web/driver_map_camera.js` | 789 / 666 | 207 |
| `lib/core/api/api_client.dart` | `lib/core/api/api_client.dart` | 371 / 406 | 118 |
| `lib/shared/widgets/custom_google_map.dart` | `lib/widgets/custom_google_map.dart` | 443 / 510 | 96 |
| `lib/core/contracts/money.dart` | `lib/core/money/money.dart` | 134 / 229 | 12 |
| `lib/core/maps/camera_tilt.dart:7–23` (67.5° / 15.5 curve, "Same as the driver app") | `lib/core/navigation/driver_camera_controller.dart:172–186` | | same curve copied |
No shared package; fixes (e.g. N5 traffic layer, N6 tilt) must be made twice.

**Contract copy is stale:** `contracts/CONTRACT.md:1` and `contracts/openapi.yaml:5` say **v0.5.0** (last synced in #399,
`7cff2fab`), while HANDOFF.md says the contract is v0.5.5. S2 risk: fields added in v0.5.1–v0.5.5 are not in the rider's copy/tests.

**Controllers, streams, timers:** 51 `Timer(`/`Timer.periodic` sites, 18 `StreamController`s, 20 `.listen(` in `lib/`.
Heuristic scan (files creating controllers/subscriptions/timers without a `dispose()`): only real leak found is
`lib/features/profile/presentation/account_widgets.dart:310–311` — a `TextEditingController` and `ValueNotifier` created per
edit sheet and never disposed (S4). `trip_detail.dart:114` disposes at line 198; `push_coordinator.dart:105–106` cancels in
its own stop method. A full lifecycle review was **not** done (heuristic only).

**Map/WebGL lifecycle on web:** `docs/web-lifecycle-investigation.md` measured one Google map per screen kept alive forever
(≈1 400 DOM nodes, 870 listeners, 5 maps, ~8 MB per booking) and WebGL context loss on vector maps; #411 reuses one map
(measured 2 maps instead of 15 over three bookings). Note: `qa-critical-rider-flow` has been red on `main` since #411 (§3) —
cause **NOT VERIFIED** (logs not readable here). iPhone behaviour after #411: **NOT VERIFIED** (needs device).

**Realtime by polling:** `ApiRideRealtime` polls every 2 s per active trip (api_ride_realtime.dart:29,110) — ~30 req/min per
rider during a trip; fine for a test week, a cost/latency item for Phase 7.

**Secrets:** `git grep AIza HEAD` → no match. History (`git log --all -S`): Google Maps key `AIzaSyB2…` was committed in
`96df05f1` (2026-09-08, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/AppDelegate.swift`) and removed in
`72e4bb7a`; a second key `AIzaSyBJ…` appears in gh-pages publish commits (e.g. `be853f02`) — expected for a browser Maps key,
which must therefore be HTTP-referrer restricted. Whether either key is restricted/rotated: **NOT VERIFIED** (Google console).
CI reads the key from secrets (`publish-web-live.yml:44,111`). `test/architecture/guard_test.dart:46` guards against `sk_live`.

**Personal data in logs:** all logging goes through `AppLog` (`lib/core/logging/app_log.dart`), which runs `extra` through
`Observability.sanitize` and prints to console only in `kDebugMode`. No raw `print(` in `lib/`. The `error` object is not
sanitized (an `ApiError` with a server body could carry PII) — **NOT VERIFIED** whether it does.


## 8. Known issues N3–N10 (HANDOFF.md §4.2)

`main` (`c1063fb8`) and `rider-live-fixes-1` (`166fc8ab`) have identical trees, so the status is the same on both.
"Code" = verified by reading/grepping `main`; "live" = behaviour on the iPhone / live server, not verified here.

| Note | Status on main | Evidence | Still open |
|---|---|---|---|
| N3 Booking steps crash/reload on iPhone; Back on every screen | **Partly addressed** (map reuse #411; a stale index.html retries once) | docs/web-lifecycle-investigation.md; Back handlers listed in §6 | No per-screen Back test sweep; iPhone **NOT VERIFIED** (needs device); `qa-critical-rider-flow` red since #411 |
| N4 Raise during long search fails | **Partly**: the raise card is now reachable (sheet opens, body drags) | test/finding_driver/n4_raise_offer_reachable_test.dart; #413 message says "WIP … full gates not run yet; live re-run of the raise probe still to do" | Which server rule (expired / 2× cap / `expectedVersion` / currency) rejects the live raise: **NOT VERIFIED**; owner decision D4 |
| N5 Traffic layer | **Fixed** | `custom_google_map.dart:327` `trafficEnabled: false`; `web/rider_map_camera.js:614–625` only tracks a plugin TrafficLayer; test/maps/custom_google_map_release_test.dart | — |
| N6 Tilt/zoom on tiny routes; pinch faults while searching | **Partly**: route fits capped at zoom 17 and booking/trip maps flat | `lib/core/maps/camera_tilt.dart:71` `routeFitMaxZoom = 17`; camera_tilt / phase101 tests (per #413) | "minimum map span" for tiny routes and the pinch-zoom faults while searching: no evidence of a fix found |
| N7 Wrong first address after sign-in | **Fixed in code** (coarse >150 m fix not geocoded) | test/home/n7_coarse_first_fix_test.dart | Not reproducible in Chromium; phone **NOT VERIFIED** |
| N8 Ride check end to end (rider side) | **Not verified** | 41 test files mention RideCheck; #407 wired it to the live server | E2E against server: Phase 3 |
| N9 Early finish shows booked price | **Fixed** (poll carries projection `fare`; receipt shows server fare) | test/ride/n9_early_finish_fare_test.dart | Live re-check **NOT VERIFIED** |
| N10 "Search again" after driver cancel / no-show; no "connection lost" over a finished trip; sheet text | **Fixed in code** | `ride_terminal_state_sheet.dart`, test/active_ride/n10_search_again_test.dart; l10n `searchAgain` en/sv/fr | Live **NOT VERIFIED** |


## 9. Untested features and risks

| # | Risk / untested area | Sev | Evidence |
|---|---|---|---|
| R1 | Most tests run the **mock dialect**, not the contract wire the live server speaks (`ApiClient.contractWire` false in test). Only 23 test files reference `contractWire`/staging flavor. Live-only bugs (N4, N9) were found by the owner, not tests | S1 | §1, `grep -rln contractWire test` |
| R2 | Rider's contract copy is **v0.5.0**, contract is v0.5.5 | S2 | §7 |
| R3 | All 4 `qa-*` browser workflows red on `main` (the only tests against the published live build) | S2 | §3 |
| R4 | iPhone Safari crash/reload (N3) after #411 map reuse: untested on device | S1 | §8 |
| R5 | Raise price live path (N4): unverified which server rule fails; #413 says gates not run for it | S2 | §8 |
| R6 | Client-side money: cancel fee calculator, waiting-fee counter, raise arithmetic, double-kr wallet split | S2 | §7 |
| R7 | No rider↔server↔driver end-to-end test (ride check N8, driver cancel/no-show, search expiry at 10 min) | S2 | no such test in repo; plan Phase 3 |
| R8 | Pinch zoom faults while searching, tiny-route minimum span (N6 rest) | S3 | §8 |
| R9 | Google Maps keys in git history; restriction unverified | S3 | §7 |
| R10 | CI: no lockfile enforcement, no format/coverage/security, unpinned Flutter, 11 workflows without timeout, full suite ×5 per PR | S3 | §3 |
| R11 | Native iOS/Android builds: only `apk --debug` on a path-filtered PR and a manual signed APK; no iOS build in CI | S3 | §3 |
| R12 | Huge screen files (3 000+ lines) concentrate booking state; hard to test per control | S4 | §7 |
| R13 | `RideCheckDemoPage` has no test; `DriverProfilePage`, `ReferAndEarn` one each | S4 | §6 |
| R14 | Undisposed controller in account edit sheet | S4 | §7 |


## 4. Baseline run

Machine: cloud container, 4 cores, **Flutter 3.47.7 stable** (`/home/user/flutter/bin`). Run on `main` `c1063fb8`.

| Command | Result | Wall time |
|---|---|---|
| `flutter pub get --enforce-lockfile` | exit 0 ("69 packages have newer versions incompatible with dependency constraints") | 25 s |
| `dart format --output=none --set-exit-if-changed .` | **exit 1 — 519 of 1 066 files would change** (lib 217, test 298, integration_test 4). Not applied | 6 s |
| `flutter analyze --fatal-infos` | exit 0, "No issues found! (ran in 47.4s)" | 57 s |
| `flutter test` (full, once) | exit 0, **+2958 ~3, 0 failed** ("All tests passed!") | **1 831 s (30.5 min)** |
| `flutter build web --release` | exit 0, "✓ Built build/web" (warning: CupertinoIcons font family referenced but not bundled) | 91 s |
| tool/CI gates (batch5-phase69 integrity steps; rider-l10n ARB check), run locally by extracting the workflow `run:` blocks | all exit 0; "Legacy grep-style test cases: 39" (cap <40); "1427 messages in en, fr and sv" | <5 s |

The 3 skipped tests are all in `test/e2e/live_server_booking_test.dart` (price→book→complete→rate→history; cancel while
searching/after accept; end early) — they need a running movera-server and are skipped in every CI run, so the only
contract-wire booking test never runs in CI. `tool/web_lifecycle_probe.mjs` and `tool/select_ride_sheet_probe.mjs` were **not run** (need a served build + Chromium session; NOT VERIFIED here). No failures, so no flakiness reruns were needed.


## 2. Dependencies

`pubspec.yaml`: SDK `^3.8.1`; 20 direct deps + 3 SDK, 5 dev deps. Usage = files in `lib/` importing `package:<name>/`.

| Package | Locked | Latest (`flutter pub outdated`) | lib files |
|---|---|---|---|
| google_maps_flutter | 2.13.1 | 2.19.0 (upgradable in range; google_maps_flutter_web 0.5.14+2 → 0.6.5) | 29 |
| firebase_core / firebase_messaging | 4.15.0 / 16.7.0 | 5.1.0 / 17.0.1 (major) | 1 / 1 |
| flutter_secure_storage | 9.2.4 | 11.2.0 (major; `_macos` 3.1.3 transitive is **discontinued**) | 2 |
| google_fonts | 8.2.1 | 9.0.0 | 56 |
| pinput | 5.0.1 | 7.0.0 | 1 |
| geolocator | 14.0.2 | 14.1.2 | 6 |
| http | 1.5.0 | 1.6.0 | 8 |
| smooth_sheets | 1.2.0 | 1.3.0 | 6 |
| shared_preferences | 2.5.3 | 2.5.6 | 3 |
| record / url_launcher / pointer_interceptor / web / dotted_line | 7.1.1 / 6.3.2 / 0.10.1+2 / 1.1.1 / 3.2.3 | 7.1.2 / 6.3.3 / 0.10.1+3 / 1.1.2 / 3.3.0 | 1 / 2 / 17 / 6 / 1 |
| flutter_screenutil, flutter_svg, flutter_rating_bar, flutter_animate, intl, path_provider | current | — | 2, 7, 1, 1, 6, 1 |
| dev: flutter_lints | 5.0.0 | 6.0.0 | — |

- Unused direct deps: **none** (every direct dep is imported in `lib/`; dev deps crypto, fake_async, maps platform interface used in tests).
  Light use: dotted_line, flutter_rating_bar, flutter_animate, pinput, record, path_provider each in 1 file.
- 69 packages have newer versions outside the constraints (pub get output).
- Advisories: **NOT VERIFIED** — no Dart advisory tool is installed and CI has none; `pub outdated` reports no "retracted"/security
  markers for these versions (only the discontinued notice above).
- `pubspec.lock` is committed; `--enforce-lockfile` passes locally but no CI uses it.

## 5. Coverage of critical logic

`flutter test --coverage` over the full suite (exit 0, +2958 ~3, **1 192 s**). lcov contains 442 of 491 `lib/` files (only files
loaded by a test are listed, so untouched files are missing, not 0 %). Tests run on the Dart VM: web-only `*_web.dart`
code and `web/*.js` are not measured. Coverage is from mock-dialect tests (R1), so a high % does not mean the live wire is tested.

| Area | Lines hit / found | % |
|---|---|---|
| lib/ total | 37 348 / 41 140 | 90.8 |
| lib/core | 4 693 / 5 052 | 92.9 |
| core/api (ApiClient 97.9 %) | 1 682 / 1 751 | 96.1 |
| core/auth (secure_token_store 87.9 %) | 68 / 78 | 87.2 |
| core/realtime (api_ride_realtime 96.0 %) | 807 / 832 | 97.0 |
| core/maps (**camera_tilt 69.4 %**, map_camera_motion 98.0 %) | 648 / 685 | 94.6 |
| core/contracts (money 86.0 %, cancel_fee 97.6 %, trip_transitions 93.8 %) | 384 / 397 | 96.7 |
| core/web (**rider_map_bridge 58.1 %**) | 50 / 78 | 64.1 |
| features/booking (booking_coordinator 95.6 %) | 371 / 391 | 94.9 |
| features/ride_booking (ride_session 95.6 %) | 1 017 / 1 096 | 92.8 |
| features/finding_driver (controller 89.4 %) | 2 077 / 2 360 | 88.0 |
| features/active_ride (waiting_fee_counter 100 %) | 2 523 / 2 926 | 86.2 |
| features/auth (auth_controller 87.2 %) | 1 752 / 1 833 | 95.6 |
| features/ride_complete / wallet / payments | 637/659, 770/869, 585/624 | 96.7 / 88.6 / 93.8 |

Lowest in lib/core (≥40 lines): firebase_push_service 52.5 %, rider_map_bridge 58.1 %, camera_tilt 69.4 % (the N6 code),
api_payment_gateway 83.6 %, money 86.0 %.
