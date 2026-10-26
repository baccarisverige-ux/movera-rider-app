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
- [x] 6. Screen inventory
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
