# Audit Phase 2: CI hardening (rider app)

Branch `audit/phase-2`, from `main` `c1063fb8` (origin/main merged in later: #415, #416, #421).
Machine: cloud container, Flutter 3.47.7 stable. Plan: `movera-contracts` `docs/audit/AUDIT_PLAN.md` § Phase 2.
"Verified" means it ran here or in CI on this branch; everything else says why not.

## Summary

| # | Item | Status |
|---|---|---|
| 1 | One consolidated gate workflow | **Done**; green on PR #422 |
| 2 | `dart format .` in its own commit + format check in the gate | **Done** |
| 3 | The 4 `qa-*` live-build workflows red on `main` | **Diagnosed, not fixed** (needs the live site; see below) |
| 4 | Contract copy v0.5.0 → v0.5.5 + test fallout | **Done** |
| 5 | Leak at `account_widgets.dart:310` | **No change: not a leak** |

## Required checks (for the owner to set on `main`, decision D1)

Branch protection was **not** changed (not in scope, no admin action taken). Proposed required check:

- `CI gate / gate` (job `gate` in `.github/workflows/ci.yml`; it fails unless `static`, `test`, `integration`,
  `web-build` and `secret-scan` all succeed).

Not proposed as required: `Batch 7 Phase 85 browser responsive matrix` (needs the Maps key secret, external
network), the path-filtered `batch6-*`/`batch7-phase81..84` workflows (run only on some paths, so a required
check would never report on other PRs), and the `qa-*` workflows (they test the already-published site).

## 1. Consolidated gate — `.github/workflows/ci.yml`

**Finding (baseline §3):** the full `flutter test` suite ran 5× per PR (architecture-gates, batch4,
batch7-phase85, deep-safe, global-e2e) plus once more in backend-readiness-gate (6 with that one); the 4
linux integration tests ran in 5 workflows; no lockfile enforcement, no format check, `analyze` without
`--fatal-infos` (backend-readiness even `--no-fatal-warnings`), no coverage, no secret scan, Flutter not pinned,
11 workflows without a timeout.

**Change:**
- New `ci.yml` (trigger: every PR, push to main, dispatch; `concurrency` cancel-in-progress per PR/ref):
  - `static` (20 min): `flutter pub get --enforce-lockfile`; `dart format --output=none --set-exit-if-changed`
    over tracked `.dart` files except the generated `test/l10n/all_messages.g.dart`; `flutter analyze --fatal-infos`;
    the existing repo gates moved verbatim: backend-readiness source guards, batch5-phase69 journey integrity
    + "<40 grep-style cases", rider-l10n ARB key check + `tool/gen_l10n_messages.py` up-to-date check; and
    `sha256sum -c contracts/CHECKSUMS`.
  - `test` (50 min): `flutter test --coverage` **once**; the time-zone reruns from architecture-gates
    (Stockholm, New York); lib/core line-coverage floor; `coverage/lcov.info` uploaded as artifact `coverage-lcov`.
  - `integration` (40 min): the 4 linux integration tests once (`ride_flow`, `rider_full_uat`,
    `pre15_all_lifecycle_paths`, `global_uat_flow`).
  - `web-build` (30 min): production and staging `flutter build web --release`.
  - `secret-scan` (10 min): gitleaks 8.28.0 `dir .` on the checked-out tree (history not scanned: it holds the
    Maps key removed in `72e4bb7a`, an owner action per baseline §7/R9).
  - `gate` (5 min): needs all five; this is the one check to require.
  - Flutter pinned `3.47.7` (`subosito/flutter-action` `flutter-version`), `cache: true`, plus `actions/cache`
    of `~/.pub-cache` keyed on `pubspec.lock`.
- Deleted (each re-ran the suite or a subset of it; every distinct step moved into `ci.yml`):
  `architecture-gates`, `global-e2e-uat`, `deep-safe-recertification`, `batch4-final-runtime-certification`,
  `backend-readiness-gate`, `batch5-phase69-test-integrity`, `rider-l10n`.
  The single-file `flutter test test/...` steps those workflows ran are all part of the full suite.
- `batch7-phase85-final-certification`: only the Chromium/WebKit responsive matrix job remains (genuinely
  different: a real browser on the demo build); its analyzer/unit/integration/build jobs were duplicates.
  It gained `concurrency` and `--enforce-lockfile`.
- Kept as they are (genuinely different, path-filtered, ~2–3 min): `batch6-*` (APK debug / production web builds
  with Firebase defines, grep guards) and `batch7-phase81..84`. They still run a handful of test files on
  their paths; left in place to keep this PR to the plan's scope.
- `flutter-version: '3.47.7'` added to every `subosito/flutter-action` use; `timeout-minutes` added to
  `android-release-signing` (45), `live-rider-browser-audit` (30), `publish-web-live` (40), `qa-critical`/
  `qa-live`/`qa-book-now` (30), `qa-device-pwa-responsive` (40). Every job in every workflow now has a timeout
  (checked by parsing all 19 workflow files).

**Coverage floor:** lib/core line coverage **92.90 % (4725 / 5086 lines)**, measured from `coverage/lcov.info`
of the local full run on this branch (after the contract sync). Floor set to **92.8 %** (0.1 below, for
run-to-run noise from timers). Raise it, never lower it.

**Evidence (local):** `flutter analyze --fatal-infos` → "No issues found!"; format check → "0 changed";
`sha256sum --quiet -c CHECKSUMS` → exit 0; all workflow YAML parses. gitleaks was not run locally
(downloading the binary was not permitted in this session).

**Evidence (CI, PR #422, run 40362590881 on `851eb228`):** all six `CI gate` jobs success — static 0:52,
test 14:47 (suite 13:47, TZ reruns 0:28, coverage floor passed), integration 3:15, web-build 2:39,
secret-scan 0:06, gate. Artifact `coverage-lcov` uploaded. Wall time ≈ 15 min, against 5–6 suite runs of
10–13 min each before.

**Fallout found by the first CI runs and fixed:**
- `batch7-phase82` grep guard `child: Text(_saving ? … : …)` failed after `dart format` wrapped the argument;
  it now greps the file with whitespace collapsed (same text). Every grep-only step of the batch6/batch7
  workflows was re-run locally afterwards: all exit 0.
- gitleaks reported 6 `generic-api-key` findings; each line was read: made-up test keys and idempotency keys,
  a preferences key name, and mock payment-intent ids in a recorded audit output. None is a credential. They
  are listed by exact fingerprint (`file:rule:line`) in `.gitleaksignore`, so any new finding fails.
  (Line-number fingerprints: an edit above one of those lines needs the ignore entry updated.)
- `origin/main` moved twice during the work (#415, #416, #421, #418); merged in, and the files they added
  were formatted in format-only commits. From now on a PR with unformatted Dart fails `static`.

**On PR #422 `qa-critical-rider-flow` is red** (it runs on PRs that touch its file, and tests the published
site at the PR's base SHA): the same live-build failure as on main (§3); not caused by this PR.

## 2. Formatting

**Finding:** 519 files unformatted at baseline (543 on this tree, see below).

**Change (commits contain nothing but formatting):**
- `c0af23d3` `dart format .` — run before `flutter pub get`, so the formatter used its default language version.
- `e30c9bb7` re-run with the package's language version resolved (SDK ^3.8.1): 84 files format differently.
- `365de352` (separate, not formatting): 10 braces that `curly_braces_in_flow_control_structures` (an info,
  fatal under `--fatal-infos`) asked for after the formatter split one-line `if`s; `dart fix --apply
  --code=curly_braces_in_flow_control_structures`, no behaviour change.
- `fcb7385a` (separate): `test/pickup/phase99_pickup_accuracy_test.dart` read `home.dart` and looked for
  `refreshCurrentLocation: chosen == null` on one line; the formatter broke that line. Same assertion, now
  `matches(RegExp(r'refreshCurrentLocation:\s+chosen == null'))`. It failed in the full run, passes now.
- After merging `origin/main`, one more format-only commit for the 3 files main added.
- `test/l10n/all_messages.g.dart` is left as `tool/gen_l10n_messages.py` writes it (the gate diffs it).

**Evidence:** `dart format --output=none --set-exit-if-changed $(git ls-files '*.dart' | grep -v '\.g\.dart$')`
→ "Formatted 1062 files (0 changed)", exit 0. The check is the `Format` step of `ci.yml` / `static`.

## 3. `qa-*` workflows (live published build) — diagnosed, not fixed

Logs were readable this time through the GitHub MCP `get_job_logs` (runs on `main` `c1063fb8`, 2026-10-26 12:02Z):

| Workflow (run) | Failing step | Error (from the log) | Last green on main |
|---|---|---|---|
| qa-critical-rider-flow (40319480147) | Payment, Finding to Waiting, standalone Cancel… | `payment: selection: expected map owner select_ride, got none` (same for `finding_waiting`, `cancel_standalone`); `wallet_standalone` PASS | `7e3f1aa6`; red since `39677d69` (#411, map reuse) |
| qa-book-now-e2e (40319480224) | Book now with GPS on and GPS off | `gps-on: expected map owner pickup, got none` | none in the last 40 main runs listed (back to 2026-10-21) |
| qa-live-rider-flow (40319479862) | Exercise actual live Rider flow | `Ride category taps produced no live UI change (0 of 4)`; console: "Attempted to load a Vector Map, but failed. Falling back to Raster." | red on all main runs listed (since ≥ `7e3f1aa6`) |
| qa-device-pwa-responsive (40319480042) | Certify responsive… WebKit | `standalone: destination input missing` | red on all main runs listed |

**Local reproduction** (the published site `baccarisverige-ux.github.io` is blocked by this machine's proxy):
built the same demo bundle as `publish-web-live` from `main` `c1063fb8` (`main_demo.dart`, `--no-web-resources-cdn`
because gstatic is blocked here, Maps JS without a key), served it under `/movera-rider-app/`, and ran the
workflow's own `qa-critical.mjs` with Playwright 1.55.0 / Chromium 1194 (only the base URL, the browser launch
flags for this machine, and a filter for the headless "Could not find a 3d context" WebGL error changed):
`payment` **PASS**, `cancel_standalone` **PASS** (both reached `select_ride`), `finding_waiting` FAIL
(`expected map owner waiting, got none`), `wallet_standalone` FAIL (Menu click intercepted by the glass pane;
it passes in CI). So the CI failure at "selection" did **not** reproduce here; the failures depend on the
environment (keyed Maps, vector map, timing on the runner) and could not be pinned to one cause.

**Reading of the scripts:**
- `qa-book-now-e2e` is stale against the current flow: it types the destination, clicks "Next" (or the point
  195,804) and waits for the `pickup` map. The critical script documents the current flow: "The route planner
  has no Next button: picking a suggestion is the step … Home goes straight to the categories (Select ride);
  the pickup spot is confirmed after the ride is chosen." A script fix must be verified against the published
  build, which only happens after merge (these workflows test the Pages deploy of `main`, and on PRs only
  `qa-critical` runs, against the PR's *base* SHA).
- `qa-critical` regressed with #411 (web map reuse in `web/rider_map_camera.js`): no map owner after
  picking a destination. Whether that is the app (map reused without `onMapCreated` → `maps.attach`) or the
  script's timing is **NOT VERIFIED**: it did not reproduce locally. → Phase 3/5 item, with the published
  site and the Maps key; same root area as N3 (iPhone reloads after #411).

**Change:** only `timeout-minutes` and the pinned Flutter version. No script or app change, because none
could be verified before merge. **Needs:** a run against the live Pages build (access to
`baccarisverige-ux.github.io`, the `MAPS1` secret), i.e. CI on `main` after merge or a dispatch run.

## 4. Contract copy v0.5.0 → v0.5.5

**Change:** `sh tool/sync_contract.sh 5719833fda73331b836c6f6625d59f5ee963c0bc` (movera-contracts `main`,
"Contract v0.5.5") → "synced 17 files … (contract 0.5.5)". Full suite then had 3 contract failures:
- `contract_copy_test` pinned `0.5.0` → now `0.5.5`.
- `trip_lifecycle_contract_test` "table equals contract.json#transitions row by row" and "replays
  fixtures/scenarios.json" (`live_accept_only_from_offered: accept by driver from requested` expected
  `invalid_transition`, got `accepted`): `lib/core/contracts/trip_transitions.dart` (`TripStateMachine`, the
  Dart mirror of `contract.json#transitions`) still had the v0.5.0 rows. Updated row for row: `accept` from
  `offered`; `accept` from `requested` only `when: scheduled` (v0.5.1); new `raise_price` (rider,
  `searching|offered` → `searching`, v0.5.5); `contractVersion` `0.5.5`.

**Behaviour:** in `lib` the machine is consulted for the rider's `cancel`/`end_early` (finding_driver_controller)
and by the in-process mock (`in_process_mock_client.dart`); the changed rows are the driver's `accept` and the
rider's `raise_price`, which the rider app never applies through it. **For Phase 3:** the rider's mirror was
two contract versions behind on the transition table (v0.5.1 accept split, v0.5.5 raise_price) and nothing
failed until the copy was synced — the live server is the authority, but the mock dialect most tests run
(R1) followed the old rule (a live trip acceptable from `requested`).

**Evidence:** `flutter test test/contracts` → "+112: All tests passed!"; CHECKSUMS verify.

## 5. `account_widgets.dart:310` — not a leak

`showAccountTextEditor` creates a `TextEditingController` and a `ValueNotifier` and passes both to
`MoveraSheetDisposables(disposables: [controller, error], …)` (`lib/shared/design_system/movera_sheet.dart:91–116`),
whose `State.dispose` disposes each. The baseline's heuristic scan missed that wrapper. No change.

## Full suite

- Run 1 (after format + contract sync, before the fixes above): `+2954 ~3 -4` ("Some tests failed"): the 3 contract tests
  and phase99 (all fixed above). Wall 42m49s (4 cores, shared with a web build).
- Run 2 (after all fixes, before merging #418): `+2962 ~3: All tests passed!`, wall 28m35s; lib/core
  coverage 92.90 % (4725/5086), same as run 1.
- CI on the final tree: see §1 evidence (suite green, coverage floor passed).
