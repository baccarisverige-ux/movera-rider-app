# Movera rider app: bug audit (partial, saved 2026-10-21)
Confirmed: 78 (high 4, medium 27, low 47). Rejected as false alarms: 24.
Each finding was checked by an independent code tracer and a reproducer (often with a throwaway flutter test), with a third reviewer on disagreements. Deep-search runs still in progress at save time are not included.

## High (4)

### H1. Driver drop while a child route is open pops that route instead of Waiting; Waiting is left dead and Finding never restarts the search

`lib/features/active_ride/presentation/waiting_for_driver.dart:657`

**What happens:** Rider is on Waiting and opens the driver's profile (or chat, or the cancel sheet, or 'Change route'); the driver drops the ride. The profile page closes by itself, the rider lands back on a grey, parked Waiting screen showing the old driver with no live updates and no way to cancel (`_confirmCancel` returns on `_leaving`), while the server trip is back in `searching` and the next driver's acceptance is never shown.

**Why:** `_onLiveTick` handles `cancelledByDriver` immediately and deliberately bypasses the route-current gate (lines 405-415). `_researchAfterDriverCancel` disposes tracking, reconciles the session back to `findingDriver`, sets `_leaving = true`, then does `final navigator = Navigator.of(context); if (navigator.canPop()) { navigator.pop(true); return; }` (651-659). The app has a single navigator (app.dart:34, MoveraSheet.show uses rootNavigator: true), so `pop(true)` pops whatever route is on top: the driver profile (`_openProfile`, 976), Chat (waiting_sheet_bits 215), the arrived sheet, the cancel/reason sheets, the Safety Kit or the RoutePickerPage opened by `_changeRoute`. Waiting itself stays mounted with `_leaving = true`, `_mapParked = true` and a disposed `DriverTrackingController`; `FindingDrivers._openWaiting` (finding_drivers.dart 535-557) never receives `true`, so `_resumeFindingAfterDriverCancel` never runs and `FindingDriverController.active` stays null. Reproduced with a throwaway widget test (Waiting pushed over a parent, DriverProfilePage pushed above it, `MockRideRealtime.cancelByDriver()`): output was `profile still mounted: false`, `waiting still mounted: true`, `waiting route result: null`, `session status: RideStatus.findingDriver`.

**Suggested fix:** Pop Waiting's own route by reference (store `ModalRoute.of(context)` in initState and use `Navigator.of(context).popUntil`/`removeRoute` on that route, or `closeRouteByReference`-style logic), or defer the research until `_routeIsCurrent` like the other stage navigations do.

### H2. History archives book-now rides with a UTC DateTime that is then rendered field-by-field, so times/dates show in UTC

`lib/features/history/data/on_demand_ride_history_store.dart:201`

**What happens:** Stockholm rider finishes a ride at 14:30 local (CEST). History lists it as '12:30'. A ride ended 00:40 on 1 May shows as 30 Apr 22:40 and is counted in April on the home 'Your month' card; near midnight the Today/Yesterday split is wrong. In Tunisia (UTC+1) every History time is one hour early.

**Why:** recordFor stores `scheduledPickupAt: ended.toUtc()` (line 201) and `createdAt: snapshot.createdAt.toUtc()`. The History UI then formats that DateTime with helpers that read the DateTime's own fields rather than converting to local: ReservationFormat.time (lib/features/reservations/presentation/reservation_format.dart:70-74 uses `when.hour`/`when.minute`), ReservationFormat.moment/historyWhen (221-227 compare `when.year/month/day` to a local `DateTime.now()`), weekdayDate/_dayMonth via L10n.formatDate (intl formats the instance's fields; a UTC DateTime prints UTC), called from lib/features/history/presentation/ride_history.dart:546 `ReservationFormat.historyWhen(ride)`. HomeJourneySection.fromRides (lib/features/home/presentation/widgets/home_journey_section.dart:74-83) likewise buckets by `at.year/at.month` and `weeks[(at.day - 1) ~/ 7]` on the UTC value against a local `now`. The only consumer that converts, SupportController (`when: ride.scheduledPickupAt.toLocal()`), shows the correct intent. Verified by throwaway test: a ride ended at 14:30 CEST archived via recordFor and formatted with ReservationFormat.time gave '12:30'.

**Suggested fix:** Either store `ended.toLocal()` in the archived Reservation (consistent with how book-later Reservations hold wall-clock local times) or make every formatter/aggregator call `.toLocal()` before reading fields (ReservationFormat.time/moment/cardDate/weekdayDate, HomeJourneySection.fromRides). Add a test with a UTC-constructed DateTime.

### H3. Server-backed History silently drops every fully settled trip (RideStatus.closed) and every paymentFailed trip

`lib/features/history/data/on_demand_ride_history_store.dart:243`

**What happens:** Rider completes a trip, pays, rates the driver. Server projection now has status completed/paymentStatus settled/ratingStatus submitted -> RideStatusWire.fromTrip -> RideStatus.closed. The History screen loads /trips, _record returns null for it, and the ride (and every older settled ride) is not listed. A rider with 50 past trips sees an empty or near-empty History; a trip whose card payment failed also disappears, so the rider cannot see what is owed.

**Why:** ApiRideHistoryRepository._record (lib/features/history/data/ride_history_repositories.dart:56-66) feeds each server TripProjection through RideProjection.toSnapshot and then OnDemandRideHistoryStore.recordFor(snapshot, terminalStatus: snapshot.status, ...). recordFor maps the status with _reservationStatus (lines 243-259), which returns ReservationStatus.completed only for status.isCompletedSurface (tripCompleted | paymentProcessing | paymentFinalized | ratingPending per lib/core/contracts/ride_status.dart:85-89) and ReservationStatus.cancelled only for an explicit cancelled list. RideStatus.closed (trip completed + payment settled + rating submitted/skipped) and RideStatus.paymentFailed are in neither branch, so _reservationStatus returns null and recordFor returns null (line 194), i.e. the trip is omitted from History. In release builds (ApiRideHistoryRepository) almost every finished trip the server returns is eventually `closed`, so the History tab loses the rider's past rides and their receipts; a payment-failed ride (which the rider must settle) also vanishes. Verified with a throwaway test (test/_audit_datamath_test.dart, since deleted): recordFor(...terminalStatus: RideStatus.closed) and paymentFailed both returned null while ratingPending returned a record (`3 passed` for these cases).

**Suggested fix:** In _reservationStatus treat RideStatus.closed and RideStatus.paymentFailed as ReservationStatus.completed (optionally carry a payment-failed flag on the Reservation for the receipt), or add a separate mapping for server trips in ApiRideHistoryRepository. Add a test that a `completed`+settled+rated projection appears in History.

### H4. "Arrive by" mode books the chosen arrival time as the pickup time

`lib/features/scheduled_rides/presentation/select_date_time.dart:153`

**What happens:** Rider taps "Arrive by", picks 10:00 for a 20-minute trip; screen says "Estimated pickup 09:40". The reservation is created with scheduledPickupAt = 10:00; Home chrono counts down to 10:00 and the driver is dispatched for a 10:00 pickup, so the rider arrives at ~10:20 instead of by 10:00.

**Why:** The scheduling screen offers two modes, "Pickup at" and "Arrive by" (`_modeSelector`, lines 585-608 toggle only `_pickupMode`). In "Arrive by" mode the estimate row shows `_selectedDateTime.subtract(trip)` as the "Estimated pickup" (lines 484-488, 726-749), so the rider understands the chosen time is their arrival. But the time committed to the session is always `_selectedDateTime` itself: `_commitSchedule()` (153-158) calls `captureSchedule(_selectedDateTime, ...)` and the `popOnConfirm` path returns `_selectedDateTime` (130-132). `_pickupMode` is never read anywhere else in the file. The committed time becomes `ScheduledRideSession.scheduledAt` -> `SelectRide.initialScheduledFor` -> `ScheduledRideCheckout.draftFrom(scheduledPickupAt: when)` (scheduled_ride_checkout.dart:21-31), i.e. the pickup time of the reservation.

**Suggested fix:** When `_pickupMode == false` and `tripMinutes` is known, commit/return `_selectedDateTime.subtract(Duration(minutes: trip))` (clamped with `clampPickup`) as the pickup; hide the Arrive-by mode when `tripMinutes` is null.

## Medium (27)

### M1. Cold start awaits push re-registration (Firebase init, getToken, POST /push/devices) before runApp, blocking the first frame on the network

`lib/app/bootstrap.dart:130`

**What happens:** Production rider on a poor connection opens the app: the splash/boot screen stays up to ~15 s (API timeout) plus however long FCM getToken takes before Home appears; on web the boot screen can vanish at 20 s into a blank page.

**Why:** `await _registerExistingPushSession()` runs before `runApp`. In staging/production with stored tokens and an accepted push consent it calls `PushPermissionGate.registerIfConsented` -> `FirebasePushService.register()` (lib/core/notifications/firebase_push_service.dart:198-227), which awaits `_gateway.initialize`, `requestPermission`, `getToken` (FCM network round-trip, no timeout in this code) and `_replaceToken` -> `_api.post('/api/v1/push/devices')` (ApiClient `_timeout` 15 s). Nothing in the app is painted until it resolves. The comment at lines 143-147 states the rider must not be kept waiting on push registration and defers `_pushCoordinator.start()` for that reason, but this earlier await defeats it. On the web the HTML boot screen's fallback timer (web/index.html:144 `setTimeout(clear, 20000)`) can remove the loading screen before Flutter paints, leaving a blank page.

**Suggested fix:** Do not await it: `unawaited(_registerExistingPushSession())` after runApp (e.g. in the same post-frame callback as `_pushCoordinator.start()`), or run it with a short timeout.

### M2. Route-change pricing charges booked stops again: bookedKm is the straight pickup-to-destination distance while routeKm goes through the stops, plus a 25 kr fee for every stop

`lib/core/api/in_process_mock_client.dart:2319`

**What happens:** Demo/dev/test flavors (the stand-in backend the live GitHub Pages build uses). Rider books a multi-stop trip, then edits the destination by a few metres (or just re-confirms the same route) during the ride: the sheet shows a large surcharge (here +88 kr), and for card/wallet methods the mock records a captured adjustment for it. Money shown and 'charged' is wrong on every route change of a multi-stop trip.

**Why:** `_ride()` stores `bookedKm` as the straight pickup->destination distance (lines 2319-2330) even when the booking body carries `stops` (which `_quote` priced through, via `_routedMeters`, lines 2103-2124 / 2134-2137). `_routeChangePricing` (lines 2046-2096) then prices a change as `bookedMinor + stops.length * 25 kr + (routeKm - bookedKm) * perKm`, where `routeKm` is pickup -> stops -> destination (lines 2071-2080). For a ride booked with a stop, a route change that keeps the same stop charges the stop's detour kilometres a second time plus a 25 kr stop fee that the quote never contained. The result is returned as `newTotal`/`difference` from `POST .../route-quote` and `PATCH .../rides/{id}` (routeChange) and, for non-cash methods, written as a `paymentAdjustments` capture (lines 919-932). Reproduced: booking pickup (59.3293,18.0686) -> stop (59.35,18.10) -> dest (59.3326,18.0649), fare 29 100 öre; route-quote of the identical route: `AUDIT B1: bookedKm=0.42 routeKm=5.69 newTotal=37900 difference=8800` (+88 kr for changing nothing).

**Suggested fix:** Store `bookedKm` from the routed distance through the booked stops (reuse `_routedMeters(body)`), and only add the 25 kr fee for stops that are new relative to the booked `ride['stops']` (or drop the per-stop fee, since `_quote` never charges one).

### M3. `MatchedDriver.fromJson` reads `id`/`vehicleMake`/... but the contract `DriverSummary` carries `driverId` and a nested `vehicle`, so a contract-conformant projection parses to no driver

`lib/core/contracts/matched_driver.dart:80`

**What happens:** Staging/production flavor against a backend built from `contracts/openapi.yaml`: the trip reaches `accepted`; `ApiRideRealtime` emits `driverAssigned` with `driver: null`; Waiting shows 'Driver details unavailable' (no name, plate, vehicle, photo) for the whole ride, and the history/receipt has no driver either.

**Why:** The production transport `ApiRideRealtime` builds the driver from the projection with `MatchedDriver.fromJson` (api_ride_realtime.dart lines 201-204), as do `ride_projection.dart:68` and the restore path. `fromJson` requires `json['id']` (line 80, returns null when empty, line 83) and reads flat `vehicleMake/vehicleModel/vehicleColor/plate/photoAsset`. `contracts/openapi.yaml` `DriverSummary` (lines 5281-5305, required `driverId, firstName, vehicle`) and CONTRACT.md §2 (`DriverSummary { driverId, firstName, ..., photoUrl?, vehicle: { make?, model?, color?, plate? } }`) never send `id` or flat vehicle fields. The in-process mock sends `MatchedDriver.toJson()` (`id`, `vehicleMake`, ...), so the mock and the parser agree with each other but not with the shipped contract, and no test can catch it. Against a server that follows `openapi.yaml`, every projection yields `driver == null`.

**Suggested fix:** Accept `driverId` (and `photoUrl`, nested `vehicle.{make,model,color,plate}`) in `fromJson` alongside the legacy flat keys, and have the mock emit the contract shape so the contract tests exercise it.

### M4. Firebase-configured web builds (none deployed today) would replace the root-scope Firebase SW with Flutter's self-unregistering flutter_service_worker.js on every cold start, forcing a reload and killing the push subscription

`lib/core/notifications/firebase_push_service.dart:118`

**What happens:** Staging/production web build with Firebase defines; rider accepted ride-update notifications. Every cold start: boot screen, 1-4 s pause, page reloads itself once, then boots; `/api/v1/push/devices` receives a new token on every launch and old tokens are never unregistered. If the reload lands during an active search, the search restores from the snapshot but the rider sees the app restart.

**Why:** `getToken` passes `serviceWorkerScriptPath: 'firebase-messaging-sw.js'` and firebase_messaging_web registers it with `navigator.serviceWorker.register(path)` and no `scope`, so the registration's scope is the app root (`/movera-rider-app/`). The build never passes `--pwa-strategy=none` (publish-web-live.yml line 45), so Flutter 3.47's `flutter build web` still emits `flutter_service_worker.js` and a `flutter_bootstrap.js` with `serviceWorkerSettings` (flutter_tools web.dart: `includeServiceWorkerSettings = strategy == offlineFirst`, compile.dart defaults to offlineFirst). Flutter's loader (`service_worker_loader.js` lines 105-113) calls `navigator.serviceWorker.getRegistration()` and, whenever ANY registration covers the page, registers `flutter_service_worker.js?v=...` at the same default scope, which replaces the Firebase registration's script. The 3.47 `flutter_service_worker.js` template is a cleanup worker: on activate it `unregister()`s and `client.navigate(client.url)` for every window client. index.html's cleanup (lines 169-176) deliberately keeps the Firebase registration, so on each boot where push consent was accepted: boot waits up to 4 s for SW activation, the page is force-reloaded mid-boot, the push subscription dies with the registration, and `_registerExistingPushSession` then re-registers the Firebase SW and POSTs a brand-new FCM token (`_replaceToken` only unregisters the previous token held in memory, so stale tokens accumulate server-side). The same `getRegistration()` path also fires once for demo visitors who still carry an old `flutter_service_worker.js` registration, because index.html's async `unregister()` races the deferred bootstrap.

**Suggested fix:** Build with `--pwa-strategy=none` (or ship a custom web/flutter_bootstrap.js that calls `_flutter.loader.load()` without `serviceWorkerSettings`), and/or register firebase-messaging-sw.js under its own scope (e.g. `firebase-cloud-messaging-push-scope`) so the loader's root-scope `getRegistration()` finds nothing.

### M5. After the not-found pause, a successful resync never restarts periodic polling: the ride freezes while the connection reports connected

`lib/core/realtime/api_ride_realtime.dart:383`

**What happens:** Production transport (staging/production flavors). The trip endpoint answers 404 three polls in a row (replica lag, a brief routing fault). Polling pauses and the banner shows failed. The rider taps retry / the app resumes -> `reconnectAndResync` -> 200, banner says connected. From then on the driver's position, arrival, boarding and completion never arrive on this screen; the ride appears stuck at that status indefinitely although the connection state claims it is live.

**Why:** `_endNotFound` (lines 347-353) cancels `poll.timer` and sets `poll.timer = null` after `notFoundLimit` consecutive 404s. `reconnectAndResync` (lines 379-390) only flips `poll.ended = false`, lowers `poll.notFound` and runs one forced `_poll`. Nothing re-creates the `Timer.periodic` that `subscribe()`'s `onListen` made (lines 69-77), and `onListen` does not run again because the broadcast controller already has its listener. When the forced poll succeeds, the success path calls `connection.markConnected()` (line 256) so the UI banner clears, but no further GET is ever issued for that ride: the Waiting/in-trip screen keeps showing the projection from that single read until the user triggers another manual resync. Reproduced with a throwaway test (3x404, resync -> 200, pollInterval 20 ms): `AUDIT A: events after resync = 1, state = RealtimeState.connected` then `AUDIT A: calls after 200ms of connected state = 4` (no new polls). Callers: `FindingDriverController` lines 897/1156/1288/1642, `WaitingForDriver` line 929, `RideRestoreCoordinator` line 167, `notification_navigation.dart` line 89 all use `reconnectAndResync` as the recovery path.

**Suggested fix:** In `reconnectAndResync` (or in `_poll`'s success path when `poll.timer == null` and the controller has listeners) re-create `poll.timer = Timer.periodic(pollInterval, (_) => unawaited(_poll(poll)))` once the forced read succeeds; keep it cancelled while `poll.ended` is true.

### M6. Mock driver position and arrival are computed against a hard-coded central-Stockholm pickup (never hydrated on resume, hydrated only after the first assignment fix), so after a reload the driver approaches and 'arrives' at Stockholm instead of the trip's pickup

`lib/core/realtime/mock_ride_realtime.dart:183`

**What happens:** Demo build (R-web: 'a live ride must survive browser reload'). Rider books Gare du Nord -> Louvre (Q7 Paris zone) or a Södertälje pickup, gets a driver, reloads the tab: the driver marker appears in central Stockholm, the ETA reads ~2 min then jumps, the car 'arrives' and the trip starts from a point tens or hundreds of km from the pickup, and the free-cancel countdown restarts from the reload.

**Why:** `_pickupLat/_pickupLng` default to (59.3293, 18.0686) in both the resume path (lines 183-184) and `_assignNow` (lines 263-264), and the driver start position is derived from that default (`lastLat ??= _pickupLat! + 0.0072`, lines 209-210 and 265-266). The real pickup is only fetched by `_hydratePickup()` after the `driverAssigned` event (line 305) and never on the `primeResume` path; after a web reload the stand-in server is empty anyway so `_pickup()` 404s and keeps the default (line 660). `_startGps` therefore lerps toward and declares `driverWaiting` within 50 m of central Stockholm for a Paris/Tunis/Södertälje pickup, `_etaSeconds` is computed against that point, and the resumed `emit()` sets `_acceptedAt ??= now` / `_waitingSince ??= now` (lines 328-333) which `DriverTrackingController` adopts (`acceptedAt = event.acceptedAt ?? acceptedAt`) so the free-cancel/waiting clocks restart at reload time. Reproduced: a Paris trip resumed via `primeResume(driverArriving)`: `AUDIT D: resumed event lat=59.3365 lng=18.0638 eta=102s acceptedAt=<now>`.

**Suggested fix:** Let `primeResume` (and the first assignment) take the pickup coordinates and the snapshot's `acceptedAt`/`waitingArrivedAt`; hydrate the pickup before emitting `driverAssigned`, and do not stamp `_acceptedAt`/`_waitingSince` with the resume time.

### M7. Reload during re-dispatch after a driver drop restores Waiting with the dropped driver; Waiting never reacts to a searching status

`lib/features/active_ride/presentation/waiting_for_driver.dart:417`

**What happens:** Release build: driver accepts, then drops the ride; the rider reloads the web app (or the process is restarted) before the next driver accepts. Waiting shows the old driver as 'on the way' while the server is searching; messages go to a driver who is no longer on the trip.

**Why:** `DriverTrackingController._persistLiveStatus` skips terminal statuses (211-212), and `ActiveRideController.resumeSearchingAfterDriverCancel` explicitly does not persist (327-334), so after a driver drop the stored snapshot still says `driverArriving`/`driverAssigned` with the old driver until the next accept. A reload in that window (`RideRestoreCoordinator.surfaceFor`, 285-291) restores `WaitingForDriver` with `driver: snapshot.driver`. With `ApiRideRealtime` the first poll carries `searching`; `reassigned` is only derived when `poll.lastStatus?.isMatched` (api_ride_realtime.dart 193-199), which is null on a fresh poll, so the event is a plain `findingDriver`. `_onLiveTick` has branches only for `cancelledByDriver`, terminal and completed statuses (410-423); a searching status falls through to the normal sheet rendering, so the screen keeps the 'Driver found' headline (`_headlineFor` → `eta?.headline(status: findingDriver)`), the dropped driver's card, plate and message/call buttons, and no reassignment notice. The rider only learns a new driver was assigned when the next accept arrives; a second reload would restore Finding because `_persistLiveStatus` then saves `findingDriver`.

**Suggested fix:** Persist the `findingDriver` status (without driver) when the research starts, and have Waiting treat an incoming `isSearching` status the same way as `cancelledByDriver` (back to Finding).

### M8. Back gesture while the Waiting cancel/end-early request is in flight pops Waiting; Finding underneath stays parked and the cancel result is lost

`lib/features/active_ride/presentation/waiting_for_driver.dart:820`

**What happens:** On Waiting the rider confirms 'Cancel ride', the network is slow, and they press the Android back button during the 'Cancelling…' card. Waiting disappears and the rider sees a dead grey Finding screen; depending on the server answer the ride is either cancelled with no Home navigation or still live with no way to see or cancel it from this screen.

**Why:** `_confirmCancel` sets `_leaving = true; setState(() {});` (820-821) before `await _ride.markCancelled(...)` (838). `PopScope(canPop: _leaving, ...)` (1441) therefore lets a system back pop Waiting while the server request is still out (up to two attempts with 15 s timeouts each). The `_cancelling` overlay only blocks pointer input, not back. After the pop, `if (!mounted) return;` (846) discards the outcome: if the server confirmed, `_commitCancelled` already cleared the snapshot and set the session to `cancelledByRider` but `RideNavigator.home` is never called; if it was `pendingRetry`/`rejected`, the ride stays live with no screen. Waiting was pushed by `FindingDrivers._openWaiting` with `await Navigator.push<bool>` (finding_drivers.dart 535-556); the pop returns null, so `researchDriver != true` and Finding remains with `_leaving = true`, `_mapParked = true` and a disposed `_match` (528-531): a blank parked screen whose close button is inert (`_confirmCancel` returns on `_leaving`, 568).

**Suggested fix:** Keep `canPop` false while `_cancelling` is true (set `_leaving` only after the outcome is known), or handle `didPop` by finishing the flow from the result.

### M9. A pasted international number (+46 …) at sign-in or Add phone is either rejected or, in the spaced form, cut short and accepted as a wrong number (+4646…) that the OTP is sent to

`lib/features/auth/presentation/auth_navigation.dart:993`

**What happens:** Rider pastes their number from the clipboard/contacts in international format on Sign in or Add phone; Continue is refused with an "invalid" error.

**Why:** `AuthPhoneField` filters input to digits and spaces (auth_controls.dart:289-292), so a pasted `+46 70 123 45 67` becomes `46 70 123 45 67`. `swedishNumberFromField` then prefixes `+46` to anything not starting with `0` (993) giving `+4646701234567`; `toE164` sees 11 digits after +46 and returns null, so the screen shows "invalid Swedish mobile" for a valid number the rider pasted from Contacts.

**Suggested fix:** Strip a leading `46`/`0046` before prefixing, or pass the raw digits to `toE164` which already handles `46…`/`0046…` prefixes.

### M10. Finding treats a driver drop (cancelledByDriver) that arrives while a match is deferred as the end of the ride: it archives the ride as cancelled, clears the snapshot and sends the rider Home while the server trip is searching again

`lib/features/finding_driver/application/finding_driver_controller.dart:394`

**What happens:** Rider raises the offer; while the PATCH is out a driver accepts and immediately drops the ride. The next poll delivers `cancelledByDriver` to Finding: the ride is filed in History as cancelled, the snapshot is cleared and the rider is sent Home, although the server trip is still searching and may be accepted by another driver.

**Why:** `RideStatus.cancelledByDriver` is in `isTerminal` only so the UI stops tracking the old driver; the trip itself is back in `searching` (core/contracts/ride_status.dart 31-36, trip_status.dart 134). Waiting handles it as a reversible re-dispatch, but the Finding listener does `if (event.status.isTerminal) { unawaited(_completeTerminal(event.status)); return; }` (394-397), and `_completeTerminal` archives `cancelledByDriver` to History as a cancelled ride (1027-1035), clears the snapshot and fires `_onTerminal`, which shows the 'Driver cancelled … Continue' sheet and `RideNavigator.home` (finding_drivers.dart 330-334). The event is reachable while Finding is still the subscriber: `ApiRideRealtime` maps a matched→searching projection to `cancelledByDriver` (api_ride_realtime.dart 193-199), and Finding stays subscribed after an accept whenever `_completeAssigned` is deferred (`_assignmentPending` because an offer raise/pickup edit or a cancel is in flight, 939-945) or during the `_persistAssigned` await before `_openWaiting` disposes the controller.

**Suggested fix:** In the Finding listener treat `cancelledByDriver` as 'back to searching' (reset `_assigned`/`_assignmentPending`, keep the search) instead of routing it to `_completeTerminal`.

### M11. Home's load() keeps only the first 8 custom places and every Home persist() writes that cut list back, so places 9 and later are deleted from storage

`lib/features/home/application/home_places_controller.dart:69`

**What happens:** Rider adds nine custom places in Menu > Saved places. They book a ride from Home; _persistAddressData runs and the ninth place disappears from Saved places permanently.

**Why:** HomePlacesController.load() maps `saved.places ... .take(maxCustom)` (8) into savedPlaces, and persist() writes `places: savedPlaces.map((place) => place.toJson()).toList()` to the shared HomeAddressRepository keys. SavedPlacesController.save() has no cap and appends freely (saved_places_controller.dart:98-99). Home persists on every booking/route change (_showRouteAddressPicker -> _persistAddressData, home.dart:1003) and after any saved-place edit, so the first Home persist after a 9th place exists removes places 9+ from storage for good. Reproduced: 9 stored places -> load gives 8 -> persist stores 8 (test output `loaded 8 of 9`, `stored after persist: 8`).

**Suggested fix:** Either enforce the same cap in SavedPlacesController.save, or keep the untruncated list (or re-read storage) when Home persists so it never writes fewer places than are stored.

### M12. Custom saved places are matched by type: editing or adding a second place of the same kind overwrites the first

`lib/features/home/application/home_places_controller.dart:133`

**What happens:** Rider has 'Gym A' and 'Gym B' saved from Saved Places. On Home they long-press the Gym B card and enter a new address: Gym A's address is replaced, Gym B is unchanged, and the change is persisted. Likewise 'Add place > Gym' with an existing gym silently overwrites it.

**Why:** Saved Places (SavedPlacesController.save, FLOW-5) deliberately allows several custom places of the same kind, each with its own id (saved_places_controller.dart:84-102). Home's edit path ignores ids: SavedPlacesRow long-press passes only `place.type` (saved_places_row.dart:108-110), _editSavedPlace -> _showAddressPicker(target:'custom', customType) -> _saveAddressFor -> applyResolved, which does `savedPlaces.indexWhere((place) => place.type == type)` and rewrites that first match. Home's Add place picker (home.dart:1359-1461) has the same effect: choosing a type that already exists replaces that place's address instead of adding one. Reproduced with a throwaway test: two gyms (ids a,b); applyResolved(custom, 'New street 9', 'gym') changed a to 'New street 9' and left b untouched (output: `after edit: [a:New street 9, b:Street B 2]`).

**Suggested fix:** Pass the SavedPlaceData id (or index) through onEditSavedPlace/_showAddressPicker/applyResolved and match on id; for Add place with an existing type, append a new entry (as Saved Places does) or ask.

### M13. Late first GPS fix glides whichever map is on top (pickup / Set pickup / Select ride), not Home's

`lib/features/home/presentation/home.dart:395`

**What happens:** Cold start on web/Safari, slow first fix. Rider taps Where to, picks a destination; _awaitCurrentFix times out at 8 s, SelectRide opens, rider taps Book, Set pickup opens with the fallback pin. At ~12 s the fix lands: Set pickup's camera glides to the GPS point at city zoom 11.7; onCameraMove recomputes _center, _onCameraIdle sets _routeStart/_usable=true, re-resolves the address and re-quotes. The pickup silently moved under the rider; in ConfirmPickupSpot the pin likewise jumps and the shown address changes.

**Why:** _runDetectCurrentAddress ends with `AppScope.instance.maps.animateCamera(target, zoom: homeOpeningZoom, follow: true)` with no check that Home's map is the active owner. While Home is parked (NAV-3 or _withParkedHomeMap) its controller is detached (home.dart:233) and GoogleMapProvider.controller returns `_owners.last.controller` (google_map_provider.dart:24-25), i.e. the map of ConfirmPickupSpot (owner 'pickup', confirm_pickup_spot.dart:333), SetPickupPage (set_pickup_page.dart:870) or SelectRide. _mayMove(map, follow:true) only checks heldByRider (google_map_provider.dart:79-85), so the booking screen's camera eases to the rider's GPS point at zoom 11.7. The sibling path _centerCameraOnQuickFix explicitly guards `if (maps.activeOwner != MapOwners.home) return;` (home.dart:312), showing this guard was intended. detectCurrent can take up to 16 s (detectFixTimeout) while _awaitCurrentFix gives up after 8 s and the flow continues with the fallback pickup, so the fix routinely lands after the rider is on a map screen.

**Suggested fix:** In _runDetectCurrentAddress skip the animateCamera when `_mapParked.value || AppScope.instance.maps.activeOwner != MapOwners.home` (onMapCreated already re-centres from _currentLatLng when Home's map comes back).

### M14. A failed forward geocode after the route picker closes, or when a saved place is tapped, aborts the flow silently with an unhandled async error

`lib/features/home/presentation/home.dart:953`

**What happens:** Rider is offline or the geocode endpoint times out. They pick pickup and destination in the route picker (onFinish succeeds because resolvePlace is cached or the point came with the suggestion), the picker closes, the forward geocode of the raw strings throws, the flow aborts: Home shows the old sheet, no error, no SelectRide, Recents not updated. Tapping a saved place (Home/Work card) while offline likewise does nothing.

**Why:** After RoutePickerPage pops with a draft, _showRouteAddressPicker runs `Future.wait([_normaliseAddress(rawPickup...), _normaliseAddress(rawDestination...), ...])`. HomeLocationController.normaliseAddress calls `geocoding.forward(clean)` with no try/catch (home_controller.dart:258); AppGeocoding._forwardFromApi does `api.post(...).timeout(requestTimeout)` and ApiClient._send throws ApiError on HTTP >= 400, NETWORK and TIMEOUT (api_client.dart:98, 123, 131). The exception propagates through _handleDestinationTap -> _runRouteFlow (finally only resets the flag) -> WhereToCard.onTap, which is a VoidCallback, so it becomes an unhandled zone error. Nothing is shown to the rider, nothing is persisted and SelectRide never opens. The picker itself catches onFinish failures (route_picker_page.dart:408-411) but this post-pop step does not. Same unguarded pattern: _useSavedPlaceAsDestination (home.dart:545), _saveAddressFor (home.dart:469, 477), PickupMapController.search used by ConfirmPickupSpot._lookup (confirm_pickup_spot.dart:286) and SetPickupPage._searchAddress (set_pickup_page.dart:702).

**Suggested fix:** Wrap the post-pop normalisation (and the saved-place / favourite / pickup-search paths) in try/catch; on failure fall back to the raw strings (the draft already carries pickupLat/Lng and destinationLat/Lng) or show homeChooseValidRoute / routeCouldNotReach, instead of letting the exception escape.

### M15. 'Use current location' row saves the placeholder 'Location off, set pickup' as Home/Work and into Recents

`lib/features/home/presentation/home.dart:1211`

**What happens:** Location services off. Rider long-presses the Home card, sees 'Use current location' with subtitle 'Location off, set pickup', taps it: Home address becomes 'Location off, set pickup', it shows on the Home card and in Recents, and tapping the Home card later feeds that text to the geocoder as a destination.

**Why:** When location is off/denied, _runDetectCurrentAddress and _resetPickupLabel set _pickupAddress = locationOffPickupLabel. _placeOrNull only filters '' and 'Current location' (home.dart:524-528), so in _showAddressPicker the 'Use current location' row is enabled and pops that placeholder string; _saveAddressFor normalises it and applyResolved stores it as homeAddress/workAddress and calls remember(address), whose own filter also only knows 'Current location' (home_places_controller.dart:86). Home's _rememberAddress guard (isPlaceholderPickupLabel, home.dart:449) is bypassed on this path. Reproduced: applyResolved(target:'home', address: locationOffPickupLabel) -> `home=Location off, set pickup recents=[Location off, set pickup]`.

**Suggested fix:** Use isPlaceholderPickupLabel (and isUnusablePickupLabel) in _placeOrNull / the row's enabled check, and have HomePlacesController.remember reject placeholder and raw-coordinate labels like Home._rememberAddress does.

### M16. Zone wall-clock pickup time is stored as a device-local DateTime and compared with DateTime.now()

`lib/features/reservations/application/reservation_controller.dart:334`

**What happens:** Web rider with browser in UTC (or a Stockholm phone in Tunis zone in summer) books a Stockholm pickup for 12:30 local (30 min ahead). Home chrono shows 2 h 30 m; `startLiveIfDue` reaches T-2 two hours after the real pickup; "No driver found" fires two hours late; free-cancel window shown/charged against the wrong instant.

**Why:** Q9 makes every Book-later time the pickup zone's wall-clock time: `ZoneClock.wallTime` returns a plain local `DateTime(local.year, …)` (zone_clock.dart:57-69) and `PickupSchedule` works in those (stockholm_schedule.dart:105-121). The picker returns that wall-clock value (select_date_time.dart:131, 153-158) and it flows unchanged into `ReservationDraft.scheduledPickupAt` (scheduled_ride_checkout.dart:21-32). The backend path converts it to a UTC instant (`PickupSchedule(timezone).toUtc(at)`, scheduled_rides_controller.dart:63-64), but the local reservation path never does: `startLiveIfDue` computes `ride.scheduledPickupAt.difference(currentTime)` with `currentTime = DateTime.now()` (334, 329), the chrono counts down with `DateTime.now()` (home_reservation_chrono.dart:206, 242-249; reservation_format.dart:99,117), `isNoDriverFound` (313-316) and the cancel-fee window (scheduled_ride_rules.dart:93-103) do the same. Whenever the device time zone differs from the pickup zone's (any browser outside CET on the public web build; a Stockholm phone booking a Tunis pickup in summer; a traveller abroad), every one of these is off by the offset. Throwaway test in this UTC container: minimumPickup() for 10:00Z gives wall-clock 12:30 (local, isUtc=false); `pickup.difference(now)` = 2:30:00 and the chrono label reads `2h 30m` for a ride 30 minutes away.

**Suggested fix:** Convert the picked wall-clock time to an instant (`PickupSchedule(timeZone).toUtc(when)`) before building the ReservationDraft, and render it back with `ZoneClock.wallTime` in the reservation screens; or store the IANA zone with the reservation and use it in every comparison.

### M17. Cancelling a reservation from its live screen skips the reservation late-cancel terms, so no fee is recorded

`lib/features/reservations/presentation/reservation_live_ride.dart:79`

**What happens:** Rules: free until 60 min before pickup, 50 kr after. Rider lets the driver start (T-2), the live screen opens, taps Cancel: the ride is cancelled with no fee recorded; History and the receipt show no fee, contradicting the terms the rider was shown.

**Why:** The Upcoming page computes the terms and passes the agreed fee: `cancelTermsFor(ride)` then `_reservations.cancel(id, reason:, fee: terms.fee)` (upcoming_reservation.dart:131-142). The two other cancel entry points for the same reservation never pass a fee: `ReservationLiveRide.onCancel` calls `reservations.cancel(ride.reservationId, reason: reasonId ?? 'rider_cancelled_live')` (78-85) and `ReservationRideRealtime.cancelRide` does the same (reservation_ride_realtime.dart:255-265). The live screen is exactly where the rider is once the driver is en route (T-2 min, `startLiveIfDue` 383-394 + chrono `_openLiveIfNeeded`), i.e. inside the late-cancel window the rules define (scheduled_ride_rules.dart:86-118, default 60 min / 50 kr). The cancelled ride is then saved with `cancellationFee == null`, History shows plain "Cancelled" (reservation_format.dart:27-33) and no fee is recorded, while the same cancel five minutes earlier from the Upcoming page records 50 kr.

**Suggested fix:** Compute `reservations.cancelTermsFor(ride)` in both live-screen cancel paths and pass `fee: terms.fee` (and show the terms note in the live cancel sheet).

### M18. A leftover suppressRestore from a ride closed earlier makes resumeIfNeeded delete a just-adopted server trip on a push tap, so the ride does not open

`lib/features/ride_booking/application/ride_restore_coordinator.dart:595`

**What happens:** Release build (ApiActiveTripRepository): rider finishes ride A on their phone (Done → closed). Later they book ride B on the web; the push for B taps on the phone. `_openRide` adopts B from the server, then `resumeIfNeeded` clears it and returns; the rider sees Home with no ride, and 'This ride has ended.' may be shown by `openNotificationRide`.

**Why:** `RideSession.suppressRestore` is set true by every terminal `localTransition`/`backendReconcile` (ride_session.dart 82, 148) and is only reset by a non-terminal transition or `reset()` (sign-out wipe). After the rider closes or cancels a ride on this device the flag stays true indefinitely. `openRideFromNotification` → `_openRide` (notification_navigation.dart 88-125) reads no snapshot, calls `adoptServerActiveTrip(expectedRideId)` which saves the server trip as the snapshot (ride_restore_coordinator.dart 78-100), then calls `resumeIfNeeded()`. `resumeIfNeeded` reads the new snapshot, resyncs, and then hits `if (AppScope.instance.ride.suppressRestore) { unawaited(RideSnapshotStore.clear()); return null; }` (595-598): the just-adopted trip is deleted and nothing opens, although the flag belongs to a different, finished ride. The cold-start path (`_root` → `pageFor`) has no such check, so the same trip is restored after a restart.

**Suggested fix:** Scope `suppressRestore` to the ride id it was set for (ignore it when the snapshot's rideId differs from `session.rideId`), or clear it in `adoptServerActiveTrip`.

### M19. A terminal status (e.g. paymentFailed) reconciled during the Waiting->RideCompleted handoff makes closeCompletedRide throw InvalidRideTransition, so Done and Back both fail with a misleading 'feedback could not be saved' and the rider cannot leave

`lib/features/ride_complete/presentation/ride_completed.dart:252`

**What happens:** Payment fails on the server right as Waiting hands over to the summary. The rider rates the driver and taps Done: the rating is sent, then 'Your feedback could not be saved' appears every time, and neither Done nor Back leaves the screen.

**Why:** `_leave` wraps feedback submission and `closeCompletedRide` in one try/catch; any throw from the latter sets `_submitError = context.l10n.feedbackSaveFailed` and `_leaving = false` (259-265), and both Done and Back route through `_leave`, so the rider can never leave. `closeCompletedRide` can throw after the feedback was accepted: `localTransition(RideStatus.closed)` (active_ride_controller.dart 459) throws `InvalidRideTransition` when the session is already terminal, which happens when a `paymentFailed` (or other terminal) projection is reconciled by the still-live `DriverTrackingController` during the Waiting→RideCompleted `pushReplacement` handoff (RideCompleted's own listener ignores non-completed statuses, 123-127, so the screen keeps showing 'Trip complete'); `archive` can also throw its `StateError` after six lost writes (on_demand_ride_history_store.dart 172-176). The message then blames the rating/tip, which was in fact sent (`_acceptedFeedbackIntent` is set).

**Suggested fix:** Separate the two failure classes: keep the error only for a refused feedback submission, and make leaving tolerant (catch `InvalidRideTransition`/archive errors, clear the snapshot and still navigate Home).

### M20. Wallet is offered as the full payment method even when the fare is above the balance, and completing the ride drives the local wallet ledger negative (demo/dev builds, where the local wallet is enabled)

`lib/features/ride_selection/application/ride_selection_controller.dart:267`

**What happens:** Rider has 50 kr in the wallet, picks a 259 kr ride, opens Pay with, taps the Movera Wallet row ('Balance: 50 kr'), books. Ride completes: wallet balance shows -209 kr, the wallet disappears from Pay with (balance not > 0), and the next 100 kr top-up shows -109 kr.

**Why:** The wallet row is listed whenever `walletBalance > 0` with no comparison against the fare (ride_selection_controller.dart:265-268), PayWithPage pops `'wallet'` on tap with no check (pay_with_page.dart:224-232), and `walletSplitFor` returns `WalletSplit.none` for the wallet method (200-202) so `walletAmountMinor` is 0 and the server-side range check in the mock (`walletMinor > serverTotal`) cannot catch it. At completion `RideCompleted._maybeChargeWallet` → `chargeCompletedRideById` → `chargeCompletedRide` charges `amount = snapshot.price` (wallet_controller.dart:282-283) and `LocalWalletRepository._apply` subtracts with no floor (wallet_repository.dart:215-218), so the stored balance becomes negative and WalletHome shows e.g. '-209 kr'. Reproduced: `brand=wallet walletMinor=0 remainderMinor=25900` and `balance after wallet-paid 259 kr ride from 50 kr: -209.0`.

**Suggested fix:** Offer the wallet as a full method only when `walletBalance >= fare` of the selected ride (or show it disabled with 'Balance too low'), and clamp `debitRide` to the available balance / refuse the charge with a logged error.

### M21. Saved 'wallet' default payment is silently replaced by Cash on every Select Ride open (load-order race)

`lib/features/ride_selection/application/ride_selection_controller.dart:576`

**What happens:** Rider with 500 kr in the wallet chooses Movera Wallet in Pay with (persisted as default). Next time they open Select Ride the footer shows Cash; if they do not notice, the ride is booked as Cash and the driver asks for cash.

**Why:** `SelectRide.initState` starts `_loadSavedCards(paymentName)` (line 353) and `_loadWalletBalance()` (line 361) concurrently. `_loadSavedCards` → `restoreDefaultPayment()` reads the saved brand and, because `payments()` only lists the wallet when `walletBalance > 0` (ride_selection_controller.dart:267) and the balance has not loaded yet, hits `if (saved == null || !list.any((item) => item.brand == saved)) { _selectDefaultPayment(); }` and selects Cash. `_loadWalletBalance` resolves later (`loadUseWalletFirst` → `WalletStore.loadPayments` performs four `prefs.remove` platform calls plus possible writes before returning) and calls `setWalletBalance`, which only re-selects the *current* brand (`if (current != null) selectPaymentByBrand(current);`, 598-602), i.e. Cash. The remembered wallet default (persisted by `selectPayment` → `_persistSelectedBrand` and by WalletScreen `_selectMethod('wallet')`) is therefore never restored, contradicting the R10 note in default_payment_store.dart ('the choice survives relaunch'). A return ride whose origin was paid with 'Movera Wallet' loses it the same way (`selectPaymentNamed` runs before the balance is known). Reproduced with a throwaway test driving the same sequence on the controller: `afterRestore=cash walletOffered=true afterBalance=cash savedDefault=wallet`.

**Suggested fix:** Remember the saved brand in the controller (e.g. `_pendingDefaultBrand`) when it is not yet offered, and re-apply it in `setWalletBalance`/`setZonePaymentMethods` once it appears; or have SelectRide await the wallet balance before `restoreDefaultPayment`.

### M22. Ride category notes and badges ('Affordable and convenient rides', 'RECOMMENDED', 'FASTER') from the built-in and mock catalogs are shown in English to fr/sv riders

`lib/features/ride_selection/data/ride_selection_repository.dart:14`

**What happens:** Swedish rider opens Välj din resa: each category row shows 'Affordable and convenient rides', 'Newer cars with extra legroom' and the badges 'RECOMMENDED'/'FASTER' in English.

**Why:** RideCatalogItem.note/badge are rendered raw on Select ride (select_ride.dart:2355 `ride.note,` and :2376 `ride.badge!,`). The built-in list (the initial `_current` of RideCatalogController and the offline/cold-start fallback, ride_catalog_controller.dart:27, :89) and the in-process mock catalog (in_process_mock_client.dart:176-204) both carry English-only notes/badges; unlike payment rows (payment_labels.dart maps the English detail strings to ARB keys) there is no mapping for catalog text and no ARB keys for them. The API client also sends no Accept-Language/language header (api_client.dart:80-82 only Accept/Content-Type), so a real server has no way to localize them either. In the public demo build (mock client) every fr/sv rider therefore sees English descriptions and badges on the main booking screen.

**Suggested fix:** Map built-in/mock notes and badges by category id to ARB keys at display time (as payment_labels.dart does), and send Accept-Language with L10n.code so the server can localize catalog text.

### M23. After a confirmed pickup-pin move, other categories (and the selected one when its pin re-quote failed) are booked with quotes priced at the original pickup

`lib/features/ride_selection/presentation/select_ride.dart:1487`

**What happens:** Rider picks Economy, taps Book, drags the pin 1.5 km in Set pickup, confirms, gets 'Price updated 310 kr (was 259 kr)', taps Not now. List now shows Comfort at the price quoted for the original pickup. Rider taps Comfort → Book → Set pickup opens at the new pin showing the old-pickup price → Confirm and search → ride is created at the new coordinates with the old-pickup quote and price; Finding/Waiting then show that price.

**Why:** Set pickup only re-quotes the selected category, and only when the pin moves (set_pickup_page.dart:493-507 `if (_isAwayFrom(_center, _routeStart)) { ... unawaited(_requote()); }`). When the rider confirms a moved pin, `_bookNow` stores the new position (`_pickupAddress = spot.address; _pickupPosition = spot.position; _pickupConfirmed = true;`, 1487-1489) but never reloads the list quotes. If the rider then declines the 'Price updated' dialog (1515-1520 returns after `setState`), or returns from Finding Drivers, every other category still holds `authoritativeQuotes` priced from the old pickup, and the tiles show those prices. Tapping Book on such a category passes `_book`'s `quoteIsAvailable` check (the quote is fresh for up to 2 min), opens Set pickup at the NEW position showing `fare: SetPickupFare(totalKr: _priceFor(ride) ...)` (1307-1309, the old-pickup quote), and because the pin does not move nothing re-quotes; `_quoteAfterPickup` returns `_bookableQuote(ride.id)` as long as it is not expired (559-560), so `submitFinding` sends `pickupLat/Lng` of the new point with `quoteId`/`quoteSignedPayload` of the old point. The same happens for the selected category itself when its pin re-quote timed out: `_requoteNow` keeps the old fare (set_pickup_page.dart:534-541), `shown == quote.totalMinor` so no dialog, and the old-point quote is booked. The in-process mock's `_validateQuoteBinding` (in_process_mock_client.dart:2188-2230) checks id, signature, expiry, total and category but not the pickup, so the booking is accepted at the wrong price. `_bookScheduled` has the same shape: it never awaits `_pinQuote`, so a pin re-quote still in flight when Set pickup pops (it waits at most 3 s) leaves `ScheduledRideCheckout.draftFrom` → `quotedPrice` on the old-point quote.

**Suggested fix:** After a confirmed pin move (and on 'Not now'), call `_loadQuotes()` so every category is re-priced from `_pickupPosition`; in `_quoteAfterPickup`, treat a quote whose pickup point differs from the confirmed one (or a failed pin re-quote) as unavailable and re-quote before booking; have `_bookScheduled` await `_pinQuote` the way `_bookNow` does.

### M24. Trip-share contact checkbox (trip_share_page.dart:167-188): a failed save gets no rider feedback, editContact's error escapes unhandled, and a partial failure leaves the preference list and shareTrips inconsistent

`lib/features/safety/presentation/trip_share_page.dart:612`

**What happens:** Offline rider unchecks a contact under "Trusted contacts": `setTripShare` fails silently (or succeeds), `editContact` throws unhandled; the checkbox snaps back to checked (or shows checked while the preference list no longer has the id) and the rider gets no error.

**Why:** The checkbox value is `prefs.tripShareContactIds.contains(id) || contact.shareTrips` (581-585). Its `onChanged` first calls `_ctl.setTripShare(contactIds: selected)` (612-614) and then `_ctl.editContact(contact.copyWith(shareTrips: value == true))` (615-619). `setTripShare` swallows failures into `controller.error` (safety_controller.dart:277-295) and this page never shows `error`; `editContact` has no generic catch, so a transport failure in `SafetyStore._write` (safety_store.dart:92-101 rethrows after restoring the cache) escapes the async callback as an unhandled exception. Because the two writes are independent, one can succeed while the other fails: unchecking a contact may remove the id from `tripShareContactIds` while `shareTrips` stays true, and the `||` keeps the box checked with no message.

**Suggested fix:** Wrap the handler in try/catch, show `controller.error`/a toast on failure, and keep a single source of truth (either the preference list or `shareTrips`) so the box reflects one flag.

### M25. Book-for-later pickup field is pre-filled with the English string 'Current location'

`lib/features/scheduled_rides/presentation/schedule_ride.dart:58`

**What happens:** Swedish rider opens 'Boka senare': the 'Upphämtning' field shows 'Current location' instead of 'Nuvarande plats'.

**Why:** The pickup TextEditingController is created with `text: 'Current location'` (:57-58) and that controller is bound directly to the visible address field `_scheduleAddressField(controller: _pickupController, ...)` (:350-351). There is no L10n.place on the controller text, so the first thing the rider sees in the pickup box is English in fr/sv. The same literal is passed as the initial address of ConfirmPickupSpot at :184 (`? 'Current location'`), which then shows it raw (see the ConfirmPickupSpot finding). The screen is covered by test/l10n/l10n_screens_finish_test.dart ('Schedule a ride'), but that test only asserts one translated string is present and cannot notice the English default.

**Suggested fix:** Initialise the controller with L10n.current.currentLocation (and treat that translated value, or an empty value, as the 'current location' sentinel in resolveScheduledPoint), or keep the field empty and show the translated hint.

### M26. Continue button stays disabled as 'Continuing…' after the category step returns or fails (needs Back to the address step to recover)

`lib/features/scheduled_rides/presentation/select_date_time.dart:126`

**What happens:** Rider on Plan your ride -> Continue -> category cards -> taps back to change the time. The time screen now shows a greyed "Continuing…" button that never re-enables; the only way out is Back to the address step and re-confirming the pickup pin.

**Why:** `_goNext` sets `_continuing = true` (line 126) before calling `widget.onConfirm()` and nothing ever resets it. In `ScheduleRide` the selector is embedded (schedule_ride.dart:257-267) with `onConfirm: goToNextStep`, which pushes the category selector and, when the rider comes back without booking, just does `setState` (schedule_ride.dart:148-151). The rebuilt `ScheduleDateTimeSelector` is the same widget type at the same tree position, so its State (and `_continuing == true`) is kept. The button is built with `enabled = legal && !_continuing` (757) and label `_continuing ? continuing : continueLabel` (809). Reproduced with a throwaway widget test: after one tap and `onConfirm` returning, `ElevatedButton.enabled == false`, label `Continuing…`, and a second tap does not call onConfirm again (`AUDIT continue enabled after return: false; label: Continuing…` / `AUDIT confirms after second tap: 1`).

**Suggested fix:** Make `onConfirm` a `Future<void>` and reset `_continuing = false` (with setState) when it completes, or reset it in `didUpdateWidget`/when the route becomes current again.

### M27. 'Open settings' in the push primer calls Geolocator.openAppSettings, which throws UnsupportedError on web

`lib/shared/widgets/push_permission_primer.dart:86`

**What happens:** Staging web build, rider taps 'Turn on' and declines the browser notification prompt. Next visit to Notifications shows 'Ride updates are off' -> 'Open settings'; tapping does nothing visible and logs `zone.error UnsupportedError: openAppSettings() has not been implemented on the web`.

**Why:** `_openSettings` defaults to `Geolocator.openAppSettings`. geolocator_web implements it as `throw _unsupported('openAppSettings')`. The primer is reachable on web in release-like builds (gate `enabled = !allowsMockTransport`): when the browser's `Notification.requestPermission()` answers 'denied' (or 'default'), `FlutterFirebasePushGateway.requestPermission` maps it to `PushAuthorizationStatus.denied`, `PushPermissionGate._register` stores `blockedBySystem`, and both the sheet (`_blocked`) and the Notifications screen banner then offer 'Open settings'. Tapping it throws inside the button callback; nothing opens, the rider gets no feedback, and the error is recorded as a crash by the zone handler. The location notice already handles this case correctly via `locationSettingsOpenerFor(isWeb: ...)` returning null, so the web branch was simply missed here.

**Suggested fix:** On web hide the settings action (or show copy explaining the browser's site-permission UI) the way `locationSettingsOpenerFor` does; wrap the call in try/catch and show a toast on failure.

## Low (47)

### L1. Documented live URL points at /-movera-rider/, the Pages build is published under /movera-rider-app/

`ARCHITECTURE.md:90`

**What happens:** A reviewer or QA engineer opens the URL in ARCHITECTURE.md to verify the live build and gets a GitHub 404 instead of the deployed rider app.

**Why:** ARCHITECTURE.md line 90 gives the live site as `https://baccarisverige-ux.github.io/-movera-rider/`. The publish workflow rewrites the base href to `/movera-rider-app/` (publish-web-live.yml:124) and the repository/Pages project is movera-rider-app, so the documented URL 404s. Per the ground rules, docs and code disagreeing is a defect.

**Suggested fix:** Change the ARCHITECTURE.md URL to `https://baccarisverige-ux.github.io/movera-rider-app/`.

### L2. QA_HOOKS.md (and its rule not to leave hooks ungated) is stale: moveraOpenSafety is deliberately exposed in public release builds as a navigation-only bridge

`lib/app/bootstrap.dart:76`

**What happens:** An operator reading QA_HOOKS.md assumes `window.moveraOpenSafety` is absent on the public demo; on https://.../movera-rider-app/ `typeof window.moveraOpenSafety` is 'function' and calling it opens the Safety hub.

**Why:** docs/QA_HOOKS.md lists `moveraOpenSafety` among the hooks that public GitHub Pages release builds do NOT expose, and ARCHITECTURE.md states 'QA window.movera* hooks are gated (kDebugMode or --dart-define=MOVERA_QA=true)'. bootstrap.dart calls `installSafetyNavigationBridge(...)` outside the `moveraQaHooksEnabled` gate and `web_qa_hooks_web.dart` installs `window.moveraOpenSafety` with a comment that it is 'intentionally available in public web builds'; qa-live-rider-flow.yml even asserts it exists on public Pages. The code and the public workflow contradict the documented contract; one of them is wrong. The bridge can push the Safety hub over any screen from page script, so the doc readers' assumption that no navigation hook exists in release is false.

**Suggested fix:** Either gate `installSafetyNavigationBridge` behind `moveraQaHooksEnabled` (and drop the public-Pages step from qa-live-rider-flow.yml) or correct QA_HOOKS.md/ARCHITECTURE.md to list `moveraOpenSafety` as a release-available navigation bridge.

### L3. Web auth-preview: a wrong OTP while an earlier session's tokens are still in sessionStorage expires the session and re-roots Sign in instead of showing 'wrong code'

`lib/core/api/api_client.dart:89`

**What happens:** Web demo with `?auth_preview=1`: rider who signed in earlier in the tab types one wrong OTP digit; instead of 'wrong code' the screen jumps back to the first Sign in step, the stored session is gone and the last good location fix is wiped.

**Why:** `_send` enters the refresh/retry/expire path for any 401 whose request carried an access token (line 89); the comment relies on OTP verify never carrying one. `RideRestoreCoordinator` returns `SignIn()` when `AppEnv.current.authPreview && snapshot == null` (ride_restore_coordinator.dart lines 432-434, 449-452) without clearing tokens, and on web the tokens live in this tab's sessionStorage, so a reload with `?auth_preview=1` after an earlier sign-in reaches `PhoneVerify` with tokens present. A wrong code -> mock `401 invalid_otp` -> `_refreshAccess` (mock accepts any `mock-refresh-*`) -> retry -> 401 again -> `_expireSession` clears tokens, calls `onSessionExpired` (`LocationRepository.clearLastGoodFix()` + `showMoveraRoot(SignIn())`), then throws; `PhoneVerify` is unmounted so its `_error` is never shown.

**Suggested fix:** Exclude `/api/v1/auth/*` paths from the refresh/expire path (or let callers opt out), or clear tokens before showing the preview Sign in.

### L4. `PATCH /rides/{id}` offer raise / searching edit changes the fare, pickup and destination without `_touch`, so version, updatedAt, sequence and eventId stay unchanged

`lib/core/api/in_process_mock_client.dart:993`

**What happens:** Demo flavor: rider raises the offer by 50 kr while searching; the projection's `version`, `updatedAt` and `eventId` do not move. A command sent from another tab/screen with the pre-raise `expectedVersion` is not refused as stale, and a polling consumer never sees a new event for the change.

**Why:** The non-routeChange PATCH branch (lines 947-1011) calls `_setFare(ride, fare + increase)` and rewrites `pickupAddress/pickupLat/pickupLng/destination*` but never calls `_touch(ride)`, unlike every other mutation (route change line 895, cancel via `_apply`, feedback line 646). The mock's own rule (lines 1351-1361) is 'one committed change: version + 1, new updatedAt, next sequence/eventId' and CONTRACT.md §1 requires a stale `expectedVersion` to be refused. After a raise the trip still reports the old `version`/`updatedAt`/`eventId`, so a second screen's `expectedVersion` from before the raise is accepted, `ApiRideRealtime` dedupes the projection by the unchanged eventId, and `updatedAt` misreports when the trip last changed. Reproduced: `AUDIT B2: fare 29100 -> 34100; version 1 -> 1; eventId ev_..._1 -> ev_..._1; updatedAt unchanged`.

**Suggested fix:** Call `_touch(ride)` after applying the offer raise / pickup / destination edit in that branch.

### L5. PickupSchedule.zoneNow builds the zone wall-clock as a device-local DateTime: for a Tunis pickup on an EU-DST phone, during 02:00-02:59 Tunis on the EU spring-forward day, the earliest legal pickup is pushed an hour late

`lib/core/config/zone_clock.dart:60`

**What happens:** Rider with a Swedish phone books a reservation in the Tunis zone for 2026-03-29 02:30 Tunis time (instant 01:30Z): `wallTime('Africa/Tunis', instant)` -> `DateTime(2026,3,29,2,30)` in Europe/Stockholm does not exist -> shows 03:30. The reverse mapping of the shown value then lands on a different instant than the one stored.

**Why:** `wallTime` computes the correct zone wall-clock components and then constructs `DateTime(year, month, day, hour, ...)` with the local-time constructor. Dart resolves a non-existent local time (the device's spring-forward gap) by shifting it, so when the device time zone differs from the zone's (RiderZones has Europe/Stockholm, Europe/Paris, Africa/Tunis; Tunis has no DST) the picker shows the wrong hour. `toUtc` (lines 74-86) uses `DateTime.utc`, so the round trip is asymmetric. Also the doc comment on `toUtc` says the summer offset is used in the non-existent hour, but the two-step guess yields the winter offset: wall 02:30 Stockholm on 2026-03-29 -> asUtc 02:30Z -> offsetAt = +2 -> guess 00:30Z -> offsetAt(00:30Z) = +1 -> 01:30Z (= 03:30 wall), not 00:30Z.

**Suggested fix:** Return `DateTime.utc(local.year, ..., local.millisecond)` (a UTC-flagged carrier of wall components, which never shifts) and have the pickers treat it as offset-free; fix the toUtc doc comment or the algorithm to match.

### L6. docs/QA_HOOKS.md still lists moveraOpenSafety as absent from release builds, but code and CI intentionally expose a navigation-only bridge

`lib/core/debug/web_qa_hooks_web.dart:67`

**What happens:** On the public GitHub Pages build any page script (or the Maps JS SDK) can call `window.moveraOpenSafety()` and navigate the rider to the Safety hub; QA_HOOKS.md promises this surface is absent.

**Why:** docs/QA_HOOKS.md:3-11 states public release builds do not expose `moveraOpenSafety` and that hooks install only under kDebugMode or MOVERA_QA. `installSafetyNavigationBridge` sets exactly that global without any gate, and bootstrap calls it unconditionally (lib/app/bootstrap.dart:76-78) outside the `if (moveraQaHooksEnabled)` block (lines 82-85). The gated `installSafetyQaOpener` (line 52) writes the same property name, so in QA builds whichever runs last wins. The code comment says this is intentional, so either the record or the code is wrong; per the audit rules a place where code does not do what the decision document says is reportable.

**Suggested fix:** Either gate the bridge with moveraQaHooksEnabled (and use the gated installSafetyQaOpener only), or correct docs/QA_HOOKS.md / ARCHITECTURE.md to state that moveraOpenSafety is a public navigation-only hook.

### L7. MotionEngine lerp window is anchored at the previous fix's timestamp, so with fixes 420 ms or more apart t clamps to 1 and the home puck snaps between raw smoothed fixes (pose heading is unused)

`lib/core/motion/motion_engine.dart:47`

**What happens:** On the home map the blue rider dot and heading cone jump between 1 Hz fixes rather than easing across the 420 ms window.

**Why:** ingest() is called once per delivered fix (HomeController._deliverFix, lib/features/home/application/home_controller.dart:518) and passes `startedAt: _from!.timestamp` with a 420 ms window. `_from` is the previous accepted sample, whose timestamp is at least one fix interval (typically >= 1 s) old, so `now - startedAt` always exceeds 420 ms and the interpolator clamps to t=1, returning `_to` verbatim. There is no ticker that calls lerp between fixes, so the 'interpolation' is a no-op and the rider marker snaps to each raw smoothed point; heading likewise jumps. Not a crash, but the animation math does not do what the component is for.

**Suggested fix:** Record `startedAt = clock` when a new sample arrives and expose a `poseAt(now)` used by a frame ticker; or drop the interpolator if snapping is intended.

### L8. History record time is overwritten with the Done-tap time; receipt date uses savedAt which lifecycle refreshes move

`lib/features/active_ride/application/active_ride_controller.dart:454`

**What happens:** Trip completes at 14:00; the rider leaves the app on the summary, backgrounds it a few times and taps Done at 14:40. Ride History lists the trip at 14:40, and after a reload the receipt's 'Date and time' shows the last time the app was backgrounded.

**Why:** `markCompleted` archives the trip with `endedAt` defaulting to now (completion time) (377-382, on_demand_ride_history_store.dart 197 `final ended = endedAt ?? DateTime.now();`). When the rider taps Done, `closeCompletedRide` archives again with the same `reservationId` and no `endedAt` (453-457), so `archive` replaces the record (146-148) and its `scheduledPickupAt` becomes the time the rider left the summary, which can be much later. Separately, the receipt's 'Date and time' comes from `DriverRepository._completedAtLabel(ride.savedAt)` (driver_repository.dart 59), and `savedAt` is rewritten by `persistCompletedStatus` (395-400) on each payment/rating event and by `RideSnapshotStore.touchCurrent` on every background/pagehide (ride_snapshot_store.dart 452) because completed-surface statuses are not terminal; after a restore `LastCompletedRide.remember(snapshot)` (ride_restore_coordinator.dart 383) therefore shows the last backgrounding time, not the completion time.

**Suggested fix:** Record a completion timestamp in the snapshot when `markCompleted` runs and pass it as `endedAt` on every later archive and to the receipt.

### L9. Sign-in hero tagline 'Moving to a new era.' is English although brandTagline is translated in the ARB

`lib/features/auth/presentation/widgets/balloon_brand_intro.dart:95`

**What happens:** App started in the France zone: Sign in shows 'Moving to a new era.' while Rider name shows 'Movera · Vers une nouvelle ère'.

**Why:** The sign-in hero (sign_in.dart:164 `hero: BalloonBrandIntro(progress: _story)`) draws `Text('Moving to a new era.', ...)` (:95) and a Semantics label 'Movera. Moving to a new era.' (:26). The ARB defines brandTagline with French/Swedish translations (' · Vers une nouvelle ère', ' · På väg mot en ny era') and rider_name.dart:140 uses it, so the same slogan appears translated on the next screen but English on Sign in when the zone default is fr/sv.

**Suggested fix:** Render the translated tagline (strip the leading ' · ' or add a dedicated key) in the intro and its Semantics label.

### L10. ARCHITECTURE.md and the cancelSearch doc comment still describe the old offline cancel (commit locally); the code implements RC-03 (queued, not committed), so the docs are out of date

`lib/features/finding_driver/application/finding_driver_controller.dart:1090`

**What happens:** An operator or tester reading ARCHITECTURE.md expects an offline cancel to land on Home with the ride archived; the app instead stays on the search screen with 'Cancelling…' until the server answers.

**Why:** ARCHITECTURE.md lines 13-17 state that on Finding, Cancel request commits the ride as `cancelledByRider`, archives it and clears the snapshot 'on its OK — or when it cannot be reached, leaving the outbox entry to retry'. The method doc of `cancelSearch` repeats it (1089-1091: 'unreachable: the same local commit, with the outbox entry kept'). The implementation does the opposite: `if (result == SearchCancelResult.queued) { _cancelInFlight = false; _cancelQueued = true; ... return result; }` (1123-1137) commits nothing, keeps the search listening and shows 'Cancelling…'. The `SearchCancelResult.queued` enum comment (45-50) and the restore coordinator (111-117) describe this newer RC-03 behaviour, so the two records contradict each other and the architecture document no longer describes what the product does.

**Suggested fix:** Update ARCHITECTURE.md and the `cancelSearch` doc comment to the RC-03 behaviour (or restore the documented behaviour, whichever is the decision).

### L11. `_refreshRoadRoute` has no request generation, so an older road-route answer can overwrite the route drawn for a changed destination

`lib/features/finding_driver/presentation/finding_drivers.dart:506`

**What happens:** Rider changes the destination from the Finding screen (or the server's route-change event arrives) right after the screen opened. The new destination marker appears, then the road line for the OLD destination is drawn on the map and stays until another route change or ride stage.

**Why:** `_adoptRoute` (line 395-406) and `_applyRouteChange` (line 700-711) update `_pickupPosition`/`_destinationPosition`, clear `_roadRoutePoints`, redraw, and then call `unawaited(_refreshRoadRoute())`. `_refreshRoadRoute` awaits `roadRoutePolyline(from: _pickupPosition, to: _destinationPosition)` (a network call via `RoutingService.roadLine`) and on return only checks `mounted` and `route.points.length < 2` before assigning `_roadRoutePoints = route.points` and redrawing. There is no check that the answer is for the route currently adopted. When a route change happens while the previous road request is still in flight (or a slow first request is beaten by the second), the older polyline lands last and is drawn between the new pickup/destination markers.

**Suggested fix:** Capture `from`/`to` (or a `++_routeGeneration`) before the await and discard the result when `_pickupPosition`/`_destinationPosition` changed (or the generation moved on) in the meantime.

### L12. History detail shows 'Movera Wallet' / 'Card' untranslated; only Cash is localized

`lib/features/history/presentation/ride_history.dart:552`

**What happens:** Swedish UI, wallet-paid ride: History detail shows 'Betalsätt: Movera Wallet'; the reservation page for a scheduled wallet ride shows 'Movera Plånbok'.

**Why:** The ride detail sheet prints `L10n.isCashLabel(ride.paymentMethod) ? context.l10n.payCash : ride.paymentMethod`. Rides booked with the wallet or the generic card row store the English names 'Movera Wallet' / 'Card' (`payment.name` in `_bookNow`), so in Swedish/French the line reads 'Betalsätt: Movera Wallet' while the Upcoming/Scheduled screens use `paymentLabelFor` (payment_labels.dart:24-29) and show 'Movera Plånbok' / 'Portefeuille Movera' for the same ride.

**Suggested fix:** Use `paymentLabelFor(ride.paymentMethod)` in the History detail sheet.

### L13. normaliseAddress forward-geocodes placeholder pickup labels, contrary to its own contract

`lib/features/home/application/home_controller.dart:256`

**What happens:** Staging build with a real geocoder. Rider chooses the pickup on the map; reverse geocode yields no street so the label is 'Pickup location'. After the picker pops, forward('Pickup location') returns e.g. a business called 'Pickup Location AB' in another city; SelectRide and the booking carry that label with the pin's coordinates.

**Why:** isPlaceholderPickupLabel's doc says a placeholder 'must not be forward-geocoded or saved' (home_controller.dart:62-69), but normaliseAddress only short-circuits '' and 'Current location'. _showRouteAddressPicker normalises draft['pickup'] unconditionally (home.dart:954), and that value is locationOffPickupLabel when _prefillPickup fell back (home.dart:818-822) or pickupLocationFallbackLabel ('Pickup location') / a 'Dropped pin …' label when the pin was placed on the map (confirmedPickupAddress, pickup_address.dart:46-49). Reproduced with a recording geocoder: forward() was called with 'Location off, set pickup' and 'Pickup location'. With the in-process mock the text comes back unchanged (in_process_mock_client.dart returns `'address': normalized`), but any real geocoder that fuzzy-matches returns some place name, which then becomes the pickup label shown in SelectRide and sent with the booking while pickupLat/Lng stay at the pin or the Stockholm default.

**Suggested fix:** Return early in normaliseAddress when isPlaceholderPickupLabel(clean) || needsDroppedPinLabel(clean), and skip normalising the pickup when the draft already carries pickupLat/Lng.

### L14. Custom place added from Home gets the raw type key as its title ('gym', 'restaurant', 'other') shown verbatim in every locale

`lib/features/home/application/home_places_controller.dart:145`

**What happens:** Swedish rider taps Add > Restaurang on Home and saves an address; the Home card and Menu > Sparade platser list the place as 'restaurant'.

**Why:** applyResolved creates `SavedPlaceData(title: type, type: type, address: address)` and persist() stores 'title': 'gym'. _CustomPlaceCard renders `place.title` (saved_places_row.dart:239-240) and the Saved Places screen renders the stored title (saved_places_controller.dart:177-180 uses the title whenever non-empty), so the card reads 'restaurant' / 'other' in lowercase English even in the Swedish/French UI, while RoutePickerPage shows the localized placeLabelFor(place.type) for the same place. Reproduced: applyResolved(custom, customType:'restaurant') -> title 'restaurant'.

**Suggested fix:** Store the localized label (placeLabelFor(type)) or leave title empty and let the UI derive it from type.

### L15. Location permission is requested again immediately after the rider denies it, and again on every app resume

`lib/features/home/presentation/home.dart:343`

**What happens:** Android rider taps Where to with location not yet granted, denies the prompt; within the same tap the prompt appears a second time (attempt 2). Later, every time they switch apps and come back, the prompt is shown again.

**Why:** _awaitCurrentFix loops two attempts; if the first detectCurrent returns quickly with permissionDenied (target == null), the second attempt starts a fresh detectCurrent, which calls location.requestPermission() again (home_controller.dart:369-371) — a second system prompt right after the first 'Deny'. didChangeAppLifecycleState(resumed) also calls _detectCurrentAddress() whenever _currentLatLng == null (home.dart:266-267), so an Android rider who denied once gets the prompt on each return to the app until Android auto-blocks it. iOS/web report deniedForever after one refusal, so only Android (and 'denied' on older Android indefinitely) is affected.

**Suggested fix:** Stop retrying when the first attempt ended in a permission failure (track the last DetectedLocation.failure), and on resume only re-detect when the last state was not permissionRequired.

### L16. Recenter button is hidden after a recenter that was interrupted or blocked, leaving the map off the rider with no way back

`lib/features/home/presentation/home.dart:1668`

**What happens:** Rider taps recenter; while latestFix() runs (up to 9 s) they pan the map elsewhere (button correctly shows). latestFix returns a point >15 m away, the follow glide is refused because the map is held, then _showRecenterButton = false: the map stays where they panned and the recenter button is gone until they move the map again.

**Why:** _recenterOnUser unconditionally ends with `setState(() => _showRecenterButton = false)`. The flight future completes early when a finger touches the map (MapView.touching -> interrupt() completes _done, map_camera_motion.dart:76-94), and the refinement glide `_flyToUser(fresh, follow: true)` is a no-op when heldByRider (google_map_provider.dart:81, 102). In both cases the camera is not on the rider, any 'show' decision made by _handleMapCameraMove during the rider's pan is overwritten with false, and the button only returns after the next camera move event.

**Suggested fix:** Only clear _showRecenterButton when the glide actually landed (e.g. re-evaluate with AppScope.instance.camera.showRecenter against the last camera pose), or leave it to _handleMapCameraMove.

### L17. Chat message times use the Material 12/24-hour locale default instead of the app's 24-hour rule

`lib/features/messages/presentation/chat.dart:196`

**What happens:** Rider with app language EN opens the driver chat: bubbles show '3:05 PM' while the ride sheet shows 'Pickup 15:05'.

**Why:** _messageTime formats with `TimeOfDay.fromDateTime(sentAt.toLocal()).format(context)`, which follows MaterialLocalizations.timeOfDayFormat: for the 'en' locale that is 'h:mm a' (12-hour, '3:05 PM') unless MediaQuery.alwaysUse24HourFormat is set. Every other time in the app is forced to 24-hour ('08:05') by L10n.formatTime (l10n.dart:111-114, 'as Movera shows it in every language') and ReservationFormat.time, so a rider using English in Sweden sees '3:05 PM' on chat bubbles but '15:05' on the Waiting sheet and notifications for the same moment.

**Suggested fix:** Use L10n.formatTime(sentAt.toLocal()) in chat.dart.

### L18. Hard-coded English UI strings in localized screens (notification toast, account security errors)

`lib/features/notifications/application/notification_navigation.dart:154`

**What happens:** App language Svenska; rider taps an old ride notification: toast reads "This ride has ended." in English. Security page fails to load: "Account security is unavailable right now." in English.

**Why:** The app ships en/fr/sv (`L10n.languages`) and every other user-facing string on these screens goes through `context.l10n`. These do not: `MoveraToast.show(context, 'This ride has ended.')` shown when a notification row's ride can no longer be opened (154); `errorMessage = 'Account security is unavailable right now.'` and `'Could not update active sessions.'` (account_security_controller.dart:240, 265) which `SecurityPage` renders directly (security.dart:924, 1090). A Swedish or French rider sees English here.

**Suggested fix:** Add ARB keys and use `L10n.current`/`context.l10n` for these three strings.

### L19. A push sent the day before is labelled with no day (as today) when it is ingested on the day after spring-forward, because Duration.inDays between local midnights is 0 (23h)

`lib/features/notifications/data/notifications_repository.dart:95`

**What happens:** Sunday 29 Mar 2026 (Europe/Stockholm) at 23:10 a 'Driver arrived' push arrives. On Monday 30 Mar the Notifications list shows it as '23:10' (today) instead of 'Yesterday 23:10'; a push from Saturday 28 Mar shows as 'Yesterday'.

**Why:** _formatTime computes `today.difference(day).inDays` where both are local midnights built with DateTime(y,m,d). On the day after a spring-forward transition the two midnights are 23 hours apart (verified by throwaway test under TZ=Europe/Stockholm: DateTime(2026,3,30).difference(DateTime(2026,3,29)) == 23:00:00), so inDays == 0 and the function returns only the clock, dropping the 'Yesterday' prefix the FLOW-18 comment promises. More generally, any day count across a DST change is one short (a notification from 3 days ago reads as 2 days -> still fine, but 2 days ago reads as 1 -> 'Yesterday').

**Suggested fix:** Compare calendar days with UTC-constructed midnights: `DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(time.year, time.month, time.day)).inDays`.

### L20. Notification time label is frozen at ingest, so items never become "Yesterday …"

`lib/features/notifications/data/notifications_repository.dart:213`

**What happens:** Push at 23:50 shows "23:50"; the next morning the same row still says "23:50" instead of "Yesterday 23:50".

**Why:** FLOW-18 says only today's items show just the time and older ones name the day. `_formatTime(at)` is evaluated once when the item is ingested (206-213) and stored in `AppNotification.time`; `_formatTime` compares against `_now()` at that moment (248-261). The screen renders `notification.time` (notifications.dart:630) and never recomputes from `at`. The feed is in-memory for the process, so any app/tab left open across midnight shows yesterday's pushes with a bare clock.

**Suggested fix:** Format from `notification.at` at build time (or recompute labels on emit).

### L21. Card brand error 'We accept Visa and Mastercard' is shown untranslated under the card number

`lib/features/payments/application/saved_cards_controller.dart:67`

**What happens:** French rider types a card number starting with 3 (Amex) on Ajouter une carte: the inline error reads 'We accept Visa and Mastercard'.

**Why:** CardInput.brandError is an English const. add_card_page.dart `_numberError` returns it directly: `if (CardInput.brandRejected(digits)) return CardInput.brandError;` (:125), and the same text is thrown as ArgumentError(CardInput.brandError) (:153) which add_card_page.dart:170 displays via `e.message`. All sibling errors on that page use context.l10n (cardCheckNumber, cardUseMmYy, cardExpired, cardCvc3), so this one field error stays English in fr/sv.

**Suggested fix:** Add an ARB key (cardBrandsAccepted) and return context.l10n.cardBrandsAccepted from _numberError; keep the controller's ArgumentError for programmer errors only.

### L22. Card brand rejection error is a hardcoded English string in a localized form

`lib/features/payments/presentation/add_card_page.dart:125`

**What happens:** App language Swedish; rider types '3782 8224 6310 005' in Add card → red line 'We accept Visa and Mastercard' among Swedish labels.

**Why:** `_numberError` returns `CardInput.brandError` ('We accept Visa and Mastercard', saved_cards_controller.dart:67) while every sibling error on the same field uses `context.l10n.*` (`cardCheckNumber`, `cardUseMmYy`, `cardExpired`, `cardCvc3`). There is no ARB key for this text (no match in app_en/sv/fr.arb), so a Swedish or French rider typing an Amex/Diners number sees an English error under the number field.

**Suggested fix:** Add an ARB key (e.g. `cardBrandUnsupported`) and return `context.l10n.cardBrandUnsupported` from `_numberError`.

### L23. Fallback 'Dropped pin · lat° N lng° E' pickup label is hard-coded English and is saved as the booking address

`lib/features/pickup/application/pickup_address.dart:35`

**What happens:** French rider drags the pin to a spot without a street address and confirms: pickup card, Finding screen, Waiting sheet and History all read 'Dropped pin · 59.32930° N 18.06860° E'.

**Why:** droppedPinPickupAddress builds an English sentence ('Dropped pin · …° N …° E') with no ARB key. SetPickupPage assigns it to `_address` when reverse geocoding yields nothing (:565) and it is shown in the pickup card `Text(_address, ...)` (:1137), then on confirm (:754-756) it is returned as `SetPickupResult.address`, persisted via `_spotsController.remember` and used as the ride's pickup label, so it stays English on Finding/Waiting/History and is sent to the driver. Reproduced under L10n.use('fr'): 'Dropped pin · 59.32930° N 18.06860° E'.

**Suggested fix:** Add an ARB message with a {coords} placeholder (and localized N/S/E/W) and render it through L10n; store the coordinates, not the sentence, as the booking label.

### L24. Pickup spot chips and the booked pickup label use hard-coded English ('Main entrance', 'Side entrance', 'Parking', 'Near Home', 'Previously used', 'Short walk')

`lib/features/pickup/application/pickup_spots_controller.dart:75`

**What happens:** Swedish-language rider on Set pickup sees 'Main entrance / Front of the building' chips among otherwise Swedish copy and confirms; the booking's pickup reads 'Klockarvägen 37 – Main entrance'.

**Why:** The app ships en/sv/fr ARB files (l10n.yaml, app_sv.arb, app_fr.arb) and none contains these strings. The titles are rendered on the Set pickup chips (set_pickup_page.dart:1217-1222) and, via pickupSpotLabel, become the confirmed pickup address ('Klockarvägen 37 – Main entrance') that is booked and shown to the driver. Only the spot placement is documented as a mock; the labels are production UI. pickup_location.dart:228 likewise shows a literal 'CURRENT' button text.

**Suggested fix:** Move the titles/subtitles to the ARB files (L10n.current.*) and localize the 'CURRENT' label.

### L25. Confirm pickup spot shows untranslated 'Current location' / 'Pickup location' / 'Location off, set pickup' in its search field and address caption

`lib/features/pickup/presentation/confirm_pickup_spot.dart:170`

**What happens:** French rider on Home with location on taps the pickup field → 'Confirmer le point de départ' page opens with the search box and the grey address line reading 'Current location'; moving the pin where no street resolves shows 'Pickup location'.

**Why:** ConfirmPickupSpot writes the English constants straight into the search TextField and the address Text instead of going through L10n.place: initState copies `widget.initialAddress` into `_address` and `_search.text` (:134, :143), and Home passes `'Current location'` there (home.dart:752 `cleanAddress = gps != null ? 'Current location' : ...` and :760 `(_pickupAddress ?? 'Current location')`). Inside the page `_address = 'Current location'; _search.text = _address;` (:170-171, :271-272) and `pickupLocationFallbackLabel` ('Pickup location', :228) are assigned the same way. They are rendered with `TextField(controller: _search, ...)` at :459 and `Text(_address, ...)` at :515 with no translation. L10n.place (l10n.dart:92-96) is only applied by shortenPlace/compactAddress on other screens, never here. The page is on the Book-now path (home.dart:756 ConfirmPickupSpot.open) and on route change (route_change_flow.dart:74).

**Suggested fix:** Keep the English sentinel internally but render `L10n.place(_address)` / `L10n.current.pickupLocation` in the TextField and Text, and extend L10n.place to cover pickupLocationFallbackLabel.

### L26. `_idle` turns a superseded (null) reverse-geocode into the 'Pickup location' fallback and can overwrite the newer resolved address

`lib/features/pickup/presentation/confirm_pickup_spot.dart:222`

**What happens:** Rider drags the pin, lets go (request A starts), nudges it once more and lets go (request B starts). B answers first and shows 'Klockarvägen 37'; A then answers (as null, superseded) and the card flips to 'Pickup location'. The rider confirms and the booking/driver gets the neutral label 'Pickup location' although the street had been resolved.

**Why:** Every `onCameraIdle` (line 345-349) calls `_idle()`, which awaits `_pickup.reverse(_center)`. `PickupMapController.reverse` (pickup_controller.dart:53-74) deliberately returns `null` for a call that was superseded by a newer one (`if (!_stale.isCurrent(generation)) return null;`). `_idle` does not distinguish 'superseded' from 'no address': `isUnusablePickupLabel(null)` is true, so it does `setState(() { _address = pickupLocationFallbackLabel; _search.text = label; })`. The two lookups are independent HTTP requests (AppGeocoding dedupes only identical keys), so when the newer request B completes before the older request A, B's continuation writes the real street and A's continuation then overwrites it with 'Pickup location'. `_confirmPosition` (line 296-305) books `confirmedPickupAddress(_address, position)`, which keeps that fallback string. Contrast set_pickup_page.dart:550-570 `_resolveAddressNow`, which guards with its own `_resolveGeneration` and `_isAwayFrom(at, _center)` before applying.

**Suggested fix:** Give `_idle` its own generation counter (or read `_pickup`'s) and return without touching state when the lookup was superseded or when `_isAwayFrom(at)`; only apply the fallback label when the current lookup genuinely returned no address.

### L27. Set pickup address search has no try/catch (a failed geocode shows no feedback) and no staleness guard against a pin moved while it was pending

`lib/features/pickup/presentation/set_pickup_page.dart:702`

**What happens:** Rider types 'Storgatan 1' and submits, then immediately drags the pin to the exact entrance; 3-8 s later the geocode answers and the pin jumps back to Storgatan 1 with that label, the quote re-runs, and the rider confirms a pickup they did not choose.

**Why:** _searchAddress closes the sheet, then `final found = await _pickup.search(text)` (PickupMapController.search -> geocoding.geocodeAddress, up to the 8 s API timeout, no generation/stale check and no try/catch) and unconditionally calls `_glideTo(found.position, address: ...)`, which rewrites _center/_routeStart/_address and animates the camera. While the search is pending the page is fully interactive (no busy state), so a drag, a spot chip or My location can already have moved the pin; the old search then overrides it. ConfirmPickupSpot._lookup (confirm_pickup_spot.dart:286-293) has the same shape. The page's own reverse lookups and requotes are generation-guarded (RIDE-12), only the forward search is not. A thrown search (offline) is also uncaught here, so the snackbar 'addressNotFoundMoveMap' never appears.

**Suggested fix:** Bump a generation (or compare _center/_routeStart before and after) around the search and ignore a result once the pin has moved or a newer search started; wrap in try/catch and show the not-found snackbar on failure.

### L28. Account security error messages are English literals shown on the Security screen

`lib/features/profile/application/account_security_controller.dart:42`

**What happens:** Server returns 500 for the security endpoint; French rider opens Account → Sécurité and reads 'Account security is unavailable right now.' under the tile; tapping 'Sign out other devices' after a failure shows 'Could not update active sessions.'

**Why:** The controller stores `errorMessage = 'Account security is unavailable right now.'` (:42) and `'Could not update active sessions.'` (:67). security.dart renders them to the rider: `body: _security.errorMessage ?? context.l10n.securityUnavailableBody` (:72) and `Text(_security.errorMessage!, ...)` (:238). Because errorMessage is non-null whenever load() fails, the localized securityUnavailableBody is never used in the failure case, so fr/sv riders always see English.

**Suggested fix:** Set errorMessage from L10n.current (reuse securityUnavailableBody and add a key for the sign-out failure).

### L29. Pending profile sync (name/consents) is lost on app restart; class doc promises resend on launch

`lib/features/profile/data/synced_profile_repository.dart:315`

**What happens:** Rider renames themselves while offline, closes the app; next launch the server still has the old name until the rider edits the profile again.

**Why:** `_syncPending` is a plain in-memory field (301). `save()` keeps the local copy and swallows the PATCH failure, setting `_syncPending = true` (341-352); `hydrate()` only resends `if (_syncPending)` (313-316). After the app is killed the flag is false again, so a name/consent change that never reached the server is not resent on the next launch, contrary to the class comment ("sent again with the next save or launch"). The driver app shows the rider's name from this profile.

**Suggested fix:** Persist the pending flag (e.g. a `movera_profile_sync_pending` pref) and read it in `hydrate`, or compare a stored "last synced" hash with the cache.

### L30. Promotion details opened outside Select Ride use the built-in category list instead of the live RideCatalogController catalog, so admin-disabled, renamed or added categories show wrongly

`lib/features/promotions/presentation/promotion_details_sheet.dart:77`

**What happens:** Server catalog has the 7 seed categories. Rider opens Pay with → taps the promotion row → sheet lists Van, Wheelchair, Business, Airport, Kids seat, Women driver and Delivery as 'Included', none of which exist on Select Ride.

**Why:** `PromotionDetailsSheet.open` defaults `categories` to `AppScope.instance.rideCatalog.rides()`. In di.dart:337 `rideCatalog` is `RideSelectionRepository()`, whose `builtInRides` is the 14-item fallback list that explicitly includes seven 'Categories the admin may switch on later' (van, wheelchair, business, airport, kids, women, delivery; ride_selection_repository.dart:84-162). The live catalog is `AppScope.instance.catalog.current` (di.dart:341, RideCatalogController), which SelectRide uses for its own `_openPromotionDetails`. PayWithPage (pay_with_page.dart:271 `PromotionDetailsSheet.open(context, promo)`) and the default `onTap` of PromotionTicket (promotion_ticket.dart:54) use the default, so the 'Prices with promotion' section lists categories the rider cannot book and, when `rideTypes` is empty, marks each 'Included'.

**Suggested fix:** Default to `AppScope.instance.catalog.current` (the server/cached catalog) instead of `rideCatalog.rides()`.

### L31. cardDate 'Tomorrow' label breaks on the spring-forward day because today.add(Duration(days:1)) is not the next local midnight

`lib/features/reservations/presentation/reservation_format.dart:143`

**What happens:** On Sunday 29 Mar 2026 a Stockholm rider with a reservation on Monday 30 Mar sees 'Mon, 30 Mar' on the upcoming card instead of 'Tomorrow 30 Mar'. Same for Tunisia or any zone with DST on its switch day.

**Why:** cardDate compares `day == today.add(const Duration(days: 1))` where today is a local midnight. Dart's add() works in absolute time, so on the DST switch day the result is 01:00 of the next day, not midnight (verified by throwaway test: DateTime(2026,3,29).add(Duration(days:1)) == 2026-03-30 01:00:00 under Europe/Stockholm). The equality then fails and the reservation card falls through to weekdayDate instead of 'Tomorrow, 30 Mar'.

**Suggested fix:** Build tomorrow as `DateTime(now.year, now.month, now.day + 1)` (calendar arithmetic) instead of adding a Duration.

### L32. Driver card screen-reader label says 'plate …' in English in every language (the recovery-barrier label is also English but only on screen for one frame)

`lib/features/ride_booking/application/ride_restore_coordinator.dart:620`

**What happens:** Swedish VoiceOver user reloads during a live ride: the barrier announces 'Restoring active ride'; on the upcoming reservation the driver card announces 'plate ABC123'.

**Why:** Two Semantics labels bypass l10n: the ride-recovery barrier `Semantics(label: 'Restoring active ride', ...)` (:620) read aloud while a live ride is restored on cold start, and upcoming_reservation.dart:506 `'plate ${driver.plate}'` inside the driver card's Semantics label list. TalkBack/VoiceOver users on fr/sv hear English.

**Suggested fix:** Use L10n.current (e.g. rtConnectingBody or a new key) for both labels.

### L33. restoreFromBackend/backendReconcile never logs the `ride.restore.jump` record that DECISIONS R6 specifies for illegal jumps

`lib/features/ride_booking/application/ride_session.dart:98`

**What happens:** Backend projection moves a session from `driverArriving` straight to `paymentFinalized` (the example in the code comment at 141-142). Per R6 a `ride.restore.jump` entry should be logged for diagnostics; no log line is emitted.

**Why:** docs/DECISIONS.md line 67 (R6) states that `restoreFromBackend` 'may jump; illegal jumps log `ride.restore.jump` and are not rejected'. `backendReconcile` (98-152) logs only `ride.restore.stale` when ordering rejects an event and otherwise assigns the status silently; `canTransition` is never consulted and the string `ride.restore.jump` does not exist anywhere in the repository (grep). Operators relying on that log to detect backend projections that skip states get nothing.

**Suggested fix:** In `backendReconcile`, when `!canTransition(status, backendStatus)` log `AppLog.info('ride.restore.jump', ...)` before assigning.

### L34. Ride completed driver panel shows the English fallback 'Vehicle details unavailable' when the matched driver has no vehicle fields

`lib/features/ride_booking/data/driver_repository.dart:55`

**What happens:** A ride completes with a driver payload lacking vehicleMake/Model/Color; the Swedish Ride completed → driver info panel shows 'Vehicle details unavailable'.

**Why:** DriverRepository.current() builds DriverProfile with `vehicle: vehicle.isEmpty ? 'Vehicle details unavailable' : vehicle` (:55) (and tagline 'Movera driver' / '{n} trips completed', :52-54). RideCompletedDriverInfo (driver_info.dart:70 `text: driver.vehicle`) renders the vehicle line to the rider on the Ride completed screen (ride_completed.dart:387). When the matched driver carried no make/model/color the English fallback is shown in fr/sv; no ARB key exists for it.

**Suggested fix:** Use L10n.current for the vehicle fallback (and the tagline, which also has no localized form).

### L35. Scheduled booking does not re-quote a quote that expired during the date picker and Set pickup; booking fails with a no-price toast and needs two more taps

`lib/features/ride_selection/presentation/select_ride.dart:1155`

**What happens:** Rider taps Schedule, spends 3 minutes picking Saturday 07:00 and adjusting the pickup pin, taps 'Confirm and schedule' → toast that no price is available; reservation not created; second attempt repeats every step.

**Why:** `_book` checks `quoteIsAvailable` once, then `_bookScheduled` opens the date-time picker and Set pickup (and possibly the picker again for return rides) before `ScheduledRideCheckout.run` → `draftFrom` → `ScheduledRideBooking.quotedPrice`, which throws `ScheduledQuoteRequiredException` as soon as `authoritativePriceFor` is null. Quotes expire after 2 minutes (in_process_mock_client.dart:2173 and catalog_quote_repository.dart:35), so a rider who spends more than two minutes choosing a time and pickup spot gets the `resErrNoPriceBook` toast and nothing is booked; Book now handles the same situation by re-quoting in place (`_quoteAfterPickup`, RIDE-2) but the scheduled path has no equivalent. Tapping Book again then shows 'price unavailable, refreshing' and the rider must repeat the picker and pickup steps.

**Suggested fix:** Before `ScheduledRideCheckout.run`, reuse `_quoteAfterPickup(ride)` (awaiting `_pinQuote`, re-quoting from the confirmed pickup when stale) and pass its price, mirroring `_bookNow`.

### L36. Wallet split line is computed from the SEK list price for a pickup priced in another currency before the quote arrives

`lib/features/ride_selection/presentation/select_ride.dart:2334`

**What happens:** Rider in Paris with 50 € in the EUR wallet opens Select Ride; before quotes land, the selected tile shows '…' as the price and 'Wallet −50 € · you pay 209 €' underneath.

**Why:** `_rideTile` shows `_walletLine(price)` whenever `walletSplitFor(moneyOf(price).amountMinor).usesWallet`, where `price = _priceFor(ride)` falls back to `ride.price` (the SEK catalog figure) when no quote is held. The price text itself is guarded by `_hasPrice(ride)` and shows '…' for a pickup whose zone currency differs from the list's, but the wallet line is not guarded, so for a EUR pickup with a EUR wallet balance the selected tile reads e.g. 'Wallet −50 € · you pay 209 €' built from the 259 kr list price while the price shows '…'.

**Suggested fix:** Guard the wallet line with `_hasPrice(ride)` (and ideally with an available quote).

### L37. Ride check saves the answer 'Called 112' even when the dialer failed to open (alert is still correctly sent)

`lib/features/safety/application/ride_check_controller.dart:495`

**What happens:** No dialer (web/tablet) or launch refused: card shows a note that the dialer failed, yet the trip details and the submitted answers say "Called 112".

**Why:** `call112()` catches the dialer failure into `failure` (478-489) but then unconditionally sets `called112: true` and appends `RideCheckAnswer.call112` (495-501), and sends the alert. The answer label "Called 112" is what is saved on the trip and shown in the trip's details (`RideCheckRecord.answerSummary`, ride_check_trip_entry.dart:466) and what the safety team receives, although no call happened; only the transient card note shows `callError`.

**Suggested fix:** Record a distinct answer (e.g. `call_112_failed`) or omit the "Called 112" answer when `failure != null`, while still sending the alert.

### L38. SwedishPhone.toE164 accepts a trunk zero after +46 and stores an invalid contact number

`lib/features/safety/domain/phone_e164.dart:116`

**What happens:** Rider adds a trusted contact as "+46 070 123 45 67"; it is saved as +46070 123 45 67 and shown as such; the number cannot be reached by the safety team.

**Why:** After normalising, the function only checks that the part after `+46` is 7–10 digits (116-119). Input like `+46 070 123 45 67` (a very common way to write a Swedish mobile) becomes `+46070…`, which passes (10 digits) and is stored as the emergency contact's `phoneE164` and sent to the share/alert backend, but is not a dialable E.164 number.

**Suggested fix:** Strip a leading `0` from `rest` (or reject it), and require the national number to start with a non-zero digit.

### L39. `_ContactEditorState._save` calls setState in its catch block without a mounted check; the editor is a dismissible sheet

`lib/features/safety/presentation/emergency_contacts_page.dart:287`

**What happens:** Rider taps Save on the emergency-contact sheet, swipes the sheet down during the request, and the request then fails (offline, server error). The app logs/reports an unhandled 'setState() called after dispose()' error from `_ContactEditorState._save`.

**Why:** `_ContactEditor` is shown through `MoveraSheet.show` (line 42-46) with the defaults `swipeDismissible = true, barrierDismissible = true` (movera_sheet.dart:22-23), so the rider can swipe it away while `await widget.controller.addContact/editContact` is in flight. The success branch guards with `if (mounted) Navigator.pop(context);` but the catch branch does `setState(() { _error = ...; _saving = false; })` unconditionally. If the save fails after the sheet was dismissed, `setState` runs on a disposed State: an assertion error in debug ('setState() called after dispose()'), a null-check error on `_element` in release, surfacing as an unhandled async error from the button's unawaited `_save()` future.

**Suggested fix:** Add `if (!mounted) return;` at the top of the catch block (mirroring the success branch).

### L40. 'CURRENT' button caption on the saved-places location picker is hard-coded English

`lib/features/saved_places/presentation/pickup_location.dart:228`

**What happens:** French rider adds a saved place and opens the location picker: the GPS button reads 'CURRENT'.

**Why:** RiderSearchPickupLocation (reached from Add place → pick location, add_place.dart:65) draws the use-my-location button with `TextWidget(text: 'CURRENT', ...)` (:228). No ARB key is used; fr/sv riders see the English caption on the Saved places flow.

**Suggested fix:** Use a localized caption (e.g. context.l10n.currentLocation shortened or a new key).

### L41. Untranslated '24-hour', 'SCHEDULE' and 'Current location' on the scheduling screens (the realtime 'driver arrived' message is never displayed)

`lib/features/scheduled_rides/presentation/select_date_time.dart:342`

**What happens:** French rider opens Schedule: header "SCHEDULE", pickup field "Current location", time sheet "24-hour" all in English while the rest of the page is French.

**Why:** Literal English in localized screens: `'24-hour'` caption on the time sheet (342); `'SCHEDULE'` header (schedule_ride.dart:305); `'Current location'` as the pickup field's initial text and label (schedule_ride.dart:58, 184; scheduled_category_gate.dart:411 — note `resolveScheduledPoint` also uses it as a sentinel at 490, so a translation must keep the sentinel separate); and `message = 'Your driver has arrived at the pickup point.'` emitted with the driverArrived signal (reservation_ride_realtime.dart:197).

**Suggested fix:** Move these to ARB keys; keep an internal sentinel constant for the "current location" pickup rather than comparing the displayed text.

### L42. L10n.place never translates the 'Pickup location' fallback label, so it shows in English on every later screen

`lib/l10n/l10n.dart:92`

**What happens:** Reverse geocoding fails for the confirmed pin → the ride is booked with label 'Pickup location'; the French rider sees 'Pickup location' as the pickup on the Finding/Waiting sheet, in History and in Support instead of 'Lieu de départ'.

**Why:** L10n.place only maps 'Current location' and 'Location off, set pickup'. The third app-generated sentinel, `pickupLocationFallbackLabel = 'Pickup location'` (pickup_address.dart:6), is returned by confirmedPickupAddress/bookingPickupAddress (:46-49, :69) as the ride's pickup label and is therefore shown through shortenPlace/compactAddress (place_format.dart:8) on Finding, Waiting, History and Support untranslated, although an ARB key `pickupLocation` ('Lieu de départ', 'Upphämtningsplats') exists. Reproduced: L10n.use('fr'); shortenPlace(pickupLocationFallbackLabel) == 'Pickup location' while L10n.current.pickupLocation == 'Lieu de départ'.

**Suggested fix:** Add `'Pickup location' => current.pickupLocation` to L10n.place.

### L43. HorizontalSwipe keeps the drag origin in build-local variables, so a rebuild mid-drag resets start to 0: a leftward drag is swallowed or read as a right swipe

`lib/shared/widgets/horizontal_swipe.dart:22`

**What happens:** Rider on Home drags the sheet left to open Payment while a location fix arrives (Home rebuilds ~1 Hz): nothing opens, or on a bottom-bar page the app pops to the previous tab instead of the next one.

**Why:** `start` and `last` are plain locals declared inside `build()` and captured by the three drag closures. GestureDetector re-syncs recognizer callbacks on every rebuild (RawGestureDetectorState.didUpdateWidget -> _syncAll re-initialises onStart/onUpdate/onEnd), so if the widget rebuilds while a finger is down, onUpdate/onEnd run with a fresh `start = 0`. `distance = last - start` then equals the absolute x position of the finger (always > 56 on a phone), so `right` is true regardless of direction. Callers: lib/features/home/presentation/home.dart:2177 wraps the Home sheet inside an AnimatedBuilder (rebuilds on every sheet tick and on every Home setState, e.g. each GPS fix delivered by HomeLocationController._deliverFix) with only onSwipeLeft -> a slow left swipe is swallowed and a fast one is cancelled because both `left` and `right` are true; lib/features/home/presentation/widgets/home_tab_page.dart:42 sets both callbacks, so a rebuild during a leftward drag pops the page with `HomeTabs.previousOf(tab)` (the wrong neighbour). Reproduced with a throwaway widget test (deleted): a 100 px leftward drag with one setState mid-drag printed `left=0 right=1`; the identical drag without the rebuild gave `left=1 right=0`.

**Suggested fix:** Make HorizontalSwipe a StatefulWidget (or keep start/last in a ValueNotifier/record owned outside build) so the drag origin survives rebuilds; alternatively use DragStartDetails/DragEndDetails only (d.velocity + accumulated delta from onHorizontalDragUpdate stored in State).

### L44. screenHorizPadding is computed once (lazy top-level), so after a web/desktop window resize side gutters stay at the first scale (e.g. 16 px vs 20 px) while ResSize-scaled layout rescales

`lib/shared/widgets/responsive_size.dart:3`

**What happens:** Desktop/web rider resizes the browser window from phone width to 1280 px: everything scaled through ResSize.w grows to the 1.25 bound, but the side gutters in Chat, Home's location card and Trip detail stay at the old 16 x (old scale) value, leaving misaligned edges.

**Why:** `double screenHorizPadding = ScreenUtil().setWidth(16);` is evaluated on first read and never again. lib/app/screen_scale.dart:45-47 deliberately rebuilds ScreenUtilInit with new bounds on a window resize so widths rescale, but every consumer of this global (lib/features/messages/presentation/chat.dart:107-314, lib/features/home/presentation/home.dart:1990-2002, lib/features/ride_complete/presentation/trip_detail.dart:28, driver_info.dart:40) keeps the padding computed for the first window size while the rest of the layout (ResSize.w, which is a getter) rescales. If the first read happens before ScreenUtilInit has run (any host that builds one of those widgets directly) the value is derived from ScreenUtil's uninitialised defaults for the rest of the process.

**Suggested fix:** Make it a getter: `double get screenHorizPadding => ScreenUtil().setWidth(16);`.

### L45. core -> features/di import guard only matches single-quoted package: imports, so a relative import from lib/core bypasses it (no current breach)

`test/architecture/guard_test.dart:188`

**What happens:** A developer adds `import '../../features/booking/application/booking_coordinator.dart';` to a file in lib/core; `flutter test test/architecture/guard_test.dart` still passes and the documented 'core is feature-agnostic' rule in ARCHITECTURE.md is silently broken.

**Why:** The architecture guard extracts directives with `^\s*(?:import|export)\s+'([^']+)'` and then only flags URIs that start with `package:movera_rider/features/` or equal `package:movera_rider/app/di.dart`. A file under lib/core that writes `import '../../features/x/y.dart';`, `import "package:movera_rider/features/x/y.dart";`, or a `part`/deferred/conditional form reaches features without tripping the guard. Relative imports are already in use elsewhere in lib (e.g. lib/features/home/presentation/home_map_style.dart:1, lib/shared/widgets/custom_google_map.dart:12,14), so the style is not forbidden by lint. No current violation exists, so this is a gap in the gate, not a live breach.

**Suggested fix:** Match both quote styles (`['"]([^'"]+)['"]`), resolve relative URIs against the file's directory before checking, and also reject any resolved path under lib/features or lib/app/di.dart; optionally add `always_use_package_imports` to analysis_options to make relative imports impossible.

### L46. lock_test idempotency-key tests are vacuous: failNext fails the quote POST, so only one ride POST is ever made and no keys are compared (coverage exists elsewhere)

`test/booking/lock_test.dart:105`

**What happens:** A regression that generates a fresh Idempotency-Key on every retry (so a network blip double-books a ride), or that drops the header entirely on retry, passes both tests unchanged, while the test names claim the opposite is guaranteed.

**Why:** Both 'failed finding retry reuses the same logical booking key' (lines 105-126) and 'changed finding intent receives a new booking key' (lines 128-161) set `RecordingMockClient()..failNext = true` and expect the first `submitFinding` to throw. But `BookingCoordinator.submitFinding` first calls `_resolveQuoteBinding` (POST /api/v1/quotes) before posting /api/v1/rides, and `InProcessMockClient.failNext` returns 500 to the next request of any path. So the 500 hits the quote request; the rides endpoint is never reached on the failed attempt, and `RecordingMockClient.send` (which only records POST /api/v1/rides, lines 19-26) records nothing. The second submit records exactly one key. Both tests then assert `hasLength(1)` and `isNotNull`, which is satisfied regardless of whether the coordinator reuses, rotates, or never sends an idempotency key. Neither test compares a key across attempts, so the 'reuse' and 'new key' semantics are untested. Reproduced with a throwaway test (test/_audit_lock_vacuous_test.dart, since deleted) recording request paths: after the failed submit, `rideKeys` was empty and exactly one `POST /api/v1/quotes` had been made; the second submit produced one ride key; `flutter test` output: `00:00 +1: All tests passed!`.

**Suggested fix:** Make the failure hit the rides endpoint (e.g. a mock that fails only `POST /api/v1/rides` once, or pre-fetch the quote and pass the quote binding), then assert `idempotencyKeys` has length 2 and `keys[0] == keys[1]` for the retry case and `keys[0] != keys[1]` for the changed-intent case.

### L47. Empty `_guards()` body: the documented replacement guard for 'mock never invents a driver' asserts nothing

`test/ride/mock_driver_assignment_test.dart:49`

**What happens:** A presentation widget or controller starts constructing a `MatchedDriver` locally when the API returns none; nothing in this test file fails, although its comment claims the invariant is guarded.

**Why:** `_guards()` is called from main() (line 37) and carries a doc comment explaining it is 'The guard that replaces "the mock never invents a driver"' and that 'no screen, controller or feature repository may conjure a driver of its own'. Its body is empty, so the rule it documents is not enforced by any test in this file.

**Suggested fix:** Implement the guard (e.g. assert that no file outside lib/core/api constructs `MatchedDriver(` with literal mock identities, or that `MockDriverPool` is only referenced from the in-process mock client) or delete the empty function and its misleading comment.
