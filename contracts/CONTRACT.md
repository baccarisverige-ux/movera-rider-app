# Movera shared contract v0.4.4

v0.4.4: owner decision 6, after-cancel reason (§3): new rider command `POST /trips/{tripId}/cancel-reason {reasonCode, note?}` tells the reason of a cancel-first once the trip is `cancelled_by_rider` with the placeholder `something_else`. It is not a transition: no version bump, no fee change, no realtime event. A second `/cancel` stays `409 invalid_transition`.

v0.4.3: owner decision 5, route-change pricing (§3): a route change is priced from the booking, with the booked route through its booked stops; only stops that were not booked pay the stop fee, and the rider's offer raises stay in the price.

v0.4.2: owner decision 1, the `reservations.leaveNow` switch is removed. Leave now always opens the trip (§6.1); apps ignore a `leaveNow` field in an older document. Owner decision 2, reservations on/off is binding on the driver app for the whole zone (`reservations.on`) and for one driver (new `Driver.scheduledRides`, `GET /driver/profile`); reservations already accepted still run (§6.1).

v0.4.1 (additive): `DriverAppConfig.reservations` carries the Dispatch › Reservations timings to the driver app, with the new running-late ETA watch (`reservations.lateEta`, §6.1).

One contract for **Rider** (Flutter), **Driver** (Flutter) and **Admin** (React/TS), so one future backend can serve all three.
This folder is copied byte-for-byte into each repo at `contracts/`. Each repo runs contract tests that (1) check its copy matches `contracts/CHECKSUMS` and (2) replay `fixtures/*.json` through its own code. Change the contract here first, bump `version`, then copy to all three repos.

Files:

| File | What |
|---|---|
| `contract.json` | Machine-readable source of truth: enums, terminal set, transition table, cancel codes, realtime rules, error codes, currencies, categories, languages, admin dispatch rules, config defaults |
| `CONTRACT.md` | This document: entities, lifecycle per app, events, admin control matrix, config documents, API surface |
| `openapi.yaml` | REST + realtime surface v0.4 (all three apps) |
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
- **Payment methods**: `card, apple_pay, google_pay, cash, wallet` (a saved card is `card` + `paymentMethodId`). Every country offers the same four (`contract.json#zonePaymentMethods`: `cash, card, apple_pay, google_pay`, owner Q7). No `swish`, no `d17`. `wallet` is never a config payment method: it is one balance per currency (no conversion), used first. The v0.3 ids `apple` / `google` are accepted on read as `apple_pay` / `google_pay` for one release.
- **Languages**: `en, fr, sv` (`contract.json#languages`). Admin sets the default per country for the rider, driver and admin apps; the user can change it.
- **Headers**: `Idempotency-Key` on every mutation (16–128 chars, server 409s on a different body under the same key), `X-Request-Id`, `X-Api-Version: 0.4`.
- **Concurrency**: every trip/offer/driver/config command sends `expectedVersion`; a stale version gets `409 version_mismatch` with the current projection. The one exception is the rider's after-cancel reason (`POST /trips/{tripId}/cancel-reason`, §3), which does not change the trip's version.
- **Errors**: `{ code, message, requestId, retryable, projection? }`, codes in `contract.json#errors.codes`. `projection` is the current resource for `version_mismatch` / `invalid_transition` (trip, offer, driver, rider, vehicle or config draft). Validation and wrong PIN are 400 `invalid_request`; too many PIN attempts 429. Success responses are the bare resource.

## 2. Canonical entities

```
TripProjection {
  tripId, status: TripStatus, version ≥1, sequence ≥0,
  kind: live | scheduled, scheduledAt?,
  createdAt, updatedAt,
  acceptedAt: Timestamp | null,      // when a driver accepted (null before); the live free-cancel clock counts from it (owner Q12)
  riderId, driverId?, vehicleId?, zoneId, categoryId,
  pickup: Place, dropoff: Place, stops: Place[],
  quote?: { quoteId, total: Money, expiresAt },
  fare: Money,                       // current authoritative fare (rider pays)
  fareLines?: [{ code, amount: Money }],   // base, distance, time, stops, waiting, pickup_pay, surge, discount, cancel_fee
  driverEarnings?: Money, commission?: Money,
  driverBonus?: Money,               // Movera-paid extra for the driver (admin / driver only; never in the rider's fare)
  paymentMethod, paymentMethodId?, paymentStatus?: PaymentStatus, ratingStatus: RatingStatus,
  driver?: DriverSummary, driverLocation?: GeoFix, etaSeconds?,
  waiting?: { arrivedAt, freeUntil, noShowAt, chargedSeconds },
  cancellation?: { actor, reasonCode, at, fee: Money | null, note? },
  pinRequired: bool
}
DriverSummary { driverId, firstName, rating?, tripCount?, photoUrl?, vehicle: { vehicleId?, make?, model?, color?, plate?, categoryId? } }
Offer { offerId, tripId, kind: OfferKind, status: OfferStatus, version, expiresAt, fare: Money, driverEarnings: Money,
        pickupPay?: Money, fareBoost?: Money, driverBonus?: Money, priority: bool, source: system | admin, groupId?,
        pickup: Place, dropoff: Place, stops: Place[], categoryId, paymentMethod,
        pickupEtaSeconds, pickupMeters, tripSeconds, tripMeters, riderRating?, riderTrips?, scheduledAt?, reasonCode? }
        // driverBonus is already included in fare and driverEarnings as the driver sees them; priority → "Priority" badge
Quote { quoteId, categoryId, total: Money, fareLines, expiresAt, pickup, dropoff, stops, surgeMultiplier? }
Rider { riderId, firstName, phone?, email?, rating?, status: active | suspended, version }
Driver { driverId, accountStatus: DriverAccountStatus, onlineStatus: DriverOnlineStatus, firstName, rating?, zoneIds, categoryIds, vehicleId?, documents: DocumentSummary[], version }
Vehicle { vehicleId, make, model, year, color, plate, seats, categoryIds, status: pending | approved | rejected | blocked, version }
Document { documentId, ownerId, type, status: missing | in_review | approved | rejected | expired, expiresAt?, version }
PaymentIntent { paymentId, tripId, amount: Money, method, status: PaymentStatus, failureCode? }
Refund { refundId, paymentId, amount: Money, reason, status: pending_approval | done | rejected }
WalletEntry { entryId, ownerId, amount: Money, kind: topup | charge | refund | payout | adjustment, tripId?, at }
Rating { tripId, from: rider | driver, stars: 1..5 (whole stars, integer), tags[], comment? }
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
| send_offer (system) / assign (admin) | searching (admin: requested, searching, offered) | offered | Still searching | Radar / Exclusive / "Assigned by Movera" card (Priority badge when `priority`) | Direct assign or radar group (§3.1); sees offers and countdown |
| offer_lapsed (system) | offered | searching | — | Card gone ("taken" / expired) | — |
| accept (driver) | offered (scheduled: requested) | accepted | Driver card, car, ETA | Trip screen / Accepted reservation | Driver shown on trip; assignment locked |
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

### 3.1 Admin dispatch tooling (owner Q13–Q18)

Both tools are the admin `assign` transition (`contract.json#adminDispatch`); the trip stays `offered` until one driver accepts.

- **Direct assign** `POST /admin/trips/{id}/assign {driverId}`: an exclusive offer (`kind = assigned`, `source = admin`) to one driver, who accepts or declines within `offers.exclusiveSeconds`. It counts as an exclusive offer (acceptance rate, auto-offline).
- **Radar group** `POST /admin/trips/{id}/radar-group {driverIds[1..10]}`: one `radar` offer per chosen driver with the same `groupId`, on the zone's normal timer (`offers.radarSeconds`); the admin sees the countdown (`expiresAt`). The first to accept wins, the others get `offer_withdrawn` (`claimed_elsewhere`). Groups can be repeated while the trip is not locked.
- **Nearby drivers** `GET /admin/trips/{id}/nearby-drivers?scope=radius|zone|zone_and_neighbours&radiusKm=` (presets 5 / 7 / 10 km or any number).
- **Lock**: once a driver accepts (`status` in `driverAssigned` or terminal), `assign` and `radar-group` are `409 invalid_transition`.
- **Driver bonus** ("add money to trip"): `driverBonus: Money` on assign / radar-group, or `POST /admin/trips/{id}/driver-bonus`. Paid by Movera (from its commission, possibly beyond it); the rider never pays it. The driver's `Offer.fare` and `driverEarnings` already include it, and `priority: true` shows the "Priority" badge. Above the country's `driverBonus.defaultLimit` the server answers `400 invalid_request` ("adjust the limit in Pricing"); the limit can never exceed `driverBonus.hardMax`.
- **Events**: `GET /admin/dispatch/stream` (SSE, `AdminDispatchEvent`): `offer_sent, offer_declined, offer_expired, offer_withdrawn, offer_accepted, assignment_locked, driver_bonus_added`. The rider only sees "searching" then "driver assigned".

Multi-stop: `stops[]` ordered on quote, request and projection; quotes MUST include stops. Waiting at a stop is billed per `pickupWait` rules. Route changes after request create a new quote (`/trips/{id}/route-quote`) and a `PATCH` with `expectedVersion`.

Route-change pricing (v0.4.3, owner decision 5). The route quote and the `PATCH` that applies it price the whole new route from the booking, never from the current fare alone:

- `total` = booked fare (the fare at request) + every offer raise the rider made while searching + the distance price of (new route km − booked route km) + the stop fee for each stop of the new route that was not booked. It is never below half of (booked fare + raises) and is rounded to the zone's price step.
- **Booked route** = pickup → booked stops, in order → dropoff: the route the booking quote priced. A booked stop is already in the booked fare, so a booked stop the new route keeps adds no kilometres and no stop fee. A stop of the new route within 50 m of a booked stop is that booked stop; each booked stop matches one new stop, once. A booked stop the new route drops gives back its kilometres (and its `stops` fare line, if the booking quote had one).
- **Offer raises stay.** A raise the rider made to find a driver is part of the price of every new route: a route change never cancels or refunds it. The offer ceiling is worked out again from the new total.
- `difference` = `total` − current `fare`; positive is charged, negative refunded (cash: only shown). Because `total` always starts from the booking, re-quoting the route the trip already has gives `difference` 0, successive changes do not add up, and going back to the booked route gives back what the changes cost.

After-cancel reason (v0.4.4, owner decision 6). A rider who cancels before picking a reason (cancel-first) names the placeholder `something_else`, because `CancelCommand.reasonCode` is required. The reason picked afterwards is sent with `POST /trips/{tripId}/cancel-reason {reasonCode, note?}` (rider only, `CancelReasonCommand`):

- Allowed only while the trip is `cancelled_by_rider` and its `cancellation.reasonCode` is still `something_else`. It sets `cancellation.reasonCode` to the given code, and `cancellation.note` when `note` is sent, and answers `200` with the TripProjection.
- `reasonCode` must be a rider code (`contract.json#cancelReasons.rider`); any other code is `400 invalid_request`. Any other trip state, also a trip whose reason was already told, is `409 invalid_transition` with the projection. Another rider's trip is `403 forbidden` or `404 not_found`, as for every trip command.
- It is not a lifecycle command and not in the transition table. Only `cancellation.reasonCode` and `cancellation.note` change: `status`, `version`, `sequence`, `updatedAt`, `fare`, `cancellation.fee`, `cancellation.actor` and `cancellation.at` stay as the cancel left them, and no realtime event is sent (after a terminal status the gate would block a `trip_projection` anyway). Apps read the new reason from the response and from `GET /trips/{tripId}` (admin: `GET /admin/trips/{id}`).
- It takes no `expectedVersion` (the state rule already makes it one-shot) and needs `Idempotency-Key` like every mutation: a repeat with the same key and body returns the first answer.
- A second `POST /trips/{tripId}/cancel` on a cancelled trip stays `409 invalid_transition` (the table) and never changes the reason.

Live free cancel: the `freeMin` of a live FeeRule counts from `acceptedAt` (owner Q12).

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
| Waiting & no-show (Dispatch › Waiting at pickup; money in Pricing) | `rider.waiting`, `driver.waiting` (+ `byCategory`) | Waiting clock, price/min per category | Waiting clock, no-show button at the category free wait | Waiting charge (100% driver), no-show fee, driver share per country |
| Stops (Dispatch › Stops) | `rider.booking.maxStops`, `driver.booking.maxStops` | Max stops | Stop marks | Stop pricing |
| Pickup move after accept (Dispatch) | `rider.booking.maxPickupMoveMeters`, `driver.booking.maxPickupMoveMeters` | Move pickup up to N m, further = cancel/rebook | Notified of the move | Rejects a bigger move |
| Tips (Pricing, per country) | `rider.tips` | Tip options | — | Tip limits |
| Raise-offer steps (Pricing, per country) | `rider.raiseSteps` | Quick "+" steps while searching | — | Fare raise |
| Promo cap (Riders › Promotions, per country) | `rider.promoCap` | Shown in local money | — | Caps the discount |
| Driver bonus limits (Pricing, per country) | `driver.driverBonus` | — | — | Admin "add money to trip" limits |
| Default languages (Settings, per country) | `rider.languages`, `driver.languages` | Default app language | Default app language | — |
| Offer modes, timers, offer card (Dispatch › Modes) | `driver.offers` | — | Radar/Exclusive timers, card fields, auto-offline | Dispatch |
| Exclusive reasons (Dispatch) | `driver.offers.exclusiveReasons` | — | Reason line on Exclusive | — |
| Reservations: steps, smart gap, Leave now, running late, cancels (Dispatch › Reservations) | `driver.reservations` (§6.1) | — | Home popup / Exclusive / Radar times, Leave now (always opens the trip), late warning, ETA watch, offline backup, late-cancel pause | Reassigns a late or offline driver's ride |
| Scheduled rides for one driver (Drivers › driver page; Dispatch › Reservations desk) | `Driver.scheduledRides` (§6.1) | — | Off: no new reservations; accepted ones still run. On: the late-cancel pause is skipped while it lasts | Offers and assigns no reservation to a driver who is off |
| Destination mode, next trips (Dispatch) | `driver.destinationMode`, `driver.nextTrips` | — | Filters, limits | Dispatch filter |
| Cancel reasons (Dispatch › Cancel reasons) | `rider.cancelReasons`, `driver.cancelReasons` | Rider reason list | Driver reason sheets | Validates `reasonCode` per actor |
| Ride check thresholds (Safety) | `rider.rideCheck`, `driver.rideCheck` | Ride check prompts | Ride check prompts | Triggers |
| Driving / rest hours (Dispatch › Rest) | `driver.drivingLimits` | — | Driving-time row, forced rest | Blocks going online |
| Feature flags (Config, one registry) | `rider.features`, `driver.features` | Scheduled rides, wallet, PIN, share trip, payment methods | Scheduled rides, performance cards | Gates commands |
| Payment methods per zone (Finance) | `rider.paymentMethods`, `driver.paymentMethods` | Methods offered (wallet first) | Cash collect allowed | Payment routing |
| App texts and notices (Content) | `driver.texts`, `driver.notices` | — | Island/notice texts | — |
| App update (Config › Updates) | `rider.appUpdate`, `driver.appUpdate` | Force/soft update | Force/soft update | — |
| Account status (Riders/Drivers/Fleet) | entity status | Suspended screen | On hold / suspended, can't go online | Blocks commands |
| Trip actions (Trips) | commands §3 | As table §3 | As table §3 | Transition table + permission |
| Refunds (Finance/Trips) | command `refund {amount: Money}` | Refund shown | — | Two-person approval over `refundLimit[role][country]` |

**Duplicates to remove** (Admin): Pricing per-category `cancelFee`/`freeCancelMin` → replaced by Dispatch cancel-fee tables; Reservation policy "Free cancel after accept" → removed (reservations count before pickup; live trips count after accept in the live table); Config `booking.maxStops` → Dispatch Stops; Config Reasons editor → Dispatch Cancel reasons; five "reservations on" switches → one flag `features.scheduledRides` per app with precedence country < zone < driver; Safety policy hours → Dispatch Rest.

## 6. Config documents

Two versioned documents per zone, built by the Admin exporters, read by the apps through a repository (local seed today, `GET /rider/config?zoneId` and `GET /driver/config?zoneId` later):

```
RiderAppConfig  { version, publishedAt, zoneId, currency, timeZone, country, languages,
  catalog: { categories: [{ id, label, seats, sort }] },
  features: { scheduledRides, wallet, pin, shareTrip, … },
  paymentMethods: [ZonePaymentMethod],          // cash | card | apple_pay | google_pay
  wallet: { usedFirst: bool },                  // one balance per currency; on/off is features.wallet
  tips: [AmountOption], raiseSteps: [AmountOption], promoCap: Money | null,
  booking: { maxStops, bookingHorizonDays, maxPickupMoveMeters },
  cancelFees: { live: { [categoryId]: FeeRule }, reservation: { [categoryId]: FeeRule } },
  waiting: { freeWaitMin, perMin: Money, noShowAfterMin, noShowFee: Money, byCategory: { [categoryId]: CategoryWaiting } },
  cancelReasons: [{ code, title }],
  rideCheck: {...}, appUpdate: {...} }

DriverAppConfig { version, publishedAt, zoneId, currency, timeZone, country, languages,
  catalog, features, paymentMethods: [ZonePaymentMethod],
  booking: { maxStops, maxPickupMoveMeters },
  offers: { radarSeconds, exclusiveSeconds, offerCard: {...}, exclusiveReasons: [...], autoOffline: { missedExclusive, … } },
  pickupPay: { perKm: Money, perMin: Money, freeKm, freeMin, ranges: [...], display: total | breakdown },
  driverBonus: { defaultLimit: Money, hardMax: Money },
  cancelFees: { live: {...}, reservation: {...} },
  waiting: { freeWaitMin, perMin, noShowAfterMin, noShowFee, driverSharePct, driverShareWaitPct, byCategory: { [categoryId]: CategoryWaiting } },
  destinationMode: {...}, nextTrips: {...},
  reservations: DriverReservations,             // §6.1
  cancelReasons: { driverBeforeTrip, driverDuringTrip, driverNextTrip, scheduled, noShow },
  drivingLimits: {...}, rideCheck: {...}, texts: {...}, notices: {...}, appUpdate: {...} }

languages      { available: [Language], default: { rider: Language, driver: Language, admin: Language } }   // Language = en | fr | sv
AmountOption   { amount: Money, enabled: bool }       // in the zone's currency; disabled options are not shown
CategoryWaiting { freeWaitMin, perMin: Money, noShowAfterMin, noShowFee: Money }   // noShowAfterMin = freeWaitMin (Q41)
FeeRule { freeMin: int, type: fixed | percent, value: number, min: Money | null, max: Money | null }
   // live: freeMin = minutes after accept; reservation: freeMin = minutes before pickup
   // fixed: value is minor units; percent: value is 0–100 of the fare, rounded half-up to a whole minor unit, then clamped to min/max
```

Per-zone settings (owner round 2; defaults in `contract.json#configDefaults`, used by the Admin exporter where no setting exists yet and by the apps when a field is missing or invalid):

| Field | Rider | Driver | Default |
|---|---|---|---|
| `country` (ISO 3166 alpha-2), `timeZone` (IANA) | ✓ | ✓ | Z001 `SE` Europe/Stockholm · FR-PC `FR` Europe/Paris · TN-TC `TN` Africa/Tunis |
| `languages` | ✓ | ✓ | available `en, fr, sv`; default `sv` in SE, `fr` in FR and TN (rider, driver and admin) |
| `tips` | ✓ | — | SE 10 / 20 / 30 kr · FR 1 / 2 / 5 € · TN 1 / 2 / 3 DT |
| `raiseSteps` | ✓ | — | SE +50 / 100 / 150 / 200 kr · FR +2 / 4 / 6 / 8 € · TN +2 / 4 / 6 / 8 DT |
| `paymentMethods` | ✓ | ✓ | `cash, card, apple_pay, google_pay` in every country |
| `wallet.usedFirst` | ✓ | — | `true` (one wallet per currency) |
| `promoCap` | ✓ | — | `null` (no cap) until Admin sets one per country |
| `booking.maxStops` | ✓ | ✓ | 3 |
| `booking.maxPickupMoveMeters` | ✓ | ✓ | 500 (further = cancel and rebook; the driver is notified) |
| `waiting.byCategory[].freeWaitMin` = `noShowAfterMin` | ✓ | ✓ | 5 min, `xl` 3 min |
| `waiting.byCategory[].perMin` (waiting fee after the free wait) | ✓ | ✓ | from Pricing; `driverShareWaitPct` 100 |
| `waiting.driverSharePct` (no-show fee share, per country) | — | ✓ | 80 |
| `offers.autoOffline.missedExclusive` (missed/declined exclusive offers in a row → offline) | — | ✓ | 3 |
| `driverBonus.defaultLimit` / `hardMax` | — | ✓ | SE 200 / 1000 kr · FR 20 / 95 € · TN 60 / 300 DT |

All Money above is in the zone's currency; an amount in another currency is invalid and falls back to the default. The top-level `waiting` terms are the headline category's (`economy`, else the first).

### 6.1 `DriverAppConfig.reservations`

Built by Admin from Dispatch › Reservations of the zone. Every field is optional on read: a missing or invalid field keeps the driver app's default, which is `contract.json#configDefaults.reservations` (the values below).

```
DriverReservations {
  on: true,                     // reservations for every driver in the zone (= features.scheduledRides); off: no new ones, accepted ones still run
  lateWarn: true,               // "Head to your 07:40 pickup" island warning when Leave now cannot start
  offlineBackupAfterMin: 5,     // 1–60. Only an OFFLINE driver loses the ride this long after Leave now; an online driver keeps it
  homePopupAfterMin: 10,        // untaken: Home popup this long after booking
  exclusiveBeforeMin: 20,       // untaken: Exclusive from this long before pickup
  radarBeforeMin: 15,           // untaken: Radar trips from this long before pickup
  onDriverCancel: "byTime",     // byTime | list | home | exclusive
  hideClashing: true,           // rides that do not fit the smart gap leave the driver's list once they take one
  towardPickup: true, towardPickupBeforeMin: 60,
  longTripKm: 50,               // a ride longer than this is a longTrip
  driverLateCancelHours: 1,     // a driver cancel closer to pickup is a late cancel
  lateCancelLimit: 2, lateCancelPeriodDays: 7, pauseDays: 7,   // limit late cancels in the period → no scheduled rides for pauseDays
  assignAcceptSeconds: 30,      // time to accept a ride assigned by Movera
  rideTypes: { normal | airport | longTrip | comfortPremium | event:
               { onlineBeforeMin, spareMin, reminderMin: [int] } },  // defaults 30/60/60/45/45, spare 15, reminders [60, 15]
  lateEta: { on: true, toleranceMin: 3, checkEverySeconds: 60, reassignTo: "exclusive" } }
```

- **Leave now** fires at the driver's estimated drive time to the pickup + `rideTypes[kind].spareMin` before pickup (an estimate, not live traffic). It always opens the trip, heading to the pickup; there is no switch for it (v0.4.2, owner decision 1). When the trip cannot open at that moment (the driver is offline, or another screen or an offer answer is in the way), the `lateWarn` warning shows and the trip opens as soon as it can. A `leaveNow` field in an older document is ignored.
- **Running late (`lateEta`)**: from Leave now until the driver arrives at the pickup, the driver's ETA is checked every `checkEverySeconds` (15–600). When `now + ETA > pickup time + toleranceMin` (`toleranceMin` 0–30), the ride is reassigned early to `reassignTo`: `exclusive` (Exclusive offer to the nearest available driver), `radar` (Radar trips) or `dispatch` (back to admin dispatch). Otherwise an online driver keeps the ride.
- **Offline driver**: only a driver who is offline at Leave now loses the ride, after `offlineBackupAfterMin`. An online driver is never removed by that timer.
- **Reservations on/off (owner decision 2)**: a driver gets new reservations (Scheduled rides requests, the Home popup, Exclusive and Radar reservation offers, rides Movera assigns) only while the zone's `reservations.on` (and `features.scheduledRides`) is true **and** their `Driver.scheduledRides` does not turn them off. Off, for the zone or for the driver, the app lists no open requests and shows no reservation offer, and the backend offers and assigns none to that driver. Reservations the driver already accepted stay theirs and run as usual: reminders, Leave now, the ETA watch, cancel.
- `Driver.scheduledRides { on: bool, until: Timestamp | null }` (on `GET /driver/profile`): the admin's choice for this one driver. Missing = no choice (the zone switch and the late-cancel pause decide). `on: false` = no new reservations until `until` (null = until an admin turns them on). `on: true` = on until `until`, and the late-cancel pause is skipped while it lasts. A zone that is off wins over `on: true`.
- Admin ids map: `normal → normal`, `airport → airport`, `long → longTrip`, `premium → comfortPremium`, `event → event`; Admin `lateBackupAfterMin` is `offlineBackupAfterMin`.

Cancel reasons: the rider document lists `{code, title}` in the rider's language; the driver document lists codes per group and the titles come from `texts`. Unknown keys are ignored; missing keys fall back to the app's seed. `version` only increases; apps keep the last good document.

## 7. API surface (summary; full detail in `openapi.yaml`)

Rider: `POST /quotes`, `POST /trips`, `GET /trips/{id}`, `PATCH /trips/{id}` (route/payment), `POST /trips/{id}/route-quote`, `POST /trips/{id}/cancel`, `POST /trips/{id}/cancel-reason`, `POST /trips/{id}/end-early`, `GET /trips/{id}/events`, `GET /trips/{id}/pin`, `POST /trips/{id}/rating`, `GET /rider/trips?cursor`, `GET /rider/trips/active`, `GET /rider/config`, payments (`/payment-methods`, `/payments`, `/wallet`), `/rider/profile`, `/rider/places`, `/notifications`, `/trips/{id}/messages`, `/support/tickets`.

Driver: `POST /driver/availability`, `POST /driver/location`, `GET /driver/offers`, `GET /driver/offers/stream`, `POST /offers/{id}/accept|decline`, `POST /trips/{id}/{head-to-pickup|arrive|board|start|complete|cancel|no-show}`, `POST /trips/{id}/pin/verify`, `GET /driver/reservations`, `GET /driver/config`, `GET /driver/earnings`, `/driver/profile`, `/driver/vehicles`, `/driver/documents`, `/driver/payouts`, `POST /trips/{id}/rating`.

Admin: cursor lists `GET /admin/{trips|riders|drivers|vehicles|payments|refunds|payouts|tickets|incidents}?cursor&filter`, `GET /admin/trips/{id}`, trip commands `POST /admin/trips/{id}/{cancel|reassign|assign|radar-group|driver-bonus|no-show|complete|refund|adjust}`, dispatch `GET /admin/trips/{id}/offers`, `GET /admin/trips/{id}/nearby-drivers`, `GET /admin/dispatch/stream`, `POST /admin/{drivers|riders}/{id}/status`, `POST /admin/vehicles/{id}/review`, `POST /admin/documents/{id}/review`, config `GET|PUT /admin/config/{doc}` (draft) + `POST /admin/config/{doc}/publish` (approval), `GET /admin/audit?cursor`, `GET /admin/approvals`, `POST /admin/approvals/{id}/{approve|reject}`. Permissions: write actions need `*.edit` permissions; refunds above the role limit return `202 pending_approval`.

Auth (all apps): bearer token; actor and scope come from the token, never from the body.
