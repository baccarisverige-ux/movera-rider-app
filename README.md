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

## Web deployment

The Rider web build publishes to GitHub Pages from `main`. Pages deployments are serialized by the publish workflow so overlapping updates do not race each other.
