# Movera: safe plan to fix the audit findings

Audit of 2026-10-21. Driver app: 82 confirmed bugs (5 high, 22 medium, 55 low). Rider app: 94 confirmed bugs (4 high, 30 medium, 60 low).
Full list: `docs/audit-2026-10-21/AUDIT.md` in each repo. IDs below (for example `driver-40`) match `raw/*_audit_results.json`.

## Rules for every fix

1. **Test first.** Write a test that fails because of the bug. Then fix the code and watch the test pass. A fix without such a test is not merged.
2. **Small pull requests.** One area per PR, at most about 10 bugs. Never mix the driver and rider apps in one PR.
3. **CI must be green on the exact PR head.** Driver: `Drider CI` (analyze `--fatal-infos`, the full test suite, the lifecycle integration test, web build). Rider: `Architecture gates`, `Rider languages` and the QA workflows. Today both are clean: driver 1,632 tests and rider 2,254 tests passing, and `flutter analyze` reports no issues.
4. **Never change an existing test only to make it pass.** If an old test fails, decide first: was the test asserting the bug? If yes, change it in the same PR and say so in the PR text. If not, the fix is wrong.
5. **Merge one PR at a time** and rebase the next one on the new `main`. Shared files (`accept_ride_trip.dart`, `home_offer_radar.dart`, `waiting_for_driver.dart`) are touched by several PRs, so the order below matters.
6. **Check on a real device after each high or medium PR.** Use the live demo links: one rider trip and one driver trip, on iPhone Safari and on Android Chrome.
7. **If a merged PR breaks something,** revert that one PR. Do not patch on top of it. Each PR is small, so it reverts cleanly.

## Decisions the product owner makes before the work starts

Some fixes change what users see, or the shared contract. The rider docs say the approved UI is frozen, so these need a yes or no first:

| Topic | Fix changes | Bugs |
|---|---|---|
| History times | Times are shown in local time instead of UTC | rider-36 |
| History list | Settled and payment-failed trips are listed (a new or changed status label) | rider-37 |
| Arrive-by booking | Pickup time is computed from arrival time minus trip time; the screen shows both | rider-89 |
| Error messages | New honest error or "not sent" messages where the app now shows success | ui-truth items in both apps |
| Route-change price | The stand-in server stops charging booked stops twice; this must match the admin panel and backend contract | rider-9 |
| Contract wording | Docs updated where code and docs disagree (ARCHITECTURE.md, DECISIONS.md) | rider-34, driver docs items |

## Phase 0: preparation (no app code changes)

- **0.1** Check the 585 saved but unchecked findings (`raw/*_unverified_findings.json`) with the same two-step check. Expected: many repeats, plus a few new real bugs that get added to the phases below.
- **0.2** Merge repeated findings. For example `driver-74` and `driver-75` are one bug.
- **0.3** Get the owner decisions above.
- **0.4** Create a tracking issue per phase with the bug IDs as a checklist.

## Phase 1: driver high-severity bugs (trip ends, offers, scheduled rides)

All of these are about a trip or offer ending the wrong way. They touch the same files, so they go in this order, one PR each:

| PR | Bugs | What gets fixed |
|---|---|---|
| D1 | driver-40, then j2-7 | Trip exits close the trip screen itself, not whatever screen is on top. Driver cancel and no-show release the trip, so the driver can go online again. |
| D2 | driver-71, driver-69, driver-70, driver-87 | Offer claims in flight survive closing the card, going offline, system Back and two offers leaving together. A won trip is never dropped. |
| D3 | driver-74/75 | "Leave now" only removes the scheduled ride after the trip screen has opened. |
| D4 | driver-37, driver-38, driver-39 | Admin-completed and repeated-status trips keep their cash payment, the next-trip offer and the last-trip data. |

Tests to add: widget tests for each case. The audit's throwaway tests show the exact steps.

## Phase 2: rider high-severity bugs

| PR | Bugs | What gets fixed |
|---|---|---|
| R1 | rider-27, rider-26, rider-32 | Driver drop or reassign closes the waiting screen itself, restarts the search and never sends the rider Home by mistake. |
| R2 | rider-36, rider-37 | History stores times correctly and lists every finished trip (after the owner decision). |
| R3 | rider-89 and the select date/time items | "Arrive by" books the correct pickup time; the Continue button does not stay disabled. |

## Phase 3: medium bugs, one PR per area

Driver:

| PR | Area | Bugs |
|---|---|---|
| D5 | Trip screen, rest | medium items in `accept ride/` not already in D1-D4 |
| D6 | Home, rest | medium items in `home/` not already in D2-D3 |
| D7 | Ride requests, dispatch, overlays | 4 medium |
| D8 | Settings and data: preferences (category choice after restart, driver-78), profile, vehicle, add vehicle | 4 medium |
| D9 | Navigation, location, waybill money (thousands parsing), safety recording, scheduled rides, ride data privacy | 7 medium |

Rider:

| PR | Area | Bugs |
|---|---|---|
| R4 | Home and pickup (location prompt, map moved by a late fix, geocode errors) | 5 medium |
| R5 | Select ride and fare | 4 medium |
| R6 | Reservations and scheduled rides (time zone storage, DST) | 6 medium |
| R7 | Active ride, finding a driver, realtime, ride booking | 6 medium |
| R8 | Stand-in server and API (route-change pricing, version bump on edits) | 2 medium, after the owner decision |
| R9 | Safety, notifications, auth, ride complete, shared widgets, maps | 7 medium |

## Phase 4: low bugs, grouped by kind

| PR | Kind | Notes |
|---|---|---|
| D10 / R10 | Translations (en, fr, sv) | Hard-coded English, plurals, labels parsed in one language. The largest group, low risk, add l10n tests. |
| D11 / R11 | UI truth | Messages that claim success they did not get, for example "Emergency dialer opened" on web. |
| D12 / R12 | Remaining low items per area | Small local fixes. |
| D13 / R13 | Tests and docs | Tests that cannot fail, and docs that contradict the code. |

## Phase 5: final check

- Run the same audit again on the new `main` (finders plus the two-step check) to confirm the fixed bugs are gone and nothing new appeared.
- Do a full device check of both apps using `docs/UAT_CHECKLIST.md`.

## Order and size

About 30 PRs in total. Each PR is reviewed and merged before the next one starts in the same area. PRs for the other app can run in parallel, because the two apps are separate repos.

## What is not in this plan

- Fixes in the admin panel or the backend contract, except where a rider or driver fix needs them (they are flagged in R8).
- New features. Mocks stay mocks; the audit only reports where the app pretends success.
