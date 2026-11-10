# Movera Rider

This repository is the canonical source of truth for the **Movera Rider** Flutter application.

## Architecture

- `lib/features/rider/` — Rider-only product features and screens
- `lib/core/constants/` — app-wide constants, colors, assets and typography configuration
- `lib/core/services/` — Rider app services
- `lib/shared/models/` — Rider data models used across features
- `lib/shared/widgets/` — reusable UI widgets
- `lib/shared/presentation/` — shared presentation such as splash/onboarding
- `assets/` — original app assets, kept intact

Driver application code belongs only in the separate Movera Driver repository.
Generated Flutter/Gradle files, temporary upload ZIPs, and build output are intentionally not source-controlled.

## Translations

Rule: new texts go in their area file, `lib/l10n/parts/<area>.<lang>.arb`
(en, fr and sv), never in `lib/l10n/app_<lang>.arb`, which
`python3 tool/gen_l10n_messages.py` writes from the area files. See
`lib/l10n/parts/README.md`.

## Google Maps configuration

Never commit Maps API keys. Android reads `MAPS_API_KEY` from a Gradle property or environment variable; release builds fail without it (debug builds use a placeholder and show grey tiles). iOS reads `GOOGLE_MAPS_API_KEY` from the untracked `ios/Flutter/Secrets.xcconfig` (copy `Secrets.xcconfig.example`), exposed to the Maps SDK as `GMSApiKey` in `Info.plist`; Release/Profile builds fail without it, and a Debug build without it shows the no-map fallback instead of creating a map.

## Contract copy

`contracts/` is the byte-for-byte copy of the shared contract (version **0.18.54**). Never edit it by hand
(Rule 43(4)). After a contract merge run `tool/sync_contract.sh v<version>` and commit `contracts/` exactly as
it comes out. `.github/workflows/contract-copy.yml` runs `tool/check_contract_copy.sh` on every PR and push and
once a day opens or closes the issue "Contract copy behind movera-contracts main".

## Build and test

Flutter 3.47.7 (stable) on CI; `pubspec.yaml` asks for Dart ^3.8.1.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed $(git ls-files '*.dart' | grep -v '\.g\.dart$')
flutter analyze --fatal-infos
python3 tool/l10n_parts.py --check
flutter test --coverage
flutter build web --release
python3 tool/check_web_budget.py build/web --main-raw 6500000 --main-gzip 1850000
```

`.github/workflows/ci.yml` ("CI gate", on every PR and push to `main`) runs these in the jobs `changes`
(docs-only detection), `static`, `test`, `integration`, `web-build`, `web-memory`, `secret-scan` and `gate`,
the one job a branch rule requires ("CI gate / gate"): green only when every job passed or was skipped on
purpose (docs-only PR or draft). The `qa-*.yml` and `batch*-phase*.yml` workflows are older checks that still
run on PRs; `live-rider-browser-audit.yml` and the `android-*.yml` workflows run by hand.

## Web deployment

`.github/workflows/publish-web-live.yml` ("Publish Rider Web Live") builds the live rider on every push to
`main` and publishes it to GitHub Pages at `https://baccarisverige-ux.github.io/movera-rider-app/live/` (the
site root redirects there); it reads the `MOVERA_LIVE_API_URL` repository variable (the server, movera-server
on Render). Pages deployments are serialized by the publish workflow so overlapping updates do not race each
other.

## Working rules

- The owner's memory for the project is the Rules repository (`Movera-team/Rules`: `RULES.md`, `decisions/`,
  `plan/`). Read it first; decisions for this app are in `docs/DECISIONS.md`.
- Rule 25: a hand-written file over 1,500 lines is split before it is changed (`.arb` files included;
  generated l10n outputs are exempt). Rule 21: never delete anything without asking the owner.
- Pull requests use `.github/pull_request_template.md`; security problems go through `SECURITY.md` (private
  reporting), never a public issue.
