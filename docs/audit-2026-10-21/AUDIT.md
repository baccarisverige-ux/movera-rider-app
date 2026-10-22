# Movera rider app: bug audit

Confirmed: 320 (high 12, medium 123, low 185). Rejected as false alarms: 58.

Runs finished: 24 of 24. Still running at this save: none.

Each finding was checked by an independent code tracer and a reproducer (often with a throwaway flutter test), with a third reviewer on disagreements. Findings from read-only runs were verified by code reading only. Possible duplicates across runs are not yet merged.

## High (12)

### H1. Wallet-paid ride: a cheaper route change is refunded to the wallet twice (credited now and again at completion)

`lib/features/active_ride/presentation/route_change_flow.dart:166` (found by r2-rider2)

**What happens:** Wallet ride booked at 300 kr. In the trip the rider removes a stop and the new price is 250 kr. Refund goes to Wallet, so +50 kr is credited now. At completion the wallet is debited 250 kr. In total the wallet pays 200 kr for a 250 kr trip.

**Why:** When a route change makes the trip cheaper and the rider keeps the default 'Movera Wallet' refund, `_creditWallet` credits `-quote.differenceKr` to the local wallet ledger straight away. `apply` has already saved the snapshot with the new, lower `price`. When the trip completes, `WalletController.chargeCompletedRide` debits a wallet-paid ride for `snapshot.price`, which is already the reduced fare. So the reduction is counted twice: once as the wallet credit and once because the debit is smaller. The 'use wallet first' split has the same problem when the new fare is below `walletAmountMinor`, because the debit is `min(walletAmountMinor, fare)`.

**Suggested fix:** For wallet-paid rides, do not credit the wallet locally, or charge the booked price minus the refunds already credited at completion. One ledger rule must own the difference.

### H2. Driver drop while a child route is open pops that route instead of Waiting; Waiting is left dead and Finding never restarts the search

`lib/features/active_ride/presentation/waiting_for_driver.dart:657` (found by rider2)

**What happens:** Rider is on Waiting and opens the driver's profile (or chat, or the cancel sheet, or 'Change route'); the driver drops the ride. The profile page closes by itself, the rider lands back on a grey, parked Waiting screen showing the old driver with no live updates and no way to cancel (`_confirmCancel` returns on `_leaving`), while the server trip is back in `searching` and the next driver's acceptance is never shown.

**Why:** `_onLiveTick` handles `cancelledByDriver` immediately and deliberately bypasses the route-current gate (lines 405-415). `_researchAfterDriverCancel` disposes tracking, reconciles the session back to `findingDriver`, sets `_leaving = true`, then does `final navigator = Navigator.of(context); if (navigator.canPop()) { navigator.pop(true); return; }` (651-659). The app has a single navigator (app.dart:34, MoveraSheet.show uses rootNavigator: true), so `pop(true)` pops whatever route is on top: the driver profile (`_openProfile`, 976), Chat (waiting_sheet_bits 215), the arrived sheet, the cancel/reason sheets, the Safety Kit or the RoutePickerPage opened by `_changeRoute`. Waiting itself stays mounted with `_leaving = true`, `_mapParked = true` and a disposed `DriverTrackingController`; `FindingDrivers._openWaiting` (finding_drivers.dart 535-557) never receives `true`, so `_resumeFindingAfterDriverCancel` never runs and `FindingDriverController.active` stays null. Reproduced with a throwaway widget test (Waiting pushed over a parent, DriverProfilePage pushed above it, `MockRideRealtime.cancelByDriver()`): output was `profile still mounted: false`, `waiting still mounted: true`, `waiting route result: null`, `session status: RideStatus.findingDriver`.

**Suggested fix:** Pop Waiting's own route by reference (store `ModalRoute.of(context)` in initState and use `Navigator.of(context).popUntil`/`removeRoute` on that route, or `closeRouteByReference`-style logic), or defer the research until `_routeIsCurrent` like the other stage navigations do.

### H3. History archives book-now rides with a UTC DateTime that is then rendered field-by-field, so times/dates show in UTC

`lib/features/history/data/on_demand_ride_history_store.dart:201` (found by rider4)

**What happens:** Stockholm rider finishes a ride at 14:30 local (CEST). History lists it as '12:30'. A ride ended 00:40 on 1 May shows as 30 Apr 22:40 and is counted in April on the home 'Your month' card; near midnight the Today/Yesterday split is wrong. In Tunisia (UTC+1) every History time is one hour early.

**Why:** recordFor stores `scheduledPickupAt: ended.toUtc()` (line 201) and `createdAt: snapshot.createdAt.toUtc()`. The History UI then formats that DateTime with helpers that read the DateTime's own fields rather than converting to local: ReservationFormat.time (lib/features/reservations/presentation/reservation_format.dart:70-74 uses `when.hour`/`when.minute`), ReservationFormat.moment/historyWhen (221-227 compare `when.year/month/day` to a local `DateTime.now()`), weekdayDate/_dayMonth via L10n.formatDate (intl formats the instance's fields; a UTC DateTime prints UTC), called from lib/features/history/presentation/ride_history.dart:546 `ReservationFormat.historyWhen(ride)`. HomeJourneySection.fromRides (lib/features/home/presentation/widgets/home_journey_section.dart:74-83) likewise buckets by `at.year/at.month` and `weeks[(at.day - 1) ~/ 7]` on the UTC value against a local `now`. The only consumer that converts, SupportController (`when: ride.scheduledPickupAt.toLocal()`), shows the correct intent. Verified by throwaway test: a ride ended at 14:30 CEST archived via recordFor and formatted with ReservationFormat.time gave '12:30'.

**Suggested fix:** Either store `ended.toLocal()` in the archived Reservation (consistent with how book-later Reservations hold wall-clock local times) or make every formatter/aggregator call `.toLocal()` before reading fields (ReservationFormat.time/moment/cardDate/weekdayDate, HomeJourneySection.fromRides). Add a test with a UTC-constructed DateTime.

### H4. Server-backed History silently drops every fully settled trip (RideStatus.closed) and every paymentFailed trip

`lib/features/history/data/on_demand_ride_history_store.dart:243` (found by rider4)

**What happens:** Rider completes a trip, pays, rates the driver. Server projection now has status completed/paymentStatus settled/ratingStatus submitted -> RideStatusWire.fromTrip -> RideStatus.closed. The History screen loads /trips, _record returns null for it, and the ride (and every older settled ride) is not listed. A rider with 50 past trips sees an empty or near-empty History; a trip whose card payment failed also disappears, so the rider cannot see what is owed.

**Why:** ApiRideHistoryRepository._record (lib/features/history/data/ride_history_repositories.dart:56-66) feeds each server TripProjection through RideProjection.toSnapshot and then OnDemandRideHistoryStore.recordFor(snapshot, terminalStatus: snapshot.status, ...). recordFor maps the status with _reservationStatus (lines 243-259), which returns ReservationStatus.completed only for status.isCompletedSurface (tripCompleted | paymentProcessing | paymentFinalized | ratingPending per lib/core/contracts/ride_status.dart:85-89) and ReservationStatus.cancelled only for an explicit cancelled list. RideStatus.closed (trip completed + payment settled + rating submitted/skipped) and RideStatus.paymentFailed are in neither branch, so _reservationStatus returns null and recordFor returns null (line 194), i.e. the trip is omitted from History. In release builds (ApiRideHistoryRepository) almost every finished trip the server returns is eventually `closed`, so the History tab loses the rider's past rides and their receipts; a payment-failed ride (which the rider must settle) also vanishes. Verified with a throwaway test (test/_audit_datamath_test.dart, since deleted): recordFor(...terminalStatus: RideStatus.closed) and paymentFailed both returned null while ratingPending returned a record (`3 passed` for these cases).

**Suggested fix:** In _reservationStatus treat RideStatus.closed and RideStatus.paymentFailed as ReservationStatus.completed (optionally carry a payment-failed flag on the Reservation for the receipt), or add a separate mapping for server trips in ApiRideHistoryRepository. Add a test that a `completed`+settled+rated projection appears in History.

### H5. The profile is never read from the server, so an empty device copy overwrites the rider's name and consents on the server with blanks

`lib/features/profile/data/synced_profile_repository.dart:42` (found by r2-rider4)

**What happens:** A rider named 'Ada Lovelace' with promotions on signs out, then signs back in with the same phone (a returning rider, so no name step). She changes the app language in Account. The app sends PATCH /rider/profile {name: '', consents: {promotions: false, ...}}. Her name on the server (which the driver app shows) is erased and her marketing consent is switched off without her doing it.

**Why:** SyncedProfileRepository calls itself 'the profile the server knows', with the device copy only a cache (FLOW-7). But hydrate() only reads the local cache (`await _cache.hydrate()`). No GET is made. After any sign-out the cache is empty, because UserDataWipe removes movera_profile_v1 and clearLocal resets it to defaults; the same is true on a new device. Sign-in for a returning rider (isNewRider false) goes straight to Home, so the cache is never filled. Every later save sends the whole cached profile through body(): `'name': profile.name.trim()` (''), `language` 'en' and the default consents. The mock accepts an empty name, since it only rejects non-strings or names over 80 characters, and stores it. This was seen in a throwaway run, where the server profile became `{name: , language: en, consents: {rideUpdates: true, emailUpdates: false, promotions: false}}`.

**Suggested fix:** Read the server profile on hydrate or after sign-in (a GET or the verify response). Until it is known, send only the fields the rider changed, never the whole cached default profile.

### H6. Duplicate of rider-u148: the server profile is never read, so a returning rider's first save sends name '' and the default consents

`lib/features/profile/data/synced_profile_repository.dart:60` (found by r2-rider4)

**What happens:** A rider whose server profile is {name: 'Anna Berg', emailUpdates: false} signs out and back in (or signs in on a new phone). Account shows 'Add your name'. They pick Svenska under Language, and pickAppLanguage -> ProfileController.update -> PATCH /api/v1/rider/profile {name:'', language:'sv', consents:{rideUpdates:true, emailUpdates:true, promotions:false}}. The server's name is now empty, so the driver sees no rider name, and the e-mail consent is flipped back to true without the rider asking.

**Why:** SyncedProfileRepository is described as 'the profile the server knows', but it has no GET. hydrate() only reads the device cache (`await _cache.hydrate(); if (_syncPending) await _sync(...)`). Every save sends the full body built from that cache: name, language and all three consents. Two cases leave the cache empty or at defaults for a rider who already has a server profile: (a) sign-out, where UserDataWipe removes `movera_profile_v1` and clearLocal() resets the cache to RiderProfileData.defaults(); (b) a fresh device or browser. Nothing on the sign-in path fills the cache from the server: enterMoveraApp only shows Home, and RiderNameScreen is shown only for isNewRider. The returning rider's first profile write is any Privacy switch, a language pick or a gender pick. It PATCHes `{name: '', language: ..., consents: {rideUpdates: true, emailUpdates: true, promotions: false}}` (the defaults, apart from the one switch they changed). The mock and the proposed contract accept an empty name and merge the consents, so the server-side name (which the driver app shows) is erased. A rider who opted out of e-mail updates on another device is silently opted back in. Account also shows 'Add your name' to a rider who has one.

**Suggested fix:** Fetch the server profile (GET /api/v1/rider/profile) after sign-in or on hydrate, and seed the cache from it before any save. Until it has loaded, either block saves or send only the fields the rider changed.

### H7. Scheduled-ride completion screen shows the previous Book Now ride's driver and receipt (or 'unavailable')

`lib/features/reservations/presentation/reservation_live_ride.dart:104` (found by r2-rider2)

**What happens:** Rider takes a Book Now ride Slussen → Kista (kr 189, driver Ali) in the morning. Later the scheduled 23:50 ride Home → Arlanda (kr 450, driver Erik) completes. The completion screen says driver Ali, Slussen → Kista, total kr 189. With no earlier Book Now ride, it shows 'Driver details unavailable' / 'Trip details unavailable' for a ride that just finished.

**Why:** When a reservation completes, `onCompleted` pushes `RideCompleted(persistOnDemandState: false, ...)`. That screen always renders `RideCompletedDriverInfo` and `RideCompletedTripDetail`. Both read `LastCompletedRide.value` (DriverRepository.current / TripReceiptRepository.last). Only Book Now paths (`ActiveRideController.markCompleted`, `_commitCancelled`, restore) ever call `LastCompletedRide.remember`. A normal Book Now close (`closeCompletedRide`) does not clear it. So the reservation's own driver, addresses, price and payment are never shown. The screen shows the last Book Now ride of the session instead, or the 'details unavailable' empty states. The tip options (`_tripCurrency`) also come from that stale ride.

**Suggested fix:** Before opening RideCompleted for a reservation, build a RideSnapshot from the Reservation and call LastCompletedRide.remember. Or pass the receipt/driver explicitly to RideCompleted.

### H8. Reservation completion screen shows the previous Book-now ride's driver, receipt and tip currency (LastCompletedRide is never cleared after a normal close)

`lib/features/ride_complete/data/last_completed_ride.dart:13` (found by r2-rider3)

**What happens:** In one app session the rider completes a Book-now ride in EUR (driver 'Anna', Gamla stan -> Arlanda, 24 EUR) and taps Done. Later a scheduled reservation in SEK (driver 'Erik', Solna -> KTH, 320 kr) completes on the live screen. The 'Ride summary' then shows Anna's photo, car and plate, the receipt 'Gamla stan -> Arlanda, 24 EUR', and tip chips in EUR. If the rider picks a tip, `submitFeedback` sends it for the reservation id with `tipCurrency: EUR`. Verified by reading the code; nothing was run.

**Why:** The completion screen does not read its driver, receipt or tip currency from the ride it is showing. It reads them from the process-wide static `LastCompletedRide`, which only ActiveRideController writes, for on-demand rides. On the normal Done path (`closeCompletedRide`) the static is never cleared. Only `leaveEndedEarlySummary` and the sign-out wipe clear it. A scheduled ride completes through `ReservationLiveRide.pageFor` -> `onCompleted`, which pushes `RideCompleted(rideId: reservationId, persistOnDemandState: false)`. That path never calls `markCompleted`, so `LastCompletedRide` still holds the last Book-now ride. `RideCompletedDriverInfo` calls `AppScope.instance.rideComplete.driver()`, which reads `DriverRepository.current()`, which reads `LastCompletedRide.value`. `RideCompletedTripDetail` calls `receipt()`, which reads `TripReceiptRepository.last()`, which reads `LastCompletedRide.value`. `RideCompleteController._tripCurrency` and `initialTips()`/`tips()` also come from `LastCompletedRide.value`. None of them check the ride id against `widget.rideId`. The same stale copy shows for an on-demand completion whenever `markCompleted` returns early because `historyCandidate()` is null (active_ride_controller.dart:372).

**Suggested fix:** Clear LastCompletedRide in closeCompletedRide/markClosed. Also have DriverRepository.current/TripReceiptRepository.last/_tripCurrency return null unless `LastCompletedRide.value?.rideId` equals the screen's rideId. The reservation completion path should build its own driver and receipt from the Reservation.

### H9. After a reload, a Ride check whose alert failed comes back as 'Movera safety team alerted', and closing it sends alert:false, so the team is never alerted

`lib/features/safety/application/ride_check_controller.dart:450` (found by r2-rider2)

**What happens:** Reproduced with a throwaway test. Open a long-stop card, make POST /safety/ridecheck/answers fail, tap Call 112: alertState=failed. Rebuild the store and controller over the same device cache (a reload) and call resume('r1'): called112=true, alertState=none, and the card shows 'Movera safety team alerted · Trip, driver and rider details were sent.' Tap Done: the final submission has alert=false, final=true, and the server holds 0 alerts. A rider in danger is told help was alerted when it was not.

**Why:** resume() rebuilds the card from the saved event. It sets alertState to `sent` only when the payload has an alertId, and to `none` otherwise. It never restores `failed`. If the rider called 112 (or tapped a red row), the alert POST failed (offline), and the app was then reloaded or killed and reopened, the event is still `acknowledged`, so unanswered() returns it. The answers contain call112, so `called112` is true, but alertState is `none`. _MainStep shows _AlertBanner whenever called112 is true, and _AlertBanner maps `RideCheckAlertState.none` to the success copy (ride_check_card.dart:909). The retry tap is also gone, because retryAlert needs `failed`. When the rider then taps Done or I'm OK, _close submits with `alert: closing.alertState != RideCheckAlertState.none` (line 697), which is false. The server only alerts on alert==true or an existing alert, so no alert is ever created. The red-row case behaves the same: after a reload the failed red-row alert is silently dropped on close.

**Suggested fix:** Persist the alert intent and state, for example `alertPending: true` on the event when an alert is required and not yet confirmed. On resume, restore `failed` when the answers include call112 or a red row and there is no alertId. Never map `none` to the 'alerted' copy. In _close, compute `alert` from the answers (call112 or any red row), not from alertState.

### H10. Ride check buttons (Call 112, I'm OK, Done, answer rows, options, Record) have no semantic tap action because excludeSemantics also drops the InkWell's action

`lib/features/safety/presentation/ride_check_card.dart:797` (found by r2-rider1)

**What happens:** Android TalkBack user (native or Flutter web semantics) is in a trip, a Ride check (long stop / possible crash) opens. Focus lands on 'Call 112' / 'I'm OK'. Double-tap sends ACTION_CLICK, but the node has no tap action, so nothing happens. The card blocks the screen (barrier not dismissible, back blocked), so the rider is stuck on a safety prompt. VoiceOver on native iOS may still work through its simulated-touch fallback.

**Why:** _BigButton, _Call112Now, _RecordAudio, _RowTile and _OptionButton all wrap their InkWell in `Semantics(button: true, label: ..., excludeSemantics: true, child: Material(child: InkWell(onTap: onTap ...)))` and never pass `onTap` to the Semantics. In Flutter, `excludeSemantics` makes RenderSemanticsAnnotations skip visitChildrenForSemantics (rendering/object.dart:4931), so the descendant InkWell's RenderSemanticsGestureHandler never contributes its tap action. The resulting node is a labelled 'button' with no SemanticsAction.tap. The codebase's own pattern elsewhere (safety_ui.dart:161-170, side_menu.dart:709-713) forwards `onTap:` to the Semantics for exactly this reason, and safety_test.dart:111 asserts hasAction(tap) for Safety hub rows; nothing tests the Ride check card this way. RideCheckLayer makes the card modal (non-dismissible ModalBarrier, PopScope canPop: !answering), so a screen-reader user who cannot activate these nodes cannot answer, call 112 or close it.

**Suggested fix:** Pass `onTap: onTap` (and `enabled`) to each of these Semantics widgets, as safety_ui.dart and side_menu.dart already do, and add a test that asserts SemanticsAction.tap on the Ride check buttons.

### H11. "Arrive by" mode books the chosen arrival time as the pickup time

`lib/features/scheduled_rides/presentation/select_date_time.dart:153` (found by rider1)

**What happens:** Rider taps "Arrive by", picks 10:00 for a 20-minute trip; screen says "Estimated pickup 09:40". The reservation is created with scheduledPickupAt = 10:00; Home chrono counts down to 10:00 and the driver is dispatched for a 10:00 pickup, so the rider arrives at ~10:20 instead of by 10:00.

**Why:** The scheduling screen offers two modes, "Pickup at" and "Arrive by" (`_modeSelector`, lines 585-608 toggle only `_pickupMode`). In "Arrive by" mode the estimate row shows `_selectedDateTime.subtract(trip)` as the "Estimated pickup" (lines 484-488, 726-749), so the rider understands the chosen time is their arrival. But the time committed to the session is always `_selectedDateTime` itself: `_commitSchedule()` (153-158) calls `captureSchedule(_selectedDateTime, ...)` and the `popOnConfirm` path returns `_selectedDateTime` (130-132). `_pickupMode` is never read anywhere else in the file. The committed time becomes `ScheduledRideSession.scheduledAt` -> `SelectRide.initialScheduledFor` -> `ScheduledRideCheckout.draftFrom(scheduledPickupAt: when)` (scheduled_ride_checkout.dart:21-31), i.e. the pickup time of the reservation.

**Suggested fix:** When `_pickupMode == false` and `tripMinutes` is known, commit/return `_selectedDateTime.subtract(Duration(minutes: trip))` (clamped with `clampPickup`) as the pickup; hide the Arrive-by mode when `tripMinutes` is null.

### H12. In release builds the default chosen on the Payments tab only goes to local prefs, while Select Ride reads and writes the server default, so the choice is ignored at booking

`lib/features/wallet/presentation/wallet.dart:774` (found by r2-rider4)

**What happens:** Staging/production. On the Payments tab the rider taps Google Pay, and the tile shows the check and 'Default for rides'. They open Select Ride, which calls ApiPaymentMethodRepository.read(), gets the server's defaultMethodId ('cash') and preselects Cash. The rider books a cash ride although they set Google Pay as their default.

**Why:** In release, di.dart sets `defaultPayment = methods` (ApiPaymentMethodRepository, server GET/PATCH /api/v1/payment-methods). RideSelectionController.restoreDefaultPayment and _persistSelectedBrand use that store (select_ride.dart:274 `paymentStore: AppScope.instance.defaultPayment`). The Wallet & Payments 'How do you want to pay' tab (WalletScreen) does not use it: _restorePaymentSettings and _savePaymentSettings go through WalletController.loadPayments/savePayments, which call WalletStore and read and write the SharedPreferences key 'movera_default_payment' directly. This tab is a bottom tab in every build (home.dart:1849 `WalletAndPaymentsScreen(initialTab: 1)`). In release the two defaults therefore drift apart. The tab marks a method 'Default for rides' that Select Ride never preselects, and a default the rider picks at Select Ride is never shown on the tab.

**Suggested fix:** Read and save the default method on the Payments tab through AppScope.instance.defaultPayment (the composed DefaultPaymentStore), and keep WalletStore for the wallet-only settings (business, use wallet first).

## Medium (123)

### M1. Cold start awaits push re-registration (Firebase init, getToken, POST /push/devices) before runApp, blocking the first frame on the network

`lib/app/bootstrap.dart:130` (found by rider4)

**What happens:** Production rider on a poor connection opens the app: the splash/boot screen stays up to ~15 s (API timeout) plus however long FCM getToken takes before Home appears; on web the boot screen can vanish at 20 s into a blank page.

**Why:** `await _registerExistingPushSession()` runs before `runApp`. In staging/production with stored tokens and an accepted push consent it calls `PushPermissionGate.registerIfConsented` -> `FirebasePushService.register()` (lib/core/notifications/firebase_push_service.dart:198-227), which awaits `_gateway.initialize`, `requestPermission`, `getToken` (FCM network round-trip, no timeout in this code) and `_replaceToken` -> `_api.post('/api/v1/push/devices')` (ApiClient `_timeout` 15 s). Nothing in the app is painted until it resolves. The comment at lines 143-147 states the rider must not be kept waiting on push registration and defers `_pushCoordinator.start()` for that reason, but this earlier await defeats it. On the web the HTML boot screen's fallback timer (web/index.html:144 `setTimeout(clear, 20000)`) can remove the loading screen before Flutter paints, leaving a blank page.

**Suggested fix:** Do not await it: `unawaited(_registerExistingPushSession())` after runApp (e.g. in the same post-frame callback as `_pushCoordinator.start()`), or run it with a short timeout.

### M2. On public Pages a reload restores the ride screen, but the in-process server has forgotten the ride, so rating/tip, offer raise and route change all fail

`lib/core/api/in_process_mock_client.dart:82` (found by r2-rider3)

**What happens:** Public demo: the trip completes and the rating screen shows. The rider reloads, and the completion screen is restored at ratingPending. The rider picks 5 stars and a tip and taps Done. The screen shows 'feedback could not be saved' every time. The only way out is back plus 'Leave without sending', which drops the rating and tip.

**Why:** DECISIONS R-web requires a live ride to survive a reload on public Pages. The UI does survive it: RideSnapshotStore restores Finding, Waiting or RideCompleted. But the demo's 'server' is InProcessMockClient, whose `rides` map is in memory only. Safety state is persisted (`persistSafety: true`); rides are not, and nothing re-seeds the server from the snapshot. After a reload every ride call answers 404. Feedback: POST /rides/:id/feedback returns 404, RideFeedbackRepository.submit throws, and RideCompleted._leave shows feedbackSaveFailed and stays on screen. The rider can only leave by backing out without the rating or tip. Also, PATCH offer raise and route-quote fail, GET nearby is empty, and the mock's own status commits are silently refused.

**Suggested fix:** Persist the mock rides map the way safety state is persisted, or re-seed the ride from the restored snapshot. Then a restored ride's commands reach a server that knows it.

### M3. Route-change pricing starts from the booked fare, so any route change (even re-quoting the same route) cancels and refunds the rider's offer raise

`lib/core/api/in_process_mock_client.dart:2055` (found by r2-rider3)

**What happens:** The rider books for kr 287 and raises the offer by kr 50 while searching (fare kr 337), then a driver accepts. On Waiting the rider adds a destination tweak or re-confirms the same destination. The route quote shows the new price as kr 287 with a kr 50 refund. Applying it lowers the fare to kr 287, records a kr 50 refund (or a wallet credit) and resets the offer ceiling, so the driver loses the raise they accepted.

**Why:** `_routeChangePricing` builds `newMinor` from `_bookedMinor(ride)`, which is `bookedFare`, the fare at booking *before* offer raises. It then works out `differenceMinor` against `_fareMinor(ride)`, the current fare, which *includes* the raise. So the raise the rider paid to get a driver comes out of every route quote and every applied route change. On PATCH routeChange, `_setFare(ride, newMinor)` lowers the fare and `maxOfferMinor` is recomputed from it. For non-cash methods a `refunded` paymentAdjustment is recorded. On the client, `route_change_flow.dart:166` credits the wallet with `-quote.differenceKr`. Path: Finding `confirmPriceIncreaseBy` sends PATCH {offerIncrease}, which `_setFare(fare+increase)` applies at line 993. Later, Waiting runs RouteChangeController.quote/apply, which calls POST route-quote and then PATCH routeChange, and those call `_routeChangePricing`.

**Suggested fix:** Price route changes from the current fare (or bookedFare plus the accumulated offerIncrease), not from bookedFare alone; keep the raise when computing newMinor.

### M4. Route-change pricing charges booked stops again: bookedKm is the straight pickup-to-destination distance while routeKm goes through the stops, plus a 25 kr fee for every stop

`lib/core/api/in_process_mock_client.dart:2319` (found by rider3)

**What happens:** Demo/dev/test flavors (the stand-in backend the live GitHub Pages build uses). Rider books a multi-stop trip, then edits the destination by a few metres (or just re-confirms the same route) during the ride: the sheet shows a large surcharge (here +88 kr), and for card/wallet methods the mock records a captured adjustment for it. Money shown and 'charged' is wrong on every route change of a multi-stop trip.

**Why:** `_ride()` stores `bookedKm` as the straight pickup->destination distance (lines 2319-2330) even when the booking body carries `stops` (which `_quote` priced through, via `_routedMeters`, lines 2103-2124 / 2134-2137). `_routeChangePricing` (lines 2046-2096) then prices a change as `bookedMinor + stops.length * 25 kr + (routeKm - bookedKm) * perKm`, where `routeKm` is pickup -> stops -> destination (lines 2071-2080). For a ride booked with a stop, a route change that keeps the same stop charges the stop's detour kilometres a second time plus a 25 kr stop fee that the quote never contained. The result is returned as `newTotal`/`difference` from `POST .../route-quote` and `PATCH .../rides/{id}` (routeChange) and, for non-cash methods, written as a `paymentAdjustments` capture (lines 919-932). Reproduced: booking pickup (59.3293,18.0686) -> stop (59.35,18.10) -> dest (59.3326,18.0649), fare 29 100 öre; route-quote of the identical route: `AUDIT B1: bookedKm=0.42 routeKm=5.69 newTotal=37900 difference=8800` (+88 kr for changing nothing).

**Suggested fix:** Store `bookedKm` from the routed distance through the booked stops (reuse `_routedMeters(body)`), and only add the 25 kr fee for stops that are new relative to the booked `ride['stops']` (or drop the per-stop fee, since `_quote` never charges one).

### M5. A brand-new install on iOS signs in as the previous owner: Keychain tokens survive uninstall and nothing clears them on first launch

`lib/core/auth/secure_token_store.dart:38` (found by r2-rider4)

**What happens:** Rider A uses the app on a family iPad and uninstalls it without signing out. Rider B installs Movera and opens it for the first time. There is no Sign in screen: B lands on Home signed in as A, with A's server-side history, payment methods and any live trip, and can book on A's account.

**Why:** Tokens (and the ride PIN, SecureRidePinStore) live in the iOS Keychain through flutter_secure_storage with default options. iOS keeps Keychain items after the app is uninstalled, but it wipes SharedPreferences, including `movera_rider_fingerprint`. Nothing records a first run and clears the secure store on first launch. On a 'fresh' install, RideRestoreCoordinator._root -> _shouldRequireSignIn -> _hasSession() reads the surviving access and refresh tokens and skips Sign in. It then calls adoptServerActiveTrip() and opens Home, or the previous rider's live trip, under that rider's account. The fingerprint is gone too, so enterSessionAs can never notice that the rider changed.

**Suggested fix:** Keep a first-run marker in SharedPreferences. When it is missing at bootstrap, clear the secure token store and the ride PIN before the restore gate reads the session.

### M6. Cancel-first sends /cancel without the reasonCode openapi CancelCommand requires; a contract server's 400 is treated as transient, so the cancel stays queued and the search stays live (the in-process mock hides this)

`lib/core/contracts/cancel_reasons.dart:39` (found by r2-rider2)

**What happens:** Against a backend built from openapi.yaml, the rider taps Cancel request on Finding. The server returns 400 invalid_request (reasonCode missing). The app shows the ride as cancelling but it is never cancelled: the search goes on, a driver can still be matched and charged, and every reconnect resends the same 400 body.

**Why:** openapi.yaml `CancelCommand` has `required: [expectedVersion, reasonCode]`, and CONTRACT.md §1 says validation errors are `400 invalid_request`. With cancel-first, Finding calls `_match.cancelSearch()` with no reason (finding_drivers.dart:580). `_requestServerCancel` then posts `entry.body(reasonId)`, which is `{...CancelReasonCodes.riderCancelBody(null), 'expectedVersion': v}`. `riderCancelBody(null)` returns `{}`, so the body has no `reasonCode`. BookingCoordinator's stand-down and duplicate cancels (booking_coordinator.dart:778 and 808) send only `{expectedVersion}` too. The in-process mock hides this because it only checks `reasonCode` when one is sent (in_process_mock_client.dart:684 `reasonCode != null && ...`). A server that follows openapi answers 400. `isPermanentCancelFailure` (pending_cancel_store.dart:161) treats only 404/409/410/422 as final, so a 400 falls through to `SearchCancelResult.queued`. The ride stays live and the outbox replays the same rejected body on every reconnect. The why-sheet reason is sent later as a second `/cancel` on an already `cancelled_by_rider` trip. The contract table has no row for that (terminal → `409 invalid_transition`), so on a contract server the reason is also lost. The mock's R-O3 branch (in_process_mock_client.dart:690) answers 200 there instead.

**Suggested fix:** Always send a contract rider code: use the chosen reason, or a default such as `something_else` for cancel-first. Send the later why-sheet reason as feedback, not as a second cancel. Make the mock require `reasonCode` the way openapi does, and treat 400 as a permanent refusal in `isPermanentCancelFailure`.

### M7. `MatchedDriver.fromJson` reads `id`/`vehicleMake`/... but the contract `DriverSummary` carries `driverId` and a nested `vehicle`, so a contract-conformant projection parses to no driver

`lib/core/contracts/matched_driver.dart:80` (found by rider1)

**What happens:** Staging/production flavor against a backend built from `contracts/openapi.yaml`: the trip reaches `accepted`; `ApiRideRealtime` emits `driverAssigned` with `driver: null`; Waiting shows 'Driver details unavailable' (no name, plate, vehicle, photo) for the whole ride, and the history/receipt has no driver either.

**Why:** The production transport `ApiRideRealtime` builds the driver from the projection with `MatchedDriver.fromJson` (api_ride_realtime.dart lines 201-204), as do `ride_projection.dart:68` and the restore path. `fromJson` requires `json['id']` (line 80, returns null when empty, line 83) and reads flat `vehicleMake/vehicleModel/vehicleColor/plate/photoAsset`. `contracts/openapi.yaml` `DriverSummary` (lines 5281-5305, required `driverId, firstName, vehicle`) and CONTRACT.md §2 (`DriverSummary { driverId, firstName, ..., photoUrl?, vehicle: { make?, model?, color?, plate? } }`) never send `id` or flat vehicle fields. The in-process mock sends `MatchedDriver.toJson()` (`id`, `vehicleMake`, ...), so the mock and the parser agree with each other but not with the shipped contract, and no test can catch it. Against a server that follows `openapi.yaml`, every projection yields `driver == null`.

**Suggested fix:** Accept `driverId` (and `photoUrl`, nested `vehicle.{make,model,color,plate}`) in `fromJson` alongside the legacy flat keys, and have the mock emit the contract shape so the contract tests exercise it.

### M8. isLateEcho drops every camera report for 600 ms after a web flight lands, including the rider's own pan or pinch, so MapView.pose goes stale and the next glide jumps back

`lib/core/maps/map_camera_motion.dart:115` (found by rider-j8)

**What happens:** On the web Home map, the rider taps recenter (a 1 s JS flight). Right after it lands, they quickly drag the map a few hundred metres and let go, all within 0.6 s. Every report is dropped as a late echo, so pose still holds the recenter point. Later an app glide (for example the follow update after the 12 s hold, or a 450 ms refit on a trip map) steps from that stale pose. Its first frame moves the camera back next to the old recenter point, then it glides, which looks like a jump. Worked by reading the code: easing is false after landing, so _onMove's only remaining filter is isLateEcho.

**Why:** After a JS (web) flight lands, _jsGlide sets view.pose to the goal and _landedAt to now (lines 366-368). For the next cameraEchoGrace (600 ms), CustomGoogleMap._onMove discards any reported pose that is not near the landing pose (custom_google_map.dart:202). The check assumes such reports are late echoes of flight frames. Nothing clears _landedAt when the rider touches or moves the map: interrupt() (lines 80-94) and the touching setter leave it set, and _movedByHand only sets movedByHandAt. So the camera moves from a pan, pinch or wheel zoom in that window are thrown away too, as are those of an app animateCamera bounds fit (runCameraUpdate). view.pose stays at the landing pose. The next stepped glide starts from view.pose (easeCameraTo line 325, _glide line 391) and its first frame is sent from that stale origin. This affects a requested trip-map refit (fitBounds with the 450 ms default, a Dart glide) or a follow update once the 12 s hold ends.

**Suggested fix:** Clear _landedAt in interrupt() and in the touching setter, and when movedByHandAt is set, so only echoes that arrive before any newer gesture or command are filtered.

### M9. Firebase-configured web builds (none deployed today) would replace the root-scope Firebase SW with Flutter's self-unregistering flutter_service_worker.js on every cold start, forcing a reload and killing the push subscription

`lib/core/notifications/firebase_push_service.dart:118` (found by rider3)

**What happens:** Staging/production web build with Firebase defines; rider accepted ride-update notifications. Every cold start: boot screen, 1-4 s pause, page reloads itself once, then boots; `/api/v1/push/devices` receives a new token on every launch and old tokens are never unregistered. If the reload lands during an active search, the search restores from the snapshot but the rider sees the app restart.

**Why:** `getToken` passes `serviceWorkerScriptPath: 'firebase-messaging-sw.js'` and firebase_messaging_web registers it with `navigator.serviceWorker.register(path)` and no `scope`, so the registration's scope is the app root (`/movera-rider-app/`). The build never passes `--pwa-strategy=none` (publish-web-live.yml line 45), so Flutter 3.47's `flutter build web` still emits `flutter_service_worker.js` and a `flutter_bootstrap.js` with `serviceWorkerSettings` (flutter_tools web.dart: `includeServiceWorkerSettings = strategy == offlineFirst`, compile.dart defaults to offlineFirst). Flutter's loader (`service_worker_loader.js` lines 105-113) calls `navigator.serviceWorker.getRegistration()` and, whenever ANY registration covers the page, registers `flutter_service_worker.js?v=...` at the same default scope, which replaces the Firebase registration's script. The 3.47 `flutter_service_worker.js` template is a cleanup worker: on activate it `unregister()`s and `client.navigate(client.url)` for every window client. index.html's cleanup (lines 169-176) deliberately keeps the Firebase registration, so on each boot where push consent was accepted: boot waits up to 4 s for SW activation, the page is force-reloaded mid-boot, the push subscription dies with the registration, and `_registerExistingPushSession` then re-registers the Firebase SW and POSTs a brand-new FCM token (`_replaceToken` only unregisters the previous token held in memory, so stale tokens accumulate server-side). The same `getRegistration()` path also fires once for demo visitors who still carry an old `flutter_service_worker.js` registration, because index.html's async `unregister()` races the deferred bootstrap.

**Suggested fix:** Build with `--pwa-strategy=none` (or ship a custom web/flutter_bootstrap.js that calls `_flutter.loader.load()` without `serviceWorkerSettings`), and/or register firebase-messaging-sw.js under its own scope (e.g. `firebase-cloud-messaging-push-scope`) so the loader's root-scope `getRegistration()` finds nothing.

### M10. Inbound push routing (foreground, opened and the launch notification) is attached only after the backend acknowledges the device token

`lib/core/notifications/firebase_push_service.dart:226` (found by r2-rider4)

**What happens:** The API is briefly unavailable when a rider taps a 'Your driver has arrived' notification that launches the app. POST /push/devices fails, so the tap lands on the default root instead of the ride. Later notification taps in that session also do nothing in the app.

**Why:** register() calls `_attachInboundStreams()` only after `await _replaceToken(token)` succeeds. That call POSTs /push/devices and throws when the request fails or is not acknowledged. `_attachInboundStreams` is the only place that listens to onMessage and onMessageOpenedApp and that reads getInitialMessage into `_initialMessage`. If the registration POST fails at cold start (5xx, timeout, offline; bootstrap catches and only logs it), PushCoordinator.start() gets null from takeInitialMessage(), and no foreground or opened push reaches it for the rest of the session. The OS still shows the notifications, because the FCM token exists. Sign-out's unregister() cancels the subscriptions, so a failed re-registration after the next sign-in has the same effect.

**Suggested fix:** Attach the inbound listeners and read getInitialMessage as soon as Firebase is initialised and permission is granted, separately from whether the server acknowledged the token.

### M11. Polling transport misses a driver drop when the first poll of a new subscription (after the Finding to Waiting handover or a retry) already sees searching, or when a later poll jumps straight to a different driver's accepted status

`lib/core/realtime/api_ride_realtime.dart:193` (found by r2-rider4)

**What happens:** Release build on the polling transport. The rider is at the 'driver waiting' stage, the arrived sheet showing driver A (Elin, plate MVR 204) is up, and the phone is pocketed so the app is backgrounded. A drops and dispatch matches B within a minute. On resume, the first poll returns `accepted` with driver B. Waiting swaps the card to B with no 'your driver cancelled' notice. The arrived sheet with A's name and plate stays on top, because it closes only on trip start (line 396). B's arrival is never announced, because `_arrivalAnnounced` is already true (line 452). Variant (a): A accepts and drops within about 1 s. Waiting shows 'Driver found / leave now, Elin' while the server is searching. If no one accepts, `expired` reaches Waiting as noDriverFound and `markExternalTerminal` clears it without archiving (noDriverFound is not in the archive list at active_ride_controller.dart:353-358). The rider is also never offered RIDE-19 'Try again'.

**Why:** ApiRideRealtime reports a driver drop only when `status.isSearching && (poll.lastStatus?.isMatched ?? false)` (lines 193-199). `poll.lastStatus` lives on the per-subscription `_RidePoll`, and `onCancel` (lines 78-84) removes that poll as soon as its only listener cancels. Every handover cancels the only listener: Finding `_openWaiting` calls `_match.dispose()`, which cancels `_sub` (finding_driver_controller.dart:1682), before Waiting subscribes again. `_retryLiveFeed` does the same. So Waiting's tracking always starts with a new poll whose `lastStatus` is null. (a) When the driver drops in the 'just assigned' stage, before Waiting's first poll returns, that first projection is `searching`, `reassigned` is false, and the event goes out as plain `findingDriver`. The first poll can be late because it fails and backs off for 1, 2, 4... s. DriverTrackingController accepts it. Waiting `_onLiveTick` (waiting_for_driver.dart:410-433) only re-dispatches on `cancelledByDriver`, so Waiting stays up with the dropped driver's card. (b) Even inside one poll, a drop is missed when driver B accepts before the next successful poll: every 2 s, or a backgrounded app whose timers paused. The stream then goes straight from driverArriving/driverWaiting(A) to driverAssigned(B). Nothing compares driver ids, so no notice is shown.

**Suggested fix:** Keep reassignment state (last lifecycle status and driver id) per ride id, outside the per-subscription poll, for example in a map like `_sequences`. Also treat a change of `driver.id` between two matched projections as a driver-cancelled reassignment, so Waiting re-dispatches or at least shows the notice, closes the old arrived sheet and resets `_arrivalAnnounced`.

### M12. After the not-found pause, a successful resync never restarts periodic polling: the ride freezes while the connection reports connected

`lib/core/realtime/api_ride_realtime.dart:383` (found by rider1)

**What happens:** Production transport (staging/production flavors). The trip endpoint answers 404 three polls in a row (replica lag, a brief routing fault). Polling pauses and the banner shows failed. The rider taps retry / the app resumes -> `reconnectAndResync` -> 200, banner says connected. From then on the driver's position, arrival, boarding and completion never arrive on this screen; the ride appears stuck at that status indefinitely although the connection state claims it is live.

**Why:** `_endNotFound` (lines 347-353) cancels `poll.timer` and sets `poll.timer = null` after `notFoundLimit` consecutive 404s. `reconnectAndResync` (lines 379-390) only flips `poll.ended = false`, lowers `poll.notFound` and runs one forced `_poll`. Nothing re-creates the `Timer.periodic` that `subscribe()`'s `onListen` made (lines 69-77), and `onListen` does not run again because the broadcast controller already has its listener. When the forced poll succeeds, the success path calls `connection.markConnected()` (line 256) so the UI banner clears, but no further GET is ever issued for that ride: the Waiting/in-trip screen keeps showing the projection from that single read until the user triggers another manual resync. Reproduced with a throwaway test (3x404, resync -> 200, pollInterval 20 ms): `AUDIT A: events after resync = 1, state = RealtimeState.connected` then `AUDIT A: calls after 200ms of connected state = 4` (no new polls). Callers: `FindingDriverController` lines 897/1156/1288/1642, `WaitingForDriver` line 929, `RideRestoreCoordinator` line 167, `notification_navigation.dart` line 89 all use `reconnectAndResync` as the recovery path.

**Suggested fix:** In `reconnectAndResync` (or in `_poll`'s success path when `poll.timer == null` and the controller has listeners) re-create `poll.timer = Timer.periodic(pollInterval, (_) => unawaited(_poll(poll)))` once the forced read succeeds; keep it cancelled while `poll.ended` is true.

### M13. Mock driver position and arrival are computed against a hard-coded central-Stockholm pickup (never hydrated on resume, hydrated only after the first assignment fix), so after a reload the driver approaches and 'arrives' at Stockholm instead of the trip's pickup

`lib/core/realtime/mock_ride_realtime.dart:183` (found by rider2)

**What happens:** Demo build (R-web: 'a live ride must survive browser reload'). Rider books Gare du Nord -> Louvre (Q7 Paris zone) or a Södertälje pickup, gets a driver, reloads the tab: the driver marker appears in central Stockholm, the ETA reads ~2 min then jumps, the car 'arrives' and the trip starts from a point tens or hundreds of km from the pickup, and the free-cancel countdown restarts from the reload.

**Why:** `_pickupLat/_pickupLng` default to (59.3293, 18.0686) in both the resume path (lines 183-184) and `_assignNow` (lines 263-264), and the driver start position is derived from that default (`lastLat ??= _pickupLat! + 0.0072`, lines 209-210 and 265-266). The real pickup is only fetched by `_hydratePickup()` after the `driverAssigned` event (line 305) and never on the `primeResume` path; after a web reload the stand-in server is empty anyway so `_pickup()` 404s and keeps the default (line 660). `_startGps` therefore lerps toward and declares `driverWaiting` within 50 m of central Stockholm for a Paris/Tunis/Södertälje pickup, `_etaSeconds` is computed against that point, and the resumed `emit()` sets `_acceptedAt ??= now` / `_waitingSince ??= now` (lines 328-333) which `DriverTrackingController` adopts (`acceptedAt = event.acceptedAt ?? acceptedAt`) so the free-cancel/waiting clocks restart at reload time. Reproduced: a Paris trip resumed via `primeResume(driverArriving)`: `AUDIT D: resumed event lat=59.3365 lng=18.0638 eta=102s acceptedAt=<now>`.

**Suggested fix:** Let `primeResume` (and the first assignment) take the pickup coordinates and the snapshot's `acceptedAt`/`waitingArrivedAt`; hydrate the pickup before emitting `driverAssigned`, and do not stamp `_acceptedAt`/`_waitingSince` with the resume time.

### M14. Reload while the driver is waiting at pickup regresses the ride to 'driver arriving' with the car about 800 m away

`lib/core/realtime/mock_ride_realtime.dart:209` (found by r2-rider2)

**What happens:** Demo build: the driver reaches pickup (Waiting shows 'Your driver has arrived'). The rider reloads, or Safari kills the tab. Waiting comes back as driverWaiting, and 3 s later it switches to 'driver arriving' with the car drawn about 800 m away. The stored snapshot is overwritten with driverArriving. The car then drives back and announces its arrival again.

**Why:** pageFor primes the mock with the snapshot status (ride_restore_coordinator.dart:339-344). For any matched status that is not on board, subscribe() takes the pre-trip branch: it places the driver at `pickup + 0.0072 / -0.0048` and starts _startGps(). It does this for driverWaiting too. The first GPS tick 3 s later moves only 18% toward pickup, so the distance is still far over 50 m. It then sets `status = RideStatus.driverArriving` and emits it with a higher sequence. DriverTrackingController accepts it, because the version is newer than the seeded one. _persistLiveStatus then saves driverArriving: _wouldRegress allows a lower stage when the incoming version is greater. Waiting goes back to 'driver on the way'. About 15 ticks (roughly 45 s) later the driver 'arrives' a second time and the arrived sheet and the boarding timer run again.

**Suggested fix:** On resume with driverWaiting, put the driver at pickup and call _startTrip() instead of _startGps(). Never emit an approach status lower than the primed one.

### M15. Pickup coordinates are not reset between rides, so the next ride's driver spawns near the previous ride's pickup

`lib/core/realtime/mock_ride_realtime.dart:263` (found by r2-rider2)

**What happens:** In one session the rider takes a ride from Södertälje and then books a ride from Arlanda. The 'driver found' marker and ETA show a driver about 50 km away at the old pickup, who then speeds across the map for about 100 s; the server projection stores that position too.

**Why:** For a new ride, `subscribe` resets lastLat/lastLng, progress, trip start and clocks, but not `_pickupLat`/`_pickupLng`. `_assignNow` then uses `_pickupLat ??= ...` and `lastLat ??= _pickupLat! + 0.0072` *before* `_hydratePickup()` fetches the new ride's pickup. On the second and later rides of a session, the driver is spawned next to the *previous* ride's pickup. That position is committed to the server through `_persistAssignment` (driverLat/driverLng) and is emitted to the UI, and the GPS walk then has to cross the whole distance. This is a different root cause from the known hard-coded Stockholm spawn (that one concerns the first ride or a resume, when the field is null).

**Suggested fix:** Reset `_pickupLat`/`_pickupLng` in subscribe for a new ride, and hydrate the pickup before spawning or emitting the assigned driver.

### M16. A queued (offline) end-early that the server later applies is committed as a plain cancel: no receipt, History shows 'Cancelled · booked price', and the reason is lost

`lib/features/active_ride/application/active_ride_controller.dart:160` (found by r2-rider1)

**What happens:** The rider taps 'End trip here' on board with no connection and gets 'We couldn't reach Movera…'. On reconnect the outbox posts /end-early, and the server sets fare to the distance price, e.g. 80 kr. Polling reports cancelledByRider, and the app goes Home with no receipt. History shows 'Cancelled ride · Movera · Booked price 245 kr' with no 'Ended early' and no reason, although 80 kr was charged.

**Why:** When an on-board end-early cannot reach the server, it stays in the outbox (`command: endEarly`). Later the flush, or `_dropIfCancelQueued` on restore, sends it. `_dropIfCancelQueued` deliberately keeps the snapshot for end-early so that 'the restored trip resyncs and shows how the server closed it' (ride_restore_coordinator.dart:144-150). Realtime then reports cancelledByRider, and Waiting's `_handleExternalTerminal` calls `completeServerConfirmedCancel()` (waiting_for_driver.dart:570-576). That method calls `_commitCancelled(rideId)` with no `endedEarly` and no `reasonId`. So there is no `LastCompletedRide`, no ended-early summary, History gets `endedEarly: false` and no `chargedFare`, the stored reason is dropped, and the rider is sent straight Home.

**Suggested fix:** Keep the queued command and reason (or read `cancellation`/`fare`/`endedEarly` from the projection). For an end-early, commit it with an EndedEarlyTrip (charged = projection fare) and open the ended-early summary instead of going Home.

### M17. The cancel fee charged for a Book-now ride is never stored on the History record, so History shows 'Cancelled · Booked price X' with no fee line

`lib/features/active_ride/application/active_ride_controller.dart:308` (found by r2-rider1)

**What happens:** Economy ride at 245 kr. The driver accepted 3 minutes ago. The rider opens Cancel and the sheet says 'Cancelling now costs 35 kr.' They confirm, and the server stores cancellation.fee = 3500 öre. In History > Cancelled the card says just 'Cancelled', and the detail says 'Movera · Booked price 245 kr' with no fee line. The rider cannot see that they were charged 35 kr, and the screen suggests 245 kr.

**Why:** When the rider cancels on Waiting after the free window, the mock server works out `_riderCancelFee` and stores it as `ride.cancellation.fee` in the cancel response (in_process_mock_client.dart:712, 724-733). `ActiveRideController._requestServerCancel` only reads `fare` from that response (`_chargedFare`, lines 282-285). `_commitCancelled` then archives with `_archive(snapshot, RideStatus.cancelledByRider, ...)`, which has no fee argument. `OnDemandRideHistoryStore.recordFor` (on_demand_ride_history_store.dart:184-235) builds the `Reservation` without `cancellationFee`, and so does the server-backed `ApiRideHistoryRepository._record`. History does have a fee display: `ReservationFormat.historyStatus` shows 'Cancelled · fee X', and the detail sheet shows the `cancelFee` line (ride_history.dart:537). Neither ever appears for an on-demand ride. `Reservation.cancellationFee` is only ever set by the reservation repository.

**Suggested fix:** Parse `projection/ride.cancellation.fee` (Money) from the cancel response and from server trips. Pass it through `_archive` / `archive` / `recordFor` into `Reservation.cancellationFee`.

### M18. A trip that ends in paymentFailed is cleared without a History record or receipt; the rider is told only 'the trip is not active'

`lib/features/active_ride/application/active_ride_controller.dart:353` (found by r2-rider1)

**What happens:** I reproduced this with a throwaway widget test: an in-trip Waiting with a stored snapshot, then MockRideRealtime.emit(RideStatus.paymentFailed). Afterwards OnDemandRideHistoryStore.read() had length 0 and RideSnapshotStore.read() was null. The rider is driven to the destination and the payment fails, then the ride vanishes: no History entry, no receipt, no way to retry payment.

**Why:** paymentFailed is a post-completion state: the trip was driven and completed, and the payment failed (trip_status.dart:183). Waiting treats it as an external terminal (waiting_for_driver.dart:417, 589-595). markExternalTerminal archives only the cancel/no-show/failed statuses, then always runs _store.clear(). So a completed trip whose payment failed is not archived to the device History and gets no completion or receipt screen. The rider sees the generic 'Payment could not be completed ... The trip is not active' sheet and lands on Home. The trip they took is no longer visible anywhere on the device.

**Suggested fix:** Archive paymentFailed (it is a completed trip) before clearing, and/or route it to the completion surface that can show the payment problem.

### M19. A destination or pickup moved on the map is discarded when its label matches the current address; the rider is told the route was updated

`lib/features/active_ride/application/route_change_controller.dart:172` (found by r2-rider4)

**What happens:** Destination 'Mall of Scandinavia'. The rider opens 'Pick on map', drags the pin 400 m to the other entrance and confirms before the label changes (or it resolves to the same name). The sheet shows 'Same price', the rider confirms and gets 'Route updated, driver told', but the destination coordinates did not change.

**Why:** `preview` picks the coordinates by comparing the address string: if the new destination text equals `ride.destinationAddress`, it uses the old point and ignores the `destinationPoint` the picker passed. The pickup is handled the same way at :153. ConfirmPickupSpot often returns the same label after a pin move: it keeps `initialAddress` until the reverse geocode settles, a nearby pin resolves to the same street address, and an unresolvable point gives the 'Pickup location' fallback. In those cases the moved point is thrown away, the server prices and applies the old route ('Same price'), and Waiting shows 'Route updated · driver told'.

**Suggested fix:** Use the explicit point whenever one was given (`destinationPoint ?? (same label ? old point : locate)`), and the same for pickup.

### M20. A stop chosen on the map or from a suggestion loses its coordinates and is re-geocoded from its label (in demo: a hash point about 0.5-0.7 km from Stockholm Central, or 'Current location')

`lib/features/active_ride/presentation/route_change_flow.dart:97` (found by r2-rider2)

**What happens:** In the trip the rider taps Add stop, uses 'Pick on map' and drops the pin at a friend's door. The confirmed label is re-geocoded, the stop lands several km away, and the price, the orange stop marker and the driver's stop all point to the wrong place.

**Why:** In the route picker, choosing a stop keeps only the text: `_choose` in the 'stop' branch drops `point`. `openRouteChange` also passes `selection.stops` to `preview` without any `stopPoints`. `preview` then geocodes each new stop by its label. The mock geocoder returns a hash-derived point within about ±6/±8 km of Stockholm Central for any label that is not a demo place. A map-pick label ('Pickup location' fallback, a reverse-geocoded street) can also fail with 'Address not found'. That wrong point is priced (25 kr + km), saved, drawn and sent to the driver.

**Suggested fix:** Keep a point per stop in RoutePickerSelection (as for pickup/destination) and pass them as `stopPoints` to preview.

### M21. Scheduled ride's live screen takes the waiting-fee terms and cancel-fee preview from the on-demand RideSession's last booked category

`lib/features/active_ride/presentation/waiting_for_driver.dart:296` (found by r2-rider1)

**What happens:** Earlier in the session the rider booked an Economy ride (bookedCategoryId = 'economy'). Later their XL reservation goes live and the driver has accepted. Tapping Cancel shows 'Cancelling now costs 35 kr', the economy live fee (fixed 3500 öre after 2 free min). The XL live rule is 15% with a 50 kr minimum, and the reservation cancel that actually runs (`reservations.cancel`) applies reservation rules. When the driver waits at pickup, the fee counter uses economy's 5 free minutes instead of XL's 3. Not run; worked from the seed config in rider_app_config.dart:612-690.

**Why:** WaitingForDriver is reused for scheduled rides. Its widget comment says it runs 'without touching the on-demand ride session'. Two places still take the category from `AppScope.instance.ride.bookedCategoryId`, falling back to the on-demand `RideSnapshotStore` snapshot without checking its ride id: `_loadWaitingTerms` (waiting-fee counter) and `_cancelFeeNote` (the 'Cancelling now costs …' line). For a reservation, `widget.rideId` is the reservation id. The session's booked category belongs to whatever Book-now ride ran last in this process. It is never cleared: `RideSession.reset()` leaves `bookedCategoryId`/`bookedPaymentMethodId`/`bookedMaxOfferMinor` untouched, so it can even be the previous rider's after a sign-out. The reservation's own `categoryId` is never consulted. With no Book-now ride in this process, the note and counter silently disappear.

**Suggested fix:** Pass the trip's categoryId into WaitingForDriver (the reservation's categoryId; for Book-now, the snapshot's) and use it instead of the session. Accept the stored snapshot only when its rideId equals `_rideId`. Clear the booked* fields in RideSession.reset().

### M22. After a reload, the server's waiting.arrivedAt and acceptedAt are thrown away, so the waiting fee clock restarts on every rebuild and the cancel-fee preview counts from reload time

`lib/features/active_ride/presentation/waiting_for_driver.dart:322` (found by r2-rider1)

**What happens:** I reproduced this with a throwaway widget test: snapshot version 5 at driverWaiting with category economy, session reconciled at version 5, then mock emit(driverWaiting, sequence: 5), which carries waitingArrivedAt. WaitingFeeCounter.since was 01:39:30.719. After one Waiting rebuild it was 01:39:32.013, so it moved by 1.29 s and equals 'now' on each build. A rider who reloads while the driver waits sees 'free waiting 5:00 left' reset each time the sheet moves while the server is already charging. The cancel sheet may also say 'free for N more minutes' when a fee applies.

**Why:** DriverTrackingController applies event.acceptedAt and event.waitingArrivedAt only inside `if (accepted)` (driver_tracking_controller.dart:127-145). A restore seeds the session with the snapshot's version (ride_restore_coordinator.dart:312-326), and tracking saves the latest version into the snapshot. The first projection after a reload therefore usually has the same version and status, and backendReconcile rejects it as a duplicate (ride_session.dart:168-173). So waitingSince and acceptedAt stay null although the projection carries them. Waiting then passes `since: _tracking.waitingSince ?? DateTime.now()` to WaitingFeeCounter. That value is recomputed on every Waiting rebuild (sheet settle, measurement, signature change), so the free-wait countdown restarts each time and never reaches the fee. The cancel-fee preview falls back to _shownAt (759), which is the reload time, although the server sent acceptedAt. The comment at 752-754 accepts that fallback only when 'the projection has no acceptedAt'.

**Suggested fix:** Apply acceptedAt and waitingArrivedAt (timestamps from the server) even when the status part of a same-version event is not accepted. At minimum, compute the WaitingFeeCounter fallback once and keep it, rather than DateTime.now() on each build.

### M23. Reload during re-dispatch after a driver drop restores Waiting with the dropped driver; Waiting never reacts to a searching status

`lib/features/active_ride/presentation/waiting_for_driver.dart:417` (found by rider2)

**What happens:** Release build: driver accepts, then drops the ride; the rider reloads the web app (or the process is restarted) before the next driver accepts. Waiting shows the old driver as 'on the way' while the server is searching; messages go to a driver who is no longer on the trip.

**Why:** `DriverTrackingController._persistLiveStatus` skips terminal statuses (211-212), and `ActiveRideController.resumeSearchingAfterDriverCancel` explicitly does not persist (327-334), so after a driver drop the stored snapshot still says `driverArriving`/`driverAssigned` with the old driver until the next accept. A reload in that window (`RideRestoreCoordinator.surfaceFor`, 285-291) restores `WaitingForDriver` with `driver: snapshot.driver`. With `ApiRideRealtime` the first poll carries `searching`; `reassigned` is only derived when `poll.lastStatus?.isMatched` (api_ride_realtime.dart 193-199), which is null on a fresh poll, so the event is a plain `findingDriver`. `_onLiveTick` has branches only for `cancelledByDriver`, terminal and completed statuses (410-423); a searching status falls through to the normal sheet rendering, so the screen keeps the 'Driver found' headline (`_headlineFor` → `eta?.headline(status: findingDriver)`), the dropped driver's card, plate and message/call buttons, and no reassignment notice. The rider only learns a new driver was assigned when the next accept arrives; a second reload would restore Finding because `_persistLiveStatus` then saves `findingDriver`.

**Suggested fix:** Persist the `findingDriver` status (without driver) when the research starts, and have Waiting treat an incoming `isSearching` status the same way as `cancelledByDriver` (back to Finding).

### M24. A terminal or completion status that arrives while a cancel/end-early is in flight is dropped. After a rejected or pendingRetry outcome, Waiting stays on an ended trip until the next live tick, and for a truly terminal status (noShow, cancelledByAdmin) that tick may never come

`lib/features/active_ride/presentation/waiting_for_driver.dart:515` (found by r2-rider1)

**What happens:** On board, the rider taps End trip just as the driver completes the trip. tripCompleted arrives on realtime while the POST is in flight and is ignored. The server answers 409 invalid_transition, so the outcome is rejected. The rider sees 'This ride can no longer be cancelled' and stays on the Waiting screen with the trip ended and no completion screen. The same happens with noShow or cancelledByAdmin during an in-flight cancel.

**Why:** _confirmCancel sets _leaving=true (820) while it awaits _ride.markCancelled, which can take two network attempts. During that time _onLiveTick sends terminal statuses to _queueStageNavigation, and that returns before it stores _pendingStageStatus (515). _maybeOpenCompleted also returns early (542). If the server then answers rejected (409: 'the ride already ended — realtime reports the real outcome', active_ride_controller.dart:256-259) or the call ends as pendingRetry, _confirmCancel resets _leaving=false (848-851). Nothing replays the swallowed status. A terminal status gets no further events, so nothing ever navigates. Only the 'stale' outcome triggers a resync (923-936); 'rejected' does not.

**Suggested fix:** Store the status in _pendingStageStatus even while _leaving, and drain it (or re-check _tracking.status) after a non-confirmed cancel outcome. Alternatively, resync on rejected as is done for stale.

### M25. A queued on-board End trip that the outbox later delivers is committed as a plain cancel, with no ended-early receipt or rating

`lib/features/active_ride/presentation/waiting_for_driver.dart:570` (found by r2-rider1)

**What happens:** The rider is in the car with a flaky connection and taps End trip. They see 'couldn't reach Movera ... we'll retry'. The connection returns, the queued end-early is accepted and the rider is charged for the distance. The app then jumps straight to Home: no ended-early summary, no fare, no rating, and History shows a plain 'Cancelled' ride with no charge.

**Why:** If the rider taps End trip on board while the server cannot be reached, markCancelled returns pendingRetry and queues an end_early command in the outbox (active_ride_controller.dart:207-211). The outbox flush later sends it. The server applies end_early, which moves the trip to cancelled_by_rider (trip_transitions.dart:103-104) and charges the distance fare. Realtime then reports cancelledByRider to Waiting. _handleExternalTerminal takes the cancelledByRider branch and calls completeServerConfirmedCancel(), which calls _commitCancelled with no endedEarly. As a result: LastCompletedRide.remember is skipped, the History record has endedEarly:false and no charged amount, and RideNavigator.home is called. UI-01 says an on-board end 'is a finished trip with a receipt, not a silent return to Home' (waiting_for_driver.dart:860-862), and R-O6 says the rider rates an ended-early trip on the trip-end screen. Neither happens here. Nothing in Waiting listens for the outbox's `sent` outcome; it only listens for refused/stale.

**Suggested fix:** When committing a server-confirmed cancelledByRider, check the outbox entry or the last in-trip stage. If it was end_early, build an EndedEarlyTrip (fare from the projection) and open the ended-early summary as the direct path does.

### M26. A 'closed' projection reaching Waiting throws ArgumentError in markExternalTerminal and leaves Waiting dead

`lib/features/active_ride/presentation/waiting_for_driver.dart:589` (found by r2-rider1)

**What happens:** I reproduced this with a throwaway widget test: snapshot plus session at tripInProgress, then MockRideRealtime.emit(RideStatus.closed). Result: 'ArgumentError: Invalid argument (status): Expected a non-rider external terminal status.' thrown from markExternalTerminal <- _handleExternalTerminal:589 <- _drainStageNavigation:533 <- _onLiveTick:418, and WaitingForDriver was still mounted afterwards. The rider is stuck on a frozen in-trip screen whose stored snapshot is never cleared.

**Why:** RideStatus.closed is terminal but not a completed surface (core/contracts/ride_status.dart:59-89). In _onLiveTick (417-418) it goes to _queueStageNavigation, then _drainStageNavigation (532-533) calls _handleExternalTerminal. That path sets _leaving=true, disposes tracking, and calls _ride.markExternalTerminal(closed) at line 589. markExternalTerminal (active_ride_controller.dart:337-347) explicitly throws ArgumentError for closed. The future is unawaited, so the error is unhandled. Waiting stays mounted with tracking stopped, no terminal sheet, no navigation and no snapshot clear. RideSession.backendReconcile says projections may jump on reconnect (ride_session.dart:140-143, e.g. 'driverArriving -> paymentFinalized'), and _afterCompletion maps completed + captured + rating submitted/skipped to closed (trip_status.dart:186-190). So an in-trip Waiting that resyncs after the trip was settled and rated, or after the rating window was skipped, gets this status.

**Suggested fix:** Route closed (and other post-trip statuses) to the completion surface or Home without calling markExternalTerminal, e.g. treat closed like a completed surface in _onLiveTick/_drainStageNavigation, or close the ride via closeCompletedRide.

### M27. On the reservation live screen, the cancel-fee note and waiting terms use the Book Now session's leftover category and live fee rule, not the reservation's

`lib/features/active_ride/presentation/waiting_for_driver.dart:774` (found by r2-rider1)

**What happens:** The 23:50 Comfort reservation goes en route (inside the late window, so a kr 60 fee applies under the reservation rules). The rider taps Cancel on the live screen. With no Book Now session the sheet shows no fee line, so it reads as free. If an older Economy Book Now session is still in memory, it shows 'Free to cancel for 2 more minutes' from the live economy rule.

**Why:** For a reservation, `ReservationLiveRide.pageFor` mounts WaitingForDriver. `_cancelFeeNote` and `_loadWaitingTerms` take the category from `AppScope.instance.ride.bookedCategoryId ?? RouteChangeController.storedRide()?.categoryId`. Those belong to the global Book Now session and snapshot, not to the reservation (whose `categoryId` is not passed in). The note then applies the LIVE fee rule (`LiveCancelFeePreview`, minutes since accept), not the reservation's late-cancel terms. With no Book Now ride the category is null, so the sheet shows no fee at all. With a stale Book Now session it shows another category's live fee. This differs from the known finding that the live-screen cancel records no fee: here the fee line the rider confirms against is wrong.

**Suggested fix:** Pass the reservation's categoryId (and a fee-note provider using ReservationController.cancelTermsFor) into WaitingForDriver from ReservationLiveRide.pageFor.

### M28. Back gesture while the Waiting cancel/end-early request is in flight pops Waiting; Finding underneath stays parked and the cancel result is lost

`lib/features/active_ride/presentation/waiting_for_driver.dart:820` (found by rider2)

**What happens:** On Waiting the rider confirms 'Cancel ride', the network is slow, and they press the Android back button during the 'Cancelling…' card. Waiting disappears and the rider sees a dead grey Finding screen; depending on the server answer the ride is either cancelled with no Home navigation or still live with no way to see or cancel it from this screen.

**Why:** `_confirmCancel` sets `_leaving = true; setState(() {});` (820-821) before `await _ride.markCancelled(...)` (838). `PopScope(canPop: _leaving, ...)` (1441) therefore lets a system back pop Waiting while the server request is still out (up to two attempts with 15 s timeouts each). The `_cancelling` overlay only blocks pointer input, not back. After the pop, `if (!mounted) return;` (846) discards the outcome: if the server confirmed, `_commitCancelled` already cleared the snapshot and set the session to `cancelledByRider` but `RideNavigator.home` is never called; if it was `pendingRetry`/`rejected`, the ride stays live with no screen. Waiting was pushed by `FindingDrivers._openWaiting` with `await Navigator.push<bool>` (finding_drivers.dart 535-556); the pop returns null, so `researchDriver != true` and Finding remains with `_leaving = true`, `_mapParked = true` and a disposed `_match` (528-531): a blank parked screen whose close button is inert (`_confirmCancel` returns on `_leaving`, 568).

**Suggested fix:** Keep `canPop` false while `_cancelling` is true (set `_leaving` only after the outcome is known), or handle `didPop` by finishing the flow from the result.

### M29. Cancel confirmed on a sheet opened before boarding sends a charged end_early if the trip starts while the sheet is open

`lib/features/active_ride/presentation/waiting_for_driver.dart:838` (found by r2-rider1)

**What happens:** Demo: the driver reaches pickup, and the mock boards the rider 8 s later (`boardAfter`). The rider taps Cancel while the driver waits and sees 'Cancel ride? … Cancelling is free for less than a minute more.' They pick a reason. Meanwhile tripStarted arrives. On confirm, POST /rides/{id}/end-early runs and the rider lands on an 'Ended early' summary charged the base fare (e.g. 45 kr) for a cancel the app called free.

**Why:** `_confirmCancel` fixes the phase (`CancelPhase.matched`) and the fee note ('free…') when the sheet opens (lines 804-812). Then it awaits two sheets, the confirm sheet and the reason sheet. Nothing closes or re-checks them when the stage changes: `_onLiveTick` only closes the arrived sheet on trip start (lines 396-403). After the rider confirms, `markCancelled` chooses the command from the session status at send time (`onboard = tripRiderOnboardStatuses.contains(...)`, active_ride_controller.dart:207-211). It therefore posts `/end-early`, and the server charges base fare plus distance (`_endEarlyFare`). The app then opens the 'ended early' receipt. Finding has a guard for this exact race (RIDE-15, `driverMatched` closes the sheet); Waiting has none for boarding.

**Suggested fix:** Close the cancel and reason sheets when `_isInTrip` changes, as RIDE-15 does on Finding. Or pass the phase the rider confirmed into markCancelled, and refuse or re-ask when the session's onboard state no longer matches it.

### M30. Ride check 'long stop' fires when the rider's own connection drops mid-trip, because connectionDegraded is never set on the polling transport (default threshold 2 min, not 4)

`lib/features/active_ride/presentation/waiting_for_driver.dart:1113` (found by r2-rider1)

**What happens:** Release build, trip in progress. The rider's phone loses network for 5 minutes, for example in a tunnel or a dead zone, while the car keeps moving. About 4 minutes after the last fix the Ride check card opens asking whether everything is OK because the car 'stopped for 4 minutes'. The rider is alarmed by a false alert, and an answer may be posted to admin's Ride check log. Traced by reading the code.

**Why:** The 15-second stillness timer is meant to run only 'while the trip is under way and the live feed is up', and it uses `_tracking.connectionDegraded` as that check. `DriverTrackingController` sets that flag only from the stream's `onError`/`onDone`. `ApiRideRealtime._poll` never adds an error to the stream: a failed poll only calls `connection.markFailed()` and backs off. So when the rider's phone loses network during the trip, no new fixes arrive, `connectionDegraded` stays false, and `RideCheckMonitor.checkStill(now)` measures the time since the last fix as a stop. After admin's `longStop` minutes (4 by default) it opens the 'long stop' Ride check card, though the car may be driving normally.

**Suggested fix:** Also skip `checkStill` while `AppScope.instance.realtime.state != RealtimeState.connected`, or have the poller mark the tracking feed degraded on failure. Reset the still anchor when the feed returns.

### M31. The 'not in traffic' exemption for long stops is dead: samples never set inTraffic, so stops in a traffic queue open Ride check

`lib/features/active_ride/presentation/waiting_for_driver.dart:1212` (found by r2-rider1)

**What happens:** In a jam on Essingeleden the car creeps less than 25 m in 2 min 15 s. The 15-second checkStill timer fires a long stop and the non-dismissible card covers the trip screen, although the page says stops in traffic are excluded.

**Why:** RideCheckMonitor skips stops in traffic only when `sample.inTraffic` is true (ride_check_monitor.dart:175 and 192). The only producer of live samples builds `RideCheckSample(point: point, at: at, etaSeconds: eta?.seconds)`, which leaves inTraffic at its default of false. No other code sets it (a grep finds no traffic signal anywhere). The rider-facing RideCheck page promises 'The car stops for more than {minutes} min, not at a planned stop or in traffic.' (app_en.arb:1991). In practice any queue where the car moves less than 25 m for more than longStopMinutes (default 2) opens the blocking 'Is everything OK?' card.

**Suggested fix:** Feed a traffic signal into RideCheckSample, for example from server ETA growth or speed versus the route's expected speed, or a server-provided flag. Otherwise remove 'or in traffic' from the copy.

### M32. On web, the moving driver car makes a new blob URL that is never revoked, plus an image load, about 20 times a second for the whole live ride

`lib/features/active_ride/presentation/waiting_for_driver.dart:2012` (found by r2-rider1)

**What happens:** A rider on iPhone Safari (public web demo or a real web build) follows a 30-minute trip: driver to pickup, then in trip. The mock or live feed sends a fix every 2-3 s, so the ease never stops. Worked by hand: about 20 marker updates/s x 1800 s = about 36,000 Blob URLs of the 31x31 car PNG (about 1-2 KB each), so about 36-72 MB kept in the blob store. Also about 36,000 image elements loaded, and an icon swap on every frame. Memory grows without bound and the map stutters. On a longer trip, iOS Safari kills the tab mid-ride and the page reloads. Not run (read-only audit); traced through the plugin source in ~/.pub-cache.

**Why:** The car's ease now runs for almost the whole gap between fixes, because driverEaseDuration copies that gap (0.4 to 4 s). Its listener rebuilds the marker set every 50 ms (lines 1999-2013). Each set has a driver Marker at a new position (lines 2298-2308). Its icon is a BytesMapBitmap with no width or height: `BitmapDescriptor.bytes(data.buffer.asUint8List())` at lib/shared/widgets/movera_map_markers.dart:173. GoogleMap sees the driver marker as changed on every update. google_maps_flutter_web 0.5.14+2 then runs, per update: `_changeMarker` -> `_markerOptionsFromMarker` -> `_gmIconFromBitmapDescriptor` -> `urlFromMapBitmap`, which calls `URL.createObjectURL(Blob(bytes))` (convert.dart:754-760). The URL cache is cleared after every batch (`_cleanUpBitmapConversionCaches()`, google_maps_controller.dart:577), so every update gets a fresh Blob copy of the PNG. The plugin never calls revokeObjectURL for marker icons, so each Blob lives until the page unloads. With no width or height given, `_getBitmapSize` -> `_fetchBitmapSize` also creates an HTMLImageElement and waits for it to load on every update (convert.dart:404). Then `marker.options = ...` gives Google Maps a new icon URL to fetch and decode. The U7 change only kept the map leaf from rebuilding. It did not stop the per-update icon churn on the web, which is the main shipped platform. The comment in home_controller.dart:172-178 shows the team knew each repaint costs "a new blob URL and image decode on the web". It does not account for those URLs never being freed.

**Suggested fix:** On web, give frequently moving markers an icon that does not go through a blob. One option is an AssetMapBitmap (BitmapDescriptor.asset with explicit width/height), which resolves to a stable asset URL with no Blob and no size probe. Another is to cap web driver-marker updates to once per fix (no 20 fps interpolation). At minimum, pass width/height to BitmapDescriptor.bytes to skip the per-update image probe.

### M33. In-trip road route and Ride check's planned route go driver to destination only and ignore stops (booked or added), so driving to a stop more than 2 km off the direct line fires a false 'off route' alert

`lib/features/active_ride/presentation/waiting_for_driver.dart:2334` (found by r2-rider1)

**What happens:** Trip Sergels torg → Odenplan. In the trip the rider adds a stop at Liljeholmen, about 4 km south. The map keeps drawing the line straight to Odenplan. As the driver heads south to the stop, Ride check opens 'Your driver seems off route'.

**Why:** During the trip `_routeEndpoints` returns only driver → destination, and `_refreshRoadRoute` asks `roadRoutePolyline(from,to)` for those two points, so the drawn route never passes the rider's stops (the stop markers sit off the line). The same polyline goes to `RideCheckController.setPlannedRoute` through `onTripRoute`. `RideCheckMonitor._offRoute` measures distance only against `_route`; stops are not excluded. After the rider adds a stop more than `offRouteKm` (2 km) from the direct road, a driver correctly heading to the stop triggers an offRoute Ride check card. `replan` on route change resets `_route`, but the next route it gets is again stopless.

**Suggested fix:** Route driver → remaining stops → destination (a waypoint route), and give Ride check that route; or drop the planned route when stops exist and use the per-stop plan only.

### M34. In-trip road route and Ride check planned route go straight from driver to destination and ignore booked stops, causing false off-route alerts on multi-stop trips

`lib/features/active_ride/presentation/waiting_for_driver.dart:2386` (found by r2-rider1)

**What happens:** A trip from Södermalm to Solna with a stop in Bromma. Once on board, the planned route is the direct Södermalm to Solna road line. The driver heads to Bromma, more than 2 km from that line, and the Ride check card asks the rider if they are OK because the car is 'off route'. The map also draws a route that bypasses the stop.

**Why:** _routeEndpoints for the in-trip stage returns only driver to destination (2334-2346), and _refreshRoadRoute asks roadRoutePolyline for that single leg. The resulting points are passed to RideCheckController.setPlannedRoute through onTripRoute (2386-2390 -> 1474-1481). RideCheckMonitor keeps the first route (setPlannedRoute without replace) and fires offRoute when a fix is more than offRouteKm (default 2 km) from it (ride_check_monitor.dart:98-102, 212-220). When the driver goes to a booked stop more than about 2 km off the direct line, as they are supposed to, the safety Ride check fires an 'off route' alert. The rider-facing polyline also skips the stop.

**Suggested fix:** Route the in-trip leg through the remaining stops (or concatenate per-leg road routes) before showing it and handing it to Ride check, or do not set a planned route when the trip has stops.

### M35. Safety Kit row on the Waiting sheet uses the on-demand session's rideId, not the screen's ride, so SOS, share and recording target no ride or the wrong one on scheduled live rides

`lib/features/active_ride/presentation/waiting_sheet_bits.dart:550` (found by r2-rider4)

**What happens:** On a scheduled ride's live screen, the rider opens Safety Kit from the row in the sheet and taps SOS. The SOS is not registered with the trip (sos returns false). Trip share starts for an empty ride id. The same actions from the map button work.

**Why:** WaitingNotesAndPin builds SafetyKitSheetRow with AppScope.instance.ride.rideId. The rest of Waiting uses _rideId, which is widget.rideId ?? session.rideId (for example SafetyKitMapButton(rideId: _rideId) at waiting_for_driver.dart:1503). ReservationLiveRide.pageFor passes rideId: reservationId with its own realtime, while the on-demand session holds null or a previous on-demand ride. From the sheet row, RideSafetyKitSheet then calls _ctl.sos(rideId: null), which returns false (not registered), startShare(''), and audio.start(rideId: 'ride_local'). It could also use a stale on-demand ride id.

**Suggested fix:** Pass the screen's ride id into WaitingNotesAndPin (rideId: _rideId) and use it for SafetyKitSheetRow.

### M36. Sign-out wipe deletes the recording index but leaves the previous rider's Safety audio files on disk

`lib/features/auth/application/user_data_wipe.dart:92` (found by r2-rider3)

**What happens:** Rider A records audio from the Safety Kit or a Ride check card during a trip, then signs out. Rider B signs in on the same phone. Rider A's .m4a files are still in the app's documents/safety_recordings folder (device backups and file-sharing tools can reach them), and the app can no longer list or delete them.

**Why:** UserDataWipe.run says it removes everything a rider left on this device. It removes `movera_safety_cache_v1`, which is the list of recordings, and resets the Safety mock. It never deletes the audio files themselves. NativeSafetyRecorder writes every Safety Kit and Ride check (RC5, 'saved only on this phone') recording to `<documents>/safety_recordings/<id>.m4a`. The only code that deletes a file is SafetyAudioService.delete, and it needs the AudioRecording entry that the wipe has just thrown away. After sign-out, or after another rider signs in (enterSessionAs -> run), the previous rider's cabin audio stays on the device for good, and nothing in the UI can reach it to remove it.

**Suggested fix:** In UserDataWipe.run, delete the safety_recordings directory (on native only), or delete every localPath found in the safety cache before removing the key.

### M37. Sign-out wipe leaves the rider's safety audio files on disk (Documents/safety_recordings) and drops their only index

`lib/features/auth/application/user_data_wipe.dart:135` (found by r2-rider3)

**What happens:** Rider A records a 4-minute Ride check audio during an incident and later signs out. Rider B signs in on the same phone. A's m4a files are still in the app's Documents/safety_recordings and no app flow will ever remove them.

**Why:** UserDataWipe promises 'Removes everything a rider left on this device'. Safety recordings are written by NativeSafetyRecorder to `<ApplicationDocuments>/safety_recordings/<id>.m4a` (safety_recorder_native.dart:26-33). Their metadata lives in `movera_safety_cache_v1.recordings`. The wipe removes that prefs key and resets SafetyController, but never deletes the files. Nothing else in the app deletes them either: `SafetyAudioService.delete` has no caller and no screen lists recordings. Every Ride check and Safety Kit recording therefore stays on the phone after sign-out, now unreferenced, and is available to whoever signs in next on the app's storage. On iOS the Documents directory is also included in device backups, contrary to 'saved only on this phone'.

**Suggested fix:** In UserDataWipe.run, delete the safety_recordings directory (and the files of any cached recordings). Consider storing recordings in a non-backed-up location (Application Support with excludeFromBackup).

### M38. OTP expiry is checked against the device clock, so a phone whose clock runs a few minutes fast can never sign in

`lib/features/auth/domain/otp_challenge.dart:21` (found by r2-rider4)

**What happens:** A laptop or phone with its clock set 6 minutes ahead opens Sign in. The rider types the correct code and gets 'This code has expired'. Resend gives the same result every time, so the rider cannot sign in.

**Why:** OtpChallenge.isExpired compares the server's absolute `expiresAt` (mock: now + 5 min) with `DateTime.now().toUtc()` on the device. PhoneVerification._verify returns 'code expired' locally when it is true, before any request, and AuthRepository.verifyOtp throws StateError in the same case. If the device clock is ahead by more than the OTP lifetime, every challenge, including each one from Resend, is already expired on arrival and the code is never sent. The server is the authority and would answer 410 itself. The client check can only block valid codes.

**Suggested fix:** Work out the expiry from the local receipt time plus the server's remaining lifetime (expiresAt minus the server's issue time, or a TTL field), or let the server's 410 decide.

### M39. A pasted international number (+46 …) at sign-in or Add phone is either rejected or, in the spaced form, cut short and accepted as a wrong number (+4646…) that the OTP is sent to

`lib/features/auth/presentation/auth_navigation.dart:993` (found by rider4)

**What happens:** Rider pastes their number from the clipboard/contacts in international format on Sign in or Add phone; Continue is refused with an "invalid" error.

**Why:** `AuthPhoneField` filters input to digits and spaces (auth_controls.dart:289-292), so a pasted `+46 70 123 45 67` becomes `46 70 123 45 67`. `swedishNumberFromField` then prefixes `+46` to anything not starting with `0` (993) giving `+4646701234567`; `toE164` sees 11 digits after +46 and returns null, so the screen shows "invalid Swedish mobile" for a valid number the rider pasted from Contacts.

**Suggested fix:** Strip a leading `46`/`0046` before prefixing, or pass the raw digits to `toE164` which already handles `46…`/`0046…` prefixes.

### M40. Leaving the code screen while Verify is in flight completes sign-in but leaves the rider on Sign in, and a new rider skips the name step

`lib/features/auth/presentation/phone_verify.dart:138` (found by r2-rider-r3)

**What happens:** A new rider types the 4-digit code, taps Verify, and on a slow connection taps the back chevron (or Android back) before the spinner stops. The server accepts the code. The app shows the Sign in phone form again, although a session now exists. Entering the number again sends another SMS. Killing and reopening the app lands on Home with no name, so drivers see an empty rider name.

**Why:** _verify() awaits `_auth.verifyOtp(...)`. AuthController.verifyOtp saves the session tokens, runs `_enterSession` (the user-data wipe for a different rider) and registers push. Only after that does the screen decide where to go. The Back button (`onBack: () => Navigator.of(context).maybePop()`, line 163) and Android system back are still enabled while `_submitting` is true; only the Verify button shows busy. If the rider goes back while the request is running, the widget is unmounted, so after a successful verify `if (!mounted) return;` (line 138) skips both `showMoveraRoot(RiderNameScreen…)` and `enterMoveraApp`. The SignIn screen's `await Navigator.push(...)` returns and resets `_busy`. The rider is now signed in, with tokens stored, but is looking at the Sign in form. RideRestoreCoordinator.resumeIfNeeded and the push primer never run. For a rider whose result had isNewRider = true, the name step is lost: on the next launch the stored session goes straight to Home with an empty name. That is the state the known 'reload skips name step' finding describes, here reached without any reload.

**Suggested fix:** Block pops while `_submitting` (PopScope canPop: !_submitting, and pass onBack: null while submitting). Or, once verifyOtp succeeds, navigate through the root navigator or moveraNavigatorKey even if this widget has been unmounted.

### M41. Sign-in Continue/Verify and the Apple/Google buttons expose no tap action to screen readers

`lib/features/auth/presentation/widgets/auth_controls.dart:26` (found by r2-rider1)

**What happens:** A TalkBack user focuses 'Continue' on Sign in after entering a number and double-taps. The node has no tap action, nothing happens and no code is requested, so the rider cannot sign in with a screen reader.

**Why:** AuthPrimaryButton and AuthProviderButton wrap their InkWell in `Semantics(button: true, enabled: ..., label: ..., excludeSemantics: true)` and pass no `onTap`. excludeSemantics drops the InkWell's semantics node, which is where the tap action lives. The resulting node is announced as a button but has no SemanticsAction.tap. On Android, TalkBack marks it as not clickable and double-tap does not activate it. Web semantics also gives it no click handler. These buttons are the only way through sign-in (Continue, Verify, Let's ride, Apple, Google).

**Suggested fix:** Pass `onTap: enabled ? onPressed : null` to the outer Semantics, or drop excludeSemantics and use MergeSemantics.

### M42. Names over 80 characters (40+1+40 at sign-up, or any length in Personal info) are rejected by the mock/proposed profile PATCH, and SyncedProfileRepository hides this permanent 422 as 'pending', so later consent and language syncs fail silently

`lib/features/auth/presentation/widgets/auth_controls.dart:377` (found by r2-rider1)

**What happens:** A new rider types a 40-character first name and a 40-character last name and taps Let's ride. PATCH {name: <81 chars>} returns 422 and the app enters normally. Later the rider turns off Offers in Privacy. That PATCH also returns 422 because it carries the same name. The server never learns the name or any consent change, and the rider is shown no error.

**Why:** AuthTextField caps each name field at 40 characters, and RiderNameScreen saves '$first $last'. That can be 81 characters. The Personal info editor (showAccountTextEditor) has no length limit at all. The profile contract and the in-process mock reject `name.trim().length > 80` with 422 invalid_profile. SyncedProfileRepository._sync catches every error the same way: it sets `_syncPending = true` and logs a warning. The UI therefore never says anything. Every later save resends the same over-long name, so every PATCH is rejected, including consent and language changes, and the 'resend' can never succeed.

**Suggested fix:** Validate the combined name against the server limit (80) in the sign-up and Personal info editors. Treat a 4xx validation answer as a user-facing error instead of as pending.

### M43. A booking that may have been created is not checked against the server before a retry gets a fresh key, so a retry books a second live ride

`lib/features/booking/application/booking_coordinator.dart:355` (found by r2-rider1)

**What happens:** Rider taps Book now. The POST reaches the server and creates ride R1, then the connection drops before the answer arrives. The replay and the active-trip lookup also fail offline, and the rider sees 'We couldn't confirm your booking. Check your connection and try again.' The network comes back after 5 minutes, and the rider taps Book now again (or after 10 seconds, with the pickup pin re-confirmed a few metres away). `_attemptFor` creates a new attempt with a new key, `POST /rides` creates R2, and Finding opens for R2. R1 is still searching on the server and can be matched with a second driver. Two rides are booked. Traced by hand through booking_coordinator.dart, booking_attempt.dart and the in-process mock.

**Why:** RC-09 accepts that a timeout, dropped connection or 5xx may still have created the ride. `_sendOrRecover` recovers only inside the same call (one replay plus `GET /rider/trips/active`), and when the network is down that recovery fails too. The rider is then told `bookingUncertain` ('Check your connection and try again'). The kept `BookingAttempt` is reused only when the next intent matches exactly and less than 5 minutes have passed since the first tap (`matches` uses `startedAt`). The intent includes pickup and destination rounded to 1e-4 degrees, so a pin a metre away across a cell edge, a GPS-preselected pickup that moved, or a retry after 5 minutes all produce a new `BookingAttempt` with a new idempotency key. Nothing calls `_adoptActiveTrip` or `fetchActive` before that new key is sent. The server has no one-live-trip rule (the mock `POST /rides` just creates another ride, and the contract defines none). So the ghost ride from the first attempt stays live on the server with no screen watching it, and a second ride is created.

**Suggested fix:** When the previous attempt ended 'maybe created' (an attempt with a replay that never succeeded or was refused), call `_adoptActiveTrip`/`fetchActive` before minting a new key for any intent, and adopt or block if the server already has a live trip. Alternatively keep the uncertain key until the server has been asked.

### M44. Swapping the last stop and the destination in Change route makes preview re-geocode both from text instead of using the booked coordinates

`lib/features/destination_search/presentation/route_picker_page.dart:320` (found by r2-rider3)

**What happens:** A live ride's destination was set by map pin, so its label is a street near the pin or 'Dropped pin · 59.32930° N ...', with exact coordinates. It has one stop. The rider taps the stop/destination swap: the old destination's label is forward-geocoded to a different point (in the demo, any unknown text gets a made-up hashed point), or is not found at all. The re-quote and the driver's route then use the wrong points.

**Why:** RoutePickerPage never receives the destination's point (`_destinationPoint` starts null), and stops never carry points. `RouteChangeController.preview` makes up for this by matching text: it uses `ride.destination*` when the destination text equals `ride.destinationAddress`, and a stop's coordinates when the text matches an entry in `ride.stops`. After `_swap` that matching fails. With stops, the old destination moves into the last stop (it is not in `ride.stops`), and the old stop becomes the destination (it is not equal to `ride.destinationAddress`). Without stops, the pickup becomes the old destination text with `_destinationPoint == null`. Every one of these is sent to `_locate(address)` instead of using the exact booked coordinates.

**Suggested fix:** Accept and track per-field points in the picker, including an initial destinationPoint and stop points, and swap them along with the text. Pass stopPoints to preview.

### M45. Back during the finish step does not cancel it: a date picker or route-change price sheet appears after the picker has closed

`lib/features/destination_search/presentation/route_picker_page.dart:390` (found by r2-rider3)

**What happens:** Change route on a live ride: pick a new destination, then press Android back while 'See new price' is loading. The picker closes, and a moment later the route-change price sheet appears over the ride screen. Confirming it changes the route, but the caller receives null, so the updated snapshot and refund notice are lost. On Home with Book for later, a date and time picker opens over Home after the rider backed out.

**Why:** While `_finishing` is true, the picker shows a full-screen overlay but has no PopScope, so system back, iOS swipe-back or browser back still pops it. `widget.onFinish` keeps running. In Home's `_confirmRouteSelection`, the `mounted` checks are Home's (Home stays mounted), so for Book for later `ScheduleDateTimeSelector.choose` opens over Home after the rider left Where to, and the chosen time is then dropped because `_finish` returns when `!mounted`. In `openRouteChange`, `RouteChangeSheet.confirm(context, ...)` uses the ride screen's context, so the price sheet still opens. If the rider confirms, `changes.apply` changes the live route and credits the wallet. But the route already completed with null, so `openRouteChange` returns null and `lastRefundDestination` is never set.

**Suggested fix:** Wrap the page in `PopScope(canPop: !_finishing)`, or make onFinish cancellable and check the picker route is still current before opening follow-up UI.

### M46. Choose-on-map passes the shortened or translated pickup field text, so Home treats the GPS or placeholder label as typed and geocodes it instead of opening at GPS

`lib/features/destination_search/presentation/route_picker_page.dart:440` (found by r2-rider3)

**What happens:** First case: an English rider with a GPS pickup whose label is a long geocoder address taps the map badge. The picker opens at the forward-geocode of the short label instead of at GPS, and does not take a fresh fix. In the in-process demo the mock geocoder hashes unknown text to a made-up point near central Stockholm. Second case: a Swedish rider with location off ('Platsen är avstängd, ange upphämtning') taps it. The picker opens at a geocoded point with Confirm already enabled, contrary to D-002.

**Why:** The pickup field shows _show(widget.pickupAddress), which is compactAddress(...). That function both shortens the geocoder address and runs L10n.place, which translates 'Current location' and 'Location off, set pickup'. _finish undoes this with _expand(...), but _pickOnMap passes the raw display text. Home._openPickupMapPicker decides 'typedByRider' by comparing that text with the stored English, full _pickupAddress. The comparison fails, so Home forward-geocodes it (U6 says only text the rider typed may be geocoded). It also skips the fresh-fix refresh (refreshCurrentLocation: chosen == null). In fr/sv the translated location-off label is not recognised as a placeholder, so chosen becomes the geocoder's hit and positionIsFallback becomes false.

**Suggested fix:** Pass _expand(_activeController.text) (and the current _pickupPoint) to onPickOnMap. In Home, open at the picker's known point when one is given.

### M47. Pressing Enter picks the first result of an older query still on screen and goes straight to booking

`lib/features/destination_search/presentation/route_picker_page.dart:511` (found by r2-rider3)

**What happens:** The rider types 'Kungsgatan' and suggestions arrive, then keeps typing ' 44' and presses Enter before the request for 'Kungsgatan 44' returns. `_results.first` is still the 'Kungsgatan' list's first entry (for example 'Kungsgatan 1'), and it is booked as the destination.

**Why:** `_onTyped` leaves `_results` in place while a new query is in flight; it only clears them when the field is empty. `onSubmitted` then chooses `_results.first`, which can belong to an earlier, shorter query. `_choose` on the destination field calls `_finish` immediately, so the rider moves on to Select ride with a destination they did not type. `_results.first` can also be a row that `_whileTyping` hides behind a recent match, so Enter may pick a different place from the first row the rider sees.

**Suggested fix:** Store the query that `_results` belongs to and only accept Enter when it equals the current text, or clear `_results` when the text changes. Pick the first row actually displayed.

### M48. Re-dispatch after a driver drop restores the offer ceiling from the booking-time RideSession copy, discarding the ceiling a route change set

`lib/features/finding_driver/application/finding_driver_controller.dart:277` (found by r2-rider2)

**What happens:** Booked at 200 kr, so the server and client ceiling is 1.8 x 200 = 360 kr (36000 öre). On Waiting the rider changes the destination and the price becomes 300 kr. The server ceiling becomes 540 kr and the stored snapshot gets 54000. The driver then cancels. Finding resumes at 300 kr with maxOfferMinor 36000, so maxOfferPrice is 360. Raising by 100 kr (to 400 kr) returns false client-side, although the server allows up to 540. In the opposite case (route lowered to 100 kr, server ceiling 180 kr), the client still allows +150 kr (250 kr). The server refuses with 409 offer_above_maximum and the rider sees 'couldn't update offer'. About 90 s later the delayed-search save overwrites the stored 54000 with 36000. Worked by hand from the code; not run.

**Why:** The offer ceiling (ARCH-20) exists in two places: `RideSnapshot.maxOfferMinor` (in the store and in Finding's `_snapshot`) and `RideSession.bookedMaxOfferMinor`. Only booking and restore write `bookedMaxOfferMinor`. A route change sets a new ceiling: the mock server recomputes it, and `RouteChangeController.apply` saves `maxOfferMinor: serverMax` into the stored snapshot. The session copy is left at the booking value. When the driver drops the ride on Waiting, Waiting pops to Finding. `_resumeFindingAfterDriverCancel` adopts the stored route and price, then calls `_startMatching` -> `startFrom`. `startFrom` builds a new snapshot whose ceiling is `session.bookedMaxOfferMinor`, the stale booking-time value. `maxOfferPrice` and `confirmPriceIncreaseBy` then use the wrong ceiling. `_evaluatePhase` and `_persistAssigned` later write it back over the store's correct value, so even a reload keeps it.

**Suggested fix:** Make the snapshot the only owner of the ceiling. In _resumeFindingAfterDriverCancel, pass the stored snapshot's maxOfferMinor (and categoryId/paymentMethodId) into startFrom. Alternatively, have RouteChangeController.apply (it already has the session) update `bookedMaxOfferMinor` too.

### M49. Finding treats a driver drop (cancelledByDriver) that arrives while a match is deferred as the end of the ride: it archives the ride as cancelled, clears the snapshot and sends the rider Home while the server trip is searching again

`lib/features/finding_driver/application/finding_driver_controller.dart:394` (found by rider4)

**What happens:** Rider raises the offer; while the PATCH is out a driver accepts and immediately drops the ride. The next poll delivers `cancelledByDriver` to Finding: the ride is filed in History as cancelled, the snapshot is cleared and the rider is sent Home, although the server trip is still searching and may be accepted by another driver.

**Why:** `RideStatus.cancelledByDriver` is in `isTerminal` only so the UI stops tracking the old driver; the trip itself is back in `searching` (core/contracts/ride_status.dart 31-36, trip_status.dart 134). Waiting handles it as a reversible re-dispatch, but the Finding listener does `if (event.status.isTerminal) { unawaited(_completeTerminal(event.status)); return; }` (394-397), and `_completeTerminal` archives `cancelledByDriver` to History as a cancelled ride (1027-1035), clears the snapshot and fires `_onTerminal`, which shows the 'Driver cancelled … Continue' sheet and `RideNavigator.home` (finding_drivers.dart 330-334). The event is reachable while Finding is still the subscriber: `ApiRideRealtime` maps a matched→searching projection to `cancelledByDriver` (api_ride_realtime.dart 193-199), and Finding stays subscribed after an accept whenever `_completeAssigned` is deferred (`_assignmentPending` because an offer raise/pickup edit or a cancel is in flight, 939-945) or during the `_persistAssigned` await before `_openWaiting` disposes the controller.

**Suggested fix:** In the Finding listener treat `cancelledByDriver` as 'back to searching' (reset `_assigned`/`_assignmentPending`, keep the search) instead of routing it to `_completeTerminal`.

### M50. Price raise the server accepted is thrown away and reported as failed when the rider taps Cancel during the PATCH; the fare shown stays the old one

`lib/features/finding_driver/application/finding_driver_controller.dart:833` (found by r2-rider2)

**What happens:** After 45 s the rider taps +20 kr. While the PATCH is in flight they hit X → Cancel request. The server applies the raise (279 kr). The cancel comes back 409 (version changed / driver accepted). Finding says the offer failed and keeps showing 259 kr, Waiting and History show 259 kr, and the rider is charged 279 kr. If they raise again (+20), the server makes it 299 kr while the button previewed 279 kr.

**Why:** `cancelSearch` does not check `_editInFlight`. It just bumps `_editEpoch` (line 1102), and the Cancel X stays tappable while the price-bump card is busy. When the raise PATCH response then arrives, `ride.observeProjection(response)` records the new version, but `_editInvalid(editToken)` is true, so the method returns false before `_snapshot` or the store is updated and before `_bumpDismissed`/`offerConfirmation` are set. `_raiseOffer` then shows `editFeedback ?? editOfferFailed`, and `editFeedback` was reset to null, so the rider sees "couldn't update your offer". If the cancel does not commit (409 driver accepted, or `stale` because the raise bumped the version), the search goes on with the pre-raise price: the card shows again, `_persistAssigned` saves the old price, and Waiting gets `price: _match.currentPrice` (old). A second raise is computed from the old fare while the server adds it on top of the already-raised fare.

**Suggested fix:** When the PATCH succeeded, apply the server fare to `_snapshot` (and the store) even if a cancel started meanwhile, unless the cancel committed. Or make `cancelSearch` wait for / refuse while `_editInFlight`, and disable the X while an edit is busy.

### M51. Cold-start/reconnect outbox flush moves a cancel queued during search onto the accepted trip's version and replays it, cancelling the matched ride and charging the live cancel fee (contradicts RC-03 'match overtakes queued cancel')

`lib/features/finding_driver/application/finding_driver_controller.dart:1559` (found by r2-rider2)

**What happens:** The rider taps Cancel while searching with no signal and gets 'Cancelling…' (queued, free). They close the app. A driver accepts at 12:00 and drives toward the pickup. At 12:06 the rider reopens the app. The restore flush re-reads `accepted`/`driver_to_pickup`, the state machine allows `cancel`, and the cancel is posted. The server cancels the trip and stores a 35 kr live cancel fee, for a cancel the rider made while it was free.

**Why:** `_completeAssigned` says a match that overtakes a queued cancel removes it 'so it cannot cancel the matched ride later' (lines 947-959), and tells the rider 'driver already accepted'. But the flush (`_flushPendingCancels` / `_rereadForReplay`) re-reads the trip and replays the cancel whenever `TripStateMachine.apply(status, 'cancel', rider)` allows it. Rider cancel is allowed from accepted, driver_to_pickup and arrived. The flush also moves the entry onto the current version (`forVersion`), which removes the version check that would have refused it. On cold start `_dropIfCancelQueued` flushes before any screen exists. On reconnect the flush runs in parallel with the realtime match. Either way the cancel reaches the server for an accepted trip. The mock then charges `_riderCancelFee` counted from acceptedAt.

**Suggested fix:** When replaying a `cancel` queued during search, drop it as stale once the trip is past searching/offered (accepted or later), or send the version from when it was queued. Report it as refused/stale so the rider decides again with the fee shown.

### M52. "Try again" after no driver found leaves the screen poppable while the new booking is created, orphaning a live search

`lib/features/finding_driver/presentation/finding_drivers.dart:340` (found by r2-rider4)

**What happens:** No driver found → the rider taps Try again, sees nothing change for a second and swipes back. Finding pops to Select Ride/Home. The server has a new searching ride with the stored snapshot, but no screen shows it. A driver can accept it unseen. If the rider books again from Select Ride, `_findingAlreadyActive` is false, so a second live ride is created.

**Why:** `_handleTerminal` sets `_leaving = true` (line 323) before showing the no-driver sheet. On Try again, `_requestAgain` awaits `submitFinding` (a quote plus POST /rides, two round trips) and only resets `_leaving = false` after success (line 380). The screen's `PopScope(canPop: _leaving)` therefore lets a system back / swipe pop Finding during the request, and the X is inert (`_confirmCancel` returns on `_leaving`). The booking still creates the server ride and saves its snapshot (BookingCoordinator._submitFinding), but `_requestAgain` sees `!mounted` and returns false. No Finding owns the new live ride, `FindingDriverController.active` is null (cleared by `_completeTerminal`), and nothing navigates to it until a later lifecycle resume/reload restore.

**Suggested fix:** Set `_leaving = false` (or keep a separate rebooking flag that keeps canPop false and shows progress) while `_requestAgain` is in flight. If the widget unmounted after the ride was created, hand the ride to `RideRestoreCoordinator.recoverCreatedFinding`.

### M53. 'Try again' after no driver found reports a may-have-booked failure as a plain failure and sends the rider Home while the new ride may exist

`lib/features/finding_driver/presentation/finding_drivers.dart:370` (found by r2-rider4)

**What happens:** The search ends with no driver found and the rider taps Try again. The POST /rides creates the ride but the connection drops before the answer. The replay and adopt fail, and the rider sees 'We couldn't request a new ride. Choose your route and try again.' and lands on Home. The server ride keeps searching, may be matched with a driver who comes to an empty pickup, or the rider books again and has two rides. Traced by reading the code.

**Why:** `_requestAgain` catches every error with `rebookFailed` ('We couldn't request a new ride. Choose your route and try again.') and returns false, and `_handleTerminal` then goes Home. It never checks `BookingController.mayHaveBooked(error)`, which Select Ride uses (RC-09) for exactly this case. A timeout or dropped connection after the POST may have created the ride. The rider is told it failed and is told to rebook from Home, so the ghost ride stays live with no screen. If the rider rebooks with any different intent, that books a second ride (see the BookingAttempt finding).

**Suggested fix:** When `BookingController.mayHaveBooked(error)` is true, show `bookingUncertain`, stay on the screen, and try `fetchActive` to adopt the ride (or offer Retry, which reuses the same attempt) instead of sending the rider Home.

### M54. After location is revoked and then allowed again, Home never restarts live tracking; the puck freezes while the state says 'live'

`lib/features/home/application/home_controller.dart:478` (found by r2-rider3)

**What happens:** On iOS, Home is showing the rider's position. The rider switches location to 'Never' in Settings: the stream errors and Home shows 'location denied'. The rider then sets 'While using' and comes back. Home shows one fresh fix and the notice clears, but as the rider walks the blue puck and 'Current location' pickup no longer move. Bookings start from the stale point until Home is rebuilt.

**Why:** When the position stream errors with PermissionDeniedException, startTracking cancels the subscription, sets permissionRequired and returns without arranging a resubscribe. When the rider allows location again and returns to the app, Home.didChangeAppLifecycleState calls resumeLiveUpdates(). That only asks for one fix (_refreshAfterResume -> latestFix) and sets the state to live. The resume handler restarts tracking only for `temporarilyUnavailable` (recoverLiveLocation) or when `_currentLatLng == null` (a fresh detect). A rider who had a fix before the revoke matches neither branch. The stream is never subscribed again, so the puck and the pickup label stop following the rider, although the location notice has cleared.

**Suggested fix:** On resume, when the controller has no active _positionSub and permission is granted, call startTracking again (for example through recoverLiveLocation), not only for temporarilyUnavailable.

### M55. Home puck pulse on web creates a never-revoked blob URL every 850 ms while Home is open

`lib/features/home/application/home_controller.dart:642` (found by r2-rider3)

**What happens:** A rider leaves the web app open on Home (for example, an installed PWA on iPhone left in the foreground) with location granted. Worked by hand: 3600/0.85 = about 4,235 pulse swaps/hour plus one per GPS fix, each a new Blob of the 65x75 puck PNG (a few KB). That is about 10-20 MB/hour that is never freed, plus one Google Maps icon decode each time. Over a long session this adds to the WebGL map's memory and raises the risk of iOS Safari killing the tab. Not run; traced by reading the code and the plugin source.

**Why:** startPulse flips pulseExpanded every 850 ms and calls onTick, which is Home's _updateLocationVisuals. On web that runs _paintWebPuck (home.dart:1588-1601). It swaps the puck icon between the cached 'expanded' and 'compact' rotated BitmapDescriptors, both BitmapDescriptor.bytes (home.dart:1562). paintUserPuck sees a non-identical icon and publishes a new marker Set (home_controller.dart:702-713). google_maps_flutter_web then runs _changeMarker for the puck, and urlFromMapBitmap makes a fresh `URL.createObjectURL(Blob(png))` each time, because its cache is cleared after every batch and the URL is never revoked. Every GPS fix (a position change) does the same. RotatedPuckCache (U7) only avoids re-rasterising in Dart. Each icon swap still allocates a new Blob in the browser that lives until the page unloads. The pulse runs for as long as Home is the current route and the camera is still, which is the app's idle state.

**Suggested fix:** On web, draw the pulse without swapping marker bitmaps, for example with a Circle overlay whose radius alternates, or with asset-backed icons. Another option is to keep one icon and stop pulsing on web. Do not send BytesMapBitmap icon changes at timer cadence.

### M56. Home's load() keeps only the first 8 custom places and every Home persist() writes that cut list back, so places 9 and later are deleted from storage

`lib/features/home/application/home_places_controller.dart:69` (found by rider3)

**What happens:** Rider adds nine custom places in Menu > Saved places. They book a ride from Home; _persistAddressData runs and the ninth place disappears from Saved places permanently.

**Why:** HomePlacesController.load() maps `saved.places ... .take(maxCustom)` (8) into savedPlaces, and persist() writes `places: savedPlaces.map((place) => place.toJson()).toList()` to the shared HomeAddressRepository keys. SavedPlacesController.save() has no cap and appends freely (saved_places_controller.dart:98-99). Home persists on every booking/route change (_showRouteAddressPicker -> _persistAddressData, home.dart:1003) and after any saved-place edit, so the first Home persist after a 9th place exists removes places 9+ from storage for good. Reproduced: 9 stored places -> load gives 8 -> persist stores 8 (test output `loaded 8 of 9`, `stored after persist: 8`).

**Suggested fix:** Either enforce the same cap in SavedPlacesController.save, or keep the untruncated list (or re-read storage) when Home persists so it never writes fewer places than are stored.

### M57. Custom saved places are matched by type: editing or adding a second place of the same kind overwrites the first

`lib/features/home/application/home_places_controller.dart:133` (found by rider3)

**What happens:** Rider has 'Gym A' and 'Gym B' saved from Saved Places. On Home they long-press the Gym B card and enter a new address: Gym A's address is replaced, Gym B is unchanged, and the change is persisted. Likewise 'Add place > Gym' with an existing gym silently overwrites it.

**Why:** Saved Places (SavedPlacesController.save, FLOW-5) deliberately allows several custom places of the same kind, each with its own id (saved_places_controller.dart:84-102). Home's edit path ignores ids: SavedPlacesRow long-press passes only `place.type` (saved_places_row.dart:108-110), _editSavedPlace -> _showAddressPicker(target:'custom', customType) -> _saveAddressFor -> applyResolved, which does `savedPlaces.indexWhere((place) => place.type == type)` and rewrites that first match. Home's Add place picker (home.dart:1359-1461) has the same effect: choosing a type that already exists replaces that place's address instead of adding one. Reproduced with a throwaway test: two gyms (ids a,b); applyResolved(custom, 'New street 9', 'gym') changed a to 'New street 9' and left b untouched (output: `after edit: [a:New street 9, b:Street B 2]`).

**Suggested fix:** Pass the SavedPlaceData id (or index) through onEditSavedPlace/_showAddressPicker/applyResolved and match on id; for Add place with an existing type, append a new entry (as Saved Places does) or ask.

### M58. After signing back in mid-ride on web, Home says 'Your ride search was interrupted. Book again' while the kept ride is being resumed

`lib/features/home/presentation/home.dart:191` (found by r2-rider4)

**What happens:** Web staging: the rider's refresh token expires while a driver is on the way, and Sign in is shown with the ride kept. The rider signs in and lands on Home with the toast 'Your ride search was interrupted. Book again when you are ready.' A moment later the Waiting screen for the same ride appears under the same toast. The rider may book a second ride or think the trip was lost. Traced by reading the code; not run.

**Why:** Whether a ride is live is recorded twice on web: in `RideSnapshotStore` and in a sessionStorage flag (`movera_search_live`). Every `RideSnapshotStore.save` sets the flag (`markSearchLive`). Only `RideRestoreCoordinator.goHome` and the sign-out wipe clear it; `RideSnapshotStore.clear()` does not. Home's initState treats a set flag as proof the search was dropped. Its comment still assumes the old document-load wipe ('the web build's snapshot is gone before Flutter starts'), which R-web removed. When a session expires mid-ride (staging/production, authRequired), `onSessionExpired` deliberately keeps the snapshot and roots Sign in. After the rider signs back in, `enterMoveraApp` mounts Home first, and Home takes the flag and posts the 8-second toast. Only then does `resumeIfNeeded` (which awaits the session check, the snapshot read and a network resync) swap the root to the live Finding/Waiting screen. The SnackBar lives in the root ScaffoldMessenger, so it is still showing on the ride screen. The same mismatch occurs when `_dropIfCancelQueued` ends a ride on reload: it clears the store without clearing the flag, so Home claims the search was interrupted although the rider's own cancel went through.

**Suggested fix:** Derive the notice from the snapshot store, not a second flag. Call clearSearchLive() inside RideSnapshotStore.clear(). Have Home skip the notice while `RideSnapshotStore.read()` still returns a fresh live ride, or announce only after the restore decision (the first root/resumeIfNeeded result) says the ride was dropped.

### M59. Resume-recovery after a failed first fix tracks GPS but never draws the puck, never moves the camera and keeps 'Location off, set pickup'

`lib/features/home/presentation/home.dart:257` (found by r2-rider4)

**What happens:** On the web, the first GPS fix takes longer than 16 s (indoors), then the rider switches tabs and comes back. The location stream now delivers fixes and the recenter button appears, but no rider puck is ever painted. The map stays on central Stockholm, and the pickup still reads 'Location off, set pickup' although location works.

**Why:** If the first detectCurrent() throws (the 16 s detectFixTimeout or a platform error), the controller state is temporarilyUnavailable and _runDetectCurrentAddress returns after setting _pickupAddress = locationOffPickupLabel. It never reaches _prepareLocationPuckIcons, bindLiveLocation or the camera move. On the next app resume Home calls _locationCtl.recoverLiveLocation(...), which only starts the position stream. Its onFix sets _currentLatLng and calls _updateLocationVisuals(), which returns early because _locationPuckCompact/_locationPuckExpanded are still null. _refreshPickupLabelIfMoved sees _pickupLabelAt == null, stores the fix and returns, so the label stays 'Location off, set pickup'. The pulse and compass are never started and the camera stays on the default Stockholm view.

**Suggested fix:** On a recovered first fix, run the same first-fix work as _runDetectCurrentAddress: prepare the puck icons, bind pulse and heading, set the pickup label/_pickupLabelAt and do a follow camera move. Or simply call _detectCurrentAddress() when no fix has ever been bound.

### M60. When the first GPS fix on Home times out, no position stream starts, no notice or retry is shown, and the puck stays missing until the app is resumed or a booking starts

`lib/features/home/presentation/home.dart:365` (found by r2-rider4)

**What happens:** An Android rider opens the app indoors with location permitted and services on. The high-accuracy cold fix takes longer than 16 s. Home keeps the default map with no puck and the pickup label 'Location off, set pickup', and offers no retry. The puck never appears while the rider stays on Home, even after the GPS gets a fix seconds later, until the app is backgrounded or the rider starts a booking.

**Why:** HomeLocationController.detectCurrent times out after 16 s (detectFixTimeout). It then catches the error, sets state temporarilyUnavailable and returns target null (home_controller.dart:438-446). _runDetectCurrentAddress then writes the 'Location off, set pickup' label and returns, so bindLiveLocation/startTracking never runs and no position stream exists. accessIssue maps only servicesDisabled and permissionRequired to a notice, so temporarilyUnavailable shows no notice and no Try again button. Nothing schedules a retry. The only recovery is an app pause/resume (didChangeAppLifecycleState → recoverLiveLocation) or a booking action that calls _awaitCurrentFix.

**Suggested fix:** On an 'unavailable' result, start the position stream anyway (startTracking has its own resubscribe backoff), or schedule detectCurrent again. Do not label a timeout as 'Location off'.

### M61. Late first GPS fix glides whichever map is on top (pickup / Set pickup / Select ride), not Home's

`lib/features/home/presentation/home.dart:395` (found by rider1)

**What happens:** Cold start on web/Safari, slow first fix. Rider taps Where to, picks a destination; _awaitCurrentFix times out at 8 s, SelectRide opens, rider taps Book, Set pickup opens with the fallback pin. At ~12 s the fix lands: Set pickup's camera glides to the GPS point at city zoom 11.7; onCameraMove recomputes _center, _onCameraIdle sets _routeStart/_usable=true, re-resolves the address and re-quotes. The pickup silently moved under the rider; in ConfirmPickupSpot the pin likewise jumps and the shown address changes.

**Why:** _runDetectCurrentAddress ends with `AppScope.instance.maps.animateCamera(target, zoom: homeOpeningZoom, follow: true)` with no check that Home's map is the active owner. While Home is parked (NAV-3 or _withParkedHomeMap) its controller is detached (home.dart:233) and GoogleMapProvider.controller returns `_owners.last.controller` (google_map_provider.dart:24-25), i.e. the map of ConfirmPickupSpot (owner 'pickup', confirm_pickup_spot.dart:333), SetPickupPage (set_pickup_page.dart:870) or SelectRide. _mayMove(map, follow:true) only checks heldByRider (google_map_provider.dart:79-85), so the booking screen's camera eases to the rider's GPS point at zoom 11.7. The sibling path _centerCameraOnQuickFix explicitly guards `if (maps.activeOwner != MapOwners.home) return;` (home.dart:312), showing this guard was intended. detectCurrent can take up to 16 s (detectFixTimeout) while _awaitCurrentFix gives up after 8 s and the flow continues with the fallback pickup, so the fix routinely lands after the rider is on a map screen.

**Suggested fix:** In _runDetectCurrentAddress skip the animateCamera when `_mapParked.value || AppScope.instance.maps.activeOwner != MapOwners.home` (onMapCreated already re-centres from _currentLatLng when Home's map comes back).

### M62. Tapping a saved place prices and books the previous route's stops, which the rider never added in this flow

`lib/features/home/presentation/home.dart:595` (found by r2-rider4)

**What happens:** The rider plans Home -> stop 'Odenplan' -> 'Arlanda', looks at the prices and backs out to Home. Later they tap the 'Work' chip. SelectRide quotes Work via Odenplan (an extra stop and detour in the price), and Set pickup shows 'via Odenplan'. If they book, the trip carries a stop they never asked for.

**Why:** _useSavedPlaceAsDestination opens SelectRide with stops: List<String>.from(_routeStops). _routeStops is whatever the last Where to flow left. It is cleared in _withParkedHomeMap only when a ride changed and reached a terminal or completed state, and nothing clears it when the rider backs out of SelectRide without booking. SelectRide quotes include the stops (select_ride.dart:466-471, 'Quotes include the stops'), and Set pickup shows 'via ...'. So a one-tap saved-place booking silently carries stops from an earlier abandoned route.

**Suggested fix:** A saved-place destination starts a new route: pass const [] (or clear _routeStops) in _useSavedPlaceAsDestination. Also clear _routeStops when a flow ends without a booking.

### M63. A failed forward geocode after the route picker closes, or when a saved place is tapped, aborts the flow silently with an unhandled async error

`lib/features/home/presentation/home.dart:953` (found by rider1)

**What happens:** Rider is offline or the geocode endpoint times out. They pick pickup and destination in the route picker (onFinish succeeds because resolvePlace is cached or the point came with the suggestion), the picker closes, the forward geocode of the raw strings throws, the flow aborts: Home shows the old sheet, no error, no SelectRide, Recents not updated. Tapping a saved place (Home/Work card) while offline likewise does nothing.

**Why:** After RoutePickerPage pops with a draft, _showRouteAddressPicker runs `Future.wait([_normaliseAddress(rawPickup...), _normaliseAddress(rawDestination...), ...])`. HomeLocationController.normaliseAddress calls `geocoding.forward(clean)` with no try/catch (home_controller.dart:258); AppGeocoding._forwardFromApi does `api.post(...).timeout(requestTimeout)` and ApiClient._send throws ApiError on HTTP >= 400, NETWORK and TIMEOUT (api_client.dart:98, 123, 131). The exception propagates through _handleDestinationTap -> _runRouteFlow (finally only resets the flag) -> WhereToCard.onTap, which is a VoidCallback, so it becomes an unhandled zone error. Nothing is shown to the rider, nothing is persisted and SelectRide never opens. The picker itself catches onFinish failures (route_picker_page.dart:408-411) but this post-pop step does not. Same unguarded pattern: _useSavedPlaceAsDestination (home.dart:545), _saveAddressFor (home.dart:469, 477), PickupMapController.search used by ConfirmPickupSpot._lookup (confirm_pickup_spot.dart:286) and SetPickupPage._searchAddress (set_pickup_page.dart:702).

**Suggested fix:** Wrap the post-pop normalisation (and the saved-place / favourite / pickup-search paths) in try/catch; on failure fall back to the raw strings (the draft already carries pickupLat/Lng and destinationLat/Lng) or show homeChooseValidRoute / routeCouldNotReach, instead of letting the exception escape.

### M64. Save Home/Work address sheet adds the keyboard inset a second time, overflows, and its buttons stop taking taps once the keyboard opens

`lib/features/home/presentation/home.dart:1100` (found by r2-rider4)

**What happens:** Native iPhone 390x844 with a 336 px keyboard: sheet content max = 844 - 2*336 = 172, minus the Container's ~32 px padding leaves 140 px. The fixed content (handle, title row with close button 48, field ~50, 'Use current location' row ~56, spacers) needs about 197 px. Typing a query adds 'Use this address' (+62). The Column overflows by 57-119 px. The parts outside the Column are painted but not hit-tested (RenderBox.hitTest checks size), so 'Use current location' and 'Use this address' cannot be tapped. The sheet is pushed up to y=0 under the status bar, with a transparent keyboard-height band below it. On a 360x640 Android phone (Android Chrome web reports the keyboard as viewInsets too), only about 9 px is left.

**Why:** MoveraSheet.show already wraps every builder in `Padding(bottom: MediaQuery.viewInsetsOf(ctx).bottom)` (movera_sheet.dart:36-41). MoveraModalSheetRoute uses `SheetViewport(child: child)` with zero padding, and smooth_sheets 1.2 does not consume viewInsets (viewport.dart:225-240 asks the caller to pad), so the builder still sees the full keyboard inset. _showAddressPicker pads by `MediaQuery.of(context).viewInsets.bottom` again, so the content area shrinks by twice the keyboard height. The TextField has autofocus, so this happens as soon as the sheet opens.

**Suggested fix:** Remove the inner viewInsets Padding (MoveraSheet already applies it), and make the sheet body scrollable.

### M65. 'Use current location' row saves the placeholder 'Location off, set pickup' as Home/Work and into Recents

`lib/features/home/presentation/home.dart:1211` (found by rider1)

**What happens:** Location services off. Rider long-presses the Home card, sees 'Use current location' with subtitle 'Location off, set pickup', taps it: Home address becomes 'Location off, set pickup', it shows on the Home card and in Recents, and tapping the Home card later feeds that text to the geocoder as a destination.

**Why:** When location is off/denied, _runDetectCurrentAddress and _resetPickupLabel set _pickupAddress = locationOffPickupLabel. _placeOrNull only filters '' and 'Current location' (home.dart:524-528), so in _showAddressPicker the 'Use current location' row is enabled and pops that placeholder string; _saveAddressFor normalises it and applyResolved stores it as homeAddress/workAddress and calls remember(address), whose own filter also only knows 'Current location' (home_places_controller.dart:86). Home's _rememberAddress guard (isPlaceholderPickupLabel, home.dart:449) is bypassed on this path. Reproduced: applyResolved(target:'home', address: locationOffPickupLabel) -> `home=Location off, set pickup recents=[Location off, set pickup]`.

**Suggested fix:** Use isPlaceholderPickupLabel (and isUnusablePickupLabel) in _placeOrNull / the row's enabled check, and have HomePlacesController.remember reject placeholder and raw-coordinate labels like Home._rememberAddress does.

### M66. Home "Your month" card now counts trips whose payment failed as rides and money spent

`lib/features/home/presentation/widgets/home_journey_section.dart:74` (found by r2-rider-fixrev)

**What happens:** In a release build, the rider finishes a 250 SEK trip and the card charge fails (server: status completed, paymentStatus failed). Home's "Your month" card shows one more ride and 250 SEK more spent, while History labels the same trip "Payment failed".

**Why:** R2 (rider-37) changed OnDemandRideHistoryStore._reservationStatus so that RideStatus.paymentFailed maps to ReservationStatus.completed, with only a paymentFailed flag to tell it apart. MonthRideStats.fromRides filters on `ride.status.isCompleted` alone and adds `ride.price` to the month's spend. It never looks at `ride.paymentFailed`. In release, ApiRideHistoryRepository._record -> recordFor(terminalStatus: snapshot.status), and a server trip with paymentStatus failed becomes RideStatus.paymentFailed (trip_status.dart _afterCompletion). Before the change recordFor returned null for these trips, so they never reached the card. Now HomeJourneySection.defaultRides -> OnDemandHistoryController().load() returns them, and the card adds an amount the rider was never charged.

**Suggested fix:** In MonthRideStats.fromRides, skip `ride.paymentFailed` (or at least leave it out of `spent`), and add a test for it.

### M67. Pickup 'My location' / 'Use current location' has no Dart-side timeout; on the web it can hang for about 4 hours (D-003)

`lib/features/pickup/application/pickup_controller.dart:97` (found by r2-rider1)

**What happens:** On the web demo, the rider taps the My location button on Set pickup where the browser cannot get a high-accuracy fix (indoors, desktop). Nothing happens: no glide, and no 'location unavailable' snackbar, because the failure branch is never reached. A later answer (if any) glides the pin away from wherever the rider has put it since.

**Why:** geolocator_web 4.1.4 passes timeLimit.inMicroseconds as the JS geolocation timeout (html_geolocation_manager.dart:36), so the 15 s limit becomes about 4.2 h. The code records this as D-003 and requires an explicit Dart-side .timeout wherever getCurrentPosition is used (home_controller.dart:393-403, 614-622). PickupMapController.currentPosition calls location.getCurrentPosition with only timeLimit, and LocationRepository adds no timeout. SetPickupPage._useCurrentLocation (line 631) and ConfirmPickupSpot._useCurrentLocation (line 241) await it directly; only _refreshCurrentFix wraps it in .timeout(10 s).

**Suggested fix:** Add .timeout(...) inside PickupMapController.currentPosition (mapped to PickupLocationFailure.unavailable), and drop a late result when the pin has moved since the tap.

### M68. Confirm pickup spot (Home prefill, Schedule ride, Change route) can confirm the new pin point under the previous spot's address while the pin moves or its reverse lookup is pending

`lib/features/pickup/presentation/confirm_pickup_spot.dart:300` (found by r2-rider2)

**What happens:** On Where to, the rider uses 'Set pickup on map', drags the pin two blocks and taps Confirm before the reverse geocode returns (up to the 8 s request timeout). The route picker gets the new coordinates labelled with the old street, and that label is what the pickup shows from then on.

**Why:** onCameraMove sets _center on every frame, but _address is only replaced when _idle's reverse lookup answers. _confirmPosition has no _moving check and no 'address is stale' state. It pops ConfirmPickupResult(position: _center, address: confirmedPickupAddress(_address, ...)), where _address still names wherever the pin was before. This differs from the known _idle finding, which is about a superseded null overwriting the label: here no lookup has answered at all.

**Suggested fix:** Mark the address stale on onCameraMove. On confirm with a stale address, use droppedPinPickupAddress(_center) or wait briefly for the lookup, as SetPickupPage does.

### M69. Pickup address search sheet floats a full keyboard height above the keyboard and overflows on short phones

`lib/features/pickup/presentation/set_pickup_page.dart:663` (found by r2-rider3)

**What happens:** 360x640 Android (native, or Chrome where Flutter web reports the keyboard in viewInsets), keyboard about 280 px: the Container gets 640 - 560 = 80 px for 141 px of content (padding 42, title ~25, 12, field ~56). The field overflows the Column, and the part below 80 px is outside the hit area. On 390x844 iOS the sheet fits but hangs in mid-screen with a 336 px see-through gap above the keyboard.

**Why:** _searchAddress pads the sheet body with `MediaQuery.viewInsetsOf(sheetContext).bottom` even though MoveraSheet.show already does, and the TextField autofocuses. The sheet is lifted by twice the keyboard height. The area between the sheet and the keyboard is transparent (it is part of the sheet, so a tap there falls through to the barrier and dismisses it).

**Suggested fix:** Remove the extra viewInsets Padding.

### M70. Confirm tapped while the map is still gliding books the new pin point with the previous street and the previous fare

`lib/features/pickup/presentation/set_pickup_page.dart:754` (found by r2-rider3)

**What happens:** The rider flings the map 400 m up the street and taps 'Confirm and search' while it is still sliding. The ride is booked at the new point but labelled with the original street ('Drottninggatan 5'), and SetPickupResult.fareTotalKr is the old pin's price. The driver is sent to the wrong-named address and the price-change check compares against the wrong total.

**Why:** onCameraMove updates _center continuously, but _addressIsStale, the resolve and the requote are only started in _onCameraIdle. If Confirm is tapped after the finger lifts but before the camera settles (a fling's deceleration), _resolving and _requoting are both false, so nothing is awaited. _addressIsStale is still false, so the address booked is the old street, and fareTotalKr is the old pin's fare, while position is the new _center. The method's own contract (RIDE-12) says the street and the fare confirmed are the pin's own.

**Suggested fix:** In _confirm, treat _moving (or _isAwayFrom(_center, _routeStart)) as pending: mark the address stale and wait for the next idle, resolve and requote. Or disable Confirm while the camera moves.

### M71. Expanded Set pickup sheet clips the Confirm button off-screen (NeverScrollableScrollPhysics inside a 72% height cap), even without a promotion at 375x667

`lib/features/pickup/presentation/set_pickup_page.dart:980` (found by r2-rider3)

**What happens:** iPhone SE 375x667, 1x: cap 480, minus 26 padding = 454 available. The open sheet needs about 475 (handle 16, header 59, spot row 30, card 68, chips 49, bags 49, price 60, payment 58, Confirm 56, gaps). The bottom of Confirm is clipped. With an active promotion (+~69) Confirm and part of the payment 'Change' line disappear. With promotion and wallet on 390x844 (cap ~547) Confirm is hidden too. The same happens at 1.3x text. The rider sees Confirm vanish when expanding and cannot reach Change payment.

**Why:** The sheet Container is capped at `media.size.height * 0.72` and its content sits in a SingleChildScrollView with NeverScrollableScrollPhysics, which clips anything taller. When the rider opens the sheet (handle tap or drag), _reveal adds the ride header, bags row, price box (extra rows for a promotion and wallet split) and payment line above the Confirm button. The matrix tests at 320x568/2x only check for exceptions, and clipping throws none.

**Suggested fix:** Keep Confirm outside the clipped area (a pinned footer), or allow scrolling once content exceeds the cap (the drag gesture can still move the sheet when the scroll is at the top).

### M72. A 422 from the profile PATCH is treated as 'pending, retry later', so an over-long name blocks every later profile sync while the UI shows success

`lib/features/profile/data/synced_profile_repository.dart:78` (found by r2-rider4)

**What happens:** A rider enters a long full name (over 80 characters) in Personal info. The tile shows the new name and no error appears. The server never gets it, and from then on every privacy or language change fails silently, so the server keeps stale consents.

**Why:** _sync catches every error, sets `_syncPending = true` and returns normally. A permanent 422 invalid_profile (the contract and mock reject names over 80 characters) therefore looks the same as a network failure. Every later save resends the same cached invalid name and fails again, so no consent or language change reaches the server. Callers are never told: PersonalInfoPage._save only shows saveFailed when update() throws, and it never throws for this. The name editor (showAccountTextEditor) has no length limit, and RiderNameScreen allows 40 + 1 + 40 = 81 characters. A throwaway run with an 81-character name showed `thrown=null pending=true server=null`. A later consent change gave `pending=true server=null`.

**Suggested fix:** Mark only network/5xx/timeout errors as pending. Rethrow 4xx (422) errors so the screen can show them, and limit the name field to the contract's 80 characters.

### M73. Leaving Delete account during the in-flight request signs the rider out and wipes the device, but never routes to Sign in

`lib/features/profile/presentation/delete_account.dart:66` (found by r2-rider3)

**What happens:** Rider taps Delete my account, confirms, and taps back while the spinner shows. The server accepts with 202: tokens are cleared and local data wiped, but the rider stays on Account and Home looking signed in. Booking or loading anything fails with errors, and Sign in only appears after the app is restarted.

**Why:** While `_sending`, the main Delete account view has no PopScope, and its AccountScaffold back button calls Navigator.pop. If the rider leaves during the request, AccountDeletionController.requestDeletion still completes: it calls signOutLocally, which clears the tokens and runs UserDataWipe. Then `if (!mounted) return;` skips everything, including the _sentView whose Done and back buttons are the only way to reach showSignInRoot. The rider is left on Account/Home with no session and wiped data. In release builds every API call then fails without a token (no 401 refresh path, because there is no access token), and no Sign in screen appears until a cold start.

**Suggested fix:** Block pop while _sending, or call showSignInRoot from the controller path when the page is no longer mounted (the root navigator is available through moveraNavigatorKey).

### M74. Personal info saves edits from a stale copy of the profile, so editing the name while a gender save is still in flight puts the old gender back

`lib/features/profile/presentation/personal_info.dart:125` (found by r2-rider-r3)

**What happens:** On a slow network the rider opens Account > Personal info, taps Gender and picks Woman, then taps Name, types Lina and taps Save. When both saves finish, the stored profile has name 'Lina' and gender '' (the Gender row shows 'Not added'), so the gender choice is silently lost. Reproduced with a throwaway widget test: a repository wrapping ProfileRepository that writes the cache and then waits (like SyncedProfileRepository). Result: `Expected: 'Woman' Actual: ''` (test failed as predicted, then the test file was deleted).

**Why:** build() reads `final ride = _profile.profile;` (line 83), and each tile's onTap closure saves `ride.copyWith(...)` from that copy (name at line 125, gender at line 156). ProfileController.update awaits `_store.save(next)` and only calls notifyListeners afterwards. In SyncedProfileRepository.save, the cache is written first and then the PATCH /api/v1/rider/profile is awaited. So the page does not rebuild until the network call returns. The tiles have no busy guard. If the rider picks a gender and then taps Name before that PATCH returns, the editor's save builds the next profile from the copy taken before the gender change. That overwrites the cached gender with the old value. The same path also writes back an old `language` if the language was changed through the menu in the meantime. This is the same stale-copy pattern as the known privacy.dart finding, but in a different screen and through a different reachable path.

**Suggested fix:** Build the next profile from the current value when the save runs (`_profile.profile.copyWith(...)` inside the onTap, after the editor or choice sheet returns), or have ProfileController notify right after the cache write. Optionally disable the tiles while a save is in flight.

### M75. Privacy switches build the next profile from a stale copy and do not move until the PATCH returns, so a second toggle reverts the first one locally and on the server

`lib/features/profile/presentation/privacy.dart:97` (found by r2-rider1)

**What happens:** On a slow connection the rider turns Offers on. The switch stays off, so they turn Email updates off as well. Offers ends up off on the device and on the server, although the rider turned it on.

**Why:** Each Switch's onChanged calls `_profile.update(ride.copyWith(...))`, where `ride` was captured at build time. ProfileController.update calls notifyListeners only after `_store.save(next)` returns. SyncedProfileRepository.save awaits the network PATCH (`await _sync(saved)`, up to the 15 s ApiClient timeout) before returning. So during the round trip the page does not rebuild: the tapped switch still shows its old value, and `ride` is still the old profile. If the rider taps another switch in that window, the new profile is built from the stale `ride` and overwrites the first change, both in the cache and in a second PATCH. This was reproduced with InProcessMockClient(latency: 2s): after tapping Offers, the switch still showed false while the model was true. Tapping Email then left promotions=false, both locally and on the server.

**Suggested fix:** Notify listeners right after the cache write, before the network sync. Build each change from `_profile.profile` read at tap time, not from the build-time copy.

### M76. Zone wall-clock pickup time is stored as a device-local DateTime and compared with DateTime.now()

`lib/features/reservations/application/reservation_controller.dart:334` (found by rider3)

**What happens:** Web rider with browser in UTC (or a Stockholm phone in Tunis zone in summer) books a Stockholm pickup for 12:30 local (30 min ahead). Home chrono shows 2 h 30 m; `startLiveIfDue` reaches T-2 two hours after the real pickup; "No driver found" fires two hours late; free-cancel window shown/charged against the wrong instant.

**Why:** Q9 makes every Book-later time the pickup zone's wall-clock time: `ZoneClock.wallTime` returns a plain local `DateTime(local.year, …)` (zone_clock.dart:57-69) and `PickupSchedule` works in those (stockholm_schedule.dart:105-121). The picker returns that wall-clock value (select_date_time.dart:131, 153-158) and it flows unchanged into `ReservationDraft.scheduledPickupAt` (scheduled_ride_checkout.dart:21-32). The backend path converts it to a UTC instant (`PickupSchedule(timezone).toUtc(at)`, scheduled_rides_controller.dart:63-64), but the local reservation path never does: `startLiveIfDue` computes `ride.scheduledPickupAt.difference(currentTime)` with `currentTime = DateTime.now()` (334, 329), the chrono counts down with `DateTime.now()` (home_reservation_chrono.dart:206, 242-249; reservation_format.dart:99,117), `isNoDriverFound` (313-316) and the cancel-fee window (scheduled_ride_rules.dart:93-103) do the same. Whenever the device time zone differs from the pickup zone's (any browser outside CET on the public web build; a Stockholm phone booking a Tunis pickup in summer; a traveller abroad), every one of these is off by the offset. Throwaway test in this UTC container: minimumPickup() for 10:00Z gives wall-clock 12:30 (local, isUtc=false); `pickup.difference(now)` = 2:30:00 and the chrono label reads `2h 30m` for a ride 30 minutes away.

**Suggested fix:** Convert the picked wall-clock time to an instant (`PickupSchedule(timeZone).toUtc(when)`) before building the ReservationDraft, and render it back with `ZoneClock.wallTime` in the reservation screens; or store the IANA zone with the reservation and use it in every comparison.

### M77. Queued dispatch/lifecycle writes resurrect a ride the rider just cancelled (no status check inside the serialized change)

`lib/features/reservations/data/local_reservation_repository.dart:266` (found by r2-rider3)

**What happens:** On the live scheduled ride the rider taps Cancel at the moment the 20 s 'arrived' timer fires. writeStep sees driverEnRoute (the cancel is not committed yet) and queues driverEnRoute→driverArrived behind the cancel. The cancel commits, then the update sets driverArrived. The ride is 'upcoming' again, the trip continues to completed, and the rider was already sent Home.

**Why:** `_oneAtATime` serializes changes, but each change re-applies a status decided from an older snapshot. `startLiveIfDue` picks `ride` from `upcoming()` before its awaits, then calls `_store.assignDriver(id)` (→ driverAssignmentPending/driverAssigned) or `_store.updateReservation(... driverEnRoute)`. The mock trip's writeStep checks `current.status != from` synchronously and then queues `update(id, ReservationPatch(status: to))`. If a rider cancel is already queued in `_oneAtATime` (its prefs write in flight), these later changes run after it. Neither `assignDriver` nor `updateReservation` checks that the ride is still upcoming, so a cancelled ride gets its status overwritten. `cancellationActor`, `cancelledAt` and `cancellationFee` stay set.

**Suggested fix:** Inside the serialized change, re-check the current status (e.g. assignDriver/updateReservation status patches refuse when `!current.status.isUpcoming`, or take an expected `from` status) and return the current record unchanged.

### M78. Pickup and creation times are persisted as offset-less local ISO strings, so a device time-zone change moves the booked pickup instant

`lib/features/reservations/domain/reservation.dart:369` (found by rider-j8)

**What happens:** In Stockholm (UTC+2) the rider books 10:00 tomorrow, stored as '...T10:00:00.000' (08:00Z). They fly to London (UTC+1) and relaunch. Hydrate parses 10:00 London time = 09:00Z. The chrono counts down to a pickup an hour late, startLiveIfDue starts assignment and en-route an hour late, and the free-cancel window and fee are worked out against the wrong instant.

**Why:** toJson writes scheduledPickupAt, createdAt and estimatedDropoffAt with DateTime.toIso8601String(). For a local DateTime (what the booking flow passes) that gives '2026-10-22T10:00:00.000' with no offset. tryParse (DateTime.tryParse) reads it back as local time in whatever zone the device is in at hydrate. cancelledAt is stored as UTC (local_reservation_repository.dart:232), so only some timestamps keep their instant. This is the persistence side, separate from the known zone wall-clock construction issue at line 334: even a booking made correctly in the device zone changes instant after a zone change and an app restart. ARCHITECTURE.md names WireTime (RFC 3339 UTC) as the time contract.

**Suggested fix:** Serialize with toUtc().toIso8601String() (WireTime) and convert to local only for display.

### M79. Reservation status banner and driver-left banner name the driver even when admin set showDriverOnAccept=false

`lib/features/reservations/presentation/reservation_format.dart:192` (found by r2-rider3)

**What happens:** Admin sets showDriverOnAccept=false. The mock assigns Erik 15 s after booking. The card is hidden and the page says 'Driver details appear when your driver is on the way', but the banner directly above it reads 'Erik is assigned to this reservation.' After the handover, 'Erik left…' names a driver the rider was never meant to see.

**Why:** `ScheduledRideRules.showDriverOnAccept = false` means the rider sees the driver 'only once on the way' (`showsDriverOf`). UpcomingReservationPage hides the driver card in that case, but the status banner body still uses `ReservationFormat.statusBody`. For driverAssigned that body interpolates `driver.firstName` with no rules check. The 'driver left' banner (upcoming_reservation.dart:306-316) also prints `previousDriver`'s name unconditionally, even though that driver was never revealed.

**Suggested fix:** Pass `showsDriverOf(ride)` into statusBody and use `resBodyDriverAssigned` (no name) when false. Gate the driver-left banner the same way.

### M80. Cancelling a reservation from its live screen skips the reservation late-cancel terms, so no fee is recorded

`lib/features/reservations/presentation/reservation_live_ride.dart:79` (found by rider4)

**What happens:** Rules: free until 60 min before pickup, 50 kr after. Rider lets the driver start (T-2), the live screen opens, taps Cancel: the ride is cancelled with no fee recorded; History and the receipt show no fee, contradicting the terms the rider was shown.

**Why:** The Upcoming page computes the terms and passes the agreed fee: `cancelTermsFor(ride)` then `_reservations.cancel(id, reason:, fee: terms.fee)` (upcoming_reservation.dart:131-142). The two other cancel entry points for the same reservation never pass a fee: `ReservationLiveRide.onCancel` calls `reservations.cancel(ride.reservationId, reason: reasonId ?? 'rider_cancelled_live')` (78-85) and `ReservationRideRealtime.cancelRide` does the same (reservation_ride_realtime.dart:255-265). The live screen is exactly where the rider is once the driver is en route (T-2 min, `startLiveIfDue` 383-394 + chrono `_openLiveIfNeeded`), i.e. inside the late-cancel window the rules define (scheduled_ride_rules.dart:86-118, default 60 min / 50 kr). The cancelled ride is then saved with `cancellationFee == null`, History shows plain "Cancelled" (reservation_format.dart:27-33) and no fee is recorded, while the same cancel five minutes earlier from the Upcoming page records 50 kr.

**Suggested fix:** Compute `reservations.cancelTermsFor(ride)` in both live-screen cancel paths and pass `fee: terms.fee` (and show the terms note in the live cancel sheet).

### M81. Scheduled-ride Terms page shows only the admin's single cancel rule (1 h / kr 50), while Comfort/Premium/XL reservations are charged by their category rule

`lib/features/reservations/presentation/scheduled_ride_terms.dart:58` (found by r2-rider1)

**What happens:** Rider books a Premium ride for tomorrow 07:15 at kr 600. The Terms page says cancelling is free until 1 h before pickup, then kr 50. Cancelling at 05:30 (1 h 45 min before) is charged 25% = kr 150. The 'Things to know' card on the same ride also disagrees with the Terms page.

**Why:** `ReservationController.cancelTermsFor` prefers the zone config's per-category rule. di.dart passes `config: SeedRiderConfigRepository.seed`, so a SEK ride always gets `_configFor` → config → `reservationFeeFor(categoryId)`. The Stockholm seed has comfort: 60 min / 6000 öre and premium/xl: 120 min / 25% (min 8000, max 30000 öre). The Terms page (opened from 'View terms' on the Upcoming page) renders only `ReservationFormat.cancelRule(rules)`, the single admin rule (60 min / 5000 öre).

**Suggested fix:** Show the rule that applies to the ride (pass the Reservation and use cancelTermsFor / the category FeeRule), or list the per-category rules.

### M82. Cancel confirmed on a stale ride overwrites a ride that already went live or completed, and records a late fee

`lib/features/reservations/presentation/upcoming_reservation.dart:138` (found by r2-rider4)

**What happens:** At 23:47 the rider opens Cancel on the 23:50 ride and lingers on the reason sheet. At 23:48 the ride goes en route, and about 46 s later it is completed. The rider then taps a reason. The completed ride is rewritten as cancelled by the rider with a 'Cancelled · fee kr 50' chip. It moves from History › Completed to Cancelled, and a fee is recorded for a trip that was delivered.

**Why:** `_cancel(ride)` uses the `ride` captured at build time and works out `terms` before the two cancel sheets open. After the sheets it calls `_reservations.cancel(...)` without re-reading the ride or checking `status.canCancel`. `LocalReservationRepository.cancelReservation` has no status guard either: it always sets `status: cancelled`, `cancellationActor: rider`, `cancelledAt` and the fee. While the sheets are open, the Home chrono tick keeps running `startLiveIfDue`, which moves the ride driverAssigned → driverEnRoute, and the mock trip then runs to completed in about 46 s. `_handoffIfLive` does not fire because the page route is not current while a sheet is up.

**Suggested fix:** In cancelReservation (or the controller), re-read the ride and refuse when `!current.status.canCancel`. In the page, re-read `byId` after the sheets and abort when the status changed.

### M83. Upcoming reservation page says 'Reservation confirmed' for a ride the app has already declared 'No driver found'

`lib/features/reservations/presentation/upcoming_reservation.dart:287` (found by rider-j8)

**What happens:** A ride is booked for 10:00 in a build without dispatch. At 10:06 Home's chrono shows the red '!' badge and the 'No driver found' sheet. The rider opens History > Upcoming and taps the ride. The page shows a green 'Reservation confirmed' banner and says a driver will be assigned, which contradicts Home.

**Why:** ReservationController.isNoDriverFound (reservation_controller.dart:306-317) marks a scheduled/driverAssignmentPending ride with no driver as 'No driver found' 5 minutes after pickup, and the Home chrono turns red and opens the no-driver sheet. UpcomingReservationPage never asks the controller. It renders ReservationFormat.statusTitle(ride) / statusBody(ride, assignmentDisclaimer: ...), which map scheduled and driverAssignmentPending to resStatusConfirmed ('Reservation confirmed') plus the policy's assignment disclaimer. It also keeps showing Edit and Cancel with the 'Things to know' copy. The page is reachable for such a ride from History > Upcoming (ride_history.dart:283) and from notifications (notification_navigation.dart:133). In staging or production with flags.scheduledRides or bookingLater on, di.dart:143-168 composes LocalReservationRepository with no dispatch, so every reservation ends up in this state.

**Suggested fix:** In the build, check _reservations.isNoDriverFound(ride). When it is true, show the termNoDriverFound title and body (and the resolve/rebook actions) instead of the confirmed banner.

### M84. Cold start of a signed-in rider with no local ride waits up to about 30 s on GET /rider/trips/active, showing a blank white screen

`lib/features/ride_booking/application/ride_restore_coordinator.dart:453` (found by r2-rider1)

**What happens:** A signed-in rider opens the production app on a poor or captive network where the connection hangs instead of failing at once. They stare at a blank white screen for about 30 s before Home appears. With a 401 refresh in between it takes even longer. Nothing says the app is working, and an Active trip is not needed to show Home.

**Why:** _root() returns `pageFor(snapshot ?? await adoptServerActiveTrip())`, so with no local snapshot (the normal case) the root page waits for ApiActiveTripRepository.fetchActive(). That call goes through ApiClient.get → _getWithRetry: a 15 s timeout, retried once on timeout, plus a refresh round trip on a 401. Until it resolves, RideRestoreGate renders `_child ?? ColoredBox(white)`, and bootstrap has already dismissed the web splash on the first frame. adoptServerActiveTrip catches the eventual error, so the app does open on Home in the end, but only after the full timeout. Server-backed builds (staging/production) compose ApiActiveTripRepository.

**Suggested fix:** Render Home immediately and adopt the server trip in the background (replace the root if one comes back), or give the cold-start lookup a short deadline.

### M85. A leftover suppressRestore from a ride closed earlier makes resumeIfNeeded delete a just-adopted server trip on a push tap, so the ride does not open

`lib/features/ride_booking/application/ride_restore_coordinator.dart:595` (found by rider4)

**What happens:** Release build (ApiActiveTripRepository): rider finishes ride A on their phone (Done → closed). Later they book ride B on the web; the push for B taps on the phone. `_openRide` adopts B from the server, then `resumeIfNeeded` clears it and returns; the rider sees Home with no ride, and 'This ride has ended.' may be shown by `openNotificationRide`.

**Why:** `RideSession.suppressRestore` is set true by every terminal `localTransition`/`backendReconcile` (ride_session.dart 82, 148) and is only reset by a non-terminal transition or `reset()` (sign-out wipe). After the rider closes or cancels a ride on this device the flag stays true indefinitely. `openRideFromNotification` → `_openRide` (notification_navigation.dart 88-125) reads no snapshot, calls `adoptServerActiveTrip(expectedRideId)` which saves the server trip as the snapshot (ride_restore_coordinator.dart 78-100), then calls `resumeIfNeeded()`. `resumeIfNeeded` reads the new snapshot, resyncs, and then hits `if (AppScope.instance.ride.suppressRestore) { unawaited(RideSnapshotStore.clear()); return null; }` (595-598): the just-adopted trip is deleted and nothing opens, although the flag belongs to a different, finished ride. The cold-start path (`_root` → `pageFor`) has no such check, so the same trip is restored after a restart.

**Suggested fix:** Scope `suppressRestore` to the ride id it was set for (ignore it when the snapshot's rideId differs from `session.rideId`), or clear it in `adoptServerActiveTrip`.

### M86. Driver rating stars have no labels and no value for screen readers

`lib/features/ride_complete/presentation/give_review.dart:49` (found by r2-rider4)

**What happens:** On the ride summary a VoiceOver or TalkBack user swipes to the rating area and hears five unnamed 'button's (or nothing useful), with no '3 of 5 stars' state. They cannot tell what they are rating or what they already chose, on the main post-trip feedback path.

**Why:** RideCompletedGiveReview uses flutter_rating_bar 4.0.1's RatingBar.builder with plain `Icon(Icons.star_rounded)` items (no semanticLabel) and no Semantics wrapper. RatingBar builds a GestureDetector per star with onTapDown/drag only. Each star becomes an unlabeled actionable node: Flutter turns the TapGestureRecognizer into a semantic tap (gesture_detector.dart:1721), but nothing says which star it is, and the current rating is never exposed (no value, increase or decrease actions).

**Suggested fix:** Wrap the bar in a Semantics slider (label 'Rate your driver', value '$n of 5', onIncrease/onDecrease), or label each star item ('1 star' … '5 stars', selected).

### M87. An ended-early trip paid fully or partly by wallet is never debited from the local wallet ledger (demo/dev builds only)

`lib/features/ride_complete/presentation/ride_completed.dart:102` (found by r2-rider2)

**What happens:** Demo build. The rider books with Movera Wallet (balance 200 kr) and ends the trip on board after 3 km. The summary says 'You pay 74 kr'. They tap Done, and the wallet still shows 200 kr.

**Why:** An ended-early trip opens RideCompleted with endedEarly set and persistOnDemandState: false (waiting_for_driver.dart:895-899). initState returns at line 102 before the subscription and before _maybeChargeWallet. _maybeChargeWallet would also bail out on !persistOnDemandState. The server's charged fare (EndedEarlyTrip.charged, shown on the receipt as 'You pay X') is never taken off the local wallet ledger for a wallet-paid ride, and no other code calls chargeCompletedRide/chargeRide. The result is a receipt that says the rider pays X while the wallet balance stays the same.

**Suggested fix:** When an ended-early trip was paid by wallet (or had a wallet part), debit EndedEarlyTrip.charged (capped at the wallet part) once, using the same chargedRidesKey dedupe.

### M88. The completion screen ignores paymentFailed, so a declined card shows 'Payment processing' until the rider taps Done, and the trip is filed as Completed

`lib/features/ride_complete/presentation/ride_completed.dart:125` (found by r2-rider2)

**What happens:** Release build. A rider pays with a card. The trip completes, RideCompleted opens, the server reports payment authorized (Payment processing), then the card is declined (paymentStatus failed). The screen stays on 'Payment processing' indefinitely, and the decline also survives a reload because the snapshot keeps paymentProcessing. The rider taps Done, History shows the ride as Completed, and the rider gets no 'payment could not be completed / review your payment method' message. If the decline arrives during the Waiting-to-Completed handoff, Done instead fails with 'feedback could not be saved' every time.

**Why:** Release realtime is ApiRideRealtime. A card declined at the end of a trip arrives as status completed plus paymentStatus failed. RideStatusWire._afterCompletion (core/contracts/trip_status.dart:183) maps that to RideStatus.paymentFailed. paymentFailed is isTerminal but not isCompletedSurface (core/contracts/ride_status.dart:65,85). Once Waiting has pushed RideCompleted, its tracker is disposed, and RideCompleted's own subscription is the only listener. That listener throws away every event whose status is not a completion surface. The decline is never reconciled into RideSession, never persisted and never shown. _CompletionSpec has no paymentFailed case, and the paymentFailed terminal sheet in ride_terminal_state_sheet.dart:287 is only reachable from Waiting. The rider stays on 'Trip complete / Payment processing' with rating locked ('rating after payment'). Done then runs closeCompletedRide: OnDemandRideHistoryStore.archive gets the snapshot status (paymentProcessing, a completion surface), so History lists the trip as Completed, and the session moves to closed. The payment is still outstanding and nothing tells the rider. Handoff race: if the decline lands while Waiting parks the map (active_ride_controller markCompleted, then waiting_for_driver.dart:717), the tracker has already set the session to paymentFailed. RideCompleted's initState accepts only completion-surface session statuses (line 114), so it starts at tripCompleted. Done then calls localTransition(closed) from the terminal paymentFailed, transitionRide throws InvalidRideTransition, and the rider is trapped on 'feedback could not be saved'.

**Suggested fix:** Handle paymentFailed (and other terminal non-completion statuses) in the RideCompleted listener and in initState's session check. Reconcile it into RideSession, persist it, and show the payment-failed state or terminal sheet with a path to change the payment method. In closeCompletedRide, do not call localTransition(closed) when the session is already terminal.

### M89. The wallet debit depends on RideCompleted still being mounted when paymentFinalized arrives; leaving at tripCompleted/paymentProcessing (or ending early) never charges the local wallet (demo/dev builds)

`lib/features/ride_complete/presentation/ride_completed.dart:149` (found by r2-rider2)

**What happens:** Demo/dev build. The wallet holds 500 kr and the rider books a 259 kr ride paid by Movera Wallet. When the trip completes, the mock realtime only sends paymentFinalized after about 1 s (paymentProcessingAfter plus paymentFinalizedAfter, 500 ms each). The rider taps Done straight away and the balance stays at 500 kr for good. I reproduced this with a throwaway widget test built on phase105_wallet_ride_charge_test: pump RideCompleted at tripCompleted, replace it with SizedBox, then emit paymentFinalized. Output: 'balance after leaving early then paymentFinalized: 500.0' (expected 241). The same happens for any ended-early trip paid from the wallet.

**Why:** D-022 says a wallet-paid ride is deducted once it reaches paymentFinalized. The only caller of WalletController.chargeCompletedRideById is RideCompleted._maybeChargeWallet, which runs from initState and from the realtime listener on this screen. The Done button is enabled at every completion status (`onPressed: _leaving ? null : _closeAndHome`), and Back with nothing selected leaves at once. If the rider leaves while the status is still tripCompleted or paymentProcessing, three things happen: _leave calls closeCompletedRide, which archives the ride and runs `_store.clear()` on the snapshot; dispose cancels _completionSub; and the later paymentFinalized event reaches nobody. Nothing tries the charge again: the snapshot is gone and nothing else calls chargeCompletedRide. Ended-early trips are never charged at all, because initState returns before both _maybeChargeWallet calls (`if (widget.endedEarly != null) return;`).

**Suggested fix:** Do not tie the debit to this screen's lifetime. Either record a pending wallet charge for the ride id when it completes and settle it from an app-level listener once the payment is final, or charge when the ride closes, using the booked wallet part or the ended-early `charged` amount, keeping the existing charged-rides guard against double charging.

### M90. A terminal status (e.g. paymentFailed) reconciled during the Waiting->RideCompleted handoff makes closeCompletedRide throw InvalidRideTransition, so Done and Back both fail with a misleading 'feedback could not be saved' and the rider cannot leave

`lib/features/ride_complete/presentation/ride_completed.dart:252` (found by rider1)

**What happens:** Payment fails on the server right as Waiting hands over to the summary. The rider rates the driver and taps Done: the rating is sent, then 'Your feedback could not be saved' appears every time, and neither Done nor Back leaves the screen.

**Why:** `_leave` wraps feedback submission and `closeCompletedRide` in one try/catch; any throw from the latter sets `_submitError = context.l10n.feedbackSaveFailed` and `_leaving = false` (259-265), and both Done and Back route through `_leave`, so the rider can never leave. `closeCompletedRide` can throw after the feedback was accepted: `localTransition(RideStatus.closed)` (active_ride_controller.dart 459) throws `InvalidRideTransition` when the session is already terminal, which happens when a `paymentFailed` (or other terminal) projection is reconciled by the still-live `DriverTrackingController` during the Waiting→RideCompleted `pushReplacement` handoff (RideCompleted's own listener ignores non-completed statuses, 123-127, so the screen keeps showing 'Trip complete'); `archive` can also throw its `StateError` after six lost writes (on_demand_ride_history_store.dart 172-176). The message then blames the rating/tip, which was in fact sent (`_acceptedFeedbackIntent` is set).

**Suggested fix:** Separate the two failure classes: keep the error only for a refused feedback submission, and make leaving tolerant (catch `InvalidRideTransition`/archive errors, clear the snapshot and still navigate Home).

### M91. A wallet-paid ride is never debited if the rider taps Done before payment is finalized

`lib/features/ride_complete/presentation/ride_completed.dart:414` (found by r2-rider2)

**What happens:** Demo build, wallet balance 300 kr. The rider pays a 129 kr trip with Movera Wallet. The completion screen appears and they tap Done within about one second, while the status is tripCompleted or paymentProcessing. They land on Home and the wallet still shows 300 kr, permanently, so the ride was free.

**Why:** D-022 wallet deduction runs only from _maybeChargeWallet, inside RideCompleted. It fires only once _status reaches paymentFinalized or later (lines 149-158). chargeCompletedRideById is called from nowhere else (grep: ride_completed.dart:163 only). Done is enabled from the first frame, including tripCompleted and paymentProcessing. Tapping it runs closeCompletedRide, which clears the completion snapshot, and dispose cancels the subscription. The later paymentFinalized event therefore never reaches a charging listener, and no restore will bring the screen back because the snapshot is gone. In the demo transport, paymentProcessing comes 500 ms after completion and paymentFinalized 500 ms after that (mock_ride_realtime.dart:32-33), so a quick Done skips the debit. The same applies to the wallet part of a 'use wallet first' split.

**Suggested fix:** Run the wallet debit from a place that outlives the screen, for example the realtime or session layer or closeCompletedRide when the ride is wallet-paid and payment later settles. Alternatively keep listening (or keep the snapshot) until the payment reaches a settled state.

### M92. Receipt dispute sheet double-pads for the keyboard, so Submit is out of reach while the rider types

`lib/features/ride_complete/presentation/trip_detail.dart:150` (found by r2-rider3)

**What happens:** Native iPhone 390x844, keyboard 336 px: the Column gets 844 - 336 - 336 - 40 = 132 px but needs about 213 px (title 25, body ~40, field ~72, spacers, button 40). The FilledButton 'Submit issue' starts at about 173 px, outside the Column, so it is not hit-testable. The rider types the issue and cannot submit it. Tapping above the sheet dismisses it and the typed text is lost.

**Why:** _openDispute's builder pads its non-scrolling Column with `20 + MediaQuery.viewInsetsOf(context).bottom`, on top of MoveraSheet.show's own keyboard Padding. The multiline field (minLines 2, maxLines 4) uses a newline return key, so on iOS the keyboard cannot be dismissed from the keyboard. Flutter does not unfocus on a touch tap outside the field on mobile. A tap on the transparent band falls through to the barrier and closes the sheet, losing the text.

**Suggested fix:** Drop the viewInsets term (keep the 20), and wrap the Column in a SingleChildScrollView.

### M93. Wallet is offered as the full payment method even when the fare is above the balance, and completing the ride drives the local wallet ledger negative (demo/dev builds, where the local wallet is enabled)

`lib/features/ride_selection/application/ride_selection_controller.dart:267` (found by rider4)

**What happens:** Rider has 50 kr in the wallet, picks a 259 kr ride, opens Pay with, taps the Movera Wallet row ('Balance: 50 kr'), books. Ride completes: wallet balance shows -209 kr, the wallet disappears from Pay with (balance not > 0), and the next 100 kr top-up shows -109 kr.

**Why:** The wallet row is listed whenever `walletBalance > 0` with no comparison against the fare (ride_selection_controller.dart:265-268), PayWithPage pops `'wallet'` on tap with no check (pay_with_page.dart:224-232), and `walletSplitFor` returns `WalletSplit.none` for the wallet method (200-202) so `walletAmountMinor` is 0 and the server-side range check in the mock (`walletMinor > serverTotal`) cannot catch it. At completion `RideCompleted._maybeChargeWallet` → `chargeCompletedRideById` → `chargeCompletedRide` charges `amount = snapshot.price` (wallet_controller.dart:282-283) and `LocalWalletRepository._apply` subtracts with no floor (wallet_repository.dart:215-218), so the stored balance becomes negative and WalletHome shows e.g. '-209 kr'. Reproduced: `brand=wallet walletMinor=0 remainderMinor=25900` and `balance after wallet-paid 259 kr ride from 50 kr: -209.0`.

**Suggested fix:** Offer the wallet as a full method only when `walletBalance >= fare` of the selected ride (or show it disabled with 'Balance too low'), and clamp `debitRide` to the available balance / refuse the charge with a logged error.

### M94. A quote in another currency drops the wallet row and shifts the index-based payment choice to a different method

`lib/features/ride_selection/application/ride_selection_controller.dart:457` (found by r2-rider2)

**What happens:** A rider with wallet credit picks Card. The quote comes back in EUR, so the wallet row disappears and the payment line switches to Cash without the rider touching it. Book then sends paymentMethod 'cash'.

**Why:** The chosen payment is held as an index into payments() (selectedPayment, line 114). payments() includes the wallet row only while walletMatchesTrip holds (line 267). Every other list change re-selects by brand: setWalletBalance, setZonePaymentMethods and loadSavedCards all do. adoptQuote changes `currency = quote.currency` without that. When the server prices the pickup in a currency other than the RiderZones guess (the controller explicitly supports this: 'the server decides'), walletMatchesTrip turns false and the wallet row, which is first in the list, disappears. Every index then points one row further down, so the selected method silently becomes a different one. This is separate from the known finding about prices mixing currencies.

**Suggested fix:** In the currency setter (or adoptQuote), remember the selected brand before the change and call selectPaymentByBrand(brand) afterwards. Better still, store the selection as a brand instead of an index.

### M95. An expired quote makes the ride row show the catalog list price as if it were the fare, with no re-quote until Book is tapped

`lib/features/ride_selection/application/ride_selection_controller.dart:498` (found by r2-rider2)

**What happens:** The rider looks at Select Ride for more than the quote lifetime (2 min in the mock) on an Arlanda trip quoted at 412 kr. Dragging the sheet changes every row to its list price (Movera 259 kr, Comfort 339 kr ...), which looks like a price drop. Tapping Book then says the price is unavailable and re-prices.

**Why:** priceFor discards an expired quote (_discardExpiredQuote removes offeredPrices and authoritativeQuotes) and returns `offeredPrices[id] ?? catalog`. A failed quote (_loadQuote catch) also removes offeredPrices. _hasPrice is true for any list price in the pickup's currency, so _rideTile shows the catalog price (e.g. 259 kr for every Movera trip, whatever the distance) as the fare. It is not marked as an estimate or as unavailable. Nothing schedules a re-quote at expiry. The next rebuild (sheet drag, tapping a row) simply swaps the quoted fare for the list price. The rider learns that there is no price only when Book answers 'price unavailable, refreshing'. DECISIONS P4: 'Clients display a quote; they do not invent totals.'

**Suggested fix:** Show '…' or 'updating' for ids in unavailableQuoteIds or with an expired quote instead of the catalog price, and schedule a re-quote shortly before quoteExpiresAt.

### M96. Saved 'wallet' default payment is silently replaced by Cash on every Select Ride open (load-order race)

`lib/features/ride_selection/application/ride_selection_controller.dart:576` (found by rider4)

**What happens:** Rider with 500 kr in the wallet chooses Movera Wallet in Pay with (persisted as default). Next time they open Select Ride the footer shows Cash; if they do not notice, the ride is booked as Cash and the driver asks for cash.

**Why:** `SelectRide.initState` starts `_loadSavedCards(paymentName)` (line 353) and `_loadWalletBalance()` (line 361) concurrently. `_loadSavedCards` → `restoreDefaultPayment()` reads the saved brand and, because `payments()` only lists the wallet when `walletBalance > 0` (ride_selection_controller.dart:267) and the balance has not loaded yet, hits `if (saved == null || !list.any((item) => item.brand == saved)) { _selectDefaultPayment(); }` and selects Cash. `_loadWalletBalance` resolves later (`loadUseWalletFirst` → `WalletStore.loadPayments` performs four `prefs.remove` platform calls plus possible writes before returning) and calls `setWalletBalance`, which only re-selects the *current* brand (`if (current != null) selectPaymentByBrand(current);`, 598-602), i.e. Cash. The remembered wallet default (persisted by `selectPayment` → `_persistSelectedBrand` and by WalletScreen `_selectMethod('wallet')`) is therefore never restored, contradicting the R10 note in default_payment_store.dart ('the choice survives relaunch'). A return ride whose origin was paid with 'Movera Wallet' loses it the same way (`selectPaymentNamed` runs before the balance is known). Reproduced with a throwaway test driving the same sequence on the controller: `afterRestore=cash walletOffered=true afterBalance=cash savedDefault=wallet`.

**Suggested fix:** Remember the saved brand in the controller (e.g. `_pendingDefaultBrand`) when it is not yet offered, and re-apply it in `setWalletBalance`/`setZonePaymentMethods` once it appears; or have SelectRide await the wallet balance before `restoreDefaultPayment`.

### M97. Ride category notes and badges ('Affordable and convenient rides', 'RECOMMENDED', 'FASTER') from the built-in and mock catalogs are shown in English to fr/sv riders

`lib/features/ride_selection/data/ride_selection_repository.dart:14` (found by rider3)

**What happens:** Swedish rider opens Välj din resa: each category row shows 'Affordable and convenient rides', 'Newer cars with extra legroom' and the badges 'RECOMMENDED'/'FASTER' in English.

**Why:** RideCatalogItem.note/badge are rendered raw on Select ride (select_ride.dart:2355 `ride.note,` and :2376 `ride.badge!,`). The built-in list (the initial `_current` of RideCatalogController and the offline/cold-start fallback, ride_catalog_controller.dart:27, :89) and the in-process mock catalog (in_process_mock_client.dart:176-204) both carry English-only notes/badges; unlike payment rows (payment_labels.dart maps the English detail strings to ARB keys) there is no mapping for catalog text and no ARB keys for them. The API client also sends no Accept-Language/language header (api_client.dart:80-82 only Accept/Content-Type), so a real server has no way to localize them either. In the public demo build (mock client) every fr/sv rider therefore sees English descriptions and badges on the main booking screen.

**Suggested fix:** Map built-in/mock notes and badges by category id to ARB keys at display time (as payment_labels.dart does), and send Accept-Language with L10n.code so the server can localize catalog text.

### M98. Editing a reservation or planning a return ride paid with Movera Wallet always reopens Select Ride with Cash, because the wallet row is not offered until the balance loads and the requested name is never re-applied after that

`lib/features/ride_selection/presentation/select_ride.dart:406` (found by r2-rider4)

**What happens:** The rider edits a scheduled ride that was booked with Movera Wallet. Select Ride opens with Cash selected, Review changes lists the payment change to Cash, and saving the edit stores Cash.

**Why:** initState calls selectPaymentNamed(paymentName) and then _loadSavedCards(paymentName), which re-applies the name after the cards load (line 406). The wallet row exists only once walletBalance > 0, which _loadWalletBalance sets in a separate future (two awaits). If the cards load first, 'Movera Wallet' is not in payments(). selectPaymentNamed finds nothing and leaves the constructor default (Cash), and setWalletBalance later re-selects that current brand (cash). The reservation's stored payment is lost. In the edit flow, ReviewChanges then saves Cash. This has the same root race as the known restoreDefaultPayment finding, but on the explicit initialPaymentMethod / editingReservationId path.

**Suggested fix:** Re-apply the requested payment name (or brand) after the wallet balance has loaded too, for example by awaiting both loads before resolving the initial method.

### M99. Cancelling Set pickup in Book for later after the pin was re-priced keeps the pin's price, and the next Schedule books it at the original pickup

`lib/features/ride_selection/presentation/select_ride.dart:1137` (found by r2-rider4)

**What happens:** A rider scheduling a ride drags the pin toward the airport terminal, then changes their mind and goes back. The Movera row now shows 301 kr for the original pickup. Tapping Schedule and confirming at the original point saves a reservation priced 301 kr instead of the 259 kr quote for that point.

**Why:** When the rider backs out of Set pickup after a pin quote was adopted, Book now reloads the list quotes (line 1484: `if (_pinQuoteAdopted) unawaited(_loadQuotes());`) because 'the pin's price belongs to a point the rider did not confirm'. The scheduled path just returns (line 1137: `if (spot == null || !mounted) return;`). It never resets or checks _pinQuoteAdopted, so the selection keeps the moved pin's quote as the authoritative price at the unchanged original pickup. On the next Schedule tap, Set pickup opens at the original point and shows that price. Confirming without moving the pin creates the reservation at the moved pin's price for the original pickup.

**Suggested fix:** In _bookScheduled, reset _pinQuote/_pinQuoteAdopted before opening Set pickup and reload quotes when Set pickup is cancelled after a pin quote, as _bookNow does.

### M100. After a confirmed pickup-pin move, other categories (and the selected one when its pin re-quote failed) are booked with quotes priced at the original pickup

`lib/features/ride_selection/presentation/select_ride.dart:1487` (found by rider2)

**What happens:** Rider picks Economy, taps Book, drags the pin 1.5 km in Set pickup, confirms, gets 'Price updated 310 kr (was 259 kr)', taps Not now. List now shows Comfort at the price quoted for the original pickup. Rider taps Comfort → Book → Set pickup opens at the new pin showing the old-pickup price → Confirm and search → ride is created at the new coordinates with the old-pickup quote and price; Finding/Waiting then show that price.

**Why:** Set pickup only re-quotes the selected category, and only when the pin moves (set_pickup_page.dart:493-507 `if (_isAwayFrom(_center, _routeStart)) { ... unawaited(_requote()); }`). When the rider confirms a moved pin, `_bookNow` stores the new position (`_pickupAddress = spot.address; _pickupPosition = spot.position; _pickupConfirmed = true;`, 1487-1489) but never reloads the list quotes. If the rider then declines the 'Price updated' dialog (1515-1520 returns after `setState`), or returns from Finding Drivers, every other category still holds `authoritativeQuotes` priced from the old pickup, and the tiles show those prices. Tapping Book on such a category passes `_book`'s `quoteIsAvailable` check (the quote is fresh for up to 2 min), opens Set pickup at the NEW position showing `fare: SetPickupFare(totalKr: _priceFor(ride) ...)` (1307-1309, the old-pickup quote), and because the pin does not move nothing re-quotes; `_quoteAfterPickup` returns `_bookableQuote(ride.id)` as long as it is not expired (559-560), so `submitFinding` sends `pickupLat/Lng` of the new point with `quoteId`/`quoteSignedPayload` of the old point. The same happens for the selected category itself when its pin re-quote timed out: `_requoteNow` keeps the old fare (set_pickup_page.dart:534-541), `shown == quote.totalMinor` so no dialog, and the old-point quote is booked. The in-process mock's `_validateQuoteBinding` (in_process_mock_client.dart:2188-2230) checks id, signature, expiry, total and category but not the pickup, so the booking is accepted at the wrong price. `_bookScheduled` has the same shape: it never awaits `_pinQuote`, so a pin re-quote still in flight when Set pickup pops (it waits at most 3 s) leaves `ScheduledRideCheckout.draftFrom` → `quotedPrice` on the old-point quote.

**Suggested fix:** After a confirmed pin move (and on 'Not now'), call `_loadQuotes()` so every category is re-priced from `_pickupPosition`; in `_quoteAfterPickup`, treat a quote whose pickup point differs from the confirmed one (or a failed pin re-quote) as unavailable and re-quote before booking; have `_bookScheduled` await `_pinQuote` the way `_bookNow` does.

### M101. A trigger detected while another card is open is used up and never shown or posted (for example dropped-far at trip end while the long-stop card is unanswered)

`lib/features/safety/application/ride_check_controller.dart:304` (found by r2-rider2)

**What happens:** Long stop card shows mid-trip and the rider does not answer. The trip is then finished 3.6 km from the drop-off. On the summary the rider answers the long-stop card ('I'm OK'). No 'Driver finished far from drop-off' check ever appears and no droppedFar safety event is posted, though the admin trigger is on.

**Why:** `RideCheckMonitor._fire` adds the trigger to `_fired` before the controller tries to show it. The controller then calls `open()`, which returns `busy` when a card is already up. The detection is neither queued nor posted as a safety event, and because the monitor already marks it fired it can never trigger again for this trip. In this journey, the rider has not answered the long-stop card. The driver taps Finish 3.6 km from the drop-off. `tripEnded` makes the monitor fire droppedFar and `open()` returns busy. The dropped-far check never opens, is never recorded on the trip and never reaches the server. The same happens to a long stop that is detected while an off-route or crash card is still up.

**Suggested fix:** Queue detections that arrive while a card is open and show them after it closes, or at least post their safety event. Alternatively, only mark a trigger fired once it has actually been shown.

### M102. A Ride check left open when the trip ends externally (admin cancel or failed) stays as the session forever, and no later trip can open a Ride check

`lib/features/safety/application/ride_check_controller.dart:379` (found by r2-rider2)

**What happens:** Ride 1: a long-stop card is open and unanswered when the admin cancels the trip. The rider lands on Home and the card is gone. Ride 2, same app session: the car stands still for 10 minutes at a non-planned spot. RideCheckController.open returns busy and no card ever appears. The Safety › RideCheck demo also reports 'busy'.

**Why:** Only imOk()/done() clear `_session` (via `_close`). When a trip with an open card ends in a non-completed terminal status, `_handleExternalTerminal` calls markExternalTerminal and goes Home (waiting_for_driver.dart:548-596). Statuses that do this include cancelledByAdmin and failed. Home and later screens host no RideCheckLayer for that ride, so the card can never be answered. `_session` still holds ride X, so every later `open()` returns `busy` at line 379, and `resume()` returns early at line 426. On ride Y in the same process, `sessionFor(Y)` is null, so nothing shows and nothing blocks: long stop, off-route, crash and dropped-far are all silently dropped (the monitor marks them fired). This lasts until the app process restarts.

**Suggested fix:** When a ride ends without a completion surface, close or park the session for that ride (save it as unanswered on the event). Scope the `busy` check to the visible ride, so a stale session for another ride does not block new trips.

### M103. A Ride check the rider already answered reappears if any ride screen resumes while the close is still queued behind a slow alert

`lib/features/safety/application/ride_check_service.dart:97` (found by r2-rider1)

**What happens:** Reproduced with a throwaway test. Open a long-stop card and hold POST /ridecheck/answers. chooseRow(unsafe) starts the alert, then done() leaves session=null, then resume('r2') leaves the session open again. After the held request is released and the queue settles, the session is still open. On a slow or offline network the rider who answered 'I feel unsafe' and tapped Done sees the card come back on the next ride screen and must answer again. Back is blocked until they do.

**Why:** _close sets `_session = null` immediately, but the final submit that marks the event `resolved` is only enqueued, behind any alert POST still in flight (_enqueue serialises writes). Until that job runs, the saved event stays `acknowledged`; the red-row alert submit set that status before awaiting the network. resume(rideId) runs from every RideCheckLayer initState or didUpdateWidget, for example when RideCompleted mounts. It sees `_session == null`, asks unanswered(), which returns any event that is not resolved or stale, and rebuilds the card. resume does not consult `_shown` or anything that records a just-closed check. When the queued close finally runs, nothing closes the resurrected session.

**Suggested fix:** Mark the event resolved locally and synchronously in _close, before enqueuing the network work. Alternatively, keep a set of closed checkIds and make resume() skip them, or wait for settle() before it calls unanswered().

### M104. The card and Kit keep showing 'Recording m:ss' after the OS has interrupted capture (112 call or app in background); the app has no background audio mode

`lib/features/safety/application/safety_audio_service.dart:30` (found by r2-rider1)

**What happens:** The rider starts a Ride check recording, then taps Call 112 and talks to the operator for 3 minutes. Returning to the app, the card shows 'Recording 3:40'. The saved file has no audio after the dialer opened, which the rider learns only if they ever find the file.

**Why:** `isRecording` only reflects the service's own `_active` field. Nothing listens to the recorder's state or interruptions. The app declares no background audio (Info.plist UIBackgroundModes has only remote-notification, and the Android manifest has no microphone foreground service). So when the rider follows the journey and taps Call 112, the dialer takes the foreground and the call takes the microphone: iOS interrupts and suspends the recording, and Android 9+ records silence for a backgrounded app. Back in the app, the card's ticker still counts 'Recording 3:12 · Tap to stop' as if everything since the call had been captured.

**Suggested fix:** Subscribe to the recorder's state/interruption stream and update the card (stop, or show 'paused by call'). Declare background audio (iOS) or a microphone foreground service (Android) if recording must survive a call or a locked screen.

### M105. Wipe disposes the Safety and Ride check controllers without stopping a running recording, so the microphone keeps recording with no owner

`lib/features/safety/application/safety_controller.dart:71` (found by r2-rider1)

**What happens:** Rider A is in a trip, a Ride check opens and A taps 'Record audio'. The session expires (refresh rejected), so Sign in replaces the trip screen and the microphone is still recording. Rider B signs in: the wipe replaces the controllers, and the microphone stays on recording into A's file with no Stop button anywhere, until the app is killed.

**Why:** UserDataWipe.resetInMemory calls SafetyController.resetShared(). That calls RideCheckController.resetShared() (dispose only sets _disposed and clears the QA owner), then `_shared?.dispose()`. SafetyController does not override dispose, so this is plain ChangeNotifier.dispose. Neither path calls `audio.stopIfRecording`. An RC5 recording started from the Ride check card is not stopped when WaitingForDriver is torn down either: its dispose only calls `RideCheckController.shared.detachTrip(rideId)`, which nulls the monitor. When the session expires mid-trip, showMoveraRoot(SignIn) pops the trip screen and the recording keeps running behind Sign in. When the next rider signs in, enterSessionAs -> run -> resetShared drops the only reference to that SafetyAudioService. Nothing can ever stop the recorder again before the process dies.

**Suggested fix:** In resetShared (or in UserDataWipe.resetInMemory, before resetting), await or fire `_shared?.audio.stopIfRecording(reason: 'session_end')` and delete the result. Also stop the recording when the trip screen is disposed by a forced Sign in.

### M106. Share trip uses the stored tripShareContactIds whenever that list is non-empty, so deleted contacts are sent the trip and contacts marked 'Share trips' are left out

`lib/features/safety/application/safety_controller.dart:300` (found by r2-rider1)

**What happens:** Reproduced with a throwaway test. Add contact Anna, tick her on Trip share (prefs ids [Anna]), delete Anna, then add Bo with 'Share trips' on. Safety Kit > Share trip: share.contactIds=[<Anna's deleted id>] and Bo is not included. The toast says 'Trip sharing started for 1 trusted contact.' Bo, the only real contact, never receives the trip. The same happens when a contact ticked on Trip share is later disabled or has 'Share trips' switched off in the editor: that contact still receives the ride.

**Why:** Two sources of truth decide who receives a shared trip: `preferences.tripShareContactIds` (set by the Trip share checkboxes) and `EmergencyContact.shareTrips` (set by the checkbox and by the contact editor's 'Share trips' switch). The Trip share page shows a contact as checked if either is set (trip_share_page.dart:150-154), and the Safety Kit guard accepts either (ride_safety_kit.dart:214-217). startShare, however, passes `preferences.tripShareContactIds` whenever it is non-empty. The store then uses those ids verbatim, without checking that they still exist or are enabled (safety_store.dart:257-258). Nothing removes an id from that list when a contact is deleted, disabled, or has 'Share trips' turned off in the editor. The share is therefore sent to stale ids, contacts enabled only through shareTrips are omitted, and the success toast counts share.contactIds.length, stale ids included.

**Suggested fix:** Derive the recipient list from the current contacts only: enabled contacts that are in the selected ids or have shareTrips. Prune ids for deleted or disabled contacts in deleteContact and updateContact. Better, keep a single source of truth for the selection.

### M107. Safety audio recording stops capturing when the app backgrounds or the 112 dialer opens; no iOS audio background mode or Android foreground service, and the default interruption mode pauses without resume

`lib/features/safety/application/safety_recorder_native.dart:30` (found by r2-rider2)

**What happens:** During a ride the rider taps Record audio, then Call 112 (or locks the phone). The dialer or call takes the foreground. iOS suspends or pauses the AVAudioRecorder, and Android delivers silence. When the rider returns, the card still shows 'Recording mm:ss'. Stop saves a file that holds only the seconds before the call, while the record lists the full wall-clock duration. Verified by reading the code and plugin defaults; nothing was run.

**Why:** NativeSafetyRecorder starts `record` with a bare RecordConfig. The audioInterruption default is AudioInterruptionMode.pause, which pauses on an interruption such as a phone call and needs a manual resume. Nothing in the app ever resumes. Info.plist UIBackgroundModes holds only remote-notification, not audio, so iOS suspends the recorder when the screen locks or the app leaves the foreground. On Android there is no foreground service (no FOREGROUND_SERVICE/FOREGROUND_SERVICE_MICROPHONE permission, no AndroidRecordConfig service), and since Android 9 a backgrounded app gets silence from the mic. The UI copy says recording continues until Stop or until the kit closes. SafetyAudioService.stop computes durationMs from wall-clock start/end, so the saved record claims the full duration. The Safety Kit and Ride check put 'Record audio' next to 'Call 112', and the 112 button opens the external dialer (backgrounds the app and starts a call), which is exactly the moment audio matters.

**Suggested fix:** Add the iOS 'audio' background mode and configure the audio session. On Android, record through the plugin's foreground service with FOREGROUND_SERVICE_MICROPHONE. Choose pauseResume, or listen to onStateChange and surface paused state. Compute the duration from the recorder, not the wall clock.

### M108. A failed Safety write restores a snapshot of the whole cache, which wipes Ride check answers, events, recordings and contacts saved while it was in flight

`lib/features/safety/data/safety_store.dart:98` (found by r2-rider-r3)

**What happens:** During a trip on a flaky connection, the rider taps Share trip in the Safety Kit, so startShare's `_write` takes its snapshot and waits on POST /rides/{id}/share. A Ride check card opens and the rider answers 'I'm OK'. submitRideCheckAnswers saves the answers locally, and its own send fails offline (the answers are meant to stay). The share request then times out and `_cache = previous` restores the snapshot taken before the answers. The Ride check event and its answers are gone from the device: the trip's details show no Ride check, and after a reload `unanswered()` cannot find it. Reproduced with a throwaway test against SafetyStore (fake remote, memoryOnly local): 'answers saved before share fails: 1' and then 'answers after share rollback: 0'.

**Why:** Each `_write` call takes `previous = SafetyCache.fromJson(_cache.toJson())` (line 83). On a remote failure it runs `_cache = previous; await _local.save(_cache);` (lines 98-99). That replaces the entire cache: preferences, contacts, shares, events and recordings. Nothing serializes writes across the store. RideCheckController queues only its own jobs, and the Safety Kit (startShare, initAudio/completeAudio), the preference toggles (patchPreferences, patchRideCheck) and contact edits all call `_write` independently. Anything written to the cache after the snapshot and before the failure is erased from memory and from the persisted blob. That includes `submitRideCheckAnswers` (its `keep()` plus `_local.save`, lines 452-455), which RC5 says must keep the answers on the device even when the send fails. The reverse also happens: when a concurrent write succeeded first, the failing write's rollback drops the confirmed change (for example a contact the server created) from the device copy.

**Suggested fix:** Roll back only the slice the write changed. Capture the previous value of that field or entry and restore it, for example the previous share for that rideId or the previous preferences, instead of reassigning the whole cache. Or serialize every store mutation behind one queue.

### M109. The 'longer than expected' budget is fixed from the first in-trip sample's ETA and never revised; a stale pickup ETA fires a false off-route Ride check, and an ETA of 0 turns the trigger off for the whole trip

`lib/features/safety/domain/ride_check_monitor.dart:118` (found by r2-rider-r3)

**What happens:** The driver starts the trip at the pickup. The first in-trip sample has etaSeconds 20 (the pickup ETA), followed by normal samples whose ETA to the drop-off counts down from 600 s. Reproduced with a throwaway test on RideCheckMonitor: driving normally along the planned route, it returned `RideCheckTrigger.offRoute` with longerPercent 900% at 200 s into a 10-minute trip. The rider sees a 'trip is taking much longer than expected' Ride check card on a normal trip.

**Why:** `addSample` sets `_tripStartedAt ??= sample.at` and `_expectedSeconds ??= sample.etaSeconds` once, from whichever sample comes first, and `_tooLong` compares all later elapsed time against that one value. The first in-trip sample comes from Waiting's `_feedRideCheck`, which takes `_tracking.eta`. When the trip-start status event carries no new fix, DriverTrackingController rebuilds the eta with `etaSeconds: event.etaSeconds ?? eta!.seconds` (driver_tracking_controller.dart:174). That carries over the pre-trip ETA to pickup, which is about 20 s (the clamp minimum) or 0, together with the old fix's `locationAt`. With a small budget, `_tooLong` fires after about 3 minutes of normal driving. With a budget of 0, `expected <= 0` returns null on every sample, and because `??=` never replaces a 0, the off-route-by-time trigger is dead for that trip.

**Suggested fix:** Take the budget from a sample whose fix is newer than the trip start and whose ETA is positive, or use the larger of the ETA and the straight-line estimate. Do not keep a non-positive value: treat 0 or null as unknown and fall back to `_straightLineSeconds()`.

### M110. Emergency contact editor shrinks by twice the keyboard height and leaves a 40-140 px strip to edit in

`lib/features/safety/presentation/emergency_contacts_page.dart:296` (found by r2-rider4)

**What happens:** Rider adds a trusted contact on a 360x640 phone with a ~280 px keyboard: the scrollable form viewport is 640 - 560 - 36 = 44 px, floating 280 px above the keyboard. Name, phone, relationship, share-trips switch and Save show through a 44 px slit. On 390x844 iOS it is about 136 px.

**Why:** _ContactEditor (opened via MoveraSheet.show at :42) pads by `20 + MediaQuery.of(context).viewInsets.bottom`, and MoveraSheet already pads by the keyboard inset. The SingleChildScrollView keeps it from overflowing, but its viewport is the screen height minus 2x keyboard minus 36.

**Suggested fix:** Use only the fixed 20 px bottom padding, since MoveraSheet applies the keyboard inset.

### M111. Opening a Ride check card pops the Safety Kit sheet, which silently stops the rider's ongoing Safety Kit recording

`lib/features/safety/presentation/ride_check_card.dart:216` (found by r2-rider1)

**What happens:** The rider feels uneasy, opens the Safety Kit and taps Record audio, leaving the sheet open. Two minutes later the car stops off-route and the long-stop card opens. The kit is popped and the recording is stopped and saved. The rider sees the card with 'Record audio' and has to notice and tap again. Nothing was recorded in between.

**Why:** `_comeToFront` pops every route above the trip screen when a card opens. The Safety Kit tells the rider the recording keeps going until they tap Stop audio or close the kit ('safetyKitRecording'), so a rider who wants to keep recording leaves the kit open. When a trigger fires, popUntil closes the kit. The kit's dispose then calls `stopIfRecording(reason: 'sheet_closed')`. The recording ends at the moment the app has just detected something wrong, and neither the kit (now gone) nor the card says so. The card's Record row now shows 'Record audio'.

**Suggested fix:** Do not stop the recording when the kit is closed programmatically by the Ride check, or hand the running recording over to the card (the same audio service), so the card shows it as still recording.

### M112. When a Ride check card opens, it closes the Safety Kit sheet, and the kit's dispose stops the rider's ongoing recording

`lib/features/safety/presentation/ride_safety_kit.dart:146` (found by r2-rider3)

**What happens:** Mid-trip, the rider opens the Safety Kit and taps Record audio. The car stops off-route for 2 minutes and the long-stop card opens. The kit sheet is popped, the recording is stopped and saved, and the card shows 'Record audio · saved only on this phone' as idle. Audio of what happens next is lost unless the rider notices and starts recording again.

**Why:** RideCheckLayer._comeToFront pops every route above the trip screen when a card opens (ride_check_card.dart:212-217). That includes the Safety Kit sheet, a MoveraModalSheetRoute on the same navigator. The kit's dispose calls `_ctl.audio.stopIfRecording(reason: 'sheet_closed')`. A rider who started 'Record audio' in the Safety Kit because they felt unsafe has the recording stopped and finalised at the moment Ride check detects an anomaly (long stop, off route, possible crash). The card then offers 'Record audio' again as idle. The FLOW-6 rule, stop when the rider can no longer reach Stop, does not fit here: the app closed the sheet, not the rider, and the card has its own recording control.

**Suggested fix:** Do not stop the recording when the sheet is closed programmatically by the Ride check layer: pass a flag, or let the card take over the active recording. Alternatively, have _comeToFront skip routes whose dispose has side effects.

### M113. Safety Kit 'Contact 112' sends no SOS to Movera when the phone dialer cannot be opened

`lib/features/safety/presentation/ride_safety_kit.dart:167` (found by r2-rider3)

**What happens:** On a device that cannot place calls (Android tablet without a dialer, iPad, some in-app browsers), a rider in an emergency during a trip taps 'Contact 112' in the Safety Kit. launchUrl returns false, and the rider sees 'Could not open the system phone dialer.' Movera is not told either: there is no call and no SOS. That is the moment the in-app alert matters most.

**Why:** _call112 calls emergency.callEmergencyNumber() first and _ctl.sos() only after it. SystemEmergencyDialer.open throws EmergencyCallException whenever launchUrl(tel:) returns false or throws. That exception jumps to the outer `on EmergencyCallException` handler, which only shows a toast, so the SOS event for the ride is never posted. RideCheckController.call112 handles the same failure by still alerting the safety team (_sendAlert runs regardless of the dialer result), so the Safety Kit is the only path where a failed dial also drops the alert.

**Suggested fix:** Send the SOS whatever the dialer outcome (or before dialing), and report both results to the rider.

### M114. 'Automatically share every ride' can be switched on and Safety shows 'Every ride', but nothing ever starts a share when a ride starts

`lib/features/safety/presentation/trip_share_page.dart:94` (found by r2-rider3)

**What happens:** The rider turns on 'Automatically share every ride' with two contacts ticked and books a ride. The trip starts and nobody gets a link or share. The rider only finds out if they open Safety Kit › Share trip.

**Why:** TripSharePage lets the rider set `tripShareMode` to auto ('When a ride starts, selected contacts can follow it.'), and the Safety Hub status reads 'Every ride' (safety_controller.dart:105-107). No code reads `TripShareMode.auto` to call startShare: the only startShare caller is the manual Safety Kit button (ride_safety_kit.dart:225). The in-process mock server only stores the preference (safety_mock_api.dart:184-185), so in the shipped demo no share is ever created automatically. Trusted contacts are not following the ride the rider believes is being shared.

**Suggested fix:** When a ride reaches in-trip (or accepted) with tripShareEnabled and mode auto, call SafetyController.startShare once per ride. Otherwise document it as server-side and make the mock do it.

### M115. Trip-share contact checkbox (trip_share_page.dart:167-188): a failed save gets no rider feedback, editContact's error escapes unhandled, and a partial failure leaves the preference list and shareTrips inconsistent

`lib/features/safety/presentation/trip_share_page.dart:612` (found by rider4)

**What happens:** Offline rider unchecks a contact under "Trusted contacts": `setTripShare` fails silently (or succeeds), `editContact` throws unhandled; the checkbox snaps back to checked (or shows checked while the preference list no longer has the id) and the rider gets no error.

**Why:** The checkbox value is `prefs.tripShareContactIds.contains(id) || contact.shareTrips` (581-585). Its `onChanged` first calls `_ctl.setTripShare(contactIds: selected)` (612-614) and then `_ctl.editContact(contact.copyWith(shareTrips: value == true))` (615-619). `setTripShare` swallows failures into `controller.error` (safety_controller.dart:277-295) and this page never shows `error`; `editContact` has no generic catch, so a transport failure in `SafetyStore._write` (safety_store.dart:92-101 rethrows after restoring the cache) escapes the async callback as an unhandled exception. Because the two writes are independent, one can succeed while the other fails: unchecking a contact may remove the id from `tripShareContactIds` while `shareTrips` stays true, and the `||` keeps the box checked with no message.

**Suggested fix:** Wrap the handler in try/catch, show `controller.error`/a toast on failure, and keep a single source of truth (either the preference list or `shareTrips`) so the box reflects one flag.

### M116. Positional legacy ids collide after a delete, so deleting one custom place removes two and editing one overwrites another

`lib/features/saved_places/application/saved_places_controller.dart:170` (found by r2-rider2)

**What happens:** On Home, add a 'gym' place (A) and then a 'restaurant' place (B); neither gets an id. In Saved Places, delete A: B is stored as place_legacy_1. On Home, add a 'school' place (C): the list is now [B(place_legacy_1), C(no id, index 1)], so C also reads as place_legacy_1. Delete C in Saved Places and B disappears as well. Edit C instead and B's entry is overwritten with C's data while C's old entry stays.

**Why:** `_withIds` gives every custom place that has no stored id the id `place_legacy_$i`, where i is its current position in the list. Home's own add path (`HomePlacesController.applyResolved` case 'custom') appends `SavedPlaceData(title: type, type: type, address: address)` with no id, so places added from Home never have one. Once Saved Places writes the list, those positional ids are stored permanently (save and remove both persist the output of `_withIds`). After a delete shrinks the list, a place Home adds later lands at an index whose `place_legacy_<i>` id is already stored on another place. `remove` filters with `item['id'] != id`, so it drops every place with that id. `save` uses `indexWhere`, so it replaces the first place with that id instead of the one being edited.

**Suggested fix:** Assign a fresh unique id (`place_${newRequestId()}`) to id-less entries and persist it, rather than a position-derived id. Also give places added from Home an id.

### M117. Book-for-later pickup field is pre-filled with the English string 'Current location'

`lib/features/scheduled_rides/presentation/schedule_ride.dart:58` (found by rider2)

**What happens:** Swedish rider opens 'Boka senare': the 'Upphämtning' field shows 'Current location' instead of 'Nuvarande plats'.

**Why:** The pickup TextEditingController is created with `text: 'Current location'` (:57-58) and that controller is bound directly to the visible address field `_scheduleAddressField(controller: _pickupController, ...)` (:350-351). There is no L10n.place on the controller text, so the first thing the rider sees in the pickup box is English in fr/sv. The same literal is passed as the initial address of ConfirmPickupSpot at :184 (`? 'Current location'`), which then shows it raw (see the ConfirmPickupSpot finding). The screen is covered by test/l10n/l10n_screens_finish_test.dart ('Schedule a ride'), but that test only asserts one translated string is present and cannot notice the English default.

**Suggested fix:** Initialise the controller with L10n.current.currentLocation (and treat that translated value, or an empty value, as the 'current location' sentinel in resolveScheduledPoint), or keep the field empty and show the translated hint.

### M118. Arrive by on the fall-back night: the Duration-based pickup lands in the first copy of the repeated hour, but the booking reads that wall time as the second copy, so the rider is picked up 60 min late (edge case)

`lib/features/scheduled_rides/presentation/select_date_time.dart:123` (found by r2-rider-fixrev2)

**What happens:** I reproduced this with a throwaway widget test that drives ScheduleDateTimeSelector.choose in Arrive by mode, presses Continue, and converts the result with ZoneClock.toUtc as booking does. The file is deleted and git status is clean.

TZ=Europe/Stockholm, Stockholm pickup, now 2026-10-24 10:00Z, arrival 2026-10-25 03:10 (= 02:10Z), trip 80 min:
`arrival wall 2026-10-25 03:10 trip 80 -> pickup wall 2026-10-25 02:50 ; booked UTC 2026-10-25 01:50Z ; arrival UTC 02:10Z ; lead 20 min`
The correct pickup is 00:50Z. The rider is picked up 60 min late and arrives at 04:10 local, not 03:10. The old code gave wall 01:50 (23:50Z), 60 min early, never late. Any arrival and trip where arrival_utc - trip falls in [00:00Z, 01:00Z) on that night is affected, e.g. arrival 03:30 with trip 90.

TZ=America/New_York, Stockholm pickup, arrival 2026-11-01 02:10, trip 80:
`pickup wall 01:50 ; booked UTC 2026-11-01 00:50Z ; arrival UTC 01:10Z ; lead 20 min`
The correct pickup is wall 00:50 (23:50Z), which the old field arithmetic produced.

The UI says nothing about it, and the 'Estimated pickup' row shows 02:50 / 01:50.

**Why:** Commit 7137eee changed _pickupFor from wall-clock field arithmetic to `chosen.subtract(Duration(minutes: trip))`. The values on this screen are plain device-local DateTimes that hold the pickup zone's wall-clock fields (PickupSchedule docs: 'Times in and out are plain wall-clock DateTimes of timeZone'). Downstream, only the fields count. captureSchedule -> PickupSchedule.clampPickup rebuilds the value from y/m/d/h/min (stockholm_schedule.dart:42-44). ScheduledRideSession.confirm sends `WireTime.format(PickupSchedule(timezone).toUtc(at))` (scheduled_rides_controller.dart:64). ZoneClock.toUtc resolves a repeated wall hour to the LATER occurrence (zone_clock.dart:71-86). The choose() callers (home.dart:864, select_ride.dart:943/1145) pass the popped `_pickupAt` on, and they are converted the same way.

On a fall-back night in the device zone, subtracting real elapsed time from an arrival after the change can land in the FIRST (summer) occurrence of the repeated hour. Its wall fields (e.g. 02:50) are then booked as the SECOND occurrence, one hour later. Before the commit, field subtraction gave a wall time that ZoneClock maps to exactly `trip` minutes before the arrival, so this is a regression. The commit fixed spring-forward and broke fall-back. The new DST test and CI step (TZ=Europe/Stockholm) only cover 2027-03-28 spring-forward, so they cannot catch this.

The same thing happens when the device zone and the pickup zone differ. Duration arithmetic follows the DEVICE zone's DST rules, not the pickup zone's. A phone on America/New_York booking a Stockholm pickup on 2026-11-01 (the US fall-back, no change in Stockholm) is also booked 60 minutes late.

**Suggested fix:** Do the arithmetic in the pickup zone, not the device zone. Convert the arrival with `_schedule.toUtc(chosen)`, subtract `trip` minutes as a UTC Duration, and convert back with `ZoneClock.wallTime(widget.timeZone, …)`. Then floor to the 5-minute grid with fields. Where the floored wall time is ambiguous and ZoneClock would read it as the later occurrence, step back to the slot whose `toUtc` is at or before `arrivalUtc - trip`. Add a fall-back case (2026-10-25 03:10, trip 80) and a device-zone ≠ pickup-zone case to audit_fix_arrive_by_dst_test.dart.

### M119. Continue button stays disabled as 'Continuing…' after the category step returns or fails (needs Back to the address step to recover)

`lib/features/scheduled_rides/presentation/select_date_time.dart:126` (found by rider1)

**What happens:** Rider on Plan your ride -> Continue -> category cards -> taps back to change the time. The time screen now shows a greyed "Continuing…" button that never re-enables; the only way out is Back to the address step and re-confirming the pickup pin.

**Why:** `_goNext` sets `_continuing = true` (line 126) before calling `widget.onConfirm()` and nothing ever resets it. In `ScheduleRide` the selector is embedded (schedule_ride.dart:257-267) with `onConfirm: goToNextStep`, which pushes the category selector and, when the rider comes back without booking, just does `setState` (schedule_ride.dart:148-151). The rebuilt `ScheduleDateTimeSelector` is the same widget type at the same tree position, so its State (and `_continuing == true`) is kept. The button is built with `enabled = legal && !_continuing` (757) and label `_continuing ? continuing : continueLabel` (809). Reproduced with a throwaway widget test: after one tap and `onConfirm` returning, `ElevatedButton.enabled == false`, label `Continuing…`, and a second tap does not call onConfirm again (`AUDIT continue enabled after return: false; label: Continuing…` / `AUDIT confirms after second tap: 1`).

**Suggested fix:** Make `onConfirm` a `Future<void>` and reset `_continuing = false` (with setState) when it completes, or reset it in `didUpdateWidget`/when the route becomes current again.

### M120. Booking screen promises free cancellation before a driver is assigned and terms before booking; neither is true

`lib/features/scheduled_rides/presentation/select_date_time.dart:532` (found by r2-rider3)

**What happens:** At 23:15 the rider books the 23:50 ride (pickup 35 min away, inside the 60 min window) and immediately taps Cancel, before any driver is assigned. The sheet says 'Cancelling costs kr 50' and the fee is recorded. The booking screen had promised a free cancel before assignment, and no terms were shown before booking.

**Why:** The date/time step shows `cancelBeforeAssigned`: 'You can cancel without a fee before a driver is assigned. Final terms are shown before booking.' The fee actually charged (`ScheduledRideRules.cancelTermsFor`) depends only on minutes before pickup (free while `minutesBeforePickup >= freeMin`, default 60 or the zone's per-category rule). Driver assignment does not matter; the only exception is a missed pickup. Nothing in the scheduled SelectRide/checkout path shows the cancel terms before booking: `cancelTermsFor`/`cancelRule` are only used on the Upcoming and Terms pages.

**Suggested fix:** Replace the copy with the actual rule (`ReservationFormat.cancelRule` / cancelTermsFor on a draft). Show the cancel terms on the scheduled Select Ride CTA before booking.

### M121. Schedule Continue exposes a hard-coded English semantics label with no tap action, hiding the localized and busy text

`lib/features/scheduled_rides/presentation/select_date_time.dart:792` (found by r2-rider3)

**What happens:** A Swedish TalkBack user on Book for later hears 'Schedule Continue' in English, hears no 'Continuing…' busy state, and double-tapping does nothing because the node has no tap action. They cannot leave the date/time step.

**Why:** The Continue CTA on the date/time step is wrapped as `Semantics(container: true, label: 'Schedule Continue', button: true, enabled: enabled, child: ExcludeSemantics(child: ElevatedButton(onPressed: ...)))`. The literal label replaces the localized visible text (continueLabel = 'Continuer'/'Fortsätt', or 'Continuing…' while busy). ExcludeSemantics removes the ElevatedButton's tap action, and the outer Semantics has no onTap, so the node cannot be activated by assistive tech. test/scheduled_rides/phase81_schedule_continue_test.dart is titled 'Schedule Continue is accessible' but only does `tester.tap(find.bySemanticsLabel('Schedule Continue'))`, a pointer tap, so it passes either way.

**Suggested fix:** Drop the wrapper (the ElevatedButton already has correct semantics), or use a localized label plus `onTap: enabled ? _goNext : null`. Make the test assert SemanticsAction.tap.

### M122. 'Open settings' in the push primer calls Geolocator.openAppSettings, which throws UnsupportedError on web

`lib/shared/widgets/push_permission_primer.dart:86` (found by rider3)

**What happens:** Staging web build, rider taps 'Turn on' and declines the browser notification prompt. Next visit to Notifications shows 'Ride updates are off' -> 'Open settings'; tapping does nothing visible and logs `zone.error UnsupportedError: openAppSettings() has not been implemented on the web`.

**Why:** `_openSettings` defaults to `Geolocator.openAppSettings`. geolocator_web implements it as `throw _unsupported('openAppSettings')`. The primer is reachable on web in release-like builds (gate `enabled = !allowsMockTransport`): when the browser's `Notification.requestPermission()` answers 'denied' (or 'default'), `FlutterFirebasePushGateway.requestPermission` maps it to `PushAuthorizationStatus.denied`, `PushPermissionGate._register` stores `blockedBySystem`, and both the sheet (`_blocked`) and the Notifications screen banner then offer 'Open settings'. Tapping it throws inside the button callback; nothing opens, the rider gets no feedback, and the error is recorded as a crash by the zone handler. The location notice already handles this case correctly via `locationSettingsOpenerFor(isWeb: ...)` returning null, so the web branch was simply missed here.

**Suggested fix:** On web hide the settings action (or show copy explaining the browser's site-permission UI) the way `locationSettingsOpenerFor` does; wrap the call in try/catch and show a toast on failure.

### M123. Web FCM worker suppresses pushes when a tab is visible but never forwards them, so FirebaseMessaging.onMessage (foreground in-app push) never fires on web

`web/firebase-messaging-sw.js:75` (found by r2-rider3)

**What happens:** Production/staging web build with MOVERA_FIREBASE_* and VAPID set (as built in batch6-phase78-push.yml). The rider accepted ride updates and has the tab open. The backend sends 'driver arrived'. The SW sees a visible client and returns. No system notification appears, onMessage never fires, and no in-app toast is shown. The update is silently lost. Verified by reading the code; nothing was run.

**Why:** The worker loads no Firebase SDK (the test enforces no importScripts). In the Firebase JS SDK, the page's onMessage only fires when the messaging service worker posts the payload to window clients ({isFirebaseMessaging:true, messageType:'push-received'}). The browser delivers push events only to the service worker, never to the page. This worker sees a visible client and returns undefined. It shows no notification and calls no client.postMessage. The comment's claim that 'A visible Movera tab receives the message through onMessage instead' is false. FirebasePushService._attachInboundStreams subscribes to FirebaseMessaging.onMessage (firebase_push_service.dart:126), and that stream never emits on web, so PushCoordinator never shows the in-app ride update.

**Suggested fix:** When a client is visible, postMessage the payload to the clients in the Firebase internal format, or importScripts the Firebase messaging SW SDK and let it route foreground messages. Otherwise always show the notification.

## Low (185)

### L1. Documented live URL points at /-movera-rider/, the Pages build is published under /movera-rider-app/

`ARCHITECTURE.md:90` (found by rider2)

**What happens:** A reviewer or QA engineer opens the URL in ARCHITECTURE.md to verify the live build and gets a GitHub 404 instead of the deployed rider app.

**Why:** ARCHITECTURE.md line 90 gives the live site as `https://baccarisverige-ux.github.io/-movera-rider/`. The publish workflow rewrites the base href to `/movera-rider-app/` (publish-web-live.yml:124) and the repository/Pages project is movera-rider-app, so the documented URL 404s. Per the ground rules, docs and code disagreeing is a defect.

**Suggested fix:** Change the ARCHITECTURE.md URL to `https://baccarisverige-ux.github.io/movera-rider-app/`.

### L2. API_V1_MOCK.md is stale: it documents a 404->cancelledBySystem terminal, an X-Api-Version of v1 and legacy status names, but the code pauses polling with no status change, sends 0.4 and uses contract wire names

`docs/API_V1_MOCK.md:99` (found by r2-rider2)

**What happens:** The server forgets a ride (three 404s). Following the doc, QA expects the ride to end as cancelledBySystem. Instead the ride stays on its last status with polling stopped.

**Why:** ARCHITECTURE.md points to docs/API_V1_MOCK.md as the mock contract. That document says 'Three `404`s in a row end the ride as `cancelledBySystem`' (line 99) and '`X-Api-Version` | Always `v1` from `ApiClient`' (line 27). It also says POST /rides returns status `findingDriver`/`bookingRequested` (line 84). In the code, `_endNotFound` only pauses polling and marks the connection failed, with no status change (api_ride_realtime.dart:347-353). ApiClient sends `'0.4'` (api_client.dart:15), and the mock stores contract names `searching`/`requested`. A QA or backend engineer working from the doc expects a cancelledBySystem terminal (History entry, Home) and a v1 header; neither happens.

**Suggested fix:** Update API_V1_MOCK.md to the current behaviour (polling pauses with no client-invented status, header 0.4, contract status names), or change the code to match the documented behaviour.

### L3. Global UAT wallet step only sums two hand-added WalletLedger entries; WalletController.topUp and the Wallet-paid ride debit are never exercised despite the file's and UAT_CHECKLIST's claim

`integration_test/global_uat_flow_test.dart:51` (found by r2-rider3)

**What happens:** WalletController.topUp stops crediting (creditTopUp throws or is skipped), or a Wallet-paid ride is never debited. The 'Booking wallet reservations profile UAT' step in batch7-phase85, deep-safe-recertification and backend-readiness still passes.

**Why:** The file says it 'drives booking, wallet, reservations, and profile through their real controllers ... so a regression in any of them fails CI'. The wallet step calls `AppScope.instance.wallet.add(WalletEntry(...))` twice and asserts `balanceMinor == start + 20000 - 34900`, which only tests list summation in WalletLedger. It never runs WalletController.topUp (gateway create/confirm, idempotency, creditTopUp), chargeRide, or the wallet balance repository the UI reads. The booking in the same test uses paymentMethod 'Wallet' for 349 kr, and nothing checks that it is charged. In integration_test/ride_flow_test.dart:29 ('quote then book'), the quote comes from a separate InProcessMockClient and is never passed to submitFinding, so the 'then book' part does not use that quote.

**Suggested fix:** Call `WalletController.topUp(...)` with the mock gateway and assert the balance from `walletBalances.loadBalance()`. Complete the Wallet-paid ride through `chargeCompletedRide` and assert the debit.

### L4. iOS permission purpose strings exist only in English; no sv/fr InfoPlist.strings or CFBundleLocalizations although the app ships sv/fr and defaults Stockholm riders to Swedish

`ios/Runner/Info.plist:5` (found by r2-rider4)

**What happens:** A rider whose iPhone is set to Swedish opens Movera, which is in Swedish. The location prompt reads 'Movera uses your location while you use the app...' in English, and the same happens when they tap Record audio. Verified by reading the config.

**Why:** The app supports en, fr and sv (lib/l10n/app_*.arb), and the zone default (Q48) picks the language for Stockholm. The OS location and microphone prompts that iOS shows use NSLocationWhenInUseUsageDescription/NSMicrophoneUsageDescription from Info.plist. There is no sv.lproj/fr.lproj InfoPlist.strings and no CFBundleLocalizations (ios/Runner holds only Base.lproj). So a Swedish rider gets English system prompts in the middle of a Swedish UI, and iOS does not offer the app's languages in per-app Language settings.

**Suggested fix:** Add CFBundleLocalizations (en, sv, fr) and sv.lproj/fr.lproj/InfoPlist.strings with translated purpose strings.

### L5. QA_HOOKS.md (and its rule not to leave hooks ungated) is stale: moveraOpenSafety is deliberately exposed in public release builds as a navigation-only bridge

`lib/app/bootstrap.dart:76` (found by rider4)

**What happens:** An operator reading QA_HOOKS.md assumes `window.moveraOpenSafety` is absent on the public demo; on https://.../movera-rider-app/ `typeof window.moveraOpenSafety` is 'function' and calling it opens the Safety hub.

**Why:** docs/QA_HOOKS.md lists `moveraOpenSafety` among the hooks that public GitHub Pages release builds do NOT expose, and ARCHITECTURE.md states 'QA window.movera* hooks are gated (kDebugMode or --dart-define=MOVERA_QA=true)'. bootstrap.dart calls `installSafetyNavigationBridge(...)` outside the `moveraQaHooksEnabled` gate and `web_qa_hooks_web.dart` installs `window.moveraOpenSafety` with a comment that it is 'intentionally available in public web builds'; qa-live-rider-flow.yml even asserts it exists on public Pages. The code and the public workflow contradict the documented contract; one of them is wrong. The bridge can push the Safety hub over any screen from page script, so the doc readers' assumption that no navigation hook exists in release is false.

**Suggested fix:** Either gate `installSafetyNavigationBridge` behind `moveraQaHooksEnabled` (and drop the public-Pages step from qa-live-rider-flow.yml) or correct QA_HOOKS.md/ARCHITECTURE.md to list `moveraOpenSafety` as a release-available navigation bridge.

### L6. docs/API_V1_MOCK.md:27 says X-Api-Version is 'v1', but ApiClient sends '0.4', which matches the contract

`lib/core/api/api_client.dart:15` (found by r2-rider1)

**What happens:** A gateway configured from API_V1_MOCK.md to require X-Api-Version: v1 rejects every request from the app.

**Why:** The documented mock contract says ApiClient always sends `X-Api-Version: v1`. The code sends `'0.4'`, which matches contracts/openapi.yaml (`const: '0.4'`). The ride-quote body separately still carries `'apiVersion': 'v1'`. The document is out of date, so a backend team working from API_V1_MOCK.md would expect a value the client never sends.

**Suggested fix:** Fix the table row in docs/API_V1_MOCK.md to '0.4' (contract.json#headers).

### L7. Web auth-preview: a wrong OTP while an earlier session's tokens are still in sessionStorage expires the session and re-roots Sign in instead of showing 'wrong code'

`lib/core/api/api_client.dart:89` (found by rider1)

**What happens:** Web demo with `?auth_preview=1`: rider who signed in earlier in the tab types one wrong OTP digit; instead of 'wrong code' the screen jumps back to the first Sign in step, the stored session is gone and the last good location fix is wiped.

**Why:** `_send` enters the refresh/retry/expire path for any 401 whose request carried an access token (line 89); the comment relies on OTP verify never carrying one. `RideRestoreCoordinator` returns `SignIn()` when `AppEnv.current.authPreview && snapshot == null` (ride_restore_coordinator.dart lines 432-434, 449-452) without clearing tokens, and on web the tokens live in this tab's sessionStorage, so a reload with `?auth_preview=1` after an earlier sign-in reaches `PhoneVerify` with tokens present. A wrong code -> mock `401 invalid_otp` -> `_refreshAccess` (mock accepts any `mock-refresh-*`) -> retry -> 401 again -> `_expireSession` clears tokens, calls `onSessionExpired` (`LocationRepository.clearLastGoodFix()` + `showMoveraRoot(SignIn())`), then throws; `PhoneVerify` is unmounted so its `_error` is never shown.

**Suggested fix:** Exclude `/api/v1/auth/*` paths from the refresh/expire path (or let callers opt out), or clear tokens before showing the preview Sign in.

### L8. `PATCH /rides/{id}` offer raise / searching edit changes the fare, pickup and destination without `_touch`, so version, updatedAt, sequence and eventId stay unchanged

`lib/core/api/in_process_mock_client.dart:993` (found by rider3)

**What happens:** Demo flavor: rider raises the offer by 50 kr while searching; the projection's `version`, `updatedAt` and `eventId` do not move. A command sent from another tab/screen with the pre-raise `expectedVersion` is not refused as stale, and a polling consumer never sees a new event for the change.

**Why:** The non-routeChange PATCH branch (lines 947-1011) calls `_setFare(ride, fare + increase)` and rewrites `pickupAddress/pickupLat/pickupLng/destination*` but never calls `_touch(ride)`, unlike every other mutation (route change line 895, cancel via `_apply`, feedback line 646). The mock's own rule (lines 1351-1361) is 'one committed change: version + 1, new updatedAt, next sequence/eventId' and CONTRACT.md §1 requires a stale `expectedVersion` to be refused. After a raise the trip still reports the old `version`/`updatedAt`/`eventId`, so a second screen's `expectedVersion` from before the raise is accepted, `ApiRideRealtime` dedupes the projection by the unchanged eventId, and `updatedAt` misreports when the trip last changed. Reproduced: `AUDIT B2: fare 29100 -> 34100; version 1 -> 1; eventId ev_..._1 -> ev_..._1; updatedAt unchanged`.

**Suggested fix:** Call `_touch(ride)` after applying the offer raise / pickup / destination edit in that branch.

### L9. The Q40 pickup-move limit is checked per move against the current pickup, so chained moves after accept take the pickup past the limit without a cancel/rebook

`lib/core/api/in_process_mock_client.dart:1813` (found by r2-rider3)

**What happens:** With a 300 m limit and the driver on the way, the rider moves the pickup 290 m four times in a row. Each move is accepted, and the driver is sent about 1.2 km from the accepted pickup without the 'that's a new ride' refusal.

**Why:** After accept, the pickup may move only `maxPickupMoveMeters`. Both the client (`preview`: `ride.pickupLat` vs the new point) and the server (`_pickupMoveMeters`: `ride['pickupLat']` vs the body) measure from the pickup as it stands now, and each applied change overwrites it. The pickup the driver accepted is never kept, so repeating the change moves the pickup by the limit each time with no total cap.

**Suggested fix:** Store the pickup at accept (`acceptedPickupLat/Lng`) and measure every later move from it, on both client and server.

### L10. Mock safety PIN is predictable: on the web demo it is always one of 10 values ending in 000, and the mock saves it in plain text

`lib/core/api/safety_mock_api.dart:157` (found by r2-rider3)

**What happens:** On the GitHub Pages demo, Safety › PIN shows e.g. '7000'. Change PIN gives '3000', '0000' and so on, always ending in 000.

**Why:** `_newPin` sets `n = DateTime.now().microsecondsSinceEpoch % 10000`. On dart2js, `DateTime.now()` has millisecond precision (the microsecond part is 0), so `microsecondsSinceEpoch` is always a multiple of 1000 and `n` is `(ms % 10) * 1000`. Every PIN issued or rotated on the public web demo, the transport the Pages build actually runs, ends in 000: there are only 10 possible PINs, and the digit is just the last digit of the current millisecond. The rider page then says 'Your driver must confirm your PIN before starting the trip' over a code anyone can guess. The mock also writes the digits in plaintext to localStorage (`movera_safety_demo_v1`, persist() line 87-94), although safety_data_sources.dart:146-149 says web keeps the PIN 'in memory only (P-06) — never in this plaintext prefs blob'. Verified by reading only (no web test runner).

**Suggested fix:** Generate the mock PIN with `Random.secure().nextInt(10000)`. Do not persist the digits in the plaintext demo blob.

### L11. PickupSchedule.zoneNow builds the zone wall-clock as a device-local DateTime: for a Tunis pickup on an EU-DST phone, during 02:00-02:59 Tunis on the EU spring-forward day, the earliest legal pickup is pushed an hour late

`lib/core/config/zone_clock.dart:60` (found by rider2)

**What happens:** Rider with a Swedish phone books a reservation in the Tunis zone for 2026-03-29 02:30 Tunis time (instant 01:30Z): `wallTime('Africa/Tunis', instant)` -> `DateTime(2026,3,29,2,30)` in Europe/Stockholm does not exist -> shows 03:30. The reverse mapping of the shown value then lands on a different instant than the one stored.

**Why:** `wallTime` computes the correct zone wall-clock components and then constructs `DateTime(year, month, day, hour, ...)` with the local-time constructor. Dart resolves a non-existent local time (the device's spring-forward gap) by shifting it, so when the device time zone differs from the zone's (RiderZones has Europe/Stockholm, Europe/Paris, Africa/Tunis; Tunis has no DST) the picker shows the wrong hour. `toUtc` (lines 74-86) uses `DateTime.utc`, so the round trip is asymmetric. Also the doc comment on `toUtc` says the summer offset is used in the non-existent hour, but the two-step guess yields the winter offset: wall 02:30 Stockholm on 2026-03-29 -> asUtc 02:30Z -> offsetAt = +2 -> guess 00:30Z -> offsetAt(00:30Z) = +1 -> 01:30Z (= 03:30 wall), not 00:30Z.

**Suggested fix:** Return `DateTime.utc(local.year, ..., local.millisecond)` (a UTC-flagged carrier of wall components, which never shifts) and have the pickers treat it as offset-free; fix the toUtc doc comment or the algorithm to match.

### L12. Telemetry version comment says CI passes MOVERA_APP_VERSION, but no workflow does, so every release-like build reports appVersion 'dev'

`lib/core/constants/app_version.dart:1` (found by r2-rider1)

**What happens:** Every crash from the signed production APK is posted to /api/v1/telemetry/crashes with appVersion 'dev', so operators cannot tell which release crashes. Verified by grep.

**Why:** CrashReporter attaches appVersion to every crash/telemetry record (crash_reporter.dart:24). The constant's contract is that CI passes the pubspec version with --dart-define=MOVERA_APP_VERSION. None of the production/staging builds in .github/workflows (android-release-signing, phase72/73/74/78/80/85, backend-readiness-gate) pass it, so release telemetry can never be told apart by version.

**Suggested fix:** Pass --dart-define=MOVERA_APP_VERSION=$(grep '^version:' pubspec.yaml ...) in every release build step, or derive it from package info.

### L13. docs/QA_HOOKS.md still lists moveraOpenSafety as absent from release builds, but code and CI intentionally expose a navigation-only bridge

`lib/core/debug/web_qa_hooks_web.dart:67` (found by rider3)

**What happens:** On the public GitHub Pages build any page script (or the Maps JS SDK) can call `window.moveraOpenSafety()` and navigate the rider to the Safety hub; QA_HOOKS.md promises this surface is absent.

**Why:** docs/QA_HOOKS.md:3-11 states public release builds do not expose `moveraOpenSafety` and that hooks install only under kDebugMode or MOVERA_QA. `installSafetyNavigationBridge` sets exactly that global without any gate, and bootstrap calls it unconditionally (lib/app/bootstrap.dart:76-78) outside the `if (moveraQaHooksEnabled)` block (lines 82-85). The gated `installSafetyQaOpener` (line 52) writes the same property name, so in QA builds whichever runs last wins. The code comment says this is intentional, so either the record or the code is wrong; per the audit rules a place where code does not do what the decision document says is reportable.

**Suggested fix:** Either gate the bridge with moveraQaHooksEnabled (and use the gated installSafetyQaOpener only), or correct docs/QA_HOOKS.md / ARCHITECTURE.md to state that moveraOpenSafety is a public navigation-only hook.

### L14. A web JS flight stopped by a tap leaves MapView.pose at the flight's starting pose, so the next stepped glide starts from the wrong place

`lib/core/maps/map_camera_motion.dart:86` (found by rider-j8)

**What happens:** On the web Home map, the rider taps recenter and taps the map (for example a marker) halfway through the 1 s flight. The camera stops mid-way, but pose still holds the pre-recenter view. The next follow update (a GPS fix) starts a Dart glide whose first frame jumps the camera back toward the old view before gliding to the target.

**Why:** While a JS flight runs, view.easing is true, so CustomGoogleMap._onMove ignores every camera report and view.pose stays at the pose from before the flight. On the web, Dart only learns where the camera is when the flight lands (_jsGlide sets pose = goal). If the flight is cancelled, interrupt() calls RiderMapBridge.cancelFlight and clears easing. _jsGlide's finally block skips its work because the generation changed. view.pose is never refreshed. A tap without a drag (pointerdown on .gm-style sets touching=true and interrupts) produces no further camera report. It also does not set movedByHandAt, so follow updates are not held. The next follow glide or 450 ms fitBounds ease runs on the Dart loop from view.pose, which is the pre-flight origin.

**Suggested fix:** When a JS flight is cancelled, read the live camera into view.pose, for example by having cancelFlight return the current pose or by calling controller.getVisibleRegion/zoom, or mark pose unknown so the next report is accepted.

### L15. A recenter that joins a running follow glide is stepped on the Dart timer on the web and keeps the old glide's 240-frame cap, which can cut the flight short

`lib/core/maps/map_camera_motion.dart:318` (found by rider-j8)

**What happens:** On web Safari, the Home map is gliding after a stream of GPS follow fixes when the rider taps recenter. The 1 s locate flight runs on the Dart 16 ms timer (the stutter the JS path exists to avoid). If the follow glide was already near frame 240, the flight lands with a jump after a fraction of a second.

**Why:** When easeCameraTo gets a flight-length goal (>= 600 ms, for example animateCamera(follow:false) from a recenter) while a damped follow glide is running, it converts that glide in place: it sets _flight and resets _flownMicros to 0. It never hands the flight to RiderMapBridge.flight, although the comment at lines 336-338 says web flights run on the browser frame clock so they do not stutter on a Dart timer in Safari. The loop variable `frame` in _glide also keeps counting from the start of the old glide, and the flight branch ends with `last = after >= 1 || frame >= _maxEaseFrames`. If the follow glide had already run about 180 frames (it was retargeted repeatedly without settling), the new 1 s flight is cut off after the remaining frames and snaps to its goal.

**Suggested fix:** When a flight-length goal arrives during a follow glide, interrupt and start a fresh flight (JS on the web), or reset the frame counter when converting to a flight.

### L16. Road-route cache is unbounded and gets a new entry every 10 s of a live ride (driver position is part of the key)

`lib/core/maps/routing_service.dart:77` (found by r2-rider3)

**What happens:** With the real /api/v1/routes backend, which returns road polylines, a rider takes several rides in one long web or PWA session. A 30-minute trip adds about 180 entries of a few hundred GeoPoints each, never freed. Memory grows by MBs per ride and adds to the web map's footprint. The in-process mock returns 2-point lines, so the demo grows slowly, but the pattern is the same. Not run; traced by reading the code.

**Why:** roadLine stores every resolved road geometry in a per-RoutingService map that is never evicted (`cache[key] = points`). The key is built from the endpoints at 5 decimals. AppScope holds one RoutingService for the app's lifetime (di.dart:191-192). Waiting's paintIfDue calls _refreshRoadRoute at most every 10 s (waiting_for_driver.dart:2097-2102). Its endpoints are the driver's live position and the pickup or destination (lines 2328-2357), so each refresh while the driver moves is a new key and a new cached polyline. Nothing ever reads these stale driver-origin entries again. With a real route provider each entry can hold hundreds of points, so memory grows with every ride in a session.

**Suggested fix:** Bound the cache: an LRU of a few dozen entries. Another option is to skip caching for requests whose origin is a live driver position.

### L17. MotionEngine lerp window is anchored at the previous fix's timestamp, so with fixes 420 ms or more apart t clamps to 1 and the home puck snaps between raw smoothed fixes (pose heading is unused)

`lib/core/motion/motion_engine.dart:47` (found by rider2)

**What happens:** On the home map the blue rider dot and heading cone jump between 1 Hz fixes rather than easing across the 420 ms window.

**Why:** ingest() is called once per delivered fix (HomeController._deliverFix, lib/features/home/application/home_controller.dart:518) and passes `startedAt: _from!.timestamp` with a 420 ms window. `_from` is the previous accepted sample, whose timestamp is at least one fix interval (typically >= 1 s) old, so `now - startedAt` always exceeds 420 ms and the interpolator clamps to t=1, returning `_to` verbatim. There is no ticker that calls lerp between fixes, so the 'interpolation' is a no-op and the rider marker snaps to each raw smoothed point; heading likewise jumps. Not a crash, but the animation math does not do what the component is for.

**Suggested fix:** Record `startedAt = clock` when a new sample arrives and expose a `poseAt(now)` used by a frame ticker; or drop the interpolator if snapping is intended.

### L18. Polling drops fresh driver fixes whose coordinates did not change, so a driver stopped on the way to pickup shows 'Updating location…'

`lib/core/realtime/api_ride_realtime.dart:205` (found by r2-rider4)

**What happens:** In a release build the driver waits at the pickup and the phone reports the same coordinates every few seconds. About 25 s later the rider's Waiting sheet switches to 'Updating location…' and stays there while the driver waits, although the server has fresh fixes.

**Why:** The 'nothing changed' short-circuit compares version, updatedAt, status and lat/lng, but not the fix time (`location.at` from `driverLocation.measuredAt` / `locationAt`). Location-only updates keep the version (and, in the documented stand-in, updatedAt) unchanged. So when the driver is stationary, for example waiting at the pickup or stopped at lights, every new fix with identical coordinates is swallowed and `locationAt` never advances. DriverTrackingController's 5 s stale check then marks the ETA stale after `DriverEta.staleAfter` (25 s) and shows 'Updating location…' / 'Waiting for fresh location' even though fresh fixes are arriving.

**Suggested fix:** Include the fix timestamp (and the eventId or sequence) in the no-change comparison, and track `poll.lastLocationAt`.

### L19. A driver drop followed by a re-offer within one poll is labelled an admin reassign, so the rider never sees the 'driver cancelled' notice

`lib/core/realtime/api_ride_realtime.dart:299` (found by r2-rider4)

**What happens:** The driver cancels before pickup and dispatch sends the trip to the next driver within about 2 s. The rider's poll sees `offered` with kind trip_projection. Waiting treats it as an admin reassign (Q13 path): no 'your driver cancelled' notice, only a silent return to searching.

**Why:** When a matched trip comes back as searching or offered, `_poll` calls `_reassignedByAdmin(ride, explicitKind)` (line 198) to decide between a driver drop and an admin reassign. With no `cancellation.actor` in the projection (the mock never sets one for the non-terminal driver cancel → searching, see `_apply` line 1426, which only fills it for terminals), the check falls back to `explicitKind != null && explicitKind != RealtimeKind.driverCancelled`. `explicitKind` is the kind of the latest committed event (`envelope['kind'] ?? ride['eventKind']`), not the kind of the event that ended the match. Dispatch normally re-offers the trip right after a driver drops it (`send_offer`, kind `trip_projection`). If that happens inside the 2 s poll window, the poll sees status `offered` with kind `trip_projection` and labels the driver drop as an admin reassign. The event then carries `reassignedBy: admin` and kind `trip_projection` instead of `driver_cancelled`, so the rider is never told their driver cancelled. Reproduced with a throwaway test against InProcessMockClient: after driver_to_pickup, `POST /status {command: cancel, actor: driver}` then `{command: send_offer, actor: system}`, then resync. Output: `status=RideStatus.cancelledByDriver kind=trip_projection adminReassign=true server=offered cancellation=null`.

**Suggested fix:** Decide driver drop or admin reassign from the event or command that left the matched state, or from `cancellation.actor`. Do not use the newest event's kind. When the polled projection cannot tell, default to the driver-cancelled notice, or read `GET /trips/{id}/events?after=` for the skipped events.

### L20. After a reload, the mock carries on with a ride the in-memory stand-in server no longer has, ignoring every 404

`lib/core/realtime/mock_ride_realtime.dart:275` (found by r2-rider2)

**What happens:** On the public demo, the rider reloads while 'Finding a driver'. 25 s later a driver is 'found' and the trip completes, but the server has no such ride: route changes and the rating/tip POST fail with 404, and the completion screen shows that feedback could not be saved.

**Why:** The class contract says every step it shows is first committed on the stand-in server 'so the server projection and what the rider sees agree'. But `_enqueue` swallows every error, and `_assignNow` goes on to emit driverAssigned whatever `_persistAssignment` returned. The other steps (`_commit`) are fire-and-forget before the event is added. The in-process server keeps rides only in memory (ApiClient creates a fresh `InProcessMockClient` per page load and nothing re-seeds `rides`). So after a public Pages reload during Finding, the restored search runs on a ride the server does not have: POST /status answers 404, the error is ignored, and the rider is moved to Waiting with a made-up driver. The trip then plays out locally, and at the end POST /feedback answers 404. The same applies when the server refuses a commit for any other reason, for example a rider cancel that already landed.

**Suggested fix:** Have `_enqueue` return the outcome and only emit a step whose commit succeeded (or resync from the server on refusal); for the demo, persist the mock's rides with the snapshot or re-seed the stand-in from the restored snapshot.

### L21. Mock driver never learns a pickup moved by a route change; it drives to and 'arrives' at the old pickup

`lib/core/realtime/mock_ride_realtime.dart:379` (found by r2-rider2)

**What happens:** After a driver accepts, the rider moves the pickup pin 250 m. The driver marker stops 250 m from the new pin and the sheet says 'Your driver has arrived at the pickup point'.

**Why:** The mock's GPS approach and `_etaSeconds` use `_pickupLat`/`_pickupLng`, which are set only once by `_hydratePickup()` after assignment. When the rider moves the pickup after accept (Q40, allowed up to maxPickupMoveMeters while accepted/driverToPickup), Waiting `_applyRouteChange` updates the tracking controller's pickup and the mock's destination only. It cannot update the mock's private pickup, and nothing re-reads it. The mock keeps walking to the old point and emits driverWaiting plus the 'arrived' signal within 50 m of the *old* pickup.

**Suggested fix:** Expose a pickup setter (as for the destination) and set it from `_applyRouteChange`, or re-hydrate the pickup from the server after a route change.

### L22. Mock realtime sends the ETA to the pickup during the trip, so the in-trip 'Arrive by' moves later as the car nears the destination

`lib/core/realtime/mock_ride_realtime.dart:630` (found by r2-rider2)

**What happens:** Demo build, 5 km trip. At boarding the sheet shows 'Arrive by <now+20s>'. On the last tick before drop-off it shows 'Arrive by <now+~8 min>' (about 4.2 km back to the pickup at 8.3 m/s), the opposite of the real progress.

**Why:** `_emit` attaches `_etaSeconds()` to every event, including the in-trip `tripInProgress` ticks (line 600). `_etaSeconds` always measures from the driver to `_pickupLat/_pickupLng`. `DriverEta.fromFix` prefers a supplied `etaSeconds` over its own destination distance (`seconds = etaSeconds ?? secondsForDistance(distance)`). So `_tripHeadline` shows 'Arrive by now + time back to the pickup', and the destination time pin does the same. A destination change mid-trip has no effect on it. Ride check also seeds `_expectedSeconds` from this value.

**Suggested fix:** While on board, measure to the destination (through the remaining stops) in `_etaSeconds`, or send no etaSeconds so DriverEta uses the destination distance.

### L23. Trip completion silently stops a Ride check recording while the card, with its Stop control, is still open on the summary

`lib/features/active_ride/application/active_ride_controller.dart:371` (found by r2-rider1)

**What happens:** Off-route card is up and the rider taps Record audio. The driver then taps Finish (an 'asked to leave the car' situation). markCompleted stops and saves the recording. The card on the summary now shows 'Record audio' with no message, and anything said after Finish is not recorded.

**Why:** `markCompleted` (called from Waiting._openCompleted, waiting_for_driver.dart:712) always calls `_stopSafetyRecording()`, which calls `SafetyController.stopRecordingForRideEnd()` → `audio.stopIfRecording`. The audio service is shared with RideCheckController (`RideCheckController.forSafety` uses `safety.audio`), so a deviceOnly Ride check recording is stopped too. The FLOW-6 rationale (lines 464-466: 'once the ride is over the rider can no longer reach Stop audio') does not hold for Ride check. The unanswered card moves to RideCompleted (RideCheckLayer at ride_completed.dart:443) and keeps its Record/Stop row. The rider gets no note. The row just flips from 'Recording 1:42 · Tap to stop' back to 'Record audio', in the middle of the incident the card is about.

**Suggested fix:** Skip the ride-end stop for a deviceOnly recording while a Ride check card is open for that ride; let `_close` stop it. Or set a recordingNote telling the rider the recording was stopped and saved.

### L24. History record time is overwritten with the Done-tap time; receipt date uses savedAt which lifecycle refreshes move

`lib/features/active_ride/application/active_ride_controller.dart:454` (found by rider3)

**What happens:** Trip completes at 14:00; the rider leaves the app on the summary, backgrounds it a few times and taps Done at 14:40. Ride History lists the trip at 14:40, and after a reload the receipt's 'Date and time' shows the last time the app was backgrounded.

**Why:** `markCompleted` archives the trip with `endedAt` defaulting to now (completion time) (377-382, on_demand_ride_history_store.dart 197 `final ended = endedAt ?? DateTime.now();`). When the rider taps Done, `closeCompletedRide` archives again with the same `reservationId` and no `endedAt` (453-457), so `archive` replaces the record (146-148) and its `scheduledPickupAt` becomes the time the rider left the summary, which can be much later. Separately, the receipt's 'Date and time' comes from `DriverRepository._completedAtLabel(ride.savedAt)` (driver_repository.dart 59), and `savedAt` is rewritten by `persistCompletedStatus` (395-400) on each payment/rating event and by `RideSnapshotStore.touchCurrent` on every background/pagehide (ride_snapshot_store.dart 452) because completed-surface statuses are not terminal; after a restore `LastCompletedRide.remember(snapshot)` (ride_restore_coordinator.dart 383) therefore shows the last backgrounding time, not the completion time.

**Suggested fix:** Record a completion timestamp in the snapshot when `markCompleted` runs and pass it as `endedAt` on every later archive and to the receipt.

### L25. After a route-change PATCH whose response was lost, a later route change shows and reports a locally computed difference, not the server's differenceMinor

`lib/features/active_ride/application/route_change_controller.dart:66` (found by r2-rider4)

**What happens:** A first destination change times out on the client after the server applied it and captured +49 kr. The rider sees 'Couldn't update route' and tries again. The second quote's sheet says '+49 kr charged now to Visa' and the snackbar repeats it, but the server's difference is 0 and nothing is charged.

**Why:** `differenceKr` is `newPriceKr - oldPriceKr`, where `oldPriceKr` is the device's `_price`. The server charges `differenceMinor = newMinor - current fare`. The client parses that value into `quote.differenceMinor` but never shows it, and `showRouteUpdated` uses `updated.price - ride.price` as well. When the device price lags the server, the rider is shown a wrong charge. This happens when a PATCH reached the server but its response was lost: `_send` reports `network`, Waiting keeps the old route and price, and it never reads the route back from the projection.

**Suggested fix:** Show `quote.differenceMinor` (the server's), and after a lost PATCH response re-read the trip projection before offering another change.

### L26. A route change committed on the server but whose PATCH response is lost (15 s timeout or network drop) is reported as failed, and Waiting keeps the old route and price unless the rider retries

`lib/features/active_ride/application/route_change_controller.dart:350` (found by r2-rider4)

**What happens:** In trip, the rider changes the destination and confirms +kr 60. The PATCH lands but the response is lost, and the rider sees 'Couldn't update the route. Try again.' and closes the picker. The driver drives to the new destination and the card is charged kr 60, while the rider's map and price still show the old trip. Traced by reading the code.

**Why:** `apply` maps any non-ApiError (ClientException) and any retryable ApiError (TIMEOUT, NETWORK, 5xx) to `RouteChangeFailure.network`. Waiting's snapshot, map, destination and price stay as before. The PATCH may have been applied: the server changed the destination, notified the driver and charged the difference. Realtime projections are never read for the route, so Waiting keeps showing the old destination and price for the rest of the ride unless the rider retries.

**Suggested fix:** For a retryable apply failure, re-send the same request (the key is stable) or re-read the projection and adopt the server's route and fare before telling the rider it failed.

### L27. The in-trip status pill (unflexed Row, rider_in_trip_panel.dart:76) overflows on narrow phones at 2x text scale

`lib/features/active_ride/presentation/rider_in_trip_panel.dart:85` (found by r2-rider1)

**What happens:** 320 px phone, trip approaching dropoff, 2x text: about 190 px is available for the text, while 'NEAR DESTINATION' needs ~224 px and Swedish 'NÄRA DESTINATIONEN' ~257 px. RenderFlex overflow, and the pill text runs past the pill. The Swedish label also overflows at 360 px. The in-trip state is not rendered by the text-scale tests.

**Why:** The pill is `Container(padding 10/6) > Row(mainAxisSize.min, [Icon 14, 6, Text(UPPERCASE, 11px w700, letterSpacing 0.7)])` in a Column inside an Expanded that also has to leave room for the share button. The Text has no Flexible, maxLines or FittedBox.

**Suggested fix:** Make the Text Flexible with maxLines: 1 and ellipsis (or use FittedBox.scaleDown).

### L28. Change route shows 'Set your Home/Work' rows that do nothing when tapped

`lib/features/active_ride/presentation/route_change_flow.dart:69` (found by r2-rider2)

**What happens:** A rider with no saved Work opens Change route during a ride and taps 'Set your Work': nothing happens, with no sheet and no message.

**Why:** RoutePickerPage always renders Home and Work rows. When the address is unset, the row is styled as an action ('routeSetFavourite' in accent colour) and calls `widget.onSetFavourite`. The live-ride Change route flow passes `onSetFavourite: (_) async => null`, so tapping the row returns null and `_setFavourite` returns silently.

**Suggested fix:** Hide the set-favourite rows when no handler is available (make onSetFavourite nullable), or wire it to the address sheet.

### L29. In EUR/TND zones, route changes under 0.5 major units are shown as 'Same price' and skip the card confirmation step, though the difference is charged or refunded

`lib/features/active_ride/presentation/route_change_sheet.dart:93` (found by r2-rider2)

**What happens:** In Paris (EUR) the rider moves the destination slightly. The quote goes from 18.20 € to 18.60 €. The sheet says 'Same price' next to 18.60 € and confirms with no payment step, and the card is charged 0.40 € more.

**Why:** The sheet treats |newPrice − oldPrice| < 0.5 as no change: the copy says 'Same price', the struck-through old price is hidden and the payment step is skipped. In EUR or TND zones (Q7: the trip's currency), fares have cents or millimes, so a real change of, for example, 0.40 € is presented as the same price. apply() still sends expectedTotalMinor = the new total, and the server charges the difference. The same threshold hides the difference in showRouteUpdated (route_change_flow.dart:185).

**Suggested fix:** Compare minor units (newTotalMinor vs the booked total in minor units) and treat any non-zero difference as a change.

### L30. A no-show or other pre-trip terminal status stays hidden behind the 'Your driver has arrived' sheet until the rider dismisses it

`lib/features/active_ride/presentation/waiting_for_driver.dart:396` (found by r2-rider1)

**What happens:** The driver arrives and the arrived sheet opens. The rider does not come out. After 5 minutes the driver marks no-show, and tracking reports noShow, which is queued because the route is not current. The rider looks at the phone and sees 'Your driver has arrived · MVR 204', with no hint that the ride has ended as a no-show and may carry a fee. Only after swiping the sheet away do the no-show sheet and Home appear.

**Why:** The arrived sheet opens when the driver reaches the pickup (`_maybeAnnounceArrival`) and is closed in code only when the trip starts (lines 396-403). Terminal statuses go through `_queueStageNavigation` / `_drainStageNavigation`, which refuse to act while `!_routeIsCurrent` (line 525), and the arrived sheet is a modal route above Waiting. No-show is the terminal that by definition happens while the driver is waiting at the pickup, which is exactly when this sheet is up. The rider therefore keeps seeing 'Your driver has arrived', with the driver's name and plate, after the server has closed the trip. History archival and the snapshot clear are also held back until dismissal.

**Suggested fix:** Also close `_arrivedSheetRoute` (by reference, as for trip start) when a terminal or cancelledByDriver status arrives, then drain the stage navigation.

### L31. In-trip 'Arrive by HH:MM' on the sheet freezes because the rebuild signature ignores ETA changes during the trip

`lib/features/active_ride/presentation/waiting_for_driver.dart:430` (found by r2-rider1)

**What happens:** I reproduced this with a throwaway widget test: an in-trip Waiting, emit with etaSeconds 600 shows 'Arrive by 01:47'. A later fix with etaSeconds 3600 still showed 'Arrive by 01:47' (expected about 02:37). The rider stuck in traffic is told they will arrive 50 minutes earlier than the live ETA.

**Why:** _onLiveTick rebuilds only when _sheetSignatureFor changes. That signature uses eta.headline() and eta.subtitle(), which return the constant 'Ride in progress' and 'to drop-off' copy during the trip (driver_eta.dart:99-101, 117-121). The sheet headline and RiderInTripPanel headline come from _tripHeadline, computed from eta.seconds at build time (1665-1669). So an ETA change during the trip never rebuilds the sheet, and its arrival time stays at the value from the last rebuild. The map's destination time pin does update (paintIfDue -> _syncTimePins), so the map and the sheet disagree.

**Suggested fix:** Include the in-trip arrival minute (or eta.seconds rounded to a minute) in _sheetSignatureFor.

### L32. 'Driver has arrived' modal pops up again after every reload during the waiting stage

`lib/features/active_ride/presentation/waiting_for_driver.dart:463` (found by r2-rider1)

**What happens:** The driver arrives, and the rider dismisses the arrived sheet and walks out. The phone browser reloads. The 'Your driver has arrived' sheet opens again over Waiting, and again after each later reload.

**Why:** _maybeAnnounceArrival is documented as 'say it once and never again for this ride', but `_arrivalAnnounced` lives only in State memory. A restored Waiting starts tracking at driverWaiting (via _knownStatus). The first live tick passes `_tracking.status == RideStatus.driverWaiting`, so the arrived sheet opens again on top of the restored screen, even though the rider already dismissed it before the reload.

**Suggested fix:** Persist the announced flag per rideId (for example in the snapshot or session storage) and check it before showing the sheet.

### L33. Route change and 'change destination instead' are offered on scheduled live rides but can never succeed

`lib/features/active_ride/presentation/waiting_for_driver.dart:1004` (found by r2-rider1)

**What happens:** During a scheduled ride the rider taps 'Change destination instead' on the cancel sheet, picks a new address and taps See new price. The result is always 'couldn't update the route' and the ride continues unchanged.

**Why:** _routeEditable depends only on tracking status, so the ⋯ buttons (_openDetails) and the cancel sheet's offerDestinationChange are enabled for ReservationLiveRide pages too. _currentRide() builds a RideSnapshot whose rideId is the local reservation id. RouteChangeController.preview then posts /api/v1/rides/<reservationId>/route-quote. Reservations are device-local (LocalReservationRepository), so the server has no such ride and answers 404, which _send maps to RouteChangeFailure.network ('route update failed'). The rider is offered an action that always fails, with a misleading network error, and the map is parked and rebuilt each time.

**Suggested fix:** Disable route editing when widget.realtime/onCancel indicate a reservation-backed page, or route it through the reservation controller.

### L34. A rebuilt Waiting map (after a route change) shows no car until the next tracking event, which never comes if the feed is already quiet and stale

`lib/features/active_ride/presentation/waiting_for_driver.dart:2031` (found by r2-rider1)

**What happens:** The driver is waiting at the pickup and the rider changes the destination. When the route sheet closes, the map shows pickup and destination but no car until the driver's app sends another fix.

**Why:** _changeRoute parks the map, which removes _WaitingRideMap, and then rebuilds it. The new _WaitingRideMapState builds its markers in initState and _prepareMapVisuals using _currentDriverPosition(), and that reads _driverAnimTo. _driverAnimTo is filled only by _updateDriverAnimation from paintIfDue, which runs only on the next _onLiveTick. The tracking controller already holds the driver's last fix (tracking.eta), but the new map does not use it. If the feed is quiet (driver standing at the pickup with no new fix), the car stays off the map.

**Suggested fix:** Seed the animation from widget.tracking.eta in initState (call _updateDriverAnimation, or paintIfDue after the first frame).

### L35. Pre-trip 'Arrive by' destination pin ignores the stops the rider added

`lib/features/active_ride/presentation/waiting_for_driver.dart:2232` (found by r2-rider1)

**What happens:** While the driver is on the way, the rider adds a stop 5 km off the direct line. The 'Arrive by 08:19' pin over the destination stays at 08:19.

**Why:** Before boarding, `_syncTimePins` computes the arrival as now + minutes to pickup + `estimatedTripMinutes(pickup, destination)`, a straight pickup-to-destination estimate. `widget.stops` is not used, so adding a stop (or several) never moves the shown arrival time.

**Suggested fix:** Sum the estimate over pickup → stops → destination.

### L36. Driver car (and Finding's nearby cars) never rotate on web: Marker.rotation is ignored by google_maps_flutter_web

`lib/features/active_ride/presentation/waiting_for_driver.dart:2302` (found by r2-rider1)

**What happens:** On the web demo, the driver heads east along a street towards the pickup, or the trip runs west. The car icon slides sideways, still pointing north, instead of facing where it is driving. Nearby cars on Finding likewise ignore their bearing. On Android and iOS the same code rotates correctly. Not run; read from the plugin source.

**Why:** Waiting computes an interpolated heading for the car and passes it as `rotation: _currentDriverHeading()` with `flat: true`. Finding passes `rotation: vehicle.bearing` (finding_drivers.dart:433). google_maps_flutter_web 0.5.14+2 never maps rotation or flat onto the JS marker (convert.dart:516: "Flat and Rotation are not supported directly on the web."). The top-down car bitmap (MoveraVehicleMarker, headlight dot at the top) therefore always points north on the web. Home already handles this plugin gap by pre-rotating its puck bitmaps on web (home.dart:1521-1541, 1575-1583). The driver markers do not, so the heading work in _bearingDegrees and lerpHeading has no visible effect on the main web platform.

**Suggested fix:** Reuse Home's approach for the car on web: a small cache of pre-rotated car bitmaps per heading bucket, with heading minus the map bearing. Give those icons explicit width/height or asset URLs so the blob leak above is not made worse.

### L37. Share-trip button on Waiting and in-trip panels is a 40x40 target, below the 44 px floor

`lib/features/active_ride/presentation/waiting_sheet_bits.dart:84` (found by r2-rider4)

**What happens:** A rider in a moving car tries to share the trip from the in-trip panel and misses the 40 px circle. The tap lands on the sheet or the headline instead.

**Why:** WaitingShareButton is `Padding(EdgeInsets.all(10), child: Icon(size: 20))` inside a circular InkWell, so the hit area is 40x40. A11y.minTapIOS documents 44 as 'the floor for every tap target', and MoveraIconButton uses 48. This button is in the pickup header (_fixedPickupHeader) and the in-trip panel header, a main safety action.

**Suggested fix:** Constrain to A11y.minTap (48) or wrap in MoveraHitArea.

### L38. Driver card 'Message' button Row has no flex: overflows into the call chip in Swedish or at large text

`lib/features/active_ride/presentation/waiting_sheet_bits.dart:396` (found by r2-rider4)

**What happens:** 360 px phone, Waiting or in-trip, driver assigned. The Expanded gets 360-40-28-104 = 188 px. In Swedish at 2x text the Row needs 18+8+~169 = 195 px (+~33 with an unread badge), so a RenderFlex overflow pushes the text under the call button. At 320 px even English at 2x overflows once a message arrives (~147 + 33 > 148). The 200% tests pump WaitingForDriver without a driver, so this card is never laid out.

**Why:** The Message control sits in an Expanded next to two 44 px icon chips. Inside it a centred Row holds Icon(18) + 8 + Text(message) + optional unread badge, and no child is Flexible. Swedish 'Meddelande' is about 6.0em at 14 px w600. Row overflow paints past the Material (Clip.none) over the phone chip.

**Suggested fix:** Wrap the Text in Flexible with maxLines: 1 and ellipsis.

### L39. Successful OTP or provider sign-in waits for push registration (Firebase init, getToken, POST /push/devices) before the rider can continue

`lib/features/auth/application/auth_controller.dart:35` (found by r2-rider3)

**What happens:** On a poor connection a rider who once allowed notifications enters the correct code. The spinner keeps going for up to 15 s or more while the push device POST times out, then Home opens. It looks as if sign-in is hanging.

**Why:** verifyOtp and signIn both `await _registerPushBestEffort()` before returning, so PhoneVerification keeps the Verify button busy and SignIn keeps the provider button busy until FirebasePushService.register() finishes. That means Firebase initialize, requestPermission, getToken (no timeout) and _replaceToken's POST (15 s timeout). Push consent is kept across sessions (movera.push_consent.v1 is not wiped, see the separate finding), so this happens on every later sign-in on a device where consent was ever given. This is the sign-in counterpart of the known cold-start finding at bootstrap.dart:130.

**Suggested fix:** Run registration with unawaited() after entering the app, as the bootstrap comment intends for the first frame.

### L40. Sign-out abandons the pending-cancel flush after 5 s, and the still-running flush can write the previous rider's queued cancels back after the wipe

`lib/features/auth/application/user_data_wipe.dart:80` (found by r2-rider3)

**What happens:** On a slow network, rider A signs out with a queued end-early or cancel. The GET re-read takes about 7 s, past the 5 s budget, so sign-out clears the tokens and wipes storage. The GET then answers with a newer version, the entry is re-added, and the POST fails 401. Rider B signs in, and every reconnect retries A's cancel under B's session.

**Why:** UserDataWipe.flushPendingCancels wraps FindingDriverController.flushPendingCancels() in `.timeout(5 s)`. A timeout only stops the wait; the flush keeps running in the background while signOut goes on to clear tokens and run() removes `movera_pending_cancels`. The flush loop uses the list it read at the start. For each entry it re-reads the trip with a GET (up to 2 x 15 s). When the version moved on it calls `PendingCancelStore.add(cancel.forVersion(version))`, which writes the key again. It then POSTs: with the tokens gone that is a 401 with no access token, which is not a permanent failure, so `continue` keeps the entry. The previous rider's cancel now sits in the outbox, and the next session's reconnect or launch flush sends it with the new rider's token. The doc block says that must not happen ('sending them later with another rider's session would cancel nothing or the wrong thing'). `_flushInFlight` also stays set, so a new flush started meanwhile joins the stale run.

**Suggested fix:** Give the flush a cancellation token or a session generation that the wipe bumps. Make PendingCancelStore.add a no-op once the session it started under is over, and clear `_flushInFlight` in the wipe.

### L41. Sign-in and Add phone accept any +46 number with 7-10 digits (too-short or landline numbers), so an SMS code is 'sent' to a number that cannot receive it

`lib/features/auth/presentation/auth_navigation.dart:71` (found by r2-rider-r3)

**What happens:** The rider types '70 123 45 6' (one digit missing) and taps Continue. No 'invalid Swedish mobile' error appears. The code screen opens with 'sent to +46 70 123 456' and a resend countdown, and no SMS can arrive.

**Why:** swedishNumberFromField hands the typed digits to SwedishPhone.toE164. That function accepts any '+46' followed by 7 to 10 digits (`if (rest.length < 7 || rest.length > 10) return null;`). It does not check that the number is a mobile number: Swedish mobile numbers are '7' followed by 8 digits. The error text the app shows when the check fails is `invalidSwedishMobile`, and the screen promises an SMS code. A rider who misses a digit ("70 123 45 6" gives +46701234 56, only 8 digits) or types a landline passes the check. requestOtp is called, the app moves to 'Enter your code, sent to +46 70 123 456', and the SMS never arrives. The rider waits out the resend timer with no hint that the number is wrong. The known finding covers pasted '+46' numbers; this one covers ordinary typed national numbers that are too short.

**Suggested fix:** For sign-in and Add phone, check for a Swedish mobile number (rest matches ^7\d{8}$) before calling requestOtp, and keep the broader toE164 for Safety contacts that may be landlines.

### L42. The new-rider name step is decided once from isNewRider; a reload or kill on that step skips it forever

`lib/features/auth/presentation/phone_verify.dart:140` (found by r2-rider1)

**What happens:** A brand-new rider verifies their code on the web demo and reloads the tab on 'What should we call you?'. They land on Home with 'Welcome to Movera', are never asked for a name again, and drivers see no rider name.

**Why:** verifyOtp saves the session tokens first. Only then does PhoneVerification show RiderNameScreen as the root, and only when that one response says isNewRider. Nothing stores 'name still missing', and nothing checks for an empty profile name later. If the app is killed or the web page reloads on the name screen, the next cold start finds a session and opens Home directly: RiderRestoreCoordinator._root has no name check. The server will not say isNewRider again, because the rider is now known. The rider ends up with no name, which the screen itself says 'the driver will look for'.

**Suggested fix:** Persist a 'name pending' flag with the session, or show RiderNameScreen whenever a signed-in profile has an empty name.

### L43. The profile sent to the server says language 'en' while the app speaks the zone language, until the rider picks one by hand

`lib/features/auth/presentation/rider_name.dart:67` (found by r2-rider2)

**What happens:** A new rider in Stockholm signs up with the Swedish UI and enters their name. The server stores language 'en', so server-sent messages and receipts arrive in English.

**Why:** RiderProfileData.language defaults to 'en'. AppLanguageController (the language the app actually uses: the rider's choice, else the zone default, Swedish in Stockholm) never writes it into the profile. Only pickAppLanguage does. RiderNameScreen._save (and every other profile save) sends `language: 'en'` in the PATCH (FLOW-7: the server uses the language for the rider), even though the rider has been using the app in Swedish all along.

**Suggested fix:** Send AppScope.instance.language.code (or keep the profile language in step with AppLanguageController) instead of the default.

### L44. Sign-out shows no progress and does not block taps while flush, push unregister and server sign-out run

`lib/features/auth/presentation/sign_out_flow.dart:43` (found by r2-rider3)

**What happens:** On a weak connection the rider confirms Sign out, sees nothing happen, goes back to Home and books a ride. POST /rides succeeds with the old token and Finding opens. Seconds later the wipe disposes the search and Sign in appears, while the server ride keeps looking for a driver for a rider who has left.

**Why:** After the confirm dialog closes, confirmAndSignOut awaits signOutAndShowSignIn and shows no progress or barrier. The sequence is: flushPendingCancels (up to 5 s), push.unregister (POST, 15 s timeout, plus deleteToken), POST /auth/sign-out (15 s timeout), and the wipe. On a slow network that can take 30 s or more. The menu, Account and Home remain usable throughout, so the rider can tap Sign out again (a second dialog and a concurrent second signOut and wipe) or start a booking with the still-valid token. That booking is then wiped locally (snapshot cleared, FindingDriverController disposed) while the server ride stays searching.

**Suggested fix:** Show a modal progress barrier (or disable navigation) from the confirm until showSignInRoot, and ignore repeated sign-out taps while one is running.

### L45. Sign-in hero tagline 'Moving to a new era.' is English although brandTagline is translated in the ARB

`lib/features/auth/presentation/widgets/balloon_brand_intro.dart:95` (found by rider1)

**What happens:** App started in the France zone: Sign in shows 'Moving to a new era.' while Rider name shows 'Movera · Vers une nouvelle ère'.

**Why:** The sign-in hero (sign_in.dart:164 `hero: BalloonBrandIntro(progress: _story)`) draws `Text('Moving to a new era.', ...)` (:95) and a Semantics label 'Movera. Moving to a new era.' (:26). The ARB defines brandTagline with French/Swedish translations (' · Vers une nouvelle ère', ' · På väg mot en ny era') and rider_name.dart:140 uses it, so the same slogan appears translated on the next screen but English on Sign in when the zone default is fr/sv.

**Suggested fix:** Render the translated tagline (strip the leading ' · ' or add a dedicated key) in the intro and its Semantics label.

### L46. The duplicate-ride stand-down cancel is sent once and never queued, so a failure leaves two live rides

`lib/features/booking/application/booking_coordinator.dart:777` (found by r2-rider1)

**What happens:** A Book now request is stuck on a flaky network. Meanwhile another Finding for a different ride becomes active (restore or push). The booking response arrives and the stand-down cancel fails on the same bad network. The rider sees 'couldn't confirm your booking' while two rides are live on the server. Traced by reading the code.

**Why:** When a booking response arrives while another Finding owns a ride, `_standDownIfFindingOwned` POSTs `/cancel` for the duplicate directly. It does not go through the pending-cancel outbox. If that POST fails (offline or 5xx), the exception escapes `_submitFinding`. `_sendOrRecover` treats it as may-have-booked and replays, the replay hits the same stand-down, and the error finally reaches Select Ride as `bookingUncertain`. Nothing remembers that the duplicate must be cancelled, so it stays live on the server. Long network stalls on Book now (up to 15 s plus 15 s plus a 30 s GET) widen the window for this race.

**Suggested fix:** Enqueue the stand-down through `PendingCancelStore.enqueue` before sending, so the outbox flush retries it, and do not treat the stand-down's failure as a booking failure.

### L47. A failed autocomplete request is shown as 'No address found'

`lib/features/destination_search/data/place_suggestion_repository.dart:30` (found by r2-rider4)

**What happens:** With a dropped connection, the rider types a valid street. The spinner stops and 'No address found' appears for every query, with no hint that it is a connection problem or that retrying would help.

**Why:** `suggest` catches every error (offline, timeout, 5xx, 401) and returns an empty list. RoutePickerPage cannot tell that apart from a real empty result, so `_whileTyping` shows 'No address found' with the noAddressFoundBody copy and a map button. The rider is told the address does not exist when the lookup never ran. The saved-place picker does the same: `_submitQuery` turns a thrown geocode into 'spAddressNotFound' (pickup_location.dart:70-80).

**Suggested fix:** Return a result type that separates failure from empty, and show a connection or retry message on failure.

### L48. Suggestion distances and the CO2 figure always use '.' as the decimal separator in sv/fr

`lib/features/destination_search/domain/place_suggestion.dart:64` (found by r2-rider3)

**What happens:** App language Svenska: a Where to? suggestion 1.24 km away shows '1.2 km', and the month card shows '1.2 kg' after 3 Electric rides.

**Why:** `formatDistanceKm` builds '1.2 km' with toStringAsFixed, and the Home month card passes `co2AvoidedKg.toStringAsFixed(1)` ('0.4') into `homeCo2Kg`. Both bypass locale number formatting, so Swedish and French riders see '1.2 km' and '0.4 kg' instead of '1,2 km' and '0,4 kg'. These are separate code sites from the known shared/formatters/money.dart issue.

**Suggested fix:** Format with NumberFormat for L10n's current locale (or the app's shared decimal formatter).

### L49. On web only, matchRange can return offsets past the original string (e.g. 'İ' folds to two code units), so the suggestion highlight is misplaced or substring throws RangeError

`lib/features/destination_search/domain/place_suggestion.dart:91` (found by r2-rider3)

**What happens:** A suggestion titled 'İzmir Kebab' (5+6 chars), with the rider typing 'kebab': folded index 7, end 12, but the original length is 11, so substring throws RangeError and the results list shows an error widget (or a grey box in release).

**Why:** `foldForSearch` lowercases with `toLowerCase()`, which can change string length. On web (JS semantics), 'İ' (U+0130) becomes 'i̇', two code units. `matchRange` returns indices into the folded text, and `_highlighted` applies them to the original with `substring(start, end)`. Once the text contains such a character, the highlight shifts, and a match near the end gives `end > text.length`, a RangeError during build.

**Suggested fix:** Fold character by character while keeping a map from folded index to original index, or clamp and validate the range before calling substring.

### L50. Compact-to-full address map is keyed by the short label, so two fields with the same short form expand to the same full address

`lib/features/destination_search/presentation/route_picker_page.dart:154` (found by r2-rider3)

**What happens:** The rider picks recent 'Kyrkvägen 2, Bromma, Stockholm' as pickup (no point), then 'Kyrkvägen 2, Hägersten, Stockholm' as destination. Both fields read 'Kyrkvägen 2, Stockholm'. The selection's pickup expands to the Hägersten address and is geocoded there, so pickup and destination become the same point.

**Why:** `_show` records `_fullAddress[short] = full` for every address it shortens, and `_expand` looks the field text up by that short key. `compactAddress` keeps only the first part and the last town, so different addresses such as 'Kyrkvägen 2, Bromma, Stockholm' and 'Kyrkvägen 2, Hägersten, Stockholm' both become 'Kyrkvägen 2, Stockholm'. Whichever was shown last wins, and `_finish` sends that full address for both pickup and destination. When the pickup has no point (a recent, Home or Work row), Home geocodes the wrong full address.

**Suggested fix:** Keep the full address per field (pickup, destination, each stop) rather than in a map keyed by display text.

### L51. Route picker sends an autocomplete request on every keystroke (no debounce)

`lib/features/destination_search/presentation/route_picker_page.dart:291` (found by r2-rider3)

**What happens:** Typing 'Drottninggatan 53' fires 17 POSTs to the autocomplete endpoint in under 2 seconds. Under a per-user rate limit, later requests fail and the list shows 'No address found' (see the previous finding).

**Why:** `_onTyped` calls `destinationSearch.suggest` directly on every change, and `suggest` posts to `/api/v1/locations/autocomplete` each time. Only the response is filtered by generation, not the request. The same controller's `type()` path uses the 320 ms debounced `PlaceSearchService`, but the main Where to? field bypasses it. Typing a 20-character address sends about 20 geocoding requests, which costs quota and invites rate limiting on the live backend.

**Suggested fix:** Debounce suggest (for example reuse PlaceSearchService) and cancel or skip superseded requests before sending.

### L52. Custom saved places appear in Where to? under their type label ('Other'), not the name the rider gave them

`lib/features/destination_search/presentation/route_picker_page.dart:866` (found by r2-rider3)

**What happens:** In Saved Places, add 'Mamma' and 'Office Kista' (types 'mamma' and 'office-kista'). Open Where to?: both rows are titled 'Other'.

**Why:** Saved Places stores a place created via 'Add another' with the rider's name as its title and a slug of that name as its type (`AddPlace._kindFor`), for example 'Mamma' becomes type 'mamma'. The Home card shows `place.title`, but the route picker labels each custom place with `placeLabelFor(place.type)`, which maps every unknown type to `placeOther`. Several named places all read 'Other' and can only be told apart by address.

**Suggested fix:** Show place.title, falling back to placeLabelFor(type) only when the title is empty or equals the raw type key.

### L53. Prefix dedupe hides real suggestions, such as 'Kungsgatan 4' whenever 'Kungsgatan 44' is a recent

`lib/features/destination_search/presentation/route_picker_page.dart:939` (found by r2-rider3)

**What happens:** Recents contain 'Kungsgatan 44, Stockholm'. The rider types 'Kungsgatan 4'. The suggestion titled 'Kungsgatan 4' is hidden because the recent starts with 'Kungsgatan 4', and the list offers only the recent 'Kungsgatan 44' (or 'No address found' tooling around it).

**Why:** A suggestion is dropped when any matching recent address starts with the suggestion's title. That is a plain string prefix test, so a different house number or a longer place name with the same start counts as the same place. The rider then cannot pick the address they typed from the list. Pressing Enter still picks the hidden `_results.first`.

**Suggested fix:** Compare whole normalized addresses (or the title against the recent's first comma part) for equality instead of startsWith.

### L54. Finding's elapsed counter adds one per timer tick instead of reading searchStartedAt, so after timers are paused the 'Still looking' copy and the raise-offer card come late (a server-ended search is still caught by the resync on resume)

`lib/features/finding_driver/application/finding_driver_controller.dart:424` (found by r2-rider2)

**What happens:** The rider books, waits 30 s, then switches apps for 4 minutes while the search goes on. When they come back, Finding shows about 30 s elapsed and the early 'searching' copy. 'Still looking for a driver' (3-minute mark) and the server check behind it only appear 2.5 minutes later, although the search has really run 4.5 minutes, so a server-ended 'no driver found' is noticed late too.

**Why:** `start()` works out `elapsedSeconds` from `snapshot.searchStart` once (ARCH-3 / RIDE-5: 'elapsed counts from when this search started'). After that, `_startTick` only adds `elapsedSeconds += 1` each periodic tick. Timers are suspended while a mobile app is in the background, and browsers throttle them in hidden tabs (iOS Safari suspends the tab; Chrome drops to about one tick a minute after 5 minutes). Neither Finding nor its controller has a lifecycle hook (only Home and AppLifecycleObserver observe lifecycle), so after a pause the counter stays behind wall-clock time. Everything gated on it fires late: `isDelayed`/searchDelayed, `showPriceBump` (`elapsedSeconds >= priceBumpAfter.inSeconds`), `_reachSearchTimeout` and the periodic `checkServerSearchState`.

**Suggested fix:** On each tick, recompute elapsed from `_snapshot.searchStart` (`DateTime.now().difference(searchStart).inSeconds`) and pass the real step to `_afterElapsed`, so a resumed tick catches up at once.

### L55. checkServerSearchState ignores _cancelQueued: on a restore past searchTimeout, a server cancelled_by_rider is handled as a foreign terminal (no History record, generic sheet instead of the committed-cancel flow)

`lib/features/finding_driver/application/finding_driver_controller.dart:527` (found by r2-rider2)

**What happens:** The rider cancels offline 4 minutes into a search and reloads. The restore flush times out (no answer in 4 s), so Finding is restored as Cancelling…. The server-state GET comes back cancelled_by_rider. The ride ends with the generic sheet, is not in History, and the queued reason is never sent.

**Why:** The realtime listener treats `cancelledByRider` while `_cancelQueued` as the queued cancel landing (`_confirmQueuedCancel`: archive, why-sheet). `checkServerSearchState` checks neither `_cancelQueued` before nor after its await. On a restore whose search is past `searchTimeout`, `start()` schedules `_reachSearchTimeout` as a microtask, which starts the GET before the async `_adoptQueuedCancel` has set `_cancelQueued`. When the GET answers cancelled_by_rider, it calls `_completeTerminal(cancelledByRider)`. That status is not in the archive list, so History gets no record, `_queuedReasonId` is lost, and `_handleTerminal` (with `_match.cancelled` false) shows the generic terminal sheet instead of the committed-cancel flow.

**Suggested fix:** In checkServerSearchState, after the await, route `status == cancelledByRider` with `_cancelQueued` (or a stored outbox entry) to `_confirmQueuedCancel()`. Or skip the check while a cancel is queued.

### L56. An offer raise whose answer was lost is shown as failed, and the screen never picks up the higher fare the server applied

`lib/features/finding_driver/application/finding_driver_controller.dart:876` (found by r2-rider2)

**What happens:** Rider raises the offer by kr 20 and the PATCH times out after the server applied it. The rider sees 'Couldn't update offer', the screen shows kr 259, the driver accepts at kr 279, and the rider is charged kr 279 at the end. Traced by reading the code.

**Why:** A timeout or dropped connection on `PATCH /rides/{id}` with `offerIncrease` sets `editFeedback` to 'Couldn't update offer. Try again.' and leaves `_snapshot.price` unchanged. If the server applied the raise, nothing ever corrects the price: realtime events carry no fare, and `checkServerSearchState` reads only the status. Finding and then Waiting (`price: _match.currentPrice`) keep showing the old fare, while the trip is priced at the raised fare. A retry with the same amount reuses the key and fixes it, but a rider who takes 'failed' at its word does not retry.

**Suggested fix:** On a retryable error (`ApiError.isRetryable` or `ClientException`), say the result is unconfirmed and re-read `GET /rides/{id}` to adopt the server's `fare` into the snapshot.

### L57. ARCHITECTURE.md and the cancelSearch doc comment still describe the old offline cancel (commit locally); the code implements RC-03 (queued, not committed), so the docs are out of date

`lib/features/finding_driver/application/finding_driver_controller.dart:1090` (found by rider4)

**What happens:** An operator or tester reading ARCHITECTURE.md expects an offline cancel to land on Home with the ride archived; the app instead stays on the search screen with 'Cancelling…' until the server answers.

**Why:** ARCHITECTURE.md lines 13-17 state that on Finding, Cancel request commits the ride as `cancelledByRider`, archives it and clears the snapshot 'on its OK — or when it cannot be reached, leaving the outbox entry to retry'. The method doc of `cancelSearch` repeats it (1089-1091: 'unreachable: the same local commit, with the outbox entry kept'). The implementation does the opposite: `if (result == SearchCancelResult.queued) { _cancelInFlight = false; _cancelQueued = true; ... return result; }` (1123-1137) commits nothing, keeps the search listening and shows 'Cancelling…'. The `SearchCancelResult.queued` enum comment (45-50) and the restore coordinator (111-117) describe this newer RC-03 behaviour, so the two records contradict each other and the architecture document no longer describes what the product does.

**Suggested fix:** Update ARCHITECTURE.md and the `cancelSearch` doc comment to the RC-03 behaviour (or restore the documented behaviour, whichever is the decision).

### L58. A failed write to the cancel outbox (web localStorage quota) leaves cancelSearch stuck in flight: later cancels are ignored, driver matches are swallowed, and Finding never navigates

`lib/features/finding_driver/application/finding_driver_controller.dart:1175` (found by r2-rider2)

**What happens:** In a browser where localStorage writes throw, the rider taps Cancel request. The sheet closes, nothing is sent, the timer stops and the X does nothing. When a driver accepts, the rider is never moved to Waiting.

**Why:** `cancelSearch` sets `_cancelInFlight = true` and stops the tick, then awaits `PendingCancelStore.enqueue` outside any try. If SharedPreferences throws (web quota/blocked storage), the error escapes `cancelSearch`. In the sheet, `_confirm` closes with false and rethrows. In `_confirmCancel`, `await request` throws before `_cancelSheetOpen = false`, so `_drainDeferredNavigation` returns early from then on. In the controller, `_cancelInFlight` stays true: `cancelSearch` returns ignored, and `_completeAssigned` only sets `_assignmentPending` ("wait for the cancel"), which nothing ever resolves.

**Suggested fix:** Wrap the enqueue (and the whole server-cancel path) in try/catch. On failure, reset `_cancelInFlight`, restart the tick, still attempt the POST without the outbox, and make `_confirmCancel` clear `_cancelSheetOpen` in a finally.

### L59. A non-version 409 on the foreground search cancel always shows 'driver already accepted', but under the contract that 409 only happens when the trip has already ended (expired / no driver / admin or driver cancel)

`lib/features/finding_driver/application/finding_driver_controller.dart:1208` (found by r2-rider2)

**What happens:** The search expires on the server just as the rider taps Cancel request, and the server answers 409 with projection status expired. The rider sees "A driver already accepted your ride", then the no-driver-found sheet when realtime delivers the terminal.

**Why:** Apart from version_mismatch and already-cancelled-by-rider, `_requestServerCancel` maps any 409 to `driverAccepted` without looking at the error projection's status. The outbox path (`_refusalResult`) re-reads the trip to tell "driver accepted" from "already over", but the foreground path does not. The contract says 409 means "the ride moved on first", which includes the search expiring (expired / no_driver_found) or an admin/system cancel at the same moment.

**Suggested fix:** Branch on `TripStatusWire.parse(error.projection?['status'])`. Return driverAccepted only for matched stages, and treat a terminal projection as rejected or terminal.

### L60. Search elapsed clock freezes while a cancel is in flight or queued, and resumes from the frozen value after a refusal or stale result (e.g. an offer sent or lapsed during the replay)

`lib/features/finding_driver/application/finding_driver_controller.dart:1285` (found by r2-rider2)

**What happens:** The rider's cancel sits queued for 2 minutes offline, then is refused because a driver was about to accept, but the match falls through. The search shows 1:00 elapsed instead of 3:00, and the "Still looking for a driver" card and server check come 2 minutes late.

**Why:** ARCH-3/RIDE-5 say elapsed counts from when the search started (`start()` derives it from `snapshot.searchStart`). `cancelSearch` and `_adoptQueuedCancel` cancel the 1-second tick. After a refusal (409/422/stale, or an outbox refused/stale outcome) `_startTick()` just restarts it, so `elapsedSeconds` misses the whole in-flight or offline period. The still-looking mark (searchTimeout), the periodic server check cadence, the price-bump time, the copy rotation and the progress bar all run late by that amount, while a reload would jump to the true value.

**Suggested fix:** In `_startTick` (or on refusal), recompute `elapsedSeconds` from `_snapshot.searchStart`, and run `_afterElapsed` for the skipped span.

### L61. Cancel reason attached to an outbox entry is silently dropped when the replay re-read finds the trip already cancelled

`lib/features/finding_driver/application/finding_driver_controller.dart:1549` (found by r2-rider2)

**What happens:** On a flaky network the cancel POST lands but both responses time out, so it is queued. The next poll shows cancelled_by_rider, Finding commits and the why-sheet opens. The rider picks "Driver too far" and Send. The reason is written into the outbox entry, and the next flush drops it unsent. Support/admin never see the rider's cancel reason.

**Why:** For a queued cancel that the server already applied (the response was lost), Finding commits through the realtime listener (lines 375-378 → `_confirmQueuedCancel`) without removing the outbox entry. The why-sheet then calls `sendCancelReason`, and `PendingCancelStore.attachReason` finds the stale entry, stores the reason on it and returns true, so no POST is made (line 1376). When the outbox is later flushed, `_rereadForReplay` sees `cancelled_by_rider` and returns `sent` without sending anything, then the entry is removed. The reason never reaches the server, although the doc says it "rides along with a cancel still queued in the outbox". The mock contract stores a later reason on a cancelled ride, so the code plainly expects the server to have it.

**Suggested fix:** Remove the outbox entry when a queued cancel is confirmed by realtime/server check. Or, in `_rereadForReplay`, when the trip is already cancelled_by_rider and the entry carries a reason, still POST the (idempotent) cancel with the reason.

### L62. Re-tapping cancel while an unreachable attempt is still queued resends the first tap's expectedVersion and reason: a 409 'ride just changed' if the trip moved on, or a server reason that differs from the one History archives

`lib/features/finding_driver/data/pending_cancel_store.dart:295` (found by r2-rider1)

**What happens:** The rider cancels with reason 'plans_changed' and gets 'We couldn't reach Movera'. The driver's status advances and the connection returns. The rider taps Cancel again with 'driver_not_suitable'. The POST carries expectedVersion=old and reason 'plans_changed'. The result is 409 version_mismatch and 'Your ride just changed'. On the next try the server stores 'plans_changed' while History says 'driver_not_suitable'.

**Why:** `enqueue` returns the existing entry whenever one with the same command exists, keeping its `expectedVersion` from the first tap and its `reasonId`. `PendingCancel.body(fallback)` prefers the stored reason (`reasonId ?? fallbackReason`). On Waiting a second cancel after `pendingRetry` therefore sends the old version and the old reason. If the trip moved on meanwhile (e.g. assigned → arriving bumps the version), the mock answers 409 version_mismatch, which becomes `stale`, and the rider sees 'ride just changed' and must tap a third time. If it succeeds, the server keeps reason 1 while `_commitCancelled(reasonId: reason2)` archives reason 2 in History.

**Suggested fix:** On a new rider tap, refresh the entry with the current version and reason (new key, since the body changed), as the flush does with `forVersion`.

### L63. Admin-published rider cancel reasons (`RiderAppConfig.cancelReasons`) are parsed but never used; the reason sheet is hard-coded

`lib/features/finding_driver/domain/cancellation_reason.dart:60` (found by r2-rider2)

**What happens:** The zone document publishes cancelReasons [pickup_incorrect, plans_changed, something_else] (contracts/fixtures/config/rider_app_config.json). The rider's searching sheet still shows seven reasons, including wrong_ride_option, requested_by_mistake, wait_too_long and destination_change, with app-bundled titles instead of admin's.

**Why:** CONTRACT.md §5 lists 'Cancel reasons (Dispatch › Cancel reasons) | rider.cancelReasons | Rider reason list'. RiderAppConfig parses `cancelReasons` (rider_app_config.dart:295) and keeps rider codes only. Nothing in lib reads `config.cancelReasons`; the only references are in tests. Cancel sheets and reservation cancels use the fixed `CancellationReason.forPhase` lists. If admin removes or retitles a reason, the rider still offers and sends the shipped list. The server validates `reasonCode` per actor and may refuse a code that admin turned off.

**Suggested fix:** Build the reason sheet from `RiderAppConfig.current.cancelReasons` (filtered per phase), and fall back to the seed lists only when the document has none.

### L64. 'Try again' after no driver found books a fresh quote without asking the rider to confirm a changed price (Select Ride asks in that case)

`lib/features/finding_driver/presentation/finding_drivers.dart:360` (found by r2-rider4)

**What happens:** The rider raised the offer from 120 kr to 140 kr, the server then answered noDriverFound, and the rider taps 'Try again'. A new ride is created at the fresh quote, say 165 kr in surge, or the plain 120 kr without the raise, with no confirmation step. The rider believes they re-requested the same 140 kr ride.

**Why:** `_requestAgain` calls `submitFinding(price: ended.price, ...)` without any quote fields. In `BookingCoordinator._resolveQuoteBinding`, `suppliedCount == 0`, so it fetches a new quote and calls `..validate()` without `requestedPrice`. The `ended.price` the rider last saw is never compared. `_prepareFinding` then books `effectivePrice = binding.total.major`, which can be higher or lower. Select Ride stops for `_acceptNewPrice` whenever the price to book differs from the one shown (RIDE-1/2). This path books silently, and the new search starts at whatever the server quotes now. A raised offer the rider made in the previous search is also lost. The new price only appears afterwards, on the payment line.

**Suggested fix:** Quote first in `_requestAgain`. If the quote differs from `ended.price`, ask the rider to accept the new price, the same prompt as `_acceptNewPrice` on Select Ride. Otherwise pass `requestedPrice` into validation so a changed fare is refused, not silently booked.

### L65. `_refreshRoadRoute` has no request generation, so an older road-route answer can overwrite the route drawn for a changed destination

`lib/features/finding_driver/presentation/finding_drivers.dart:506` (found by rider2)

**What happens:** Rider changes the destination from the Finding screen (or the server's route-change event arrives) right after the screen opened. The new destination marker appears, then the road line for the OLD destination is drawn on the map and stays until another route change or ride stage.

**Why:** `_adoptRoute` (line 395-406) and `_applyRouteChange` (line 700-711) update `_pickupPosition`/`_destinationPosition`, clear `_roadRoutePoints`, redraw, and then call `unawaited(_refreshRoadRoute())`. `_refreshRoadRoute` awaits `roadRoutePolyline(from: _pickupPosition, to: _destinationPosition)` (a network call via `RoutingService.roadLine`) and on return only checks `mounted` and `route.points.length < 2` before assigning `_roadRoutePoints = route.points` and redrawing. There is no check that the answer is for the route currently adopted. When a route change happens while the previous road request is still in flight (or a slow first request is beaten by the second), the older polyline lands last and is drawn between the new pickup/destination markers.

**Suggested fix:** Capture `from`/`to` (or a `++_routeGeneration`) before the await and discard the result when `_pickupPosition`/`_destinationPosition` changed (or the generation moved on) in the meantime.

### L66. Price-bump state raises the Finding sheet to a fixed 520 px and covers the Cancel and Safety buttons on short viewports

`lib/features/finding_driver/presentation/finding_drivers.dart:792` (found by r2-rider4)

**What happens:** iPhone SE in Safari (viewport ~375x548, padding.top 0): when the raise-your-offer card appears, the sheet top sits at y=28. The X button (y 8-56) and Safety Kit button are mostly covered and take taps only in their top 20 px. Dragging to the max stop (568 > 548) pushes the sheet's handle above the screen.

**Why:** _minSheet is a constant 520 (+bottom padding) while the price-bump card shows, and _maxSheet is forced to at least minH+48 = 568. The top Cancel (X) and Safety Kit buttons sit at padding.top+8 and are drawn before the SheetViewport in the Stack, so the sheet paints over them when the viewport is shorter than about 576 px.

**Suggested fix:** Clamp the sheet stops to media.size.height - media.padding.top - 64 (below the top bar) and let the panel scroll.

### L67. New History records store English cancel reasons ('No driver found', 'Request expired', 'Cancelled by Movera', ...), which the detail sheet shows untranslated

`lib/features/history/data/on_demand_ride_history_store.dart:261` (found by r2-rider4)

**What happens:** App language is Swedish. A search ends with no driver, so the ride is archived as noDriverFound. In History › Cancelled › tap the ride, the line reads 'Reason: No driver found' in English inside a Swedish sheet.

**Why:** recordFor falls back to `_endedSearchReason(terminalStatus)` when no reason code is given. That writes English sentences into Reservation.cancellationReason for every server-ended ride (noDriverFound, bookingExpired, cancelledByAdmin, cancelledBySystem, noShow, tripFailed, endedByDriver). The History detail line shows them through ReservationFormat.reasonLabel. That function only translates reason ids, `system_*` codes, `admin_*` and snake_case strings, and returns anything else unchanged ('older records already hold a label ... and are shown as they are'). Records created today therefore keep English text in sv and fr, although translated strings exist (L10n.termNoDriverFound, cancelledByMovera, reasonNoShow, ...).

**Suggested fix:** Store reason codes (for example 'system_no_driver', 'system_expired', 'admin_cancelled', 'rider_no_show', 'system_error', 'driver_ended') and map them in ReservationFormat._reasonLabels to the existing l10n strings.

### L68. Upcoming tab lists reservations in booking order, not pickup order

`lib/features/history/presentation/ride_history.dart:268` (found by r2-rider1)

**What happens:** Book tomorrow 07:15, then book today 23:50. History › Upcoming shows the 23:50 ride below tomorrow 07:15, although it is the next ride.

**Why:** `_upcoming()` shows `_reservations.upcoming()` as stored. `createReservation` prepends (`[created, ..._items]`), so the list is newest-booked first. The Home chrono sorts by `scheduledPickupAt`; History does not.

**Suggested fix:** Sort by scheduledPickupAt ascending before building the list.

### L69. History detail shows 'Movera Wallet' / 'Card' untranslated; only Cash is localized

`lib/features/history/presentation/ride_history.dart:552` (found by rider3)

**What happens:** Swedish UI, wallet-paid ride: History detail shows 'Betalsätt: Movera Wallet'; the reservation page for a scheduled wallet ride shows 'Movera Plånbok'.

**Why:** The ride detail sheet prints `L10n.isCashLabel(ride.paymentMethod) ? context.l10n.payCash : ride.paymentMethod`. Rides booked with the wallet or the generic card row store the English names 'Movera Wallet' / 'Card' (`payment.name` in `_bookNow`), so in Swedish/French the line reads 'Betalsätt: Movera Wallet' while the Upcoming/Scheduled screens use `paymentLabelFor` (payment_labels.dart:24-29) and show 'Movera Plånbok' / 'Portefeuille Movera' for the same ride.

**Suggested fix:** Use `paymentLabelFor(ride.paymentMethod)` in the History detail sheet.

### L70. normaliseAddress forward-geocodes placeholder pickup labels, contrary to its own contract

`lib/features/home/application/home_controller.dart:256` (found by rider4)

**What happens:** Staging build with a real geocoder. Rider chooses the pickup on the map; reverse geocode yields no street so the label is 'Pickup location'. After the picker pops, forward('Pickup location') returns e.g. a business called 'Pickup Location AB' in another city; SelectRide and the booking carry that label with the pin's coordinates.

**Why:** isPlaceholderPickupLabel's doc says a placeholder 'must not be forward-geocoded or saved' (home_controller.dart:62-69), but normaliseAddress only short-circuits '' and 'Current location'. _showRouteAddressPicker normalises draft['pickup'] unconditionally (home.dart:954), and that value is locationOffPickupLabel when _prefillPickup fell back (home.dart:818-822) or pickupLocationFallbackLabel ('Pickup location') / a 'Dropped pin …' label when the pin was placed on the map (confirmedPickupAddress, pickup_address.dart:46-49). Reproduced with a recording geocoder: forward() was called with 'Location off, set pickup' and 'Pickup location'. With the in-process mock the text comes back unchanged (in_process_mock_client.dart returns `'address': normalized`), but any real geocoder that fuzzy-matches returns some place name, which then becomes the pickup label shown in SelectRide and sent with the booking while pickupLat/Lng stay at the pin or the Stockholm default.

**Suggested fix:** Return early in normaliseAddress when isPlaceholderPickupLabel(clean) || needsDroppedPinLabel(clean), and skip normalising the pickup when the draft already carries pickupLat/Lng.

### L71. Approximate-only location grant is used as the 'Current location' pickup with no 'precise location off' notice

`lib/features/home/application/home_controller.dart:397` (found by r2-rider3)

**What happens:** The rider picks 'Approximate' in the Android 12 permission dialog. Home centres on a point about 1-3 km away and labels it as the current-location pickup with that street's address, and the booking dispatches the driver there unless the rider notices and moves the pin. Verified by reading the code.

**Why:** The manifest declares ACCESS_COARSE_LOCATION next to FINE, so Android 12+ lets the rider grant only approximate location. iOS 14+ has the same toggle. geolocator then returns fixes with accuracy of several km. detectCurrent never checks Position.accuracy or Geolocator.getLocationAccuracy(), does not request temporary full accuracy, and immediately treats the fix as the 'Current location' pickup, reverse-geocodes it, and calls _rememberGoodFix. The repository describes that fix as 'a successful high-accuracy fix'.

**Suggested fix:** Check getLocationAccuracy() / Position.accuracy, show the 'precise location off' notice, and on iOS request temporary full accuracy (NSLocationTemporaryUsageDescriptionDictionary) before using the fix as a pickup.

### L72. Custom place added from Home gets the raw type key as its title ('gym', 'restaurant', 'other') shown verbatim in every locale

`lib/features/home/application/home_places_controller.dart:145` (found by rider3)

**What happens:** Swedish rider taps Add > Restaurang on Home and saves an address; the Home card and Menu > Sparade platser list the place as 'restaurant'.

**Why:** applyResolved creates `SavedPlaceData(title: type, type: type, address: address)` and persist() stores 'title': 'gym'. _CustomPlaceCard renders `place.title` (saved_places_row.dart:239-240) and the Saved Places screen renders the stored title (saved_places_controller.dart:177-180 uses the title whenever non-empty), so the card reads 'restaurant' / 'other' in lowercase English even in the Swedish/French UI, while RoutePickerPage shows the localized placeLabelFor(place.type) for the same place. Reproduced: applyResolved(custom, customType:'restaurant') -> title 'restaurant'.

**Suggested fix:** Store the localized label (placeLabelFor(type)) or leave title empty and let the UI derive it from type.

### L73. Location permission is requested again immediately after the rider denies it, and again on every app resume

`lib/features/home/presentation/home.dart:343` (found by rider1)

**What happens:** Android rider taps Where to with location not yet granted, denies the prompt; within the same tap the prompt appears a second time (attempt 2). Later, every time they switch apps and come back, the prompt is shown again.

**Why:** _awaitCurrentFix loops two attempts; if the first detectCurrent returns quickly with permissionDenied (target == null), the second attempt starts a fresh detectCurrent, which calls location.requestPermission() again (home_controller.dart:369-371) — a second system prompt right after the first 'Deny'. didChangeAppLifecycleState(resumed) also calls _detectCurrentAddress() whenever _currentLatLng == null (home.dart:266-267), so an Android rider who denied once gets the prompt on each return to the app until Android auto-blocks it. iOS/web report deniedForever after one refusal, so only Android (and 'denied' on older Android indefinitely) is affected.

**Suggested fix:** Stop retrying when the first attempt ended in a permission failure (track the last DetectedLocation.failure), and on resume only re-detect when the last state was not permissionRequired.

### L74. Home can start GPS tracking, pulse and compass on its disposed location controller if it is replaced while the puck icons are being built

`lib/features/home/presentation/home.dart:380` (found by r2-rider4)

**What happens:** On a cold start that restores a ride, Home is built, its first fix lands, and the root is replaced while the puck bitmaps are still being drawn. The rider is on the ride screen, but a dead Home location subscription and two periodic timers keep running for the rest of the session.

**Why:** _runDetectCurrentAddress awaits _prepareLocationPuckIcons() (picture rasterisation, which spans frames) and then calls _locationCtl.bindLiveLocation without re-checking mounted. If Home is disposed in that window, for example when the restore coordinator replaces the root on cold start, startTracking subscribes to the position stream on an already disposed controller. That subscription is never cancelled and keeps GPS on. startPulse and startHeading create periodic timers (850 ms and 100/250 ms) that are never cancelled, and _startCompass runs again after dispose() stopped it. A later stream error calls _setState -> notifyListeners on a disposed ChangeNotifier. The new ui.Images are also kept on the dead State.

**Suggested fix:** Check `if (!mounted) return;` after `await _prepareLocationPuckIcons()`. Make bindLiveLocation/startTracking/startPulse no-ops after the controller is disposed.

### L75. Backing out of Plan your ride while it is preparing a Book for later route still opens the date picker over Home

`lib/features/home/presentation/home.dart:864` (found by r2-rider4)

**What happens:** The rider taps Book for later, picks a destination, and while the spinner shows (waiting for a first GPS fix) presses Back to leave. A few seconds later the date and time picker pops up over Home, and choosing a time does nothing.

**Why:** RoutePickerPage has no PopScope while _finishing. On Android, system back pops it while onFinish (_confirmRouteSelection) is still running, which can take up to 8 s in _awaitCurrentFix or the destination geocode. _confirmRouteSelection checks only Home's mounted and then pushes ScheduleDateTimeSelector.choose(context, ...) from Home's context. The picker is gone and _showRouteAddressPicker already returned with a null draft, so any time chosen there is thrown away.

**Suggested fix:** Pass a cancellation or 'still open' check from the route picker to onFinish (or block pop while _finishing), and stop _confirmRouteSelection when the picker is gone.

### L76. Recenter button is hidden after a recenter that was interrupted or blocked, leaving the map off the rider with no way back

`lib/features/home/presentation/home.dart:1668` (found by rider1)

**What happens:** Rider taps recenter; while latestFix() runs (up to 9 s) they pan the map elsewhere (button correctly shows). latestFix returns a point >15 m away, the follow glide is refused because the map is held, then _showRecenterButton = false: the map stays where they panned and the recenter button is gone until they move the map again.

**Why:** _recenterOnUser unconditionally ends with `setState(() => _showRecenterButton = false)`. The flight future completes early when a finger touches the map (MapView.touching -> interrupt() completes _done, map_camera_motion.dart:76-94), and the refinement glide `_flyToUser(fresh, follow: true)` is a no-op when heldByRider (google_map_provider.dart:81, 102). In both cases the camera is not on the rider, any 'show' decision made by _handleMapCameraMove during the rider's pan is overwritten with false, and the button only returns after the next camera move event.

**Suggested fix:** Only clear _showRecenterButton when the glide actually landed (e.g. re-evaluate with AppScope.instance.camera.showRecenter against the last camera pose), or leave it to _handleMapCameraMove.

### L77. Release builds switch Book for later off only in the repository: every entry point still runs the full scheduling flow, which then ends in an honest 'isn't available yet' error

`lib/features/home/presentation/home.dart:2077` (found by r2-rider4)

**What happens:** A production rider taps 'Schedule' on Home. They choose a destination, a date and time, a category and a pickup, then tap Book. They get 'Booking for later isn't available yet, so nothing was booked.' The feature the docs say is switched off is fully offered, and the rider wastes the whole flow. Verified by reading the code.

**Why:** FeatureFlags.release sets enableScheduledRide/enableBookingLater false, and AppScope composes DisabledReservationRepository. ARCHITECTURE.md and docs/backend-readiness-gate.md say Book for later is 'switched off in staging/production'. No UI reads flags.scheduledRides or flags.bookingLater (the only flag consumers are RideSelectionController and wallet.dart's businessProfile). The release build still shows AdvanceBookingCard, the Schedule bottom-nav item, the WhereTo card's schedule action, the side menu 'Later' chip and History's schedule button. Each runs route picker, date/time, Select Ride and Set pickup. Only on Book does createReservation reject with ReservationsUnavailableException ('Booking for later isn't available yet, so nothing was booked.'). The comment in reservation_controller wiring also leaves rulesSource null, so the flow runs on default rules.

**Suggested fix:** Gate every Book-for-later entry point (Home card, nav item, WhereTo, side menu, History, plan-return) on AppScope.instance.flags.scheduledRides || bookingLater.

### L78. Menu pushes Notifications and Safety without route names, so pushPageOnce stacks a second copy when a push or the Safety bridge opens them

`lib/features/home/presentation/side_menu.dart:431` (found by r2-rider2)

**What happens:** The rider opens Menu › Notifications. A promo push arrives and they tap the system banner. A second Notifications screen slides in, and Back has to be pressed twice to leave.

**Why:** pushPageOnce avoids duplicates only by checking `_topRoute(nav)?.settings.name == name`. The side menu (and Account for SafetyHub) pushes `RightToLeftTransition(const NotificationScreen())` without settings, so the route name is null. A notification opened while the rider is on the menu's Notifications screen (PushCoordinator → _openNotificationsFromPush → pushPageOnce(..., AppRoutes.notifications)) pushes a second NotificationScreen on top. The web Safety bridge does the same over a menu-opened SafetyHub. This breaks bootstrap.dart's 'a second open does not stack a copy'.

**Suggested fix:** Push these screens with RouteSettings(name: AppRoutes.notifications / AppRoutes.safety) everywhere, or open them through pushPageOnce.

### L79. Your month card has no load generation, so an older history read can overwrite a newer one

`lib/features/home/presentation/widgets/home_journey_section.dart:184` (found by r2-rider3)

**What happens:** A reservation update starts load A. The ride completes and is archived, which starts load B. B returns first and shows 4 rides; A returns later with the pre-archive list and shows 3. Home shows 3 rides this month until something else changes.

**Why:** `_load` runs on every history-store change and every ReservationController notification, plus once at start. Each call awaits `defaultRides()` (in release a server trip list, see ARCHITECTURE), then setState with whatever it got. Nothing orders the results, so a slow read that started before a ride was archived can finish after a newer read and put the stale month back. The card stays wrong until the next change event.

**Suggested fix:** Increment a generation counter per _load and ignore results from superseded calls.

### L80. Chat message times use the Material 12/24-hour locale default instead of the app's 24-hour rule

`lib/features/messages/presentation/chat.dart:196` (found by rider1)

**What happens:** Rider with app language EN opens the driver chat: bubbles show '3:05 PM' while the ride sheet shows 'Pickup 15:05'.

**Why:** _messageTime formats with `TimeOfDay.fromDateTime(sentAt.toLocal()).format(context)`, which follows MaterialLocalizations.timeOfDayFormat: for the 'en' locale that is 'h:mm a' (12-hour, '3:05 PM') unless MediaQuery.alwaysUse24HourFormat is set. Every other time in the app is forced to 24-hour ('08:05') by L10n.formatTime (l10n.dart:111-114, 'as Movera shows it in every language') and ReservationFormat.time, so a rider using English in Sweden sees '3:05 PM' on chat bubbles but '15:05' on the Waiting sheet and notifications for the same moment.

**Suggested fix:** Use L10n.formatTime(sentAt.toLocal()) in chat.dart.

### L81. Hard-coded English UI strings in localized screens (notification toast, account security errors)

`lib/features/notifications/application/notification_navigation.dart:154` (found by rider2)

**What happens:** App language Svenska; rider taps an old ride notification: toast reads "This ride has ended." in English. Security page fails to load: "Account security is unavailable right now." in English.

**Why:** The app ships en/fr/sv (`L10n.languages`) and every other user-facing string on these screens goes through `context.l10n`. These do not: `MoveraToast.show(context, 'This ride has ended.')` shown when a notification row's ride can no longer be opened (154); `errorMessage = 'Account security is unavailable right now.'` and `'Could not update active sessions.'` (account_security_controller.dart:240, 265) which `SecurityPage` renders directly (security.dart:924, 1090). A Swedish or French rider sees English here.

**Suggested fix:** Add ARB keys and use `L10n.current`/`context.l10n` for these three strings.

### L82. A push with a title but no body shows its raw wire type (e.g. 'ride.driver_assigned') as the notification text

`lib/features/notifications/data/notifications_repository.dart:52` (found by r2-rider2)

**What happens:** The server sends a notification titled 'Your driver is here' with no body. The Notifications list shows 'Your driver is here' over the line 'ride.driver_arrived'.

**Why:** The subtitle falls back to `payload.type` when the body is empty. The type is the internal event code that PushPayload requires (`ride.`/`trip.` prefixes), not text meant for the rider, so it is shown untranslated in every language.

**Suggested fix:** Use an empty subtitle, or a localized label per known type, when there is no body.

### L83. Notification feed is ordered by ingest time, not sentAt: a tray notification tapped later is inserted above newer foreground ones

`lib/features/notifications/data/notifications_repository.dart:86` (found by r2-rider2)

**What happens:** Push A ('Your receipt', sent 12:00) arrives while the app is backgrounded and stays in the tray. The rider opens the app from its icon, and foreground push B (12:30) is ingested. Later they tap A in the tray. The Notifications list now shows A 12:00 above B 12:30.

**Why:** ingest() always does `_items.insert(0, ...)`, even though each item carries `at` (the sentAt). Pushes received while the app is in the background are not ingested until the rider taps them from the system tray (PushCoordinator._handleOpened -> ingest(read: true)). By then newer foreground pushes may already be in the feed. The cold-start initial message is also ingested only after start() has subscribed to foreground messages. In both cases an older notification lands at the top.

**Suggested fix:** Insert at the position given by `at` (newest first), not always at index 0.

### L84. A push sent the day before is labelled with no day (as today) when it is ingested on the day after spring-forward, because Duration.inDays between local midnights is 0 (23h)

`lib/features/notifications/data/notifications_repository.dart:95` (found by rider2)

**What happens:** Sunday 29 Mar 2026 (Europe/Stockholm) at 23:10 a 'Driver arrived' push arrives. On Monday 30 Mar the Notifications list shows it as '23:10' (today) instead of 'Yesterday 23:10'; a push from Saturday 28 Mar shows as 'Yesterday'.

**Why:** _formatTime computes `today.difference(day).inDays` where both are local midnights built with DateTime(y,m,d). On the day after a spring-forward transition the two midnights are 23 hours apart (verified by throwaway test under TZ=Europe/Stockholm: DateTime(2026,3,30).difference(DateTime(2026,3,29)) == 23:00:00), so inDays == 0 and the function returns only the clock, dropping the 'Yesterday' prefix the FLOW-18 comment promises. More generally, any day count across a DST change is one short (a notification from 3 days ago reads as 2 days -> still fine, but 2 days ago reads as 1 -> 'Yesterday').

**Suggested fix:** Compare calendar days with UTC-constructed midnights: `DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(time.year, time.month, time.day)).inDays`.

### L85. Notification time label is frozen at ingest, so items never become "Yesterday …"

`lib/features/notifications/data/notifications_repository.dart:213` (found by rider2)

**What happens:** Push at 23:50 shows "23:50"; the next morning the same row still says "23:50" instead of "Yesterday 23:50".

**Why:** FLOW-18 says only today's items show just the time and older ones name the day. `_formatTime(at)` is evaluated once when the item is ingested (206-213) and stored in `AppNotification.time`; `_formatTime` compares against `_now()` at that moment (248-261). The screen renders `notification.time` (notifications.dart:630) and never recomputes from `at`. The feed is in-memory for the process, so any app/tab left open across midnight shows yesterday's pushes with a bare clock.

**Suggested fix:** Format from `notification.at` at build time (or recompute labels on emit).

### L86. Unread notifications are marked only by an 8 px dot with no semantics

`lib/features/notifications/presentation/notifications.dart:195` (found by r2-rider1)

**What happens:** A TalkBack user opens Notifications after a driver update and hears every card the same way, with nothing to tell which notifications are new.

**Why:** _buildNotificationCard shows unread state solely as an 8 px primary-colour circle Container. The card's GestureDetector/Text semantics carry no unread flag or label, so screen-reader users cannot tell new notifications from read ones.

**Suggested fix:** Add a localized 'Unread' semantics label (or Semantics(label:) on the card) when !notification.read.

### L87. Card brand error 'We accept Visa and Mastercard' is shown untranslated under the card number

`lib/features/payments/application/saved_cards_controller.dart:67` (found by rider3)

**What happens:** French rider types a card number starting with 3 (Amex) on Ajouter une carte: the inline error reads 'We accept Visa and Mastercard'.

**Why:** CardInput.brandError is an English const. add_card_page.dart `_numberError` returns it directly: `if (CardInput.brandRejected(digits)) return CardInput.brandError;` (:125), and the same text is thrown as ArgumentError(CardInput.brandError) (:153) which add_card_page.dart:170 displays via `e.message`. All sibling errors on that page use context.l10n (cardCheckNumber, cardUseMmYy, cardExpired, cardCvc3), so this one field error stays English in fr/sv.

**Suggested fix:** Add an ARB key (cardBrandsAccepted) and return context.l10n.cardBrandsAccepted from _numberError; keep the controller's ArgumentError for programmer errors only.

### L88. Saved cards that expire after being saved stay listed and selectable, including as the default, in demo/dev builds

`lib/features/payments/application/saved_cards_controller.dart:142` (found by r2-rider2)

**What happens:** Demo build. In August 2026 the rider saves a card expiring 09/26. In October 2026 Select Ride still lists 'Visa •••• 4242 · Expires 09/26' and preselects it if it is the default. The ride is booked against an expired card with no warning.

**Why:** Expiry is checked only when a card is added (CardInput.expiryInFuture in add()). list() returns every stored card. RideSelectionController.savedCardItems offers every listed card as a booking method, and the Payments tab offers it as the default (wallet.dart:987). Neither checks expMonth/expYear against today. A card that expired after it was saved can therefore be preselected and used to book.

**Suggested fix:** Filter out expired cards, or show them as disabled, when building the payment lists (CardInput.expiryInFuture(card.expMonth, card.expYear)). Fall back to the default method when the saved default card has expired.

### L89. A failed PATCH of the default payment method is swallowed, and the next read() puts the server's old default back, so the rider's choice silently reverts

`lib/features/payments/data/api_payment_method_repository.dart:55` (found by r2-rider3)

**What happens:** Release build with a flaky network. At Select Ride the rider switches from Cash to Google Pay. The PATCH /payment-methods/default fails and is logged as payments.default_save_failed. They back out and open Select Ride again. The GET succeeds with defaultMethodId 'cash', and Cash is preselected again, so the rider may book with a method they had changed away from.

**Why:** save() sets `_defaultId = brand` first and then only logs a PATCH failure. Nothing retries the PATCH. read() then overwrites `_defaultId` with the server's `defaultMethodId` whenever the GET succeeds. RideSelectionController calls read() on every Select Ride open (restoreDefaultPayment), so after one failed PATCH the next open preselects the old method with no message.

**Suggested fix:** Keep a pending-save flag: retry the PATCH on the next read(), and don't let the server value overwrite the local choice until the PATCH succeeds. Or surface the failure so the UI can tell the rider.

### L90. Card brand rejection error is a hardcoded English string in a localized form

`lib/features/payments/presentation/add_card_page.dart:125` (found by rider4)

**What happens:** App language Swedish; rider types '3782 8224 6310 005' in Add card → red line 'We accept Visa and Mastercard' among Swedish labels.

**Why:** `_numberError` returns `CardInput.brandError` ('We accept Visa and Mastercard', saved_cards_controller.dart:67) while every sibling error on the same field uses `context.l10n.*` (`cardCheckNumber`, `cardUseMmYy`, `cardExpired`, `cardCvc3`). There is no ARB key for this text (no match in app_en/sv/fr.arb), so a Swedish or French rider typing an Amex/Diners number sees an English error under the number field.

**Suggested fix:** Add an ARB key (e.g. `cardBrandUnsupported`) and return `context.l10n.cardBrandUnsupported` from `_numberError`.

### L91. After a late GPS fix, the 'Location off, set pickup' placeholder is passed through as the booking pickup label and overwrites the address Home just detected

`lib/features/pickup/application/pickup_address.dart:18` (found by r2-rider4)

**What happens:** The rider denies location, then allows it in the browser and taps Where to -> a destination. _awaitCurrentFix gets a fix, but Select ride shows the pickup as 'Location off, set pickup' next to a map centred on their real position.

**Why:** isUnusablePickupLabel only rejects empty text, 'current location' and raw coordinates. bookingPickupAddress therefore returns locationOffPickupLabel unchanged instead of reverse-geocoding the real position. Home reaches it with a real fix in two ways. (1) The first detect failed or was denied, and the fix arrives later through _awaitCurrentFix: _prefillPickup keeps address: clean, the old placeholder, at home.dart:811. (2) The recover path above. SelectRide then opens with pickupAddress 'Location off, set pickup' (translated by L10n.place) and pickupIsFallback false. Set pickup later re-resolves it because its own _isPlaceholder covers 'location off', but Select ride, and the pickup Home remembers in _pickupAddress, say location is off while it works.

**Suggested fix:** Treat locationOffPickupLabel (isPlaceholderPickupLabel) as unusable in isUnusablePickupLabel/bookingPickupAddress so a real point is reverse-geocoded.

### L92. Fallback 'Dropped pin · lat° N lng° E' pickup label is hard-coded English and is saved as the booking address

`lib/features/pickup/application/pickup_address.dart:35` (found by rider1)

**What happens:** French rider drags the pin to a spot without a street address and confirms: pickup card, Finding screen, Waiting sheet and History all read 'Dropped pin · 59.32930° N 18.06860° E'.

**Why:** droppedPinPickupAddress builds an English sentence ('Dropped pin · …° N …° E') with no ARB key. SetPickupPage assigns it to `_address` when reverse geocoding yields nothing (:565) and it is shown in the pickup card `Text(_address, ...)` (:1137), then on confirm (:754-756) it is returned as `SetPickupResult.address`, persisted via `_spotsController.remember` and used as the ride's pickup label, so it stays English on Finding/Waiting/History and is sent to the driver. Reproduced under L10n.use('fr'): 'Dropped pin · 59.32930° N 18.06860° E'.

**Suggested fix:** Add an ARB message with a {coords} placeholder (and localized N/S/E/W) and render it through L10n; store the coordinates, not the sentence, as the booking label.

### L93. Pickup spot chips and the booked pickup label use hard-coded English ('Main entrance', 'Side entrance', 'Parking', 'Near Home', 'Previously used', 'Short walk')

`lib/features/pickup/application/pickup_spots_controller.dart:75` (found by rider2)

**What happens:** Swedish-language rider on Set pickup sees 'Main entrance / Front of the building' chips among otherwise Swedish copy and confirms; the booking's pickup reads 'Klockarvägen 37 – Main entrance'.

**Why:** The app ships en/sv/fr ARB files (l10n.yaml, app_sv.arb, app_fr.arb) and none contains these strings. The titles are rendered on the Set pickup chips (set_pickup_page.dart:1217-1222) and, via pickupSpotLabel, become the confirmed pickup address ('Klockarvägen 37 – Main entrance') that is booked and shown to the driver. Only the spot placement is documented as a mock; the labels are production UI. pickup_location.dart:228 likewise shows a literal 'CURRENT' button text.

**Suggested fix:** Move the titles/subtitles to the ARB files (L10n.current.*) and localize the 'CURRENT' label.

### L94. Confirm pickup spot shows untranslated 'Current location' / 'Pickup location' / 'Location off, set pickup' in its search field and address caption

`lib/features/pickup/presentation/confirm_pickup_spot.dart:170` (found by rider1)

**What happens:** French rider on Home with location on taps the pickup field → 'Confirmer le point de départ' page opens with the search box and the grey address line reading 'Current location'; moving the pin where no street resolves shows 'Pickup location'.

**Why:** ConfirmPickupSpot writes the English constants straight into the search TextField and the address Text instead of going through L10n.place: initState copies `widget.initialAddress` into `_address` and `_search.text` (:134, :143), and Home passes `'Current location'` there (home.dart:752 `cleanAddress = gps != null ? 'Current location' : ...` and :760 `(_pickupAddress ?? 'Current location')`). Inside the page `_address = 'Current location'; _search.text = _address;` (:170-171, :271-272) and `pickupLocationFallbackLabel` ('Pickup location', :228) are assigned the same way. They are rendered with `TextField(controller: _search, ...)` at :459 and `Text(_address, ...)` at :515 with no translation. L10n.place (l10n.dart:92-96) is only applied by shortenPlace/compactAddress on other screens, never here. The page is on the Book-now path (home.dart:756 ConfirmPickupSpot.open) and on route change (route_change_flow.dart:74).

**Suggested fix:** Keep the English sentinel internally but render `L10n.place(_address)` / `L10n.current.pickupLocation` in the TextField and Text, and extend L10n.place to cover pickupLocationFallbackLabel.

### L95. `_idle` turns a superseded (null) reverse-geocode into the 'Pickup location' fallback and can overwrite the newer resolved address

`lib/features/pickup/presentation/confirm_pickup_spot.dart:222` (found by rider1)

**What happens:** Rider drags the pin, lets go (request A starts), nudges it once more and lets go (request B starts). B answers first and shows 'Klockarvägen 37'; A then answers (as null, superseded) and the card flips to 'Pickup location'. The rider confirms and the booking/driver gets the neutral label 'Pickup location' although the street had been resolved.

**Why:** Every `onCameraIdle` (line 345-349) calls `_idle()`, which awaits `_pickup.reverse(_center)`. `PickupMapController.reverse` (pickup_controller.dart:53-74) deliberately returns `null` for a call that was superseded by a newer one (`if (!_stale.isCurrent(generation)) return null;`). `_idle` does not distinguish 'superseded' from 'no address': `isUnusablePickupLabel(null)` is true, so it does `setState(() { _address = pickupLocationFallbackLabel; _search.text = label; })`. The two lookups are independent HTTP requests (AppGeocoding dedupes only identical keys), so when the newer request B completes before the older request A, B's continuation writes the real street and A's continuation then overwrites it with 'Pickup location'. `_confirmPosition` (line 296-305) books `confirmedPickupAddress(_address, position)`, which keeps that fallback string. Contrast set_pickup_page.dart:550-570 `_resolveAddressNow`, which guards with its own `_resolveGeneration` and `_isAwayFrom(at, _center)` before applying.

**Suggested fix:** Give `_idle` its own generation counter (or read `_pickup`'s) and return without touching state when the lookup was superseded or when `_isAwayFrom(at)`; only apply the fallback label when the current lookup genuinely returned no address.

### L96. Set pickup can stay on 'Finding the address…' forever when the pin returns near its last rest point during a lookup

`lib/features/pickup/presentation/set_pickup_page.dart:556` (found by r2-rider3)

**What happens:** The rider moves the pin, and while its street loads they nudge the map again and let it settle back on almost the same spot. The pickup card keeps saying 'Finding the address…' indefinitely, and the confirmed pickup is 'Dropped pin · …' instead of the street.

**Why:** _resolveAddressNow returns early when the pin moved during the lookup (_isAwayFrom(at, _center)) without clearing _resolving, and relies on a later resolve to reset it. A later resolve is only started by _onCameraIdle when _center is more than about 15 m from _routeStart, and _routeStart is that same 'at' point. If the rider drags away while the lookup is running and lets go within about 15 m of where it started, no new resolve runs. _resolving stays true and the card subtitle reads 'Finding the address…' with no lookup running. _addressIsStale also stays true, so Confirm books a dropped-pin label although the street was known.

**Suggested fix:** Reset _resolving (and re-run the lookup for the current point) instead of returning silently when the pin moved.

### L97. Set pickup address search has no try/catch (a failed geocode shows no feedback) and no staleness guard against a pin moved while it was pending

`lib/features/pickup/presentation/set_pickup_page.dart:702` (found by rider3)

**What happens:** Rider types 'Storgatan 1' and submits, then immediately drags the pin to the exact entrance; 3-8 s later the geocode answers and the pin jumps back to Storgatan 1 with that label, the quote re-runs, and the rider confirms a pickup they did not choose.

**Why:** _searchAddress closes the sheet, then `final found = await _pickup.search(text)` (PickupMapController.search -> geocoding.geocodeAddress, up to the 8 s API timeout, no generation/stale check and no try/catch) and unconditionally calls `_glideTo(found.position, address: ...)`, which rewrites _center/_routeStart/_address and animates the camera. While the search is pending the page is fully interactive (no busy state), so a drag, a spot chip or My location can already have moved the pin; the old search then overrides it. ConfirmPickupSpot._lookup (confirm_pickup_spot.dart:286-293) has the same shape. The page's own reverse lookups and requotes are generation-guarded (RIDE-12), only the forward search is not. A thrown search (offline) is also uncaught here, so the snackbar 'addressNotFoundMoveMap' never appears.

**Suggested fix:** Bump a generation (or compare _center/_routeStart before and after) around the search and ignore a result once the pin has moved or a newer search started; wrap in try/catch and show the not-found snackbar on failure.

### L98. Set pickup shows the payment method name and detail in English ('Cash' / 'Pay the driver in cash') in every language

`lib/features/pickup/presentation/set_pickup_page.dart:1431` (found by r2-rider3)

**What happens:** App in Svenska, rider books a cash ride. Select Ride shows 'Kontant', then the Set pickup sheet (always shown before Book now) shows 'Cash' / 'Pay the driver in cash'. With a wallet split, the remainder row reads 'Cash  209 kr'. The same happens in French.

**Why:** SelectRide builds the SetPickupPayment from the raw catalog item: `name: item?.name ?? context.l10n.payCash, detail: item?.detail ?? ''` (select_ride.dart:1286-1289). The catalog item holds English text (ride_selection_repository.dart:184-189: 'Cash', 'Pay the driver in cash', 'Movera Wallet', 'Pay from your balance', 'Pays when the search starts'). Select Ride's own payment button translates these with paymentNameFor/paymentDetailFor (select_ride.dart:2572, 2586). Set pickup prints `_payment.name` and `_payment.detail` as they are, and also uses `_payment.name` as the remainder label of a wallet split.

**Suggested fix:** Render `paymentNameFor(_payment.brand, _payment.name)` and `paymentDetailFor(_payment.brand, _payment.detail)` in Set pickup, or pass the translated strings from SelectRide.

### L99. CurvedAnimations created in build leak a status listener on _lift/_sheet on every rebuild

`lib/features/pickup/presentation/set_pickup_page.dart:1491` (found by r2-rider3)

**What happens:** A rider who adjusts the pin many times on Set pickup triggers dozens of rebuilds. Each one adds five status listeners to the two controllers, so every pin lift and sheet status change has to iterate an ever-growing listener list, and leak tracking reports undisposed CurvedAnimations.

**Why:** _PickupPin.build creates a new CurvedAnimation(parent: lift, ...) on every build, and _reveal creates one on _sheet for each of four sections on every build of SetPickupPage. In Flutter 3.47 the CurvedAnimation constructor calls parent.addStatusListener(_updateCurveDirection), which is removed only by dispose() (animations.dart:392/441). Its docs say 'Do not recreate it on every build as it would leak'. SetPickupPage rebuilds on every spot load, address resolve, requote, glide and bags tap, so the listeners and the CurvedAnimations they retain pile up for the page's lifetime.

**Suggested fix:** Create the CurvedAnimations once (in initState, or in a StatefulWidget for _PickupPin) and dispose them.

### L100. Account security error messages are English literals shown on the Security screen

`lib/features/profile/application/account_security_controller.dart:42` (found by rider4)

**What happens:** Server returns 500 for the security endpoint; French rider opens Account → Sécurité and reads 'Account security is unavailable right now.' under the tile; tapping 'Sign out other devices' after a failure shows 'Could not update active sessions.'

**Why:** The controller stores `errorMessage = 'Account security is unavailable right now.'` (:42) and `'Could not update active sessions.'` (:67). security.dart renders them to the rider: `body: _security.errorMessage ?? context.l10n.securityUnavailableBody` (:72) and `Text(_security.errorMessage!, ...)` (:238). Because errorMessage is non-null whenever load() fails, the localized securityUnavailableBody is never used in the failure case, so fr/sv riders always see English.

**Suggested fix:** Set errorMessage from L10n.current (reuse securityUnavailableBody and add a key for the sign-out failure).

### L101. 'Sign out other devices' reports failure when the sign-out succeeded but the follow-up GET failed

`lib/features/profile/data/account_security_repository.dart:14` (found by r2-rider4)

**What happens:** The rider confirms Sign out other devices. The POST returns 200 and the GET times out. The Security page shows 'Could not update active sessions.' and still lists the iPhone session, although it was revoked. Retrying fails with 403.

**Why:** signOutOtherDevices() POSTs the sign-out and ignores its response, although the mock returns the new `security` in that response. It then does a separate GET. If the POST succeeds but the GET fails (network drop, timeout), the controller's catch sets 'Could not update active sessions.' and leaves the old state, still listing the other devices and still holding a fresh reauthenticatedAt. The server has already revoked those sessions and cleared reauthenticatedAt. A retry therefore gets 403 reauth_required and shows the same error.

**Suggested fix:** Decode the `security` from the POST response. If only the refresh fails, report success and reload in the background.

### L102. Menu greeting falls back to the English literal 'Welcome to Movera' in every language

`lib/features/profile/data/profile_repository.dart:25` (found by r2-rider1)

**What happens:** A Swedish rider without a saved name opens the menu and sees 'Welcome to Movera' in English above Swedish menu items.

**Why:** For a rider with no name, RiderMenuPage._profileHeader shows controller.displayName(), which returns the constant ProfileRepository.emptyDisplayName. That constant is not translated and has no ARB entry. Account home uses the translated context.l10n.accountAddYourName in the same case. A rider with no name is common: a returning rider after sign-out, or the skipped name step reported above.

**Suggested fix:** Use a localized string (e.g. L10n.current for a new key) for the empty-name greeting.

### L103. Pending profile sync (name/consents) is lost on app restart; class doc promises resend on launch

`lib/features/profile/data/synced_profile_repository.dart:315` (found by rider1)

**What happens:** Rider renames themselves while offline, closes the app; next launch the server still has the old name until the rider edits the profile again.

**Why:** `_syncPending` is a plain in-memory field (301). `save()` keeps the local copy and swallows the PATCH failure, setting `_syncPending = true` (341-352); `hydrate()` only resends `if (_syncPending)` (313-316). After the app is killed the flag is false again, so a name/consent change that never reached the server is not resent on the next launch, contrary to the class comment ("sent again with the next save or launch"). The driver app shows the rider's name from this profile.

**Suggested fix:** Persist the pending flag (e.g. a `movera_profile_sync_pending` pref) and read it in `hydrate`, or compare a stored "last synced" hash with the cache.

### L104. Choice sheets (language, gender) mark the current option only with a check icon; ListTile.selected is not set

`lib/features/profile/presentation/account_widgets.dart:414` (found by r2-rider2)

**What happens:** A screen-reader user opens Language and hears 'English', 'Français', 'Svenska' with no indication of which is active.

**Why:** showAccountChoice renders each option as a ListTile whose only selected indicator is `trailing: Icon(Icons.check_rounded)` with no semanticLabel. ListTile(selected:) is not set, so no selected flag reaches the semantics tree. It is used by the language picker (language_picker.dart:18) and the gender picker.

**Suggested fix:** Pass `selected: option == selected` to ListTile (or wrap in Semantics(selected: ...)).

### L105. Language picker ignores the zone config's `languages.available` list it is documented to honour

`lib/features/profile/presentation/language_picker.dart:21` (found by r2-rider4)

**What happens:** An operator sets a zone's `languages.available` to ['fr','en']. A rider in that zone still sees and can pick 'SV · Svenska', and that choice wins over the zone forever.

**Why:** AppLanguages.available is documented as 'what the user may pick' (zone_settings.dart:27-28), and readAppLanguages parses and keeps it. pickAppLanguage always offers every shipped language, and AppLanguageController.choose saves any supported code. Neither reads `document.languages.available`, so an admin restriction of a zone's languages has no effect on the rider app.

**Suggested fix:** Keep the zone's available list in AppLanguageController, filter the picker options by it, and fall back to the zone default when a saved choice is not available.

### L106. Password 'Last changed' date is formatted from a UTC DateTime, so it shows the UTC day

`lib/features/profile/presentation/security.dart:46` (found by r2-rider1)

**What happens:** passwordUpdatedAt '2026-03-10T23:30:00Z' (00:30 on 11 March in Stockholm) shows 'Last changed 3/10/2026'.

**Why:** AccountSecurityState.fromJson converts every timestamp with `.toUtc()`, and _passwordLine passes it straight to DateFormat, which formats the UTC fields. A change made late in the evening (UTC) shows the previous day for Stockholm riders.

**Suggested fix:** Format `when.toLocal()`, or the zone wall time.

### L107. Sign out other devices stays tappable after the 5-minute reauthentication window passes, then silently does nothing

`lib/features/profile/presentation/security.dart:214` (found by r2-rider1)

**What happens:** The rider opens Security right after reauthenticating, leaves it open for 6 minutes, taps Sign out other devices and confirms. Nothing happens: no request is sent, no error appears and the other sessions remain.

**Why:** hasFreshReauthentication is checked only when the page builds. Nothing rebuilds the page when the 5-minute window ends. The tile keeps its 'server revokes others' copy and its onTap, the rider confirms in the sheet, and then AccountSecurityController.signOutOtherDevices() re-checks hasFreshReauthentication and returns early, with no error, no notify and no request.

**Suggested fix:** Re-check freshness after the confirm and show reauthBeforeRevoke (or rebuild with a timer when the window ends) instead of returning silently.

### L108. Login activity shows a dangling separator when a session has no place ('This session  ·  ', '  ·  Movera')

`lib/features/profile/presentation/security.dart:261` (found by r2-rider1)

**What happens:** In the demo build, Account > Security > Login activity shows 'This device' over 'This session  ·  ' with an empty place after the separator.

**Why:** _LoginTile always interpolates session.place, which defaults to '' when the server omits it. The demo mock's only session has place ''. The current session therefore renders 'This session  ·  ', and another session renders '  ·  Movera'.

**Suggested fix:** Leave out the separator and the place when the place is empty.

### L109. Promotion details opened outside Select Ride use the built-in category list instead of the live RideCatalogController catalog, so admin-disabled, renamed or added categories show wrongly

`lib/features/promotions/presentation/promotion_details_sheet.dart:77` (found by rider2)

**What happens:** Server catalog has the 7 seed categories. Rider opens Pay with → taps the promotion row → sheet lists Van, Wheelchair, Business, Airport, Kids seat, Women driver and Delivery as 'Included', none of which exist on Select Ride.

**Why:** `PromotionDetailsSheet.open` defaults `categories` to `AppScope.instance.rideCatalog.rides()`. In di.dart:337 `rideCatalog` is `RideSelectionRepository()`, whose `builtInRides` is the 14-item fallback list that explicitly includes seven 'Categories the admin may switch on later' (van, wheelchair, business, airport, kids, women, delivery; ride_selection_repository.dart:84-162). The live catalog is `AppScope.instance.catalog.current` (di.dart:341, RideCatalogController), which SelectRide uses for its own `_openPromotionDetails`. PayWithPage (pay_with_page.dart:271 `PromotionDetailsSheet.open(context, promo)`) and the default `onTap` of PromotionTicket (promotion_ticket.dart:54) use the default, so the 'Prices with promotion' section lists categories the rider cannot book and, when `rideTypes` is empty, marks each 'Included'.

**Suggested fix:** Default to `AppScope.instance.catalog.current` (the server/cached catalog) instead of `rideCatalog.rides()`.

### L110. 'Days left' on a promotion uses local-midnight Duration.inDays, so it is one day short across spring-forward and says 'Ends today' for a promotion that ends tomorrow

`lib/features/promotions/presentation/promotion_details_sheet.dart:112` (found by r2-rider2)

**What happens:** I reproduced this with a throwaway test run under TZ=Europe/Stockholm. A promotion with endsAt '2026-03-30T18:00:00' viewed at 2026-03-29 12:00 showed 'Ends today' (expected '1 day left'). A promotion ending on 15 Apr viewed on 1 Mar showed 'Valid until 15 Apr 2026 · 44 days left' (expected 45).

**Why:** validityText builds two local midnights and uses `last.difference(today).inDays`. When the range includes the spring-forward night, the two midnights are 23 h apart per transition, so inDays rounds down. Every count across the DST change is one day short. When the promotion ends the day after the change, days is 0 and the sheet shows 'Ends today'.

**Suggested fix:** Count calendar days with UTC dates: `DateTime.utc(ends.year, ends.month, ends.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays`.

### L111. Reservation cancel reasons written by the app ('no_driver_found', 'rider_cancelled_live') have no translation and show as English text

`lib/features/reservations/application/reservation_controller.dart:302` (found by rider-j8)

**What happens:** App language is Swedish. The rider resolves a no-driver ride from the chrono sheet, then opens it in History > Cancelled. The banner reads 'Avbokad. No driver found' instead of 'Avbokad. Ingen förare hittades'. A live-cancelled reservation reads 'Avbokad. Rider cancelled live'.

**Why:** resolveNoDriverFound records reason 'no_driver_found', and the live-ride cancel records 'rider_cancelled_live' (reservation_live_ride.dart:81, reservation_ride_realtime.dart:148). The cancelled reservation's banner (upcoming_reservation.dart:288 -> ReservationFormat.statusBody -> reasonLabel) looks codes up in CancellationReason ids and _reasonLabels. That map translates 'system_no_driver', not 'no_driver_found'. Neither code matches, so both fall through to the snake_case prettifier and come out as the English words 'No driver found' and 'Rider cancelled live' in every locale.

**Suggested fix:** Record the canonical 'system_no_driver' code, or add 'no_driver_found' and 'rider_cancelled_live' to _reasonLabels with translated labels.

### L112. ReservationPriceChange treats any change under 0.5 major units as unchanged, so EUR/TND edits under half a unit show a zero difference and a 'price unchanged' summary

`lib/features/reservations/domain/reservation.dart:178` (found by rider-j8)

**What happens:** A Paris (EUR) reservation was booked at 12.35 €, and the edit re-quotes it at 12.70 €. Review changes shows Previous '12,35 €', New '12,70 €', Difference '0,00 €'. The rider confirms an edit that costs 0.35 € more while being told the difference is zero.

**Why:** ReviewChangesPage builds ReservationPriceChange(previous: original.price, next: draft.price, currency: original.currency). It shows the previous and new prices, then a difference of kr(0) whenever `unchanged`. The 0.5 threshold suits whole-kronor SEK display only. EUR is formatted with cents and TND with millimes (formatMoney), so a real change of up to 0.49 EUR or 0.499 DT is shown as a zero difference. The class also holds a single currency, so when the edited pickup is priced in another currency (draft.currency = selection.currency) the two amounts are subtracted across currencies.

**Suggested fix:** Compare in minor units with Money.fromLegacyMajor(next, currency) != Money.fromLegacyMajor(previous, currency), or set the threshold at half a displayed unit per currency. Refuse, or show separately, a change across currencies.

### L113. A failed no-driver resolve escapes as an unhandled async error: no message, and Rebook is never opened

`lib/features/reservations/presentation/home_reservation_chrono.dart:124` (found by rider-j8)

**What happens:** Web storage write fails (quota, blocked storage) when the rider taps Rebook on the 'No driver found' sheet. The sheet closes, nothing happens, no toast appears, and an uncaught error is logged. The chrono stays red.

**Why:** _showNoDriverFound is started with unawaited(...) (lines 106 and 162) and has try/finally but no catch. resolveNoDriverFound -> cancel -> LocalReservationRepository.cancelReservation -> _commit -> PrefsReservationStorage.write, which rethrows on a storage failure (local_reservation_repository.dart:38-41). The error then reaches the zone as uncaught. The rider sees nothing, the ride stays in the no-driver state, and the Rebook flow they chose never opens. _onTick has the same unguarded unawaited(startLiveIfDue) path. The Upcoming page's cancel, by contrast, catches and shows reservationErrorMessage.

**Suggested fix:** Catch around resolveNoDriverFound, record the error and show MoveraToast with reservationErrorMessage(error, ReservationAction.cancel), as UpcomingReservationPage._cancel does.

### L114. An unresolved 'No driver found' ride stays the chrono's next ride and stops a later ride's live screen from auto-opening

`lib/features/reservations/presentation/home_reservation_chrono.dart:199` (found by rider-j8)

**What happens:** Demo build: ride A (09:00) timed out without a driver and the rider dismissed the sheet. Ride B (11:00) gets a driver, and at 10:58 its driver goes en route. Home keeps showing A's red badge and never opens B's live ride. The rider only finds B through History > Upcoming.

**Why:** _nextRide always returns the earliest upcoming reservation. A no-driver-found ride is still `upcoming` (driverAssignmentPending) until the rider resolves it. If they swipe the sheet away, _promptedNoDriverId stops it reappearing, but the ride stays first. _openLiveIfNeeded and _promptNoDriverIfNeeded only look at _nextRide(), so a later reservation that gets a driver and goes en route is never auto-opened, and tapping the chrono opens the stale no-driver sheet again.

**Suggested fix:** For live auto-open, pick the first ride that reveals a driver. For the chrono, skip rides already prompted as no-driver when a later actionable ride exists.

### L115. Chrono screen-reader label reads 'Reservation in Now' for a due or live ride

`lib/features/reservations/presentation/home_reservation_chrono.dart:255` (found by rider-j8)

**What happens:** During a scheduled trip in progress, VoiceOver on the Home chrono announces 'Reservation in Now' (sv: 'Bokning om Nu', fr: 'Réservation dans Maintenant').

**Why:** remainingCompact returns L10n.now ('Now' / 'Nu' / 'Maintenant') when less than 60 s remain, and also for every past pickup (driver arrived, in progress). That value is interpolated into reservationIn ('Reservation in {time}'), which gives broken sentences in all three languages.

**Suggested fix:** When the remaining time is under a minute or past, use a separate label (for example 'Reservation now' or a status-based label) instead of interpolating 'Now'.

### L116. Home reservation chrono's countdown overflows its 54 px disc at large text sizes (no textScaler clamp); in French 'Maintenant' breaks mid-word

`lib/features/reservations/presentation/home_reservation_chrono.dart:283` (found by r2-rider4)

**What happens:** French rider with a reservation, in its last minute: primary 'Maintenant' wraps to about 3 lines * 13 = 39 px, plus 12 = 51 > 41 → RenderFlex overflow (about 10 px), text spills past the disc. At 1.3x text, sv/fr '45 min' (2 lines of 16.9 px) gives 46 > 41. At 2x in English, '2h'/'45m' gives 11+1+26+19.8 = 58 > 41. The matrix tests render Home without reservations, so the chrono is never laid out there.

**Why:** The chrono is a fixed 54x54 box. Inside Padding(8,7,8,6) the Column gets 38x41 px and holds an 11 px car image, 1 px, and the countdown Text(s) with no maxLines. French strings are longer: 'Maintenant' (now) and '{m} min' (durMinutes) at 13 px w700 are wider than 38 px and wrap. 'Maintenant' is one word, so it breaks per character onto about 3 lines. The badge Stack uses Clip.none, so overflowing text paints outside the circle over the map.

**Suggested fix:** Wrap the countdown in FittedBox(fit: BoxFit.scaleDown) with maxLines: 1, or use a short 'now' form for the chrono.

### L117. Reservation cancel reason codes 'no_driver_found' and 'rider_cancelled_live' show as raw English text

`lib/features/reservations/presentation/reservation_format.dart:39` (found by r2-rider3)

**What happens:** A French rider resolves a 'No driver found' reservation. The cancelled reservation reads 'Annulée. No driver found', and History shows 'Motif : No driver found'. A ride cancelled from the live screen shows 'Rider cancelled live' in every language.

**Why:** The controller records no-driver cancels with the code 'no_driver_found' (ReservationController.noDriverFoundReason), and the live screen records 'rider_cancelled_live'. reasonLabel only maps CancellationReason ids and the _reasonLabels table, which has 'system_no_driver' but not these two codes. Both fall through to the snake_case prettifier, so they show as untranslated English in the reservation status body (resBodyCancelledReason) and in the History detail 'Reason:' line. Verified with a throwaway test in fr: reasonLabel('no_driver_found') returned 'No driver found' and reasonLabel('rider_cancelled_live') returned 'Rider cancelled live'.

**Suggested fix:** Map 'no_driver_found' to termNoDriverFound and 'rider_cancelled_live' to a translated label in _reasonLabels, or record 'system_no_driver' instead.

### L118. Reservation reasons the app itself writes ('no_driver_found', 'rider_cancelled_live') are shown as English text in every language

`lib/features/reservations/presentation/reservation_format.dart:60` (found by r2-rider3)

**What happens:** App in Svenska, a reservation times out without a driver and the rider taps the No-driver sheet (home_reservation_chrono.dart:124). The reservation then reads 'Avbokad. No driver found' and History reads 'Anledning: No driver found'. Cancelling a live scheduled ride and skipping the reason sheet shows 'Anledning: Rider cancelled live'.

**Why:** ReservationController.resolveNoDriverFound stores `noDriverFoundReason = 'no_driver_found'` (reservation_controller.dart:302, 325), and the live scheduled ride stores `'rider_cancelled_live'` when the rider cancels without a reason (reservation_live_ride.dart:81, reservation_ride_realtime.dart:148). Neither is a CancellationReason id or a key of `_reasonLabels`: the map has 'system_no_driver', not 'no_driver_found'. Both fall through to the snake_case regex, which turns them into English words. The result appears in the History detail ('Reason: …') and in the cancelled-reservation status body.

**Suggested fix:** Add 'no_driver_found' (-> termNoDriverFound) and 'rider_cancelled_live' (-> a translated 'Cancelled by you' label) to the reason map, or store contract codes that are already mapped.

### L119. cardDate 'Tomorrow' label breaks on the spring-forward day because today.add(Duration(days:1)) is not the next local midnight

`lib/features/reservations/presentation/reservation_format.dart:143` (found by rider3)

**What happens:** On Sunday 29 Mar 2026 a Stockholm rider with a reservation on Monday 30 Mar sees 'Mon, 30 Mar' on the upcoming card instead of 'Tomorrow 30 Mar'. Same for Tunisia or any zone with DST on its switch day.

**Why:** cardDate compares `day == today.add(const Duration(days: 1))` where today is a local midnight. Dart's add() works in absolute time, so on the DST switch day the result is 01:00 of the next day, not midnight (verified by throwaway test: DateTime(2026,3,29).add(Duration(days:1)) == 2026-03-30 01:00:00 under Europe/Stockholm). The equality then fails and the reservation card falls through to weekdayDate instead of 'Tomorrow, 30 Mar'.

**Suggested fix:** Build tomorrow as `DateTime(now.year, now.month, now.day + 1)` (calendar arithmetic) instead of adding a Duration.

### L120. Live scheduled ride rebuilds ride notes by substring search: 'Bags 3+' shows as plain Bags, and rider free text can turn on Pet/Baby/Child chips

`lib/features/reservations/presentation/reservation_live_ride.dart:34` (found by r2-rider2)

**What happens:** A rider books for later with 3+ bags and a note 'Petra will meet the driver'. The live ride sheet shows 'Bags' (not 3+) and a Pet chip, and the driver-facing summary is wrong.

**Why:** notesOf turns the stored note string back into RideNotes with note.contains('Bags'|'Pet'|'Baby'|'Child'). manyBags is never set, so a 'Bags 3+' booking shows as 1-2 bags on the live screen. Any free text that contains those substrings sets the flags. The note holds the rider's own words joined with ' · ' (SelectRide._driverNote), so 'Petra meets you' sets pet and 'Child seat in my bag' sets child.

**Suggested fix:** Split on ' · ' and ', ' and match the exact labels from RideNotes.selected, including 'Bags 3+'. Better, store RideNotes structurally on the reservation.

### L121. Scheduled live ride offers route/destination changes that cannot work: the route quote is sent to /rides/{reservationId}, which the API does not know (404)

`lib/features/reservations/presentation/reservation_live_ride.dart:64` (found by r2-rider2)

**What happens:** During a scheduled ride with the driver en route, the rider opens ride details and changes the destination. Pricing the change fails (404), or in the cancel sheet they choose 'change destination' instead of cancelling and get an error.

**Why:** pageFor reuses WaitingForDriver and does not turn off route editing. _routeEditable is true until the ride ends, so the three-dots route screen and the cancel sheet's 'change destination' offer are shown. RouteChangeController then posts to /api/v1/rides/{rideId}/route-quote with the reservation id (rsv_...). The API has no such ride: the in-process mock answers 404 not_found when rides[id] is null. The rider is offered an edit that cannot work, and a successful local change would never reach the reservation record anyway.

**Suggested fix:** Add a WaitingForDriver flag to turn off route changes for reservation live rides, or route reservation edits through ReservationController.

### L122. Icon-only close/back buttons in the scheduling flow have no accessible name; two are 42 px, below the app's 44 px floor

`lib/features/reservations/presentation/ride_scheduled.dart:128` (found by r2-rider4)

**What happens:** After booking a scheduled ride, a VoiceOver/TalkBack user on RideScheduledPage hears 'button' with no name for the only exit control. The same happens on the date/time step's back button and the address step's back button, so the scheduling flow cannot be navigated by name.

**Why:** Several icon-only navigation buttons are a bare InkWell around an Icon with no tooltip, semanticLabel or Semantics label. Screen readers announce an unlabeled button. Two of them are also 42x42, below the app's own 44 px floor (A11y.minTapIOS, 'the floor for every tap target').

**Suggested fix:** Use MoveraIconButton (tooltip + 48 px) or wrap in Semantics(button: true, label: l10n.close/back).

### L123. Completed reservations opened from History are headed 'Upcoming ride', and both completed and cancelled ones say 'Your ride is reserved for ...'

`lib/features/reservations/presentation/upcoming_reservation.dart:235` (found by rider-j8)

**What happens:** History > Completed > tap a finished scheduled ride. The header reads 'Upcoming ride' and 'Your ride is reserved for Mon, 5 Oct at 10:00' above a 'Completed' status banner. A cancelled ride reads 'Cancelled reservation' and then 'Your ride is reserved for ...'.

**Why:** History's Completed and Cancelled tabs open every non-ondemand reservation in UpcomingReservationPage (ride_history.dart:469-480). The headline only checks isCancelled, so a completed ride gets resUpcomingRide ('Upcoming ride'). The subtitle is always resReservedFor ('Your ride is reserved for {date} at {time}'), including on cancelled and completed rides. When admin turned showDriverOnAccept off, a completed ride also falls into the `else if (ride.driverAssigned)` branch, because status.hasDriver includes completed. That branch shows 'Driver details appear when your driver is on the way.' on a finished trip.

**Suggested fix:** Choose the title and subtitle by status: completed and cancelled get past-tense copy with no 'reserved for'. Limit the resDriverOnTheWay hint to status.isUpcoming.

### L124. Editing a reservation keeps its dispatch status: a searching or no-driver ride moved to a later day stays 'searching'

`lib/features/reservations/presentation/upcoming_reservation.dart:374` (found by rider-j8)

**What happens:** A ride for 10:00 has reached 'No driver found' (status driverAssignmentPending). The rider opens it and edits the time to tomorrow 10:00. Home now shows the orange 'searching' badge for 24 hours, although the ride is a normal future booking.

**Why:** canEdit covers driverAssignmentPending (and the no-driver-found state), so the Upcoming page offers Edit. The edit goes through ScheduledRideBooking.confirm -> ReservationController.update with a patch that changes the time and route but not status. The ride keeps driverAssignmentPending. startLiveIfDue only moves `scheduled` to pending at T-2 and never back. In builds without dispatch, the rescheduled ride therefore shows the 'searching' dots badge on Home (HomeReservationChrono.searching) for the whole time until the new pickup, though no search is running. In mock builds the dispatch immediately assigns a driver to a ride that is now days away, because acceptAfter has long passed.

**Suggested fix:** When an edit moves the pickup out of the assignment window and no driver is assigned, include status: ReservationStatus.scheduled in the patch (the repository's updateReservation or the booking patch).

### L125. 'Things to know' cancellation line keeps saying 'free until …' after the free window has closed

`lib/features/reservations/presentation/upcoming_reservation.dart:440` (found by r2-rider4)

**What happens:** At 08:50 the rider opens a reservation for 10:00 (free until 09:00) and keeps the page open. At 09:05 it still reads 'Free until 09:00, then 50 kr', and the fee only shows once they tap Cancel.

**Why:** The cancellation summary is worked out from cancelTermsFor(ride) at build time. UpcomingReservationPage only rebuilds when the ReservationController notifies, and nothing rebuilds it on a timer. While the rider stays on the page past freeUntil, it still says cancelling is free until HH:mm. The cancel sheet works out fresh terms, so the fee does appear before confirming.

**Suggested fix:** Rebuild when freeUntil passes (a one-shot Timer), or word the line without the live 'until' state.

### L126. Driver card accessibility label hard-codes the English word 'plate'

`lib/features/reservations/presentation/upcoming_reservation.dart:506` (found by rider-j8)

**What happens:** App in Swedish: the screen reader announces 'Din förare Anna, Svart Volvo XC40, plate ABC 123'.

**Why:** ReservationDriverCard's Semantics label joins the translated resYourDriverName with the literal 'plate ${driver.plate}'. This is a different occurrence from the known ride_restore_coordinator.dart:620 one.

**Suggested fix:** Add an ARB key such as resPlateLabel('{plate}') and use it here.

### L127. A restored completion screen does not prime the mock transport, which restarts a whole fake ride (search, assignment, trip) for the finished trip

`lib/features/ride_booking/application/ride_restore_coordinator.dart:332` (found by r2-rider1)

**What happens:** Demo: the rider reloads right after 'Trip complete' appears, before payment settles. The restored summary sits at tripCompleted with no rating control for about 1.5 minutes while the mock re-runs a search and a trip in the background.

**Why:** pageFor calls primeResume only for the waiting surface (`surface == RestoredSurface.waiting && snapshot.status.isMatched`). For RestoredSurface.complete, RideCompleted subscribes to the fresh MockRideRealtime with nothing primed. subscribe() resets to findingDriver, arms the 25 s assignment, then walks the GPS approach, boarding and trip ticks. It POSTs accepted, driver_to_pickup and so on to /rides/:id/status for a completed trip. RideCompleted ignores the non-completion events, so a completion screen restored at tripCompleted, paymentProcessing or paymentFinalized gets no ratingPending (rating stays locked, the wallet charge is delayed) until the fake ride ends about 100 s later. The timers also keep running after the rider taps Done, because closeCompletedRide never cancels the transport.

**Suggested fix:** For a completed-surface restore, prime the mock to resume the post-trip flow (_startPostTripFlow from the stored stage), or have RideCompleted use a resync that never restarts dispatch.

### L128. Driver card screen-reader label says 'plate …' in English in every language (the recovery-barrier label is also English but only on screen for one frame)

`lib/features/ride_booking/application/ride_restore_coordinator.dart:620` (found by rider4)

**What happens:** Swedish VoiceOver user reloads during a live ride: the barrier announces 'Restoring active ride'; on the upcoming reservation the driver card announces 'plate ABC123'.

**Why:** Two Semantics labels bypass l10n: the ride-recovery barrier `Semantics(label: 'Restoring active ride', ...)` (:620) read aloud while a live ride is restored on cold start, and upcoming_reservation.dart:506 `'plate ${driver.plate}'` inside the driver card's Semantics label list. TalkBack/VoiceOver users on fr/sv hear English.

**Suggested fix:** Use L10n.current (e.g. rtConnectingBody or a new key) for both labels.

### L129. restoreFromBackend/backendReconcile never logs the `ride.restore.jump` record that DECISIONS R6 specifies for illegal jumps

`lib/features/ride_booking/application/ride_session.dart:98` (found by rider2)

**What happens:** Backend projection moves a session from `driverArriving` straight to `paymentFinalized` (the example in the code comment at 141-142). Per R6 a `ride.restore.jump` entry should be logged for diagnostics; no log line is emitted.

**Why:** docs/DECISIONS.md line 67 (R6) states that `restoreFromBackend` 'may jump; illegal jumps log `ride.restore.jump` and are not rejected'. `backendReconcile` (98-152) logs only `ride.restore.stale` when ordering rejects an event and otherwise assigns the status silently; `canTransition` is never consulted and the string `ride.restore.jump` does not exist anywhere in the repository (grep). Operators relying on that log to detect backend projections that skip states get nothing.

**Suggested fix:** In `backendReconcile`, when `!canTransition(status, backendStatus)` log `AppLog.info('ride.restore.jump', ...)` before assigning.

### L130. RideSession.reset() keeps the previous rider's booked category, payment method id and offer ceiling, and they carry into the next rider's adopted ride

`lib/features/ride_booking/application/ride_session.dart:205` (found by r2-rider2)

**What happens:** Rider A books a Premium ride (ceiling 600 kr, card_A), then signs out. Rider B signs in and opens a ride B booked on another device, adopted from GET /rider/trips/active, whose projection has no maxOfferMinor. B's search is stored and priced with A's 600 kr offer ceiling and A's payment method id, and Waiting loads waiting terms for A's category.

**Why:** reset() is documented as 'Back to "no ride" at the end of a rider's session'. It clears rideId, status, versions and quote, but not bookedCategoryId, bookedPaymentMethodId or bookedMaxOfferMinor. backendReconcile clears these fields only when both the current and the incoming ride id are non-null and differ. After reset, rideId is null, so the next ride never clears them. RideRestoreCoordinator._adoptBookingIds and BookingCoordinator's active-trip adoption then fall back to the stale session values whenever the server projection omits a field (`snapshot.maxOfferMinor ?? session.bookedMaxOfferMinor`). FindingDriverController.start writes them into the new snapshot, and WaitingForDriver prefers `ride.bookedCategoryId` over the stored category for the waiting-fee terms.

**Suggested fix:** Clear bookedCategoryId, bookedPaymentMethodId and bookedMaxOfferMinor in reset().

### L131. Ride completed driver panel shows the English fallback 'Vehicle details unavailable' when the matched driver has no vehicle fields

`lib/features/ride_booking/data/driver_repository.dart:55` (found by rider3)

**What happens:** A ride completes with a driver payload lacking vehicleMake/Model/Color; the Swedish Ride completed → driver info panel shows 'Vehicle details unavailable'.

**Why:** DriverRepository.current() builds DriverProfile with `vehicle: vehicle.isEmpty ? 'Vehicle details unavailable' : vehicle` (:55) (and tagline 'Movera driver' / '{n} trips completed', :52-54). RideCompletedDriverInfo (driver_info.dart:70 `text: driver.vehicle`) renders the vehicle line to the rider on the Ride completed screen (ride_completed.dart:387). When the matched driver carried no make/model/color the English fallback is shown in fr/sv; no ARB key exists for it.

**Suggested fix:** Use L10n.current for the vehicle fallback (and the tagline, which also has no localized form).

### L132. Ride receipt shows the stored payment names 'Movera Wallet' / 'Card' in English; only Cash is translated

`lib/features/ride_complete/presentation/trip_detail.dart:77` (found by r2-rider3)

**What happens:** App language is French. The rider pays a ride with the Movera Wallet. The Ride summary's Trip details card shows 'Payment method: Movera Wallet' instead of 'Portefeuille Movera'.

**Why:** The completion receipt builds its Payment method row with `L10n.isCashLabel(trip.method) ? payCash : trip.method`. trip.method is the snapshot's English paymentMethod name, set when Select Ride books with `paymentMethod: payment.name`. A wallet or generic-card ride therefore shows 'Movera Wallet' or 'Card' in every language, although the ARB files translate them (sv 'Movera Plånbok' / 'Kort', fr 'Portefeuille Movera' / 'Carte') and payment_labels.dart already has paymentLabelFor for exactly this mapping. The known finding covers the History detail at ride_history.dart:552; this is the separate receipt on the ride-complete screen.

**Suggested fix:** Use `paymentLabelFor(trip.method)` for the receipt row, and also accept the localized cash label if isCashLabel is still needed.

### L133. A catalog answer that changes the category ids while Set pickup is open starts a list re-quote at the unconfirmed original pickup that can overwrite the pin's quote

`lib/features/ride_selection/presentation/select_ride.dart:435` (found by r2-rider4)

**What happens:** On a slow first launch, the ride-types answer lands while the rider is on Set pickup with the pin already moved and re-priced. The selected ride's quote reverts to the original point's price, and the booking dialog proposes that wrong price for the moved pickup.

**Why:** _onCatalogChanged runs _loadQuotes() whenever the ids differ (for example, the server list replacing the 14 built-in ids on first use). _loadQuotes prices every category at _pickupPosition, which is still the original point while Set pickup is open. RIDE-11 protects the pin quote only from list loads begun before it (quoteFromPin bumps _quoteGeneration). A list load begun after the pin quote is adopted overwrites the selected category's authoritative quote with the original point's price. Book now then shows a 'price updated' dialog asking the rider to accept the original pickup's price for the moved pickup.

**Suggested fix:** Defer catalog-triggered re-quotes while the booking flow (_bookingInFlight / Set pickup) is open, or skip overwriting a quote adopted from a pin after the list load began.

### L134. 'Cheaper' filter sorts by catalog list price instead of the quoted fare shown on each row, so a promoted or cheaper-quoted ride can appear below dearer ones

`lib/features/ride_selection/presentation/select_ride.dart:668` (found by r2-rider-r3)

**What happens:** A rider taps 'Cheaper'. The list shows Movera 228 kr, then Electric, then Pet 248 kr and others, and only after them Priority at 208 kr, even though Priority is the cheapest car on screen. The filter claims an order the prices it shows contradict.

**Why:** _visibleRides orders with `price: (ride) => ride.price`, and ride.price is the catalog list price. Each tile shows `_kr(_priceFor(ride))`, which is the server quote after distance pricing and the promotion. The promotion takes off up to 50 kr on comfort/priority/premium only, so the list-price order and the shown-price order differ. orderRidesForFilter's doc comment admits it compares the catalog base price, but the rider only sees the chip 'Cheaper' and the quoted prices. I checked it on the stand-in server with a throwaway test (POST /quotes, Stockholm Central to Drottninggatan): economy 22800, priority 20800, comfort 25800, premium 28800, pet 24800 öre. The list prices are economy 259, pet 279 and priority 289 kr.

**Suggested fix:** Sort by `_priceFor(ride)` (the shown quote) when a quote exists, and fall back to the list price only for rides without one.

### L135. Scheduled booking does not re-quote a quote that expired during the date picker and Set pickup; booking fails with a no-price toast and needs two more taps

`lib/features/ride_selection/presentation/select_ride.dart:1155` (found by rider2)

**What happens:** Rider taps Schedule, spends 3 minutes picking Saturday 07:00 and adjusting the pickup pin, taps 'Confirm and schedule' → toast that no price is available; reservation not created; second attempt repeats every step.

**Why:** `_book` checks `quoteIsAvailable` once, then `_bookScheduled` opens the date-time picker and Set pickup (and possibly the picker again for return rides) before `ScheduledRideCheckout.run` → `draftFrom` → `ScheduledRideBooking.quotedPrice`, which throws `ScheduledQuoteRequiredException` as soon as `authoritativePriceFor` is null. Quotes expire after 2 minutes (in_process_mock_client.dart:2173 and catalog_quote_repository.dart:35), so a rider who spends more than two minutes choosing a time and pickup spot gets the `resErrNoPriceBook` toast and nothing is booked; Book now handles the same situation by re-quoting in place (`_quoteAfterPickup`, RIDE-2) but the scheduled path has no equivalent. Tapping Book again then shows 'price unavailable, refreshing' and the rider must repeat the picker and pickup steps.

**Suggested fix:** Before `ScheduledRideCheckout.run`, reuse `_quoteAfterPickup(ride)` (awaiting `_pinQuote`, re-quoting from the confirmed pickup when stale) and pass its price, mirroring `_bookNow`.

### L136. Select Ride stays interactive during the Home lookup before Set pickup opens, so category, payment and booking-mode taps race the booking already captured

`lib/features/ride_selection/presentation/select_ride.dart:1280` (found by r2-rider4)

**What happens:** A rider with Home saved taps Select Movera, then immediately taps Comfort. Comfort is highlighted on Select Ride, but Set pickup and the booking are for Movera. Or they tap the calendar and a 'When do you want to ride' sheet stays under Set pickup and Finding.

**Why:** _bookNow captures `selected` and `payment`, parks the map, and _openSetPickup then awaits _homePosition() (saved-places hydrate up to 600 ms plus a Home geocode up to 900 ms) before pushing Set pickup. During that window only the Book CTA is disabled (_bookingInFlight). Ride tiles (_selectRide, line 2187), the payment row (_showPaymentPicker) and the calendar button (_showBookingPicker) still respond. A tap on another category highlights it, but Set pickup and the booking use the captured one. A tap on Pay with or the calendar pushes that page or sheet, and Set pickup then opens on top of it.

**Suggested fix:** Ignore row, payment and booking-mode taps while _bookingInFlight, or resolve Home before setting the lock and capturing the selection.

### L137. In demo/dev builds (mock transport only), picking the generic 'Card' row in Set pickup's payment picker books with paymentMethod 'cards' and no saved card

`lib/features/ride_selection/presentation/select_ride.dart:1493` (found by r2-rider-r3)

**What happens:** In a demo/dev build (CardEntryPolicy.enabled) a rider with no saved card and Cash selected taps Book. On Set pickup they tap the payment line, choose 'Card' and tap Confirm. The ride is booked with paymentMethodId 'cards', and Finding/Waiting show 'Card · 259 kr', but no card exists. Add card never opened, so nothing can be charged. Choosing 'Card' from the Select Ride footer instead would have opened Add card.

**Why:** In _bookNow the Add-card gate runs only once, before Set pickup opens: `if (payment.brand == 'cards' && !_selection.hasSavedCard) { AddCardPage.open ... }` (line 1465). Set pickup is then opened with `onChangePayment: () async { await _showPaymentPicker(); ... }` (line 1320). PayWithPage lists the generic 'Card' row whenever there is no saved card (ride_selection_controller.dart:243-247: `return CardEntryPolicy.enabled ? [item] : ...`; pay_with_page.dart:199 only hides it once a saved card exists), and tapping it pops 'cards' (`onTap: () => Navigator.of(context).pop(method.brand)`). _showPaymentPicker selects it. After Set pickup returns, _bookNow re-reads the method (`final chosen = _selection.selectedPaymentItem(); if (chosen != null) { payment = _PaymentOption(brand: chosen.brand, ...) }`, lines 1493-1500) and goes straight to `submitFinding(paymentMethod: payment.brand, ...)` (line 1542) without checking the card gate again. BookingCoordinator sends it as is (`'paymentMethodId': paymentMethod`, booking_coordinator.dart:654), and the stand-in server stores any string (in_process_mock_client.dart:2264).

**Suggested fix:** Run the same Add-card gate after Set pickup returns (when the chosen brand is 'cards' and there is no saved card). Alternatively, make PayWithPage open Add card when the generic Card row is tapped.

### L138. The 'Price updated' dialog has no time limit, so a quote that expires while it is open fails the booking with a generic error after the rider accepted

`lib/features/ride_selection/presentation/select_ride.dart:1517` (found by r2-rider4)

**What happens:** After moving the pin, the rider gets 'Price updated: 301 kr', leaves the phone for a couple of minutes, comes back and taps 'Book for 301 kr'. They are told the booking failed and must start again.

**Why:** _bookableQuote guarantees only 10 s of quote life (_quoteMargin) before _acceptNewPrice opens. The dialog waits for the rider indefinitely, and the quote is not re-checked or refreshed after they accept. Mock quotes live 2 minutes. If the rider takes longer, BookingCoordinator refuses the expired quote locally (booking_coordinator.dart:630) and the rider sees 'bookingFailed' right after tapping 'Book for X'.

**Suggested fix:** After the dialog, re-run _bookableQuote (refreshing via _quoteAfterPickup if needed) and ask again only if the refreshed price differs.

### L139. Select ride filter chips and ride tiles show selection only visually: no button/selected semantics; filter chips are ~34 px tall

`lib/features/ride_selection/presentation/select_ride.dart:2108` (found by r2-rider4)

**What happens:** A VoiceOver user on Select ride swipes through Economy/Comfort/Premium and hears names and prices with no 'selected' state. They tap Faster and get no confirmation of which filter is active.

**Why:** _filterChip is a GestureDetector > AnimatedContainer(padding 14/8) > Row(icon, Text 13). It is about 34 px tall and has no Semantics(button/selected), so the active filter (Recommended/Faster/Cheaper) is never announced. _rideTile marks the chosen category only with an accent border. Its InkWell has no Semantics(selected:), so a screen-reader user cannot tell which category will be booked. The Book CTA text includes it, but the list does not. The same visual-only pattern is in select_date_time.dart _modeOption (Pickup at / Arrive by) and the wallet top-up amount chips (wallet.dart:390-400).

**Suggested fix:** Wrap chips and tiles in Semantics(button: true, selected: selected, ...) and give the chips a minimum height of 44.

### L140. Wallet split line is computed from the SEK list price for a pickup priced in another currency before the quote arrives

`lib/features/ride_selection/presentation/select_ride.dart:2334` (found by rider2)

**What happens:** Rider in Paris with 50 € in the EUR wallet opens Select Ride; before quotes land, the selected tile shows '…' as the price and 'Wallet −50 € · you pay 209 €' underneath.

**Why:** `_rideTile` shows `_walletLine(price)` whenever `walletSplitFor(moneyOf(price).amountMinor).usesWallet`, where `price = _priceFor(ride)` falls back to `ride.price` (the SEK catalog figure) when no quote is held. The price text itself is guarded by `_hasPrice(ride)` and shows '…' for a pickup whose zone currency differs from the list's, but the wallet line is not guarded, so for a EUR pickup with a EUR wallet balance the selected tile reads e.g. 'Wallet −50 € · you pay 209 €' built from the 259 kr list price while the price shows '…'.

**Suggested fix:** Guard the wallet line with `_hasPrice(ride)` (and ideally with an available quote).

### L141. The 'Long stop' demo opens an 'Off the route' (longer than expected) card when admin's long-stop time is 15 minutes or more

`lib/features/safety/application/ride_check_controller.dart:350` (found by r2-rider2)

**What happens:** Reproduced with a throwaway test: with the mock's longStopMinutes set to 15, playDemo(longStop) returned shown with session.trigger == offRoute. The demo page described as 'Long stop' shows 'taking N% longer than expected'.

**Why:** playDemo(longStop) feeds the real monitor samples at one point, for up to (longStopMinutes+1)*60 s. On every sample the monitor also evaluates _tooLong, using the straight-line expectation of the demo plan: about 4.7 km at 8.3 m/s, roughly 566 s, with a limit of 566*1.5 ≈ 849 s. If admin's longStopMinutes is 14 or more, _tooLong fires the offRoute trigger (longer than expected) before the long stop exceeds its threshold. The loop stops at the first hit and opens the off-route card, while the demo page title says 'Long stop'.

**Suggested fix:** Build the demo with a monitor whose offRoute trigger is off (settings.copyWith(offRouteEnabled: false)), or feed only the long-stop path.

### L142. Ride check saves the answer 'Called 112' even when the dialer failed to open (alert is still correctly sent)

`lib/features/safety/application/ride_check_controller.dart:495` (found by rider4)

**What happens:** No dialer (web/tablet) or launch refused: card shows a note that the dialer failed, yet the trip details and the submitted answers say "Called 112".

**Why:** `call112()` catches the dialer failure into `failure` (478-489) but then unconditionally sets `called112: true` and appends `RideCheckAnswer.call112` (495-501), and sends the alert. The answer label "Called 112" is what is saved on the trip and shown in the trip's details (`RideCheckRecord.answerSummary`, ride_check_trip_entry.dart:466) and what the safety team receives, although no call happened; only the transient card note shows `callError`.

**Suggested fix:** Record a distinct answer (e.g. `call_112_failed`) or omit the "Called 112" answer when `failure != null`, while still sending the alert.

### L143. A card the rider closed comes back after a quick reload when its close was queued behind a slow alert send

`lib/features/safety/application/ride_check_controller.dart:693` (found by r2-rider2)

**What happens:** Offline: the rider taps a red row (the alert POST hangs), then taps Done within a few seconds and the card folds away. The browser reloads before the 15 s timeout. The card is back on the trip screen, blocking it, and the Done/note answer is lost.

**Why:** `_close` clears `_session` immediately, but the local save that marks the event resolved happens inside the queued 'close' job. Jobs run one after another (`_enqueue`). If an earlier alert job is still waiting on the API (up to the 15 s ApiClient timeout when offline), the close job and its local `keep(status: resolved)` have not run yet. If the page reloads or the app is killed in that window, the event is still pending/acknowledged on disk, so `unanswered()` returns it and the non-dismissible card reopens. The rider's final answer (for example 'I'm OK' or the note) was never saved.

**Suggested fix:** Save the closing answers and resolved status to the local cache synchronously in `_close`, before enqueueing the network part.

### L144. A failed stop (NO_AUDIO / SAVE_FAILED) leaves an orphan recording entry with endedAt == null (and any 0-byte or captured file) that nothing ever cleans up

`lib/features/safety/application/safety_audio_service.dart:89` (found by r2-rider1)

**What happens:** The rider taps Record and then Stop within a fraction of a second, so the encoder writes 0 bytes. The card says 'No audio file was captured.' The cache keeps a recording with no file and an endedAt timestamp, and the empty .m4a stays in safety_recordings. Repeating this grows both.

**Why:** `start()` registers the recording in the cache (`initDeviceAudio` / `initAudio`) before capture. In `stop()`, when the recorder returns null (missing or 0-byte file) the service throws NO_AUDIO without deleting that cache entry. The native recorder also leaves the 0-byte file on disk, because it only checks the file and returns null (safety_recorder_native.dart:39-41). When completeDeviceAudio/completeAudio throws, SAVE_FAILED leaves the captured m4a on disk with no localPath recorded anywhere. A recording interrupted by an app kill likewise stays as an entry with endedAt == null (isRecording == true) forever. These entries and files accumulate in `movera_safety_cache_v1` and Documents.

**Suggested fix:** On NO_AUDIO, delete the store entry and the empty file. On SAVE_FAILED, keep the localPath in memory and retry, or delete the file.

### L145. Ride check recording keeps the microphone on after session expiry replaces the trip screen with Sign in

`lib/features/safety/application/safety_audio_service.dart:118` (found by r2-rider1)

**What happens:** During an unanswered card the rider records. The alert POST gets a 401 and the token refresh fails, so the app shows Sign in. The microphone indicator stays on and the recording grows until the process dies, or until the same rider signs back in and returns to the card.

**Why:** The only things that stop a Ride check recording are answering the card (`_close`) and the ride-end paths in ActiveRideController. On session expiry, `onSessionExpired` re-roots to Sign in and keeps the ride (di.dart:104-116). Waiting and the card's layer are disposed, but RideCheckController keeps `_session` and the audio service keeps `_active`, so the recorder keeps capturing on the Sign in screen with no Stop control. If a different rider then signs in, `enterSessionAs` wipes and `SafetyController.resetShared()` discards the service, so the recorder can no longer be stopped by any code path.

**Suggested fix:** Call `audio.stopIfRecording` on session expiry and in SafetyController.resetShared before discarding the service.

### L146. Failures to change the PIN, the PIN requirement, trip-share settings or the Ride check switch are never shown to the rider

`lib/features/safety/application/safety_controller.dart:208` (found by r2-rider1)

**What happens:** Offline, the rider taps Change PIN and confirms. The request fails, the old PIN stays on screen and no message appears, so the rider may believe the PIN was rotated. Toggling 'Require PIN' or 'Ride check alerts' offline snaps back with no explanation.

**Why:** setPinRequired, rotatePin, setTripShare and setRideCheck catch the error and set `error` to a translated message (safetyPinChangeFailed and the others). No widget reads SafetyController.error except the contact editor. PinVerificationPage, TripSharePage, RideCheckPage and SafetyHub never render it. After 'Change PIN?' > Change fails, the dialog closes and nothing says the PIN was not changed. Failed toggles flip back silently.

**Suggested fix:** Show `_ctl.error` (a toast or inline text) on the PIN, Trip share and Ride check pages after these calls, or have the calls return a result that the pages report.

### L147. A trip share is never stopped: no caller of stopShare, so the live link stays active after the trip ends

`lib/features/safety/application/safety_controller.dart:309` (found by r2-rider1)

**What happens:** The rider shares the trip from the Safety Kit, then the trip completes at their home address. For up to six hours afterwards the contacts' live link still reports an active share for that ride, with its final location, and the rider cannot turn it off.

**Why:** `SafetyController.stopShare` / `TripShareRepository.stop` / `SafetyStore.stopShare` exist but nothing calls them. The ride-end paths (markCompleted, markExternalTerminal, _commitCancelled, closeCompletedRide) only stop the audio recording (`_stopSafetyRecording`). The share created from the Safety Kit stays `isActive: true` locally and on the server until its 6-hour expiry (safety_store.dart:267, safety_mock_api.dart:270). The rider also has no control anywhere to stop sharing. The Trip share copy promises 'Share your active ride'.

**Suggested fix:** Stop the ride's share (best effort) wherever the ride ends (markCompleted / markExternalTerminal / cancel commit), and offer a Stop sharing action in the kit.

### L148. Safety Kit audio cannot start without a successful server init (fails offline); each successful init also leaves an orphaned optimistic recording in the persisted cache

`lib/features/safety/data/safety_store.dart:501` (found by r2-rider3)

**What happens:** Offline in a tunnel, the rider opens the Safety Kit and taps Record audio. The note says recording failed and the microphone never starts. Online, every Kit recording adds two cache entries, one of which is never completed.

**Why:** The Kit records with `deviceOnly: false`, so `start()` awaits `_store.initAudio`, a `_write` that must reach POST /safety-audio/init. Offline, the remote fails, `_write` reverts and rethrows, and the Kit shows 'recording failed': a rider in a dead zone cannot record from the Safety Kit at all, although the file is saved locally. When init succeeds, the server returns its own id (`aud_$requestId` in the mock), not the optimistic id. `apply(confirmed)` only removes entries with the confirmed id, so the optimistic entry with the local id stays in the cache forever with endedAt == null.

**Suggested fix:** Start capture locally first and register with the server best effort (queue the init when offline). In apply, replace the optimistic entry by its local id.

### L149. SwedishPhone.toE164 accepts a trunk zero after +46 and stores an invalid contact number

`lib/features/safety/domain/phone_e164.dart:116` (found by rider2)

**What happens:** Rider adds a trusted contact as "+46 070 123 45 67"; it is saved as +46070 123 45 67 and shown as such; the number cannot be reached by the safety team.

**Why:** After normalising, the function only checks that the part after `+46` is 7–10 digits (116-119). Input like `+46 070 123 45 67` (a very common way to write a Swedish mobile) becomes `+46070…`, which passes (10 digits) and is stored as the emergency contact's `phoneE164` and sent to the share/alert backend, but is not a dialable E.164 number.

**Suggested fix:** Strip a leading `0` from `rest` (or reject it), and require the national number to start with a non-zero digit.

### L150. One implausible GPS fix (a jump) opens an off-route Ride check and resets the long-stop timer, although the monitor already detects such jumps

`lib/features/safety/domain/ride_check_monitor.dart:134` (found by r2-rider-r3)

**What happens:** Reproduced with a throwaway test. Two normal fixes on the route, then one fix 5 km east 3 s later (about 1.7 km/s, impossible), returned `[null, null, RideCheckTrigger.offRoute]`. The rider gets an 'off the route' safety card from a GPS glitch, and later real off-route driving on the same trip never triggers. A glitch during a real long stop also restarts the stop timer.

**Why:** `addSample` treats a fix faster than `plausibleSpeedMps` (60 m/s) as a GPS jump, but only by leaving `speed` null. The same sample is still stored as `_previous` and passed to `_longStop`, which resets `_stillAt` and `_stillSince` because the point moved more than 25 m, and to `_offRoute`, which fires when the point is more than `offRouteKm` (2 km) from the planned route. Each trigger fires at most once per trip, so the glitch also uses up the real off-route trigger.

**Suggested fix:** When the speed from the previous fix is implausible, drop the sample: do not update `_previous` or the anchor, and do not run the triggers. Or require the off-route distance to persist across two or more consecutive fixes.

### L151. The monitor marks a trigger as fired even when the card could not open (another card up), so that trigger is lost for the rest of the trip

`lib/features/safety/domain/ride_check_monitor.dart:252` (found by r2-rider4)

**What happens:** A long-stop card is open and the rider has not answered. The driver then finishes 5 km from the drop-off. tripEnded fires droppedFar, open() returns busy, and droppedFar is now marked fired. After the rider answers the long-stop card, no 'finished far from drop-off' check ever appears for this trip.

**Why:** RideCheckMonitor._fire adds the trigger to `_fired` before the controller tries to open it. RideCheckController.open returns `busy` when any session is up (line 379), and the result is ignored (`unawaited(open(...))` at lines 274/290, and the tripEnded result). Because `_canFire` checks `_fired`, the trigger can never fire again on this trip. The droppedFar check at finish is lost if an unanswered mid-trip card is still up, and an off-route hit is lost while a long-stop card is open.

**Suggested fix:** Mark the trigger fired only when open() returns shown, or queue the detection and open it after the current card closes.

### L152. Ride check distances use '.' as decimal separator in Swedish/French ('1.2 km')

`lib/features/safety/domain/ride_check_trigger.dart:244` (found by r2-rider1)

**What happens:** Swedish UI: the dropped-far card reads 'Resan slutade 3.6 km från …' and the RideCheck page shows 'mer än 2.5 km' instead of '3,6 km' / '2,5 km'.

**Why:** `formatRideCheckDistance` builds the bold part of the card's reason line with `toStringAsFixed`, which always uses '.'. RideCheckPage and the demo page format admin's km the same way (ride_check_page.dart:44-50, ride_check_demo_page.dart:158-159). Swedish and French need ','. This code is separate from lib/shared/formatters/money.dart (the known finding), so fixing that file does not fix these strings.

**Suggested fix:** Format with NumberFormat for the current locale (the same helper the money formatter fix will use).

### L153. formatRideCheckDistance (ride_check_trigger.dart:238-245) prints '1000 m' for 995-999 m; this is only reachable when an admin sets a threshold below 1 km

`lib/features/safety/domain/ride_check_trigger.dart:401` (found by r2-rider-r3)

**What happens:** A trip whose driver went 997 m off the route, or ended 997 m from the drop-off, shows 'Your trip ended 1000 m from …' on the Ride check card and in the trip details.

**Why:** For `meters < 1000`, the value is rounded to the nearest 10 m: `(meters / 10).round() * 10`. Anything from 995 m to just under 1000 m rounds to 1000 and is printed as '1000 m', while 1000 m and above print as '1.0 km'. The function's own doc says '650 m' below a kilometre and '1.2 km' from there.

**Suggested fix:** Round first, then choose the unit: `if (rounded < 1000) return '$rounded m';` and otherwise format as km.

### L154. `_ContactEditorState._save` calls setState in its catch block without a mounted check; the editor is a dismissible sheet

`lib/features/safety/presentation/emergency_contacts_page.dart:287` (found by rider3)

**What happens:** Rider taps Save on the emergency-contact sheet, swipes the sheet down during the request, and the request then fails (offline, server error). The app logs/reports an unhandled 'setState() called after dispose()' error from `_ContactEditorState._save`.

**Why:** `_ContactEditor` is shown through `MoveraSheet.show` (line 42-46) with the defaults `swipeDismissible = true, barrierDismissible = true` (movera_sheet.dart:22-23), so the rider can swipe it away while `await widget.controller.addContact/editContact` is in flight. The success branch guards with `if (mounted) Navigator.pop(context);` but the catch branch does `setState(() { _error = ...; _saving = false; })` unconditionally. If the save fails after the sheet was dismissed, `setState` runs on a disposed State: an assertion error in debug ('setState() called after dispose()'), a null-check error on `_element` in release, surfacing as an unhandled async error from the button's unawaited `_save()` future.

**Suggested fix:** Add `if (!mounted) return;` at the top of the catch block (mirroring the success branch).

### L155. Safety Kit sheet overflows at 2x text on a 375x667 screen (no scroll view), clipping the Safety preferences link

`lib/features/safety/presentation/ride_safety_kit.dart:252` (found by r2-rider3)

**What happens:** French, 2x text, 375x667. Open the Safety Kit during a trip and tap 'Enregistrer l'audio': the title takes 2 lines (123), the 3 tool tiles ~183 (their labels break mid-word in the ~90 px tiles), the recording note ~214 and the Safety preferences card ~207, about 870 px in total. RenderFlex overflow of ~200 px, and the 'Préférences de sécurité' link and part of the note are off-screen. On 360x640, the 'Taking longer' cancel sheet (148-char body ≈ 7-8 lines) also needs about 660 px, so 'Attendre un chauffeur' is clipped.

**Why:** MoveraSheet content is laid out against the full viewport and these builders return a plain Column with no scroll view: RideSafetyKitSheet, CancelRideSheet (cancel_ride_sheet.dart:177), showCancelReservationFlow (reservation_edit_sheets.dart:24) and the History detail sheet (ride_history.dart:485). Their texts have no maxLines, so at large text they grow past the viewport and the bottom children are clipped and untappable. None of these sheets are covered by the text-scale tests.

**Suggested fix:** Wrap these sheet bodies in SingleChildScrollView (as cancel_reason_sheet.dart and emergency contact editor already do).

### L156. Trip share contact list shows the raw English relationship ('Family', 'Partner') in every language

`lib/features/safety/presentation/trip_share_page.dart:161` (found by r2-rider3)

**What happens:** With the app in Swedish, Safety > Share trip lists 'Anna / Family' while the contacts page shows the translated label.

**Why:** Relationships are stored in English and translated with relationshipLabel(), which the Emergency contacts page uses (emergency_contacts_page.dart:190 and :342). The Trip share checkbox subtitle shows `shareable[i].relationship` directly, so Swedish and French riders see the English words.

**Suggested fix:** Use relationshipLabel(shareable[i].relationship).

### L157. Add/Edit place form is a non-scrolling Column; on a 320x568 phone with the keyboard up, the validation error overflows it (by ~2 px in the measured case)

`lib/features/saved_places/presentation/add_place.dart:216` (found by r2-rider2)

**What happens:** 320x568 phone, keyboard ~260: the body is 568-20-56-260 = 232 px. The content needs ~216 px, then 245 px with the 'name and location' error, so RenderFlex overflow and the Save button is pushed under the keyboard. At 1.3x text it overflows even without the error.

**Why:** The Scaffold body is Padding > Column(16, name TextField, 16, location field, error, Spacer, Save 52, 16) with no scroll view, and the Scaffold resizes for the keyboard. When Save is tapped with a field empty, the error text appears while the keyboard is still up.

**Suggested fix:** Use a scrollable body (ListView or SingleChildScrollView with the button in bottomNavigationBar).

### L158. Address search is not blocked while 'CURRENT' is resolving, so both lookups can pop the picker

`lib/features/saved_places/presentation/pickup_location.dart:62` (found by r2-rider2)

**What happens:** The rider taps CURRENT (a slow GPS fix), then types 'Odenplan' and taps search. If the GPS address arrives first, it is returned and the typed address is ignored. If both arrive within the exit animation, AddPlace is popped as well, losing the form, and a String is handed to a PlaceShortcut route.

**Why:** `_useCurrentLocation` bails out if `_searching`, but `_submitQuery` only checks `_searching`, and the search button is enabled while `_locating`. Both operations end with `Navigator.maybePop(context, address)`. Whichever finishes first decides the saved address, which can be the current position even though the rider typed and submitted an address afterwards. If the second one finishes during the ~300 ms exit transition, `mounted` is still true, and `maybePop` pops the next route, AddPlace, with a String result for a `Navigator.push<PlaceShortcut>` route.

**Suggested fix:** Make the two actions mutually exclusive (check `_locating` in `_submitQuery` and disable search while locating), and guard against a second pop with a 'done' flag.

### L159. Saved-place location picker close button is a 26 px unlabeled InkWell

`lib/features/saved_places/presentation/pickup_location.dart:148` (found by r2-rider2)

**What happens:** On a 320x568 phone the close hit area is about 22x22 px. A TalkBack user hears an unnamed button as the first control. Sighted users on small phones miss it often.

**Why:** RiderSearchPickupLocation (opened from Add place → location field, add_place.dart:62-70) closes through an InkWell wrapping a `ResSize.h * 26` x `ResSize.w * 26` circle with an Icon and no label. That is a 22-32 px target, far below the 44 px floor, and screen readers get no name.

**Suggested fix:** Wrap it in MoveraHitArea(label: l10n.close, ...) like add_place.dart:171 does for its back button.

### L160. 'CURRENT' button caption on the saved-places location picker is hard-coded English

`lib/features/saved_places/presentation/pickup_location.dart:228` (found by rider1)

**What happens:** French rider adds a saved place and opens the location picker: the GPS button reads 'CURRENT'.

**Why:** RiderSearchPickupLocation (reached from Add place → pick location, add_place.dart:65) draws the use-my-location button with `TextWidget(text: 'CURRENT', ...)` (:228). No ARB key is used; fr/sv riders see the English caption on the Saved places flow.

**Suggested fix:** Use a localized caption (e.g. context.l10n.currentLocation shortened or a new key).

### L161. Return-ride picker silently moves a stale or off-grid prefill: choose() clamps before initState, so the 'pickup time updated' notice never shows

`lib/features/scheduled_rides/presentation/select_date_time.dart:52` (found by r2-rider3)

**What happens:** A return ride is prefilled at origin+3h = 21:07, which is off the 5-minute grid. The picker opens at 21:10 with no 'pickup time updated' line, so the rider does not know the time was changed.

**Why:** choose() calls session.captureSchedule(initial), which already runs clampPickup. initState then compares clampPickup(existing) with existing, and both are the already clamped value, so _pickupCorrectionMessage is never set. SelectRide relies on this picker for return-ride prefills ('opens on the prefill clamped to the next legal slot'). The rider's return time can be moved (for example 21:07 to 21:10, or a past time to now+30) with no notice.

**Suggested fix:** Pass the raw initial time to the selector (for example a separate field), or compare against the unclamped value.

### L162. Arrive by into the DST spring-forward gap gives an estimated pickup after the requested arrival

`lib/features/scheduled_rides/presentation/select_date_time.dart:121` (found by r2-rider-fixrev)

**What happens:** The device is set to Europe/Stockholm. The rider picks Arrive by 03:10 on 29 March 2026 with a 20-minute trip. "Estimated pickup" shows 03:50 and Continue books a 03:50 pickup, so the rider arrives about an hour late.

**Why:** _pickupFor works out the pickup as `DateTime(y, m, d, h, minute - trip)` with the local DateTime constructor. When the result falls in the device zone's DST gap, Dart moves it forward by an hour. On 29 Mar 2026 in Europe/Stockholm, an arrival of 03:10 minus 20 minutes is 02:50, which does not exist, so Dart returns 03:50. The slot floor keeps 03:50. The booked pickup is 40 minutes after the arrival the rider asked for, which breaks the rider-89 rule that the rider is never late. _goNext, _continueButton and _commitSchedule all use this value, and choose() returns it to SelectRide.

**Suggested fix:** Subtract the trip as a Duration on a UTC-based value (for example DateTime.utc(...) wall-clock arithmetic, then back), or fall back to the last valid slot at or before the arrival.

### L163. Untranslated '24-hour', 'SCHEDULE' and 'Current location' on the scheduling screens (the realtime 'driver arrived' message is never displayed)

`lib/features/scheduled_rides/presentation/select_date_time.dart:342` (found by rider1)

**What happens:** French rider opens Schedule: header "SCHEDULE", pickup field "Current location", time sheet "24-hour" all in English while the rest of the page is French.

**Why:** Literal English in localized screens: `'24-hour'` caption on the time sheet (342); `'SCHEDULE'` header (schedule_ride.dart:305); `'Current location'` as the pickup field's initial text and label (schedule_ride.dart:58, 184; scheduled_category_gate.dart:411 — note `resolveScheduledPoint` also uses it as a sentinel at 490, so a translation must keep the sentinel separate); and `message = 'Your driver has arrived at the pickup point.'` emitted with the driverArrived signal (reservation_ride_realtime.dart:197).

**Suggested fix:** Move these to ARB keys; keep an internal sentinel constant for the "current location" pickup rather than comparing the displayed text.

### L164. After a rebuild that happens without a pick (e.g. backing out of the category step), a pickup time that has gone stale greys out Continue with no correction message

`lib/features/scheduled_rides/presentation/select_date_time.dart:753` (found by r2-rider3)

**What happens:** The rider opens the picker at 09:29 with 10:00 selected, waits, and at 09:31 taps 'Arrive by' and then 'Pickup at'. Continue goes grey with no explanation while 10:00 is still shown. They have to guess that they must pick the time again.

**Why:** _goNext has a branch that moves an illegal pickup to the next legal slot and shows 'pickup time updated'. But _continueButton disables the button whenever isLegalPickup is false at build time. If the rider stays on the screen past the slot boundary (the minimum moves on about every minute, because roundToFive rounds now+30 up) and anything rebuilds the screen (switching Pickup at / Arrive by, a resize or a keyboard change), Continue turns grey. No message appears and the old time is still shown. The correction path can only be reached if no rebuild happened after the boundary.

**Suggested fix:** Keep the button enabled (apart from _continuing) and let _goNext do the correction, or clamp the time and show the message during build/tick when the selection becomes illegal.

### L165. Support 'Cases' is a static empty state that says 'No active cases' even after the rider has submitted a ride issue

`lib/features/support/presentation/support.dart:526` (found by r2-rider4)

**What happens:** A rider reports 'I was charged twice', sees 'Sent to Movera', taps Support › Cases and reads 'No active cases'. They conclude the report was lost and send it again.

**Why:** SupportMessages is static: it always renders 'No active cases' and 'You have no closed support cases.' No data source backs it. SupportChat really sends the message (POST /rides/{id}/disputes, which answers `status: submitted`) and says 'Sent to Movera. The team reviews it…'. Opening Cases straight afterwards states that there is no active case.

**Suggested fix:** Keep the disputes sent in this session (or read them from the server) and list them, or replace the empty state with copy that does not claim there are no cases.

### L166. Support shows a cancelled ride as the full fare in Select ride (_RideRow) and as '0 · Cancelled' elsewhere, dropping a late-cancel fee that History shows

`lib/features/support/presentation/support.dart:1097` (found by r2-rider4)

**What happens:** A rider cancelled a kr 189 Comfort ride. Support › View all lists it at 'kr 189', while Support Home says 'kr 0 · Cancelled'. For a late-cancelled reservation with a kr 50 fee, History shows the kr 50 fee but Support shows kr 0. The rider raising a money issue sees the wrong amount.

**Why:** SupportController.rideFor never passes the reservation's cancellationFee (`extra` is never set). SupportRide.priceLabel therefore shows `formatMajor(0)` · Cancelled for every cancelled ride (SupportHome cards, the SupportChat header and SelectIssue's trip line), even when a late-cancel fee was recorded. Ride History shows the same fee (`ride.cancellationFee ... context.l10n.cancelFee`). The 'View all' list (_RideRow) shows `formatMajor(ride.price, ...)` for the same cancelled ride, i.e. the full fare as if it had been charged. The two Support screens contradict each other, and both can differ from History.

**Suggested fix:** Carry the cancellation fee into SupportRide (extra or a fee field), and make _RideRow use the same priceLabel for cancelled rides.

### L167. Support's ride list shows the 'No rides to review' / 'No rides yet' empty state with no retry when GET /rider/trips fails or takes more than 8 s

`lib/features/support/presentation/support.dart:1449` (found by r2-rider-r3)

**What happens:** A rider with 20 past trips opens Help on a slow or offline connection. The GET /rider/trips call fails or takes more than 8 s. Support shows 'No rides to review' and Select ride shows 'No rides yet'. They cannot pick the ride they were overcharged on, and the screen gives no hint that loading failed or how to try again.

**Why:** `_SupportRides` builds with `snapshot.data ?? const []` and never checks `snapshot.hasError`. Its future is `widget.load().timeout(const Duration(seconds: 8))`, held in a `late final` field, so it is never retried. In release, `SupportController.loadRides` reads `ApiRideHistoryRepository.loadOnDemand` (GET /api/v1/rider/trips). That call throws offline, on a server error, or when 8 s pass. Support Home and Select ride then show the empty state 'No rides to review / Your completed and cancelled rides will appear here.' (or 'No rides yet'). This is the only in-app path to report a ride (SupportChat needs a ride id), and there is no retry button or error text, so the rider is told something false and is stuck.

**Suggested fix:** When `snapshot.hasError`, show a load-failed state with a Retry action that recreates the future, separate from the true empty state.

### L168. Finding and Waiting ride cards (and the route-change sentences) show the English payment name ('Cash', 'Movera Wallet') in sv/fr, even when the ride was booked in sv/fr

`lib/features/wallet/domain/wallet_split.dart:110` (found by r2-rider3)

**What happens:** Rider books a cash ride in English, then switches to Svenska during the search or the ride. The ride card reads 'Cash · 259 kr' instead of 'Kontant · 259 kr'. In French, a route change with Movera Wallet reads '+30 kr de plus, débité sur Movera Wallet.' instead of 'Portefeuille Movera'.

**Why:** The snapshot and the screens keep the payment method under its English catalog name: select_ride passes `paymentMethod: payment.name` / `paymentMethodLabel: payment.name` (select_ride.dart:1547, 1615), and booking_coordinator.dart:728 saves `paymentMethod: paymentMethodLabel ?? paymentMethod`. payment_labels.dart says that name 'stays the method's identity; only what is shown is translated', but `bookedPaymentLine` puts it into the line as it is. That line is the payment row on both live ride cards: FindingDrivers (finding_drivers.dart:1130) and WaitingForDriver (waiting_sheet_bits.dart:162). The same raw name also goes into the route-change sentences: route_change_sheet.dart:132/134 `context.l10n.moreCharged(_kr(diff), paymentMethod)` / `lessReturned` and route_change_flow.dart:188/192 `chargedTo(kr, paymentMethod)` / `refundedToDays`. A ride restored from a server projection that has no label shows the raw id ('cash', 'card:…') instead (ride_projection.dart:62). paymentLabelFor / paymentNameFor exist for this, and the reservation pages use them, but these paths do not.

**Suggested fix:** Pass the stored name through paymentLabelFor (and map ids such as 'cash', 'wallet', 'card:*' too) inside bookedPaymentLine and before the moreCharged/lessReturned/chargedTo/refundedToDays calls.

### L169. L10n.place never translates the 'Pickup location' fallback label, so it shows in English on every later screen

`lib/l10n/l10n.dart:92` (found by rider3)

**What happens:** Reverse geocoding fails for the confirmed pin → the ride is booked with label 'Pickup location'; the French rider sees 'Pickup location' as the pickup on the Finding/Waiting sheet, in History and in Support instead of 'Lieu de départ'.

**Why:** L10n.place only maps 'Current location' and 'Location off, set pickup'. The third app-generated sentinel, `pickupLocationFallbackLabel = 'Pickup location'` (pickup_address.dart:6), is returned by confirmedPickupAddress/bookingPickupAddress (:46-49, :69) as the ride's pickup label and is therefore shown through shortenPlace/compactAddress (place_format.dart:8) on Finding, Waiting, History and Support untranslated, although an ARB key `pickupLocation` ('Lieu de départ', 'Upphämtningsplats') exists. Reproduced: L10n.use('fr'); shortenPlace(pickupLocationFallbackLabel) == 'Pickup location' while L10n.current.pickupLocation == 'Lieu de départ'.

**Suggested fix:** Add `'Pickup location' => current.pickupLocation` to L10n.place.

### L170. Confirm sheet's Cancel button stays English in sv/fr: default cancelLabel 'Cancel' is never overridden by the three callers

`lib/shared/design_system/movera_confirm_sheet.dart:13` (found by rider-j8)

**What happens:** With the app in Swedish, a rider long-presses a saved place and taps Remove. The sheet reads 'Ta bort …?' with a 'Ta bort' button and an English 'Cancel' button. The same happens when deleting an emergency contact or replacing Home/Work.

**Why:** confirmMoveraAction defaults cancelLabel to the literal 'Cancel'. All three production callers pass title, message and confirmLabel from context.l10n but never pass cancelLabel: add_place.dart:104 (replace Home/Work), saved_places.dart:73 (remove place) and emergency_contacts_page.dart:51 (delete contact). The ARB files already have the key (`cancel`: 'Avbryt' in sv, 'Annuler' in fr), so the sheet mixes a translated title and confirm button with an English Cancel.

**Suggested fix:** Default cancelLabel to null and use `cancelLabel ?? sheetContext.l10n.cancel`, or pass context.l10n.cancel at every call site.

### L171. HorizontalSwipe keeps the drag origin in build-local variables, so a rebuild mid-drag resets start to 0: a leftward drag is swallowed or read as a right swipe

`lib/shared/widgets/horizontal_swipe.dart:22` (found by rider1)

**What happens:** Rider on Home drags the sheet left to open Payment while a location fix arrives (Home rebuilds ~1 Hz): nothing opens, or on a bottom-bar page the app pops to the previous tab instead of the next one.

**Why:** `start` and `last` are plain locals declared inside `build()` and captured by the three drag closures. GestureDetector re-syncs recognizer callbacks on every rebuild (RawGestureDetectorState.didUpdateWidget -> _syncAll re-initialises onStart/onUpdate/onEnd), so if the widget rebuilds while a finger is down, onUpdate/onEnd run with a fresh `start = 0`. `distance = last - start` then equals the absolute x position of the finger (always > 56 on a phone), so `right` is true regardless of direction. Callers: lib/features/home/presentation/home.dart:2177 wraps the Home sheet inside an AnimatedBuilder (rebuilds on every sheet tick and on every Home setState, e.g. each GPS fix delivered by HomeLocationController._deliverFix) with only onSwipeLeft -> a slow left swipe is swallowed and a fast one is cancelled because both `left` and `right` are true; lib/features/home/presentation/widgets/home_tab_page.dart:42 sets both callbacks, so a rebuild during a leftward drag pops the page with `HomeTabs.previousOf(tab)` (the wrong neighbour). Reproduced with a throwaway widget test (deleted): a 100 px leftward drag with one setState mid-drag printed `left=0 right=1`; the identical drag without the rebuild gave `left=1 right=0`.

**Suggested fix:** Make HorizontalSwipe a StatefulWidget (or keep start/last in a ValueNotifier/record owned outside build) so the drag origin survives rebuilds; alternatively use DragStartDetails/DragEndDetails only (d.velocity + accumulated delta from onHorizontalDragUpdate stored in State).

### L172. Transition builders allocate an undisposed CurvedAnimation on every transition frame, leaking status listeners on the route controller for the route's lifetime and losing curve-direction continuity on mid-animation reversal

`lib/shared/widgets/navigation_transition.dart:28` (found by rider-j8)

**What happens:** SelectRide or FindingDrivers (RideStageTransition) stays in the stack while many pages and sheets are pushed and popped above it. Each transition frame (about 20 per 360 ms push) adds another dead status listener to that route's controller. Memory grows with every navigation over the route, and every later status change iterates the whole list.

**Why:** Each transitionsBuilder (TopToBottomTransition:28, RideStageTransition:61, SwitchTransition:99, _sheetCover:169, _sideCover:193) constructs a CurvedAnimation. In this Flutter SDK the CurvedAnimation constructor always calls parent.addStatusListener(_updateCurveDirection), and only dispose() removes it. _ModalScopeState rebuilds buildTransitions through a ListenableBuilder on Listenable.merge(animation, secondaryAnimation) (flutter routes.dart:1101-1102, 1204-1208), so the builder runs on every tick of the route's own animation and of every route pushed or popped above it. Each tick leaves one more status listener on the route's AnimationController for the route's lifetime. Flutter's own CurvedAnimation docs (animations.dart:410-411) say not to recreate it on every build because it leaks. A fresh CurvedAnimation per frame also drops the curve-direction memory, so a pop that starts mid-push jumps to the reverse curve.

**Suggested fix:** Use `CurveTween(curve: ...)` chained on the animation, for example `animation.drive(CurveTween(curve: MoveraCurves.open))`, or move the curves into a StatefulWidget that owns and disposes its CurvedAnimation.

### L173. Connection banner and MoveraEmptyState are read twice by screen readers: an explicit Semantics label plus the unexcluded child Texts (empty state is at lib/shared/design_system/movera_empty_state.dart)

`lib/shared/widgets/realtime_connection_banner.dart:34` (found by rider-j8)

**What happens:** TalkBack or VoiceOver user on the trip screen: the connection drops and the live region announces 'Reconnecting. <body>' and then 'Reconnecting <body>' again. History's loading and empty states are read twice in the same way.

**Why:** The banner wraps its content in Semantics(liveRegion: true, label: '<title>. <body>'), but the title and body Text widgets below it are not excluded. Neither is a semantics boundary, so their labels merge into the same node and the live-region announcement reads the title and body twice. MoveraEmptyState (movera_empty_state.dart:29-31, Semantics(container: true, label: '$title. $message') above the same two Texts) has the same duplication on every empty and loading screen.

**Suggested fix:** Wrap the visual content in ExcludeSemantics, or drop the explicit label and keep only the Texts.

### L174. screenHorizPadding is computed once (lazy top-level), so after a web/desktop window resize side gutters stay at the first scale (e.g. 16 px vs 20 px) while ResSize-scaled layout rescales

`lib/shared/widgets/responsive_size.dart:3` (found by rider4)

**What happens:** Desktop/web rider resizes the browser window from phone width to 1280 px: everything scaled through ResSize.w grows to the 1.25 bound, but the side gutters in Chat, Home's location card and Trip detail stay at the old 16 x (old scale) value, leaving misaligned edges.

**Why:** `double screenHorizPadding = ScreenUtil().setWidth(16);` is evaluated on first read and never again. lib/app/screen_scale.dart:45-47 deliberately rebuilds ScreenUtilInit with new bounds on a window resize so widths rescale, but every consumer of this global (lib/features/messages/presentation/chat.dart:107-314, lib/features/home/presentation/home.dart:1990-2002, lib/features/ride_complete/presentation/trip_detail.dart:28, driver_info.dart:40) keeps the padding computed for the first window size while the rest of the layout (ResSize.w, which is a getter) rescales. If the first read happens before ScreenUtilInit has run (any host that builds one of those widgets directly) the value is derived from ScreenUtil's uninitialised defaults for the rest of the process.

**Suggested fix:** Make it a getter: `double get screenHorizPadding => ScreenUtil().setWidth(16);`.

### L175. core -> features/di import guard only matches single-quoted package: imports, so a relative import from lib/core bypasses it (no current breach)

`test/architecture/guard_test.dart:188` (found by rider2)

**What happens:** A developer adds `import '../../features/booking/application/booking_coordinator.dart';` to a file in lib/core; `flutter test test/architecture/guard_test.dart` still passes and the documented 'core is feature-agnostic' rule in ARCHITECTURE.md is silently broken.

**Why:** The architecture guard extracts directives with `^\s*(?:import|export)\s+'([^']+)'` and then only flags URIs that start with `package:movera_rider/features/` or equal `package:movera_rider/app/di.dart`. A file under lib/core that writes `import '../../features/x/y.dart';`, `import "package:movera_rider/features/x/y.dart";`, or a `part`/deferred/conditional form reaches features without tripping the guard. Relative imports are already in use elsewhere in lib (e.g. lib/features/home/presentation/home_map_style.dart:1, lib/shared/widgets/custom_google_map.dart:12,14), so the style is not forbidden by lint. No current violation exists, so this is a gap in the gate, not a live breach.

**Suggested fix:** Match both quote styles (`['"]([^'"]+)['"]`), resolve relative URIs against the file's directory before checking, and also reject any resolved path under lib/features or lib/app/di.dart; optionally add `always_use_package_imports` to analysis_options to make relative imports impossible.

### L176. lock_test idempotency-key tests are vacuous: failNext fails the quote POST, so only one ride POST is ever made and no keys are compared (coverage exists elsewhere)

`test/booking/lock_test.dart:105` (found by rider3)

**What happens:** A regression that generates a fresh Idempotency-Key on every retry (so a network blip double-books a ride), or that drops the header entirely on retry, passes both tests unchanged, while the test names claim the opposite is guaranteed.

**Why:** Both 'failed finding retry reuses the same logical booking key' (lines 105-126) and 'changed finding intent receives a new booking key' (lines 128-161) set `RecordingMockClient()..failNext = true` and expect the first `submitFinding` to throw. But `BookingCoordinator.submitFinding` first calls `_resolveQuoteBinding` (POST /api/v1/quotes) before posting /api/v1/rides, and `InProcessMockClient.failNext` returns 500 to the next request of any path. So the 500 hits the quote request; the rides endpoint is never reached on the failed attempt, and `RecordingMockClient.send` (which only records POST /api/v1/rides, lines 19-26) records nothing. The second submit records exactly one key. Both tests then assert `hasLength(1)` and `isNotNull`, which is satisfied regardless of whether the coordinator reuses, rotates, or never sends an idempotency key. Neither test compares a key across attempts, so the 'reuse' and 'new key' semantics are untested. Reproduced with a throwaway test (test/_audit_lock_vacuous_test.dart, since deleted) recording request paths: after the failed submit, `rideKeys` was empty and exactly one `POST /api/v1/quotes` had been made; the second submit produced one ride key; `flutter test` output: `00:00 +1: All tests passed!`.

**Suggested fix:** Make the failure hit the rides endpoint (e.g. a mock that fails only `POST /api/v1/rides` once, or pre-fetch the quote and pass the quote binding), then assert `idempotencyKeys` has length 2 and `keys[0] == keys[1]` for the retry case and `keys[0] != keys[1]` for the changed-intent case.

### L177. AUD-3 chevron test never taps the chevron: it is only built when the sheet is expanded, and the test never expands it

`test/finding_driver/audit_fix_cancel_first_test.dart:359` (found by r2-rider2)

**What happens:** Wire the chevron's onPressed to `_confirmCancel`, which is the AUD-3 regression. The test still passes because the chevron is never on screen when it looks.

**Why:** FindingDrivers renders the collapse chevron only `if (_sheetExpanded)`, and `_sheetExpanded` starts false. The test opens Finding at rest, looks up `find.bySemanticsLabel('Collapse')`, and taps it only `if (chevron.evaluate().isNotEmpty)`. That condition is false, so nothing is tapped, and `expect(find.text('Cancel ride?'), findsNothing)` holds trivially. The rest of the test checks the separate close button.

**Suggested fix:** Drag the sheet up (or set it with `_sheetController`) first, assert the chevron is found (`findsOneWidget`, not an `if`), tap it, then assert 'Cancel ride?' is absent and the sheet collapsed.

### L178. Required Phase 69 journey 'rider cancels after driver assignment' never mounts WaitingForDriver, and its cancel only succeeds through the 404 'no such ride' branch

`test/journeys/rider_cancel_test.dart:178` (found by r2-rider3)

**What happens:** Break WaitingForDriver._confirmCancel, for example by dropping the `RideNavigator.home(context)` call or never calling markCancelled when phase is matched. Or change the cancel path segment so the request hits the mock's 'No route' 404. The 'rider cancels after driver assignment' journey still passes, and the CI gate reports the cancel journey as green.

**Why:** batch5-phase69-test-integrity.yml requires this file as one of the six 'real Rider journeys'. The matched-cancel test pushes a hand-built Scaffold whose button 'Mirrors Waiting's production cancel'. It calls showCancelRideSheet and `ActiveRideController(api: _api()).markCancelled` directly, so none of WaitingForDriver._confirmCancel runs (fee note, phase, change-destination branch, outcome handling, map park, RideNavigator.home). Neither test seeds the ride on the server: `_api()` is a fresh InProcessMockClient with no `rides` entry, and `seed()` writes only local state. The cancel POST therefore gets `status = 404; _error('not_found')`. Both `_requestServerCancel` and Finding's cancel treat 404 as `confirmed`. Any 404 passes the journeys, including the mock's catch-all 'No route for $path' 404 for a wrong URL. The same unseeded pattern appears in cancel_first_controller_test.dart, web/installed_pwa_cancel_restore_test.dart and integration_test/ride_flow_test.dart:60.

**Suggested fix:** Mount the real WaitingForDriver (as waiting_external_terminal_test does) and seed `server.rides[rideId]` with an accepted trip. Assert that the server row becomes cancelled_by_rider, the route returns Home, and History holds the record.

### L179. 'each placeholder survives translation' skips every count/number placeholder, and plural =1 branches are never rendered

`test/l10n/l10n_parity_test.dart:68` (found by r2-rider4)

**What happens:** Change the sv text of retrySeconds to `{count, plural, =1{1 sekund} other{några sekunder}}`, or leave the fr `=1` branch of tripSharingStarted in English. The rider then sees 'några sekunder' with no number, or English in French, and rider-l10n.yml stays green.

**Why:** tool/gen_l10n_messages.py passes the sample `3` for int/num/double placeholders. It writes into `messagePlaceholders` only the names whose type is String (`if dart_type(s) == 'String'`). So for homeRideCount, ridesLeft, validUntilDays(days), driverTripCount, tripSharingStarted, safetyContactsCount, retrySeconds and resSeatsPayment(count), the test never checks that `{count}`/`{days}` survives in fr/sv. Every message is also rendered only with 3, so the `=1{...}` branch of each plural is never checked, for either 'translated' or 'placeholder present'.

**Suggested fix:** Use a distinctive numeric sample (for example 37), check that the rendered text contains '37' for numeric placeholders, and render each plural message with 1 as well, comparing it against English.

### L180. 'Book for later keeps the addresses already entered' never sends the addresses to any production object, so its address assertions compare constants with themselves

`test/reservations/scheduled_booking_flow_test.dart:363` (found by r2-rider1)

**What happens:** Home's 'Later' path replaces the addresses already typed with 'Current location' or an empty destination when it switches to Book for later (compare the known schedule_ride.dart:58 prefill bug). The test still passes, because the addresses it checks never left the test.

**Why:** The test declares `const pickup = 'Klockarvägen 37'` and `const dropoff = 'Arlanda Express'`, switches a fresh RideSelectionController to scheduled, and ends with `expect(pickup, 'Klockarvägen 37'); expect(dropoff, 'Arlanda Express');`. The addresses never reach any production object, so the two address assertions compare a constant with itself. guard_test only checks that this test name exists.

**Suggested fix:** Enter both addresses on Home or RoutePicker, choose Later, and assert the addresses shown on ScheduleDateTimeSelector/SelectRide/SetPickup and in the created reservation.

### L181. 'edit hydrates the saved payment instead of defaulting to Cash' does the hydration itself, so it cannot catch SelectRide losing it

`test/reservations/scheduled_booking_flow_test.dart:409` (found by r2-rider1)

**What happens:** Delete the `editingReservationId` branch in SelectRide.initState, or let `restoreDefaultPayment()` run after it. Editing a Card reservation then re-saves it as Cash, which is the bug the test title names, and the test still passes.

**Why:** In production, payment hydration on edit happens only in SelectRide.initState. It reads `_reservations.byId(widget.editingReservationId!)?.paymentMethod` and calls `_selection.selectPaymentNamed(paymentName)` (select_ride.dart:347-352, again at :406). The test never builds SelectRide. It first asserts that a fresh selection is NOT on Card, then calls `edit.selectPaymentNamed(first.paymentMethod)` itself, and finally asserts the reservation kept 'Card'. All it proves is that ScheduledRideBooking.confirm copies whatever the selection holds. No other test passes `editingReservationId` to SelectRide.

**Suggested fix:** Pump SelectRide with `editingReservationId` pointing at a reservation paid by Card, let `_loadSavedCards` finish, and assert the selected payment before confirming.

### L182. book_now_two_paths_e2e_test names are misleading: the 'starts Finding Driver' test only pumps ConfirmPickupSpot behind a stand-in button, and its findsNothing check is on copy no longer in lib; guard_test only checks that the strings exist. The real Book now flow is covered by book_to_home_test

`test/ride/book_now_two_paths_e2e_test.dart:128` (found by r2-rider1)

**What happens:** Change Home or SelectRide so that Book now with a GPS fix skips Set pickup/Confirm pickup and books straight away, or so that Confirm pickup never pushes FindingDrivers. Every test in this file still passes, and the guard test still passes because the strings are still in the file. Line 162 also treats the untranslated placeholder 'Pickup location' as the correct booked pickup address, which is the behaviour behind the known L10n.place finding.

**Why:** The file says it is the 'Book now E2E on two paths' and claims GPS on and GPS off both open Confirm pickup. None of the tests goes through Home or SelectRide. 'GPS available/unavailable still opens Confirm pickup' pump `ConfirmPickupSpot` directly as `home:`, so all they show is that the widget renders. 'Confirm pickup then Select Movera starts Finding Driver' builds its own `TextButton(child: const Text('Select Movera'))` that calls `ConfirmPickupSpot.open`, then only checks `spot != null` and `spot.address == 'Pickup location'`. Nothing in it checks Finding, the ride status or `FindingDriverController.active`. The `findsNothing` checks on 'Connecting you with nearby drivers' look for copy the app no longer has (it is in no ARB or lib file), so they can never fail. guard_test.dart:600-620 does not check behaviour either: it only checks that these test names and the dead string appear in the test file's text. That pins the vacuous assertion in place.

**Suggested fix:** Drive the real flow: pump Home or SelectRide with a fake location repository (fix and no fix), tap the real CTA, and assert that ConfirmPickupSpot/SetPickupPage appears and then FindingDrivers with `ride.status == findingDriver`. Replace the dead-copy findsNothing with `find.byType(FindingDrivers)`, and delete the string-presence guard.

### L183. Empty `_guards()` body: the documented replacement guard for 'mock never invents a driver' asserts nothing

`test/ride/mock_driver_assignment_test.dart:49` (found by rider1)

**What happens:** A presentation widget or controller starts constructing a `MatchedDriver` locally when the API returns none; nothing in this test file fails, although its comment claims the invariant is guarded.

**Why:** `_guards()` is called from main() (line 37) and carries a doc comment explaining it is 'The guard that replaces "the mock never invents a driver"' and that 'no screen, controller or feature repository may conjure a driver of its own'. Its body is empty, so the rule it documents is not enforced by any test in this file.

**Suggested fix:** Implement the guard (e.g. assert that no file outside lib/core/api constructs `MatchedDriver(` with literal mock identities, or that `MockDriverPool` is only referenced from the in-process mock client) or delete the empty function and its misleading comment.

### L184. The phase71 'driver call is explicitly unavailable' tests supply the unavailable-dialog callback themselves, so WaitingForDriver's real onCall wiring (waiting_for_driver.dart:1894/1909) is never tested

`test/safety/phase71_real_calling_test.dart:87` (found by r2-rider3)

**What happens:** Change WaitingForDriver to `onCall: () => launchUrl(Uri(scheme: 'tel', path: driver.phone))`, which dials an unmasked number, or to a no-op. The batch6/phase71 'explicitly unavailable' tests still pass.

**Why:** Both widget tests build WaitingDriverCard/RiderInTripPanel with `onCall: () => showDriverCallUnavailable(...)` written in the test, then tap Call and find the dialog. The production wiring is WaitingForDriver passing `onCall: _callDriverUnavailable` (waiting_for_driver.dart:1888, :1903), and it is never exercised. The tests only show that a callback the test supplies is called.

**Suggested fix:** Pump WaitingForDriver with a matched driver (as waiting_external_terminal_test does), tap 'Call driver', and assert the unavailable dialog appears.

### L185. 'duplicate payment key returns same intent family' asserts only the amount, so it cannot detect a second intent (or the wrong intent) being returned

`test/wallet/gateway_test.dart:28` (found by r2-rider4)

**What happens:** Remove the idempotency check, so every call creates `pi_<new>`, and the test still passes. Or create key A (100 kr), then key B (200 kr), then retry A. The mock returns B's 200 kr intent, and no test notices.

**Why:** The test creates two intents with key 'dup' and asserts `second.amountMinor == 5000`. Any newly created intent for 5000 öre satisfies that, so idempotency is not tested. It also hides a defect in the mock: on a reused key MockPaymentGateway returns `_intents.values.last`, the most recently created intent of any key, not the one created for that key. ops_test 'top-up idempotency key reused' uses a single key too, so the mismatch is never seen.

**Suggested fix:** Assert `second.id == first.id`. Add a two-key case and key the mock's map by idempotency key.
