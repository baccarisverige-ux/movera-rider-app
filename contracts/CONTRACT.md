# Movera shared contract v0.5.5

v0.5.5 (additive; X-Api-Version stays `0.5`): **the rider raises their offer** (§3.6, owner decision 25, 2026-10-26): `POST /trips/{tripId}/raise-price { expectedVersion, increase }` while the trip is `searching` or `offered`: the fare grows by `increase` (a `rider_raise` fare line), the whole raise goes to the driver's earnings (Movera's share is unchanged), open offers are withdrawn and a new search starts in which drivers who already declined are asked again at the new price; `version` + 1. At most `contract.json#dispatch.raisePrice.maxFactor` (2) × the quoted fare. The `raise_price` waiting step stays skipped: the rider app offers the raise on its own schedule. The refund and payout additions the server already does move to v0.5.6.

v0.5.4 (additive; X-Api-Version stays `0.5`): **the rider's "I'm on the way"** (§4): `POST /trips/{tripId}/on-the-way` (rider, while the trip is `accepted`, `driver_to_pickup` or `arrived`) raises the `rider_on_the_way` realtime event for the driver, with the current projection; no status or version change. The refund and payout additions the server already does move to v0.5.5.

v0.5.3 (additive; X-Api-Version stays `0.5`): **driver sign-up and fleets** (§14, `contract.json#driverOnboarding`), owner decisions of 2026-10-25: after the phone sign-in (§8) the driver app sends its details once (`POST /driver/onboarding`: name, date of birth, e-mail, country, city, language, account type `driver` | `fleet`, the company for a fleet, an optional fleet join) and the account waits `on_hold` until an admin activates it; fleets (`Fleet`, `FleetView`, `FleetInvitation`, `GET /driver/fleet`, `POST /driver/fleet/join|leave|invite`, `GET /driver/fleet/invitations`, `POST /driver/fleet/invitations/{invitationId}/accept|decline|cancel`, `POST /driver/fleet/drivers/{driverId}/remove`, `GET /driver/fleet/earnings`; admin `GET /admin/fleets`, `GET /admin/fleets/{fleetId}`, `POST /admin/fleets/{fleetId}/review|code`, `POST /admin/fleets/{fleetId}/invitations/{invitationId}/accept|cancel`, `POST /admin/fleets/{fleetId}/drivers/{driverId}/remove`) joined by a two-sided invitation (the driver asks with a server-made code plus the owner's name and e-mail, or the owner invites a phone number; the other side accepts; 7 days; in-app notice and one SMS); fleet-owned cars picked by one driver at a time (`Vehicle.fleetId`, `driverId`, `inUse`); the documents each country and account type needs (`contract.json#driverOnboarding.documents`, `Driver.requiredDocuments`, `requiredFleetDocuments`, `Vehicle.requiredDocuments`), uploaded to the server and read back only through `GET /driver/documents/{documentId}/file` and `GET /admin/documents/{documentId}/file`; `GET /admin/drivers/{driverId}`; `Driver` gains `accountType`, `pendingFleetInvitations`, `lastName`, `dateOfBirth`, `email`, `country`, `cityId`, `language`, `termsAcceptedAt`, `fleet`, `payoutTo`; `Document` gains `fileName`, `mediaType`, `uploadedAt`, `reviewedAt`. Tunisia is listed but not open. The refund and payout additions the server already does move to v0.5.4.

v0.5.2 (additive; X-Api-Version stays `0.5`): **nearby cars on the rider's map** (§13): `GET /rider/nearby-vehicles?lat&lng` gives the free cars near the rider while it chooses a ride, without anything that tells who drives them (`contract.json#riderNearby`).

v0.5.1 (additive; X-Api-Version stays `0.5`): what the server needs for the first test week, with the owner decisions of 2026-10-24 (`docs/DECISIONS.md` of the server; in the v0.5.1 sections "owner decision N" means that list, not the earlier numbering of v0.4.x–v0.5.0). **Server-only pricing and dispatch documents** (§6.2, §6.3): `ConfigDocName` gains `pricing` and `dispatch`, published like the app documents but never served to the apps; the **fare formula** (§3.5, `contract.json#pricing`, `fixtures/fares.json`) in the order of the admin panel's calculator, with commission-free waiting, the app fee and pickup fee outside the commission, 3 free minutes per stop and the rider's end-early price; **automatic dispatch** (§3.6, `contract.json#dispatch`, `fixtures/dispatch.json`) as the admin panel's rules describe it, with the search gap filled, declined drivers re-offered on Radar and the "Keep waiting?" answers (`TripProjection.searchStep`, `POST /trips/{tripId}/keep-waiting`), and the live switch `PUT /admin/zones/{zoneId}/dispatch-control`; **unpaid cash fees** (§3.7): `Rider.outstanding`, the `outstanding_fee` line and `Cancellation.feeStatus`; **admin sign-in** (§9): e-mail and password, a one-time setup link, `AdminMe` with the panel's 34 permissions (`AdminPermission`; every admin operation's `x-permission` now uses them, the v0.5.0 value stays as `x-permission-v050`), and the Super admin's approval exemption; **locations and routes** (§10): `POST /locations/autocomplete|geocode|reverse-geocode` (the one `latitude`/`longitude` exception), `POST /routes`, `GET /routes/driving/{coordinates}`; **telemetry** (§11): `POST /telemetry/logs|analytics|crashes`; **admin live drivers** (§12): `GET /admin/live/drivers`, `GET /admin/trips/{tripId}/trace`, `Driver.location`. Also: optional `pickup` on `UpdateTripRequest` and `RouteQuoteRequest`; `POST /account/deletion`; `Rider.language` and `consents`; new rider fare line codes (`app_fee`, `minimum_adjust`, `maximum_adjust`, `stop_waiting`, `extras`, `airport`, `reservation_fee`, `fixed_route`, `rounding`, `outstanding_fee`); and the `accept` row split so that `accept` from `requested` carries `when: scheduled`, which its note already said. Which zones are open in the test week is a deploy setting, not contract.
Owner decisions cited with (2026-10-24) are numbered as in movera-server docs/DECISIONS.md; earlier citations use the numbering of their own version.

v0.5.0 (additive, the first version of the `movera-contracts` repository; X-Api-Version `0.5`): **pickup pay** as the owner decided it (§3.2): the rider's fixed pickup fee per category for live rides and reservations (`pickup_fee` fare line, `RiderAppConfig.pickupFee`) and the driver's Movera-paid tiered km ranges with a maximum per ride (`DriverAppConfig.pickupPay.byCategory`, `Offer.pickupPay`, `TripProjection.pickupPay`), with `fixtures/pickup_pay.json`; **offers while driving** (§3.3): the driver app's stopped / driving judgement travels as `GeoFix.moving` (+ `speedMps`) and the Radar limits per state come in `DriverAppConfig.offers.radarApp` / `exclusiveWhileDriving`; **surge schedule** (§3.4): an admin surge curve over time (`SurgeSchedule`, `PUT /admin/zones/{zoneId}/surge`, `Quote.surge`), with `fixtures/surge.json`; **sign-in, tokens and push devices** (§8): `POST /auth/otp/request|verify`, `/auth/provider`, `/auth/refresh`, `/auth/sign-out`, `/push/devices`, test numbers with a fixed code outside production, the error code `otp_expired` and an optional `Error.reason`; and the meaning of the config document `version` (§6). Fare line codes now live in `contract.json#fareLines`: the rider's pickup line is `pickup_fee` (a v0.4 `pickup_pay` line in a rider fare is read as `pickup_fee` for one release); `pickup_pay` and `driver_bonus` are driver-only lines. The v0.4 `pickupPay` keys (`perKm`, `perMin`, `freeKm`, `freeMin`, top-level `ranges`) stay in the driver document for one release, filled from the headline category.

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
| `openapi.yaml` | REST + realtime surface v0.5 (all three apps) |
| `fixtures/scenarios.json` | Trip lifecycle scenarios (commands × actors → status or `invalid_transition`), plus who may rate the trip afterwards (`rating`) |
| `fixtures/events.json` | Realtime gate cases (accepted / gap / duplicate / blocked / invalid) |
| `fixtures/money.json` | Money minor-unit cases incl. TND (3 decimals) |
| `fixtures/cancel_fees.json` | Cancel fee rule cases (live and reservation) |
| `fixtures/pickup_pay.json` | Driver pickup pay cases: tiered ranges, minute split, maximum per ride, kinds that get none (§3.2) |
| `fixtures/surge.json` | Surge schedule cases: the step in force at a time (§3.4) |
| `fixtures/fares.json` | Fare cases: every line, the total, the driver's earnings and Movera's share (§3.5, v0.5.1) |
| `fixtures/dispatch.json` | Automatic dispatch timelines: the offers sent, the rider-waiting steps and how the search ends (§3.6, v0.5.1) |
| `fixtures/config/*.json` | Sample `RiderAppConfig` and `DriverAppConfig` documents; the server-only `PricingDocument` (`pricing_document.json`) and `DispatchDocument` (`dispatch_document.json`) of Z001 (v0.5.1) |
| `reference_check.py` | Reference engine; proves the fixtures agree with `contract.json` |

---

## 1. Wire rules

- **Ids**: opaque strings `^[A-Za-z0-9_-]{1,64}$`. `tripId` is the trip. `offerId` is an offer (one trip, many offers). `rideId` is a read-only legacy alias of `tripId`. Clients never invent a `tripId`.
- **Time**: RFC 3339 UTC with `Z`. Durations are integer seconds. Zone-local wall times (surge windows, `HH:mm`) carry the zone `timeZone`.
- **Money**: `{ "amountMinor": int, "currency": "SEK" }`. Exponent from ISO 4217 (`SEK`/`EUR` 2, `TND` 3). No floats, no display strings (`"126,75 kr"`) on the wire. Apps format locally.
- **Location**: `Place { address?, lat, lng }` for pickup, dropoff, stops (ordered). `GeoFix { lat, lng, accuracy, heading?, speedMps?, moving?, measuredAt }` for device GPS only; `moving` is the driver app's stopped / driving judgement (§3.3). JSON says `lat`/`lng`; Dart may keep `latitude`/`longitude` inside.
- **Location exception (v0.5.1)**: the bodies of `POST /locations/autocomplete`, `/locations/geocode` and `/locations/reverse-geocode` say `latitude`/`longitude`, the names the rider app sends and reads (§10). This is the only exception; `POST /routes` and everything else keep `lat`/`lng`.
- **Case**: keys camelCase, enum values snake_case.
- **Categories**: ids from the admin Pricing catalog (`^[a-z][a-z0-9_]{1,31}$`). Seed: `economy, comfort, premium, priority, xl, electric, pet`. Alias `movera → economy` accepted on read for one release. Labels are display only.
- **Payment methods**: `card, apple_pay, google_pay, cash, wallet` (a saved card is `card` + `paymentMethodId`). Every country offers the same four (`contract.json#zonePaymentMethods`: `cash, card, apple_pay, google_pay`, owner Q7). No `swish`, no `d17`. `wallet` is never a config payment method: it is one balance per currency (no conversion), used first. The v0.3 ids `apple` / `google` are accepted on read as `apple_pay` / `google_pay` for one release.
- **Languages**: `en, fr, sv` (`contract.json#languages`). Admin sets the default per country for the rider, driver and admin apps; the user can change it.
- **Headers**: `Idempotency-Key` on every mutation (16–128 chars, server 409s on a different body under the same key), `X-Request-Id`, `X-Api-Version: 0.5`.
- **Read-only POSTs (v0.5.1)**: `POST /locations/*`, `POST /routes`, `POST /admin/auth/setup-password/check` and `POST /telemetry/*` change nothing (`x-read-only` in `openapi.yaml`): they take no `Idempotency-Key` and the server must not ask for one. Telemetry also needs no bearer token and no standard headers (§11).
- **Concurrency**: every trip/offer/driver/config command sends `expectedVersion`; a stale version gets `409 version_mismatch` with the current projection. The one exception is the rider's after-cancel reason (`POST /trips/{tripId}/cancel-reason`, §3), which does not change the trip's version.
- **Errors**: `{ code, message, requestId, retryable, reason?, projection? }`, codes in `contract.json#errors.codes`; `reason` is an optional machine-readable detail under the code (`invalid_phone`, `invalid_otp_code`, …), never shown as is. `projection` is the current resource for `version_mismatch` / `invalid_transition` (trip, offer, driver, rider, vehicle or config draft). Validation and wrong PIN are 400 `invalid_request`; too many PIN attempts 429. Success responses are the bare resource.

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
  fareLines?: [{ code, amount: Money }],   // contract.json#fareLines: base, distance, time, stops, waiting, pickup_fee, surge, discount, cancel_fee
  driverEarnings?: Money, commission?: Money,
  driverBonus?: Money,               // Movera-paid extra for the driver (admin / driver only; never in the rider's fare)
  pickupPay?: Money,                 // Movera-paid driver pickup pay (admin / driver only; never in the rider's fare), §3.2
  paymentMethod, paymentMethodId?, paymentStatus?: PaymentStatus, ratingStatus: RatingStatus,
  driver?: DriverSummary, driverLocation?: GeoFix, etaSeconds?,
  waiting?: { arrivedAt, freeUntil, noShowAt, chargedSeconds },
  cancellation?: { actor, reasonCode, at, fee: Money | null, note? },
  pinRequired: bool,
  searchStep?: { id, kind, message, extraMin: int | null, at }   // v0.5.1: the latest rider-waiting step while searching (§3.6)
}
  // v0.5.1: fareLines codes add app_fee, minimum_adjust, maximum_adjust, stop_waiting, extras, airport, reservation_fee, fixed_route, rounding,
  //         outstanding_fee (§3.5); FareLine.sourceTripId? on outstanding_fee; cancellation.feeStatus?: paid | owed | waived (§3.7);
  // v0.5.5: fareLines code rider_raise (the rider's own raise while searching, §3.6).
  //         commission = Movera's share of the fare (fare − driverEarnings)
DriverSummary { driverId, firstName, rating?, tripCount?, photoUrl?, vehicle: { vehicleId?, make?, model?, color?, plate?, categoryId? } }
Offer { offerId, tripId, kind: OfferKind, status: OfferStatus, version, expiresAt, fare: Money, driverEarnings: Money,
        pickupPay?: Money, fareBoost?: Money, driverBonus?: Money, priority: bool, source: system | admin, groupId?,
        pickup: Place, dropoff: Place, stops: Place[], categoryId, paymentMethod,
        pickupEtaSeconds, pickupMeters, tripSeconds, tripMeters, riderRating?, riderTrips?, scheduledAt?, reasonCode? }
        // driverBonus is already included in fare and driverEarnings as the driver sees them; priority → "Priority" badge
Quote { quoteId, categoryId, total: Money, fareLines, expiresAt, pickup, dropoff, stops, surgeMultiplier?, surge?: { multiplier, until?, scheduleId? } }
       // surgeMultiplier stays with the quote whatever the schedule does next (§3.4); pickup_fee is in fareLines when the category has a rider pickup fee (§3.2)
Rider { riderId, firstName, phone?, email?, rating?, status: active | suspended, version,
        outstanding?: Money | null, language?, consents?: { rideUpdates, emailUpdates, promotions } }   // v0.5.1: unpaid cash fees (§3.7), profile language and consents
Driver { driverId, accountStatus: DriverAccountStatus, onlineStatus: DriverOnlineStatus, moving?: bool, firstName, rating?, zoneIds, categoryIds, vehicleId?, documents: DocumentSummary[], version }
       // v0.5.3 (§14): accountType?: driver | fleet, lastName?, dateOfBirth?, email?, country?, cityId?, language?, termsAcceptedAt?, fleet?: FleetLink, payoutTo?: self | fleet,
       //               requiredDocuments: DocumentType[], requiredFleetDocuments?: DocumentType[]
       // moving mirrors the latest GeoFix.moving the driver app sent (§3.3)
       // v0.5.1, admin view only: location?: GeoFix, lastFixAt? (§12)
Vehicle { vehicleId, make, model, year, color, plate, seats, categoryIds, status: pending | approved | rejected | blocked, version }
        // v0.5.3 (§14): fleetId?, driverId? (who has it picked), inUse?: bool, documents: DocumentSummary[], requiredDocuments: DocumentType[]
Fleet { fleetId, name, orgNumber, address?, country, cityId, ownerDriverId, ownerName, ownerEmail? (owner / admin), status: pending | approved | rejected | blocked,
        code? (owner / admin, after approval), driverCount, vehicleCount, createdAt, version }   // v0.5.3 (§14)
Document { documentId, ownerId, type, status: missing | in_review | approved | rejected | expired, expiresAt?, version }
         // v0.5.3 (§14): fileName?, mediaType?, uploadedAt?, reviewedAt?; fileUrl is the file endpoint's path
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
- **Second-admin approval (v0.5.1, owner decision 14 (2026-10-24))**: a Super admin (role `super`, `AdminMe.approvalExempt: true`) never needs a second admin: refunds, adjusts, config publishes, surge and dispatch control run at once (`200`/`201`, never `202 pending_approval`) and are written in the audit. Big changes by other admins still answer `202 pending_approval` and wait for another admin (`POST /admin/approvals/{id}/approve`, `approval.decide`; for dispatch rules the panel's `dispatch.approve`).

### 3.2 Pickup pay (v0.5.0, owner decision 7)

Two separate sides (`contract.json#pickupPay`, Admin Pricing › Pickup pay, per zone and category). Cases every app's maths must reproduce: `fixtures/pickup_pay.json`.

- **Rider side, a fixed fee.** `PickupPayRate.riderFee { live: Money | null, reservation: Money | null }`: one amount for live rides (Radar and Exclusive), one for reservations, `null` = off. When on, the quote carries it as the `pickup_fee` fare line and the rider pays it whatever driver comes or how far away they are; Movera keeps it. The rider document names the fees in `pickupFee.byCategory` so the app can label the line; the server prices.
- **Driver side, paid by Movera.** `DriverAppConfig.pickupPay.byCategory[categoryId]: PickupPayRate { enabled, maxPerRide: Money | null, ranges: PickupRange[], riderFee }` with `PickupRange { fromKm, toKm: number | null, perKm: Money, perMin: Money }`. The first range starts at 0 (it may be free: rates 0), each next one starts where the one before ends, only the last may be open (`toKm` null). The pickup leg (from the driver's location when the offer is made; for a next trip while driving, from the current drop-off) is paid **tiered**: every km at the rate of the range it falls in, the minutes split across the ranges in proportion to the km in each (0 km: all the minutes in the first range), a leg beyond a closed last range at the last range's rate. Each range part is `half_up(km × perKm) + half_up(minutes × perMin)` in minor units; the parts add up, then `min(total, maxPerRide)`. `enabled: false` or a category not listed pays 0.
- **Which offers.** `pickupPay.offers { radar, exclusive, exclusiveReservation, assigned, nextTrip }` switches each kind; a reservation the driver took from the Scheduled rides list never gets pickup pay. Reservations offered as Exclusive, or in Radar near pickup time, are `exclusiveReservation`.
- **On the wire.** The server works the pay out when it makes the offer and sends `Offer.pickupPay`; the driver app shows the total only (`display: total`): the offer card's fare is `fare + pickupPay`, no breakdown. The accepted trip keeps it as `TripProjection.pickupPay` (driver and admin views; never in the rider's `fare`), and it is in `EarningsPeriod.pickupPay`. Money split: the rider pays `fare` (its `pickup_fee` line inside); the driver gets `driverEarnings + pickupPay + driverBonus`; Movera keeps `fare − driverEarnings − pickupPay − driverBonus`, and covers the difference when that is below 0 (the admin shows "Movera covers").
- **Defaults** (`contract.json#configDefaults.pickupPay`, placeholders until the owner sets the real amounts in Pricing): every offer kind on, display `total`, no maximum, the rider fee off with suggested amounts per country, the driver's first km free then the headline category's rate. The sample documents under `fixtures/config/` show the simplest state (fees `null`, no maximum, one range for every distance); `fixtures/pickup_pay.json` shows tiered ranges with a free first km, a fee and a maximum.
- **One release of compatibility.** The driver document keeps the v0.4 keys (`perKm`, `perMin`, `freeKm`, `freeMin`, top-level `ranges`, `maxPerRide`) filled from the headline category until v0.6; an app on the new shape ignores them. A v0.4 rider fare line coded `pickup_pay` is read as `pickup_fee`.

### 3.3 Offers while driving (v0.5.0, owner round 3)

The driver app decides **stopped / driving** from the device (`contract.json#driverMotion`): moving when the speed is at least `movingSpeedMps` (1 m/s) for `hysteresisSeconds` (10 s), stopped when below it for 10 s, so the state does not flicker at a traffic light. It sends the judgement as `GeoFix.moving` (and `speedMps`) in `POST /driver/location` and applies the limits itself at once; the server mirrors the latest value in `Driver.moving` (also on nearby-driver rows) and never sends more open offers than the limit of the driver's current state: an offer above it is held and sent when a slot frees, or dropped when it expires.

| Driver state | Full-screen Radar list | Offer cards over the map | Exclusive |
|---|---|---|---|
| No rider on board, stopped | up to `offers.radarApp.full` (when `fullOn`) | up to `offers.radarApp.popup` (when `popupOn`) | as today |
| No rider on board, moving | locked while `offers.radarApp.fullLockWhileDriving`; opens again once stopped | up to `offers.radarApp.popupWhileDriving` when `popupSplitByDriving`, else `popup` | as today |
| Rider on board | never Radar (Q18) | never Radar | only while `offers.exclusiveWhileDriving.on`, at most `count` at a time; cards never cover navigation |

Defaults (`contract.json#configDefaults.offers`): `radarApp { fullOn: true, full: 8, fullLockWhileDriving: true, popupOn: true, popup: 2, popupSplitByDriving: false, popupWhileDriving: 1 }`, `exclusiveWhileDriving { on: true, count: 1 }`. The owner's numbers for the test (N while stopped, M while driving) go in Admin Dispatch › Modes; they are not contract values. `offers.radarOn`, `offers.exclusiveOn` and `offers.assignAcceptSeconds` also travel in the driver document (the admin already exports them).

### 3.4 Surge schedule (v0.5.0)

An admin surge may change over its time like a speed curve (`contract.json#surge`, `SurgeSchedule`): `points [{ atMin, multiplier }]` from minute 0 to the end, straight lines between them, applied in `stepMinutes` (5) steps so the price never wobbles from one second to the next. The multiplier at a time is the curve's value at the start of the current step, rounded half-up to 0.1, never below 1.0 and never above the schedule's `cap`; `null` before `startAt` and from `endAt` on (cases: `fixtures/surge.json`). The server prices new quotes from it; **a quote keeps the multiplier it was priced with** (`Quote.surgeMultiplier`, `Quote.surge { multiplier, until, scheduleId }` for display) whatever the schedule does next. One active schedule per zone and category (`categoryIds` empty = every category); a new one replaces it. A flat manual surge is a two-point curve with the same multiplier. Admin: `GET | PUT /admin/zones/{zoneId}/surge`, `POST /admin/zones/{zoneId}/surge/end`; points above the cap are `400 invalid_request`; above the role limit `202 pending_approval`. Smart (automatic) surge stays server-side and is unchanged by this section.

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

Scheduled rides: `kind = scheduled`, `scheduledAt` UTC. Free cancel until `freeCancelMinutesBeforePickup` (per zone × category, §5). Dispatch starts `searchBeforeMin` before pickup. A driver claim (`accept` from `requested`) can be released (`cancel` → `requested`). Since v0.5.1 the table says so in its own terms: `accept` from `offered` is one row and `accept` from `requested` another with `when: scheduled`, so a live trip in `requested` cannot be accepted (`fixtures/scenarios.json` `live_accept_only_from_offered`).

### 3.5 Fare (v0.5.1, owner decisions 5, 8, 16–21 (2026-10-24))

The server prices every quote and every fare from the zone's **pricing document** (§6.2), in the order of the admin panel's calculator (Pricing › Test a ride, `quoteRide`), with the owner's decisions applied (`contract.json#pricing`). Cases every price engine must reproduce: `fixtures/fares.json`. All amounts are exact (no rounding) until they become a fare line.

1. **Ride part.** A fixed route of the category (`fixedRoutes`) replaces it all: `fixed_route` = the route price, with no surge, minimum or maximum. Otherwise `base` + `distance` (perKm × km) + `time` (perMin × minutes).
2. **Surge** multiplies the ride part only: the `surge` line is ride part × (multiplier − 1). The multiplier is clamped to [1, `surge.maxMultiplier`] (3, owner decision 21). Where it comes from: the zone's surge schedule (§3.4), else a `surge.scheduled` window in force, else smart surge when `smart.enabled` (off in the test week); else 1.0. A quote keeps its multiplier.
3. **Minimum, then maximum** of the category, on the ride part after surge: `minimum_adjust` raises it to `minimum`; `maximum_adjust` (negative) lowers it to `maximum` when that is not `null`.
4. **Extras**, never surged: `waiting` (pickup waiting: `Waiting.chargedSeconds` / 60 × `waiting.perMin`, per second after the free wait), `stops` (`extraStopFee` per extra stop), `stop_waiting` (at each stop the first `stopFreeWaitMin` = 3 minutes are free, owner decision 20; then per second at `stopWaitPerMin`), `extras` (baby and child seats), `airport` (airport pickup and drop-off fees), `reservation_fee` (`kind = scheduled`).
5. **App fee** = (ride part + extras) × `appFeePct` / 100: the `app_fee` line.
6. **Pickup fee**: the category's `riderPickupFee.live` (or `.reservation` for `kind = scheduled`) when not `null`: the `pickup_fee` line (§3.2).
7. **Total** = ride part + extras + app fee + pickup fee, rounded **once**, half-up, to a multiple of `priceStep` (1 kr in Sweden). Each line is its exact amount rounded half-up to a whole minor unit; a `rounding` line (total − the sum of the rounded lines, may be negative) makes the lines add up, and is left out when it is 0. Half-up means a tie goes up (toward +∞), also on a negative line.
8. **Outstanding fee** (§3.7): while the rider owes one, the `outstanding_fee` line is added after the rounding; `Quote.total` and `fare` include it.

**Money split** (owner decisions 16–18). Commission base = ride part + extras − waiting − stop waiting: no commission on waiting (decision 17), and the app fee and pickup fee are Movera's and outside it (decision 18). `driverEarnings` = half-up(commission base × (1 − `commissionPct` / 100)) + the `waiting` and `stop_waiting` lines, never more than the total before `outstanding_fee`. Movera's share = `fare` − `driverEarnings` (the app fee, the pickup fee, the commission, the rounding and any outstanding fee); `TripProjection.commission` carries it. Premium keeps the panel's 22 % commission and 12 % app fee, every other category 20 % and 10 % (decision 16). Driver pickup pay and driver bonus come out of Movera's share as before (§3.2).

**Quote and fare.** The quote prices the server's own route (OSRM km and minutes, §10; a distance a client sends is a hint) with no waiting. The fare at completion is the same calculation with the quote's km and minutes, the stops made and the waiting the trip had, rounded once. Route changes keep the v0.4.3 rule (§3 "Route-change pricing").

**Rider ends the trip early** (`end_early`, owner decisions 8 and 19): ride part = base + km driven × perKm + minutes on board × perMin, × the booked surge multiplier, then the minimum and maximum; no extras; then the app fee and the pickup fee. When that is above the booked fare (the quote total plus route changes, without the outstanding fee), the ride part is lowered (`maximum_adjust`) so that ride part + app fee + pickup fee is exactly the booked fare; the total is then rounded once to the price step. `driverEarnings` follow that ride part.

**Not in the formula** in v0.5.1: `cleaningFee` (charged afterwards with `POST /admin/trips/{id}/adjust`), `tollsPassThrough` (no tolls are priced), the smart surge algorithm (kept in the document, off in the test week), promotions (`discount`, hidden in the test week).

### 3.6 Automatic dispatch (v0.5.1, owner decisions 6, 10, 22–24 (2026-10-24))

How the server finds a driver for a live trip in `searching`, from the **pickup zone's** dispatch document (§6.3) and its live `DispatchControl`, as the admin panel's rules describe it (`modeNow`, `rankDrivers`, `simulate`). Constants, ranges and the full rule list: `contract.json#dispatch`; timelines every dispatcher must reproduce: `fixtures/dispatch.json`. Time `t` counts from search start (the trip enters `searching`).

- **Mode at search start**, first match: the zone is paused → no automatic offers; a forced mode (`control.mode`); the first time rule that is on, whose mode is on and whose zone-local window `[from, to)` holds now (it wraps midnight); `choose.how = auto` with both modes on → Radar when busy ≥ `radarAbove`, else Exclusive; else `choose.main` when on, else the mode that is on. Busy = waiting trips in the zone (`requested`, `searching`, `offered`, the new one included) ÷ max(1, free online drivers in the zone), rounded to 0.1, worked out once. `choose.backup` and `rulesFrom` are ignored (the next steps follow `then`).
- **Who and in what order**, ranked again before every offer: drivers who may take it (the category, within the widest radius step, and a driver on a ride only when finishing within `finishing.withinMin` and `withinKm`), then score high to low, then km, then `driverId`. Distance is the straight line × 1.25 (`roadFactor`), ETA at 24 km/h (`pickupKmh`). The score is the admin's: each factor that is on gives round(weight ÷ the sum of the on weights × 100 × its ratio, the ratio kept within 0..1): ETA 1 − min/20, rating (rating − 3.5)/1.5, acceptance %/100, cancel 1 − %/30, waited min/30, finishing nearby 1, rider's favourite 1 (within `favourite.maxKm`). A driver with no data counts as rating 4.7, acceptance 85 %, cancels 5 %. Radar never goes to a driver with a rider; Exclusive does only while `finishing.exclusive` and `exclusiveWhileDriving.on`.
- **Radar round**: the trip is shown at once to the top `radar.drivers` within the current radius step for `radar.seconds`; the first to accept wins, the others get `offer_withdrawn` (`claimed_elsewhere`). Nobody is marked as asked, so a driver who declined or let it run out may see it again on a later round (owner decision 23).
- **Exclusive**: one driver at a time, the best within the step who was not asked yet, for `exclusive.seconds`, at most `exclusive.drivers` per step. A driver is asked once per search; a decline moves on at once. Reason line (`Offer.reasonCode`): `favourite`, else `finishing-nearby`, else `best-match` for the top-ranked driver, else `nearby`.
- **What comes next** (`then`): after a Radar round nobody took, widen (`widen`, `widen_then_exclusive`) while a wider step exists; else switch to Exclusive at the same step (`exclusive`, `widen_then_exclusive`) once; else widen. After an Exclusive step, widen (`widen`, `widen_then_radar`); else switch to Radar (`radar`, `widen_then_radar`) once; else widen. The start mode does not count as switched into, so a search can go back to it once. A round with nobody in range moves on at once.
- **When the steps are used up** before the search ends (owner decision 22, approved as "Radar every 15 s at the widest area, and Exclusive to any driver not yet asked"), the search never goes silent. Each repeat round at the widest step is: when `exclusive.on` and a driver in range has not been asked on Exclusive in this search (newly free drivers count), an Exclusive offer to the best such driver for `exclusive.seconds`; otherwise, when `radar.on`, a Radar round to the top `radar.drivers` in range for `radar.seconds`; otherwise the server waits `radar.seconds` (`exclusive.seconds` when Radar is off) and looks again. Rounds go on until the search end (`fixtures/dispatch.json` `thin_zone_chain_ends_in_exclusive`).
- **Search end** = the first of `radius.maxWaitMin` and the first `busy` step that is on. No offer starts at or after it, and `Offer.expiresAt` = min(sent + seconds, search end). At the end the trip takes `expire` (`expired`, "no driver found").
- **Rider-waiting steps**: every step that is on, by `afterMin` from search start; `raise_price` and `upgrade` are skipped in the test week (owner decision 10). A step that fires before the search end becomes `TripProjection.searchStep { id, kind, message, extraMin, at }` (rider view, sent as `trip_projection`; it does not change `version`). `alert_admin`: the trip shows in Live with an alert and offers go on. `keep_waiting`: the rider app asks "Keep waiting? / Stop" and answers with `POST /trips/{tripId}/keep-waiting { answer, expectedVersion? }`: `wait` adds `extraMin` minutes to the search end and a `busy` step that has not fired moves to no earlier than the new end; `stop` is the normal free rider cancel (`cancelled_by_rider`, reason `wait_too_long`, no fee: no driver accepted); no answer, the search goes on (owner decision 24). The command is allowed only while the trip is `searching` or `offered` with an unanswered `keep_waiting` step; else `409 invalid_transition`. `busy`: the search ends with the step's message. **Raising the offer** (v0.5.5, owner decision 25): the rider's `POST /trips/{tripId}/raise-price { expectedVersion, increase }` while `searching` or `offered` (transition `raise_price` → `searching`): `fare` += `increase` as a `rider_raise` line, `driverEarnings` += `increase` (Movera's share unchanged), open offers are withdrawn and a new search starts in which the drivers who already declined are asked again at the new price; `version` + 1. The new fare may not pass `dispatch.raisePrice.maxFactor` × the quoted fare (`400 invalid_request`, reason `raise_too_high`); another currency is `400 invalid_request` (`currency_mismatch`).
- **Live switch** `DispatchControl { zoneId, paused, mode, by, at, version }`, `PUT /admin/zones/{zoneId}/dispatch-control { expectedVersion, paused, mode, note? }` (`dispatch.edit`): pausing stops new offers, also in searches already running (open offers run out), while the waiting steps and the search end keep running so riders are not stuck; a forced mode applies to new searches; forcing a mode that is off is `400 invalid_request` (`mode_off`). Pausing or forcing a mode waits for a second admin (`202 pending_approval`) unless a Super admin does it (owner decision 14); resume and back to the rules apply at once for everyone, as in the admin panel.
- **One search per driver cancel**: a driver cancel that puts the trip back in `searching` starts a new search (new `t = 0`, new steps); the driver who cancelled stays asked. A free driver holds at most one open Exclusive, a driver with a rider at most `exclusiveWhileDriving.count`; Radar deliveries keep the §3.3 limits.
- **Timers agree.** `DriverAppConfig.offers.radarSeconds`, `exclusiveSeconds`, `radarOn`, `exclusiveOn` (and `exclusiveWhileDriving`) must equal the same zone's dispatch document; the admin builds both from Dispatch › Modes (`contract.json#configDocs.mustMatch`).

### 3.7 Unpaid cash fees (v0.5.1, owner decision 7 (2026-10-24))

Cash only in the test week: a cancel or no-show fee the rider does not pay at once puts their account in minus.

- The trip's `cancellation.feeStatus` is `owed` (else `paid` or `waived`), and `Rider.outstanding` (on `GET /rider/profile` and the admin rider view) is the sum of what the rider owes; `null` or missing means nothing.
- While it is open, every quote and the next trip carry it as the `outstanding_fee` line (`FareLine.sourceTripId` names the trip that owes it), added after the price-step rounding (§3.5); `Quote.total` and `TripProjection.fare` include it, so the rider sees one higher total with its own line.
- It is cleared (`feeStatus` `paid`) when a cash trip that carries it completes and is paid. A trip that carried it but did not complete leaves it owed.
- The driver of the original trip gets their share at once (an earnings entry: `EarningsPeriod.fees`; the no-show share is `waiting.driverSharePct`), paid in Movera's regular payout; Movera carries the risk.
- On the next trip the line is cash the new driver collects (in `cashCollected`) but it is **not** in their `driverEarnings`: it is owed to Movera with the rest of the driver's cash balance.

## 4. Realtime and synchronisation

Envelope (`contract.json#realtime`): `eventId, tripId, sequence, version, kind, occurredAt, serverTime` + optional `projection, location (GeoFix), etaSeconds, cancelFee (Money|null), message (Message, only for kind=message)`. In `fixtures/events.json`, top-level `status`/`paymentStatus`/`ratingStatus` are test shorthand for the same fields in `projection`.

- `sequence` is **server-assigned**, contiguous per trip. Clients never number events.
- Gate (same in all apps; cases in `fixtures/events.json`): invalid if `sequence < 1` or blank `tripId`; duplicate if `eventId` seen or `sequence ≤ last`; gap → accept and resync; after a terminal status only `payment_updated`, `rating_updated`, `message` pass; `location` never replaces the projection.
- Kinds: `trip_projection, rider_cancelled, driver_cancelled, location, driver_arrived, rider_on_the_way, payment_updated, rating_updated, message`.
- `rider_on_the_way` is raised by the rider's `POST /trips/{tripId}/on-the-way` (v0.5.4); the other kinds come from the server's own commands and changes.
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
| Price set per zone (Pricing; v0.5.1) | server-only `pricing` document (§6.2) | Quote and fare lines (§3.5) | `Offer.driverEarnings` (§3.5 split) | Prices every quote and fare |
| Dispatch rules per zone (Dispatch; v0.5.1) | server-only `dispatch` document (§6.3); timers also in `driver.offers` | Searching, `searchStep`, Keep waiting? (§3.6) | Radar / Exclusive offers and timers | Automatic dispatch |
| Pause a zone, force a mode (Dispatch › Live; v0.5.1) | `PUT /admin/zones/{zoneId}/dispatch-control` (§3.6) | — | No new automatic offers while paused | Stops offers, waiting steps go on |
| Pickup pay, driver side (Pricing › Pickup pay) | `driver.pickupPay.byCategory`, `.offers` (§3.2) | — | `Offer.pickupPay` inside the offer card's total | Works the pay out per offer, pays it from Movera's share |
| Pickup fee, rider side (Pricing › Pickup pay) | `rider.pickupFee.byCategory`, `driver.pickupPay.byCategory[].riderFee` (§3.2) | `pickup_fee` line in the quote | — | Adds the fee to the quote |
| Radar limits while driving (Dispatch › Modes) | `driver.offers.radarApp`, `driver.offers.exclusiveWhileDriving` (§3.3) | — | Full-screen list lock, card limits per state | Holds offers above the limit of `Driver.moving` |
| Surge curve (Pricing › Surge) | `PUT /admin/zones/{zoneId}/surge` (§3.4) | `Quote.surge` shown | — | Prices new quotes from the step in force |
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

Two versioned documents per zone, built by the Admin exporters, read by the apps through a repository (local seed today, `GET /rider/config?zoneId` and `GET /driver/config?zoneId` later). v0.5.1 adds two server-only documents per zone, `pricing` (§6.2) and `dispatch` (§6.3), published the same way and never served to the apps (`contract.json#configDocs`):

```
RiderAppConfig  { version, publishedAt, zoneId, currency, timeZone, country, languages,
  catalog: { categories: [{ id, label, seats, sort }] },
  features: { scheduledRides, wallet, pin, shareTrip, … },
  paymentMethods: [ZonePaymentMethod],          // cash | card | apple_pay | google_pay
  wallet: { usedFirst: bool },                  // one balance per currency; on/off is features.wallet
  tips: [AmountOption], raiseSteps: [AmountOption], promoCap: Money | null,
  pickupFee: { byCategory: { [categoryId]: { live: Money | null, reservation: Money | null } } },   // §3.2
  booking: { maxStops, bookingHorizonDays, maxPickupMoveMeters },
  cancelFees: { live: { [categoryId]: FeeRule }, reservation: { [categoryId]: FeeRule } },
  waiting: { freeWaitMin, perMin: Money, noShowAfterMin, noShowFee: Money, byCategory: { [categoryId]: CategoryWaiting } },
  cancelReasons: [{ code, title }],
  rideCheck: {...}, appUpdate: {...} }

DriverAppConfig { version, publishedAt, zoneId, currency, timeZone, country, languages,
  catalog, features, paymentMethods: [ZonePaymentMethod],
  booking: { maxStops, maxPickupMoveMeters },
  offers: { radarSeconds, exclusiveSeconds, radarOn, exclusiveOn, assignAcceptSeconds, offerCard: {...}, exclusiveReasons: [...],
            autoOffline: { missedExclusive, … },
            radarApp: { fullOn, full, fullLockWhileDriving, popupOn, popup, popupSplitByDriving, popupWhileDriving },   // §3.3
            exclusiveWhileDriving: { on, count } },
  pickupPay: { offers: { radar, exclusive, exclusiveReservation, assigned, nextTrip }, display: total,                 // §3.2
               byCategory: { [categoryId]: PickupPayRate },
               perKm, perMin, freeKm, freeMin, ranges, maxPerRide },   // v0.4 shape of the headline category, until v0.6
  PickupPayRate { enabled, maxPerRide: Money | null, ranges: [PickupRange], riderFee: { live: Money | null, reservation: Money | null } }
  PickupRange   { fromKm, toKm: number | null, perKm: Money, perMin: Money }
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
| `offers.radarApp`, `offers.exclusiveWhileDriving` (§3.3) | — | ✓ | list 8, locked while driving; cards 2, no split, 1 while driving; Exclusive while driving on, 1 |
| `pickupPay` (§3.2) | fee | ✓ | every kind on, total only, no maximum; rider fee off (suggested SE 15 / 20 kr · FR 1.50 / 2 € · TN 1.5 / 2 DT); first km free, then SE 2.50 kr/km + 0.80 kr/min · FR 0.25 €/km + 0.08 €/min · TN 0.250 DT/km + 0.080 DT/min |

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

Cancel reasons: the rider document lists `{code, title}` in the rider's language; the driver document lists codes per group and the titles come from `texts`. Unknown keys are ignored; missing keys fall back to the app's seed.

**Document version** (v0.5.0, `contract.json#configVersion`): `version` is the admin's revision number of the zone's live document, strictly increasing per zone and document, and `publishedAt` is when it was published. The server stores the published document as the admin built it and serves it unchanged from `GET /rider/config` and `GET /driver/config`; `config_published` carries the same `version`. Apps keep the last good document and ignore an older version. The same rule holds for the server-only `pricing` and `dispatch` documents (v0.5.1), which the apps never get.

### 6.2 `PricingDocument` (v0.5.1, server-only)

Built by Admin from Pricing (the zone's price set, `zonePricing.ts` `ZoneBook`), published with `PUT /admin/config/pricing` + `POST /admin/config/pricing/publish` and the same version rule; only the server's quote engine and admins with `settings.read` read it (`GET /admin/config/pricing?zoneId`). `GET /rider/config` and `GET /driver/config` never include it and no `config_published` is sent for it. Money in minor units of the zone's currency (12.26 kr/min = `1226`). Defaults: `contract.json#configDefaults.pricing` (the admin's Stockholm prices); the Z001 document: `fixtures/config/pricing_document.json`.

```
PricingDocument { version, publishedAt, zoneId, currency, country, timeZone,
  priceStep: Money,                                   // the total is rounded once to this (1 kr)
  categories: { [categoryId]: CategoryPricing },
  fees: { airportPickup, airportDropoff, reservationFee, cleaningFee: Money, tollsPassThrough: bool },
  stopFreeWaitMin: 3,                                 // owner decision 20
  fixedRoutes: [{ id, from, to, categoryId, price: Money }],
  surge: { maxMultiplier: 3, smart: SmartSurge, scheduled: [{ id, name, multiplier, startsAt, endsAt }] },
  fleetCommissionPct }
CategoryPricing { enabled, base, perKm, perMin, minimum: Money, maximum: Money | null, appFeePct, commissionPct,
  extraStopFee, stopWaitPerMin, babySeatFee, childSeatFee: Money,
  waiting: { freeWaitMin, perMin: Money, noShowAfterMin, noShowFee: Money },
  riderPickupFee: { live: Money | null, reservation: Money | null } }
SmartSurge { enabled, activeFrom, activeTo, checkEveryMin, holdMin, stopAfterMin, cooldownMin, profiles: [{ id, name, days, windows, steps: [{ ratio, multiplier }], cap, isDefault }] }
```

Stockholm defaults (SEK; the admin converts other countries):

| Category | Base | Per km | Per min | Minimum | Maximum | App fee | Commission | Stop fee | Stop wait /min | Free wait | Wait /min |
|---|---|---|---|---|---|---|---|---|---|---|---|
| economy | 29 | 12 | 4 | 49 | 1 500 | 10 % | 20 % | 15 | 5 | 5 min | 12.26 |
| comfort | 36 | 15 | 5 | 61 | 1 875 | 10 % | 20 % | 19 | 6 | 5 min | 12.26 |
| premium | 52 | 22 | 7 | 88 | 2 700 | 12 % | 22 % | 27 | 9 | 5 min | 16.90 |
| priority | 39 | 16 | 5 | 66 | 2 025 | 10 % | 20 % | 20 | 7 | 5 min | 12.26 |
| xl | 44 | 18 | 6 | 74 | 2 250 | 10 % | 20 % | 23 | 8 | 3 min | 12.26 |
| electric | 32 | 13 | 4 | 54 | 1 650 | 10 % | 20 % | 17 | 6 | 5 min | 12.26 |
| pet | 33 | 14 | 5 | 56 | 1 725 | 10 % | 20 % | 17 | 6 | 5 min | 12.26 |
| child_seat | 35 | 14 | 5 | 59 | 1 800 | 10 % | 20 % | 18 | 6 | 5 min | 12.26 |

Every category: no-show fee 65 kr, baby and child seat 30 kr (child_seat 15 kr), rider pickup fee off. Zone: price step 1 kr, reservation fee 25 kr, cleaning fee 300 kr, tolls passed through, no airport fees (ARN and BMA: 65 kr pickup, 30 kr drop-off, base and minimum × 1.3), no fixed routes, surge at most ×3, smart surge off (owner decision 21), fleet owner share 5 %. `child_seat` is an admin catalog category the seed list does not name; ids follow the category pattern.

**Keep these equal.** `RiderAppConfig.waiting.byCategory` and `DriverAppConfig.waiting.byCategory` carry the categories' `waiting`, and `RiderAppConfig.pickupFee` / `DriverAppConfig.pickupPay.byCategory[].riderFee` the `riderPickupFee`; all come from the same admin Pricing page (`contract.json#configDocs.mustMatch`). The rule binds the documents the admin publishes for one zone. `fixtures/config/rider_app_config.json` and `driver_app_config.json` are older illustrative samples whose waiting amounts predate the pricing defaults (5 kr/min, 50 kr no-show); they are left unchanged in v0.5.1 to stay additive and are aligned in v0.6, and `reference_check.py` does not check the rule against them.

### 6.3 `DispatchDocument` and `DispatchControl` (v0.5.1, server-only)

Built by Admin from Dispatch (the zone's `ZoneDispatch`, a subset of the `movera.dispatch.rules` export, admin field names), published with `PUT /admin/config/dispatch` + `POST /admin/config/dispatch/publish` (the panel's `dispatch.edit`, approved with `dispatch.approve`), the same version rule, never served to the apps. The algorithm is §3.6. Defaults: `contract.json#configDefaults.dispatch`; the Z001 document: `fixtures/config/dispatch_document.json`.

```
DispatchDocument { version, publishedAt, zoneId, country, timeZone,               // timeZone: the time rules' clock (SE Europe/Stockholm)
  radar:     { on, drivers, seconds, then: widen | exclusive | widen_then_exclusive },   // defaults on, 5, 15 s, widen_then_exclusive
  exclusive: { on, drivers, seconds, then: radar | widen | widen_then_radar },           // defaults on, 3, 15 s, widen_then_radar
  choose: { how: auto | manual, radarAbove, main, backup, times: [{ id, on, from, to, mode }] },   // auto, 1.5, exclusive, radar (ignored), 22:00–04:00 radar off
  rulesFrom: driver | pickup,                                                       // kept, ignored in v0.5.1
  radius: { steps: [km], maxWaitMin },                                              // [3, 5, 8], 10
  factors: [{ id: eta | rating | acceptance | cancel | idle | finishing | favourite, on, weight }],   // 40 15 15 10 10 5 5
  finishing: { exclusive, withinMin, withinKm },                                    // true, 3, 1.5
  favourite: { on, maxKm },                                                         // true, 4
  exclusiveWhileDriving: { on, count },                                             // true, 1
  waiting: [{ id, kind: raise_price | upgrade | alert_admin | keep_waiting | busy, on, afterMin, message, extraMin }] }
            // w1 raise_price 1 min, w2 upgrade 2 (both skipped in the test week), w3 alert_admin 3, w4 keep_waiting 5 (+3), w5 busy 8
DispatchControl { zoneId, paused, mode: radar | exclusive | null, by, at, version }   // live state, outside publishing; default not paused, no mode
```

Allowed values (the admin's checks, `contract.json#dispatch.ranges`): Radar drivers 1–30 and 5–120 s; Exclusive drivers 1–10 and 5–60 s; `radarAbove` above 0 and at most 10; radius steps above 0, at most 50 km, each larger than the one before; `maxWaitMin` 1–30; `afterMin` 0–30; at least one factor on with a weight above 0; Auto needs both modes on; a manual main mode and the mode of every time rule that is on must be on. Z001–Z009 have the same defaults; the airport zones ARN and BMA show Radar to 8 drivers with steps [3, 6, 10].

## 7. API surface (summary; full detail in `openapi.yaml`)

Auth and devices (rider and driver, §8): `POST /auth/otp/request`, `POST /auth/otp/verify`, `POST /auth/provider`, `POST /auth/refresh`, `POST /auth/sign-out`, `POST /push/devices`, `POST /push/devices/unregister`.

Rider: `POST /quotes`, `POST /trips`, `GET /trips/{id}`, `PATCH /trips/{id}` (route/payment), `POST /trips/{id}/route-quote`, `POST /trips/{id}/cancel`, `POST /trips/{id}/cancel-reason`, `POST /trips/{id}/end-early`, `GET /trips/{id}/events`, `GET /trips/{id}/pin`, `POST /trips/{id}/rating`, `GET /rider/trips?cursor`, `GET /rider/trips/active`, `GET /rider/config`, payments (`/payment-methods`, `/payments`, `/wallet`), `/rider/profile`, `/rider/places`, `/notifications`, `/trips/{id}/messages`, `/support/tickets`.

Driver: `POST /driver/availability`, `POST /driver/location`, `GET /driver/offers`, `GET /driver/offers/stream`, `POST /offers/{id}/accept|decline`, `POST /trips/{id}/{head-to-pickup|arrive|board|start|complete|cancel|no-show}`, `POST /trips/{id}/pin/verify`, `GET /driver/reservations`, `GET /driver/config`, `GET /driver/earnings`, `/driver/profile`, `/driver/vehicles`, `/driver/documents`, `/driver/payouts`, `POST /trips/{id}/rating`.

Admin: cursor lists `GET /admin/{trips|riders|drivers|vehicles|payments|refunds|payouts|tickets|incidents}?cursor&filter`, `GET /admin/trips/{id}`, trip commands `POST /admin/trips/{id}/{cancel|reassign|assign|radar-group|driver-bonus|no-show|complete|refund|adjust}`, dispatch `GET /admin/trips/{id}/offers`, `GET /admin/trips/{id}/nearby-drivers`, `GET /admin/dispatch/stream`, `POST /admin/{drivers|riders}/{id}/status`, `POST /admin/vehicles/{id}/review`, `POST /admin/documents/{id}/review`, config `GET|PUT /admin/config/{doc}` (draft) + `POST /admin/config/{doc}/publish` (approval), surge `GET|PUT /admin/zones/{zoneId}/surge`, `POST /admin/zones/{zoneId}/surge/end` (§3.4), `GET /admin/audit?cursor`, `GET /admin/approvals`, `POST /admin/approvals/{id}/{approve|reject}`. Permissions: write actions need `*.edit` permissions; refunds above the role limit return `202 pending_approval`.

v0.5.1: maps `POST /locations/autocomplete`, `/locations/geocode`, `/locations/reverse-geocode`, `POST /routes`, `GET /routes/driving/{coordinates}` (§10); telemetry `POST /telemetry/logs|analytics|crashes` (§11); rider `POST /trips/{id}/keep-waiting` (§3.6), `POST /account/deletion`; admin `POST /admin/auth/sign-in`, `/admin/auth/setup-password`, `/admin/auth/setup-password/check`, `/admin/auth/refresh`, `/admin/auth/sign-out`, `GET /admin/auth/me`, `POST /admin/agents/{adminId}/setup-link` (§9), `GET|PUT /admin/zones/{zoneId}/dispatch-control` (§3.6), `GET /admin/live/drivers`, `GET /admin/trips/{id}/trace` (§12), and `GET|PUT /admin/config/{pricing|dispatch}` + publish (§6.2, §6.3). Admin permissions are the panel's 34 ids (§9); a Super admin never gets `202 pending_approval`.

v0.5.2: rider `GET /rider/nearby-vehicles?lat&lng` (§13).

v0.5.3: driver `POST /driver/onboarding`, `GET /driver/fleet`, `POST /driver/fleet/join|leave|invite`, `GET /driver/fleet/invitations`, `POST /driver/fleet/invitations/{invitationId}/accept|decline|cancel`, `POST /driver/fleet/drivers/{id}/remove`, `GET /driver/fleet/earnings`, `GET /driver/documents/{id}/file`; admin `GET /admin/fleets`, `GET /admin/fleets/{id}`, `POST /admin/fleets/{id}/review|code`, `POST /admin/fleets/{id}/invitations/{invitationId}/accept|cancel`, `POST /admin/fleets/{id}/drivers/{driverId}/remove`, `GET /admin/drivers/{id}`, `GET /admin/documents/{id}/file` (§14).

v0.5.4: rider `POST /trips/{tripId}/on-the-way`.
v0.5.5: rider `POST /trips/{tripId}/raise-price`.

Auth (all apps): bearer token; actor and scope come from the token, never from the body.

## 8. Sign-in, tokens and push devices (v0.5.0)

`contract.json#auth`. The rider and driver apps sign in the same way; the admin signs in with e-mail, password and a second factor, outside this contract (v0.5.1: the admin's sign-in is now §9, e-mail and password without a second factor for the test week). No bearer token on the four sign-in calls.

- **Phone + SMS code.** `POST /auth/otp/request { phone (E.164), app: rider | driver, linkToken?, locale? }` → `{ requestId, sessionId, expiresAt, retryAfterSeconds }` (code 4 digits, 300 s, resend after 30 s, 5 attempts; rate limited per phone and device, `429 rate_limited` with `Retry-After`). `POST /auth/otp/verify { phone, sessionId, code, linkToken? }` → `AuthTokens { accessToken, refreshToken, expiresIn, actor, isNewRider?, isNewDriver? }`. A wrong code is `400 invalid_request` (`reason: invalid_otp_code`), an unknown session `400` (`invalid_otp_session`), an expired code or session `410 otp_expired`, too many attempts `429`.
- **Apple / Google.** `POST /auth/provider { provider: apple | google, idToken, app, name? }` → `AuthTokens` for a linked account, or `{ code: "PHONE_REQUIRED", linkToken, firstName?, lastName?, email? }` for a new one: the app then verifies a phone with that `linkToken` on the OTP calls (the phone is confirmed once, the first time; afterwards Apple / Google alone signs in) and the account is created linked to the provider; the driver app prefills its details step with the names and e-mail the provider gave (Apple gives them only the first time and may give a hidden relay e-mail; all stay editable). The server verifies the token against the provider's public keys and its own client ids (`contract.json#auth.providerKeys`: `APPLE_CLIENT_IDS`, `GOOGLE_CLIENT_IDS`); while a provider's keys are not set it answers `503 unavailable` (`reason: provider_not_configured`) and the apps show the button as coming soon.
- **Tokens.** The access token is a short-lived JWT (900 s) carrying actor, subject id, zone scope and, for admins, role and permissions. The refresh token is opaque, lives 30 days and is **rotated** on every `POST /auth/refresh { refreshToken }` → `AuthTokens`; a used, revoked or unknown one is `401 unauthenticated` and the app signs out. `POST /auth/sign-out` revokes the session (idempotent, `204`).
- **Test numbers (outside production only).** The staging server seed lists the test group's phone numbers; an OTP request for one of them sends no SMS and the fixed code (`contract.json#auth.testSignIn.code`, placeholder `1234` until the owner sets one) signs it in. Production has no test numbers.
- **Push devices.** `POST /push/devices { token, provider: fcm | apns, platform: ios | android | web, appVersion?, locale? }` → `{ status: registered }`, keyed by token and actor (registering again updates it); `POST /push/devices/unregister { token }` on sign-out. Push is off during the first test week (the driver app stays open); the registration still happens so it can be switched on without an app change.

## 9. Admin sign-in (v0.5.1)

`contract.json#auth.admin`, owner decisions 9 and 14 (2026-10-24). The admin panel signs in through the server with e-mail and password; there is no authenticator code in v0.5.1 (the panel hides its code field). One Super admin, the owner's e-mail, set on the server and not in git. No bearer token on sign-in, setup and refresh; these are separate from the rider and driver `/auth/*` calls.

- **Sign-in.** `POST /admin/auth/sign-in { email, password }` → `AdminSession { accessToken, refreshToken, expiresIn: 900, actor: "admin", admin: AdminMe }`. An unknown e-mail, a wrong password and a deactivated account all get the same `401 unauthenticated` with reason `invalid_credentials`. Failed attempts are slowed, then locked: `429 rate_limited` with `Retry-After`. A later second factor will be added as a `{ code: "SECOND_FACTOR_REQUIRED", … }` answer; that code is reserved and never sent in v0.5.1.
- **First password.** An admin gets a one-time setup link (72 h, single use): `POST /admin/agents/{adminId}/setup-link` (`team.edit`) → `{ url, expiresAt }`; the first Super admin's link comes from the server seed / CLI. The page checks it with `POST /admin/auth/setup-password/check { setupToken }` → `{ email, name, expiresAt }` (read-only) and sets the password with `POST /admin/auth/setup-password { setupToken, password }` → `AdminSession`. The password has at least 10 characters (else `400 invalid_request`, `weak_password`) and is stored as argon2id. An unknown token is `400 invalid_request` (`invalid_setup_token`); an expired or used link is `410 otp_expired` (`setup_link_expired`, `setup_link_used`).
- **Tokens.** The access token (900 s) carries actor `admin`, the admin id, role, expanded permissions and zone scope. `POST /admin/auth/refresh { refreshToken }` → `AdminSession`, rotated every time, at most 12 h; a used, revoked or unknown token is `401`. `POST /admin/auth/sign-out` revokes the session (`204`, idempotent). The panel signs out by itself after `idleTimeoutSeconds` without use (default 900, 5–240 minutes on the Team page).
- **Who.** `GET /admin/auth/me` → `AdminMe { adminId, email, name, role: AdminRole, permissions: AdminPermission[] (fully expanded), scope: { zones: "all" | ZoneId[], countries?, fleetPartnerId? }, language?, idleTimeoutSeconds, approvalExempt }`; it maps one to one onto the panel's agent (`adminId` = `id`).
- **Permissions.** `AdminPermission` is the panel's 34 ids (`contract.json#adminPermissions`): look `overview.read, trips.read, riders.read, drivers.read, zones.read, finance.read, incidents.read, audit.read, team.read, system.read`; private data `riders.viewSensitive, drivers.viewSensitive`; act `trips.annotate, trips.intervene, support.reply, safety.edit, riders.block, riders.promotions, drivers.activate, drivers.bonuses, documents.approve, vehicles.edit, alerts.manage, payments.refund, finance.edit`; setup `zones.edit, zones.publish, dispatch.edit, dispatch.approve, settings.read, settings.edit, settings.publish, approval.decide, team.edit`. Every admin operation's `x-permission` in `openapi.yaml` is one of them; where v0.5.0 named another value it is kept as `x-permission-v050` (`trips.edit` → `trips.intervene`, `payments.edit` → `payments.refund`, `config.edit` → `settings.edit` / `settings.publish`, `pricing.*` → `settings.read` / `settings.publish`, and so on). `PUT /admin/config/{doc}` and its publish name the permission per document in `x-permission-by-doc` (dispatch rules: `dispatch.edit`, approved with `dispatch.approve`).
- **Super admin** (`super`): every permission, `approvalExempt: true`; their refunds, publishes and other big changes run at once (`200`, never `202`) and are written in the audit (owner decision 14, §3.1).

## 10. Locations and routes (v0.5.1)

`contract.json#maps`, owner decision 4 (2026-10-24): address search goes through the server (Google Places / Geocoding; the server keeps the provider's session tokens and a cache), routes, distances and arrival times come from Movera's own OSRM. All of these are read-only: no `Idempotency-Key`.

- `POST /locations/autocomplete { query, latitude?, longitude?, limit: 8 }` (rider) → `{ suggestions: [{ title, subtitle?, latitude?, longitude?, placeId? }] }`; the point biases the search; an empty list means nothing was found. A suggestion without coordinates is resolved with geocode.
- `POST /locations/geocode { query, placeId? }` (rider) → `{ address?, latitude?, longitude?, placeId? }`; no coordinates means no match (`200`, never `404`).
- `POST /locations/reverse-geocode { latitude, longitude }` (rider, driver) → `{ address: string | null, latitude, longitude }`, in the caller's profile language (or `Accept-Language`). Bad coordinates: `400 invalid_request` (`invalid_coordinates`).
- These three bodies say `latitude` / `longitude` (§1, the only exception).
- `POST /routes { mode: driving, from: { lat, lng }, to: { lat, lng } }` (rider, driver) → `RoadRoute { points: [{ lat, lng }], distanceMeters?, durationSeconds?, provider? }`; no route is `404 not_found` (`no_route`), and the app draws a straight line. The rider's ETA stays `TripProjection.etaSeconds`.
- `GET /routes/driving/{coordinates}` (driver navigation): OSRM's own path syntax (`lng,lat;lng,lat`, 2 to 10 points) and query (`overview`, `geometries=geojson`, `steps`, `annotations`, `alternatives`); the answer is the OSRM v5 route response passed through (`{ code: "Ok", routes, waypoints }`), of which the contract names the subset the driver app reads (`OsrmRouteResponse`). No route is `200 { code: "NoRoute", routes: [] }`; auth and rate errors are the normal `Error`; about 30 calls per minute per driver.
- The server routes quotes itself: a distance or duration a client sends with a quote is a hint and is never priced (§3.5).

## 11. Telemetry (v0.5.1)

`contract.json#telemetry`. `POST /telemetry/logs { level: debug | info | warning | error | fatal, event, extra?, error? }`, `POST /telemetry/analytics { event, extra? }`, `POST /telemetry/crashes { error, stack?, extra? }` from any app: no bearer token needed (one is used when sent), no `Idempotency-Key`, `X-Request-Id` and `X-Api-Version` optional. The answer is `202` with an empty body; the apps do not wait for it. A body is at most 16 KB (else `400 invalid_request`, `payload_too_large`); calls are rate limited per address and device (`429`). The apps scrub e-mails, phone numbers and coordinates; the server scrubs again and keeps the data 30 days.

## 12. Admin live drivers and trip traces (v0.5.1)

`contract.json#liveDrivers`, owner decision 11 (2026-10-24). The admin view of `Driver` gets `location?: GeoFix` and `lastFixAt?` (the latest fix from `POST /driver/location`). `GET /admin/live/drivers?zoneId` (`trips.read`, limited to the admin's zones) → `{ items: [{ driverId, firstName, onlineStatus, moving?, location?, lastFixAt?, stale, activeTripId?, tripStatus?, vehicleId?, plate?, zoneId }], staleAfterSeconds: 120, serverTime }`; the panel polls it about every 5 s. `GET /admin/trips/{tripId}/trace` (`trips.read`) → `{ tripId, fixes: GeoFix[], keptUntil? }`. Trip GPS traces are deleted 30 days after the trip; only each driver's latest position is kept beyond that (`404` for an older trace).

## 13. Nearby cars on the rider's map (v0.5.2)

`contract.json#riderNearby`. While the rider chooses a ride, the app shows the free cars around the pickup, like the other ride apps. `GET /rider/nearby-vehicles?lat&lng` (rider token) → `{ items: [{ key, lat, lng, heading? }], refreshSeconds: 5, radiusMeters: 3000 }`: drivers who are online and free (not on a trip and without an accepted trip), with a fix from `POST /driver/location` not older than 120 s, within 3000 m of the point (straight line), nearest first, at most 15. The answer tells nothing about who drives: no driver or vehicle id, no name, plate, category or trip; `lat`/`lng` are rounded to 4 decimals (about 10 m); `key` is opaque, the same for one car through the day and different the next day (Europe/Stockholm), so the app can glide a car from one answer to the next without being able to follow a driver over days. The app asks again every `refreshSeconds` while the screen is open and stops when it leaves; an empty list is a normal answer (no car is drawn). It is a picture of the area, not a promise: the ride is still dispatched by the server's rules (§3.6).

## 14. Driver sign-up, fleets and documents (v0.5.3)

`contract.json#driverOnboarding`, owner decisions of 2026-10-25. The driver app signs in like the rider (§8: phone and code, or Apple / Google followed by the phone the first time) and the details screen is the sign-in's last step. `AuthTokens.isNewDriver` and `Driver.accountStatus = pending` both mean the details screen comes next.

- **Account types** (`DriverAccountType`): `driver`, who works for a fleet and is paid through it; `fleet`, a company (taxi company in Sweden, exploitant VTC in France) that owns the cars and has drivers, whose owner may drive too.
- **Details, once.** `POST /driver/onboarding { firstName, lastName, dateOfBirth, email, country, cityId, language, accountType, termsAccepted: true, company?, fleetJoin? }` → `Driver`. `country` is one of `SE`, `FR` (open) or `TN` (listed, not open: `400 invalid_request`, `country_not_open`); `cityId` one of the country's cities (`stockholm_lan` → zone `Z001`, `paris` → `FR-PC`), which sets `zoneIds`; the driver is at least 21 (`minAge`, else `under_age`); `termsAccepted` must be `true` (`terms_required`; stored as the `terms` document, approved, `Driver.termsAcceptedAt`); a `fleet` account sends `company { name, orgNumber, address }` (`company_required`) and gets a `Fleet` in status `pending`; a `driver` account may send `fleetJoin` to join a fleet at once. Allowed while `accountStatus` is `pending` or `on_hold` (a resend replaces the details); afterwards `409 invalid_transition`. It moves `pending` → `on_hold`.
- **Account status** (`contract.json#driverOnboarding.accountStatus`): `pending` = signed in, no details yet; `on_hold` = details sent, waiting for Movera (the app opens; the driver uploads documents and sees the hold; going online is `409 invalid_transition`, `account_not_active`); `active` = an admin approved (`POST /admin/drivers/{driverId}/status`, `drivers.activate`), when the person's required documents are approved; `suspended` = blocked. Approving a fleet (`POST /admin/fleets/{fleetId}/review`) is separate from activating its owner as a driver.
- **Fleet code.** The first approval of a fleet makes its code: `MV-` + 5 characters of `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no 0 / O / 1 / I), case-insensitive on entry. Only the owner (`GET /driver/fleet`) and admins see it. `POST /admin/fleets/{fleetId}/code` makes a new code and the old one stops working at once.
- **Joining is an invitation** (`contract.json#driverOnboarding.fleetInvitations`, `FleetInvitation`, owner decision of 2026-10-25): one side asks, the other accepts; nothing links a driver without both. A driver asks with `POST /driver/fleet/join { code, ownerName, ownerEmail }` (or `fleetJoin` on onboarding) → `201 FleetInvitation` (`direction: driver_request`, `pending`): the code, the owner's first and last name and the owner's e-mail must all match one approved fleet (case and spaces forgiven); any mismatch is `400 invalid_request` with the one reason `fleet_join_mismatch`, so nothing tells which part was wrong; at most 10 tries per hour per driver (`429`); one open request at a time (`409 conflict`, `request_pending`). The owner invites a phone number with `POST /driver/fleet/invite { phone }` → `201 FleetInvitation` (`owner_invite`): a driver with that number gets it at once; a number without an account gets it the moment someone signs up with it (`driverId` missing until then). Both sides list theirs with `GET /driver/fleet/invitations`; `FleetView.invitations` carries the fleet's for the owner and admins; `Driver.pendingFleetInvitations` counts the ones waiting for this account's answer (the badge on Home and My fleet). The receiving side answers with `POST /driver/fleet/invitations/{invitationId}/accept|decline`; the sender takes its own back with `.../cancel`; an admin may `POST /admin/fleets/{fleetId}/invitations/{invitationId}/accept|cancel` (`drivers.activate`). Accepting links the driver (`Driver.fleet`, `payoutTo: fleet`) and closes every other pending invitation of his; a driver already in a fleet is `409 conflict` (`already_in_fleet`), one on a trip `409 invalid_transition` (`on_trip`). An invitation lives `expiresDays` (7) days, then is `expired`; anything not `pending` is `409 invalid_transition`. The other side is told in the app (`GET /notifications`, kind `fleet_invitation`) and by one SMS (`smsText` / `smsTextRequest` in the receiver's language; a number without an account gets the app's install link). Rejecting or blocking a fleet cancels its pending invitations.
- **Fleet view.** `GET /driver/fleet` → `FleetView { fleet, drivers, vehicles }`: the owner sees the company with its code, every linked driver (`FleetDriver`) and every car; a member sees the company (no code, no e-mail), no drivers and the approved cars. `GET /driver/fleet/earnings?from&to` (owner) → every driver's trips and earnings in the period and the total. The owner removes a driver with `POST /driver/fleet/drivers/{driverId}/remove`; a driver leaves with `POST /driver/fleet/leave`; an admin with `POST /admin/fleets/{fleetId}/drivers/{driverId}/remove`. None of these works during the driver's trip (`409 invalid_transition`, `on_trip`); the owner cannot leave (`fleet_owner`). Unlinking releases the car and takes the driver offline; he is back to waiting for a fleet and may join another with a new code.
- **Cars.** Fleet accounts add cars (`POST /driver/vehicles`, `Vehicle.fleetId` set; a member → `403`); an admin approves each (`POST /admin/vehicles/{vehicleId}/review`). `GET /driver/vehicles` gives a member the fleet's approved cars and the owner all of them, each with `driverId` (who has it picked) and `inUse` (that driver is online or on a trip). A driver picks his car with `PATCH /driver/profile { vehicleId }`: it must be approved and his fleet's; a car in use by another driver is `409 conflict` (`vehicle_in_use`); a car picked by an offline driver moves (that driver picks again before going online). Going online needs `active`, a fleet (driver accounts) and an approved picked car (`no_vehicle`, `vehicle_not_approved`, `no_fleet`). A driver account without a fleet gets an empty list; the app says the fleet's vehicle details are awaited.
- **Documents.** `contract.json#driverOnboarding.documents.types` names every type with its owner (`driver` or `vehicle`), kind and names in en / sv / fr; `required[country]` lists them per country for the person (`driver`), the company (`fleet`) and each car (`vehicle`); `Driver.requiredDocuments`, `Driver.requiredFleetDocuments` and `Vehicle.requiredDocuments` carry the lists so the apps never compute them. Sweden: driver `terms`, `info_session`, `driving_license`, `profile_photo`, `taxi_driver_license`; company `company_registration`, `taxi_traffic_permit`, `tax_settings`, `bank_statement`; car `vehicle_registration`, `insurance`. France (as the ride platforms there ask): driver `terms`, `vtc_card`, `driving_license`, `national_id`, `profile_photo`; company `company_registration` (Kbis / SIRENE), `vtc_register_certificate`, `rc_pro_insurance`, `urssaf_certificate`, `national_id` (the manager's), `bank_statement` (RIB); car `vehicle_registration`, `insurance`, `vtc_sticker`. A fleet owner who drives needs his `driver` documents too. Kinds: `file` is uploaded with `POST /driver/documents` (multipart `type`, `ownerId` = `vehicleId` for a car, `expiresAt?`, `file`; at most 10 MB; jpeg, png, heic or pdf; `201`, status `in_review`; a new upload of the same type replaces the one in review or rejected) and decided with `POST /admin/documents/{documentId}/review` (`documents.approve`); `acceptance` is `terms`; `admin_check` is `info_session` (no file; an admin approves it after the session). Files are stored by the server, encrypted at rest in Europe, and read only through `GET /driver/documents/{documentId}/file` (the owner; the fleet owner for his drivers' and cars') and `GET /admin/documents/{documentId}/file` (`documents.approve`, written in the audit); `Document.fileUrl` is that path and never a public link.
- **Money.** `Driver.payoutTo`: `fleet` for a driver linked to a fleet (Movera pays the fleet's bank; the driver still sees his own trips and earnings), `self` for a fleet account. A driver without a fleet earns nothing yet (he cannot go online).
- **Admin.** `GET /admin/fleets?status&country&zoneId&q` (`drivers.read`), `GET /admin/fleets/{fleetId}` → `FleetView` with the code, `POST /admin/fleets/{fleetId}/review { expectedVersion, decision: approved | rejected | blocked, note? }` (`drivers.activate`; blocked takes every linked driver offline and withdraws their offers), `POST /admin/fleets/{fleetId}/code`, `POST /admin/fleets/{fleetId}/drivers/{driverId}/remove`, `GET /admin/drivers/{driverId}`. New drivers appear in the lists of the admins whose scope covers their city's zone (`zoneIds` is set on onboarding), and in every list before that for Super admins.
