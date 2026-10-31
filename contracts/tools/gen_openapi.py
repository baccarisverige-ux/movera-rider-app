"""Generates contracts/openapi.yaml (v0.4.4) from contract.json + hand-written surface.
Enums are read from contract.json so they stay byte-exact."""
import json, sys, yaml
from collections import OrderedDict

BASE = sys.argv[1]  # .../align/contracts
OUT = sys.argv[2]
C = json.load(open(f"{BASE}/contract.json"))


def ref(n): return {"$ref": f"#/components/schemas/{n}"}
def pref(n): return {"$ref": f"#/components/parameters/{n}"}
def rref(n): return {"$ref": f"#/components/responses/{n}"}
def nullable(n): return {"oneOf": [ref(n), {"type": "null"}]}
def arr(items, **kw): return {"type": "array", "items": items, **kw}
def obj(props, required=(), desc=None, addl=None, **kw):
    o = {"type": "object"}
    if desc: o["description"] = desc
    if required: o["required"] = list(required)
    o["properties"] = props
    if addl is not None: o["additionalProperties"] = addl
    o.update(kw)
    return o
def s(desc=None, **kw):
    o = {"type": "string", **kw}
    if desc: o["description"] = desc
    return o
def i(desc=None, **kw):
    o = {"type": "integer", **kw}
    if desc: o["description"] = desc
    return o
def b(desc=None):
    o = {"type": "boolean"}
    if desc: o["description"] = desc
    return o
def n(desc=None, **kw):
    o = {"type": "number", **kw}
    if desc: o["description"] = desc
    return o

ID_PATTERN = C["wire"]["ids"]["pattern"]
TS_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$"

# ---------------------------------------------------------------- schemas
S = OrderedDict()

S["Id"] = s("Opaque server-minted id. Clients never invent a tripId.", pattern=ID_PATTERN, examples=["trp_8f2c1a"])
S["Timestamp"] = s("RFC 3339 instant in UTC with a literal Z.", format="date-time", pattern=TS_PATTERN, examples=["2026-10-19T08:30:00Z"])
S["DurationSeconds"] = i("Duration in whole seconds.", minimum=0)
S["CurrencyCode"] = s("ISO 4217 alphabetic code. Minor-unit exponent comes from ISO 4217 (SEK/EUR 2, TND 3).",
                      pattern="^[A-Z]{3}$", examples=list(C["currencies"].keys()),
                      **{"x-exponents": {k: v["exponent"] for k, v in C["currencies"].items()}})
S["Money"] = obj({"amountMinor": i("Amount in the currency's minor unit (öre, cent, millime). May be negative for adjustments/refunds."),
                  "currency": ref("CurrencyCode")},
                 ["amountMinor", "currency"], "Money on the wire. No floats, no display strings.", addl=False,
                 examples=[{"amountMinor": 12675, "currency": "SEK"}, {"amountMinor": 12500, "currency": "TND"}])
S["CategoryId"] = s("Category id from the admin Pricing catalog. Seed ids are listed in x-seed; aliases `movera` → `economy` and (v0.6.0) `kids` → `child_seat` are accepted on read for one release.",
                    pattern=C["categories"]["pattern"], examples=C["categories"]["seed"],
                    **{"x-seed": C["categories"]["seed"], "x-aliases": C["categories"]["aliases"]})
S["PaymentMethod"] = s("Payment method kind. A saved card is `card` + `paymentMethodId`. `wallet` is the rider's balance in one currency (used first); "
                       "v0.3 ids are accepted on read as x-aliases for one release.", enum=C["paymentMethods"],
                       **{"x-aliases": {k: v for k, v in C["paymentMethodAliases"].items() if k != "note"}})
S["ZonePaymentMethod"] = s(C["zonePaymentMethods"]["note"], enum=C["zonePaymentMethods"]["values"])
S["Language"] = s(C["languages"]["note"], enum=C["languages"]["values"])
S["CountryCode"] = s("ISO 3166-1 alpha-2 country of the zone.", pattern="^[A-Z]{2}$", examples=list(C["configDefaults"]["countries"].keys()))
S["Place"] = obj({"address": s(maxLength=512), "lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180)},
                 ["lat", "lng"], "A place on a route: pickup, dropoff or stop (stops are ordered).")
S["GeoFix"] = obj({"lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180),
                   "accuracy": n("Horizontal accuracy, metres.", minimum=0),
                   "heading": n("Degrees clockwise from north.", minimum=0, exclusiveMaximum=360),
                   "speedMps": n("Ground speed, metres per second (v0.5.0).", minimum=0),
                   "moving": b("The driver app's stopped / driving judgement (contract.json#driverMotion, v0.5.0): true after movingSpeedMps for hysteresisSeconds. Drives the offer limits while driving."),
                   "measuredAt": ref("Timestamp")},
                  ["lat", "lng", "accuracy", "measuredAt"], "Device GPS fix (driver location only).")

# --- enums from contract.json
ts = C["tripStatus"]
S["TripStatus"] = s("Single trip lifecycle. Payment and rating are NOT statuses (see PaymentStatus / RatingStatus).",
                    enum=ts["values"], **{"x-terminal": ts["terminal"], "x-driver-assigned": ts["driverAssigned"],
                                          "x-rider-onboard": ts["riderOnboard"]})
S["TripKind"] = s(enum=["live", "scheduled"])
S["PaymentStatus"] = s("Payment machine; changes after `completed` via `payment_updated`.", enum=C["paymentStatus"],
                       **{"x-transitions": C["paymentTransitions"]})
S["RatingStatus"] = s("Rating machine; changes after `completed` (rider also after a trip the rider ended early) via `rating_updated`. "
                      "Who may rate after what: x-rating-allowed (contract.json#ratingAllowed).", enum=C["ratingStatus"],
                      **{"x-transitions": C["ratingTransitions"], "x-rating-allowed": C["ratingAllowed"]["rules"]})
S["DriverAccountStatus"] = s("Account state, owned by Admin.", enum=C["driverAccountStatus"])
S["DriverOnlineStatus"] = s("Availability state, owned by the backend from driver commands.", enum=C["driverOnlineStatus"])
S["OfferKind"] = s(enum=C["offerKind"])
S["OfferStatus"] = s(enum=C["offerStatus"])
S["Actor"] = s("Who issued a command. Always derived from the bearer token, never from the body.", enum=C["actors"])
cr = C["cancelReasons"]
union = []
for g in cr.values():
    for code in g:
        if code not in union: union.append(code)
S["CancelReasonCode"] = s("Union of every cancel reason code in contract.json#cancelReasons. The server validates the code against the caller's actor/group (x-groups).",
                          enum=union, **{"x-groups": cr})
grp_names = {"rider": "RiderCancelReasonCode", "driverBeforeTrip": "DriverBeforeTripCancelReasonCode",
             "driverDuringTrip": "DriverDuringTripCancelReasonCode", "driverNextTrip": "DriverNextTripCancelReasonCode",
             "scheduled": "ScheduledCancelReasonCode", "noShow": "NoShowReasonCode",
             "admin": "AdminCancelReasonCode", "system": "SystemCancelReasonCode"}
for g, name in grp_names.items():
    S[name] = s(f"contract.json#cancelReasons.{g}", enum=cr[g])
S["ErrorCode"] = s(enum=C["errors"]["codes"])
S["RealtimeKind"] = s("Trip event kinds. After a terminal status only x-after-terminal kinds pass the client gate.",
                      enum=C["realtime"]["kinds"], **{"x-after-terminal": C["realtime"]["afterTerminal"]})
FL = C["fareLines"]
S["FareLineCode"] = s("Fare line codes (contract.json#fareLines). x-rider lines make the rider's fare; x-driver-only lines (pickup_pay, driver_bonus) are "
                      "shown to the driver and admin only and never paid by the rider. v0.4 documents named the rider's pickup line pickup_pay: x-aliases.",
                      enum=FL["rider"] + FL["driverOnly"], **{"x-rider": FL["rider"], "x-driver-only": FL["driverOnly"],
                                                               "x-aliases": {k: v for k, v in FL["aliases"].items() if k != "note"}})
S["FareLine"] = obj({"code": ref("FareLineCode"), "amount": ref("Money"),
                     "sourceTripId": {"allOf": [ref("Id")], "description": "outstanding_fee only: the earlier trip whose unpaid fee this is (v0.5.1, CONTRACT.md §3.7)."}},
                    ["code", "amount"], "One fare line; the meaning of each code: contract.json#fareLines.meaning (v0.5.1).")

# --- trip
S["QuoteRef"] = obj({"quoteId": ref("Id"), "total": ref("Money"), "expiresAt": ref("Timestamp")}, ["quoteId", "total", "expiresAt"])
S["Waiting"] = obj({"arrivedAt": ref("Timestamp"), "freeUntil": ref("Timestamp"), "noShowAt": ref("Timestamp"),
                    "chargedSeconds": ref("DurationSeconds")}, ["arrivedAt", "freeUntil", "noShowAt", "chargedSeconds"])
S["Cancellation"] = obj({"actor": ref("Actor"), "reasonCode": ref("CancelReasonCode"), "at": ref("Timestamp"),
                         "fee": {"description": "Rider cancel / no-show fee. null = not decided yet or none.", **nullable("Money")},
                         "note": s(maxLength=1000),
                         "feeStatus": s("v0.5.1 (CONTRACT.md §3.7): owed = an unpaid cash fee, in Rider.outstanding and the next trip's outstanding_fee line.", enum=C["outstandingFee"]["feeStatus"])},
                        ["actor", "reasonCode", "at", "fee"])
S["VehicleSummary"] = obj({"vehicleId": ref("Id"), "make": s(), "model": s(), "color": s(), "plate": s(),
                           "categoryId": ref("CategoryId")})
S["DriverSummary"] = obj({"driverId": ref("Id"), "firstName": s(minLength=1), "rating": n(minimum=0, maximum=5),
                          "tripCount": i(minimum=0), "photoUrl": s(format="uri"), "vehicle": ref("VehicleSummary")},
                         ["driverId", "firstName", "vehicle"], "Driver as shown to the rider.")
S["TripProjection"] = obj(OrderedDict([
    ("tripId", ref("Id")),
    ("rideId", {"allOf": [ref("Id")], "readOnly": True, "deprecated": True,
                "description": "Legacy alias of tripId, echoed during migration. Read-only; never sent by clients."}),
    ("status", ref("TripStatus")),
    ("version", i("Per-trip aggregate version; send as expectedVersion.", minimum=1)),
    ("sequence", i("Last realtime sequence included in this projection (resync cursor for `after`).", minimum=0)),
    ("kind", ref("TripKind")),
    ("scheduledAt", {"allOf": [ref("Timestamp")], "description": "Pickup time for kind=scheduled (UTC)."}),
    ("createdAt", ref("Timestamp")), ("updatedAt", ref("Timestamp")),
    ("acceptedAt", {"oneOf": [ref("Timestamp"), {"type": "null"}],
                    "description": "When a driver accepted; null before. The live free-cancel clock (FeeRule.freeMin) counts from it."}),
    ("riderId", ref("Id")), ("driverId", ref("Id")), ("vehicleId", ref("Id")), ("zoneId", ref("Id")),
    ("categoryId", ref("CategoryId")),
    ("pickup", ref("Place")), ("dropoff", ref("Place")), ("stops", arr(ref("Place"), description="Ordered intermediate stops.")),
    ("quote", ref("QuoteRef")),
    ("fare", {"allOf": [ref("Money")], "description": "Current authoritative fare (rider pays)."}),
    ("fareLines", arr(ref("FareLine"))),
    ("driverEarnings", ref("Money")), ("commission", ref("Money")),
    ("driverBonus", {"allOf": [ref("Money")], "description": "Movera-paid extra for the driver (admin / driver view only). Never part of the rider's fare."}),
    ("pickupPay", {"allOf": [ref("Money")], "description": "Driver pickup pay Movera pays for this trip (admin / driver view only, v0.5.0, contract.json#pickupPay). Never part of the rider's fare; the rider's fixed pickup fee is the pickup_fee fare line."}),
    ("paymentMethod", ref("PaymentMethod")), ("paymentMethodId", ref("Id")),
    ("paymentStatus", ref("PaymentStatus")), ("ratingStatus", ref("RatingStatus")),
    ("driver", ref("DriverSummary")), ("driverLocation", ref("GeoFix")), ("etaSeconds", ref("DurationSeconds")),
    ("waiting", ref("Waiting")), ("cancellation", ref("Cancellation")),
    ("pinRequired", b("Driver must verify the rider PIN before `board`.")),
    ("searchStep", {"allOf": [ref("SearchStep")], "description": "v0.5.1 (CONTRACT.md §3.6): the latest rider-waiting step while searching (rider view). Changing it does not change version."}),
    ("stopVisits", arr(ref("StopVisit"), description="v0.7.1 (contract.json#stopWaits): the driver's arrived-at-stop / leaving-stop per extra stop, in stop order.")),
    ("driverSilentAlert", {"allOf": [ref("DriverSilentAlert")], "description": "v0.7.0 (CONTRACT.md §15), admin view only: the rider is on board and the server has had no driver position for 30 min (\"car lost\"). Gone when positions come back. Changing it does not change version."}),
]), ["tripId", "status", "version", "sequence", "kind", "createdAt", "updatedAt", "riderId", "zoneId", "categoryId",
     "pickup", "dropoff", "stops", "fare", "paymentMethod", "ratingStatus", "pinRequired"],
    "Authoritative trip state. Field visibility depends on the actor (e.g. driverEarnings/commission are not shown to riders). "
    "v0.5.1: fare and fareLines follow contract.json#pricing (CONTRACT.md §3.5); commission is Movera's share of the fare (fare − driverEarnings).")

S["DriverSilentAlert"] = obj({"kind": s(enum=["driver_silent"]), "silentSince": ref("Timestamp"), "lastFixAt": {"type": ["string", "null"], "format": "date-time"},
                              "at": ref("Timestamp"), "autoFailAt": ref("Timestamp")},
                             ["kind", "silentSince", "at", "autoFailAt"],
                             "v0.7.0: documents the server's alert of 2026-10-26: no position for 30 min with the rider on board; the trip fails with no charge at autoFailAt (3 h). It also opens a driver_silent incident.")
S["Offer"] = obj(OrderedDict([
    ("offerId", ref("Id")), ("tripId", ref("Id")), ("kind", ref("OfferKind")), ("status", ref("OfferStatus")),
    ("version", i(minimum=1)), ("expiresAt", ref("Timestamp")),
    ("fare", {"allOf": [ref("Money")], "description": "Trip fare as the driver sees it, driverBonus included."}),
    ("driverEarnings", {"allOf": [ref("Money")], "description": "Driver net, driverBonus included."}),
    ("pickupPay", ref("Money")), ("fareBoost", ref("Money")),
    ("driverBonus", {"allOf": [ref("Money")], "description": "Movera-paid extra (admin \"add money to trip\"), already in fare and driverEarnings. The rider never pays it."}),
    ("priority", {"type": "boolean", "default": False, "description": "Show the \"Priority\" badge (red) on the offer card."}),
    ("source", {"type": "string", "enum": ["system", "admin"], "default": "system",
                "description": "admin = direct assign (kind=assigned, exclusive) or radar group (kind=radar, groupId)."}),
    ("groupId", {"allOf": [ref("Id")], "description": "Admin radar group this offer belongs to (contract.json#adminDispatch.radarGroup)."}),
    ("pickup", ref("Place")), ("dropoff", ref("Place")), ("stops", arr(ref("Place"))),
    ("categoryId", ref("CategoryId")), ("paymentMethod", ref("PaymentMethod")),
    ("pickupEtaSeconds", ref("DurationSeconds")), ("pickupMeters", i(minimum=0)),
    ("tripSeconds", ref("DurationSeconds")), ("tripMeters", i(minimum=0)),
    ("riderRating", n(minimum=0, maximum=5)), ("riderTrips", i(minimum=0)),
    ("scheduledAt", ref("Timestamp")),
    ("reasonCode", s("Exclusive reason id (driver.offers.exclusiveReasons[].id) for kind=exclusive/assigned.",
                     pattern="^[a-z][a-z0-9_-]{0,63}$")),
]), ["offerId", "tripId", "kind", "status", "version", "expiresAt", "fare", "driverEarnings", "pickup", "dropoff",
     "stops", "categoryId", "paymentMethod", "pickupEtaSeconds", "pickupMeters", "tripSeconds", "tripMeters"],
    "One driver's offer for a trip. One trip has many offers; offerId is never a tripId.")

S["Quote"] = obj(OrderedDict([
    ("quoteId", ref("Id")), ("categoryId", ref("CategoryId")), ("total", ref("Money")), ("fareLines", arr(ref("FareLine"))),
    ("expiresAt", ref("Timestamp")), ("pickup", ref("Place")), ("dropoff", ref("Place")), ("stops", arr(ref("Place"))),
    ("surgeMultiplier", n("The multiplier this quote was priced with; it stays with the quote (contract.json#surge).", minimum=1)),
    ("surge", ref("QuoteSurge")), ("etaSeconds", ref("DurationSeconds")),
]), ["quoteId", "categoryId", "total", "fareLines", "expiresAt", "pickup", "dropoff", "stops"])
S["RouteQuote"] = obj({"routeQuoteId": ref("Id"), "tripId": ref("Id"),
                       "total": {"allOf": [ref("Money")], "description": "Booked fare + the rider's offer raises + distance price of "
                                 "(new route km − booked route km, the booked route going through the booked stops) + the stop fee "
                                 "for each stop that was not booked; never below half of (booked fare + raises). CONTRACT.md §3, v0.4.3."},
                       "difference": {"allOf": [ref("Money")], "description": "total − current fare (may be negative). Re-quoting "
                                      "the route the trip already has gives 0; a route change never refunds an offer raise."},
                       "fareLines": arr(ref("FareLine")), "dropoff": ref("Place"), "stops": arr(ref("Place")),
                       "expiresAt": ref("Timestamp")},
                      ["routeQuoteId", "tripId", "total", "difference", "dropoff", "stops", "expiresAt"],
                      "Price for a route change after request; apply with PATCH /trips/{tripId}. Priced from the booking "
                      "(owner decision 5, v0.4.3): a booked stop is counted once and offer raises stay.")

S["Rider"] = obj({"riderId": ref("Id"), "firstName": s(), "phone": s(pattern=r"^\+[1-9]\d{6,14}$"), "email": s(format="email"),
                  "rating": n(minimum=0, maximum=5), "status": s(enum=["active", "suspended"]), "version": i(minimum=1),
                  "outstanding": {"oneOf": [ref("Money"), {"type": "null"}], "description": "v0.5.1 (CONTRACT.md §3.7): unpaid cash fees the rider owes (positive); null or missing = none. On GET /rider/profile and the admin rider view."},
                  "language": s("v0.5.1: the rider's app language (also sets the reverse-geocode language).", pattern="^[a-z]{2}(-[A-Z]{2})?$"),
                  "consents": {"allOf": [ref("RiderConsents")], "description": "v0.5.1: the rider's message consents."}},
                 ["riderId", "firstName", "status", "version"])
S["DocumentStatus"] = s(enum=["missing", "in_review", "approved", "rejected", "expired"])
S["DocumentType"] = s("Document type id, e.g. driver_license, insurance, vehicle_registration, national_id, taxi_permit.",
                      pattern="^[a-z][a-z0-9_]{1,63}$")
S["DocumentSummary"] = obj({"documentId": ref("Id"), "type": ref("DocumentType"), "status": ref("DocumentStatus"),
                            "expiresAt": ref("Timestamp")}, ["documentId", "type", "status"])
S["Document"] = obj({"documentId": ref("Id"), "ownerId": {"allOf": [ref("Id")], "description": "driverId or vehicleId"},
                     "type": ref("DocumentType"), "status": ref("DocumentStatus"), "expiresAt": ref("Timestamp"),
                     "fileUrl": s(format="uri", readOnly=True), "reviewNote": s(), "version": {"type": "integer", "minimum": 1}},
                    ["documentId", "ownerId", "type", "status", "version"])
S["Driver"] = obj({"driverId": ref("Id"), "accountStatus": ref("DriverAccountStatus"), "onlineStatus": ref("DriverOnlineStatus"),
                   "moving": b("Mirror of the latest GeoFix.moving the driver app sent (contract.json#driverMotion, v0.5.0); decides the offer limits while driving."),
                   "firstName": s(), "rating": n(minimum=0, maximum=5), "zoneIds": arr(ref("Id")),
                   "categoryIds": arr(ref("CategoryId")), "vehicleId": ref("Id"), "documents": arr(ref("DocumentSummary")),
                   "activeTripId": ref("Id"), "scheduledRides": {"allOf": [ref("DriverScheduledRides")], "description": C["driverHome"]["scheduledRidesPerDriver"]}, "version": i(minimum=1),
                   "location": {"allOf": [ref("GeoFix")], "description": "v0.5.1, admin view only: the latest fix (CONTRACT.md §12)."},
                   "lastFixAt": {"allOf": [ref("Timestamp")], "description": "v0.5.1, admin view only: when the latest fix was received."}},
                  ["driverId", "accountStatus", "onlineStatus", "firstName", "zoneIds", "categoryIds", "documents", "version"])
S["DriverScheduledRides"] = obj({"on": b("false = no new reservations for this driver; true = on, and the late-cancel pause is skipped while it lasts."),
                                 "until": {"description": "When the admin's choice ends; null = until an admin changes it.", **nullable("Timestamp")}},
                                ["on"], "Owner decision 2 (v0.4.2): an admin's reservations on/off for this one driver (CONTRACT.md §6.1). "
                                "Missing = no admin choice; the zone switch and the late-cancel pause decide. Accepted reservations always stay.")
S["VehicleStatus"] = s(enum=["pending", "approved", "rejected", "blocked"])
S["Vehicle"] = obj({"vehicleId": ref("Id"), "make": s(), "model": s(), "year": i(minimum=1950, maximum=2100), "color": s(),
                    "plate": s(), "seats": i(minimum=1, maximum=20), "categoryIds": arr(ref("CategoryId")),
                    "status": ref("VehicleStatus"), "version": i(minimum=1)},
                   ["vehicleId", "make", "model", "year", "color", "plate", "seats", "categoryIds", "status", "version"])
# ---- v0.5.3 (CONTRACT.md §14): driver onboarding, fleets and documents
DO = C["driverOnboarding"]
S["DriverAccountType"] = s("v0.5.3: driver = works for a fleet; fleet = a company with cars and drivers (its owner may drive too).",
                           enum=DO["accountTypes"])
S["DriverCountry"] = s("v0.5.3: ISO 3166-1 alpha-2 of the countries the driver app offers (contract.json#driverOnboarding.countries); "
                       "only an open one is accepted on POST /driver/onboarding (else 400 invalid_request, reason country_not_open).",
                       enum=list(DO["countries"].keys()))
S["FleetStatus"] = s("pending until an admin reviews the fleet; approved gives it a code.", enum=["pending", "approved", "rejected", "blocked"])
S["FleetLink"] = obj({"fleetId": ref("Id"), "name": s(), "role": s(enum=["owner", "member"]), "status": ref("FleetStatus"),
                      "linkedAt": ref("Timestamp")}, ["fleetId", "name", "role", "status", "linkedAt"],
                     "v0.5.3: the fleet this driver belongs to (owner = the fleet account itself).")
S["Fleet"] = obj({"fleetId": ref("Id"), "name": s(), "orgNumber": s("Organisationsnummer (SE) or SIREN / SIRET (FR)."), "address": s(),
                  "country": ref("DriverCountry"), "cityId": s(), "ownerDriverId": ref("Id"), "ownerName": s("The owner's first and last name."),
                  "ownerEmail": s("Owner and admin views only.", format="email"), "status": ref("FleetStatus"),
                  "code": s("The join code (contract.json#driverOnboarding.fleetCode); only after approval, and only to the owner and admins.",
                            pattern="^MV-[A-Z2-9]{5}$"),
                  "driverCount": i(minimum=0), "vehicleCount": i(minimum=0), "createdAt": ref("Timestamp"), "version": i(minimum=1)},
                 ["fleetId", "name", "orgNumber", "country", "cityId", "ownerDriverId", "ownerName", "status", "driverCount", "vehicleCount",
                  "createdAt", "version"], "v0.5.3: a fleet (company) account's company.")
S["FleetDriver"] = obj({"driverId": ref("Id"), "firstName": s(), "lastName": s(), "accountStatus": ref("DriverAccountStatus"),
                        "onlineStatus": ref("DriverOnlineStatus"), "vehicleId": ref("Id"), "linkedAt": ref("Timestamp")},
                       ["driverId", "firstName", "accountStatus", "onlineStatus", "linkedAt"])
S["FleetInvitationStatus"] = s(enum=["pending", "accepted", "declined", "cancelled", "expired"])
S["FleetInvitation"] = obj({"invitationId": ref("Id"), "fleetId": ref("Id"), "fleetName": s(),
                            "direction": s("driver_request: the driver asked with the code; owner_invite: the owner invited a phone number.", enum=["driver_request", "owner_invite"]),
                            "driverId": {"allOf": [ref("Id")], "description": "The driver concerned; missing while an owner_invite waits for a number without an account."},
                            "driverName": s(), "phone": s("owner_invite: the invited number (owner and admin views)."),
                            "status": ref("FleetInvitationStatus"), "createdAt": ref("Timestamp"), "expiresAt": ref("Timestamp"),
                            "decidedAt": ref("Timestamp"), "version": i(minimum=1)},
                           ["invitationId", "fleetId", "fleetName", "direction", "status", "createdAt", "expiresAt", "version"],
                           "v0.5.3 (contract.json#driverOnboarding.fleetInvitations): one side asks, the other accepts.")
S["FleetInvitationList"] = obj({"items": arr(ref("FleetInvitation"))}, ["items"])
S["FleetInviteRequest"] = obj({"phone": s("E.164; the driver's sign-in number.", pattern=r"^\+[1-9]\d{6,14}$")}, ["phone"], "v0.5.3: the owner invites a number.")
S["FleetView"] = obj({"fleet": ref("Fleet"), "drivers": arr(ref("FleetDriver")), "vehicles": arr(ref("Vehicle")),
                      "invitations": arr(ref("FleetInvitation"), description="v0.5.3: the pending invitations and requests (owner and admins; a member gets none).")},
                     ["fleet", "drivers", "vehicles"],
                     "v0.5.3: the fleet with its drivers (owner and admins; a member gets an empty list) and its cars.")
S["FleetDriverEarnings"] = obj({"driverId": ref("Id"), "firstName": s(), "lastName": s(), "trips": i(minimum=0), "earnings": ref("Money")},
                               ["driverId", "firstName", "trips", "earnings"])
S["FleetEarnings"] = obj({"from": ref("Timestamp"), "to": ref("Timestamp"), "items": arr(ref("FleetDriverEarnings")), "total": ref("Money")},
                         ["from", "to", "items", "total"], "v0.5.3: every driver's earnings in the period, for the fleet owner.")
PF = C["driverHome"]["performance"]
S["DriverPerformance"] = obj(OrderedDict([
    ("windowDays", {**i(minimum=1), "default": PF["windowDays"]}), ("from", ref("Timestamp")),
    ("offersAnswerable", i(minimum=0)), ("offersAccepted", i(minimum=0)), ("tripsCancelled", i(minimum=0)), ("ratingCount", i(minimum=0)),
    ("acceptancePct", {"type": ["integer", "null"], "minimum": 0, "maximum": 100, "description": f"null while offersAnswerable < {PF['minOffers']}."}),
    ("cancellationPct", {"type": ["integer", "null"], "minimum": 0, "maximum": 100, "description": f"null while offersAccepted < {PF['minTrips']}."}),
    ("rating", {"type": ["number", "null"], "minimum": 0, "maximum": 5, "description": f"null while ratingCount < {PF['minRatings']}."}),
]), ["windowDays", "from", "offersAnswerable", "offersAccepted", "tripsCancelled", "ratingCount", "acceptancePct", "cancellationPct", "rating"], "v0.18.4 (G3-D2): " + PF["note"])
S["Driver"]["properties"].update({
    "performance": {"allOf": [ref("DriverPerformance")], "description": "v0.18.4 (G3-D2): on GET /driver/profile and GET /admin/drivers/{driverId} only."},
    "outsideArea": b("v0.18.4 (G3-R2), driver view: the latest position is outside all of Driver.zoneIds; missing with no position. The app shows contract.json#driverHome.outsideArea.text."),
    "areaZones": arr(ref("AreaZone"), description="v0.18.4: with outsideArea true, the driver's own zones (names for the popup)."),
    "accountType": {"allOf": [ref("DriverAccountType")], "description": "v0.5.3; missing before POST /driver/onboarding."},
    "lastName": s("v0.5.3"), "dateOfBirth": s("v0.5.3: YYYY-MM-DD; at least contract.json#driverOnboarding.minAge years.", format="date"),
    "email": s("v0.5.3", format="email"), "country": {"allOf": [ref("DriverCountry")], "description": "v0.5.3"},
    "cityId": s("v0.5.3: a cityId of the country (contract.json#driverOnboarding.countries); sets zoneIds."),
    "language": s("v0.5.3: the driver's app language.", pattern="^[a-z]{2}(-[A-Z]{2})?$"),
    "termsAcceptedAt": {"allOf": [ref("Timestamp")], "description": "v0.5.3: when the terms were accepted (POST /driver/onboarding)."},
    "fleet": {"allOf": [ref("FleetLink")], "description": "v0.5.3: the fleet this driver belongs to; missing = none (a driver account waits for a fleet)."},
    "payoutTo": s("v0.5.3: who Movera pays (contract.json#driverOnboarding.payouts): fleet for a driver linked to a fleet, self for a fleet account.",
                  enum=["self", "fleet"]),
    "requiredDocuments": arr(ref("DocumentType"), description="v0.5.3: the person's documents this account must have approved (contract.json#driverOnboarding.documents.required[country].driver)."),
    "requiredFleetDocuments": arr(ref("DocumentType"), description="v0.5.3: fleet accounts only: the company's documents (…required[country].fleet)."),
    "pendingFleetInvitations": i("v0.5.3: pending invitations waiting for this account's answer (a driver's incoming invites, or an owner's incoming requests), for the badge.", minimum=0),
})
S["Vehicle"]["properties"].update({
    "fleetId": {"allOf": [ref("Id")], "description": "v0.5.3: the fleet that owns the car."},
    "driverId": {"allOf": [ref("Id")], "description": "v0.5.3: the driver who has the car picked now (PATCH /driver/profile { vehicleId }); missing = free."},
    "inUse": b("v0.5.3: that driver is online or on a trip, so another driver cannot pick the car (409 conflict, vehicle_in_use)."),
    "documents": arr(ref("DocumentSummary"), description="v0.5.3: the car's documents."),
    "requiredDocuments": arr(ref("DocumentType"), description="v0.5.3: contract.json#driverOnboarding.documents.required[country].vehicle."),
})
S["Document"]["properties"].update({
    "fileName": s("v0.5.3: the uploaded file's name, for display."), "mediaType": s("v0.5.3: one of contract.json#driverOnboarding.documents.upload.mediaTypes."),
    "uploadedAt": {"allOf": [ref("Timestamp")], "description": "v0.5.3"},
    "reviewedAt": {"allOf": [ref("Timestamp")], "description": "v0.5.3: when an admin decided."},
})
S["Document"]["properties"]["fileUrl"]["description"] = ("v0.5.3: the path of the file endpoint (GET /driver/documents/{documentId}/file for the owner, "
                                                          "GET /admin/documents/{documentId}/file for admins), never a public link; missing for terms and admin checks.")
S["PaymentIntent"] = obj({"paymentId": ref("Id"), "tripId": ref("Id"), "amount": ref("Money"), "method": ref("PaymentMethod"),
                          "paymentMethodId": ref("Id"), "purpose": s(enum=["trip", "wallet_topup", "tip"]),
                          "status": ref("PaymentStatus"), "failureCode": s(),
                          "clientSecret": s("PSP hand-off token for client confirmation; never logged.", writeOnly=False),
                          "createdAt": ref("Timestamp")},
                         ["paymentId", "amount", "method", "status"],
                         "tripId is required for purpose=trip|tip and absent for wallet_topup.")
S["RefundStatus"] = s(enum=["pending_approval", "done", "rejected"])
S["Refund"] = obj({"refundId": ref("Id"), "paymentId": ref("Id"), "tripId": ref("Id"), "amount": ref("Money"),
                   "reason": s(minLength=1), "status": ref("RefundStatus"), "approvalId": ref("Id"),
                   "createdAt": ref("Timestamp")}, ["refundId", "paymentId", "amount", "reason", "status"])
S["WalletEntry"] = obj({"entryId": ref("Id"), "ownerId": ref("Id"), "amount": ref("Money"),
                        "kind": s(enum=["topup", "charge", "refund", "payout", "adjustment"]), "tripId": ref("Id"),
                        "at": ref("Timestamp")}, ["entryId", "ownerId", "amount", "kind", "at"])
S["Wallet"] = obj({"ownerId": ref("Id"), "balance": ref("Money"), "updatedAt": ref("Timestamp")},
                  ["ownerId", "balance", "updatedAt"], "Server-owned balance; clients never compute it.")
S["SavedPaymentMethod"] = obj({"paymentMethodId": ref("Id"), "method": ref("PaymentMethod"),
                               "brand": s(examples=["visa", "mastercard"]), "last4": s(pattern=r"^\d{4}$"),
                               "expMonth": i(minimum=1, maximum=12), "expYear": i(minimum=2000),
                               "isDefault": b()}, ["paymentMethodId", "method", "isDefault"])
S["Rating"] = obj({"tripId": ref("Id"), "from": s(enum=["rider", "driver"]),
                   "stars": i("Whole stars (contract.json#ratings).", minimum=C["ratings"]["min"], maximum=C["ratings"]["max"]), "tags": arr(s(pattern="^[a-z][a-z0-9_]{0,63}$")),
                   "comment": s(maxLength=2000)}, ["tripId", "from", "stars", "tags"])
RT_TAGS = C["ratings"]["tags"]
S["RatingTag"] = s("v0.9.0: a rating tag code (contract.json#ratings.tags): aboutDriver when the rider rates, aboutRider when the driver rates.",
                   enum=RT_TAGS["aboutDriver"] + RT_TAGS["aboutRider"])
S["AdminRating"] = obj(OrderedDict([
    ("tripId", ref("Id")), ("from", s(enum=["rider", "driver"])),
    ("stars", i(minimum=C["ratings"]["min"], maximum=C["ratings"]["max"])), ("tags", arr(ref("RatingTag"))), ("comment", s(maxLength=2000)),
    ("at", ref("Timestamp")), ("riderId", ref("Id")), ("riderName", s()), ("driverId", ref("Id")), ("driverName", s()), ("zoneId", ref("Id")),
    ("hidden", b("Hidden by an admin: it does not count in the average nor in the low-rating risk signal.")),
    ("hiddenBy", ref("Id")), ("hiddenAt", ref("Timestamp")), ("hideReason", s(maxLength=500))]),
    ["tripId", "from", "stars", "tags", "at", "hidden"], "v0.9.0: a rating as Admin › Reviews lists it (GET /admin/ratings).")
S["RatingModerationCommand"] = obj({"reason": s(minLength=1, maxLength=500)}, ["reason"], "v0.9.0: why the rating is hidden or shown again (written in the audit).")
S["Notification"] = obj({"notificationId": ref("Id"), "audience": s(enum=["rider", "driver"]),
                         "kind": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "title": s(), "body": s(), "at": ref("Timestamp"),
                         "read": b(), "tripId": ref("Id"), "deepLink": s()},
                        ["notificationId", "audience", "kind", "title", "body", "at", "read"])
S["Message"] = obj({"messageId": ref("Id"), "tripId": ref("Id"), "from": s(enum=["rider", "driver", "support"]),
                    "text": s(minLength=1, maxLength=2000), "at": ref("Timestamp")},
                   ["messageId", "tripId", "from", "text", "at"],
                   "A trip chat message. v0.13.0 (CONTRACT.md §23): kept 90 days (longer when the trip has a safety case); never carries a phone number.")
S["TripCall"] = obj({"tripId": ref("Id"), "proxyNumber": s("v0.13.0: the masked number to dial (E.164); the provider bridges to the other side.", pattern=r"^\+[1-9][0-9]{6,14}$"),
                     "expiresAt": ref("Timestamp")}, ["tripId", "proxyNumber", "expiresAt"],
                    "v0.13.0: a masked call between the trip's rider and driver (contract.json#chat.call).")
S["SavedPlace"] = obj({"placeId": ref("Id"), "label": s(minLength=1, maxLength=80), "kind": s(enum=["home", "work", "other"]),
                       "place": ref("Place")}, ["placeId", "label", "kind", "place"])
S["SupportTicket"] = obj({"ticketId": ref("Id"), "tripId": ref("Id"), "openedBy": ref("Actor"), "riderId": ref("Id"),
                          "driverId": ref("Id"), "category": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "subject": s(),
                          "status": s(enum=["open", "pending", "resolved", "closed"]),
                          "priority": s(enum=["low", "normal", "high", "urgent"]),
                          "createdAt": ref("Timestamp"), "updatedAt": ref("Timestamp"),
                          "zoneId": {"allOf": [ref("Id")], "description": "v0.9.0: the trip's zone, else the person's first zone; admins see tickets of their zones."},
                          "lastMessageAt": ref("Timestamp"),
                          "messages": arr(ref("TicketMessage"), description="v0.9.0: only on GET /support/tickets/{ticketId} and GET /admin/tickets/{ticketId}, oldest first.")},
                         ["ticketId", "openedBy", "category", "subject", "status", "createdAt", "updatedAt"])
S["TicketMessage"] = obj({"messageId": ref("Id"), "from": s(enum=["rider", "driver", "support"]), "text": s(minLength=1, maxLength=5000),
                          "at": ref("Timestamp"), "adminName": s("The answering admin's name (from = support).")},
                         ["messageId", "from", "text", "at"], "v0.9.0: one message on a support ticket.")
S["TicketReplyCommand"] = obj({"text": s(minLength=1, maxLength=5000), "status": s("The ticket's status after the answer (default pending: waiting for the person).",
                                                                                  enum=C["support"]["replyStatuses"])},
                              ["text"], "v0.9.0: Admin › Support answers a ticket.")
SF = C["safety"]
S["IncidentPosition"] = obj({"lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180),
                             "accuracyM": n("Horizontal accuracy, metres.", minimum=0), "at": ref("Timestamp")},
                            ["lat", "lng", "at"], "v0.7.0: a phone's GPS position, measured once (CONTRACT.md §15).")
S["Incident"] = obj(OrderedDict([
    ("incidentId", ref("Id")), ("tripId", ref("Id")),
    ("kind", s("v0.7.0: contract.json#safety.incidentKinds (sos, driver_silent; v0.12.0 ride_check). Older rows may hold other snake_case kinds.",
               pattern="^[a-z][a-z0-9_]{0,63}$", examples=SF["incidentKinds"])),
    ("severity", s(enum=["low", "medium", "high", "critical"])),
    ("status", s("open = New, investigating = Taken, resolved = Solved, dismissed = False alarm (contract.json#safety.statusLabels).",
                 enum=SF["statuses"])),
    ("version", i("v0.7.0: + 1 on take / resolve / dismiss; commands send it as expectedVersion.", minimum=1)),
    ("reportedBy", ref("Actor")),
    ("raisedBy", s("v0.7.0: who raised it; system for driver_silent.", enum=SF["raisedBy"])),
    ("zoneId", ref("Id")), ("riderId", ref("Id")), ("driverId", ref("Id")),
    ("position", {"allOf": [ref("IncidentPosition")], "description": "v0.7.0: the GPS the SOS phone sent (once)."}),
    ("driverPosition", {"allOf": [ref("GeoFix")], "description": "v0.7.0: the car's latest position the server has (admin view; read live, also after the SOS)."}),
    ("openedAt", ref("Timestamp")), ("updatedAt", ref("Timestamp")),
    ("escalatedAt", {"allOf": [ref("Timestamp")], "description": f"v0.7.0: set when the incident was not taken within contract.json#safety.escalateAfterSeconds ({SF['escalateAfterSeconds']} s); every signed-in admin is alerted from then on."}),
    ("takenBy", ref("Id")), ("takenAt", ref("Timestamp")),
    ("resolvedBy", {"allOf": [ref("Id")], "description": "v0.7.0: the admin who solved it or called it a false alarm; absent when the system closed it."}),
    ("resolvedAt", ref("Timestamp")),
    ("resolution", s("v0.7.0: the closing note; 'position back' when the system closes a driver_silent incident.", maxLength=1000)),
    ("alarm", b("v0.12.0: the admin panel rings the alarm for this incident while it is open, and it escalates after escalateAfterSeconds untaken. "
                "true for sos, driver_silent and a ride_check someone answered need_help; false for a no-answer ride_check (cases list, no sound).")),
    ("rideCheck", {"allOf": [ref("IncidentRideCheck")], "description": "v0.12.0: only on kind ride_check."}),
]), ["incidentId", "kind", "severity", "status", "openedAt"])
RC = SF["rideCheck"]
S["RideCheckTrigger"] = s("v0.12.0: what made the app open the ride check card (contract.json#safety.rideCheck.triggers).", enum=RC["triggers"])
S["IncidentRideCheck"] = obj(OrderedDict([
    ("checkId", s("The app's id of the check that opened or last raised the incident.", minLength=1, maxLength=64)),
    ("trigger", ref("RideCheckTrigger")),
    ("by", s("The side whose check it is.", enum=["rider", "driver"])),
    ("answer", s("need_help = someone asked for help (alarm); no_answer = nobody answered within contract.json#safety.rideCheck.noAnswerSeconds.", enum=RC["incidentAnswers"])),
    ("shownAt", {"allOf": [ref("Timestamp")], "description": "When the server learnt the card showed."}),
    ("answeredAt", ref("Timestamp")),
    ("lateAnswer", s("An answer that came after the no-answer incident opened; the incident stays open for the admin.", enum=RC["answers"])),
]), ["checkId", "trigger", "by", "answer"], "v0.12.0 (CONTRACT.md §22).")
S["RideCheckReport"] = obj(OrderedDict([
    ("checkId", s("The app's id of this check, the same on the shown report and the answer (unique per trip and side).", pattern="^[A-Za-z0-9_-]{1,64}$")),
    ("trigger", ref("RideCheckTrigger")),
    ("at", {"allOf": [ref("Timestamp")], "description": "When it happened on the phone (shown, or answered)."}),
    ("answer", s("Absent = the card just showed (starts the 2-minute no-answer clock); ok = saved on the trip only; need_help = opens the alarm incident.", enum=RC["answers"])),
    ("position", {"allOf": [ref("IncidentPosition")], "description": "The phone's last GPS, when it has one."}),
]), ["checkId", "trigger", "at"], "v0.12.0 (CONTRACT.md §22).")
S["RideCheckReceipt"] = obj(OrderedDict([
    ("checkId", s(maxLength=64)), ("tripId", ref("Id")),
    ("answer", s("The check's stored answer; absent while it waits for one.", enum=RC["answers"])),
    ("receivedAt", ref("Timestamp")),
    ("incidentId", {"allOf": [ref("Id")], "description": "Set when this check is part of a ride_check incident."}),
]), ["checkId", "tripId", "receivedAt"], "v0.12.0: the report reached Movera. The app shows only \"Sent\" after an answer.")
S["SosRequest"] = obj({"at": {"allOf": [ref("Timestamp")], "description": "When the person pressed SOS on the phone."},
                       "position": {"allOf": [ref("IncidentPosition")], "description": "The phone's last GPS, sent once; absent when the phone has none."}},
                      ["at"], "v0.7.0 (CONTRACT.md §15).")
S["SosReceipt"] = obj({"incidentId": ref("Id"), "tripId": ref("Id"), "receivedAt": ref("Timestamp")},
                      ["incidentId", "tripId", "receivedAt"],
                      "v0.7.0: the SOS reached Movera. The app shows only \"SOS sent\"; it gets no later update.")
S["AdminIncidentCommand"] = obj(dict(expectedVersion=i("The incident version the admin last saw; stale → 409 version_mismatch with the incident.", minimum=1),
                                     note=s(maxLength=1000)), ["expectedVersion"],
                                "v0.7.0: take, resolve (Solved) or dismiss (False alarm). The note becomes the resolution.")
S["AdminIncidentEvent"] = obj({"eventId": ref("Id"), "sequence": i(minimum=1), "kind": s(enum=SF["streamEventKinds"]),
                               "incident": ref("Incident"), "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                              ["eventId", "sequence", "kind", "incident", "occurredAt", "serverTime"],
                              "v0.7.0: the admin incident feed (GET /admin/incidents/stream).")
S["PayoutLine"] = obj({"code": s("contract.json#payouts.lines", enum=C["payouts"]["lines"]),
                       "amount": {"allOf": [ref("Money")], "description": "Signed: cash_collected is negative (the driver already holds that money)."},
                       "count": i("Trips behind the line, where it counts trips.", minimum=0)},
                      ["code", "amount"], "v0.9.0: one line of a payout.")
S["Payout"] = obj({"payoutId": ref("Id"), "driverId": ref("Id"), "amount": {"allOf": [ref("Money")], "description": "v0.9.0: the sum of the lines; may be negative (the driver owes Movera)."},
                   "status": s(enum=["pending", "pending_approval", "paid", "failed", "held"]),
                   "periodStart": ref("Timestamp"), "periodEnd": ref("Timestamp"), "createdAt": ref("Timestamp"),
                   "paidAt": ref("Timestamp"),
                   "source": s("v0.9.0: weekly (the nightly job) or manual (Create payout in the admin).", enum=C["payouts"]["sources"]),
                   "tripCount": i("v0.9.0", minimum=0),
                   "driverName": s("v0.9.0, admin only"),
                   "zoneId": {"allOf": [ref("Id")], "description": "v0.9.0, admin only: the driver's first zone."},
                   "lines": arr(ref("PayoutLine"), description="v0.9.0, admin only (GET /admin/payouts): the lines behind the amount. The driver app shows only the total."),
                   "paidBy": {"allOf": [ref("Id")], "description": "v0.9.0, admin only: who marked it paid."},
                   "note": s(maxLength=1000)}, ["payoutId", "driverId", "amount", "status", "createdAt"])
S["PayoutCreateCommand"] = obj({"driverId": ref("Id"), "from": ref("Timestamp"), "to": ref("Timestamp"), "note": s(maxLength=1000)},
                               ["driverId", "from", "to"], "v0.9.0: Create payout by hand for a driver and a date range; trips already in a payout are left out (409 nothing_to_pay when none is left).")
S["PayoutPaidCommand"] = obj({"note": s(maxLength=1000)}, (), "v0.9.0: Mark as paid.")
RK = C["risk"]
S["RiskSignal"] = obj({"value": n("Percent for cancels, a count for failed_payments, stars for low_rating."), "count": i(minimum=0, description="Events counted (cancels, failed payments, rated rides)."),
                       "total": i(minimum=0, description="cancels: trips in the window.")}, ["value", "count"])
S["RiskPerson"] = obj({"who": s(enum=["driver", "rider"]), "id": ref("Id"), "name": s(), "zoneId": ref("Id"),
                       "signals": obj({k: ref("RiskSignal") for k in RK["signals"]}, (), "Only the signals the server counts (contract.json#risk.signals); a missing one has no data yet.")},
                      ["who", "id", "name", "signals"], "v0.9.0: one rider or driver with the server's risk signals.")
S["RiskPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("RiskPerson"))}}], "description": "Page<RiskPerson>"}
KF = C["kpis"]["fields"]
S["KpiDay"] = obj(OrderedDict([("date", s("The zone-local day, YYYY-MM-DD.", pattern="^\\d{4}-\\d{2}-\\d{2}$")), ("zoneId", ref("Id")),
                               ("source", s("live: counted now (today); summary: the nightly summary.", enum=["live", "summary"])),
                               ("currency", ref("CurrencyCode"))] + [(k, i(minimum=0) if k in ("completedTrips", "cancelledTrips", "noShows", "newRiders", "newDrivers") else i(C["kpis"]["money"].get(k, "Minor units of currency."))) for k in KF]),
                  ["date", "zoneId", "source", "currency"] + KF, "v0.9.0: one zone's numbers for one day (contract.json#kpis).")
S["KpiReport"] = obj({"days": arr(ref("KpiDay")), "generatedAt": ref("Timestamp")}, ["days", "generatedAt"], "v0.9.0: GET /admin/kpis.")
S["EarningsPeriod"] = obj({"periodStart": ref("Timestamp"), "periodEnd": ref("Timestamp"), "tripCount": i(minimum=0),
                           "gross": ref("Money"), "commission": ref("Money"), "pickupPay": ref("Money"),
                           "tips": ref("Money"), "adjustments": ref("Money"), "cashCollected": ref("Money"),
                           "fees": {"allOf": [ref("Money")], "description": "v0.5.1: the driver's shares of cancel and no-show fees credited in the period, also those the rider still owes (CONTRACT.md §3.7)."},
                           "net": ref("Money")},
                          ["periodStart", "periodEnd", "tripCount", "gross", "commission", "tips", "adjustments", "net"])
S["EarningsReport"] = obj({"driverId": ref("Id"), "period": s(enum=["day", "week", "month"]), "timeZone": s(),
                           "periods": arr(ref("EarningsPeriod"))}, ["driverId", "period", "periods"])
S["AreaZone"] = obj({"zoneId": ref("Id"), "name": s()}, ["zoneId", "name"], "v0.18.4: one of the driver's own zones.")
S["DriverLocationAck"] = obj({"accepted": i(minimum=0), "serverTime": ref("Timestamp"),
                              "outsideArea": b("v0.18.4 (G3-R2): the driver's latest position is outside all his zones (no trips there). " + C["driverHome"]["outsideArea"]["note"]),
                              "areaZones": arr(ref("AreaZone"), description="v0.18.4: with outsideArea true, the driver's own zones.")}, ["accepted", "serverTime"])
S["PinCode"] = obj({"tripId": ref("Id"), "pin": s(pattern=r"^\d{4}$"), "expiresAt": ref("Timestamp")},
                   ["tripId", "pin", "expiresAt"], "Per-trip PIN shown to the rider when pinRequired.")
S["PinVerification"] = obj({"verifiedPinToken": s("Short-lived proof passed to `board`; the raw PIN is never stored or logged.", minLength=16),
                            "expiresAt": ref("Timestamp")}, ["verifiedPinToken", "expiresAt"])

# --- admin
S["AdminRole"] = s(enum=["viewer", "support", "dispatcher", "compliance", "finance", "safety", "content", "config", "fleet", "ops", "super"])
S["PendingApproval"] = obj({"status": s(const="pending_approval"), "approvalId": ref("Id"),
                            "action": s(examples=["trip.refund", "config.publish"]), "targetId": ref("Id"),
                            "requestedAt": ref("Timestamp")}, ["status", "approvalId", "action", "targetId", "requestedAt"],
                           "An approval filed before v0.7.2. Since v0.7.2 (owner 2026-10-28, one admin is enough everywhere) no operation answers 202; GET /admin/approvals lists the old ones.")
S["Approval"] = obj({"approvalId": ref("Id"), "action": s(), "targetType": s(enum=["trip", "payment", "refund", "payout", "config", "driver", "rider"]),
                     "targetId": ref("Id"), "amount": ref("Money"), "reason": s(),
                     "status": s(enum=["pending_approval", "approved", "rejected", "expired"]),
                     "requestedBy": ref("Id"), "requestedAt": ref("Timestamp"), "decidedBy": ref("Id"),
                     "decidedAt": ref("Timestamp"), "decisionNote": s()},
                    ["approvalId", "action", "targetType", "targetId", "status", "requestedBy", "requestedAt"])
S["AuditEntry"] = obj({"auditId": ref("Id"), "at": ref("Timestamp"), "actor": ref("Actor"), "actorId": ref("Id"),
                       "actorRole": ref("AdminRole"), "action": s(), "targetType": s(), "targetId": ref("Id"),
                       "reason": s(), "result": s(enum=["committed", "rejected", "denied", "conflict", "pending_approval"]),
                       "before": {"description": "Server-written snapshot before the change."},
                       "after": {"description": "Server-written snapshot after the change."},
                       "requestId": s(), "idempotencyKey": s()},
                      ["auditId", "at", "actor", "actorId", "action", "targetType", "targetId", "result", "requestId"])
S["ConfigDocName"] = s("app documents are served to the apps; pricing and dispatch (v0.5.1) are server-only (x-server-only, contract.json#configDocs).",
                        enum=C["configDocs"]["app"] + C["configDocs"]["serverOnly"] + C["configDocs"]["rules"], **{"x-server-only": C["configDocs"]["serverOnly"] + C["configDocs"]["rules"]})
CONFIG_DOC_ONE_OF = [ref("RiderAppConfig"), ref("DriverAppConfig"), ref("PricingDocument"), ref("DispatchDocument"), ref("CountryRules"), ref("OnboardingSettings")]
S["ConfigDraft"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"), "country": ref("CountryCode"),
                        "usesStandard": b("v0.8.0: the zone has no own published document of this kind and uses its country's standard (configDocs.standard); the draft starts from the standard."),
                        "version": i("Draft version (expectedVersion for PUT/publish).", minimum=1),
                        "liveVersion": i("Version of the published document the apps read.", minimum=0),
                        "document": {"oneOf": CONFIG_DOC_ONE_OF},
                        "updatedAt": ref("Timestamp"), "updatedBy": ref("Id")},
                       ["doc", "version", "liveVersion", "document", "updatedAt"], "v0.8.0: zoneId for a zone's document, country for a country's standard or country_rules (" + C["configDocs"]["scope"] + ")")
S["ConfigPublication"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"), "country": ref("CountryCode"), "version": i("Stamped by the server (contract.json#configVersion).", minimum=1),
                              "publishedAt": ref("Timestamp")}, ["doc", "version", "publishedAt"])
S["CountryRules"] = obj(OrderedDict([
    ("version", i("Stamped by the server.", minimum=1)), ("publishedAt", ref("Timestamp")),
    ("country", ref("CountryCode")), ("currency", ref("CurrencyCode")),
    ("tips", arr(ref("AmountOption"))), ("raiseSteps", arr(ref("AmountOption"))), ("driverBonus", ref("DriverBonusLimits")),
]), ["version", "publishedAt", "country", "currency", "tips", "raiseSteps", "driverBonus"],
    "v0.8.1, server-only, per zone or per country (its standard): " + C["configDocs"]["countryRules"], **{"x-server-only": True})

# --- config documents (unknown keys ignored => additionalProperties allowed)
S["FeeRule"] = {
    "type": "object", "required": ["freeMin", "type", "value", "min", "max"],
    "description": "Cancel fee rule. live: freeMin = minutes after accept; reservation: freeMin = minutes before pickup. "
                   "fixed: value is minor units; percent: value is 0–100 of the fare, rounded half-up to a whole minor unit, then clamped to min/max.",
    "properties": {"freeMin": i(minimum=0), "type": s(enum=["fixed", "percent"]), "value": n(minimum=0),
                   "min": nullable("Money"), "max": nullable("Money")},
    "allOf": [
        {"if": {"properties": {"type": {"const": "percent"}}, "required": ["type"]}, "then": {"properties": {"value": {"maximum": 100}}}},
        {"if": {"properties": {"type": {"const": "fixed"}}, "required": ["type"]}, "then": {"properties": {"value": {"type": "integer"}}}},
    ]}
S["CancelFeeTable"] = {"type": "object", "description": "FeeRule per categoryId.", "propertyNames": ref("CategoryId"),
                       "additionalProperties": ref("FeeRule")}
S["CancelFees"] = obj({"live": ref("CancelFeeTable"), "reservation": ref("CancelFeeTable"),
                      "driverSharePct": {**n(minimum=0, maximum=100), "default": C["cancelFees"]["driverSharePctDefault"], "description": "DriverAppConfig only. " + C["cancelFees"]["note"]}})
S["LocalizedLine"] = obj({"sv": s(maxLength=80), "fr": s(maxLength=80), "en": s(maxLength=80)}, desc="v0.7.1: a short text in each app language.")
S["CategoryCatalog"] = obj({"categories": arr(obj({"id": ref("CategoryId"), "label": s(), "seats": i(minimum=1), "sort": i(),
                                                   "line": {"allOf": [ref("LocalizedLine")], "description": "v0.7.1: the sub-line under the name (admin Manage categories), e.g. Movera XL — up to 6 people; the rider app shows it."}},
                                                  ["id", "label", "seats", "sort"]))}, ["categories"])
S["AppUpdate"] = obj({"minimumVersion": s(pattern=r"^\d+\.\d+\.\d+$"), "latestVersion": s(pattern=r"^\d+\.\d+\.\d+$"),
                      "storeUrl": s(format="uri")}, desc="Below minimumVersion = forced update; below latestVersion = soft update.")
S["RideCheck"] = obj({"stopMinutes": n(minimum=0), "offRouteKm": n(minimum=0)}, desc="Ride check thresholds (Safety).")
S["CategoryWaiting"] = obj({"freeWaitMin": n(minimum=0), "perMin": {"allOf": [ref("Money")], "description": "Waiting fee per minute after the free wait."},
                            "noShowAfterMin": n("Equals freeWaitMin (owner Q41): the no-show button appears when the free wait ends.", minimum=0),
                            "noShowFee": ref("Money")},
                           desc="Waiting terms of one category. Default free wait 5 min, xl 3 min (contract.json#configDefaults).")
S["RiderWaiting"] = obj({"freeWaitMin": n(minimum=0), "perMin": ref("Money"), "noShowAfterMin": n(minimum=0),
                         "noShowFee": ref("Money"),
                         "byCategory": {"type": "object", "description": "CategoryWaiting per categoryId.", "propertyNames": ref("CategoryId"),
                                        "additionalProperties": ref("CategoryWaiting")}},
                        desc="Top-level terms are the headline category's (economy, else the first).")
S["DriverWaiting"] = {"allOf": [ref("RiderWaiting"), obj({"driverSharePct": n("Driver's share of the no-show fee, per country (default 80).", minimum=0, maximum=100),
                                                          "driverShareWaitPct": n("Driver's share of the waiting fee (100).", minimum=0, maximum=100)})]}
S["AmountOption"] = obj({"amount": ref("Money"), "enabled": b("Disabled options are not shown.")}, ["amount", "enabled"],
                        "One admin-editable amount (tip or raise-offer step) in the zone's currency.")
S["Languages"] = obj({"available": arr(ref("Language"), uniqueItems=True, minItems=1),
                      "default": obj({"rider": ref("Language"), "driver": ref("Language"), "admin": ref("Language")}, ["rider", "driver", "admin"])},
                     ["available", "default"], "App languages and the country's default per app (owner Q48/Q49).")
S["DriverBonusLimits"] = obj({"defaultLimit": {"allOf": [ref("Money")], "description": "Above this the admin is told to adjust the limit in Pricing."},
                              "hardMax": {"allOf": [ref("Money")], "description": "The limit can never be set above this."}},
                             ["defaultLimit", "hardMax"], "Movera-paid driver bonus (\"add money to trip\") limits per country.")
RD = C["configDefaults"]["reservations"]
def dflt(o, v): return {**o, "default": v}
S["ReservationRideType"] = obj({
    "onlineBeforeMin": i("Be online this many minutes before pickup.", minimum=5, maximum=240),
    "spareMin": i("Spare minutes in the smart gap and in Leave now.", minimum=0, maximum=60),
    "reminderMin": arr(i(minimum=1, maximum=1440), description="Reminder times, minutes before pickup, largest first.", maxItems=4)},
    desc="Times for one kind of scheduled ride.")
S["LateEta"] = obj({
    "on": dflt(b("Watch an online driver's ETA from Leave now until arrival at the pickup."), RD["lateEta"]["on"]),
    "toleranceMin": dflt(i("Reassign when now + ETA > pickup time + toleranceMin.", minimum=0, maximum=30), RD["lateEta"]["toleranceMin"]),
    "checkEverySeconds": dflt(i("How often the ETA is checked.", minimum=15, maximum=600), RD["lateEta"]["checkEverySeconds"]),
    "reassignTo": dflt(s("exclusive = Exclusive offer to the nearest available driver; radar = Radar trips; dispatch = back to admin dispatch.",
                         enum=["exclusive", "radar", "dispatch"]), RD["lateEta"]["reassignTo"])},
    desc="Running late: an online driver who would arrive more than toleranceMin late loses the ride early. Otherwise an online driver keeps it.")
S["DriverReservations"] = obj(OrderedDict([
    ("on", dflt(b("Reservations for every driver in this zone (same value as features.scheduledRides). Off: no new reservations; accepted ones still run."), RD["on"])),
    ("lateWarn", dflt(b("Island warning \"Head to your 07:40 pickup\" when Leave now cannot start the trip (driver offline, or busy with another screen). Leave now itself always opens the trip; there is no switch for it (v0.4.2)."), RD["lateWarn"])),
    ("offlineBackupAfterMin", dflt(i("Only an OFFLINE driver loses the ride, this many minutes after Leave now; an online driver keeps it.", minimum=1, maximum=60), RD["offlineBackupAfterMin"])),
    ("homePopupAfterMin", dflt(i("Untaken: the Home popup this many minutes after booking.", minimum=1, maximum=1440), RD["homePopupAfterMin"])),
    ("exclusiveBeforeMin", dflt(i("Untaken: Exclusive from this many minutes before pickup.", minimum=1, maximum=180), RD["exclusiveBeforeMin"])),
    ("radarBeforeMin", dflt(i("Untaken: Radar trips from this many minutes before pickup.", minimum=1, maximum=180), RD["radarBeforeMin"])),
    ("onDriverCancel", dflt(s("Where a ride goes after a driver cancels.", enum=["byTime", "list", "home", "exclusive"]), RD["onDriverCancel"])),
    ("hideClashing", dflt(b("Rides that do not fit the smart gap leave the driver's Scheduled rides list once they take one."), RD["hideClashing"])),
    ("towardPickup", dflt(b("Before the ride, offers head toward the scheduled pickup."), RD["towardPickup"])),
    ("towardPickupBeforeMin", dflt(i(minimum=15, maximum=240), RD["towardPickupBeforeMin"])),
    ("longTripKm", dflt(n("A ride longer than this is a longTrip.", minimum=10, maximum=500), RD["longTripKm"])),
    ("driverLateCancelHours", dflt(n("A driver cancel with less than this many hours to pickup is a late cancel.", minimum=0.5, maximum=72), RD["driverLateCancelHours"])),
    ("lateCancelLimit", dflt(i("Late cancels within lateCancelPeriodDays before a pause.", minimum=1, maximum=20), RD["lateCancelLimit"])),
    ("lateCancelPeriodDays", dflt(i(minimum=1, maximum=90), RD["lateCancelPeriodDays"])),
    ("pauseDays", dflt(i("No scheduled rides for this many days after the limit.", minimum=1, maximum=365), RD["pauseDays"])),
    ("assignAcceptSeconds", dflt(i("Time to accept a ride assigned by Movera.", minimum=10, maximum=600), RD["assignAcceptSeconds"])),
    ("rideTypes", obj({k: ref("ReservationRideType") for k in ["normal", "airport", "longTrip", "comfortPremium", "event"]},
                      desc="Per kind of ride. Admin ids long and premium are longTrip and comfortPremium.")),
    ("lateEta", ref("LateEta")),
]), desc="Scheduled-ride rules for the driver app (CONTRACT.md §6). Every field is optional; a missing or invalid one keeps the default "
         "(contract.json#configDefaults.reservations).")
CONFIG_HEAD = OrderedDict([("version", i("Stamped by the server (contract.json#configVersion); only increases; apps keep the last good document.", minimum=1)),
                           ("publishedAt", ref("Timestamp")), ("zoneId", ref("Id")), ("currency", ref("CurrencyCode")),
                           ("timeZone", s("IANA zone of the zone, for wall-clock rules and booking times.", pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$",
                                          examples=["Europe/Stockholm", "Europe/Paris", "Africa/Tunis"])),
                           ("country", ref("CountryCode")), ("languages", ref("Languages")), ("usesStandard", b("v0.8.0: set by the server when it serves or uses the country standard for this zone (contract.json#configDocs.standard)."))])
ZONE_PM = ("paymentMethods", arr(ref("ZonePaymentMethod"), uniqueItems=True, description="Methods offered in the zone; the wallet is separate."))

# --- v0.5.0: pickup pay, offer limits while driving, surge schedule, auth, push devices
PP = C["pickupPay"]
S["PickupRange"] = obj({"fromKm": n(minimum=0), "toKm": {"type": ["number", "null"], "description": "null = and above (last range only)."},
                        "perKm": ref("Money"), "perMin": ref("Money")}, ["fromKm", "toKm", "perKm", "perMin"],
                       "One pickup-distance range (contract.json#pickupPay.ranges): the first starts at 0, each next one where the one before ends.")
S["RiderPickupFee"] = obj({"live": nullable("Money"), "reservation": nullable("Money")}, ["live", "reservation"],
                          "The rider's fixed pickup fee for one category: live rides (Radar and Exclusive) and reservations; null = off. Goes into the quote as the pickup_fee line; Movera keeps it.")
S["PickupPayRate"] = obj({"enabled": b("Driver pickup pay on or off for the category."),
                          "maxPerRide": {"oneOf": [ref("Money"), {"type": "null"}], "description": "The driver never gets more than this for one pickup; null = no maximum."},
                          "ranges": arr(ref("PickupRange"), minItems=1), "riderFee": ref("RiderPickupFee")},
                         ["enabled", "maxPerRide", "ranges", "riderFee"],
                         "One category's pickup pay (Admin Pricing › Pickup pay). " + PP["ranges"]["note"] + " Rounding: " + PP["ranges"]["rounding"] + ". Cases: fixtures/pickup_pay.json.")
S["PickupPayOffers"] = obj({k: b() for k in PP["offerKinds"]}, PP["offerKinds"], PP["offerKindNote"])
S["DriverPickupPay"] = obj(OrderedDict([
    ("offers", ref("PickupPayOffers")), ("display", s(enum=PP["display"])),
    ("byCategory", {"type": "object", "description": "PickupPayRate per categoryId; a category not listed has no pickup pay.", "propertyNames": ref("CategoryId"),
                    "additionalProperties": ref("PickupPayRate")}),
    ("perKm", {"allOf": [ref("Money")], "deprecated": True, "description": "v0.4 shape of the headline category (first paid range); removed in v0.6."}),
    ("perMin", {"allOf": [ref("Money")], "deprecated": True}), ("freeKm", {**n(minimum=0), "deprecated": True}), ("freeMin", {**n(minimum=0), "deprecated": True}),
    ("ranges", {**arr(ref("PickupRange")), "deprecated": True, "description": "v0.4 shape: the headline category's ranges; use byCategory."}),
    ("maxPerRide", {"oneOf": [ref("Money"), {"type": "null"}], "deprecated": True}),
]), ["offers", "display", "byCategory"], "DriverAppConfig.pickupPay (v0.5.0, CONTRACT.md §3.2). " + PP["note"])
S["RiderPickupFees"] = obj({"byCategory": {"type": "object", "description": "RiderPickupFee per categoryId.", "propertyNames": ref("CategoryId"),
                                           "additionalProperties": ref("RiderPickupFee")}}, ["byCategory"],
                           "RiderAppConfig.pickupFee (v0.5.0): the fixed pickup fees the quote's pickup_fee line carries, so the app can name them; the server prices.")
OD = C["configDefaults"]["offers"]
S["RadarAppLimits"] = obj({"fullOn": b("The full-screen Radar list is available."), "full": i("Most offers in the full-screen list.", minimum=1),
                           "fullLockWhileDriving": b("The list cannot be opened while the car is moving; it opens again once stopped."),
                           "popupOn": b("Offer cards over the map are shown."), "popup": i("Most cards at once while stopped.", minimum=1),
                           "popupSplitByDriving": b("The cards have their own limit while driving (popupWhileDriving); false = popup all the time."),
                           "popupWhileDriving": i("Most cards at once while moving, 1 to popup.", minimum=1)},
                          desc="Radar offers one driver sees at once (Admin Dispatch › Modes; contract.json#driverMotion, v0.5.0). Defaults: " + json.dumps(OD["radarApp"]) + ". No Radar offers while driving a rider.")
S["ExclusiveWhileDriving"] = obj({"on": b(), "count": i(minimum=1, maximum=5)},
                                 desc="While driving a rider the driver gets Exclusive offers only, at most count at a time, never Radar (Q18). Defaults: " + json.dumps(OD["exclusiveWhileDriving"]) + ".")
SG = C["surge"]
S["SurgePoint"] = obj({"atMin": i("Minutes from startAt.", minimum=0), "multiplier": n(minimum=SG["minMultiplier"])}, ["atMin", "multiplier"])
S["SurgeSchedule"] = obj(OrderedDict([
    ("scheduleId", ref("Id")), ("zoneId", ref("Id")),
    ("categoryIds", arr(ref("CategoryId"), uniqueItems=True, description="Empty = every category of the zone.")),
    ("startAt", ref("Timestamp")), ("endAt", ref("Timestamp")),
    ("stepMinutes", {**i(minimum=1), "default": SG["stepMinutes"]}), ("cap", {**n(minimum=1, maximum=SG["capMax"]), "description": "No point and no step is above this: the admin's maximum, at most capMax (6, v0.6.0; v0.7.1: the server sets it to the highest point, the slider value). The quote is also kept within the zone's pricing surge.maxMultiplier."}),
    ("points", arr(ref("SurgePoint"), minItems=SG["minPoints"], description="Sorted by atMin; the first at 0, the last at the end; straight lines between.")),
    ("status", s(enum=["scheduled", "active", "ended", "cancelled"])), ("version", i(minimum=1)),
    ("createdBy", ref("Id")), ("createdAt", ref("Timestamp")),
]), ["scheduleId", "zoneId", "categoryIds", "startAt", "endAt", "stepMinutes", "cap", "points", "status", "version"],
    "A surge curve over time (v0.5.0, CONTRACT.md §3.4, contract.json#surge). " + SG["valueAt"] + ". Cases: fixtures/surge.json.")
S["SurgeScheduleCommand"] = obj(OrderedDict([
    ("expectedVersion", i("Version of the schedule being replaced; 0 when the zone has none.", minimum=0)),
    ("categoryIds", arr(ref("CategoryId"), uniqueItems=True)), ("startAt", ref("Timestamp")), ("endAt", ref("Timestamp")),
    ("stepMinutes", {**i(minimum=1), "default": SG["stepMinutes"]}), ("points", arr(ref("SurgePoint"), minItems=SG["minPoints"])),
    ("note", s(maxLength=1000)),
]), ["expectedVersion", "startAt", "endAt", "points"], "Create or replace the zone's surge schedule. A flat manual surge is two points with the same multiplier.")
S["QuoteSurge"] = obj({"multiplier": n(minimum=1), "until": {"allOf": [ref("Timestamp")], "description": "When the current step ends (the next step may differ); null for a flat surge."},
                       "scheduleId": ref("Id")}, ["multiplier"], "The surge step this quote was priced in (v0.5.0); display only, the quote total already includes it.")
AU = C["auth"]
S["PhoneE164"] = s("E.164 phone number.", pattern=r"^\+[1-9][0-9]{6,14}$")
S["OtpRequest"] = obj({"phone": ref("PhoneE164"), "app": s("Which app signs in; decides the actor of the tokens.", enum=["rider", "driver"]),
                       "linkToken": s("From a PHONE_REQUIRED provider sign-in: links this phone to that account.", minLength=1),
                       "locale": ref("Language")}, ["phone", "app"], "Start a phone sign-in: the server sends the code by " + AU["otp"]["channel"] + " (none to a test number, contract.json#auth.testSignIn).")
S["OtpChallenge"] = obj({"requestId": s(), "sessionId": ref("Id"), "expiresAt": ref("Timestamp"),
                         "retryAfterSeconds": {**i(minimum=0), "default": AU["otp"]["retryAfterSeconds"]}},
                        ["requestId", "sessionId", "expiresAt", "retryAfterSeconds"],
                        f"The code is {AU['otp']['codeLength']} digits and lives {AU['otp']['expiresSeconds']} s; at most {AU['otp']['maxAttempts']} attempts.")
S["OtpVerifyRequest"] = obj({"phone": ref("PhoneE164"), "sessionId": ref("Id"), "code": s(pattern=r"^[0-9]{%d}$" % AU["otp"]["codeLength"]),
                             "linkToken": s(minLength=1)}, ["phone", "sessionId", "code"])
S["AuthTokens"] = obj({"accessToken": s("JWT bearer token.", minLength=1), "refreshToken": s("Opaque, rotated on every refresh.", minLength=1),
                       "expiresIn": {**i(minimum=1), "description": "Access token lifetime, seconds.", "default": AU["tokens"]["accessExpiresSeconds"]},
                       "actor": s(enum=["rider", "driver"]), "isNewRider": b("First sign-in: the app asks for the name."), "isNewDriver": b("First sign-in: the app starts onboarding.")},
                      ["accessToken", "refreshToken"], "Signed in. Actor, subject id and zone scope are inside the access token.")
S["ProviderSignInRequest"] = obj({"provider": s(enum=AU["providers"]), "idToken": s("The provider's identity token, verified server-side.", minLength=1),
                                  "app": s(enum=["rider", "driver"]), "name": s(maxLength=120)}, ["provider", "idToken", "app"])
S["PhoneRequired"] = obj({"code": s(const="PHONE_REQUIRED"), "linkToken": s(minLength=1), "name": s(),
                          "firstName": s("v0.5.3: what the provider gave, for the driver's details screen; editable."), "lastName": s("v0.5.3"),
                          "email": s("v0.5.3: may be Apple's hidden relay address; editable.", format="email")}, ["code", "linkToken"],
                         "No account is linked to this provider identity yet: verify a phone with this linkToken on the OTP calls and the account is created linked.")
S["ProviderSignInResult"] = {"oneOf": [ref("AuthTokens"), ref("PhoneRequired")], "description": AU["providerNote"]}
S["RefreshRequest"] = obj({"refreshToken": s(minLength=1)}, ["refreshToken"])
# v0.15.0 (owner 2026-10-29, sign-in group 1): waiting list and the test accounts of staging builds.
S["WaitlistRequest"] = obj({"phone": ref("PhoneE164"), "app": s(enum=["rider", "driver"]), "locale": ref("Language")}, ["phone", "app"],
                           "v0.15.0: join the waiting list after 403 sign_in_restricted (contract.json#auth.waitlist).")
S["WaitlistReceipt"] = obj({"status": s(const="saved"), "requestId": s()}, ["status", "requestId"], "v0.15.0: the number is on the waiting list.")
S["WaitlistEntry"] = obj({"phone": ref("PhoneE164"), "app": s(enum=["rider", "driver"]), "locale": ref("Language"),
                          "firstAt": ref("Timestamp"), "lastAt": ref("Timestamp"), "count": i("How many times this number asked.", minimum=1)},
                         ["phone", "app", "firstAt", "lastAt", "count"], "v0.15.0: one number on the waiting list, per app.")
S["TestAccount"] = obj({"phone": ref("PhoneE164"), "app": s(enum=["rider", "driver"]), "status": s(AU["testAccounts"]["statusNote"], enum=AU["testAccounts"]["statuses"]),
                        "name": s("The account's first name, when it has one.")}, ["phone", "app", "status"], "v0.15.0: a test number and its account's status.")
S["TestAccountList"] = obj({"accounts": arr(ref("TestAccount"))}, ["accounts"], AU["testAccounts"]["note"])
S["PushDeviceRequest"] = obj({"token": s("Push token from the provider.", minLength=1), "provider": s(enum=AU["devices"]["providers"]),
                              "platform": s(enum=AU["devices"]["platforms"]), "appVersion": s(pattern=r"^\d+\.\d+\.\d+$"), "locale": ref("Language")},
                             ["token", "provider", "platform"], AU["devices"]["note"])
S["PushDeviceAck"] = obj({"status": s(enum=["registered", "unregistered"]), "requestId": s()}, ["status"])
S["PushDeviceUnregister"] = obj({"token": s(minLength=1)}, ["token"])

S["RiderAppConfig"] = obj(OrderedDict(list(CONFIG_HEAD.items()) + [
    ("catalog", ref("CategoryCatalog")),
    ("features", {"type": "object", "properties": {"scheduledRides": b(), "wallet": b(), "pin": b(), "shareTrip": b()},
                  "additionalProperties": {"type": "boolean"}}),
    ZONE_PM,
    ("wallet", obj({"usedFirst": b("The balance (one per currency, no conversion) pays first.")})),
    ("tips", arr(ref("AmountOption"), description="Tip options in admin order.")),
    ("raiseSteps", arr(ref("AmountOption"), description="Raise-offer quick steps while searching, in admin order.")),
    ("promoCap", {"oneOf": [ref("Money"), {"type": "null"}], "description": "Most a promotion may take off one trip in this country; null = no cap set."}),
    ("pickupFee", ref("RiderPickupFees")),
    ("booking", obj({"maxStops": i(minimum=0, maximum=10), "bookingHorizonDays": i(minimum=0),
                     "maxPickupMoveMeters": i("How far the rider may move the pickup after accept; further = cancel and rebook.", minimum=0)})),
    ("cancelFees", ref("CancelFees")),
    ("waiting", ref("RiderWaiting")),
    ("cancelReasons", arr(obj({"code": ref("RiderCancelReasonCode"), "title": s(minLength=1)}, ["code", "title"]))),
    ("rideCheck", ref("RideCheck")),
    ("appUpdate", ref("AppUpdate")),
]), ["version", "publishedAt", "zoneId", "currency", "timeZone"],
    "Per-zone rider document built by Admin exporters. Unknown keys are ignored; missing keys fall back to the app seed.")
S["DriverAppConfig"] = obj(OrderedDict(list(CONFIG_HEAD.items()) + [
    ("catalog", ref("CategoryCatalog")),
    ("features", {"type": "object", "properties": {"scheduledRides": b(), "performance": b()},
                  "additionalProperties": {"type": "boolean"}}),
    ZONE_PM,
    ("booking", obj({"maxStops": i(minimum=0, maximum=10),
                     "maxPickupMoveMeters": i("Pickup move limit after accept; the driver is notified of a move.", minimum=0)})),
    ("offers", obj({"radarSeconds": i(minimum=1), "exclusiveSeconds": i(minimum=1),
                    "radarOn": b("Radar offers in this zone (v0.5.0)."), "exclusiveOn": b("Exclusive offers in this zone (v0.5.0)."),
                    "assignAcceptSeconds": i("Time to accept a ride assigned by Movera (v0.5.0; also reservations.assignAcceptSeconds).", minimum=1),
                    "radarApp": ref("RadarAppLimits"), "exclusiveWhileDriving": ref("ExclusiveWhileDriving"),
                    "offerCard": {"type": "object", "description": "Which fields the offer card shows.",
                                  "properties": {"netFare": b(), "pickupAddress": b(), "dropoffAreaOnly": b(), "stops": b()},
                                  "additionalProperties": {"type": "boolean"}},
                    "exclusiveReasons": arr(obj({"id": s(pattern="^[a-z][a-z0-9_-]{0,63}$"), "text": s(), "on": b()}, ["id", "text", "on"])),
                    "autoOffline": obj({"missedExclusive": i("Missed or declined exclusive offers in a row before the driver is set offline (default 10, owner decision 35; 3 before v0.5.6). " + C["autoOffline"]["note"], minimum=0),
                                        "noFixMinutes": i("v0.18.4 (G3-R1): no position for this many minutes while online (not on a trip) → the server sets the driver offline (default 5; 0 = never). " + C["driverHome"]["setOffline"]["note"], minimum=0),
                                        "hiddenComesBackMin": n(minimum=0)})})),
    ("pickupPay", ref("DriverPickupPay")),
    ("driverBonus", ref("DriverBonusLimits")),
    ("cancelFees", ref("CancelFees")),
    ("waiting", ref("DriverWaiting")),
    ("destinationMode", {"type": "object", "properties": {"perDay": i(minimum=0)}}),
    ("nextTrips", {"type": "object", "properties": {"on": b()}}),
    ("reservations", ref("DriverReservations")),
    ("cancelReasons", obj({"driverBeforeTrip": arr(ref("DriverBeforeTripCancelReasonCode")),
                           "driverDuringTrip": arr(ref("DriverDuringTripCancelReasonCode")),
                           "driverNextTrip": arr(ref("DriverNextTripCancelReasonCode")),
                           "scheduled": arr(ref("ScheduledCancelReasonCode")),
                           "noShow": arr(ref("NoShowReasonCode"))},
                          desc="Enabled codes per reason sheet; titles come from `texts`.")),
    ("drivingLimits", {"type": "object", "properties": {"maxHoursPerDay": n(minimum=0, maximum=24), "restMinutes": n(minimum=0)}}),
    ("rideCheck", ref("RideCheck")),
    ("texts", {"type": "object", "properties": {"byLanguage": {"type": "object", "additionalProperties": {"type": "object"}}}}),
    ("notices", {"type": "object"}),
    ("appUpdate", ref("AppUpdate")),
]), ["version", "publishedAt", "zoneId", "currency", "timeZone"],
    "Per-zone driver document built by Admin exporters. Unknown keys are ignored; missing keys fall back to the app seed.")

# --- v0.5.1: server-only pricing and dispatch documents, admin sign-in, locations and routes, telemetry, live drivers, outstanding fee
PR, DP, CD = C["pricing"], C["dispatch"], C["configDocs"]
def money(desc): return {"allOf": [ref("Money")], "description": desc}
S["CategoryPricingWaiting"] = obj({"freeWaitMin": n(minimum=0, maximum=30), "perMin": money("Per minute after the free wait, charged per second (contract.json#pricing.waiting)."),
                                   "noShowAfterMin": n("Equals freeWaitMin (owner Q41).", minimum=0), "noShowFee": ref("Money")},
                                  ["freeWaitMin", "perMin", "noShowAfterMin", "noShowFee"], "Waiting at pickup for one category; RiderAppConfig / DriverAppConfig waiting.byCategory carry the same values.")
S["CategoryPricing"] = obj(OrderedDict([
    ("enabled", b("The category is offered in this zone.")),
    ("base", ref("Money")), ("perKm", money("Per km; minor units, e.g. 1200 = 12 kr/km.")), ("perMin", ref("Money")),
    ("minimum", money("The ride part is raised to this (minimum_adjust line).")),
    ("maximum", {"oneOf": [ref("Money"), {"type": "null"}], "description": "The ride part is lowered to this (maximum_adjust line); null = no maximum (the admin's 0)."}),
    ("appFeePct", n("Added to the rider's price: % of ride part + extras. Movera keeps it.", minimum=0, maximum=50)),
    ("commissionPct", n("Movera's commission on the ride part and the extras except waiting (owner decisions 17, 18).", minimum=0, maximum=60)),
    ("extraStopFee", ref("Money")), ("stopWaitPerMin", money("Waiting at a stop, per minute, charged per second from the driver's arrived-at-stop to leaving-stop; no free minutes (v0.7.1).")),
    ("childSeatFee", money("v0.7.1: the ONE seat fee, only on the child_seat category (owner 2026-10-27): every child_seat trip includes one seat and adds it once. On another category: 400 seat_fee_not_child_seat. babySeatFee is gone.")),
    ("waiting", ref("CategoryPricingWaiting")),
    ("riderPickupFee", ref("RiderPickupFee")),
]), ["enabled", "base", "perKm", "perMin", "minimum", "maximum", "appFeePct", "commissionPct", "extraStopFee", "stopWaitPerMin", "waiting", "riderPickupFee"],
    "One category's prices in a zone (admin Pricing; zonePricing.ts CategoryPrice + commission + rider pickup fee).")
S["PricingFees"] = obj({"airportPickup": ref("Money"), "airportDropoff": ref("Money"), "reservationFee": money("Added to kind=scheduled trips (reservation_fee line)."),
                        "cleaningFee": money("Charged afterwards by an admin adjust; not in the fare formula."), "tollsPassThrough": b("Tolls added to the fare; no tolls are priced in v0.5.1.")},
                       ["airportPickup", "airportDropoff", "reservationFee", "cleaningFee", "tollsPassThrough"])
S["FixedRoute"] = obj({"id": ref("Id"), "from": s(minLength=1), "to": s(minLength=1), "categoryId": ref("CategoryId"), "price": ref("Money")},
                      ["id", "from", "to", "categoryId", "price"], "A fixed price between two admin-named places: replaces base + distance + time; no surge, minimum or maximum.")
S["SurgeStep"] = obj({"ratio": n("Requests per free driver at which this step starts.", exclusiveMinimum=0), "multiplier": n(minimum=1, maximum=PR["maxMultiplier"])}, ["ratio", "multiplier"])
S["SurgeProfile"] = obj({"id": s(minLength=1), "name": s(), "days": arr(i(minimum=0, maximum=6), description="0 = Monday … 6 = Sunday."),
                         "windows": arr(obj({"from": s(pattern=r"^\d\d:\d\d$"), "to": s(pattern=r"^\d\d:\d\d$")}, ["from", "to"])),
                         "steps": arr(ref("SurgeStep")), "cap": n("The profile's own maximum (admin, ×1 to ×6; v0.7.1: the only limit of smart surge).", minimum=1, maximum=PR["maxMultiplier"]), "isDefault": b()},
                        ["id", "name", "days", "windows", "steps", "cap", "isDefault"])
S["SmartSurge"] = obj({"enabled": b("Automatic surge; false in the test week (owner decision 21)."), "activeFrom": s(pattern=r"^\d\d:\d\d$"), "activeTo": s(pattern=r"^\d\d:\d\d$"),
                       "checkEveryMin": i(minimum=1, maximum=15), "holdMin": i(minimum=1, maximum=30), "stopAfterMin": i(minimum=1, maximum=60), "cooldownMin": i(minimum=1, maximum=30),
                       "profiles": arr(ref("SurgeProfile"))},
                      ["enabled", "profiles"], "The admin's smart surge settings. v0.7.1: the server runs it (contract.json#smartSurge, fixtures/smart_surge.json); off until enabled.")
S["ScheduledSurge"] = obj({"id": s(minLength=1), "name": s(), "multiplier": n(minimum=1, maximum=PR["maxMultiplier"]), "startsAt": ref("Timestamp"), "endsAt": ref("Timestamp")},
                          ["id", "multiplier", "startsAt", "endsAt"], "A flat surge for a time window, from the pricing document.")
S["PricingSurge"] = obj({"maxMultiplier": {**n(minimum=1, maximum=PR["maxMultiplier"]), "deprecated": True, "description": "Deprecated in v0.7.1 and ignored: the maximum of each surge is the value the admin chose on its slider (owner 2026-10-27, no extra box). Kept readable for one release."},
                         "smart": ref("SmartSurge"), "scheduled": arr(ref("ScheduledSurge"), description="v0.7.1: overlapping windows, the higher multiplier counts."),
                         "notifyDrivers": {**b("Deprecated in v0.7.2 and ignored: drivers get no surge notice (owner 2026-10-28, contract.json#surgeNoticeRemoved)."), "deprecated": True, "default": False}}, ["smart", "scheduled"],
                        "Surge sources after the zone's surge schedule (§3.4): " + PR["surgeSource"])
S["PricingDocument"] = obj(OrderedDict([
    ("version", i("Server-stamped revision of the zone's live pricing document (contract.json#configVersion).", minimum=1)), ("publishedAt", ref("Timestamp")),
    ("zoneId", ref("Id")), ("currency", ref("CurrencyCode")), ("country", ref("CountryCode")), ("timeZone", s(pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$")),
    ("priceStep", money("The total is rounded once, half-up, to a multiple of this (admin fees.rounding).")),
    ("categories", {"type": "object", "propertyNames": ref("CategoryId"), "additionalProperties": ref("CategoryPricing")}),
    ("fees", ref("PricingFees")),
    ("fixedRoutes", arr(ref("FixedRoute"))),
    ("surge", ref("PricingSurge")),
    ("fleetCommissionPct", n("Fleet owner's share (admin Pricing); not in the rider's fare.", minimum=0, maximum=30)),
    ("usesStandard", b("v0.8.0: set by the server when it serves or uses the country standard for this zone (contract.json#configDocs.standard).")),
]), ["version", "publishedAt", "zoneId", "currency", "country", "priceStep", "categories", "fees", "fixedRoutes", "surge", "fleetCommissionPct"],
    "Server-only (contract.json#configDocs): the zone's prices, read by the server's quote engine. Never served to the apps. " + PR["note"] + " Sample: fixtures/config/pricing_document.json.",
    **{"x-server-only": True})
S["DispatchModeRules"] = obj({"on": b(), "drivers": i(minimum=1, maximum=30, description="radar: shown at once (1-30); exclusive: tried one after the other per radius step (1-10)."),
                              "seconds": i(minimum=5, maximum=120, description="radar 5-120, exclusive 5-60."), "then": s(enum=sorted(set(DP["then"]["radar"] + DP["then"]["exclusive"])))},
                             ["on", "drivers", "seconds", "then"], "Radar: then is widen | exclusive | widen_then_exclusive. Exclusive: then is radar | widen | widen_then_radar.")
S["DispatchTimeRule"] = obj({"id": s(minLength=1), "on": b(), "from": s(pattern=r"^\d\d:\d\d$"), "to": s(pattern=r"^\d\d:\d\d$"), "mode": s(enum=DP["modes"])},
                            ["id", "on", "from", "to", "mode"], "Zone-local [from, to); wraps midnight when from > to.")
S["DispatchChoose"] = obj({"how": s(enum=DP["chooseHow"]), "radarAbove": n("Busy level (requests per free driver) from which Auto uses Radar.", exclusiveMinimum=0, maximum=10),
                           "main": s(enum=DP["modes"]), "backup": s(enum=DP["modes"] + ["none"], description="Ignored in v0.5.1: `then` decides fallbacks."),
                           "times": arr(ref("DispatchTimeRule"))}, ["how", "radarAbove", "main", "backup", "times"])
S["DispatchFactor"] = obj({"id": s(enum=["eta", "rating", "acceptance", "cancel", "idle", "finishing", "favourite"]), "on": b(), "weight": n(minimum=0)}, ["id", "on", "weight"])
S["DispatchWaitingStep"] = obj({"id": s(minLength=1), "kind": s(enum=DP["waitingKinds"], **{"x-skipped-in-test-week": DP["skippedWaitingKinds"]}), "on": b(),
                                "afterMin": n("From search start.", minimum=0, maximum=30), "message": s(), "extraMin": {"type": ["number", "null"], "description": "keep_waiting: minutes added on Keep waiting."}},
                               ["id", "kind", "on", "afterMin", "message"])
S["DispatchDocument"] = obj(OrderedDict([
    ("version", i("Server-stamped revision of the zone's live dispatch document (contract.json#configVersion).", minimum=1)), ("publishedAt", ref("Timestamp")),
    ("zoneId", ref("Id")), ("country", ref("CountryCode")), ("timeZone", s("IANA zone for the time rules.", pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$")),
    ("radar", ref("DispatchModeRules")), ("exclusive", ref("DispatchModeRules")), ("choose", ref("DispatchChoose")),
    ("rulesFrom", s("Kept, ignored in v0.5.1: the pickup zone's document governs the search.", enum=["driver", "pickup"])),
    ("radius", obj({"steps": arr(n(exclusiveMinimum=0, maximum=50), minItems=1, description="km, strictly increasing."), "maxWaitMin": i(minimum=1, maximum=30)}, ["steps", "maxWaitMin"])),
    ("factors", arr(ref("DispatchFactor"), minItems=1)),
    ("finishing", obj({"exclusive": b(), "withinMin": n(minimum=0), "withinKm": n(minimum=0)}, ["exclusive", "withinMin", "withinKm"])),
    ("favourite", obj({"on": b(), "maxKm": n(minimum=0)}, ["on", "maxKm"])),
    ("exclusiveWhileDriving", ref("ExclusiveWhileDriving")),
    ("waiting", arr(ref("DispatchWaitingStep"))),
    ("usesStandard", b("v0.8.0: set by the server when it serves or uses the country standard for this zone (contract.json#configDocs.standard).")),
]), ["version", "publishedAt", "zoneId", "country", "timeZone", "radar", "exclusive", "choose", "radius", "factors", "finishing", "favourite", "exclusiveWhileDriving", "waiting"],
    "Server-only (contract.json#configDocs): the zone's automatic dispatch rules (admin Dispatch, a subset of the movera.dispatch.rules export, admin field names). "
    "Never served to the apps; DriverAppConfig.offers timers must equal radar/exclusive seconds and on. Algorithm: contract.json#dispatch, CONTRACT.md §3.6. Sample: fixtures/config/dispatch_document.json.",
    **{"x-server-only": True, "x-ranges": DP["ranges"]})
S["DispatchControl"] = obj({"zoneId": ref("Id"), "paused": b("No automatic offers; waiting steps and the search end keep running."),
                            "mode": {"oneOf": [s(enum=DP["modes"]), {"type": "null"}], "description": "Forced mode for new searches; null = the rules."},
                            "by": ref("Id"), "at": ref("Timestamp"), "version": i(minimum=0)},
                           ["zoneId", "paused", "mode", "version"], "Live dispatch switch of a zone (outside publishing). " + DP["control"]["note"])
S["DispatchControlCommand"] = obj({"expectedVersion": i("Version of the control being replaced; 0 when the zone has none.", minimum=0), "paused": b(),
                                   "mode": {"oneOf": [s(enum=DP["modes"]), {"type": "null"}]}, "note": s(maxLength=1000)},
                                  ["expectedVersion", "paused", "mode"])
S["SearchStep"] = obj({"id": s(minLength=1), "kind": s(enum=[k for k in DP["waitingKinds"] if k not in DP["skippedWaitingKinds"]]), "message": s(),
                       "extraMin": {"type": ["number", "null"]}, "at": ref("Timestamp")}, ["id", "kind", "message", "extraMin", "at"],
                      "The latest rider-waiting step of the search (v0.5.1, contract.json#dispatch.searchStep). keep_waiting: the app asks Keep waiting / Stop (POST /trips/{tripId}/keep-waiting); busy: the search ended.")
S["RaisePriceCommand"] = obj({"expectedVersion": i(minimum=1), "increase": ref("Money")}, ["expectedVersion", "increase"],
                             "The rider raises their offer while the search is on (owner decision 25, contract.json#dispatch.raisePrice): a positive amount in the trip's currency; "
                             "the new fare may not pass raisePrice.maxFactor × the quoted fare.")
S["KeepWaitingCommand"] = obj({"expectedVersion": i("Optional; the answer does not change the version.", minimum=1), "answer": s(enum=DP["keepWaitingAnswers"])}, ["answer"],
                              "Answer to a keep_waiting step: wait = the search end moves by the step's extraMin; stop = the normal free rider cancel (owner decision 24).")
AA = C["auth"]["admin"]
S["AdminPermission"] = s(C["adminPermissions"]["note"], enum=C["adminPermissions"]["values"], **{"x-groups": C["adminPermissions"]["groups"], "x-v050": {k: v for k, v in C["adminPermissions"]["v050"].items() if k != "note"}})
S["AdminScope"] = obj({"zones": {"oneOf": [s(const="all"), arr(ref("Id"))], "description": "\"all\" or the zone ids the admin may act in."},
                       "countries": arr(ref("CountryCode")), "fleetPartnerId": ref("Id")}, ["zones"])
S["AdminMe"] = obj(OrderedDict([("adminId", ref("Id")), ("email", s(format="email")), ("name", s()), ("role", ref("AdminRole")),
                                ("permissions", arr(ref("AdminPermission"), uniqueItems=True, description="Fully expanded; super has all of them.")),
                                ("scope", ref("AdminScope")), ("language", ref("Language")),
                                ("idleTimeoutSeconds", {**i(minimum=AA["idleTimeoutMinutesRange"][0] * 60, maximum=AA["idleTimeoutMinutesRange"][1] * 60), "default": AA["idleTimeoutSecondsDefault"]}),
                                ("approvalExempt", b("v0.7.2: true for every admin (one admin is enough everywhere, owner 2026-10-28): changes go live at once, never 202 pending_approval."))]),
                   ["adminId", "email", "name", "role", "permissions", "scope", "idleTimeoutSeconds", "approvalExempt"], "The signed-in admin (maps 1:1 onto the panel's Agent; adminId = id).")
S["AdminSession"] = obj({"accessToken": s(minLength=1), "refreshToken": s("Opaque, rotated on every refresh.", minLength=1),
                         "expiresIn": {**i(minimum=1), "default": AA["accessExpiresSeconds"]}, "actor": s(const="admin"), "admin": ref("AdminMe")},
                        ["accessToken", "refreshToken", "expiresIn", "actor", "admin"], AA["note"])
S["AdminSignInRequest"] = obj({"email": s(format="email", maxLength=254), "password": s(minLength=1, maxLength=256, writeOnly=True)}, ["email", "password"])
S["SetupPasswordRequest"] = obj({"setupToken": s(minLength=16), "password": s(minLength=AA["passwordMinLength"], maxLength=256, writeOnly=True)}, ["setupToken", "password"],
                                f"One-time link token (single use, {AA['setupLinkHours']} h). Password at least {AA['passwordMinLength']} characters, stored as argon2id.")
S["SetupTokenRequest"] = obj({"setupToken": s(minLength=16)}, ["setupToken"])
S["SetupLinkInfo"] = obj({"email": s(format="email"), "name": s(), "expiresAt": ref("Timestamp")}, ["email", "name", "expiresAt"])
S["SetupLink"] = obj({"url": s(format="uri"), "expiresAt": ref("Timestamp")}, ["url", "expiresAt"], "A one-time password setup link for an admin; send it to them out of band.")
MP = C["maps"]
S["AutocompleteRequest"] = obj({"query": s(minLength=1, maxLength=200), "latitude": n(minimum=-90, maximum=90), "longitude": n(minimum=-180, maximum=180),
                                "limit": i(minimum=1, maximum=MP["autocompleteMaxSuggestions"], default=MP["autocompleteMaxSuggestions"])}, ["query"],
                               "latitude / longitude: the bias point (wire exception, contract.json#wire.location.locationsException).")
S["AddressSuggestion"] = obj({"title": s(minLength=1), "subtitle": s(), "latitude": n(minimum=-90, maximum=90), "longitude": n(minimum=-180, maximum=180),
                              "placeId": s("Provider place id; send it to /locations/geocode to resolve a suggestion without coordinates.")}, ["title"])
S["AddressSuggestionList"] = obj({"suggestions": arr(ref("AddressSuggestion"), maxItems=MP["autocompleteMaxSuggestions"], description="Empty = nothing found.")}, ["suggestions"])
S["GeocodeRequest"] = obj({"query": s(minLength=1, maxLength=300), "placeId": s()}, ["query"])
S["GeocodeResult"] = obj({"address": s(), "latitude": n(minimum=-90, maximum=90), "longitude": n(minimum=-180, maximum=180), "placeId": s()},
                         desc="No coordinates = no match (200, never 404).")
S["ReverseGeocodeRequest"] = obj({"latitude": n(minimum=-90, maximum=90), "longitude": n(minimum=-180, maximum=180)}, ["latitude", "longitude"])
S["ReverseGeocodeResult"] = obj({"address": {"type": ["string", "null"], "description": "null or blank = no name for this point."},
                                 "latitude": n(minimum=-90, maximum=90), "longitude": n(minimum=-180, maximum=180)}, ["address", "latitude", "longitude"],
                                "The address in the caller's profile language (or Accept-Language when sent).")
S["LatLng"] = obj({"lat": n(minimum=-90, maximum=90), "lng": n(minimum=-180, maximum=180)}, ["lat", "lng"])
TPATH = C["tripPath"]
S["TripPath"] = obj({"tripId": ref("Id"), "source": s(enum=TPATH["sources"], description="driven: thinned from the trip's GPS trace; planned: the server's road route (trace deleted or never sent)."),
                     "points": arr(ref("LatLng"), minItems=2, maxItems=TPATH["maxPoints"], description="The line, in order."),
                     "pickup": ref("LatLng"), "dropoff": ref("LatLng"), "stops": arr(ref("LatLng"), description="Middle stops, in order."),
                     "keptUntil": ref("Timestamp")},
                    ["tripId", "source", "points", "pickup", "dropoff", "stops"],
                    "v0.17.0 (CONTRACT.md §25): the route of an ended trip. " + TPATH["retention"], addl=False)
CPV = C["completePreview"]
S["CompletePreview"] = obj({"previewId": ref("Id"), "expiresAt": {"allOf": [ref("Timestamp")], "description": "The frozen price holds until then (freezeSeconds after the call)."},
                            "tripId": ref("Id"), "total": ref("Money"),
                            "cashDue": {"allOf": [ref("Money")], "description": "What the driver collects in cash: total less what the rider's wallet would pay. Send it as cashCollected on complete."},
                            "driverEarnings": {"allOf": [ref("Money")], "description": "The driver's part of total (TripProjection.driverEarnings after complete)."},
                            "earlyEnd": {"type": "boolean", "description": "The driver is farther than " + str(C["pricing"]["completeNearDropoffMeters"]) + " m from the drop-off: priced as what was driven (owner decision 28)."},
                            "fareLines": arr(ref("FareLine"))},
                           ["previewId", "expiresAt", "tripId", "total", "cashDue", "driverEarnings", "earlyEnd", "fareLines"],
                           "v0.18.1 (CONTRACT.md §26): the final price complete would set now, frozen for " + str(CPV["freezeSeconds"]) + " s. " + CPV["same"], addl=False)
S["RouteRequest"] = obj({"mode": s(enum=MP["routeModes"]), "from": ref("LatLng"), "to": ref("LatLng")}, ["mode", "from", "to"])
S["RoadRoute"] = obj({"points": arr(ref("LatLng"), minItems=2, description="The road geometry, in order."), "distanceMeters": i(minimum=0),
                      "durationSeconds": ref("DurationSeconds"), "provider": s(examples=["osrm"])}, ["points"],
                     "Road route for drawing. ETA shown to the rider stays TripProjection.etaSeconds.")
S["OsrmManeuver"] = obj({"type": s(), "modifier": s(), "location": arr(n(), minItems=2, maxItems=2, description="[lng, lat]"), "exit": i(), "bearing_before": n(), "bearing_after": n()},
                        ["type", "location"])
S["OsrmIntersection"] = obj({"classes": arr(s()), "lanes": arr(obj({"indications": arr(s()), "valid": b()}))})
S["OsrmStep"] = obj({"name": s(), "ref": s(), "destinations": s(), "exits": s(), "driving_side": s(), "distance": n(minimum=0), "duration": n(minimum=0),
                     "maneuver": ref("OsrmManeuver"), "intersections": arr(ref("OsrmIntersection"))}, ["distance", "maneuver"])
S["OsrmRoute"] = obj({"geometry": obj({"type": s(const="LineString"), "coordinates": arr(arr(n(), minItems=2, maxItems=2), minItems=2, description="[lng, lat] pairs")}, ["coordinates"]),
                      "distance": n(minimum=0), "duration": n(minimum=0), "legs": arr(obj({"steps": arr(ref("OsrmStep")), "distance": n(), "duration": n()}))},
                     ["geometry", "distance", "duration"])
S["OsrmRouteResponse"] = obj({"code": s("Ok, or NoRoute (still 200).", examples=["Ok", "NoRoute"]), "routes": arr(ref("OsrmRoute")), "waypoints": arr({"type": "object"})}, ["code", "routes"],
                             "OSRM v5 route response passed through from Movera's OSRM; only the documented subset is contract, other fields may appear.")
TL = C["telemetry"]
S["TelemetryLog"] = obj({"level": s(enum=TL["levels"]), "event": s(minLength=1, maxLength=200), "extra": {"type": "object"}, "error": s(maxLength=4000)}, ["level", "event"])
S["TelemetryEvent"] = obj({"event": s(minLength=1, maxLength=200), "extra": {"type": "object"}}, ["event"])
# v0.16.0 (owner 2026-10-29, Crashes & errors): optional fields that let the server group and filter reports (contract.json#telemetry.crashReport).
TC = TL["crashReport"]; TE = TL["errorGroups"]
S["TelemetryCrash"] = obj({"error": s(maxLength=4000), "stack": s(maxLength=12000), "extra": {"type": "object"},
                           "app": s("v0.16.0", enum=TC["apps"]), "platform": s("v0.16.0", enum=TC["platforms"]),
                           "appVersion": s("v0.16.0: e.g. 1.4.2.", maxLength=40), "build": s("v0.16.0: store build number.", maxLength=40),
                           "screen": s("v0.16.0: route or screen name, no ids.", maxLength=200),
                           "kind": s(f"v0.16.0: crash (the app stopped) or error (caught). Default {TC['defaultKind']}.", enum=TC["kinds"]),
                           "occurredAt": ref("Timestamp")}, ["error"], TC["note"])
S["ErrorGroup"] = obj({"id": ref("Id"), "app": s(enum=TE["apps"]), "platform": s(enum=TE["platforms"]),
                       "appVersions": arr(s(), description="Versions seen in this group, newest first."), "message": s("Scrubbed message of the latest report."),
                       "topFrame": s("Top stack frame used in the fingerprint, when there was a stack."), "kind": s(enum=TC["kinds"]),
                       "count": i("Reports in this group.", minimum=1), "devices": i("Distinct devices (or addresses) that sent one.", minimum=0),
                       "firstSeen": ref("Timestamp"), "lastSeen": ref("Timestamp"), "status": s(enum=TE["statuses"]),
                       "fixedAt": {"anyOf": [ref("Timestamp"), {"type": "null"}]}},
                      ["id", "app", "platform", "appVersions", "message", "kind", "count", "devices", "firstSeen", "lastSeen", "status"], TE["note"])
S["ErrorGroupStatusCommand"] = obj({"status": s(enum=TE["statuses"])}, ["status"], "v0.16.0: " + TE["reopen"] + ".")
LD = C["liveDrivers"]
S["LiveDriver"] = obj(OrderedDict([("driverId", ref("Id")), ("firstName", s()), ("onlineStatus", ref("DriverOnlineStatus")), ("moving", b()),
                                   ("location", ref("GeoFix")), ("lastFixAt", ref("Timestamp")),
                                   ("stale", b(f"No fix for more than staleAfterSeconds ({LD['staleAfterSeconds']} s).")), ("activeTripId", ref("Id")),
                                   ("tripStatus", ref("TripStatus")), ("vehicleId", ref("Id")), ("plate", s()), ("zoneId", ref("Id"))]),
                      ["driverId", "firstName", "onlineStatus", "stale", "zoneId"])
S["ZoneRidersOnline"] = obj({"zoneId": ref("Id"), "count": i(minimum=0)}, ["zoneId", "count"], "v0.18.4 (G3-R4): " + C["driverHome"]["ridersOnline"]["note"])
DS = C["driverHome"]["zoneSupply"]
S["ZoneSupply"] = obj(OrderedDict([("zoneId", ref("Id")), ("online", i(minimum=0)), ("free", i(minimum=0)), ("busy", i(minimum=0)), ("waiting", i(minimum=0)),
                                   ("level", s(enum=DS["levels"])), ("shortage", b())]),
                      ["zoneId", "online", "free", "busy", "waiting", "level", "shortage"], "v0.18.4 (G3-D5): " + DS["note"])
S["LiveDriverList"] = obj({"zoneSupply": arr(ref("ZoneSupply"), description="v0.18.4 (G3-D5): supply and demand per zone; the Dashboard's rows and shortage alert."),"items": arr(ref("LiveDriver")), "staleAfterSeconds": {**i(minimum=1), "default": LD["staleAfterSeconds"]}, "serverTime": ref("Timestamp"),
                           "ridersOnline": arr(ref("ZoneRidersOnline"), description="v0.18.4 (G3-R4): real riders online per zone of the admin, the Dashboard's 'Riders online'."),
                           "ridersOnlineWindowSeconds": {**i(minimum=1), "default": C["driverHome"]["ridersOnline"]["windowSeconds"]}},
                          ["items", "staleAfterSeconds", "serverTime"], f"Drivers on the admin live map; the panel polls about every {LD['pollSeconds']} s.")
S["TripTrace"] = obj({"tripId": ref("Id"), "fixes": arr(ref("GeoFix"), description="In time order."), "keptUntil": ref("Timestamp")}, ["tripId", "fixes"],
                     f"The trip's GPS trace; deleted {LD['traceKeepDays']} days after the trip (owner decision 11).")
RN = C["riderNearby"]
S["NearbyVehicle"] = obj(OrderedDict([
    ("key", s("Opaque, the same for one car through the day (it changes every day), so the app can move the car smoothly between answers. Not a driver or vehicle id.", minLength=6, maxLength=32)),
    ("lat", n(f"Moved {C['driverHome']['nearbyBlur']['minMeters']}–{C['driverHome']['nearbyBlur']['maxMeters']} m (v0.18.4, G3-D4), then rounded to {RN['roundDecimals']} decimals.", minimum=-90, maximum=90)),
    ("lng", n(f"Moved {C['driverHome']['nearbyBlur']['minMeters']}–{C['driverHome']['nearbyBlur']['maxMeters']} m (v0.18.4, G3-D4), then rounded to {RN['roundDecimals']} decimals.", minimum=-180, maximum=180)),
    ("heading", n("Degrees clockwise from north, from the latest fix; absent when unknown.", minimum=0, maximum=360)),
]), ["key", "lat", "lng"], "A free car near the rider (v0.5.2). Nothing that tells who drives it.")
S["NearbyVehicleList"] = obj({"items": arr(ref("NearbyVehicle"), maxItems=RN["maxVehicles"], description="Nearest first."),
                              "refreshSeconds": {**i(minimum=1), "default": RN["refreshSeconds"]},
                              "radiusMeters": {**i(minimum=1), "default": RN["radiusMeters"]}},
                             ["items", "refreshSeconds"], "CONTRACT.md §13: " + RN["note"] + " " + C["driverHome"]["nearbyBlur"]["note"])
S["AccountDeletion"] = obj({"status": s(enum=C["accountDeletion"]["status"])}, ["status"], C["accountDeletion"]["note"])
S["RiderConsents"] = obj({"rideUpdates": b(), "emailUpdates": b(), "promotions": b()})

# --- realtime
S["RealtimeEvent"] = obj(OrderedDict([
    ("eventId", {"allOf": [ref("Id")], "description": "Server-assigned, unique per committed change (dedupe key)."}),
    ("tripId", ref("Id")),
    ("sequence", i("Server-assigned, contiguous per trip. Clients never number events.", minimum=1)),
    ("version", i("Projection version after this event (unchanged for location).", minimum=1)),
    ("kind", ref("RealtimeKind")),
    ("occurredAt", ref("Timestamp")),
    ("serverTime", {"allOf": [ref("Timestamp")], "description": "Send time, for clock-skew correction."}),
    ("projection", ref("TripProjection")),
    ("location", ref("GeoFix")),
    ("etaSeconds", ref("DurationSeconds")),
    ("cancelFee", {"description": "rider_cancelled / driver_cancelled: fee charged to the rider (null = none/undecided).", **nullable("Money")}),
    ("message", ref("Message")),
]), C["realtime"]["envelope"],
    "Trip event envelope (contract.json#realtime). Client gate: " + "; ".join(C["realtime"]["rules"]) + ".",
    **{"x-optional": C["realtime"]["optional"]})
S["OfferEvent"] = obj({"eventId": ref("Id"), "sequence": i("Per-driver feed cursor for `after` replay.", minimum=1),
                       "kind": s(enum=["offer_created", "offer_updated", "offer_withdrawn"]),
                       "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp"),
                       "offer": {"allOf": [ref("Offer")],
                                 "description": "For offer_withdrawn, offer.status is claimed_elsewhere | expired | withdrawn."},
                       "driverOffline": b("v0.8.0: this declined or expired Exclusive offer was the last of the run that set the driver offline (contract.json#autoOffline).")},
                      ["eventId", "sequence", "kind", "occurredAt", "serverTime", "offer"], "Driver offer feed event.")
S["ConfigEvent"] = obj({"eventId": ref("Id"), "kind": s(const="config_published"), "doc": ref("ConfigDocName"),
                        "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"),
                        "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                       ["eventId", "kind", "doc", "zoneId", "version", "publishedAt", "occurredAt", "serverTime"],
                       "Apps re-fetch the config document on this event.")

# --- error
S["Error"] = obj({"code": ref("ErrorCode"), "message": s(), "requestId": s(), "retryable": b(),
                  "reason": s(C["errors"]["reason"], pattern="^[a-z][a-z0-9_]{0,63}$"),
                  "details": {"type": "array", "items": s(), "description": C["errors"]["details"]},
                  "projection": {"description": "Current authoritative resource. Always present for version_mismatch and invalid_transition "
                                                 "(TripProjection for trip commands; Offer / Driver / Rider / Vehicle / ConfigDraft for their commands).",
                                 "anyOf": [ref("TripProjection"), ref("Offer"), ref("Driver"), ref("Rider"), ref("Vehicle"), ref("ConfigDraft"), ref("Incident")]},
                  "preview": {"allOf": [ref("CompletePreview")], "description": "v0.18.1: with reason price_changed on POST /trips/{tripId}/complete, the fresh frozen price to show and collect (CONTRACT.md §26)."}},
                 ["code", "message", "requestId", "retryable"])
S["ConflictError"] = {"allOf": [ref("Error")],
                      "if": {"properties": {"code": {"enum": ["version_mismatch", "invalid_transition"]}}, "required": ["code"]},
                      "then": {"required": ["projection"]},
                      "description": "409 body: version_mismatch | invalid_transition (with projection) or conflict (idempotency key reused with another body, offer claimed elsewhere)."}

# --- pages (Page<T>)
S["Page"] = obj({"items": arr({}), "nextCursor": {"type": ["string", "null"], "description": "Opaque; null on the last page."}},
                ["items", "nextCursor"], "Generic cursor page Page<T>. Concrete pages below narrow `items`.")
PAGES = ["TripProjection", "Offer", "Rider", "Driver", "Vehicle", "Document", "PaymentIntent", "Refund", "Payout",
         "WalletEntry", "Notification", "Message", "SupportTicket", "Incident", "AuditEntry", "Approval",
         "SavedPlace", "SavedPaymentMethod", "RealtimeEvent", "Quote", "AdminDispatchEvent", "Fleet", "AdminIncidentEvent", "AdminRating"]
for p in PAGES:
    S[f"{p}Page"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref(p))}}],
                     "description": f"Page<{p}>"}

# --- request bodies
EV = {"expectedVersion": i("Version the caller last saw; stale → 409 version_mismatch.", minimum=1)}
S["TripCommand"] = obj(dict(EV, location=ref("GeoFix")), ["expectedVersion"], "Body of driver trip commands.")
S["BoardCommand"] = {"allOf": [ref("TripCommand"), obj({"verifiedPinToken": s("Required when the trip has pinRequired=true.")})]}
S["CompleteCommand"] = {"allOf": [ref("TripCommand"), obj({"previewId": {"allOf": [ref("Id")], "description": "v0.18.1: the latest complete-preview's previewId. " + C["completePreview"]["frozen"] + " " + C["completePreview"]["unfrozen"]}, "cashCollected": {"allOf": [ref("Money")], "description": "v0.18.1: on a cash trip the cashDue of GET /driver/trips/{tripId}/complete-preview that the app showed; at most the fare less the wallet (else 400 cash_above_fare). Absent: the fare less the wallet."}})]}
S["NoShowCommand"] = {"allOf": [ref("TripCommand"), obj({"reasonCode": ref("NoShowReasonCode")})]}
S["CancelCommand"] = obj(dict(EV, reasonCode=ref("CancelReasonCode"), note=s(maxLength=1000), location=ref("GeoFix")),
                         ["expectedVersion", "reasonCode"],
                         "Actor comes from the token; reasonCode must be in the actor's group (rider; driverBeforeTrip/driverDuringTrip/scheduled/driverNextTrip).")
S["EndEarlyCommand"] = obj(dict(EV, reasonCode=ref("RiderCancelReasonCode"), note=s(maxLength=1000)), ["expectedVersion"])
S["CancelReasonCommand"] = obj({"reasonCode": ref("RiderCancelReasonCode"), "note": s(maxLength=1000)}, ["reasonCode"],
                               "The reason a rider tells after a cancel-first (owner decision 6, v0.4.4). No expectedVersion: "
                               "the trip's version does not change.")
PRICE_EXTRAS = {"babySeats": {**i("v0.6.0, deprecated in v0.7.1 (read for one release): above 0 on any category but child_seat is 400 seat_not_offered; on child_seat it changes nothing (the trip always includes one seat).", minimum=0, maximum=3), "deprecated": True},
       "childSeats": {**i("v0.6.0, deprecated in v0.7.1: as babySeats.", minimum=0, maximum=3), "deprecated": True},
       "airportPickup": {**b("v0.6.0, deprecated in v0.7.1: ignored; the server decides the airport fees from the airport zones."), "deprecated": True},
       "airportDropoff": {**b("v0.6.0, deprecated in v0.7.1: ignored."), "deprecated": True},
       "fixedRouteId": {"allOf": [ref("Id")], "description": "v0.6.0: one of the zone's fixed routes; for a route of the quoted category the fixed_route line replaces the ride part, otherwise the category is priced normally."}}
S["QuoteRequest"] = obj({"pickup": ref("Place"), "dropoff": ref("Place"), "stops": arr(ref("Place"), description="MUST be sent (may be empty)."),
                         "categoryIds": arr(ref("CategoryId"), description="Omit for every category in the zone."),
                         "kind": ref("TripKind"), "scheduledAt": ref("Timestamp"), "paymentMethod": ref("PaymentMethod"), **PRICE_EXTRAS},
                        ["pickup", "dropoff", "stops"])
S["QuoteList"] = obj({"quotes": arr(ref("Quote")), "zoneId": ref("Id"), "serverTime": ref("Timestamp")}, ["quotes", "zoneId"])
S["CreateTripRequest"] = obj({"quoteId": ref("Id"), "categoryId": ref("CategoryId"), "pickup": ref("Place"),
                              "dropoff": ref("Place"), "stops": arr(ref("Place")), "kind": ref("TripKind"),
                              "scheduledAt": ref("Timestamp"), "paymentMethod": ref("PaymentMethod"),
                              "paymentMethodId": ref("Id"), "walletFirst": b("Use wallet balance before the method."),
                              "notes": s(maxLength=500), **PRICE_EXTRAS},
                             ["quoteId", "categoryId", "pickup", "dropoff", "stops", "kind", "paymentMethod"],
                             "Request a quoted trip. No expectedVersion: the trip does not exist yet; Idempotency-Key dedupes. v0.6.0: babySeats, childSeats, airportPickup, airportDropoff and fixedRouteId repeat the quote's (else 400 quote_mismatch).")
S["UpdateTripRequest"] = obj(dict(EV, routeQuoteId=ref("Id"), dropoff=ref("Place"), stops=arr(ref("Place")),
                                  paymentMethod=ref("PaymentMethod"), paymentMethodId=ref("Id"),
                                  pickup={"allOf": [ref("Place")], "description": "v0.5.1, optional: move the pickup, at most booking.maxPickupMoveMeters after accept."}),
                             ["expectedVersion"], "Route change (needs routeQuoteId from /route-quote) and/or payment method change.")
S["RouteQuoteRequest"] = obj(dict(EV, dropoff=ref("Place"), stops=arr(ref("Place")),
                                  pickup={"allOf": [ref("Place")], "description": "v0.5.1, optional: price a moved pickup."}), ["expectedVersion", "stops"])
S["RatingRequest"] = obj({"stars": i("Whole stars (contract.json#ratings).", minimum=C["ratings"]["min"], maximum=C["ratings"]["max"]), "tags": arr(s(pattern="^[a-z][a-z0-9_]{0,63}$")),
                          "comment": s(maxLength=2000), "skip": b("Skip rating (ratingStatus → skipped)."),
                          "tip": {"allOf": [ref("Money")], "description": "Rider only; creates a tip PaymentIntent."}},
                         desc="stars required unless skip=true.")
S["AvailabilityRequest"] = obj(dict(EV, onlineStatus=s("Requested state; server answers going_online/online/offline.", enum=["online", "offline"]),
                                    location=ref("GeoFix")), ["expectedVersion", "onlineStatus"])
S["LocationBatch"] = obj({"fixes": arr(ref("GeoFix"), minItems=1, maxItems=50), "tripId": ref("Id")}, ["fixes"])
S["OfferCommand"] = obj(EV, ["expectedVersion"])
S["DeclineOfferCommand"] = obj(dict(EV, reasonCode=s(pattern="^[a-z][a-z0-9_]{0,63}$")), ["expectedVersion"])
S["PinVerifyRequest"] = obj({"pin": s(pattern=r"^\d{4}$", writeOnly=True)}, ["pin"])
S["MessageRequest"] = obj({"text": s(minLength=1, maxLength=2000)}, ["text"])
S["TicketRequest"] = obj({"tripId": ref("Id"), "category": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "subject": s(minLength=1, maxLength=200),
                          "text": s(minLength=1, maxLength=5000)}, ["category", "subject", "text"])
S["PaymentRequest"] = obj({"purpose": s(enum=["trip", "wallet_topup", "tip"]), "tripId": ref("Id"), "amount": ref("Money"),
                           "method": ref("PaymentMethod"), "paymentMethodId": ref("Id")}, ["purpose", "amount", "method"])
S["TopupRequest"] = obj({"amount": ref("Money"), "method": ref("PaymentMethod"), "paymentMethodId": ref("Id")}, ["amount", "method"])
S["AddPaymentMethodRequest"] = obj({"method": ref("PaymentMethod"), "pspToken": s("Tokenised card/account from the PSP SDK.", minLength=1),
                                    "makeDefault": b()}, ["method", "pspToken"])
S["DefaultPaymentMethodRequest"] = obj({"method": ref("PaymentMethod"), "paymentMethodId": ref("Id")}, ["method"])
S["RiderProfileUpdate"] = obj(dict(EV, firstName=s(minLength=1), email=s(format="email"), language=s(pattern="^[a-z]{2}(-[A-Z]{2})?$"),
                                   consents=obj({"rideUpdates": b(), "emailUpdates": b(), "promotions": b()})), ["expectedVersion"])
S["DriverProfileUpdate"] = obj(dict(EV, firstName=s(minLength=1), vehicleId=ref("Id"), categoryIds=arr(ref("CategoryId"))), ["expectedVersion"])
S["SavedPlaceRequest"] = obj({"label": s(minLength=1, maxLength=80), "kind": s(enum=["home", "work", "other"]), "place": ref("Place")},
                             ["label", "kind", "place"])
S["VehicleRequest"] = obj({"make": s(), "model": s(), "year": i(minimum=1950, maximum=2100), "color": s(), "plate": s(),
                           "seats": i(minimum=1, maximum=20), "categoryIds": arr(ref("CategoryId"))},
                          ["make", "model", "year", "color", "plate", "seats"])
S["DocumentUpload"] = obj({"type": ref("DocumentType"), "ownerId": {"allOf": [ref("Id")], "description": "vehicleId for vehicle documents; defaults to the driver."},
                           "expiresAt": ref("Timestamp"), "file": s(contentMediaType="application/octet-stream")}, ["type", "file"])
REASON = {"reasonCode": ref("AdminCancelReasonCode"), "note": s(minLength=1, maxLength=1000)}
S["AdminCancelCommand"] = obj(dict(EV, **REASON), ["expectedVersion", "reasonCode", "note"], "Reason required.")
S["AdminReassignCommand"] = obj(dict(EV, **REASON), ["expectedVersion", "reasonCode", "note"])
BONUS = {"driverBonus": {"allOf": [ref("Money")], "description": "Movera-paid extra for the driver, in the zone's currency; over driverBonus.defaultLimit → 400 invalid_request."},
         "priority": b("Show the Priority badge on the offer.")}
S["AdminAssignCommand"] = obj(dict(EV, driverId=ref("Id"), note=s(maxLength=1000), **BONUS), ["expectedVersion", "driverId"],
                              "Direct assign: an exclusive offer to one driver (offer kind=assigned, source=admin); the driver accepts or declines. "
                              "409 invalid_transition once a driver has accepted (locked).")
S["AdminRadarGroupCommand"] = obj(dict(EV, driverIds=arr(ref("Id"), minItems=C["adminDispatch"]["radarGroup"]["minDrivers"],
                                                          maxItems=C["adminDispatch"]["radarGroup"]["maxDrivers"], uniqueItems=True),
                                       note=s(maxLength=1000), **BONUS), ["expectedVersion", "driverIds"],
                                  "Radar group: one radar offer per chosen driver on the zone's normal timer; the first to accept wins. Repeatable until locked.")
S["AdminRadarGroup"] = obj({"groupId": ref("Id"), "tripId": ref("Id"), "offers": arr(ref("Offer")),
                            "expiresAt": {"allOf": [ref("Timestamp")], "description": "Countdown end shown to the admin."},
                            "projection": ref("TripProjection")}, ["groupId", "tripId", "offers", "expiresAt", "projection"])
S["AdminDriverBonusCommand"] = obj(dict(EV, amount=ref("Money"), priority=b(), note=s(maxLength=1000)), ["expectedVersion", "amount"],
                                   "Add money to the trip for the driver (paid by Movera). Open offers are updated (offer_updated) with the new fare.")
S["NearbyDriver"] = obj({"driverId": ref("Id"), "firstName": s(), "onlineStatus": ref("DriverOnlineStatus"), "moving": b("Latest GeoFix.moving (v0.5.0)."),
                         "location": ref("GeoFix"), "distanceMeters": i(minimum=0), "pickupEtaSeconds": ref("DurationSeconds"),
                         "zoneId": ref("Id"), "categoryIds": arr(ref("CategoryId")), "openOfferId": ref("Id")},
                        ["driverId", "firstName", "onlineStatus", "distanceMeters"])
S["NearbyDriverList"] = obj({"items": arr(ref("NearbyDriver")), "scope": s(enum=C["adminDispatch"]["nearbyScopes"]),
                             "radiusKm": n(minimum=0)}, ["items", "scope"])
S["AdminDispatchEvent"] = obj({"eventId": ref("Id"), "sequence": i(minimum=1), "kind": s(enum=C["adminDispatch"]["eventKinds"]),
                               "tripId": ref("Id"), "groupId": ref("Id"), "offer": ref("Offer"), "projection": ref("TripProjection"),
                               "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                              ["eventId", "sequence", "kind", "tripId", "occurredAt", "serverTime"],
                              "Admin dispatch feed: offers sent, declined, expired, withdrawn or accepted, the lock, and driver bonuses.")
S["AdminNoShowCommand"] = obj(dict(EV, note=s(minLength=1, maxLength=1000), waiveFee=b()), ["expectedVersion", "note"])
S["AdminCompleteCommand"] = obj(dict(EV, fare=ref("Money"), note=s(minLength=1, maxLength=1000)), ["expectedVersion", "note"])
S["AdminRefundCommand"] = obj(dict(EV, amount=ref("Money"), paymentId=ref("Id"), reason=s(minLength=1, maxLength=1000)),
                              ["expectedVersion", "amount", "reason"],
                              "v0.7.2: runs at once for every admin with the permission (one admin is enough, owner 2026-10-28).")
S["AdminAdjustCommand"] = obj(dict(EV, fare=ref("Money"), waitingSeconds=i(minimum=0), waiveCancelFee=b(),
                                   reason=s(minLength=1, maxLength=1000)), ["expectedVersion", "reason"],
                              "Fare / waiting / cancel-fee correction; runs at once (v0.7.2, one admin is enough).")
S["DriverStatusCommand"] = obj(dict(EV, accountStatus=ref("DriverAccountStatus"), note=s(minLength=1, maxLength=1000)),
                               ["expectedVersion", "accountStatus", "note"])
S["RiderStatusCommand"] = obj(dict(EV, status=s(enum=["active", "suspended"]), note=s(minLength=1, maxLength=1000)),
                              ["expectedVersion", "status", "note"])
S["VehicleReviewCommand"] = obj(dict(EV, decision=s(enum=["approved", "rejected", "blocked"]), note=s(maxLength=1000)),
                                ["expectedVersion", "decision"])
S["DocumentReviewCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "expiresAt": ref("Timestamp"),
                                  "note": s(maxLength=1000)}, ["decision"],
                                 "Document has no version in CONTRACT.md §2; Idempotency-Key only.")
S["FleetCompany"] = obj({"name": s(minLength=1, maxLength=120), "orgNumber": s("Organisationsnummer (SE) or SIREN / SIRET (FR).", minLength=5, maxLength=20),
                         "address": s(minLength=1, maxLength=200)}, ["name", "orgNumber", "address"], "v0.5.3: the company of a fleet account.")
S["FleetJoinRequest"] = obj({"code": s("Case-insensitive; spaces and a missing MV- are forgiven.", minLength=5, maxLength=12),
                             "ownerName": s("The fleet owner's first and last name as registered (case and spaces are forgiven).", minLength=1, maxLength=120),
                             "ownerEmail": s("The fleet owner's e-mail as registered (case is forgiven).", format="email")},
                            ["code", "ownerName", "ownerEmail"],
                            "v0.5.3: all three must match one approved fleet; any mismatch is 400 invalid_request with reason fleet_join_mismatch "
                            "(one message for all three). Limited to contract.json#driverOnboarding.fleetCode.joinAttemptsPerHour, then 429.")
S["DriverOnboardingRequest"] = obj({"firstName": s(minLength=1, maxLength=60), "lastName": s(minLength=1, maxLength=60),
                                    "dateOfBirth": s("YYYY-MM-DD; younger than minAge → 400 invalid_request (under_age).", format="date"),
                                    "email": s(format="email"), "country": ref("DriverCountry"),
                                    "cityId": s("A cityId of the country (invalid_city)."), "language": s(pattern="^[a-z]{2}(-[A-Z]{2})?$"),
                                    "accountType": ref("DriverAccountType"),
                                    "termsAccepted": {"type": "boolean", "const": True, "description": "Must be true (terms_required); stored as the terms document, approved."},
                                    "company": {"allOf": [ref("FleetCompany")], "description": "Required for accountType fleet (company_required); ignored for driver."},
                                    "fleetJoin": {"allOf": [ref("FleetJoinRequest")], "description": "Optional for accountType driver: join a fleet now (or later with POST /driver/fleet/join)."}},
                                   ["firstName", "lastName", "dateOfBirth", "email", "country", "cityId", "language", "accountType", "termsAccepted"],
                                   "v0.5.3: the details screen after the first sign-in. Allowed while accountStatus is pending or on_hold "
                                   "(a resend replaces the details); active or suspended → 409 invalid_transition. Moves pending → on_hold.")
S["FleetCodeCommand"] = obj(EV, ["expectedVersion"], "v0.5.3: POST /admin/fleets/{fleetId}/code.")
S["FleetReviewCommand"] = obj(dict(EV, decision=s(enum=["approved", "rejected", "blocked"]), note=s(maxLength=1000)), ["expectedVersion", "decision"],
                              "v0.5.3: approved makes the fleet code (first approval) and lets drivers join; blocked takes every linked driver offline and withdraws their offers.")
S["ConfigDraftUpdate"] = obj(dict(EV, zoneId=ref("Id"), country=ref("CountryCode"), document={"oneOf": CONFIG_DOC_ONE_OF}),
                             ["expectedVersion", "document"], "Exactly one of zoneId or country (v0.8.0). " + C["configDocs"]["scope"])
S["ConfigPublishCommand"] = obj(dict(EV, zoneId=ref("Id"), country=ref("CountryCode"), note=s(maxLength=1000)), ["expectedVersion"], "Exactly one of zoneId or country (v0.8.0).")
S["ApprovalDecision"] = obj({"note": s(maxLength=1000)})

# ---------------------------------------------------------------- parameters / responses
PARAMS = OrderedDict()
def path_id(name, desc=None):
    p = {"name": name, "in": "path", "required": True, "schema": ref("Id")}
    if desc: p["description"] = desc
    return p
for nm in ["tripId", "offerId", "paymentId", "paymentMethodId", "placeId", "notificationId", "driverId", "riderId",
           "vehicleId", "documentId", "approvalId", "fleetId", "invitationId", "incidentId", "payoutId", "ticketId", "errorId"]:
    PARAMS[nm[0].upper() + nm[1:]] = path_id(nm)
PARAMS["RideId"] = path_id("rideId", "Deprecated alias of tripId.")
PARAMS["RatingFrom"] = {"name": "from", "in": "path", "required": True, "description": "v0.9.0: who gave the rating.", "schema": {"type": "string", "enum": ["rider", "driver"]}}
PARAMS["ZoneId"] = path_id("zoneId")
PARAMS["AdminId"] = path_id("adminId")
PARAMS["ConfigDoc"] = {"name": "doc", "in": "path", "required": True, "schema": ref("ConfigDocName")}
PARAMS["IdempotencyKey"] = {"name": "Idempotency-Key", "in": "header", "required": True,
                            "description": "Required on every mutation. Bound to actor + route + body hash; the same key replays the committed response, a different body under the same key is 409 conflict.",
                            "schema": {"type": "string", "minLength": 16, "maxLength": 128}}
PARAMS["RequestId"] = {"name": "X-Request-Id", "in": "header", "required": False, "description": "Client request id, echoed by the server.",
                       "schema": {"type": "string", "maxLength": 128}}
PARAMS["ApiVersion"] = {"name": "X-Api-Version", "in": "header", "required": False, "schema": {"type": "string", "const": C["headers"]["X-Api-Version"]}}
PARAMS["Cursor"] = {"name": "cursor", "in": "query", "required": False, "description": "Opaque cursor from a previous page's nextCursor.",
                    "schema": {"type": "string", "maxLength": 512}}
PARAMS["Limit"] = {"name": "limit", "in": "query", "required": False, "schema": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50}}
PARAMS["After"] = {"name": "after", "in": "query", "required": False, "description": "Replay events with sequence > after (resync cursor = TripProjection.sequence).",
                   "schema": {"type": "integer", "minimum": 0}}
PARAMS["LastEventId"] = {"name": "Last-Event-ID", "in": "header", "required": False,
                         "description": "SSE reconnect: last sequence received (same meaning as `after`).", "schema": {"type": "string"}}
PARAMS["ZoneIdQuery"] = {"name": "zoneId", "in": "query", "required": False, "description": "Defaults to the zone in the token / current location.", "schema": ref("Id")}
PARAMS["ListZoneId"] = {"name": "zoneId", "in": "query", "required": False, "description": "v0.17.2: only this zone (inside the admin's zones; a zone outside them → 403 zone_out_of_scope).", "schema": ref("Id")}
PARAMS["ListZoneIds"] = {"name": "zoneIds", "in": "query", "required": False, "description": "v0.17.2: only these zones, comma separated or repeated (at most 200; one outside the admin's zones → 403 zone_out_of_scope). Joined with zoneId.", "schema": {"type": "array", "items": ref("Id"), "maxItems": 200}, "style": "form", "explode": False}
PARAMS["ListCountry"] = {"name": "country", "in": "query", "required": False, "description": "v0.17.2: only the zones of this country that the admin covers (with zoneId/zoneIds: only those of them in the country).", "schema": ref("CountryCode")}
PARAMS["ZoneIdRequired"] = {"name": "zoneId", "in": "query", "required": True, "schema": ref("Id")}
PARAMS["ConfigZoneId"] = {"name": "zoneId", "in": "query", "required": False, "description": "v0.8.0: the zone's own document; exactly one of zoneId or country.", "schema": ref("Id")}
PARAMS["ConfigCountry"] = {"name": "country", "in": "query", "required": False, "description": "v0.8.0: the country's standard (v0.8.1: also of country_rules); exactly one of zoneId or country.", "schema": ref("CountryCode")}
PARAMS["From"] = {"name": "from", "in": "query", "required": False, "schema": ref("Timestamp")}
PARAMS["To"] = {"name": "to", "in": "query", "required": False, "schema": ref("Timestamp")}
PARAMS["Q"] = {"name": "q", "in": "query", "required": False, "description": "Free-text search.", "schema": {"type": "string", "maxLength": 200}}
def q(name, schema, desc=None, multi=False):
    p = {"name": name, "in": "query", "required": False, "schema": arr(schema) if multi else schema}
    if multi: p.update(style="form", explode=True)
    if desc: p["description"] = desc
    return p

RESP = OrderedDict()
HDR_REQ = {"X-Request-Id": {"description": "Echo of the request id (server-generated if absent).", "schema": {"type": "string"}}}
def err(desc, schema="Error", headers=None):
    r = {"description": desc, "headers": dict(HDR_REQ, **(headers or {})), "content": {"application/json": {"schema": ref(schema)}}}
    return r
RESP["BadRequest"] = err("invalid_request: malformed body, unknown enum, wrong reasonCode group, bad PIN.")
RESP["Unauthenticated"] = err("unauthenticated: missing/expired bearer token.")
RESP["Forbidden"] = err("forbidden: actor/scope/permission from the token does not allow this.")
RESP["NotFound"] = err("not_found")
RESP["Conflict"] = err("version_mismatch / invalid_transition (with projection) or conflict.", "ConflictError")
RESP["RateLimited"] = err("rate_limited; obey Retry-After.", headers={"Retry-After": {"schema": {"type": "integer", "minimum": 0}}})
RESP["Unavailable"] = err("unavailable; retry with the same Idempotency-Key.", headers={"Retry-After": {"schema": {"type": "integer", "minimum": 0}}})
RESP["PendingApproval"] = {"description": "Accepted for two-person approval; nothing changed yet.", "headers": HDR_REQ,
                           "content": {"application/json": {"schema": ref("PendingApproval")}}}

# ---------------------------------------------------------------- paths
PATHS = OrderedDict()
TAGS = OrderedDict()

def op(method, path, opId, summary, actors, tag, params=(), body=None, ok=(200, None), mutation=False,
       transition=None, approval=False, deprecated=False, permission=None, desc=None, ok_desc=None, content=None,
       body_type="application/json", permission_v050=None, read_only=False, ext=None):
    TAGS.setdefault(tag, None)
    o = OrderedDict()
    o["operationId"] = opId
    o["summary"] = summary
    if desc: o["description"] = desc
    o["tags"] = [tag]
    if deprecated: o["deprecated"] = True
    o["x-actor"] = list(actors)
    if transition: o["x-transition"] = transition
    if permission: o["x-permission"] = permission
    if permission_v050: o["x-permission-v050"] = permission_v050
    if read_only: o["x-read-only"] = True
    for k, v in (ext or {}).items(): o[k] = v
    ps = list(params)
    if mutation: ps.append(pref("IdempotencyKey"))
    ps += [pref("RequestId"), pref("ApiVersion")]
    o["parameters"] = ps
    if body:
        o["requestBody"] = {"required": True, "content": {body_type: {"schema": ref(body)}}}
    code, schema = ok
    rs = OrderedDict()
    if content is not None:
        rs[str(code)] = {"description": ok_desc or "OK", "headers": HDR_REQ, "content": content}
    elif schema is None:
        rs[str(code)] = {"description": ok_desc or "No content", "headers": HDR_REQ}
    else:
        sch = schema if isinstance(schema, dict) else ref(schema)
        rs[str(code)] = {"description": ok_desc or "OK", "headers": HDR_REQ, "content": {"application/json": {"schema": sch}}}
    # v0.7.2 (owner 2026-10-28): one admin is enough everywhere, so no operation answers 202 pending_approval any more.
    rs["400"] = rref("BadRequest"); rs["401"] = rref("Unauthenticated"); rs["403"] = rref("Forbidden"); rs["404"] = rref("NotFound")
    if mutation: rs["409"] = rref("Conflict")
    rs["429"] = rref("RateLimited"); rs["503"] = rref("Unavailable")
    o["responses"] = rs
    PATHS.setdefault(path, OrderedDict())[method] = o
    return o

def sse(desc, data_schema, json_page=None):
    c = {"text/event-stream": {"schema": {"type": "string",
                                          "description": desc + f" Each SSE `data:` line is one JSON {data_schema}; `id:` is the sequence; heartbeat comments every 15 s."},
                               "x-sse-data": f"#/components/schemas/{data_schema}"}}
    if json_page:
        c["application/json"] = {"schema": ref(json_page)}
    return c

TP = "TripProjection"
TID = [pref("TripId")]
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
    op("get", "/auth/test-accounts", "listTestAccounts", "Test numbers and their account status (not in production)", ["rider", "driver"], "Auth",
       ok=(200, "TestAccountList"), desc=AU["testAccounts"]["note"]),
]:
    o["security"] = []
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
op("get", "/rider/trips/active", "getRiderActiveTrip", "The rider's current non-terminal live trip", ["rider"], "Rider · Booking",
   ok=(200, TP), desc="204 when there is none.")
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
   params=[pref("ZoneIdQuery")], content=sse("Server-sent events.", "ConfigEvent"))
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
op("get", "/wallet", "getWallet", "Wallet balance (server-owned)", ["rider"], "Rider · Payments", ok=(200, "Wallet"))
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
   desc="Fixes are fanned out as kind=location on the active trip's stream; they never change the projection version.")
op("get", "/driver/offers", "listDriverOffers", "Current offers for the driver", ["driver"], "Driver · Offers",
   params=[pref("Cursor"), pref("Limit"), q("status", ref("OfferStatus"), multi=True), q("kind", ref("OfferKind"), multi=True)],
   ok=(200, "OfferPage"))
op("get", "/driver/offers/stream", "streamDriverOffers", "Offer feed (offer_created / offer_updated / offer_withdrawn)", ["driver"],
   "Realtime", params=[pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "OfferEvent", "OfferPage"),
   ok_desc="SSE feed; `Accept: application/json` returns the current open offers.")
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
   desc="v0.14.0: picking a car (vehicleId) whose Vehicle.requiredDocuments are not all approved → 409 documents_not_approved (reason vehicle_documents_not_approved, details vehicle:<type>).")
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
# ---- Admin
ZF = [pref("ListZoneId"), pref("ListZoneIds"), pref("ListCountry")]
ZF_DESC = " v0.17.2 (contract.json#adminListFilters): zoneId, zoneIds and country narrow the list inside those zones; an unknown query key → 400 invalid_request (reason unknown_filter)."
AL = [pref("Cursor"), pref("Limit")]
lists = {
    "trips": ("TripProjectionPage", "trips.read", [q("status", ref("TripStatus"), multi=True), q("kind", ref("TripKind")), *ZF,
              q("categoryId", ref("CategoryId")), q("riderId", ref("Id")), q("driverId", ref("Id")), q("paymentStatus", ref("PaymentStatus")),
              pref("From"), pref("To"), pref("Q")]),
    "riders": ("RiderPage", "riders.read", [q("status", {"type": "string", "enum": ["active", "suspended"]}), *ZF, pref("Q")]),
    "drivers": ("DriverPage", "drivers.read", [q("accountStatus", ref("DriverAccountStatus"), multi=True),
                q("onlineStatus", ref("DriverOnlineStatus"), multi=True), *ZF, q("categoryId", ref("CategoryId")), pref("Q")]),
    "fleets": ("FleetPage", "drivers.read", [q("status", ref("FleetStatus"), multi=True), q("country", ref("DriverCountry")), pref("ZoneIdQuery"), pref("Q")]),
    "vehicles": ("VehiclePage", "drivers.read", [q("status", ref("VehicleStatus"), multi=True), q("driverId", ref("Id")), q("fleetId", ref("Id")),
                 q("categoryId", ref("CategoryId")), pref("Q")]),
    "payments": ("PaymentIntentPage", "finance.read", [q("status", ref("PaymentStatus"), multi=True), q("method", ref("PaymentMethod")),
                 q("tripId", ref("Id")), q("riderId", ref("Id")), *ZF, pref("From"), pref("To")]),
    "refunds": ("RefundPage", "finance.read", [q("status", ref("RefundStatus"), multi=True), q("paymentId", ref("Id")), q("tripId", ref("Id")),
                pref("From"), pref("To"), *ZF]),
    "payouts": ("PayoutPage", "finance.read", [q("status", {"type": "string", "enum": ["pending", "pending_approval", "paid", "failed", "held"]}, multi=True),
                q("driverId", ref("Id")), pref("From"), pref("To"), *ZF]),
    "tickets": ("SupportTicketPage", "support.reply", [q("status", {"type": "string", "enum": ["open", "pending", "resolved", "closed"]}, multi=True),
                q("priority", {"type": "string", "enum": ["low", "normal", "high", "urgent"]}), q("tripId", ref("Id")),
                q("riderId", ref("Id")), q("driverId", ref("Id")), pref("Q"), *ZF]),
    "incidents": ("IncidentPage", "incidents.read", [q("status", {"type": "string", "enum": ["open", "investigating", "resolved", "dismissed"]}, multi=True),
                  q("severity", {"type": "string", "enum": ["low", "medium", "high", "critical"]}), q("kind", {"type": "string"}),
                  q("tripId", ref("Id")), *ZF, pref("From"), pref("To")]),
}
PERM_V050 = {"vehicles": "fleet.read", "payments": "payments.read", "refunds": "payments.read", "payouts": "payments.read",
             "tickets": "support.read", "incidents": "safety.read"}
ZF_LISTS = {"trips", "riders", "drivers", "payments", "refunds", "payouts", "tickets", "incidents"}
for name, (page, perm, filt) in lists.items():
    op("get", f"/admin/{name}", f"adminList{name.capitalize()}", f"List {name} (cursor paging)", ["admin"], "Admin · Lists",
       params=AL + filt, ok=(200, page), permission=perm, permission_v050=PERM_V050.get(name),
       desc="Results are limited to the zones in the admin's token scope." + (ZF_DESC if name in ZF_LISTS else ""))
S["WaitlistEntryPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("WaitlistEntry"))}}], "description": "Page<WaitlistEntry>"}
op("get", "/admin/waitlist", "adminListWaitlist", "The sign-in waiting list (newest first)", ["admin"], "Admin · Lists",
   params=AL + [q("app", {"type": "string", "enum": ["rider", "driver"]})], ok=(200, "WaitlistEntryPage"), permission="overview.read",
   desc="v0.15.0 (owner 2026-10-29, decision 5): the numbers that asked to join, newest lastAt first; the admin page reads it again every 15 s. " + AU["waitlist"]["admin"])
# v0.16.0 (owner 2026-10-29): Crashes & errors (contract.json#telemetry.errorGroups).
S["ErrorGroupPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("ErrorGroup"))}}], "description": "Page<ErrorGroup>"}
op("get", "/admin/errors", "adminListErrors", "Crashes & errors, grouped (newest first)", ["admin"], "Admin · System",
   params=AL + [q("app", s(enum=TE["apps"])), q("platform", s(enum=TE["platforms"])), q("version", s(), "An app version the group was seen in."),
                q("status", s(enum=TE["statuses"]))], ok=(200, "ErrorGroupPage"),
   desc="v0.16.0: " + TE["fingerprint"] + ". " + TE["admin"] + " Permission: " + TE["permission"] + ".")
op("patch", "/admin/errors/{errorId}", "adminSetErrorStatus", "Mark a crash or error group fixed (or open)", ["admin"], "Admin · System",
   params=[pref("ErrorId")], body="ErrorGroupStatusCommand", ok=(200, "ErrorGroup"), mutation=True,
   desc="v0.16.0: " + TE["reopen"] + ". Audited. Permission: " + TE["permission"] + ".")
op("get", "/admin/trips/{tripId}", "adminGetTrip", "Trip detail incl. money split", ["admin"], "Admin · Trips",
   params=TID, ok=(200, TP), permission="trips.read")
for seg, cmd, opid, body, summ, perm, appr, okc in [
        ("cancel", "cancel", "adminCancelTrip", "AdminCancelCommand", "Cancel any non-terminal trip", "trips.intervene", False, (200, TP)),
        ("reassign", "reassign", "adminReassignTrip", "AdminReassignCommand", "Take the trip from its driver, back to searching", "trips.intervene", False, (200, TP)),
        ("assign", "assign", "adminAssignTrip", "AdminAssignCommand", "Direct assign: exclusive offer to one driver (Assigned by Movera)", "trips.intervene", False, (200, TP)),
        ("radar-group", "assign", "adminSendRadarGroup", "AdminRadarGroupCommand", "Send the trip to a radar group of up to 10 drivers", "trips.intervene", False, (200, "AdminRadarGroup")),
        ("no-show", "no_show", "adminMarkNoShow", "AdminNoShowCommand", "Mark rider no-show", "trips.intervene", False, (200, TP)),
        ("complete", "complete", "adminCompleteTrip", "AdminCompleteCommand", "Force-complete a stuck onboard trip", "trips.intervene", False, (200, TP)),
        ("refund", None, "adminRefundTrip", "AdminRefundCommand", "Refund (full or partial)", "payments.refund", True, (201, "Refund")),
        ("adjust", None, "adminAdjustTrip", "AdminAdjustCommand", "Adjust fare / waiting / waive cancel fee", "trips.intervene", True, (200, TP)),
        ("driver-bonus", None, "adminAddDriverBonus", "AdminDriverBonusCommand", "Add money to the trip for the driver (paid by Movera)", "trips.intervene", False, (200, TP))]:
    op("post", f"/admin/trips/{{tripId}}/{seg}", opid, summ, ["admin"], "Admin · Trips", params=TID, body=body, ok=okc,
       mutation=True, transition=cmd, approval=appr, permission=perm, permission_v050="payments.edit" if seg == "refund" else "trips.edit",
       desc=(None if cmd else "Not a lifecycle transition (status unchanged; paymentStatus/fare change and emit payment_updated / trip_projection).")
            if not appr else ("Not a lifecycle transition (status unchanged; paymentStatus/fare change and emit payment_updated / trip_projection). " if not cmd else "")
            + "v0.7.2 (owner 2026-10-28, one admin is enough): 200 / 201 at once for every admin with the permission, written in the audit.")
op("get", "/admin/trips/{tripId}/offers", "adminListTripOffers", "Offers of a trip (who has it, countdown)", ["admin"], "Admin · Dispatch",
   params=TID + AL, ok=(200, "OfferPage"), permission="trips.read")
op("get", "/admin/trips/{tripId}/nearby-drivers", "adminNearbyDrivers", "Active drivers near the trip's pickup", ["admin"], "Admin · Dispatch",
   params=TID + [q("scope", {"type": "string", "enum": C["adminDispatch"]["nearbyScopes"], "default": "radius"}),
                 q("radiusKm", {"type": "number", "minimum": 0.1, "maximum": 100,
                                "examples": C["adminDispatch"]["nearbyRadiusPresetsKm"]}, "Presets 5 / 7 / 10 km or any number (scope=radius).")],
   ok=(200, "NearbyDriverList"), permission="trips.read")
op("get", "/admin/dispatch/stream", "adminStreamDispatch", "Admin dispatch feed (offers, lock, driver bonus)", ["admin"], "Realtime",
   params=[pref("ZoneIdQuery"), pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "AdminDispatchEvent", "AdminDispatchEventPage"),
   permission="trips.read")
# ---- v0.9.0 (CONTRACT.md §18): real data for the admin
op("post", "/admin/payouts", "adminCreatePayout", "Create payout by hand (driver + date range)", ["admin"], "Admin · Money",
   body="PayoutCreateCommand", ok=(201, "Payout"), mutation=True, permission="finance.edit",
   desc="v0.9.0. Same calculation as the weekly job; trips already in a payout are never counted again. 409 nothing_to_pay when no trip is left.")
op("post", "/admin/payouts/{payoutId}/paid", "adminMarkPayoutPaid", "Mark a payout as paid", ["admin"], "Admin · Money",
   params=[pref("PayoutId")], body="PayoutPaidCommand", ok=(200, "Payout"), mutation=True, permission="finance.edit", desc="v0.9.0. 409 invalid_transition when it is already paid.")
op("get", "/support/tickets/{ticketId}", "getOwnTicket", "One own support ticket with its messages", ["rider", "driver"], "Support",
   params=[pref("TicketId")], ok=(200, "SupportTicket"), desc="v0.9.0.")
op("get", "/admin/tickets/{ticketId}", "adminGetTicket", "A support ticket with its messages", ["admin"], "Admin · Support",
   params=[pref("TicketId")], ok=(200, "SupportTicket"), permission="support.reply", desc="v0.9.0. In the admin's zones only (else 403 zone_out_of_scope). v0.13.0: support.reply is needed to read too.")
op("post", "/admin/tickets/{ticketId}/reply", "adminReplyTicket", "Answer a support ticket", ["admin"], "Admin · Support",
   params=[pref("TicketId")], body="TicketReplyCommand", ok=(200, "SupportTicket"), mutation=True, permission="support.reply",
   desc="v0.9.0. The person sees the answer in the app (GET /support/tickets/{ticketId}). v0.13.0: the admin's zones only (else 403 zone_out_of_scope); audited.")
op("get", "/admin/ratings", "adminListRatings", "Ratings riders and drivers gave each other", ["admin"], "Admin · Reviews",
   params=AL + [q("rater", {"type": "string", "enum": ["rider", "driver"]}, "Who gave the rating."), q("hidden", {"type": "boolean"}), q("maxStars", {"type": "integer", "minimum": 1, "maximum": 5}),
                q("driverId", ref("Id")), q("riderId", ref("Id")), *ZF, pref("From"), pref("To")],
   ok=(200, "AdminRatingPage"), permission="settings.read", desc="v0.9.0. Newest first; limited to the admin's zones." + ZF_DESC)
for verb, summ in [("hide", "Hide a rating"), ("restore", "Show a hidden rating again")]:
    op("post", f"/admin/ratings/{{tripId}}/{{from}}/{verb}", f"admin{verb.capitalize()}Rating", summ, ["admin"], "Admin · Reviews",
       params=TID + [pref("RatingFrom")], body="RatingModerationCommand", ok=(200, "AdminRating"), mutation=True, permission="settings.publish",
       desc="v0.9.0. A hidden rating stops counting in the person's average and in the low-rating risk signal; restoring counts it again.")
op("get", "/admin/risk/signals", "adminRiskSignals", "Risk signals the server counts (cancels, failed payments, low rating)", ["admin"], "Admin · Safety",
   params=AL + [q("who", {"type": "string", "enum": ["driver", "rider"]}), *ZF], ok=(200, "RiskPage"), permission="safety.edit",
   desc="v0.9.0 (contract.json#risk). People with at least one counted event in the window." + ZF_DESC)
op("get", "/admin/kpis", "adminKpis", "Key numbers per zone and day", ["admin"], "Admin · Reports",
   params=[*ZF, q("fromDate", {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"}), q("toDate", {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"})],
   ok=(200, "KpiReport"), permission="overview.read",
   desc="v0.9.0 (contract.json#kpis). Days are zone-local, both ends included, at most kpis.maxDays. Today: source live; earlier: the nightly summary." + ZF_DESC)
# ---- v0.7.0 (CONTRACT.md §15): SOS and incidents
for who, path, opid in [("rider", "/rider/trips/{tripId}/sos", "riderSos"), ("driver", "/driver/trips/{tripId}/sos", "driverSos")]:
    op("post", path, opid, f"The {who} presses SOS: alert Movera", [who], "Safety", params=TID, body="SosRequest", ok=(200, "SosReceipt"), mutation=True,
       desc=f"v0.7.0. Only the trip's own {who}, while the trip is live (contract.json#safety.sos.{who}Statuses); otherwise 409 invalid_transition with the trip. "
            "Creates the trip's one open SOS incident, or returns it when one is open (a second SOS from either side). The app opens the emergency call (112) itself; "
            "it retries with the same Idempotency-Key and then shows only \"SOS sent\".")
# ---- v0.12.0 (CONTRACT.md §22): ride check answers
for who, path, opid in [("rider", "/rider/trips/{tripId}/ride-check", "riderRideCheck"), ("driver", "/driver/trips/{tripId}/ride-check", "driverRideCheck")]:
    op("post", path, opid, f"The {who} app reports a ride check (shown, or answered)", [who], "Safety", params=TID, body="RideCheckReport", ok=(200, "RideCheckReceipt"), mutation=True,
       desc=f"v0.12.0. Only the trip's own {who}, while the trip is live or up to contract.json#safety.rideCheck.completedWithinMinutes after it completed "
            f"(contract.json#safety.rideCheck.{who}Statuses); otherwise 409 invalid_transition with the trip. Without answer: the card showed; the server opens a ride_check "
            "incident without the alarm when no answer comes within noAnswerSeconds (120 s). answer ok: saved on the trip only. answer need_help: opens or joins the trip's "
            "ride_check incident with the alarm. Idempotent by checkId and by Idempotency-Key (contract.json#safety.rideCheck.idempotency).")
op("get", "/admin/incidents/stream", "adminStreamIncidents", "Admin incident feed (opened, updated, escalated, closed)", ["admin"], "Admin · Safety",
   params=[pref("After"), pref("LastEventId")], content=sse("Server-sent events.", "AdminIncidentEvent", "AdminIncidentEventPage"), permission="overview.read",
   desc="v0.7.0. Any signed-in admin may listen. Events of an incident go to admins with incidents.read whose zones cover its zone; once it is escalated "
        "(not taken in contract.json#safety.escalateAfterSeconds) to every signed-in admin. Without Accept: text/event-stream: a JSON page of the same events (polling fallback).")
op("get", "/admin/incidents/{incidentId}", "adminGetIncident", "Incident detail with the car's latest position", ["admin"], "Admin · Safety",
   params=[pref("IncidentId")], ok=(200, "Incident"), permission="incidents.read", desc="v0.7.0. In the admin's zones only (else 403 zone_out_of_scope).")
for seg, opid, summ in [("take", "adminTakeIncident", "Take the incident (New → Taken)"),
                        ("resolve", "adminResolveIncident", "Solve the incident (→ Solved)"),
                        ("dismiss", "adminDismissIncident", "Call it a false alarm (→ False alarm)")]:
    op("post", f"/admin/incidents/{{incidentId}}/{seg}", opid, summ, ["admin"], "Admin · Safety", params=[pref("IncidentId")], body="AdminIncidentCommand",
       ok=(200, "Incident"), mutation=True, permission="safety.edit",
       desc="v0.7.0 (contract.json#safety.transitions). In the admin's zones only. A status the command cannot leave → 409 invalid_transition with the incident; "
            "a stale expectedVersion → 409 version_mismatch with the incident. Written in the audit.")
op("post", "/admin/drivers/{driverId}/status", "adminSetDriverStatus", "Set driver account status", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="DriverStatusCommand", ok=(200, "Driver"), mutation=True, permission="drivers.activate", permission_v050="drivers.edit",
   desc=C["driverOnboarding"]["activation"]["note"])
op("post", "/admin/riders/{riderId}/status", "adminSetRiderStatus", "Set rider status", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="RiderStatusCommand", ok=(200, "Rider"), mutation=True, permission="riders.block", permission_v050="riders.edit")
op("post", "/admin/vehicles/{vehicleId}/review", "adminReviewVehicle", "Approve / reject / block a vehicle", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="VehicleReviewCommand", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", permission_v050="fleet.edit")
op("post", "/admin/documents/{documentId}/review", "adminReviewDocument", "Approve / reject a document", ["admin"], "Admin · People",
   params=[pref("DocumentId")], body="DocumentReviewCommand", ok=(200, "Document"), mutation=True, permission="documents.approve", permission_v050="drivers.edit",
   desc="v0.18.0: " + C["driverOnboarding"]["documentExpiry"]["note"])
# ---- v0.5.3 (CONTRACT.md §14): fleets and document files
op("get", "/admin/drivers/{driverId}", "adminGetDriver", "Driver detail (details, fleet, documents)", ["admin"], "Admin · People",
   params=[pref("DriverId")], ok=(200, "Driver"), permission="drivers.read", desc="v0.5.3.")
op("get", "/admin/fleets/{fleetId}", "adminGetFleet", "Fleet detail: company, code, drivers and cars", ["admin"], "Admin · People",
   params=[pref("FleetId")], ok=(200, "FleetView"), permission="drivers.read", desc="v0.5.3.")
op("post", "/admin/fleets/{fleetId}/review", "adminReviewFleet", "Approve / reject / block a fleet", ["admin"], "Admin · People",
   params=[pref("FleetId")], body="FleetReviewCommand", ok=(200, "Fleet"), mutation=True, permission="drivers.activate",
   desc="v0.5.3. The first approval makes the join code (contract.json#driverOnboarding.fleetCode). Approving the fleet does not activate its owner as a driver: POST /admin/drivers/{driverId}/status does, when his own documents are approved.")
op("post", "/admin/fleets/{fleetId}/code", "adminRenewFleetCode", "Make a new join code (the old one stops working)", ["admin"], "Admin · People",
   params=[pref("FleetId")], body="FleetCodeCommand", ok=(200, "Fleet"), mutation=True, permission="drivers.activate", desc="v0.5.3. Approved fleets only (409 invalid_transition).")
for seg, opid, summ in [("accept", "adminAcceptFleetInvitation", "Accept a pending invitation or request for the fleet"), ("cancel", "adminCancelFleetInvitation", "Cancel a pending invitation or request")]:
    op("post", f"/admin/fleets/{{fleetId}}/invitations/{{invitationId}}/{seg}", opid, summ, ["admin"], "Admin · People",
       params=[pref("FleetId"), pref("InvitationId")], ok=(200, "FleetInvitation"), mutation=True, permission="drivers.activate",
       desc="v0.5.3. The same effect as the driver's or owner's answer; written in the audit.")
op("post", "/admin/fleets/{fleetId}/drivers/{driverId}/remove", "adminRemoveFleetDriver", "Remove a driver from a fleet", ["admin"], "Admin · People",
   params=[pref("FleetId"), pref("DriverId")], ok=(204, None), mutation=True, permission="drivers.activate",
   desc="v0.5.3. Same effect as the owner's POST /driver/fleet/drivers/{driverId}/remove; written in the audit.")
op("get", "/admin/documents/{documentId}/file", "adminGetDocumentFile", "The uploaded file", ["admin"], "Admin · People",
   params=[pref("DocumentId")], content=FILE_CONTENT, ok=(200, None), ok_desc="The file, with its media type.", permission="documents.approve",
   desc="v0.5.3. Read in the admin's zones only; every read is written in the audit.")
op("get", "/admin/config/{doc}", "adminGetConfigDraft", "Get the config draft for a zone", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc"), pref("ConfigZoneId"), pref("ConfigCountry")], ok=(200, "ConfigDraft"), permission="settings.read", permission_v050="config.read",
   desc="pricing and dispatch (v0.5.1) are server-only documents: only admins with settings.read read them; GET /rider/config and /driver/config never include them.")
op("put", "/admin/config/{doc}", "adminPutConfigDraft", "Replace the config draft", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigDraftUpdate", ok=(200, "ConfigDraft"), mutation=True, permission="settings.edit", permission_v050="config.edit",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.edit", "driver_app_config": "settings.edit", "pricing": "settings.edit", "dispatch": "dispatch.edit", "country_rules": "settings.edit", "onboarding": "settings.edit"}},
   desc="The draft's document must be the doc's schema (pricing → PricingDocument, dispatch → DispatchDocument, v0.5.1). x-permission-by-doc: the admin panel saves dispatch rules with dispatch.edit.")
op("post", "/admin/config/{doc}/publish", "adminPublishConfig", "Publish the draft at once (no second admin, v0.8.0)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigPublishCommand", ok=(200, "ConfigPublication"), mutation=True,
   permission="settings.publish", permission_v050="config.edit",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.publish", "driver_app_config": "settings.publish", "pricing": "settings.publish", "dispatch": "dispatch.edit", "country_rules": "settings.publish", "onboarding": "settings.publish"}},
   desc=C["configDocs"]["publishApproval"] + " The server stamps version and publishedAt (contract.json#configVersion). "
        "Emits config_published on the app streams for rider_app_config and driver_app_config only; pricing and dispatch (server-only) are published with the same version rule but never reach the apps.")
S["UseStandardCommand"] = obj(dict(EV, zoneId=ref("Id")), ["expectedVersion", "zoneId"], C["configDocs"]["useStandard"])
op("post", "/admin/config/{doc}/use-standard", "adminUseStandardConfig", "Go back to the country standard (v0.8.0)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="UseStandardCommand", ok=(200, "ConfigPublication"), mutation=True, permission="settings.publish",
   ext={"x-permission-by-doc": {"rider_app_config": "settings.publish", "driver_app_config": "settings.publish", "pricing": "settings.publish", "dispatch": "dispatch.edit"}},
   desc=C["configDocs"]["useStandard"] + " The answer names the zone and the standard's new version.")
op("get", "/admin/zones/{zoneId}/surge", "adminGetSurge", "The zone's current surge schedule", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], ok=(200, "SurgeSchedule"), permission="settings.read", permission_v050="pricing.read", desc="204 when the zone has none (flat ×1.0).")
PATHS["/admin/zones/{zoneId}/surge"]["get"]["responses"]["204"] = {"description": "No surge schedule", "headers": HDR_REQ}
op("put", "/admin/zones/{zoneId}/surge", "adminPutSurge", "Create or replace the zone's surge schedule (curve)", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], body="SurgeScheduleCommand", ok=(200, "SurgeSchedule"), mutation=True, approval=True, permission="settings.publish", permission_v050="pricing.edit",
   desc="contract.json#surge, CONTRACT.md §3.4. Points above the zone's cap → 400 invalid_request. v0.7.2: runs at once for every admin with settings.publish (one admin is enough). New quotes price from it at once; quotes already given keep their multiplier.")
op("post", "/admin/zones/{zoneId}/surge/end", "adminEndSurge", "End the schedule now (back to ×1.0)", ["admin"], "Admin · Config",
   params=[pref("ZoneId")], body="ConfigPublishCommand", ok=(200, "SurgeSchedule"), mutation=True, permission="settings.publish", permission_v050="pricing.edit")
op("get", "/admin/audit", "adminListAudit", "Server-written audit log", ["admin"], "Admin · Governance",
   params=AL + [q("actorId", ref("Id")), q("targetType", {"type": "string"}), q("targetId", ref("Id")), q("action", {"type": "string"}),
                q("result", {"type": "string", "enum": ["committed", "rejected", "denied", "conflict", "pending_approval"]}), pref("From"), pref("To")],
   ok=(200, "AuditEntryPage"), permission="audit.read")
op("get", "/admin/approvals", "adminListApprovals", "Approval queue", ["admin"], "Admin · Governance",
   params=AL + [q("status", {"type": "string", "enum": ["pending_approval", "approved", "rejected", "expired"]}, multi=True),
                q("targetType", {"type": "string"})], ok=(200, "ApprovalPage"), permission="approval.decide", permission_v050="approval.read")
for d in ["approve", "reject"]:
    op("post", f"/admin/approvals/{{approvalId}}/{d}", f"adminApproval{d.capitalize()}", f"{d.capitalize()} a pending action (not the requester)",
       ["admin"], "Admin · Governance", params=[pref("ApprovalId")], body="ApprovalDecision", ok=(200, "Approval"), mutation=True,
       permission="approval.decide")

# ---- v0.5.1
# Admin sign-in (CONTRACT.md §9, owner decisions 9 and 14). No bearer token on sign-in, setup and refresh.
AU_A = C["auth"]["admin"]
for o in [
    op("post", "/admin/auth/sign-in", "adminSignIn", "Admin sign-in with e-mail and password", ["admin"], "Admin · Auth",
       body="AdminSignInRequest", ok=(200, "AdminSession"),
       desc="Unknown e-mail, wrong password or deactivated account → 401 unauthenticated with reason invalid_credentials (one generic answer). "
            "Failed attempts are slowed, then locked: 429 rate_limited with Retry-After. No second factor in v0.5.1; a SECOND_FACTOR_REQUIRED answer is reserved for later (contract.json#auth.admin.secondFactor)."),
    op("post", "/admin/auth/setup-password", "adminSetupPassword", "Choose the password from a one-time setup link", ["admin"], "Admin · Auth",
       body="SetupPasswordRequest", ok=(200, "AdminSession"),
       desc=f"Password shorter than {AU_A['passwordMinLength']} → 400 invalid_request (weak_password); unknown token → 400 invalid_request (invalid_setup_token); "
            f"a link older than {AU_A['setupLinkHours']} h → 410 otp_expired (setup_link_expired); used already → 410 otp_expired (setup_link_used). Signs the admin in."),
    op("post", "/admin/auth/setup-password/check", "adminCheckSetupLink", "Who a setup link is for, before the password form", ["admin"], "Admin · Auth",
       body="SetupTokenRequest", ok=(200, "SetupLinkInfo"), read_only=True, desc="Read-only: the link stays unused. Same 400 / 410 answers as setup-password."),
    op("post", "/admin/auth/refresh", "adminRefresh", "Rotate the admin refresh token", ["admin"], "Admin · Auth",
       body="RefreshRequest", ok=(200, "AdminSession"), desc=f"Rotated on every call; lives at most {AU_A['refreshExpiresHours']} h. A used, revoked or unknown token → 401 unauthenticated. Separate from /auth/refresh (rider and driver)."),
]:
    o["security"] = []
for p in ["/admin/auth/setup-password", "/admin/auth/setup-password/check"]:
    PATHS[p]["post"]["responses"]["410"] = err("otp_expired: the setup link expired (setup_link_expired) or was used (setup_link_used); ask for a new link.")
op("post", "/admin/auth/sign-out", "adminSignOut", "End this admin session", ["admin"], "Admin · Auth", ok=(204, None), desc="Revokes the refresh token; idempotent.")
op("get", "/admin/auth/me", "adminMe", "The signed-in admin: role, expanded permissions, scope", ["admin"], "Admin · Auth", ok=(200, "AdminMe"))
# v0.17.1 (owner 2026-10-29, "Fix fully (Recommended)"): the admin saves their own panel language (contract.json#auth.admin.meLanguage).
S["AdminMeUpdate"] = obj(OrderedDict([("language", nullable("Language"))]), ["language"], "v0.17.1: the signed-in admin's own panel language; null clears it.")
op("patch", "/admin/auth/me", "adminUpdateMe", "Save the signed-in admin's own panel language", ["admin"], "Admin · Auth",
   body="AdminMeUpdate", ok=(200, "AdminMe"), mutation=True,
   desc="v0.17.1: " + AA["meLanguage"]["note"].split(": ", 1)[1])
op("post", "/admin/agents/{adminId}/setup-link", "adminIssueSetupLink", "Issue a one-time password setup link for an admin", ["admin"], "Admin · Auth",
   params=[pref("AdminId")], ok=(201, "SetupLink"), mutation=True, permission="team.edit",
   desc=f"Single use, {AU_A['setupLinkHours']} h; a new link revokes the admin's earlier unused one. The first Super admin's link comes from the server seed / CLI.")
# Locations and routes (CONTRACT.md §10, owner decision 4). Read-only POSTs: no Idempotency-Key.
op("post", "/locations/autocomplete", "autocompleteAddress", "Address suggestions while typing", ["rider", "driver"], "Maps",
   body="AutocompleteRequest", ok=(200, "AddressSuggestionList"), read_only=True,
   desc="Body uses latitude / longitude (wire exception). Google Places through the server; the server keeps its own session tokens and cache. An empty list = nothing found.")
op("post", "/locations/geocode", "geocodeAddress", "Coordinates for an address or a suggestion", ["rider", "driver"], "Maps",
   body="GeocodeRequest", ok=(200, "GeocodeResult"), read_only=True, desc="No match → 200 without coordinates (never 404).")
op("post", "/locations/reverse-geocode", "reverseGeocode", "Address of a point", ["rider", "driver"], "Maps",
   body="ReverseGeocodeRequest", ok=(200, "ReverseGeocodeResult"), read_only=True, desc="Bad coordinates → 400 invalid_request (invalid_coordinates).")
op("post", "/routes", "routeBetween", "Road route between two points (Movera OSRM)", ["rider", "driver"], "Maps",
   body="RouteRequest", ok=(200, "RoadRoute"), read_only=True, desc="No route → 404 not_found (reason no_route); the app then draws a straight line. lat / lng as everywhere else.")
op("get", "/routes/driving/{coordinates}", "osrmDrivingRoute", "Turn-by-turn route for driver navigation (OSRM v5 pass-through)", ["driver"], "Maps",
   params=[{"name": "coordinates", "in": "path", "required": True, "description": C["maps"]["osrm"]["coordinates"],
            "schema": {"type": "string", "pattern": r"^-?\d+(\.\d+)?,-?\d+(\.\d+)?(;-?\d+(\.\d+)?,-?\d+(\.\d+)?){1,9}$"}},
           q("overview", {"type": "string", "enum": ["full", "simplified", "false"], "default": "full"}),
           q("geometries", {"type": "string", "enum": C["maps"]["osrm"]["geometries"], "default": "geojson"}),
           q("steps", {"type": "boolean", "default": True}), q("annotations", {"type": "boolean", "default": False}),
           q("alternatives", {"type": "boolean", "default": False})],
   ok=(200, "OsrmRouteResponse"),
   desc=f"Same path syntax and query as OSRM /route/v1/driving. No route → 200 {{code: \"NoRoute\", routes: []}}. About {C['maps']['osrm']['rateLimitPerMinute']} per minute per driver (429). Auth and rate errors use Error.")
# Telemetry (CONTRACT.md §11): no auth required, no Idempotency-Key, standard headers optional.
for path, opid, summ, body in [("/telemetry/logs", "postTelemetryLog", "App log line", "TelemetryLog"),
                               ("/telemetry/analytics", "postTelemetryAnalytics", "App analytics event", "TelemetryEvent"),
                               ("/telemetry/crashes", "postTelemetryCrash", "App crash report", "TelemetryCrash")]:
    o = op("post", path, opid, summ, ["rider", "driver", "admin"], "Telemetry", body=body, ok=(202, None), read_only=True, ok_desc="Accepted (empty body)",
           desc=f"Fire-and-forget. Body at most {C['telemetry']['maxBodyBytes']} bytes (else 400 invalid_request, payload_too_large); rate limited per address and device; "
                f"scrubbed again by the server and kept {C['telemetry']['keepDays']} days. A bearer token is used when sent.")
    o["security"] = [{}, {"bearerAuth": []}]
# Rider: keep waiting, account deletion
op("post", "/trips/{tripId}/raise-price", "raisePrice", "Raise the offer while searching", ["rider"], "Rider · Booking",
   params=TID, body="RaisePriceCommand", ok=(200, TP), mutation=True, transition="raise_price",
   desc="Owner decision 25 (CONTRACT.md §3.6). While the trip is searching or offered: the fare grows by increase (a rider_raise fare line), the whole raise goes to the driver's "
        "earnings, open offers are withdrawn and a new search starts in which drivers who already declined are asked again at the new price; version + 1. "
        "Otherwise 409 invalid_transition with the projection. A raise in another currency or a fare above dispatch.raisePrice.maxFactor × the quoted fare is 400 invalid_request.")
op("post", "/trips/{tripId}/keep-waiting", "answerKeepWaiting", "Answer the Keep waiting? step while searching", ["rider"], "Rider · Booking",
   params=TID, body="KeepWaitingCommand", ok=(200, TP), mutation=True,
   desc="Owner decision 24 (CONTRACT.md §3.6). Only while the trip is searching or offered and its searchStep is an unanswered keep_waiting: wait → the search end moves by extraMin; "
        "stop → the normal free rider cancel (cancel → cancelled_by_rider, reason wait_too_long, no fee). Otherwise 409 invalid_transition with the projection.")
op("post", "/account/deletion", "requestAccountDeletion", "Ask to delete the rider account", ["rider"], "Rider · Account",
   ok=(202, "AccountDeletion"), mutation=True, ok_desc="Accepted; the server erases the account on its own schedule.")
op("get", "/trips/{tripId}/path", "getTripPath", "The route of an ended trip (driven or planned)", ["rider", "driver"], "Trips",
   params=TID, ok=(200, "TripPath"),
   desc="v0.17.0 (CONTRACT.md §25): " + TPATH["actors"] + ". " + TPATH["driven"] + " " + TPATH["planned"])["responses"]["409"] = rref("Conflict")
op("get", "/driver/trips/{tripId}/complete-preview", "previewCompleteTrip", "The final price before completing (read-only)", ["driver"], "Driver · Trip",
   params=TID, ok=(200, "CompletePreview"),
   desc="v0.18.1 (CONTRACT.md §26): " + CPV["actors"] + " " + CPV["same"] + " " + CPV["frozen"] + " " + CPV["cashCollected"])["responses"]["409"] = rref("Conflict")
# Admin: dispatch control, live drivers, trip trace
op("get", "/admin/zones/{zoneId}/dispatch-control", "adminGetDispatchControl", "The zone's live dispatch switch", ["admin"], "Admin · Dispatch",
   params=[pref("ZoneId")], ok=(200, "DispatchControl"), permission="trips.read")
op("put", "/admin/zones/{zoneId}/dispatch-control", "adminPutDispatchControl", "Pause dispatch or force a mode in a zone", ["admin"], "Admin · Dispatch",
   params=[pref("ZoneId")], body="DispatchControlCommand", ok=(200, "DispatchControl"), mutation=True, approval=True, permission="dispatch.edit",
   desc="CONTRACT.md §3.6. v0.7.2 (one admin is enough): pause, force a mode, resume and back to rules run at once (200) for every admin with dispatch.edit. "
        "Forcing a mode that is off → 400 invalid_request (mode_off). Running searches stop new offers while paused; a forced mode applies to new searches.")
op("get", "/admin/live/drivers", "adminLiveDrivers", "Driver positions for the admin live map", ["admin"], "Admin · Dispatch",
   params=ZF, ok=(200, "LiveDriverList"), permission="trips.read",
   desc="Limited to the zones in the admin's scope. stale = no fix for staleAfterSeconds." + ZF_DESC)
op("get", "/admin/trips/{tripId}/trace", "adminTripTrace", "The trip's GPS trace", ["admin"], "Admin · Trips",
   params=TID, ok=(200, "TripTrace"), permission="trips.read", desc="Traces are deleted 30 days after the trip (owner decision 11): 404 after that.")

# ---- Deprecated aliases
o = op("get", "/rides/{rideId}", "getRideDeprecated", "Deprecated alias of GET /trips/{tripId}", ["rider"], "Deprecated",
       params=[pref("RideId")], ok=(200, TP), deprecated=True, desc="Removed after v0.3. Response is the TripProjection (tripId + rideId).")
o = op("post", "/rides/{rideId}/cancel", "cancelRideDeprecated", "Deprecated alias of POST /trips/{tripId}/cancel", ["rider"], "Deprecated",
       params=[pref("RideId")], body="CancelCommand", ok=(200, TP), mutation=True, transition="cancel", deprecated=True)

# ---- v0.18.0 (owner 2026-10-29, driver group 2 "Onboarding"): onboarding settings, expiry, reminders, car rules, own company.
DOS = C["driverOnboarding"]["settings"]; LIM = DOS["limits"]
def rng(name, desc=None): return i(desc, minimum=LIM[name][0], maximum=LIM[name][1])
DOC_OR_DRAFT = {"anyOf": [ref("DocumentType"), s("A new custom type of this draft, named by its draftKey; the server puts the id in its place.", pattern="^draft:.{1,40}$")]}
S["OnboardingDocumentLists"] = obj({"driver": arr(DOC_OR_DRAFT), "fleet": arr(DOC_OR_DRAFT), "vehicle": arr(DOC_OR_DRAFT)},
                                   ["driver", "fleet", "vehicle"], "v0.18.0 (owner item 10): the documents a person (driver), a company (fleet) and a car (vehicle) need in the country.")
S["OnboardingStep"] = obj({"id": s(enum=DOS["stepIds"]), "on": b(), "days": rng("stepDays", "Days the step may take before it is late.")}, ["id", "on", "days"])
S["VehicleCategoryRule"] = obj({"category": ref("CategoryId"), "on": b(), "minYear": rng("minYear"), "minSeats": rng("minSeats"),
                                "fuels": arr(s(enum=DOS["fuels"]), uniqueItems=True)}, ["category", "on", "minYear", "minSeats", "fuels"])
CT_ = DOS["customTypes"]
S["LocalText"] = obj({"sv": s(minLength=1), "fr": s(minLength=1), "en": s(minLength=1)}, ["sv", "fr", "en"])
S["CustomDocumentType"] = obj({"id": s("Made by the server; leave out for a new type.", pattern=CT_["idPattern"]),
                               "draftKey": s("A new type only: lists may name it draft:<draftKey> until the server gives the id.", minLength=1, maxLength=40),
                               "owner": s(enum=CT_["owners"]), "kind": s(enum=CT_["kinds"]), "expires": b(),
                               "name": ref("LocalText"), "help": ref("LocalText")}, ["owner", "kind", "expires", "name", "help"], CT_["note"])
S["DocumentTypeTexts"] = obj({"name": ref("LocalText"), "help": ref("LocalText")}, [], DOS["texts"])
S["DocumentTypeInfo"] = obj({"owner": s(enum=CT_["owners"]), "kind": s(enum=["file", "acceptance", "admin_check"]), "expires": b(), "custom": b(),
                             "name": ref("LocalText"), "help": ref("LocalText")}, ["owner", "kind", "expires", "name"])
S["AdminCheckCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "note": s(maxLength=1000)}, ["decision"], DOS["adminCheck"])
op("post", "/admin/drivers/{driverId}/documents/{type}/check", "adminCheckDocument", "Mark an admin_check document (info session) held", ["admin"], "Admin · People",
   params=[pref("DriverId"), {"name": "type", "in": "path", "required": True, "schema": ref("DocumentType")}], body="AdminCheckCommand", ok=(200, "Document"),
   mutation=True, permission="documents.approve", desc="v0.18.0: " + DOS["adminCheck"])
S["OnboardingSettings"] = obj(OrderedDict([
    ("version", i("Stamped by the server; 0 = the contract defaults (nothing published).", minimum=0)), ("publishedAt", ref("Timestamp")),
    ("country", ref("CountryCode")),
    ("documents", ref("OnboardingDocumentLists")),
    ("expiringTypes", arr(DOC_OR_DRAFT, uniqueItems=True, description="Types that need an expiry date when approved (contract.json#driverOnboarding.documentExpiry).")),
    ("steps", arr(ref("OnboardingStep"), minItems=1)),
    ("signUpReminders", obj({"on": b(), "everyDays": rng("remindEveryDays"), "stuckAfterDays": rng("stuckAfterDays")}, ["on", "everyDays", "stuckAfterDays"],
                            C["driverOnboarding"]["signUpReminders"]["note"])),
    ("expiry", obj({"warnDays": arr(rng("warnDays"), minItems=1, maxItems=3), "blockAtExpiry": b(C["driverOnboarding"]["documentExpiry"]["block"])},
                   ["warnDays", "blockAtExpiry"], C["driverOnboarding"]["documentExpiry"]["warn"])),
    ("customTypes", arr(ref("CustomDocumentType"), description=DOS["customTypes"]["note"])),
    ("texts", {"type": "object", "description": DOS["texts"], "additionalProperties": ref("DocumentTypeTexts")}),
    ("documentTypes", {"type": "object", "readOnly": True, "description": "Only in GET /driver/onboarding/settings. " + DOS["driverRead"], "additionalProperties": ref("DocumentTypeInfo")}),
    ("vehicles", obj({"categories": arr(ref("VehicleCategoryRule")), "warnDays": rng("vehicleWarnDays"), "autoHold": b("An expired car document takes the car off the road."),
                      "photosNeeded": b("The four photo types are required car documents.")}, ["categories", "warnDays", "autoHold", "photosNeeded"],
                     C["driverOnboarding"]["vehicleRules"]["note"])),
]), ["version", "country", "documents", "expiringTypes", "steps", "signUpReminders", "expiry", "vehicles"],
    "v0.18.0, per country only: " + DOS["note"] + " Rules: " + " ".join(DOS["rules"]), **{"x-server-only": True, "x-defaults": DOS["defaults"]})
# ---- v0.18.3 (R8 upload guides, R9 valid months, R5 names per country)
GL = DOS["guideLimits"]
GUIDE_LINE = obj({"sv": s(minLength=1, maxLength=GL["lineChars"]), "fr": s(minLength=1, maxLength=GL["lineChars"]), "en": s(minLength=1, maxLength=GL["lineChars"])}, ["sv", "fr", "en"])
S["DocumentGuide"] = obj({"checklist": arr(GUIDE_LINE, maxItems=GL["lines"]), "tips": arr(GUIDE_LINE, maxItems=GL["lines"])}, [], DOS["guides"])
S["OnboardingSettings"]["properties"]["guides"] = {"type": "object", "description": DOS["guides"], "additionalProperties": ref("DocumentGuide")}
S["OnboardingSettings"]["properties"]["validMonths"] = {"type": "object", "description": DOS["validMonths"], "additionalProperties": rng("validMonths")}
S["DocumentTypeInfo"]["properties"]["guide"] = ref("DocumentGuide")
S["DocumentTypeInfo"]["properties"]["validMonths"] = rng("validMonths", "v0.18.3 (R9): months from the issue date (settings.validMonths).")
S["DocumentTypeInfo"]["description"] = "v0.18.3: name is the country's (" + C["driverOnboarding"]["documents"]["namesByCountry"] + ")"
op("get", "/driver/onboarding/settings", "getDriverOnboardingSettings", "The onboarding settings of the driver's country", ["driver"], "Driver · Account",
   params=[q("country", ref("CountryCode"), "Only for an account with no country yet.")], ok=(200, "OnboardingSettings"), desc="v0.18.0: " + DOS["driverRead"])
RM = C["driverOnboarding"]["reminders"]
S["ReminderFix"] = obj({"target": s(enum=RM["fixTargets"]), "documentType": ref("DocumentType"), "scope": s(enum=["driver", "fleet", "vehicle"]),
                        "vehicleId": ref("Id"), "contentSlot": s(enum=[C["driverOnboarding"]["infoSession"]["contentSlot"]])}, ["target"],
                       "Where a tap on the line goes: document = the upload guide of documentType (vehicleId for a car); info_session = the content slot; fleet_vehicles = My fleet › cars; pick_vehicle = the car list.")
S["DriverReminder"] = obj({"kind": s(enum=list(RM["kinds"].keys())), "level": s(enum=list(RM["levels"].keys())),
                           "scope": s(enum=["driver", "fleet", "vehicle"]), "documentType": ref("DocumentType"), "documentId": ref("Id"), "vehicleId": ref("Id"),
                           "status": s("The shown document state (contract.json#documentStatus), e.g. waiting_for_movera.", enum=C["documentStatus"]["values"]),
                           "expiresAt": ref("Timestamp"), "daysLeft": i(C["driverOnboarding"]["documentExpiry"]["daysLeft"], minimum=0), "reviewNote": s(),
                           "fix": ref("ReminderFix")}, ["kind", "level"], "v0.18.0: " + " ".join(f"{k}: {v}." for k, v in RM["kinds"].items()))
S["DriverReminder"]["properties"]["actions"] = arr(ref("ReminderFix"), description="v0.18.3: " + RM["actions"])
S["DriverReminderList"] = obj({"items": arr(ref("DriverReminder")), "blocksOnline": i("Lines with level blocks_online.", minimum=0)}, ["items", "blocksOnline"], RM["note"])
op("get", "/driver/reminders", "getDriverReminders", "Important reminders for the Home sheet", ["driver"], "Driver · Account", ok=(200, "DriverReminderList"),
   desc="v0.18.0: " + RM["note"])
SC = C["driverOnboarding"]["startCompany"]
S["StartCompanyRequest"] = obj(dict(EV, company=ref("FleetCompany")), ["expectedVersion", "company"], "v0.18.0: " + SC["note"])
op("post", "/driver/fleet/start-company", "startOwnCompany", "Start my own company: the account becomes a fleet (waits for Movera)", ["driver"], "Driver · Fleet",
   body="StartCompanyRequest", ok=(200, "Driver"), mutation=True, desc="v0.18.0: " + SC["note"])
VR = C["driverOnboarding"]["vehicleRules"]
FUEL = s("v0.18.0: the car's fuel (contract.json#driverOnboarding.settings.fuels).", enum=DOS["fuels"])
S["VehicleRequest"]["properties"]["fuel"] = FUEL
S["VehicleRequest"]["description"] = "v0.18.0: " + VR["note"]
S["Vehicle"]["properties"]["fuel"] = dict(FUEL)
S["Driver"]["properties"]["signUp"] = obj({"since": ref("Timestamp"), "stuck": b("Signed up at least signUpReminders.stuckAfterDays ago and not active."),
                                           "remindersSent": i(minimum=0), "lastReminderAt": ref("Timestamp")}, ["since", "stuck", "remindersSent"],
                                          "v0.18.0, admin view only, while the account is pending or on_hold: " + C["driverOnboarding"]["signUpReminders"]["note"])
S["DocumentReviewCommand"]["description"] += " v0.18.0: " + C["driverOnboarding"]["documentExpiry"]["note"]
S["DocumentReviewCommand"]["properties"]["issuedAt"] = ref("Timestamp")
S["Vehicle"]["properties"]["ruleProblems"] = arr(s(), description="v0.18.3 (admin and fleet-owner views): " + C["driverOnboarding"]["vehicleRules"]["approval"] + " " + C["driverOnboarding"]["vehicleRules"]["baseYear"])
S["Notification"]["description"] = "v0.18.3 review notices: " + C["driverOnboarding"]["reviewNotices"]["note"]
# ---- v0.18.3 (R7): push to a closed phone through Firebase Cloud Messaging
PD = AU["devices"]
S["PushWebConfig"] = obj({"apiKey": s("Public Firebase web API key (not a secret)."), "appId": s(), "messagingSenderId": s(), "projectId": s(),
                          "authDomain": s()}, ["apiKey", "appId", "messagingSenderId", "projectId"], "v0.18.3: the Firebase web app's public settings.")
S["PushConfig"] = obj({"provider": s(enum=["fcm"]), "enabled": b("False when the server has no Firebase settings; the app then skips push."),
                       "projectId": s(), "webConfig": ref("PushWebConfig")}, ["provider", "enabled"], PD["config"]["note"])
o = op("get", "/push/config", "getPushConfig", "Public push settings for the app (Firebase web config)", ["rider", "driver"], "Auth",
       params=[{"name": "app", "in": "query", "required": True, "schema": s(enum=PD["config"]["apps"])}], ok=(200, "PushConfig"),
       desc=PD["config"]["note"] + " " + PD["appFlow"])
o["security"] = []
PATHS["/push/devices"]["post"]["description"] += " v0.18.3: " + PD["sending"]["note"] + " " + PD["sending"]["riderConsent"]

# ---- v0.18.0: group 2 admin actions on live (contract.json#driverOnboarding.adminActions)
AA = C["driverOnboarding"]["adminActions"]
S["AdminVehicleUpdate"] = obj(dict(EV, make=s(minLength=1), model=s(minLength=1), year=i(minimum=1950, maximum=2100), color=s(minLength=1), plate=s(minLength=1),
                                  seats=i(minimum=1, maximum=20), fuel=s(enum=DOS["fuels"]), categoryIds=arr(ref("CategoryId"))), ["expectedVersion"], AA["updateVehicle"])
op("patch", "/admin/vehicles/{vehicleId}", "adminUpdateVehicle", "Update a car (year, seats, fuel, categories …) within the car rules", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="AdminVehicleUpdate", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["updateVehicle"])
S["AdminVehicleDriverCommand"] = obj(dict(EV, driverId={"oneOf": [ref("Id"), {"type": "null"}]}), ["expectedVersion", "driverId"], AA["linkDriver"])
op("post", "/admin/vehicles/{vehicleId}/driver", "adminLinkVehicleDriver", "Link a car to a driver of its fleet (or free it)", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="AdminVehicleDriverCommand", ok=(200, "Vehicle"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["linkDriver"])
S["AdminDriverCategoriesCommand"] = obj(dict(EV, categoryIds=arr(ref("CategoryId"), minItems=1, uniqueItems=True)), ["expectedVersion", "categoryIds"], AA["driverCategories"])
op("put", "/admin/drivers/{driverId}/categories", "adminSetDriverCategories", "Set the categories a driver takes (only what his car fits)", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminDriverCategoriesCommand", ok=(200, "Driver"), mutation=True, permission="vehicles.edit", desc="v0.18.0: " + AA["note"] + " " + AA["driverCategories"])
S["AdminBankReviewCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "note": s(maxLength=1000)}, ["decision"], AA["bankReview"])
op("post", "/admin/drivers/{driverId}/bank/review", "adminReviewDriverBank", "Approve or reject a driver's bank details", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="AdminBankReviewCommand", ok=(200, "Document"), mutation=True, permission="documents.approve", desc="v0.18.0: " + AA["note"] + " " + AA["bankReview"])

# ---- v0.18.0 (owner decision 19): car documents for the fleet owner only; members see pickable.
CD = C["driverOnboarding"]["carDocuments"]
S["Vehicle"]["properties"]["pickable"] = b("v0.18.0: the asking driver can pick this car now. " + CD["note"])
S["Vehicle"]["properties"]["notPickableReason"] = s("v0.18.0: why not (pickable false); the app says \"Can't be driven\".", enum=CD["notPickableReasons"])

# ---------------------------------------------------------------- document
TAG_DESC = {"Admin · System": "Crashes & errors from the apps and the server, grouped (v0.16.0)", "Admin · Zones": "Zones from the server: list, create, outline, open and close (v0.11.0)", "Auth": "Sign-in, tokens and push devices for the rider and driver apps (v0.5.0)", "Admin · Auth": "Admin panel sign-in with e-mail and password (v0.5.1)",
            "Maps": "Address search, geocoding and road routes through the server (v0.5.1); read-only, no Idempotency-Key",
            "Telemetry": "Fire-and-forget app logs, analytics and crashes (v0.5.1); no auth required", "Trips": "Shared trip resource (rider, driver, admin)", "Realtime": "Streams: SSE (or WebSocket) + JSON replay",
            "Deprecated": "Legacy /rides aliases kept for one release"}
# ---- v0.7.1: pricing rework part 2 (owner Pricing decisions 2026-10-27)
CC = C["categoryCatalog"]
PARAMS["CategoryIdPath"] = {"name": "categoryId", "in": "path", "required": True, "schema": ref("CategoryId")}
PARAMS["StopIndex"] = {"name": "stopIndex", "in": "path", "required": True, "schema": {"type": "integer", "minimum": 0, "maximum": 9}, "description": "0-based index into TripProjection.stops."}
S["StopVisit"] = obj({"stopIndex": i(minimum=0), "arrivedAt": ref("Timestamp"), "leftAt": ref("Timestamp")}, ["stopIndex", "arrivedAt"],
                     "v0.7.1: one extra stop the driver arrived at (contract.json#stopWaits); stop_waiting runs from arrivedAt to leftAt (or to complete).")
S["StopCommand"] = obj(dict(EV), ["expectedVersion"], "v0.7.1: the driver's arrived-at-stop or leaving-stop tap.")
for verb, oid, summ in [("arrive", "driverArriveAtStop", "Driver arrived at an extra stop (stop waiting starts)"), ("leave", "driverLeaveStop", "Driver leaves an extra stop (stop waiting ends)")]:
    op("post", "/driver/trips/{tripId}/stops/{stopIndex}/" + verb, oid, summ, ["driver"], "Driver · Trip", params=TID + [pref("StopIndex")], body="StopCommand",
       ok=(200, "TripProjection"), mutation=True, desc="v0.7.1. " + C["stopWaits"][verb])
S["ConfigHistoryEntry"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                               "note": s(), "action": s(enum=["publish", "restore"]), "restoredFrom": i(minimum=1), "document": {"type": "object"}},
                              ["doc", "zoneId", "version", "publishedAt", "action", "document"], "v0.7.1: one published version (contract.json#pricingHistory).")
S["ConfigHistoryEntryPage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("ConfigHistoryEntry"))}}]}
S["ConfigRestoreCommand"] = obj(dict(EV, zoneId=ref("Id"), version=i("The version to publish again.", minimum=1), note=s(maxLength=1000)), ["expectedVersion", "zoneId", "version"])
op("get", "/admin/config/{doc}/history", "adminConfigHistory", "Published versions of a config document, newest first", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc"), q("zoneId", ref("Id")), pref("Cursor"), pref("Limit")], ok=(200, "ConfigHistoryEntryPage"), permission="settings.read", desc="v0.7.1. " + C["pricingHistory"]["list"])
op("post", "/admin/config/{doc}/restore", "adminRestoreConfig", "Publish an earlier version again (Restore, Undo last publish)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigRestoreCommand", ok=(200, "ConfigPublication"), mutation=True, permission="settings.publish",
   desc="v0.7.1. " + C["pricingHistory"]["restore"] + " " + C["pricingHistory"]["audit"])
S["CategoryDef"] = obj({"id": ref("CategoryId"), "label": s(minLength=1, maxLength=40), "line": ref("LocalizedLine"), "seats": i(minimum=1, maximum=8),
                        "builtIn": b("A seed category."), "sort": i(minimum=0), "archivedAt": ref("Timestamp"), "archivedBy": ref("Id"), "archiveReason": s(),
                        "restoreUntil": ref("Timestamp")}, ["id", "label", "line", "seats", "builtIn", "sort"], "v0.7.1: " + CC["entity"])
S["CategoryDefList"] = obj({"categories": arr(ref("CategoryDef")), "restoreDays": i(minimum=1)}, ["categories", "restoreDays"], "Active first, then the archived ones still restorable.")
S["CategoryDefInput"] = obj({"id": ref("CategoryId"), "label": s(minLength=1, maxLength=40), "line": ref("LocalizedLine"), "seats": i(minimum=1, maximum=8), "sort": i(minimum=0)},
                            ["label", "line", "seats"], "id only on create (else made from the label).")
S["CategoryArchiveCommand"] = obj({"reason": s(minLength=1, maxLength=500)}, ["reason"])
op("get", "/admin/categories", "adminListCategories", "The car type catalog (every zone)", ["admin"], "Admin · Config", ok=(200, "CategoryDefList"), permission="settings.read", desc="v0.7.1. " + CC["note"])
op("post", "/admin/categories", "adminCreateCategory", "Add a car type (off in every zone)", ["admin"], "Admin · Config", body="CategoryDefInput", ok=(201, "CategoryDef"), mutation=True, permission="settings.publish")
op("put", "/admin/categories/{categoryId}", "adminUpdateCategory", "Rename a car type, its sub-line and seats", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], body="CategoryDefInput", ok=(200, "CategoryDef"), mutation=True, permission="settings.publish")
op("post", "/admin/categories/{categoryId}/archive", "adminArchiveCategory", "Delete a car type (archived, restorable)", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], body="CategoryArchiveCommand", ok=(200, "CategoryDef"), mutation=True, permission="settings.publish", desc="v0.7.1. " + CC["archive"])
op("post", "/admin/categories/{categoryId}/restore", "adminRestoreCategory", "Restore an archived car type (old prices, off)", ["admin"], "Admin · Config", params=[pref("CategoryIdPath")], ok=(200, "CategoryDef"), mutation=True, permission="settings.publish", desc="v0.7.1. " + CC["restore"])

# ---- v0.7.2: real surge data for the admin, the driver's surge map, one admin everywhere (owner 2026-10-28)
SL = C["surgeLive"]; DSM = C["driverSurgeMap"]
S["SurgeSource"] = s(enum=["manual", "scheduled", "smart", "off"])
S["ZoneSurgeNow"] = obj({"zoneId": ref("Id"), "multiplier": n(minimum=1, maximum=6), "source": ref("SurgeSource"), "until": ref("Timestamp"), "scheduleId": ref("Id"),
                         "profileId": s(), "requests": i(minimum=0), "freeDrivers": i(minimum=0), "ratio": n(minimum=0), "checkedAt": ref("Timestamp")},
                        ["zoneId", "multiplier", "source", "requests", "freeDrivers", "ratio"], "v0.7.2: " + SL["now"])
S["SurgeNowList"] = obj({"at": ref("Timestamp"), "zones": arr(ref("ZoneSurgeNow"))}, ["at", "zones"])
S["SurgePoint"] = obj({"at": ref("Timestamp"), "requests": i(minimum=0), "freeDrivers": i(minimum=0), "ratio": n(minimum=0), "multiplier": n(minimum=1, maximum=6)},
                      ["at", "requests", "freeDrivers", "ratio", "multiplier"], "v0.7.2: " + SL["points"])
S["PriceCheck"] = obj({"windowMin": i(minimum=1), "saw": i(minimum=0), "left": i(minimum=0), "leftPct": i(minimum=0, maximum=100)}, ["windowMin", "saw", "left", "leftPct"], "v0.7.2: " + SL["priceCheck"])
S["SurgeEffect"] = obj({"drivers": i(), "ridesPct": i(), "leftPct": i(minimum=0, maximum=100)}, ["drivers", "ridesPct", "leftPct"])
S["SurgeTimelineItem"] = obj({"at": ref("Timestamp"), "kind": s(enum=["manual_start", "manual_stop", "scheduled_start", "scheduled_end", "smart_change", "smart_end"]),
                              "multiplier": n(minimum=1, maximum=6), "previous": n(minimum=1, maximum=6), "by": s(), "profileId": s(), "effect": ref("SurgeEffect")},
                             ["at", "kind", "multiplier"], "v0.7.2: " + SL["timeline"])
S["SurgeHistory"] = obj({"zoneId": ref("Id"), "from": ref("Timestamp"), "to": ref("Timestamp"), "bucketMin": i(enum=[5, 10, 15, 30, 60]),
                         "points": arr(ref("SurgePoint")), "priceCheck": ref("PriceCheck"), "timeline": arr(ref("SurgeTimelineItem"))},
                        ["zoneId", "from", "to", "bucketMin", "points", "priceCheck", "timeline"], "v0.7.2: " + SL["history"])
op("get", "/admin/surge/now", "adminSurgeNow", "The surge now in each zone, with its demand", ["admin"], "Admin · Config",
   params=[q("zoneIds", s("Comma-separated zone ids; none = every zone in the admin's scope."))], ok=(200, "SurgeNowList"), permission="settings.read", desc="v0.7.2. " + SL["note"] + " " + SL["now"])
op("get", "/admin/zones/{zoneId}/surge/history", "adminSurgeHistory", "Demand chart, rider price check and surge timeline of a zone", ["admin"], "Admin · Config",
   params=[pref("ZoneId"), q("hours", i(minimum=1, maximum=24, default=6)), q("bucketMin", i(enum=[5, 10, 15, 30, 60], default=10))], ok=(200, "SurgeHistory"), permission="settings.read",
   desc="v0.7.2. " + SL["history"] + " " + SL["samples"])
S["SurgeLevel"] = s(enum=["low", "medium", "high"], description="v0.7.2: " + DSM["levels"])
S["ZoneBounds"] = obj({"south": n(minimum=-90, maximum=90), "west": n(minimum=-180, maximum=180), "north": n(minimum=-90, maximum=90), "east": n(minimum=-180, maximum=180)}, ["south", "west", "north", "east"])
S["DriverSurgeZone"] = obj({"zoneId": ref("Id"), "level": ref("SurgeLevel"), "bounds": ref("ZoneBounds")}, ["zoneId", "level", "bounds"], "v0.7.2: never the multiplier.")
S["DriverSurgeMap"] = obj({"at": ref("Timestamp"), "zones": arr(ref("DriverSurgeZone"))}, ["at", "zones"], "v0.7.2: " + DSM["note"])
op("get", "/driver/surge-map", "driverSurgeMap", "Zones with a surge now, as colour levels for the Home map", ["driver"], "Driver · Session",
   ok=(200, "DriverSurgeMap"), desc="v0.7.2. " + DSM["route"] + " " + DSM["refresh"] + " " + DSM["tip"])

# ---- v0.10.0: content from the admin to the apps (owner Content answers 2026-10-28)
CT = C["content"]
S["ContentSlot"] = s(enum=CT["slots"])
S["ContentText"] = obj({"sv": s(minLength=1, maxLength=4000), "fr": s(minLength=1, maxLength=4000), "en": s(minLength=1, maxLength=4000)}, ["sv", "fr", "en"])
S["AppVersionPair"] = obj({"min": s(pattern="^\\d+\\.\\d+\\.\\d+$"), "recommended": s(pattern="^\\d+\\.\\d+\\.\\d+$")}, ["min", "recommended"])
S["AppVersions"] = obj({"rider": ref("AppVersionPair"), "driver": ref("AppVersionPair")}, ["rider", "driver"])
S["ContentItem"] = obj({"slot": ref("ContentSlot"), "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                        "title": s(minLength=1, maxLength=200), "text": ref("ContentText"), "image": s(format="uri", pattern="^https://"), "expiresAt": ref("Timestamp"),
                        "reaccept": b("legal only"), "versions": ref("AppVersions")}, ["slot", "zoneId", "version", "publishedAt", "title", "text"], "v0.10.0: " + CT["item"])
S["ContentList"] = obj({"items": arr(ref("ContentItem"))}, ["items"])
S["ContentPublishCommand"] = obj({"zoneIds": arr(ref("Id"), minItems=1), "title": s(minLength=1, maxLength=200), "text": ref("ContentText"), "image": s(pattern="^https://"),
                                  "expiresAt": ref("Timestamp"), "reaccept": b(), "versions": ref("AppVersions")}, ["zoneIds", "title", "text"])
S["ContentRollbackCommand"] = obj({"zoneId": ref("Id"), "version": i(minimum=1)}, ["zoneId", "version"])
S["TermsAcceptCommand"] = obj({"contentVersion": i(minimum=1)}, ["contentVersion"])
PARAMS["ContentSlotPath"] = {"name": "slot", "in": "path", "required": True, "schema": ref("ContentSlot")}
op("get", "/admin/content", "adminListContent", "The zone's published content", ["admin"], "Admin · Config", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), permission="settings.read", desc="v0.10.0. " + CT["admin"])
op("post", "/admin/content/{slot}/publish", "adminPublishContent", "Publish a content place to the chosen zones", ["admin"], "Admin · Config", params=[pref("ContentSlotPath")], body="ContentPublishCommand", ok=(200, "ContentList"), mutation=True, permission="settings.publish", desc="v0.10.0. " + CT["note"])
op("get", "/admin/content/{slot}/history", "adminContentHistory", "Published versions of a content place in a zone", ["admin"], "Admin · Config", params=[pref("ContentSlotPath"), q("zoneId", ref("Id"))], ok=(200, "ContentList"), permission="settings.read")
op("post", "/admin/content/{slot}/rollback", "adminRollbackContent", "Publish an earlier version again", ["admin"], "Admin · Config", params=[pref("ContentSlotPath")], body="ContentRollbackCommand", ok=(200, "ContentItem"), mutation=True, permission="settings.publish")
S["TermsAcceptance"] = obj({"actor": s(enum=["rider", "driver"]), "subjectId": ref("Id"), "zoneId": ref("Id"), "contentVersion": i(minimum=1), "acceptedAt": ref("Timestamp")}, ["actor", "subjectId", "zoneId", "contentVersion", "acceptedAt"])
S["TermsAcceptanceList"] = obj({"items": arr(ref("TermsAcceptance"))}, ["items"])
op("get", "/admin/content/legal/acceptances", "adminTermsAcceptances", "Who accepted the zone's legal terms, and when", ["admin"], "Admin · Config", params=[q("zoneId", ref("Id"))], ok=(200, "TermsAcceptanceList"), permission="settings.read",
   desc="v0.10.0. An accept counts for every zone whose live legal version has that number; a version no zone has live → 409 conflict (terms_version_not_current).")
op("get", "/rider/content", "riderContent", "Content for the rider app", ["rider"], "Rider · Config", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), desc="v0.10.0. " + CT["apps_read"] + " " + CT["appVersions"])
op("get", "/driver/content", "driverContent", "Content for the driver app", ["driver"], "Driver · Session", params=[q("zoneId", ref("Id"))], ok=(200, "ContentList"), desc="v0.10.0. " + CT["apps_read"] + " " + CT["appVersions"])
op("post", "/account/terms/accept", "acceptTerms", "Accept the published legal terms", ["rider", "driver"], "Account", body="TermsAcceptCommand", ok=(204, None), mutation=True, desc="v0.10.0. " + CT["legal"])

# ---- v0.11.0: zones from the server (owner 2026-10-28, decision #9)
ZN = C["zones"]
TZ = s(pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$")
S["ZoneNames"] = obj({"sv": s(minLength=1, maxLength=80), "fr": s(minLength=1, maxLength=80), "en": s(minLength=1, maxLength=80)}, ["sv", "fr", "en"], ZN["names"])
S["ZoneKind"] = s(enum=["operating", "airport"])
S["ZonePoint"] = arr(n(), minItems=2, maxItems=2, description="[lat, lng]")
S["ZonePolygon"] = arr(ref("ZonePoint"), minItems=3, maxItems=500, description=ZN["polygon"])
S["Zone"] = obj({"zoneId": ref("Id"), "names": ref("ZoneNames"), "country": ref("CountryCode"), "currency": ref("CurrencyCode"), "timeZone": TZ,
                 "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon"), "bounds": ref("ZoneBounds"), "center": obj({"lat": n(), "lng": n()}, ["lat", "lng"]),
                 "open": b(), "version": i(minimum=1), "createdAt": ref("Timestamp"), "updatedAt": ref("Timestamp"), "updatedBy": ref("Id")},
                ["zoneId", "names", "country", "currency", "timeZone", "kind", "polygon", "bounds", "center", "open", "version"], "v0.11.0: " + ZN["zone"] + " " + ZN["idScheme"])
S["ZoneList"] = obj({"zones": arr(ref("Zone"))}, ["zones"])
S["ZoneCreateCommand"] = obj({"zoneId": ref("Id"), "names": ref("ZoneNames"), "country": ref("CountryCode"), "currency": ref("CurrencyCode"), "timeZone": TZ,
                              "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon"), "open": b("default false")},
                             ["zoneId", "names", "country", "currency", "timeZone", "polygon"], "A new zone starts closed unless open is true. 409 conflict zone_exists when the id is taken.")
S["ZoneUpdateCommand"] = obj({**EV, "names": ref("ZoneNames"), "kind": ref("ZoneKind"), "polygon": ref("ZonePolygon")}, ["expectedVersion"], ZN["version"])
S["ZoneOpenCommand"] = obj({**EV, "note": s(maxLength=1000)}, ["expectedVersion"])
op("get", "/admin/zones", "adminListZones", "Every zone in the admin's scope, open and closed", ["admin"], "Admin · Zones", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), permission="zones.read", desc="v0.11.0. " + ZN["permissions"])
op("post", "/admin/zones", "adminCreateZone", "Create a zone", ["admin"], "Admin · Zones", body="ZoneCreateCommand", ok=(201, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["idScheme"] + " " + ZN["neverDeleted"])
op("put", "/admin/zones/{zoneId}", "adminUpdateZone", "Change a zone's names, kind or outline", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneUpdateCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["polygon"])
op("post", "/admin/zones/{zoneId}/open", "adminOpenZone", "Open a zone for new rides", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneOpenCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["open"])
op("post", "/admin/zones/{zoneId}/close", "adminCloseZone", "Close a zone (never deleted)", ["admin"], "Admin · Zones", params=[pref("ZoneId")], body="ZoneOpenCommand", ok=(200, "Zone"), mutation=True, permission="zones.edit", desc="v0.11.0. " + ZN["open"] + " " + ZN["neverDeleted"])
op("get", "/rider/zones", "riderZones", "The open zones, with outline and names", ["rider"], "Rider · Config", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), desc="v0.11.0. " + ZN["apps"] + " " + ZN["notHere"])
op("get", "/driver/zones", "driverZones", "The open zones, with outline and names", ["driver"], "Driver · Session", params=[q("country", ref("CountryCode"))], ok=(200, "ZoneList"), desc="v0.11.0. " + ZN["apps"])

# ---- v0.18.5: deep-fix job of driver groups 1 and 2 (G1-B2/B3/B6/D3, G2-D1..D5.8) + chat storage (G9) + safety (G14)
AU5 = C["auth"]; DO5 = C["driverOnboarding"]; LG = C["legal"]
PATHS["/auth/otp/verify"]["post"]["description"] = PATHS["/auth/otp/verify"]["post"].get("description", "") + " v0.18.5 (G1-B3): " + AU5["signInErrors"]["otp_too_many_attempts"]
PATHS["/auth/refresh"]["post"]["description"] = PATHS["/auth/refresh"]["post"].get("description", "") + " v0.18.5: " + AU5["tokens"]["refreshRetry"] + " " + AU5["signedOut"]["note"] + " Reasons: " + ", ".join(f"{k} = {v}" for k, v in AU5["signedOut"]["reasons"].items()) + "."
# G2-D1 renewal, D5.2 content check, D5.8 expiry limit, D2 owner privacy
S["Document"]["properties"]["renewalOf"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D1): this upload renews that approved document; " + DO5["documentRenewal"]["note"]}
S["DocumentSummary"]["properties"]["renewalOf"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D1): " + DO5["documentRenewal"]["views"]}
PATHS["/driver/documents"]["post"]["description"] = PATHS["/driver/documents"]["post"].get("description", "") + " v0.18.5: " + DO5["documentRenewal"]["note"] + " " + DO5["documents"]["upload"]["contentCheck"] + " " + DO5["documentExpiry"]["maxNote"]
PATHS["/driver/documents/{documentId}/file"]["get"]["description"] = PATHS["/driver/documents/{documentId}/file"]["get"].get("description", "") + " v0.18.5: " + DO5["ownerPrivacy"]["note"]
PATHS["/admin/documents/{documentId}/review"]["post"]["description"] += " v0.18.5: " + DO5["documentExpiry"]["maxNote"] + " " + DO5["reviewReason"] + " Approving a renewal: " + DO5["documentRenewal"]["note"]
S["DriverReminder"]["properties"]["invitationId"] = {"allOf": [ref("Id")], "description": "v0.18.5 (G2-D5.6): fleet_invitation lines."}
S["DriverReminder"]["properties"]["fleetName"] = s("v0.18.5 (G2-D5.6): fleet_invitation lines.")
S["DriverReminder"]["properties"]["renewalStatus"] = s(DO5["reminders"]["renewal"], enum=["in_review", "rejected"])
S["ReminderFix"]["properties"]["invitationId"] = {"allOf": [ref("Id")], "description": "v0.18.5: accept_invitation / decline_invitation."}
PATHS["/driver/fleet/invite"]["post"]["description"] += " v0.18.5: " + DO5["fleetInvitations"]["privacy"]
S["FleetInvitation"]["properties"]["driverName"] = s("v0.18.5 (G2-D5.5): never in the owner's view of an owner_invite before it is accepted. " + DO5["fleetInvitations"]["privacy"])
# G2-D5.3 categories by the admin
S["VehicleRequest"]["properties"]["categoryIds"] = arr(ref("CategoryId"), description="Deprecated v0.18.5 (G2-D5.3): ignored, never stored. " + DO5["vehicleRules"]["categoriesByAdmin"], deprecated=True)
S["VehicleReviewCommand"]["properties"]["categoryIds"] = arr(ref("CategoryId"), uniqueItems=True, description="v0.18.5 (G2-D5.3): the categories the admin gives on approval. " + DO5["vehicleRules"]["categoriesByAdmin"])
S["VehicleReviewCommand"]["properties"]["note"]["description"] = DO5["reviewReason"]
S["Vehicle"]["properties"]["fitCategories"] = arr(ref("CategoryId"), description=DO5["vehicleRules"]["fitCategories"])
PATHS["/admin/vehicles/{vehicleId}/review"]["post"]["description"] = PATHS["/admin/vehicles/{vehicleId}/review"]["post"].get("description", "") + " v0.18.5: " + DO5["vehicleRules"]["categoriesByAdmin"] + " " + DO5["reviewReason"]
PATHS["/driver/vehicles"]["post"]["description"] = PATHS["/driver/vehicles"]["post"].get("description", "") + " v0.18.5: " + DO5["vehicleRules"]["categoriesByAdmin"]
S["DocumentReviewCommand"]["properties"]["note"]["description"] = DO5["reviewReason"]
# G2-D3 the driver's approved photo
S["DriverSummary"]["properties"]["photoUrl"] = s("v0.18.5 (G2-D3): " + DO5["riderDriverPhoto"]["url"], format="uri-reference")
op("get", "/rider/trips/{tripId}/driver-photo", "riderDriverPhoto", "The driver's approved profile photo (trip's rider, while the driver comes and during the trip)", ["rider"], "Rider · Trip",
   params=TID, content={mt: {"schema": {"type": "string", "format": "binary"}} for mt in ["image/jpeg", "image/png", "image/heic"]}, desc="v0.18.5: " + DO5["riderDriverPhoto"]["endpoint"])
# G2-D4 notices
S["Notification"]["description"] += " v0.18.5 (G2-D4): " + DO5["fleetLeaveNotices"]["note"] + " data " + DO5["fleetLeaveNotices"]["data"] + ". v0.18.5 (G9): " + C["chat"]["appStorage"]["noBellNotice"]
# G9 chat after the trip
S["MessagePage"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref("Message")),
                    "closed": b("v0.18.5 (G9): true for the rider and the driver once the trip is terminal; items is then empty.")}}], "description": "Page<Message>"}
PATHS["/trips/{tripId}/messages"]["get"]["description"] += " v0.18.5 (G9): " + C["chat"]["appStorage"]["afterTrip"] + " " + C["chat"]["appStorage"]["admin"]
# G14
for _sos in ("/rider/trips/{tripId}/sos", "/driver/trips/{tripId}/sos"):
    PATHS[_sos]["post"]["description"] = PATHS[_sos]["post"].get("description", "") + " v0.18.5: " + C["safety"]["onlyDuringTrip"]["note"] + " " + C["safety"]["onlyDuringTrip"]["server"]
# G1-B2 legal texts per country
LANG3 = obj({"sv": s(minLength=1, maxLength=200), "fr": s(minLength=1, maxLength=200), "en": s(minLength=1, maxLength=200)}, ["sv", "fr", "en"])
LTEXT = obj({"sv": s(minLength=1, maxLength=20000), "fr": s(minLength=1, maxLength=20000), "en": s(minLength=1, maxLength=20000)}, ["sv", "fr", "en"])
S["LegalDocument"] = obj({"title": LANG3, "text": LTEXT}, ["title", "text"], "v0.18.5: one legal text (terms or privacy) in sv / fr / en.")
S["LegalCompany"] = obj({"companyName": s(maxLength=200), "orgNumber": s(maxLength=60), "address": s(maxLength=300), "supportEmail": s(format="email", maxLength=200),
                         "supportPhone": s(pattern=r"^\+[1-9]\d{6,14}$")}, [], "v0.18.5: " + LG["company"])
S["LegalCountry"] = s(enum=LG["countries"])
S["LegalTexts"] = obj({"country": ref("LegalCountry"), "version": i(minimum=0), "source": s(enum=["default", "admin"]), "publishedAt": ref("Timestamp"),
                       "reaccept": b(), "reacceptFrom": {"type": ["integer", "null"], "minimum": 1, "description": "The newest version published with reaccept (null: none); a person must have accepted it or a later version (contract.json#legal.accept)."},
                       "terms": ref("LegalDocument"), "privacy": ref("LegalDocument")},
                      ["country", "version", "source", "reaccept", "terms", "privacy"], "v0.18.5: " + LG["read"])
S["LegalVersion"] = obj({"country": ref("LegalCountry"), "version": i(minimum=0), "source": s(enum=["default", "admin"]), "publishedAt": ref("Timestamp"), "publishedBy": ref("Id"),
                         "reaccept": b(), "terms": ref("LegalDocument"), "privacy": ref("LegalDocument"), "company": ref("LegalCompany")},
                        ["country", "version", "source", "reaccept", "terms", "privacy", "company"], "v0.18.5: the raw texts with their placeholders.")
S["LegalAdminView"] = obj({"live": ref("LegalVersion"), "history": arr(ref("LegalVersion"))}, ["live", "history"], "v0.18.5: " + LG["admin"])
S["LegalPublishCommand"] = obj({"terms": ref("LegalDocument"), "privacy": ref("LegalDocument"), "company": ref("LegalCompany"), "reaccept": b()}, ["terms", "privacy"], "v0.18.5: " + LG["admin"])
S["LegalAcceptCommand"] = obj({"country": ref("LegalCountry"), "version": i(minimum=1)}, ["country", "version"], "v0.18.5: " + LG["accept"])
PARAMS["LegalCountryPath"] = {"name": "country", "in": "path", "required": True, "schema": ref("LegalCountry")}
o = op("get", "/legal/{country}", "getLegalTexts", "Terms of use and privacy policy of a country (no token)", ["rider", "driver"], "Account", params=[pref("LegalCountryPath")], ok=(200, "LegalTexts"),
       desc="v0.18.5: " + LG["note"] + " " + LG["read"] + " " + LG["apps"] + " " + LG["lawyerReview"])
o["security"] = []
op("get", "/admin/legal/{country}", "adminGetLegal", "The live legal texts of a country and their history", ["admin"], "Admin · Config", params=[pref("LegalCountryPath")], ok=(200, "LegalAdminView"), permission="settings.read", desc="v0.18.5: " + LG["admin"])
op("post", "/admin/legal/{country}/publish", "adminPublishLegal", "Publish new legal texts for a country", ["admin"], "Admin · Config", params=[pref("LegalCountryPath")], body="LegalPublishCommand", ok=(200, "LegalVersion"), mutation=True, permission="settings.publish", desc="v0.18.5: " + LG["admin"] + " " + LG["company"])
op("post", "/account/legal/accept", "acceptLegal", "Accept the live legal texts of a country", ["rider", "driver"], "Account", body="LegalAcceptCommand", ok=(204, None), mutation=True, desc="v0.18.5: " + LG["accept"])

doc = OrderedDict()
doc["openapi"] = "3.1.0"
doc["info"] = {
    "title": "Movera API",
    "version": C["version"],
    "description": (
        "**Proposed contract — no backend exists yet.** One future backend serves the Rider (Flutter), Driver (Flutter) and "
        "Admin (React/TS) apps. Source of truth for names, enums, transitions, realtime and errors is `contract.json` + "
        "`CONTRACT.md` v" + C["version"] + " in this folder; this file must agree with them.\n\n"
        "Wire rules: ids match `" + ID_PATTERN + "`; times are RFC 3339 UTC with `Z`; durations are integer seconds; money is "
        "`Money {amountMinor, currency}`; keys camelCase, enum values snake_case. Success responses are the bare resource; errors are `Error`.\n\n"
        "Every mutation needs `Idempotency-Key`. Trip, offer, driver, rider, vehicle and config commands send `expectedVersion`; a stale "
        "version is `409 version_mismatch` and a command not allowed from the current status is `409 invalid_transition`, both with the current "
        "`projection`.\n\n"
        "Extensions: `x-actor` = actors allowed (derived from the token); `x-transition` = contract.json transition command; "
        "`x-permission` = admin permission (AdminPermission, v0.5.1); `x-permission-v050` = the v0.5.0 value it replaced; `x-permission-by-doc` = the permission per config document; "
        "`x-read-only` = a POST that changes nothing and takes no Idempotency-Key (v0.5.1); `x-server-only` = a document the apps never get; `x-terminal` on TripStatus = terminal set.\n\n"
        "Auth: bearer JWT. Actor (rider|driver|admin), subject id, zone scope and admin role/permissions come from the token, never from the body. "
        "Token issuance: the Auth tag (v0.5.0, contract.json#auth): phone + SMS code, Apple / Google, refresh rotation; test numbers accept a fixed code outside production. "
        "Admin: the Admin · Auth tag (v0.5.1, contract.json#auth.admin): e-mail and password, a one-time setup link, refresh rotation."),
}
doc["servers"] = [{"url": "https://api.dev.movera.invalid/api/v1", "description": "Placeholder; no backend exists."}]
doc["security"] = [{"bearerAuth": []}]
doc["tags"] = [{"name": t, **({"description": TAG_DESC[t]} if t in TAG_DESC else {})} for t in TAGS]
doc["x-contract"] = {"name": C["contract"], "version": C["version"], "source": "contract.json"}
doc["paths"] = PATHS
doc["components"] = OrderedDict([
    ("securitySchemes", {"bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT",
                                        "description": "Claims: sub, actor (rider|driver|admin), zoneIds, role, permissions."}}),
    ("parameters", PARAMS), ("responses", RESP), ("schemas", S)])

def to_plain(x):
    if isinstance(x, dict): return {k: to_plain(v) for k, v in x.items()}
    if isinstance(x, list): return [to_plain(v) for v in x]
    return x

class D(yaml.SafeDumper):
    def ignore_aliases(self, data): return True
header = f"# Movera API v{C['version']} — generated from contract.json (+ CONTRACT.md §7). PROPOSED; no backend exists.\n"
with open(OUT, "w") as f:
    f.write(header)
    yaml.dump(to_plain(doc), f, Dumper=D, sort_keys=False, allow_unicode=True, width=120)
nops = sum(len(v) for v in PATHS.values())
print(f"paths={len(PATHS)} operations={nops} schemas={len(S)}")
