# Movera shared contract v0.3.1

One contract for **Rider** (Flutter), **Driver** (Flutter) and **Admin** (React/TS), so one future backend can serve all three.
This folder is copied byte-for-byte into each repo at `contracts/`. Each repo runs contract tests that (1) check its copy matches `contracts/CHECKSUMS` and (2) replay `fixtures/*.json` through its own code. Change the contract here first, bump `version`, then copy to all three repos.

Files:

| File | What |
|---|---|
| `contract.json` | Machine-readable source of truth: enums, terminal set, transition table, cancel codes, realtime rules, error codes, currencies, categories |
| `CONTRACT.md` | This document: entities, lifecycle per app, events, admin control matrix, config documents, API surface |
| `openapi.yaml` | REST + realtime surface v0.3 (all three apps) |
| `fixtures/scenarios.json` | Trip lifecycle scenarios (commands × actors → status or `invalid_transition`), plus who may rate the trip afterwards (`rating`) |
| `fixtures/events.json` | Realtime gate cases (accepted / gap / duplicate / blocked / invalid) |
| `fixtures/money.json` | Money minor-unit cases incl. TND (3 decimals) |
| `fixtures/config/*.json` | Sample `RiderAppConfig` and `DriverAppConfig` documents |
| `reference_check.py` | Reference engine; proves the fixtures agree with `contract.json` |

---

## 1. Wire rules

- **Ids**: opaque strings `^[A-Za-z0-9_-]{1,64}$`. `tripId` is the trip. `offerId` is an offer (one trip, many offers). `rideId` is a read-only legacy alias of `tripId`. Clients never invent a `tripId`.
- **Time**: RFC 3339 UTC with `Z`. Durations are integer seconds. Zone-local wall times (surge windows, `HH:mm`) carry the zone `timeZone`.
- **Money**: `{ "amountMinor": int, "currency": "SEK" }`. Exponent from ISO 4217 (`SEK`/`EUR` 2, `TND` 3). No floats, no display strings (`"126,75 kr"`) on the wire. Apps format locally.
- **Location**: `Place { address?, lat, lng }` for pickup, dropoff, stops (ordered). `GeoFix { lat, lng, accuracy, heading?, measuredAt }` for device GPS only. JSON says `lat`/`lng`; Dart may keep `latitude`/`longitude` inside.
- **Case**: keys camelCase, enum values snake_case.
- **Categories**: ids from the admin Pricing catalog (`^[a-z][a-z0-9_]{1,31}$`). Seed: `economy, comfort, premium, priority, xl, electric, pet`. Alias `movera → economy` accepted on read for one release. Labels are display only.
- **Payment methods**: `card, swish, klarna, apple, google, paypal, cash, wallet` (a saved card is `card` + `paymentMethodId`).
- **Headers**: `Idempotency-Key` on every mutation (16–128 chars, server 409s on a different body under the same key), `X-Request-Id`, `X-Api-Version: 0.3`.
- **Concurrency**: every trip/offer/driver/config command sends `expectedVersion`; a stale version gets `409 version_mismatch` with the current projection.
- **Errors**: `{ code, message, requestId, retryable, projection? }`, codes in `contract.json#errors.codes`. `projection` is the current resource for `version_mismatch` / `invalid_transition` (trip, offer, driver, rider, vehicle or config draft). Validation and wrong PIN are 400 `invalid_request`; too many PIN attempts 429. Success responses are the bare resource.

## 2. Canonical entities

```
TripProjection {
  tripId, status: TripStatus, version ≥1, sequence ≥0,
  kind: live | scheduled, scheduledAt?,
  createdAt, updatedAt,
  riderId, driverId?, vehicleId?, zoneId, categoryId,
  pickup: Place, dropoff: Place, stops: Place[],
  quote?: { quoteId, total: Money, expiresAt },
  fare: Money,                       // current authoritative fare (rider pays)
  fareLines?: [{ code, amount: Money }],   // base, distance, time, stops, waiting, pickup_pay, surge, discount, cancel_fee
  driverEarnings?: Money, commission?: Money,
  paymentMethod, paymentMethodId?, paymentStatus?: PaymentStatus, ratingStatus: RatingStatus,
  driver?: DriverSummary, driverLocation?: GeoFix, etaSeconds?,
  waiting?: { arrivedAt, freeUntil, noShowAt, chargedSeconds },
  cancellation?: { actor, reasonCode, at, fee: Money | null, note? },
  pinRequired: bool
}
DriverSummary { driverId, firstName, rating?, tripCount?, photoUrl?, vehicle: { vehicleId?, make?, model?, color?, plate?, categoryId? } }
Offer { offerId, tripId, kind: OfferKind, status: OfferStatus, version, expiresAt, fare: Money, driverEarnings: Money,
        pickupPay?: Money, fareBoost?: Money, pickup: Place, dropoff: Place, stops: Place[], categoryId, paymentMethod,
        pickupEtaSeconds, pickupMeters, tripSeconds, tripMeters, riderRating?, riderTrips?, scheduledAt?, reasonCode? }
Quote { quoteId, categoryId, total: Money, fareLines, expiresAt, pickup, dropoff, stops, surgeMultiplier? }
Rider { riderId, firstName, phone?, email?, rating?, status: active | suspended, version }
Driver { driverId, accountStatus: DriverAccountStatus, onlineStatus: DriverOnlineStatus, firstName, rating?, zoneIds, categoryIds, vehicleId?, documents: DocumentSummary[], version }
Vehicle { vehicleId, make, model, year, color, plate, seats, categoryIds, status: pending | approved | rejected | blocked, version }
Document { documentId, ownerId, type, status: missing | in_review | approved | rejected | expired, expiresAt?, version }
PaymentIntent { paymentId, tripId, amount: Money, method, status: PaymentStatus, failureCode? }
Refund { refundId, paymentId, amount: Money, reason, status: pending_approval | done | rejected }
WalletEntry { entryId, ownerId, amount: Money, kind: topup | charge | refund | payout | adjustment, tripId?, at }
Rating { tripId, from: rider | driver, stars: 0.5..5 (step 0.5), tags[], comment? }
Notification { notificationId, audience: rider | driver, kind, title, body, at, read }
Message { messageId, tripId, from: rider | driver | support, text, at }
```

Status enums (exact values in `contract.json`): `TripStatus` (19), `PaymentStatus`, `RatingStatus`, `DriverAccountStatus`, `DriverOnlineStatus`, `OfferKind`, `OfferStatus`.

**Payment and rating are not trip statuses.** After `completed` they change as fields on the projection (`payment_updated`, `rating_updated` events) and are never blocked by the terminal rule. Rider UI states like `paymentProcessing`, `ratingPending`, `paymentFailed` are derived: `completed + paymentStatus`, `completed + ratingStatus`.

**Who may rate** (`contract.json#ratingAllowed`): the rider and the driver after `completed`; the rider also after a trip the rider ended early (`end_early` → `cancelled_by_rider`, `POST /trips/{id}/end-early`), with the normal rating screen. `ratingStatus` then goes `pending → submitted | skipped` and `rating_updated` passes the terminal gate as usual. A plain rider `cancel` (also `cancelled_by_rider`) is never rated, and the driver does not rate an ended-early trip; any other rating is `409 invalid_transition`. The marker is the command that ended the trip: `end_early` is only allowed on board and `cancel` by the rider only before boarding, so the server knows which one ended it.

## 3. Trip lifecycle (single state machine)

The transition table is `contract.json#transitions`: `command × actor × from[] → to`, with `when: live | scheduled` where the target differs. Anything not in the table is `409 invalid_transition` and the status does not change.

```
draft → quoted → requested → searching ⇄ offered → accepted → driver_to_pickup → arrived → rider_onboard → in_trip → approaching_dropoff → completed
                         (scheduled: requested ──driver claims──▶ accepted)
Terminal: completed · cancelled_by_rider · cancelled_by_driver · cancelled_by_admin · cancelled_by_system · no_show · expired · failed
```

| Command (actor) | From | To | Rider app | Driver app | Admin |
|---|---|---|---|---|---|
| quote (system) | draft | quoted | Price per category | — | Quote kept on the trip |
| request (rider) | quoted | requested | "Finding driver" / booked reservation | — | Trip appears in lists |
| start_search (system) | requested | searching | Searching animation | — | Live map: searching |
| send_offer (system) / assign (admin) | searching (admin: requested, searching, offered) | offered | Still searching | Radar / Exclusive / "Assigned by Movera" card | Sees who has the offer; can assign |
| offer_lapsed (system) | offered | searching | — | Card gone ("taken" / expired) | — |
| accept (driver) | offered (scheduled: requested) | accepted | Driver card, car, ETA | Trip screen / Accepted reservation | Driver shown on trip |
| head_to_pickup (driver) | accepted | driver_to_pickup | Car moving on map, ETA | Navigation to pickup | Live tracking |
| arrive (driver) | driver_to_pickup | arrived | "Driver is here", waiting clock | Waiting clock, no-show timer | Waiting visible |
| board (driver) | arrived | rider_onboard | PIN shown when required | PIN entry | — |
| start_trip (driver) | rider_onboard | in_trip | Ride in progress | Navigation to drop-off | — |
| near_dropoff (system) | in_trip | approaching_dropoff | "Almost there" | "Arriving" | — |
| complete (driver; admin from onboard+) | in_trip, approaching_dropoff | completed | Receipt, pay, rate | Earnings, rate rider | Money split, can refund |
| cancel (rider) | requested … arrived | cancelled_by_rider | Fee shown first (rules §5) | Island "Rider cancelled · +X kr / no fee" | Cancel check, can waive fee |
| end_early (rider) | rider_onboard … approaching_dropoff | cancelled_by_rider | Pays distance driven, rates the trip | Island "Rider ended trip" | Trip review |
| cancel (driver), live | accepted, driver_to_pickup, arrived | **searching** (reassign) | "Finding a new driver" | Back online; counts in cancel rate | Cancel rate, cancel reason |
| cancel (driver), scheduled | accepted | **requested** | Reservation still booked | Leaves Accepted | Late-cancel count |
| cancel (driver), scheduled, on the way | driver_to_pickup, arrived | **searching** | "Finding a new driver" | Back online; counts | Late-cancel count |
| cancel (driver) | rider_onboard … approaching_dropoff | cancelled_by_driver | Trip ended, support link | Reason sheet (during-trip codes) | Incident review |
| no_show (driver after noShowAfterMin; admin) | arrived (admin also accepted, driver_to_pickup) | no_show | No-show fee charged | No-show fee to driver (share %) | Can reverse |
| reassign (admin) | offered … arrived | searching | "Finding a new driver" | Trip removed, island notice | Audit, reason |
| cancel (admin) | any non-terminal | cancelled_by_admin | Cancelled by Movera | Cancelled by Movera | Reason required |
| expire (system) | quoted … offered | expired | "No driver found" / quote expired | Offer gone | — |
| system_cancel (system) | requested … accepted | cancelled_by_system | Payment problem / zone closed | Trip removed | Alert |
| fail (system) | any active | failed | Error + support | Error + support | Alert |

Multi-stop: `stops[]` ordered on quote, request and projection; quotes MUST include stops. Waiting at a stop is billed per `pickupWait` rules. Route changes after request create a new quote (`/trips/{id}/route-quote`) and a `PATCH` with `expectedVersion`.

Scheduled rides: `kind = scheduled`, `scheduledAt` UTC. Free cancel until `freeCancelMinutesBeforePickup` (per zone × category, §5). Dispatch starts `searchBeforeMin` before pickup. A driver claim (`accept` from `requested`) can be released (`cancel` → `requested`).

## 4. Realtime and synchronisation

Envelope (`contract.json#realtime`): `eventId, tripId, sequence, version, kind, occurredAt, serverTime` + optional `projection, location (GeoFix), etaSeconds, cancelFee (Money|null), message (Message, only for kind=message)`. In `fixtures/events.json`, top-level `status`/`paymentStatus`/`ratingStatus` are test shorthand for the same fields in `projection`.

- `sequence` is **server-assigned**, contiguous per trip. Clients never number events.
- Gate (same in all apps; cases in `fixtures/events.json`): invalid if `sequence < 1` or blank `tripId`; duplicate if `eventId` seen or `sequence ≤ last`; gap → accept and resync; after a terminal status only `payment_updated`, `rating_updated`, `message` pass; `location` never replaces the projection.
- Kinds: `trip_projection, rider_cancelled, driver_cancelled, location, driver_arrived, rider_on_the_way, payment_updated, rating_updated, message`.
- Transport: `GET /trips/{tripId}/events` (SSE or WebSocket), replay with `?after={sequence}`. Fallback: poll `GET /trips/{tripId}` (projection carries `sequence`).
- Driver offer feed: `GET /driver/offers/stream` with `offer_created`, `offer_updated`, `offer_withdrawn` (status `claimed_elsewhere | expired | withdrawn`), each with a per-driver `sequence` for replay (`?after=`). A driver decline (`POST /offers/{id}/decline`) makes the system run `offer_lapsed`.
- Config: `config_published` on `/rider/config/stream` and `/driver/config/stream`; apps then re-fetch the config document.
- Admin: list endpoints with cursor paging + the same trip event stream for the live map.

## 5. Admin → app control matrix

Every admin control below has one owner page, one config path and one defined effect. Anything not listed is either backend-only (⚙️) or removed as decorative.

| Admin control (owner page) | Config path | Rider effect | Driver effect | Backend effect |
|---|---|---|---|---|
| Categories (Pricing › Manage categories) | `catalog.categories[]` | Category list, labels, seats | Category labels, which they drive | Quote engine |
| Prices, surge, commission (Pricing) | ⚙️ quote engine | Quote shown | `Offer.driverEarnings` | Fare + commission |
| Pickup pay (Pricing › Pickup pay) | `driver.pickupPay` | — | Pickup pay line on offers | Added to driver earnings |
| Live cancel fees per category (Dispatch › Rider cancel fees › Live) | `rider.cancelFees.live[categoryId]` + `driver.cancelFees.live` | Fee preview before cancel | Island fee | `riderCancelFee()` + came-closer check |
| Reservation cancel fees per category (… › Reservations) | `rider.cancelFees.reservation[categoryId]` | Free-until time, late fee | Island fee | Late fee |
| Waiting & no-show (Dispatch › Waiting at pickup; money in Pricing) | `rider.waiting`, `driver.waiting` | Waiting clock, price/min | Waiting clock, no-show button time | Waiting charge, no-show fee, driver share |
| Stops (Dispatch › Stops) | `rider.booking.maxStops` | Max stops | Stop marks | Stop pricing |
| Offer modes, timers, offer card (Dispatch › Modes) | `driver.offers` | — | Radar/Exclusive timers, card fields, auto-offline | Dispatch |
| Exclusive reasons (Dispatch) | `driver.offers.exclusiveReasons` | — | Reason line on Exclusive | — |
| Destination mode, next trips (Dispatch) | `driver.destinationMode`, `driver.nextTrips` | — | Filters, limits | Dispatch filter |
| Cancel reasons (Dispatch › Cancel reasons) | `rider.cancelReasons`, `driver.cancelReasons` | Rider reason list | Driver reason sheets | Validates `reasonCode` per actor |
| Ride check thresholds (Safety) | `rider.rideCheck`, `driver.rideCheck` | Ride check prompts | Ride check prompts | Triggers |
| Driving / rest hours (Dispatch › Rest) | `driver.drivingLimits` | — | Driving-time row, forced rest | Blocks going online |
| Feature flags (Config, one registry) | `rider.features`, `driver.features` | Scheduled rides, wallet, PIN, share trip, payment methods | Scheduled rides, performance cards | Gates commands |
| Payment methods per zone (Finance) | `rider.paymentMethods` | Methods offered | Cash collect allowed | Payment routing |
| App texts and notices (Content) | `driver.texts`, `driver.notices` | — | Island/notice texts | — |
| App update (Config › Updates) | `rider.appUpdate`, `driver.appUpdate` | Force/soft update | Force/soft update | — |
| Account status (Riders/Drivers/Fleet) | entity status | Suspended screen | On hold / suspended, can't go online | Blocks commands |
| Trip actions (Trips) | commands §3 | As table §3 | As table §3 | Transition table + permission |
| Refunds (Finance/Trips) | command `refund {amount: Money}` | Refund shown | — | Two-person approval over `refundLimit[role][country]` |

**Duplicates to remove** (Admin): Pricing per-category `cancelFee`/`freeCancelMin` → replaced by Dispatch cancel-fee tables; Reservation policy "Free cancel after accept" → removed (reservations count before pickup; live trips count after accept in the live table); Config `booking.maxStops` → Dispatch Stops; Config Reasons editor → Dispatch Cancel reasons; five "reservations on" switches → one flag `features.scheduledRides` per app with precedence country < zone < driver; Safety policy hours → Dispatch Rest.

## 6. Config documents

Two versioned documents per zone, built by the Admin exporters, read by the apps through a repository (local seed today, `GET /rider/config?zoneId` and `GET /driver/config?zoneId` later):

```
RiderAppConfig  { version, publishedAt, zoneId, currency, timeZone,
  catalog: { categories: [{ id, label, seats, sort }] },
  features: { scheduledRides, wallet, pin, shareTrip, … },
  paymentMethods: [ids],
  booking: { maxStops, bookingHorizonDays },
  cancelFees: { live: { [categoryId]: FeeRule }, reservation: { [categoryId]: FeeRule } },
  waiting: { freeWaitMin, perMin: Money, noShowAfterMin, noShowFee: Money },
  cancelReasons: [{ code, title }],
  rideCheck: {...}, appUpdate: {...} }

DriverAppConfig { version, publishedAt, zoneId, currency, timeZone,
  catalog, features,
  offers: { radarSeconds, exclusiveSeconds, offerCard: {...}, exclusiveReasons: [...], autoOffline: {...} },
  pickupPay: { perKm: Money, perMin: Money, freeKm, freeMin, ranges: [...], display: total | breakdown },
  cancelFees: { live: {...}, reservation: {...} },
  waiting: { freeWaitMin, perMin, noShowAfterMin, noShowFee, driverSharePct },
  destinationMode: {...}, nextTrips: {...},
  cancelReasons: { driverBeforeTrip, driverDuringTrip, driverNextTrip, scheduled, noShow },
  drivingLimits: {...}, rideCheck: {...}, texts: {...}, notices: {...}, appUpdate: {...} }

FeeRule { freeMin: int, type: fixed | percent, value: number, min: Money | null, max: Money | null }
   // live: freeMin = minutes after accept; reservation: freeMin = minutes before pickup
   // fixed: value is minor units; percent: value is 0–100 of the fare, rounded half-up to a whole minor unit, then clamped to min/max
```

Cancel reasons: the rider document lists `{code, title}` in the rider's language; the driver document lists codes per group and the titles come from `texts`. Unknown keys are ignored; missing keys fall back to the app's seed. `version` only increases; apps keep the last good document.

## 7. API surface (summary; full detail in `openapi.yaml`)

Rider: `POST /quotes`, `POST /trips`, `GET /trips/{id}`, `PATCH /trips/{id}` (route/payment), `POST /trips/{id}/route-quote`, `POST /trips/{id}/cancel`, `POST /trips/{id}/end-early`, `GET /trips/{id}/events`, `GET /trips/{id}/pin`, `POST /trips/{id}/rating`, `GET /rider/trips?cursor`, `GET /rider/trips/active`, `GET /rider/config`, payments (`/payment-methods`, `/payments`, `/wallet`), `/rider/profile`, `/rider/places`, `/notifications`, `/trips/{id}/messages`, `/support/tickets`.

Driver: `POST /driver/availability`, `POST /driver/location`, `GET /driver/offers`, `GET /driver/offers/stream`, `POST /offers/{id}/accept|decline`, `POST /trips/{id}/{head-to-pickup|arrive|board|start|complete|cancel|no-show}`, `POST /trips/{id}/pin/verify`, `GET /driver/reservations`, `GET /driver/config`, `GET /driver/earnings`, `/driver/profile`, `/driver/vehicles`, `/driver/documents`, `/driver/payouts`, `POST /trips/{id}/rating`.

Admin: cursor lists `GET /admin/{trips|riders|drivers|vehicles|payments|refunds|payouts|tickets|incidents}?cursor&filter`, `GET /admin/trips/{id}`, trip commands `POST /admin/trips/{id}/{cancel|reassign|assign|no-show|complete|refund|adjust}`, `POST /admin/{drivers|riders}/{id}/status`, `POST /admin/vehicles/{id}/review`, `POST /admin/documents/{id}/review`, config `GET|PUT /admin/config/{doc}` (draft) + `POST /admin/config/{doc}/publish` (approval), `GET /admin/audit?cursor`, `GET /admin/approvals`, `POST /admin/approvals/{id}/{approve|reject}`. Permissions: write actions need `*.edit` permissions; refunds above the role limit return `202 pending_approval`.

Auth (all apps): bearer token; actor and scope come from the token, never from the body.
