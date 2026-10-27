# Audit Phase 5 — rider app: every screen and button

Branch `audit/phase-5-rider`. Plan: `movera-contracts/docs/audit/AUDIT_PLAN.md` (Phase 5). Date: 2026-10-26.

## How the live build was probed (and what could not be)

- **The published site and the live server could not be reached from the audit sandbox**: the egress proxy refuses
  `baccarisverige-ux.github.io` and `movera-server.onrender.com` (HTTP 403 on CONNECT). So the "live build" here is
  the same build the Pages workflow makes for `/live/` (`lib/main_staging.dart`, `MOVERA_FLAVOR=staging`,
  `MOVERA_AUTH_REQUIRED=true`), served locally and pointed at a local **movera-server `main` @ 616eb29**
  (staging seed: test phones, code 1234), as in `movera-server/test/crossapp/README.md`.
- Chromium only (Playwright 1.56, iPhone-sized 390×844 viewport, touch). **WebKit is not installed** for this
  Playwright, so nothing here is Safari-measured; the iPhone itself remains on the owner's device list.
- Stand-ins: GPS is a script position; address search answers in the browser (no Google key locally); Google Maps
  is blocked (no key), so map areas are empty. The driver is driven through the API (`/driver/*`, `/offers/*`,
  `/trips/*/...`), the cleanup through `/admin/trips/{id}/cancel`.
- Scripts: `tool/phase5_probes/` (`lib.mjs` helpers; `back.mjs` Back and reload at every step; `restore2.mjs`
  reload into an ended ride; `dbl2.mjs` double taps; `menu.mjs` every menu entry; `flow2.mjs` ride-time controls).
  Each prints what the app showed (its semantics labels), every API call with its status, and page errors.

## N3 — Back and reload at every booking step (live build, Chromium)

"Browser Back" is `history.back()` (an edge swipe in a Safari tab; the installed app has no history gesture).
"Reload" is what the page does when iOS kills and reopens it (the MOVERA boot bar shows). No step produced a page
error, a crash or an unexpected reload.

| Step | Browser Back | In-app Back / Close | Reload |
|---|---|---|---|
| Plan your ride | Home | Close → Home | Home |
| Plan your ride, typed | Home | Close → Home | Home (typed text lost) |
| Select ride | Plan your ride (by design) | Back → Plan your ride | **Home** (route lost) |
| Set pickup | Select ride | Back → Select ride | **Home** (route lost) |
| Finding | cancel sheet (by design) | — (Cancel request) | Finding (same ride) |
| Waiting | cancel sheet | — (Cancel ride) | Waiting (same ride) |
| Driver arrived sheet | closes the sheet | — | Waiting |
| In trip | opens Change route (by design: "ride details") | — | Waiting/in trip |
| Ride completed | Home | Back → Home | Ride completed |

What "crashes back to Home" is, as measured: a **reload before the ride is requested** (Select ride, Set pickup)
always lands on Home, because nothing of the booking draft is stored; after the request the same ride comes back.
On the iPhone a reload is the page being killed (memory: `docs/web-lifecycle-investigation.md`). That is open item O1.

Defect found on the way (**P5-R1**, fixed): after a reload into a ride that then ended (e.g. "Cancelled by Movera"),
"Back to home" left the rider on the dead Waiting screen (driver card, Message, Call, "Cancel ride"), 25 s and
counting, 3 of 4 runs. Evidence: `R1-before-back-to-home-stuck.png`.

## Calls outside the contract (live build → movera-server)

Every API call of the probes, by screen. Contract: `contracts/openapi.yaml` v0.5.5.

| Call | Where | Server | Before | Now |
|---|---|---|---|---|
| `GET /rides/{id}/nearby` | every search (Finding) | 404 | asked once per search | not asked (P5-R2) |
| `GET /safety/preferences` (+ all `/safety/*`, `/rides/{id}/share`, `/rides/{id}/safety-*`) | Safety checkup, Safety Kit, Share trip, Waiting | 404 | asked; every change failed ("Could not update RideCheck.") | not asked; Safety says its settings cannot be saved yet (P5-R3) |
| `POST /rides/{id}/route-quote` | Change route → See new price (Finding, Waiting, in trip) | 404 (`/trips/{id}/route-quote` and `PATCH /trips/{id}`: `operation_not_enabled`) | rider edits the route, then "Couldn't update the route. Try again." | not asked; "Changing the route in the app isn't available yet. You can tell your driver." (P5-R4) |
| `GET /account/security` | Personal info, Security, Account | 404 | asked; "Security controls unavailable" | not asked; same honest state (P5-R5) |
| `POST /rides/{id}/disputes` | History → a ride → Get help → an issue → Send to Movera | 404 (`POST /support/tickets` is in the contract: `operation_not_enabled`) | "Couldn't send. Check your connection and try again." | not sent; "Sending a report from the app isn't available yet, so this was not sent…" (P5-R7) |
| `/ride-types`, `/rider/promotions/active` | — | — | fixed in Phase 4 (P4-9) | not asked |

Not reached by any live control: `/rider/scheduled-rides/rules` (asked only where booking for later is on; on the
live build "Schedule for later" says "Booking for later isn't available yet, so nothing was booked").
After the fixes, the menu pass (every entry, Safety, Security, Personal info) and the Help report path made
**no 404 call**; the Back/reload pass over the booking steps on the fixed build was cut off by a container restart
and was not re-run (the unit/widget tests cover the booking-step calls: `test/audit/phase5_off_contract_calls_test.dart`).

## Demo pages and demo data

| What | Live build |
|---|---|
| RideCheck "Try it" demo trips (`RideCheckDemoPage`) | hidden (`allowsMockTransport` only) |
| Wallet demo top-up, "Add funds (demo)" | hidden; live shows "Add funds unavailable" |
| Sign-in "Demo verification code: 1234", "Skip for now (demo)" | hidden (demo flavour + `?auth_preview=1` only) |
| Movera Family, Movera Business, Greener rides, Refer & Earn | honest "coming soon / not available yet" pages (marked) |
| Wallet balances in SEK/EUR/TND | 0, local; the contract's `GET /wallet` is not used (open item O6) |
| Saved places | device-only; the contract's `/rider/places` is not used (open item O7) |

No demo page or made-up data was found reachable in the live build beyond these.

## Repeated taps (live build)

| Control | Taps | Server calls | Result |
|---|---|---|---|
| Where to? | 4 | — | one Plan your ride |
| A suggestion (Odenplan) | 4 | 1 `POST /quotes`, 1 `POST /routes` | one Select ride |
| **Select Movera** | 2, 200–600 ms apart | **1 `POST /trips`** | **a ride was requested**: the 2nd tap hit Set pickup's "Confirm and search" (same spot) while it slid in (P5-R6) |
| Select Movera | 2, 80 ms apart | 0 | Set pickup |
| Confirm and search | 5 | 1 `POST /trips` | one search |

After P5-R6 "Confirm and search" ignores taps until Set pickup has finished opening: double taps 80, 200 and 350 ms
apart now stop on Set pickup (0 `POST /trips`). Two taps **600 ms or more** apart still request a ride, because
Set pickup is fully open by then and the second tap lands on its button (residual, O10).

## Findings

| Id | Sev | Finding | State |
|---|---|---|---|
| P5-R1 | S2 | Back to home after a reload into an ended ride stays on the dead ride screen | fixed |
| P5-R2 | S4 | `GET /rides/{id}/nearby` (404) on every search | fixed |
| P5-R3 | S3 | Safety screens offer settings the server never keeps; every change 404s | fixed (honest state) |
| P5-R4 | S3 | Change route lets the rider edit, then fails with "Try again" (server does not serve it) | fixed (honest state) |
| P5-R5 | S4 | `GET /account/security` (404) on Personal info / Security | fixed |
| P5-R6 | S2 | Double tap on "Select <ride>" requests a ride without the rider seeing Set pickup | fixed (taps ≤ 350 ms) |
| P5-R7 | S3 | Help "Send to Movera" fails with "check your connection" (server takes no reports) | fixed (honest state) |
| O1 | S3 | Reload (iOS page kill) on Select ride / Set pickup returns to Home: no booking draft is kept | open (feature) |
| O2 | S3 | Server: `/trips/{id}/route-quote` and `PATCH /trips/{id}` are in the contract but `operation_not_enabled` | open (server) |
| O3 | S3 | Contract/server: no Safety endpoints (contacts, sharing, RideCheck answers to the safety team); the contract's `/trips/{id}/pin` is not used by the app | open (contract) |
| O4 | S4 | In trip, browser Back opens "ride details" (Change route), now the "not available" note | open (design) |
| O5 | S4 | Personal info says "Server phone status unavailable" though `/rider/profile` knows the phone | open |
| O6 | S4 | Wallet does not read the contract's `GET /wallet` | open |
| O7 | S4 | Saved places are device-only; the contract's `/rider/places` is unused | open |
| O8 | S4 | `quote.unavailable` + `.stack` logged as **errors** for every category the zone does not offer (16 lines per quote to `/telemetry/logs`) | open |
| O10 | S3 | Two taps ≥ 600 ms apart on "Select" then the same spot still request a ride (Set pickup's button sits where Select's was) | open (design: move the button or add a dwell) |
| O9 | S3 | `docs/web-lifecycle-investigation.md` tells the owner to read the Web Inspector console; release builds print nothing there (`AppLog` writes the console only in debug). On the live build the lines go to the server's `telemetry` table, routine lines capped at 20 a minute | open (doc) |

## Screen list

Status: **tested** = widget tests in `test/` (count of test files naming the screen) and, where marked, the live
probe above; **needs device** = only a phone can settle it (Safari/WebKit, memory kill, real GPS, maps);
**n/a** = no rider-facing state.

| Area | Screen | Tests | Live probe | Status |
|---|---|---:|---|---|
| Sign-in | SignIn, PhoneVerification, AddPhoneNumber, RiderNameScreen | 9, 6, 3, 6 | sign-in each run | tested |
| Home | Home | 119 | Back/reload | tested; map rendering needs device |
| Home | Side menu (RiderMenuPage) | 14 | every entry, Back | tested |
| Booking | RoutePickerPage (Plan your ride, Change route) | 19 | Back, reload, taps | tested |
| Booking | SelectRide | 48 | Back, reload, double tap | tested |
| Booking | SetPickupPage | 27 + P5-R6 | Back, reload, double tap | tested |
| Booking | ConfirmPickupSpot | 9 | — | tested |
| Ride | FindingDrivers, cancel sheets, ride details | 24, 3, 1, 3 | Back, reload, Safety Kit | tested |
| Ride | WaitingForDriver, driver arrived, in-trip panel | 51, 8, 6 | Back, reload, Share, Message, Call, More | tested |
| Ride | Ride terminal sheets | 6 + P5-R1 | reload into an ended ride | tested |
| Ride | RouteChangeSheet / Change route | 5 + P5-R4 | See new price | tested |
| Ride | Chat | 5 | Message, Back | tested |
| Ride | DriverProfilePage | 1 | — | tested |
| After the ride | RideCompleted, rating, tip, driver info, trip detail | 25, 2, 5, 3, 6 | Back, reload, Report an issue | tested |
| Safety | SafetyHub, Safety Kit sheet | 3 + P5-R3, 6 | every row, Back | tested |
| Safety | EmergencyContacts, PIN, TripShare, RideCheck, tips, how we protect | 5, 3, 4, 2, 2, 2 | open, change, Back | tested |
| Safety | RideCheck card / layer | 5 | — | tested; motion triggers need device |
| Safety | RideCheckDemoPage | 0 | not reachable live | n/a (demo only) |
| Account | AccountHome, Personal info, Security, Privacy, Legal, Language, Delete account, Checkup | 10, 6, 5, 3, 3, —, 2, 3 | every entry, Back | tested |
| Account | Refer & Earn, Family, Business, Greener rides | 1 | coming-soon pages | tested |
| Wallet | Wallet, Wallet & payments, Pay with, Add card | 4, 5, 3, 6 | open, Back | tested; card payments need device/Stripe |
| History | RideHistory | 14 | open, tabs, Back | tested |
| Notifications | NotificationScreen | 11 | open, Back | tested; push needs device |
| Saved places | SavedPlaces, AddPlace, pickup location | 4, 7, 8 | Add Home/Work/…, Back | tested |
| Scheduled | ScheduleRide, date & time, RideScheduled, Upcoming, Review changes, Terms, Plan return | 12, 14, 9, 11, 3, 3, 3 | Book now or later | tested; a scheduled ride end to end not run |
| Support | SupportHome, help articles, select ride/issue, messages, chat | 9, 2, 3, 2, 3, 2 | open, Back | tested |
| Restore | RideRestoreGate | 6 + P5-R1 | reload at every step | tested; iOS memory kill needs device |

Small screens, large text and the three languages: `test/responsive/` (viewport × text-scale matrix) and
`test/l10n/` (every message in sv/fr/en, screens per language) cover the screens above; the new texts of this
phase are in all three languages and in `test/l10n/all_messages.g.dart`.
