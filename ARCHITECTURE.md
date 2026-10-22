# Movera Rider architecture

Approved UI is frozen. Status is **runtime wiring**, not folder names.

WaitingForDriver is the approved surface for assigned / arriving / in-progress.
Stage changes keep that same screen, map, and panel mounted; only ride copy
and the driver marker update.

Web snapshot key: `flutter.movera_active_ride` (`RideSnapshotStore.key`).

Previous landmark SHA `a82b70b` / “108 tests” is **historical**, not current proof.
Mocks remain intentional (in-process API, mock realtime, mock payments).
**Cancel-first:** on Finding, tapping Cancel request runs `FindingDriverController.cancelSearch`
at once: the cancel goes into the pending-cancel outbox (one idempotency key), the server is
asked, and on its OK the ride is committed as `cancelledByRider`, archived to History and
`RideSnapshotStore.clear`ed. Only then does the optional why-sheet open (Skip / Send, no Keep
ride); its reason is sent as feedback, so a reload while it is open lands on Home. When the server
cannot be reached nothing is committed (RC-03): the outbox entry stays to retry, the search keeps
listening and shows "Cancelling…", and the server's answer either commits the cancel then or
brings the driver who accepted first. A 409 (driver already accepted) commits nothing and the
rider moves on to Waiting with a short notice. Waiting/in-trip stay server-first after the sheet (D-013).
QA `window.movera*` hooks are gated (`kDebugMode` or `--dart-define=MOVERA_QA=true`),
except the navigation-only `moveraOpenSafety` bridge, which every web build has (see QA_HOOKS.md).
See `docs/API_V1_MOCK.md`, `docs/UAT_CHECKLIST.md`, `docs/QA_HOOKS.md`.

## Canonical frontend state (existing names)

Do not invent a second source of truth. Runtime ride mutations use
`RideSession.restoreFromBackend` (not `transitionRide`).

| Concern | Owner |
|---|---|
| Live ride (in memory) | `AppScope.instance.ride` (`RideSession`) |
| Live ride persistence | `RideSnapshotStore` (`movera_active_ride`) |
| Book now submit lock | `AppScope.instance.booking` (`BookingCoordinator`) |
| Searching UI | `FindingDriverController` (`FindingDrivers`) |
| Matched / in-progress UI | `ActiveRideController` (`WaitingForDriver`) |
| Scheduled reservations | `AppScope.instance.reservations` (`ReservationController`) |
| Finished Book now History | `OnDemandRideHistoryStore` |
| Restore surface | `RideRestoreCoordinator` / `RideRestoreGate` |
| Category + payment on SelectRide | `RideSelectionController` |

Book now CTA must go through `BookingController` → `BookingRepository` →
`AppScope.instance.booking`. A second tap reuses the in-flight submit and must
not push a second `FindingDrivers`.

Cancel of a live Book now ride archives History (`archiveCancelledThenClear`)
then clears the snapshot. Reservations stay in `ReservationController` until
the frontend later promotes them.

Public web cold start restores a fresh snapshot (`RideRestoreCoordinator`).
The document-load wipe helper still exists for QA clear and is not invoked
on boot. BFCache `persisted == true` is not teardown.

## 20-phase completion pass

Historical phase table retained below for archaeology. Treat CI tip + `flutter test`
as current proof — do not cite frozen “108 tests” / `a82b70b` as live status.

## Remaining intentional mocks

These do **not** block local architecture completion:

- production backend / Postgres
- real WebSocket
- Stripe (card, Apple Pay, Google Pay; owner Q7: no Swish)
- FCM / APNs
- Sentry / Crashlytics
- separate Admin app

Release builds also reject device-only rider repositories
(`RepositoryComposition`): the wallet ledger, Book for later and saved cards
are switched off in staging/production until their server side exists, and
profile, payment methods, History and the active trip use the proposed
server routes in `docs/API_V1_MOCK.md`.

`InProcessMockClient` is the v1 mock contract. `backend/src/index.js` is a
frozen, unused Node mock (see `backend/README.md`); only the phase74, phase78
and phase80 CI workflows still boot it as a smoke target, so it is not a
second source of truth.
`AppEnv.current` defaults to `https://api.demo.movera.invalid`
(`MOVERA_API_BASE_URL` overrides it).

Contract types live in `lib/core/contracts` (P1): `TripStatus` with its
snake_case wire parser, `RideStatus` (Rider UI enum) and its one wire adapter,
`Money` (integer minor units + ISO-4217) and `WireTime` (RFC 3339 UTC).
`lib/core` never imports `lib/features` or `app/di.dart`, DI never imports a
screen, and application services do not import presentation; the
architecture guard test enforces this.

## Live

https://baccarisverige-ux.github.io/movera-rider-app/
