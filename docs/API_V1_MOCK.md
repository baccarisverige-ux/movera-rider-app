# Movera Rider API v1 — in-process mock contract

This documents `InProcessMockClient` (`lib/core/api/in_process_mock_client.dart`)
and `SafetyMockApi` (`lib/core/api/safety_mock_api.dart`), the mock the app
actually runs against in demo/dev/test builds. It is the only mock contract.

`backend/src/index.js` is **not** part of this contract: it is a frozen,
unused Node mock that is not kept in parity (see `backend/README.md`); several
of its routes disagree with the shapes below (no ride `version`/`updatedAt`,
a client `price` on PATCH, payments that succeed without `/confirm`).

No Postgres, Stripe, hosted API or real auth. In-memory only.
`AppEnv.current` defaults to `https://api.demo.movera.invalid`
(`MOVERA_API_BASE_URL` overrides it; staging/production refuse the default).

Every shape here is what the Dart mock does today. Routes marked
**PROPOSED** were added as frontend seams (PR-13) and still need agreement
with Driver, Admin and backend; the full proposals are contracts C-0..C-12
in the frontend audit report.

## Conventions

| Header | Required | Notes |
|---|---|---|
| `X-Request-Id` | yes (client always sends) | Echoed as `requestId` in bodies |
| `Idempotency-Key` | mutating calls that send one | Same key returns the cached 2xx body |
| `X-Api-Version` | yes | Always `0.4` from `ApiClient` (`contract.json#headers`) |
| `Authorization` | optional | `Bearer <access>`; a 401 with a token triggers one refresh + retry |
| `Content-Type` | JSON bodies | `application/json` |

Responses are JSON `{code, requestId, ...}`; errors are `{code, message?}`
with an HTTP status ≥ 400. Unknown paths answer `404 {code: NOT_FOUND}`.
Times are RFC 3339 UTC. Money on new fields is integer minor units
(`…Minor`, öre) with `currency: "SEK"`; `price` fields are legacy kronor.

## Routes

### Health

- `GET /health` → `{ok: true}`

### Auth

- `POST /api/v1/auth/otp/request` `{phone, linkToken?}` → `{sessionId, expiresAt, retryAfterSeconds}`; `400 INVALID_PHONE | INVALID_LINK`. The mock code is `1234`.
- `POST /api/v1/auth/otp/verify` `{phone, sessionId, code}` → `{accessToken, refreshToken, isNewRider}`; `400 INVALID_OTP_SESSION`, `401 INVALID_OTP`, `410 OTP_EXPIRED`.
- `POST /api/v1/auth/provider` `{provider}` → tokens, or `{code: PHONE_REQUIRED, linkToken}` the first time.
- `POST /api/v1/auth/refresh` `{refreshToken}` → rotated `{accessToken, refreshToken}`; `401 INVALID_REFRESH`.
- `POST /api/v1/auth/sign-out` → `{code: OK}`.

### Account

- `GET /api/v1/account/security` → `{security}`.
- `POST /api/v1/account/security/sessions/sign-out-others` → `{security}`; `403 REAUTH_REQUIRED` unless re-authenticated in the last 5 minutes.
- `POST /api/v1/account/deletion` → `202 {status: scheduled}`.
- `GET /api/v1/rider/profile` **PROPOSED** (FLOW-7) → `{profile}` (`{name, language, consents}`, or `null` for a rider with none). Read at launch, after sign-in and before the first save; nothing is sent until it has been read, so an empty device copy never blanks the server one (rider-u148).
- `PATCH /api/v1/rider/profile` **PROPOSED** (FLOW-7) `{name?, language, consents: {rideUpdates, emailUpdates, promotions}}` → `{profile}`; `422 INVALID_PROFILE` (name not a string or over 80 characters). A field left out keeps the server value; a blank name is never sent. Sent on every profile save; the device copy is a cache.

### Push devices

- `POST /api/v1/push/devices` `{token, provider: "fcm", platform}` → `{status: registered}`; `400 INVALID_PUSH_DEVICE`.
- `POST /api/v1/push/devices/unregister` `{token}` → `{status: unregistered}`.

### Places and routes

- `POST /api/v1/locations/reverse-geocode` `{latitude, longitude}` → `{data: {latitude, longitude, address}}`; `400 INVALID_COORDINATES`.
- `POST /api/v1/locations/geocode` `{query}` → `{data: {address, latitude, longitude}}`; `400 INVALID_QUERY`.
- `POST /api/v1/locations/autocomplete` `{query}` → `{suggestions: [...]}`.
- `POST /api/v1/routes` `{from: {lat, lng}, to: {lat, lng}}` → `{points: [...], provider}`.

### Catalog and promotions

- `GET /api/v1/ride-types` → `{rideTypes: [{id, name, seats, etaMin, price, currency, description, badge, glyph, imageKey, order, enabled}]}` (`price` is the list price in kronor, display only).
- `GET /api/v1/rider/promotions/active` → `{promotion}` (or `null`); display only, the discount is applied in the quote.

### Scheduled-ride rules — PROPOSED

- `GET /api/v1/rider/scheduled-rides/rules` → `{rules: {freeCancelMinutesBeforePickup, lateCancelFeeMinor, currency, showDriverOnAccept}}`. Set by admin (Dispatch › Reservations). The mock answers the admin defaults: free cancel until `60` min before pickup, then a `5000` öre (kr 50) fee; the rider sees the driver as soon as one accepts (`true`). Read at app start (`ReservationController.refreshRules`); the rider app keeps the same defaults (`ScheduledRideRules.defaults`) when it cannot read them. Reservations themselves stay device-only (see below), so the late-cancel fee is recorded on the device copy of the ride and not charged anywhere yet.

### Quotes

- `POST /api/v1/quotes` `{rideType, pickup?, destination?, stops?, distanceMeters?, …}` → `{quote}` with `id` = `quoteId`, `rideType`, `totalMinor` = `amountMinor`, `currency`, `expiresAt` (2 minutes), `expiresInSec: 120`, `breakdown {baseMinor, distanceMinor, timeMinor, bookingFeeMinor, discountMinor}`, `signedPayload`.

### Rides

- `POST /api/v1/rides` with `Idempotency-Key` `{categoryId, paymentMethodId, pickupAddress, pickupLat, pickupLng, destinationAddress, destinationLat, destinationLng, stops[], notes, price, quoteId, quoteSignedPayload, quoteExpiresAt, quoteTotalMinor, useWalletFirst?, walletAmountMinor?, scheduledAt?}` → `{ride}` with `id`, `status` in contract wire names (`searching`, or `requested` with `scheduledAt`), `version: 1`, `updatedAt`, `searchStartedAt`, `maxOfferMinor`, … . `409 QUOTE_REQUIRED | QUOTE_NOT_FOUND | QUOTE_SIGNATURE_MISMATCH | QUOTE_EXPIRED | QUOTE_AMOUNT_MISMATCH | QUOTE_CATEGORY_MISMATCH`. A scheduled booking without a quote is still accepted by the mock (older contract), but the client no longer sends one (ARCH-16).
- `GET /api/v1/rides/:id` → `{ride}` (the projection realtime polls); `404 NOT_FOUND`. A search past its expiry becomes `expired` (the app shows it as no driver found).
- `PATCH /api/v1/rides/:id` `{offerIncreaseKr}` while searching → `{ride}` with the server-priced fare (a client `price` is ignored, D-012); `409 RIDE_NOT_SEARCHING | OFFER_ABOVE_MAXIMUM`, `422 INVALID_OFFER`.
- `PATCH /api/v1/rides/:id` `{routeChange: true, routeQuoteId, pickup…?, destination…, stops, paymentMethodId, refundTo?}` → `{ride, newPriceKr, differenceKr, stops}`; `409` with the denial code (pickup locked, finished, quote missing/expired/mismatched).
- `POST /api/v1/rides/:id/route-quote` `{pickup…?, destination…, stops}` → `{routeQuoteId, expiresAt, newTotalMinor, differenceMinor, newPriceKr, differenceKr, …}`; `409` denial code; `404`.
- `POST /api/v1/rides/:id/cancel` `{reason?}` → `{ride}` with `cancelled_by_rider`. Idempotent; a second call with a `reason` stores it when none is stored. `404` for an unknown id. (Contract, not mocked: `409` when the ride moved on first.)
- `GET /api/v1/rides/:id/nearby` → `{vehicles: [{id, lat, lng, bearing}]}`.
- `POST /api/v1/rides/:id/status` `{status, driver?, lat?, lng?}` → `{ride}`, bumping `version` (QA/realtime helper only; never called by app code).
- `POST /api/v1/rides/:id/feedback` `{rating?, tipMinor?, currency}` → `{status: accepted}`; `409 RIDE_NOT_COMPLETE`, `400 INVALID_FEEDBACK`.
- `POST /api/v1/rides/:id/disputes` `{reason, detail?}` → `{dispute}`; `400 INVALID_DISPUTE`.

Realtime (`ApiRideRealtime`) polls `GET /api/v1/rides/:id` and reads, besides
the projection, an optional envelope **PROPOSED** (C-6, ARCH-13):
`eventId` (deduplicated), `serverTime` (server clock at answer time, used to
judge location age), `etaSeconds`; ordering is by the projection's `version`.
Three `404`s in a row stop polling that ride and mark the connection failed;
the client does not invent a status, so the ride keeps its last known one.
Other failures back off.

### Trips (read models) — PROPOSED (ARCH-12, C-5)

- `GET /api/v1/rider/trips/active` → `{trip}` (the live, non-scheduled ride projection) or `{trip: null}`. Release builds ask it on cold start and on a push tap when the device has no snapshot.
- `GET /api/v1/rider/trips?cursor=` → `{trips: [projection + endedAt?], nextCursor}`; the mock returns one page of finished rides. Release History reads it.

### Payments and wallet

- `POST /api/v1/payments` with `Idempotency-Key` `{amountMinor, currency: "SEK", purpose?, rideId?}` → `{intent: {id, status: "requires_confirmation", amountMinor, currency, purpose?, rideId?}}`; `400 INVALID_PAYMENT_INTENT`. `purpose` (`wallet_topup | ride | tip`) is **PROPOSED** (ARCH-6, C-10); wallet top-ups send `wallet_topup`.
- `POST /api/v1/payments/:id/confirm` → `{status: "succeeded", intent}`; `404 PAYMENT_NOT_FOUND`.
- `GET /api/v1/payments/:id` → `{status, intent}`; `404 PAYMENT_NOT_FOUND`.
- `GET /api/v1/payment-methods` **PROPOSED** (ARCH-7, C-10) → `{methods: [{id, kind, label, detail?}], defaultMethodId}`.
- `PATCH /api/v1/payment-methods/default` **PROPOSED** `{methodId}` → `{defaultMethodId}`; `422 INVALID_PAYMENT_METHOD`.
- `POST /api/v1/wallet/topup` → `{status: succeeded, amountMinor}`. Present in the mock but **not called by the app**; a top-up is a payment intent with `purpose: wallet_topup`. A server wallet (`GET /api/v1/wallet`, C-10) does not exist yet, so release builds switch the wallet off.

### Safety (`SafetyMockApi`)

- `GET/PATCH /api/v1/safety/preferences`
- `GET /api/v1/safety/pin`, `POST /api/v1/safety/pin/rotate` (per-rider PIN; the ride-scoped `GET /rides/{id}/pin` in `docs/ride-pin-backend-contract.md` is still to come). PIN verification is a driver-app call and is not part of the rider mock (ARCH-22).
- `GET/POST /api/v1/safety/contacts`, `PATCH/DELETE /api/v1/safety/contacts/:id`, `POST /api/v1/safety/contacts/:id/primary`
- `POST/GET/PATCH/DELETE /api/v1/rides/:id/share`
- `GET/PATCH /api/v1/safety/ridecheck/preferences` → `{policy: {enabled, triggers}}`. `enabled` is the rider's switch (default on). `triggers` is set by admin (Dispatch › Safety, RC6) and read-only for the rider: `{droppedFar: {enabled, meters: 500}, longStop: {enabled, minutes: 4}, offRoute: {enabled, km: 2, longerPercent: 50}, possibleCrash: {enabled}}`. A PATCH changes `enabled` only.
- `POST /api/v1/safety/ridecheck/answers` **PROPOSED** (Ride check RC4) `{checkId, rideId, trigger: dropped_far|long_stop|off_route|possible_crash, shownAt, reason, answers: [{kind, id, label, value?, question?, at}], alert, alertId?, final, rider: {id, name?, phone?}, driver: {id?, name?, plate?, vehicle?}, trip: {rideId, pickup, destination, stops?, rideType?, status?, lastLocation?}}` → `{answer, alert?: {alertId, status: sent|updated, recipients: [admin, dispatch], ...}}`; `422 INVALID_RIDECHECK_ANSWER`. A red row (accident, someone hurt, unsafe) or Call 112 sends `alert: true` at once; a later Yes / Not sure for the same `checkId` updates that alert. Every answer (OK or not) is kept for admin's Ride check log. Audio is never part of it.
- `POST/GET /api/v1/rides/:id/safety-events`, `POST /api/v1/rides/:id/safety-events/:eventId/respond`. A Ride check card posts its event with `payload: {kind: ridecheck, trigger, reason}`; types `unexpectedStop`, `routeDeviation`, `possibleCrash` and `droppedFar`.
- `POST /api/v1/rides/:id/safety-audio/init`, `POST /api/v1/rides/:id/safety-audio/:recordingId/complete`, `DELETE /api/v1/rides/:id/safety-audio/:recordingId` (Safety Kit recordings). A Ride check recording calls none of these: it stays on the phone (RC5).

### Telemetry (release builds only, not mocked)

`HttpObservabilitySink` posts to `/api/v1/telemetry/logs`, `/analytics` and
`/crashes`; demo/dev builds use no-op sinks, so the mock has no such routes.

## Device-only data and release builds

Release composition (`RepositoryComposition`, ARCH-7) only accepts
server-backed repositories. Until the server side exists, staging/production
switch off and fail closed: the wallet ledger, Book for later
(reservations) and saved cards. Profile, payment methods, History and the
active trip use the PROPOSED routes above.

## Intentional mocks

SQL under `backend/sql` remains documentation only. Do not wire a database here.
