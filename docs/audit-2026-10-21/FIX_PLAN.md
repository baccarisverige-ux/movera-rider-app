# Movera: safe plan to fix every audit finding

Updated 2026-10-21, after audit rounds 1-3 and two reviews of our own fixes.

| App | Confirmed | Already fixed and merged | In wave 2 (in progress) | Still to fix | Of those: medium | low |
|---|---|---|---|---|---|---|
| Driver | 256 | 18 | 7 (6 bugs) | 231 | 75 | 156 |
| Rider | 320 | 8 | 8 (6 bugs) | 304 | 119 | 185 |

No high-severity bug is left outside wave 2. Full lists: `DRIVER_AUDIT.md` and `RIDER_AUDIT.md` (also in each repo under `docs/audit-2026-10-21/`). IDs below (for example `driver-u39`) match `raw/*_audit_results.json`.

## The rules that keep this safe

These held for wave 1 and the feature work, and they stay for every wave:

1. **Test first.** Every bug gets a test that fails on the old code and passes with the fix. The pull request text says how the test failed before. No test, no merge.
2. **One pull request per area, at most about 10 bugs.** Never mix driver and rider in one PR. Bugs in the same file go in the same PR, so two PRs never fight over one function.
3. **Checks must be green on the exact PR head.** Driver: analyze with `--fatal-infos`, the full suite (1,683 today), the lifecycle integration test, the web and release builds. Rider: all 21 checks (2,275 tests today), including the time-zone runs added in #350/#351.
4. **Never change an old test only to make it pass.** If an old test fails, first decide: was it asserting the bug? If yes, change it in the same PR and say so. If not, the fix is wrong.
5. **Merge one PR at a time per app** and start the next one from the new `main`. The two apps can run in parallel because they are separate repos. The shared `contracts/` folder is touched only by a PR set that lands in all three repos together (as #128/#330/#350 did).
6. **Review our own fixes after each wave.** Rounds "fixrev" and "fixrev2" found 10 bugs that our wave-1 fixes introduced. That review is cheap (about 15 minutes per app) and it stays in the plan after every wave.
7. **If a merged PR breaks something, revert that one PR.** Do not patch on top of it. Each PR is small, so it reverts cleanly.
8. **Frozen UI.** The rider docs say the approved UI is frozen. A fix that changes what users see is listed in its PR under "Visible change" so the owner can say no before merge. Honest error messages where the app now claims success count as visible changes.
9. **No backend yet.** Fixes to the server seam (realtime projections, profile sync, wallet refunds) are tested with the in-process stand-in and the contract files. They are marked "server seam" in the PR so they get re-checked when a backend exists.

## Owner decisions (answered 2026-10-21)

| # | Question | Decision | Where it lands |
|---|---|---|---|
| 1 | With admin "Leave now" off, an online driver can never start a reservation. | **Remove the "Leave now" switch.** The trip always opens by itself when it is time to leave. The admin keeps the timing values. | Admin + driver PR set (contract change), wave 3 |
| 2 | The admin's reservations on/off switch is saved but unused. | **Make it work, and make it per driver as well as global.** The admin can pause reservations for one driver or for everyone. Rides already accepted still run. | New small feature: admin + driver PR set, wave 3 |
| 3 | Forced offline (daily limit, missed Exclusives) during a 1-3 s "Matching trip…" wait. | **The accept wins.** Wait for dispatch's answer; if the ride is his, do it and go offline when it ends; if not, go offline at once. | D3.1 |
| 4 | Settings changed (category, destination mode) during the match wait. | **Lock the settings while matching.** The buttons are greyed out for those seconds; the change applies after. | D3.1 |
| 5 | The stand-in server charges a booked stop twice on a route change. | **Fix the stand-in now**, write the rule in the shared contract, add a test. | R4.2 (contract change: lands in all three repos) |

Nothing is decision-blocked any more.

## Wave 2: the last high-severity bugs (in progress now)

Two helpers are working, one per app, one commit per bug, test first.

| PR | Bugs | What gets fixed |
|---|---|---|
| D-W2 | driver-u1, u39, u64, u130, u149+u150, u174 | Pages deploy trusts fork PRs; "Continue straight" while the arrow turns; screen-reader swipe skips the confirm dialog; in sv/fr an Exclusive reservation is treated as a normal ride; Back on Ride completed leaves the session "on trip"; web car marker leaks memory |
| R-W2 | rider-u42, u148+u149, u166+u176, u195, u213, u232 | Cheaper route change refunded twice; blank profile overwrites the server; reservation completion shows the last Book-now ride; failed safety alert shown as "alerted" after reload; safety buttons unusable with a screen reader; default payment ignored at booking |

Then: fixrev round on both apps (about 15 minutes each). Any regression is fixed in the same PR before merge.

## Wave 3: medium bugs, driver (75 bugs, 8 PRs)

Grouped by area so each PR touches one part of the app. Order matters where files are shared (`home/*` first, then `accept ride/*`).

| PR | Area | Bugs | Note |
|---|---|---|---|
| D3.1 | Home: offers, claims, Exclusive timeouts | 11 | includes driver-r3-14 (background network error counts as a miss) |
| D3.2 | Home: scheduled rides, radar, island notices | 11 | the rest of `home/` (22 in total with D3.1) |
| D3.3 | Trip screen: realtime, projections, restore | 8 | includes driver-r3-12 (admin cancel lost during a background save), server seam |
| D3.4 | Trip screen: stops, waybill, fare, cancel reasons | 7 | plus `core/waybill` (3), money |
| D3.5 | Scheduled rides, ride requests, dispatch | 7 | `scheduled rides` 4, `ride requests` 2, `core/dispatch` 1 |
| D3.6 | Navigation, location, safety, sound | 10 | `core/navigation` 4, `core/location` 2, `core/safety` 3, `core/sound` 1 |
| D3.7 | Settings and data: preferences, profile, vehicle, add vehicle, ride data | 6 | includes driver-78 (category choice lost after restart) |
| D3.8 | Platform: iOS, Android, web, main.dart, overlays, demo banner, test/integration gaps | 9 | small, independent fixes; the test-integrity items make existing tests able to fail |

Decision-blocked (not in any PR yet): driver-fixrev-5, driver-fixrev-12, the forced-offline and settings-during-match items (4 bugs).

## Wave 4: medium bugs, rider (119 bugs, 12 PRs)

| PR | Area | Bugs | Note |
|---|---|---|---|
| R4.1 | Active ride: waiting, driver drop, terminal states | 10 | |
| R4.2 | Active ride: route change, in-trip panel, fees | 9 | server seam for route pricing; rider-9 waits for decision 5 |
| R4.3 | Safety: ride check, triggers, store | 15 | includes rider-r3-1 (failed save wipes other safety data) and rider-r3-3 (stale "longer than expected" budget) |
| R4.4 | Home and pickup | 17 | `home` 12, `pickup` 5 |
| R4.5 | Reservations and scheduled rides | 12 | `reservations` 8, `scheduled_rides` 4; time-zone and DST items get the three-zone CI run |
| R4.6 | Ride selection and fare | 8 | |
| R4.7 | Sign-in and profile | 11 | `auth` 7 (includes rider-r3-10: Back during Verify), `profile` 4 (includes rider-r3-9: stale profile copy) |
| R4.8 | Ride complete and booking | 10 | `ride_complete` 7, `ride_booking` 2, `booking` 1 |
| R4.9 | Finding a driver and destination search | 9 | `finding_driver` 5, `destination_search` 4 |
| R4.10 | Realtime, API, contracts, notifications | 12 | `core/realtime` 5, `core/api` 3, `core/contracts` 2, `core/notifications` 2; server seam |
| R4.11 | Saved places, maps, shared widgets, bootstrap, web, core/auth | 6 | small independent fixes |

Waves 3 and 4 run in parallel (different repos). After each wave: fixrev round.

## Wave 5: low bugs, both apps (156 driver, 185 rider)

Grouped by kind, not by area, because the fixes are alike and low risk:

| PR | Kind | Driver | Rider | Note |
|---|---|---|---|---|
| D5.1 / R5.1 | Translations (en, fr, sv) | 43 | 33 | hard-coded English, plurals, mixed-language rows; add l10n parity tests |
| D5.2 / R5.2 | UI truth | 33 | 38 | messages that claim success they did not get; **visible changes**, listed for the owner |
| D5.3 / R5.3 | Accessibility | 14 | 11 | labels, tap actions, contrast; semantics tests |
| D5.4 / R5.4 | State and time: state-corruption, wrong-time, data-loss, contract-mismatch | 35 | 47 | one PR per area if a group grows past 10 |
| D5.5 / R5.5 | Tests and docs | 9 + 5 | 12 + 2 | tests that cannot fail; docs that contradict the code |
| D5.6 / R5.6 | Everything else | 17 | 42 | small local fixes, by area |

Each of these rows may become 2-3 PRs to stay under about 10 bugs each.

## Wave 6: final check

1. Run the full audit once more on the new `main` of both apps (finders, two verifiers, tie-break) to confirm the fixed bugs are gone and nothing new appeared.
2. Device check of both apps on the live demo links, with `docs/UAT_CHECKLIST.md`: one rider trip, one driver trip, one reservation, on iPhone Safari and Android Chrome.
3. Re-check the "server seam" PRs when a backend exists.

## Size and pace

About 45 pull requests in total (2 in wave 2, 8 + 11 in waves 3-4, about 18 in wave 5, plus fixrev fixes). With two helpers in parallel and test-first on every bug, waves 2-4 take about one working day of sessions each, wave 5 about one more. Count on 3-4 days of sessions, less if the low bugs go quickly.

## What is not in this plan

- Admin panel bugs, except where a rider or driver fix needs an admin change (then all three repos move together).
- The backend itself. Server-seam fixes make the apps correct against the contract; the server must still be built to match it.
- New features. The late-ETA watch is done; anything else is a separate request.
