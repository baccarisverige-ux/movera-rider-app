# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# ---- Auth and devices (v0.5.0, CONTRACT.md §8). No bearer token on the auth calls.
for o in [
    op("post", "/auth/otp/request", "requestOtp", "Start a phone sign-in (SMS code)", ["rider", "driver"], "Auth",
       body="OtpRequest", ok=(200, "OtpChallenge"),
       desc="Rate limited per phone and device (429 rate_limited with Retry-After). A test number (contract.json#auth.testSignIn, outside production) gets no SMS and accepts the fixed code. "
            "v0.15.0: 429 reasons otp_resend_too_soon and otp_too_many (contract.json#auth.limits: per phone and app, per address, in an hour); 403 forbidden, reason sign_in_restricted, for a number not open for sign-in (the app offers POST /auth/waitlist)."),
    op("post", "/auth/otp/verify", "verifyOtp", "Verify the code and sign in", ["rider", "driver"], "Auth",
       body="OtpVerifyRequest", ok=(200, "AuthTokens"),
       desc="Wrong code → 400 invalid_request (reason invalid_otp_code; retryable until maxAttempts); unknown session → 400 invalid_request (reason invalid_otp_session); "
            "expired session → 410 otp_expired; too many attempts → 429 (v0.15.0: reason otp_too_many_attempts; ask for a new code). With a linkToken the verified phone is linked to the provider account."),
    op("post", "/auth/provider", "signInWithProvider", "Sign in with Apple or Google", ["rider", "driver"], "Auth",
       body="ProviderSignInRequest", ok=(200, "ProviderSignInResult")),
    op("post", "/auth/refresh", "refreshTokens", "Rotate the refresh token for new tokens", ["rider", "driver"], "Auth",
       body="RefreshRequest", ok=(200, "AuthTokens"), desc="A used, revoked or unknown refresh token → 401 unauthenticated; the app signs out."),
]:
    o["security"] = []
PATHS["/auth/otp/verify"]["post"]["responses"]["410"] = err("otp_expired: the code or the session expired; request a new code.")
# v0.15.0 (owner 2026-10-29): sign-in group 1.
for o in [
    op("post", "/auth/waitlist", "joinWaitlist", "Join the waiting list (number not open for sign-in yet)", ["rider", "driver"], "Auth",
       body="WaitlistRequest", ok=(200, "WaitlistReceipt"), desc=AU["waitlist"]["note"]),
]:
    o["security"] = []
# v0.18.18 (owner 2026-11-03 "Close it now"): the test-account list needs a signed-in admin (drivers.read).
op("get", "/auth/test-accounts", "listTestAccounts", "Test numbers and their account status (not in production; admin only)", ["admin"], "Auth",
   ok=(200, "TestAccountList"), permission=AU["testAccounts"]["permission"], desc=AU["testAccounts"]["note"])
op("post", "/auth/sign-out", "signOut", "End this session (revokes the refresh token)", ["rider", "driver"], "Auth", ok=(204, None),
   desc="Idempotent; also unregister the push device.")
op("post", "/push/devices", "registerPushDevice", "Register this device's push token", ["rider", "driver"], "Auth",
   body="PushDeviceRequest", ok=(200, "PushDeviceAck"), mutation=True, desc="Keyed by token and actor; registering again updates it.")
op("post", "/push/devices/unregister", "unregisterPushDevice", "Forget this device's push token", ["rider", "driver"], "Auth",
   body="PushDeviceUnregister", ok=(200, "PushDeviceAck"), mutation=True)

# ---- Rider
op("post", "/quotes", "createQuotes", "Quote every (or the given) category for a route", ["rider"], "Rider · Booking",
   body="QuoteRequest", ok=(201, "QuoteList"), mutation=True, desc="Quotes MUST include stops. Server owns the price; client never computes fares.")
op("post", "/trips", "createTrip", "Request a trip from a quote (live or scheduled)", ["rider"], "Rider · Booking",
   body="CreateTripRequest", ok=(201, TP), mutation=True, transition="request")
op("get", "/trips/{tripId}", "getTrip", "Get the trip projection (also the polling fallback)", ["rider", "driver", "admin"], "Trips",
   params=TID, ok=(200, TP))
op("patch", "/trips/{tripId}", "updateTrip", "Change route (with routeQuoteId) or payment method", ["rider"], "Rider · Booking",
   params=TID, body="UpdateTripRequest", ok=(200, TP), mutation=True)
op("post", "/trips/{tripId}/route-quote", "quoteRouteChange", "Price a route change after request", ["rider"], "Rider · Booking",
   params=TID, body="RouteQuoteRequest", ok=(201, "RouteQuote"), mutation=True)
op("post", "/trips/{tripId}/cancel", "cancelTrip", "Cancel the trip (rider or driver)", ["rider", "driver"], "Trips",
   params=TID, body="CancelCommand", ok=(200, TP), mutation=True, transition="cancel",
   desc="rider: requested…arrived → cancelled_by_rider (fee per config cancelFees). driver live: accepted/driver_to_pickup/arrived → searching (reassign); "
        "driver scheduled: accepted → requested; driver onboard+: → cancelled_by_driver. Anything else → 409 invalid_transition.")
op("post", "/trips/{tripId}/end-early", "endTripEarly", "Rider ends an onboard trip early", ["rider"], "Rider · Booking",
   params=TID, body="EndEarlyCommand", ok=(200, TP), mutation=True, transition="end_early")
op("post", "/trips/{tripId}/cancel-reason", "setCancelReason", "Rider tells the reason after a cancel-first", ["rider"], "Rider · Booking",
   params=TID, body="CancelReasonCommand", ok=(200, TP), mutation=True,
   desc="Owner decision 6 (v0.4.4), CONTRACT.md §3 \"After-cancel reason\". Allowed only while the trip is cancelled_by_rider and "
        "cancellation.reasonCode is still something_else (the code a cancel-first names): sets cancellation.reasonCode and "
        "cancellation.note. Not a lifecycle transition: status, version, sequence, fee and fare do not change and no realtime event "
        "is sent. Any other state (also a reason already told) → 409 invalid_transition; a code outside the rider group → 400 invalid_request.")
op("post", "/trips/{tripId}/on-the-way", "riderOnTheWay", "Rider says they are on their way to the car", ["rider"], "Rider · Booking",
   params=TID, ok=(200, TP), mutation=True,
   desc="v0.5.4, CONTRACT.md §4. The rider's \"I'm on the way\" (shown once the driver has arrived, also while the driver is "
        "coming) reaches the driver as a `rider_on_the_way` realtime event carrying the current projection. Not a lifecycle "
        "transition: status and version do not change. Allowed while the trip is accepted, driver_to_pickup or arrived; any "
        "other state → 409 invalid_transition. No request body.")
op("get", "/trips/{tripId}/events", "streamTripEvents", "Trip realtime stream (SSE / WebSocket) or JSON replay",
   ["rider", "driver", "admin"], "Realtime", params=TID + [pref("After"), pref("Limit"), pref("LastEventId")],
   content=sse("Server-sent events. A WebSocket upgrade on the same URL carries the same JSON frames.", "RealtimeEvent", "RealtimeEventPage"),
   ok_desc="`Accept: text/event-stream` → live stream starting after `after`; `Accept: application/json` → replay page of events with sequence > after.",
   desc="Resync: GET /trips/{tripId} then GET /trips/{tripId}/events?after={projection.sequence}. Admin uses the same stream for the live map.")
op("get", "/trips/{tripId}/pin", "getTripPin", "Get the per-trip PIN to show the driver", ["rider"], "Rider · Booking",
   params=TID, ok=(200, "PinCode"))
op("post", "/trips/{tripId}/rating", "rateTrip", "Rate the other party (and optionally tip)", ["rider", "driver"], "Trips",
   params=TID, body="RatingRequest", ok=(201, "Rating"), mutation=True,
   desc="Not a lifecycle command: allowed after completed, and for the rider also after a trip the rider ended early "
        "(cancelled_by_rider via end_early; a plain cancel is 409 invalid_transition). See RatingStatus x-rating-allowed. "
        "Moves ratingStatus pending → submitted|skipped and emits rating_updated.")
op("get", "/rider/trips", "listRiderTrips", "Rider trip history and reservations", ["rider"], "Rider · Booking",
   params=[pref("Cursor"), pref("Limit"), q("status", ref("TripStatus"), multi=True), q("kind", ref("TripKind")), pref("From"), pref("To")],
   ok=(200, "TripProjectionPage"))
op("get", "/rider/trips/active", "getRiderActiveTrip", "The rider's current non-terminal live trip, else a booked trip whose driver started driving", ["rider"], "Rider · Booking",
   ok=(200, TP), desc="204 when there is none. v0.18.32 (contract.json#bookedRideSeen): a booked trip (kind scheduled) is returned once it reached driver_to_pickup, "
                      "until it ends; a live trip wins when both are active (owner Q1, the app shows a banner for the booked one).")
PATHS["/rider/trips/active"]["get"]["responses"]["204"] = {"description": "No active trip", "headers": HDR_REQ}
op("get", "/rider/nearby-vehicles", "getRiderNearbyVehicles", "Free cars near a point, for the rider's map", ["rider"], "Rider · Booking",
   params=[{**q("lat", n(minimum=-90, maximum=90)), "required": True}, {**q("lng", n(minimum=-180, maximum=180)), "required": True}],
   ok=(200, "NearbyVehicleList"), read_only=True,
   desc=f"CONTRACT.md §13 (v0.5.2). Drivers online and free within {RN['radiusMeters']} m of the point with a fix not older than "
        f"{RN['freshSeconds']} s, nearest first, at most {RN['maxVehicles']}. No id, name, plate or trip; positions rounded to "
        f"{RN['roundDecimals']} decimals. The app asks again every refreshSeconds while the rider chooses a ride. An empty list is normal.")
op("get", "/rider/config", "getRiderConfig", "Published RiderAppConfig for a zone", ["rider"], "Config",
   params=[pref("ZoneIdQuery")], ok=(200, "RiderAppConfig"))
op("get", "/rider/config/stream", "streamRiderConfig", "config_published events for the rider document", ["rider"], "Realtime",
   params=[pref("ZoneIdQuery")], content=sse("Server-sent events. v0.18.32: also RiderTripEvent (kind rider_trip_changed) for the signed-in rider's trips, id = the document version already sent.", "ConfigEvent"))
op("get", "/rider/profile", "getRiderProfile", "Get own rider profile", ["rider"], "Rider · Account", ok=(200, "Rider"))
op("patch", "/rider/profile", "updateRiderProfile", "Update own rider profile", ["rider"], "Rider · Account",
   body="RiderProfileUpdate", ok=(200, "Rider"), mutation=True)
op("get", "/rider/places", "listSavedPlaces", "Saved places", ["rider"], "Rider · Account",
   params=[pref("Cursor"), pref("Limit")], ok=(200, "SavedPlacePage"))
op("post", "/rider/places", "createSavedPlace", "Save a place", ["rider"], "Rider · Account",
   body="SavedPlaceRequest", ok=(201, "SavedPlace"), mutation=True)
op("delete", "/rider/places/{placeId}", "deleteSavedPlace", "Delete a saved place", ["rider"], "Rider · Account",
   params=[pref("PlaceId")], ok=(204, None), mutation=True)
# payments
op("get", "/payment-methods", "listPaymentMethods", "Saved payment methods", ["rider"], "Rider · Payments",
   params=[pref("Cursor"), pref("Limit")], ok=(200, "SavedPaymentMethodPage"))
op("post", "/payment-methods", "addPaymentMethod", "Add a PSP-tokenised payment method", ["rider"], "Rider · Payments",
   body="AddPaymentMethodRequest", ok=(201, "SavedPaymentMethod"), mutation=True)
op("delete", "/payment-methods/{paymentMethodId}", "deletePaymentMethod", "Remove a saved payment method", ["rider"], "Rider · Payments",
   params=[pref("PaymentMethodId")], ok=(204, None), mutation=True)
op("post", "/payment-methods/default", "setDefaultPaymentMethod", "Set the default payment method", ["rider"], "Rider · Payments",
   body="DefaultPaymentMethodRequest", ok=(200, "SavedPaymentMethodPage"), mutation=True)
op("post", "/payments", "createPayment", "Create a payment intent (trip, tip or wallet top-up)", ["rider"], "Rider · Payments",
   body="PaymentRequest", ok=(201, "PaymentIntent"), mutation=True)
op("get", "/payments/{paymentId}", "getPayment", "Get a payment intent", ["rider", "admin"], "Rider · Payments",
   params=[pref("PaymentId")], ok=(200, "PaymentIntent"))
op("post", "/payments/{paymentId}/confirm", "confirmPayment", "Confirm a payment intent after PSP client step", ["rider"], "Rider · Payments",
   params=[pref("PaymentId")], ok=(200, "PaymentIntent"), mutation=True)
PARAMS["WalletCurrency"] = {"name": "currency", "in": "query", "required": False, "description": "v0.18.28: which balance is `balance` (ISO 4217, e.g. EUR). Default: the currency of the rider's zone.", "schema": {"type": "string", "pattern": "^[A-Z]{3}$"}}
op("get", "/wallet", "getWallet", "Wallet balance (server-owned)", ["rider"], "Rider · Payments", params=[pref("WalletCurrency")], ok=(200, "Wallet"))
op("get", "/wallet/entries", "listWalletEntries", "Wallet ledger", ["rider"], "Rider · Payments",
   params=[pref("Cursor"), pref("Limit"), pref("From"), pref("To")], ok=(200, "WalletEntryPage"))
op("post", "/wallet/topup", "topUpWallet", "Top up the wallet", ["rider"], "Rider · Payments",
   body="TopupRequest", ok=(201, "PaymentIntent"), mutation=True)
# shared rider/driver
op("get", "/notifications", "listNotifications", "Own notifications (audience from token)", ["rider", "driver"], "Notifications & messages",
   params=[pref("Cursor"), pref("Limit"), q("unreadOnly", {"type": "boolean"})], ok=(200, "NotificationPage"))
op("post", "/notifications/{notificationId}/read", "markNotificationRead", "Mark a notification read", ["rider", "driver"],
   "Notifications & messages", params=[pref("NotificationId")], ok=(200, "Notification"), mutation=True)
op("get", "/trips/{tripId}/messages", "listTripMessages", "Trip chat messages", ["rider", "driver", "admin"], "Notifications & messages",
   params=TID + [pref("Cursor"), pref("Limit")], ok=(200, "MessagePage"), permission="support.reply",
   desc="v0.13.0 (CONTRACT.md §23): the trip's own rider or driver; an admin needs support.reply and the trip in the admin's zones (else 403, reason zone_out_of_scope). x-permission applies to admins only.")
op("post", "/trips/{tripId}/messages", "sendTripMessage", "Send a trip chat message (emits kind=message)", ["rider", "driver", "admin"],
   "Notifications & messages", params=TID, body="MessageRequest", ok=(201, "Message"), mutation=True, permission="support.reply",
   desc="v0.13.0: open from driver assignment until drop-off; after it the rider and driver get 409 invalid_transition, reason chat_closed (no grace period). Admins as for GET.")
op("post", "/trips/{tripId}/call", "callTripPeer", "Call the other side through a masked number", ["rider", "driver"], "Notifications & messages",
   params=TID, ok=(200, "TripCall"), mutation=True,
   desc="v0.13.0 (contract.json#chat.call): the trip's rider or driver while the trip is open for chat. 503 unavailable, reason call_unavailable, while no telephony provider is set up; 409 invalid_transition, reason chat_closed, after drop-off.")
op("get", "/support/tickets", "listOwnTickets", "Own support tickets", ["rider", "driver"], "Support",
   params=[pref("Cursor"), pref("Limit"), q("status", {"type": "string", "enum": ["open", "pending", "resolved", "closed"]})],
   ok=(200, "SupportTicketPage"))
op("post", "/support/tickets", "createTicket", "Open a support ticket", ["rider", "driver"], "Support",
   body="TicketRequest", ok=(201, "SupportTicket"), mutation=True)

# ---- Driver
op("post", "/driver/availability", "setDriverAvailability", "Go online / offline", ["driver"], "Driver · Session",
   body="AvailabilityRequest", ok=(200, "Driver"), mutation=True,
   desc="409 when on a trip, account not active, documents expired or driving limit reached (projection = Driver). v0.14.0: a car whose Vehicle.requiredDocuments are not all approved → 409 documents_not_approved (reason vehicle_documents_not_approved, details). "
        "v0.18.0: " + C["driverOnboarding"]["documentExpiry"]["block"] + " With no car picked: reason fleet_no_approved_car when the fleet has no car that can be picked, else no_vehicle (contract.json#driverOnboarding.reminders). "
        "v0.18.4: " + C["driverHome"]["locationRequired"]["note"] + " Outside the driver's zones going online still works and the Driver carries outsideArea: true (contract.json#driverHome.outsideArea). "
        "Slow server: contract.json#auth.slowStart covers this call.")
op("post", "/driver/location", "postDriverLocation", "Upload a batch of GPS fixes", ["driver"], "Driver · Session",
   body="LocationBatch", ok=(200, "DriverLocationAck"), mutation=True,
   desc="Fixes are fanned out as kind=location on the active trip's stream; they never change the projection version. v0.18.52 (§74): a batch from a driver who is offline or suspended with no active trip is not stored: 200 with accepted 0 (contract.json#driverHome.offlineLocation).")
op("get", "/driver/offers", "listDriverOffers", "Current offers for the driver", ["driver"], "Driver · Offers",
   params=[pref("Cursor"), pref("Limit"), q("status", ref("OfferStatus"), multi=True), q("kind", ref("OfferKind"), multi=True)],
   ok=(200, "OfferPage"))
op("get", "/driver/offers/stream", "streamDriverOffers", "Offer feed (offer_created / offer_updated / offer_withdrawn)", ["driver"],
   "Realtime", params=[pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "OfferEvent", "OfferPage"),
   ok_desc="SSE feed; `Accept: application/json` returns the current open offers.")
S["OfferCheck"] = obj({"offer": ref("Offer"),
                       "trip": {"allOf": [ref("TripProjection")], "description": "Driver view of the trip; only when offer.status is claimed (the accept went through: the trip is his)."}},
                      ["offer"], "v0.18.6 (G4 decision 4): " + C["driverOffers"]["acceptCheck"]["note"])
op("get", "/driver/offers/{offerId}", "getDriverOffer", "Did my accept go through? One of my offers, now", ["driver"], "Driver · Offers",
   params=[pref("OfferId")], ok=(200, "OfferCheck"),
   desc="v0.18.6 (G4 decision 4, contract.json#driverOffers.acceptCheck): the offer as it is now, any status; with the trip when status is claimed. "
        "Read-only. Another driver's offer or an unknown id → 404 offer_not_found.")
op("post", "/offers/{offerId}/accept", "acceptOffer", "Accept / claim an offer (incl. reservation claim)", ["driver"], "Driver · Offers",
   params=[pref("OfferId")], body="OfferCommand", ok=(200, TP), mutation=True, transition="accept",
   desc="expectedVersion is the OFFER version. Another driver won → 409 conflict with projection = Offer(status=claimed_elsewhere). "
        "Scheduled trip claim: requested → accepted.")
op("post", "/offers/{offerId}/decline", "declineOffer", "Decline an offer", ["driver"], "Driver · Offers",
   params=[pref("OfferId")], body="DeclineOfferCommand", ok=(200, "Offer"), mutation=True,
   desc="Offer command, not a trip command: the trip moves offered → searching through system `offer_lapsed`.")
for seg, cmd, opid, body, summ in [("head-to-pickup", "head_to_pickup", "headToPickup", "TripCommand", "Start driving to pickup"),
                                   ("arrive", "arrive", "arriveAtPickup", "TripCommand", "Arrived at pickup (starts waiting clock)"),
                                   ("board", "board", "boardRider", "BoardCommand", "Rider is on board (PIN token when required)"),
                                   ("start", "start_trip", "startTrip", "TripCommand", "Start the trip"),
                                   ("complete", "complete", "completeTrip", "CompleteCommand", "Complete the trip"),
                                   ("no-show", "no_show", "markNoShow", "NoShowCommand", "Rider no-show after noShowAfterMin")]:
    op("post", f"/trips/{{tripId}}/{seg}", opid, summ, ["driver"], "Driver · Trip", params=TID, body=body, ok=(200, TP),
       mutation=True, transition=cmd)
op("post", "/trips/{tripId}/pin/verify", "verifyTripPin", "Verify the rider PIN", ["driver"], "Driver · Trip",
   params=TID, body="PinVerifyRequest", ok=(200, "PinVerification"), mutation=True,
   desc="Wrong PIN → 400 invalid_request (retryable=false); too many attempts → 429.")
op("get", "/driver/reservations", "listDriverReservations", "Open reservation offers or accepted reservations", ["driver"], "Driver · Offers",
   params=[q("scope", {"type": "string", "enum": ["open", "accepted"], "default": "open"}), pref("Cursor"), pref("Limit"), pref("From"), pref("To")],
   ok=(200, {"oneOf": [ref("OfferPage"), ref("TripProjectionPage")]}),
   ok_desc="scope=open → OfferPage (kind=reservation); scope=accepted → TripProjectionPage (kind=scheduled, status=accepted).")
op("get", "/driver/config", "getDriverConfig", "Published DriverAppConfig for a zone", ["driver"], "Config",
   params=[pref("ZoneIdQuery")], ok=(200, "DriverAppConfig"))
op("get", "/driver/config/stream", "streamDriverConfig", "config_published events for the driver document", ["driver"], "Realtime",
   params=[pref("ZoneIdQuery")], content=sse("Server-sent events.", "ConfigEvent"))
op("get", "/driver/earnings", "getDriverEarnings", "Earnings per period", ["driver"], "Driver · Money",
   params=[q("period", {"type": "string", "enum": ["day", "week", "month"], "default": "week"}), pref("From"), pref("To")],
   ok=(200, "EarningsReport"))
op("get", "/driver/payouts", "listDriverPayouts", "Payout history", ["driver"], "Driver · Money",
   params=[pref("Cursor"), pref("Limit"), pref("From"), pref("To")], ok=(200, "PayoutPage"))
op("get", "/driver/profile", "getDriverProfile", "Own driver profile and status", ["driver"], "Driver · Account", ok=(200, "Driver"))
op("patch", "/driver/profile", "updateDriverProfile", "Update own profile / active vehicle", ["driver"], "Driver · Account",
   body="DriverProfileUpdate", ok=(200, "Driver"), mutation=True,
   desc="v0.18.12: language (sv | fr | en) saves the app language to the account, as the rider's PATCH /rider/profile does. v0.14.0: picking a car (vehicleId) whose Vehicle.requiredDocuments are not all approved → 409 documents_not_approved (reason vehicle_documents_not_approved, details vehicle:<type>).")
op("get", "/driver/vehicles", "listDriverVehicles", "Own vehicles", ["driver"], "Driver · Account",
   params=[pref("Cursor"), pref("Limit")], ok=(200, "VehiclePage"))
op("post", "/driver/vehicles", "addDriverVehicle", "Register a vehicle (status pending)", ["driver"], "Driver · Account",
   body="VehicleRequest", ok=(201, "Vehicle"), mutation=True)
op("get", "/driver/documents", "listDriverDocuments", "Own and vehicle documents", ["driver"], "Driver · Account",
   params=[pref("Cursor"), pref("Limit"), q("status", ref("DocumentStatus"), multi=True)], ok=(200, "DocumentPage"))
op("post", "/driver/documents", "uploadDriverDocument", "Upload a document (status in_review)", ["driver"], "Driver · Account",
   body="DocumentUpload", body_type="multipart/form-data", ok=(201, "Document"), mutation=True)

# ---- v0.5.3 (CONTRACT.md §14): onboarding, fleets, document files
FILE_CONTENT = {mt: {"schema": {"type": "string", "format": "binary"}} for mt in DO["documents"]["upload"]["mediaTypes"]}
op("post", "/driver/onboarding", "submitDriverOnboarding", "Send the sign-up details (once; the account goes on hold)", ["driver"], "Driver · Account",
   body="DriverOnboardingRequest", ok=(200, "Driver"), mutation=True,
   desc="v0.5.3. Validation reasons: under_age, country_not_open, invalid_city, invalid_email, terms_required, company_required, fleet_join_mismatch. "
        "A fleet account gets a Fleet in status pending; a driver account with fleetJoin is linked at once (the fleet must be approved: fleet_join_mismatch otherwise). "
        "accountStatus pending → on_hold.")
op("get", "/driver/fleet", "getDriverFleet", "Own fleet: company, drivers and cars", ["driver"], "Driver · Fleet", ok=(200, "FleetView"),
   desc="v0.5.3. The owner sees the code (after approval), the drivers and the cars; a member sees the company and the cars, no code and no drivers. No fleet → 404.")
op("post", "/driver/fleet/join", "joinFleet", "Ask to join a fleet with its code, the owner's name and e-mail", ["driver"], "Driver · Fleet",
   body="FleetJoinRequest", ok=(201, "FleetInvitation"), mutation=True,
   desc="v0.5.3. A pending driver_request the owner accepts or declines (contract.json#driverOnboarding.fleetInvitations); a pending request already open → 200 with it. "
        "Driver accounts only (a fleet account → 409 invalid_transition, fleet_account); already in a fleet → 409 invalid_transition (already_in_fleet).")
op("post", "/driver/fleet/invite", "inviteFleetDriver", "Owner: invite a driver by phone number", ["driver"], "Driver · Fleet",
   body="FleetInviteRequest", ok=(201, "FleetInvitation"), mutation=True,
   desc="v0.5.3. Owner of an approved fleet only (else 403 / 409 fleet_not_approved). A number already in a fleet → 409 invalid_transition (already_in_fleet); the owner's own number → 400. An open invite to the same number → 200 with it.")
op("get", "/driver/fleet/invitations", "listFleetInvitations", "Pending invitations: incoming and own", ["driver"], "Driver · Fleet",
   ok=(200, "FleetInvitationList"), desc="v0.5.3. A driver account: owner invites waiting for him and his own open request; an owner: his fleet's open requests and invites.")
for seg, opid, summ, d in [
    ("accept", "acceptFleetInvitation", "Accept (the driver an invite, the owner a request)", "Links the driver; his other pending invitations close. The driver on a trip → 409 (on_trip); already in a fleet → 409 (already_in_fleet); expired → 409 (invitation_expired)."),
    ("decline", "declineFleetInvitation", "Decline (the driver an invite, the owner a request)", "Closed; the sender is told."),
    ("cancel", "cancelFleetInvitation", "Cancel one's own request or invite", "Only the side that created it."),
]:
    op("post", f"/driver/fleet/invitations/{{invitationId}}/{seg}", opid, summ, ["driver"], "Driver · Fleet",
       params=[pref("InvitationId")], ok=(200, "FleetInvitation"), mutation=True, desc=f"v0.5.3. {d} Not pending → 409 invalid_transition.")
op("post", "/driver/fleet/leave", "leaveFleet", "Leave the fleet (not during a trip)", ["driver"], "Driver · Fleet", ok=(200, "Driver"), mutation=True,
   desc="v0.5.3. The car is released and the driver goes offline if online; on a trip → 409 invalid_transition (on_trip); the owner cannot leave (fleet_owner).")
op("post", "/driver/fleet/drivers/{driverId}/remove", "removeFleetDriver", "Owner: remove a driver from the fleet", ["driver"], "Driver · Fleet",
   params=[pref("DriverId")], ok=(204, None), mutation=True,
   desc="v0.5.3. Owner only (else 403). The driver's car is released and he goes offline; on a trip → 409 invalid_transition (on_trip).")
op("get", "/driver/fleet/earnings", "getFleetEarnings", "Owner: every driver's earnings in a period", ["driver"], "Driver · Fleet",
   params=[pref("From"), pref("To")], ok=(200, "FleetEarnings"), desc="v0.5.3. Owner only (else 403). Defaults to the current week (zone time).")
op("get", "/driver/documents/{documentId}/file", "getDriverDocumentFile", "The uploaded file (own or own fleet's)", ["driver"], "Driver · Account",
   params=[pref("DocumentId")], content=FILE_CONTENT, ok=(200, None), ok_desc="The file, with its media type.",
   desc="v0.5.3. The owner of the document, or the fleet owner for his drivers' and cars' documents; anyone else → 404.")
