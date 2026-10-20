"""Generates contracts/openapi.yaml (v0.4.0) from contract.json + hand-written surface.
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
S["CategoryId"] = s("Category id from the admin Pricing catalog. Seed ids are listed in x-seed; alias `movera` → `economy` is accepted on read for one release.",
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
S["FareLineCode"] = s(enum=["base", "distance", "time", "stops", "waiting", "pickup_pay", "surge", "discount", "cancel_fee"])
S["FareLine"] = obj({"code": ref("FareLineCode"), "amount": ref("Money")}, ["code", "amount"])

# --- trip
S["QuoteRef"] = obj({"quoteId": ref("Id"), "total": ref("Money"), "expiresAt": ref("Timestamp")}, ["quoteId", "total", "expiresAt"])
S["Waiting"] = obj({"arrivedAt": ref("Timestamp"), "freeUntil": ref("Timestamp"), "noShowAt": ref("Timestamp"),
                    "chargedSeconds": ref("DurationSeconds")}, ["arrivedAt", "freeUntil", "noShowAt", "chargedSeconds"])
S["Cancellation"] = obj({"actor": ref("Actor"), "reasonCode": ref("CancelReasonCode"), "at": ref("Timestamp"),
                         "fee": {"description": "Rider cancel / no-show fee. null = not decided yet or none.", **nullable("Money")},
                         "note": s(maxLength=1000)}, ["actor", "reasonCode", "at", "fee"])
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
    ("paymentMethod", ref("PaymentMethod")), ("paymentMethodId", ref("Id")),
    ("paymentStatus", ref("PaymentStatus")), ("ratingStatus", ref("RatingStatus")),
    ("driver", ref("DriverSummary")), ("driverLocation", ref("GeoFix")), ("etaSeconds", ref("DurationSeconds")),
    ("waiting", ref("Waiting")), ("cancellation", ref("Cancellation")),
    ("pinRequired", b("Driver must verify the rider PIN before `board`.")),
]), ["tripId", "status", "version", "sequence", "kind", "createdAt", "updatedAt", "riderId", "zoneId", "categoryId",
     "pickup", "dropoff", "stops", "fare", "paymentMethod", "ratingStatus", "pinRequired"],
    "Authoritative trip state. Field visibility depends on the actor (e.g. driverEarnings/commission are not shown to riders).")

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
    ("surgeMultiplier", n(minimum=1)), ("etaSeconds", ref("DurationSeconds")),
]), ["quoteId", "categoryId", "total", "fareLines", "expiresAt", "pickup", "dropoff", "stops"])
S["RouteQuote"] = obj({"routeQuoteId": ref("Id"), "tripId": ref("Id"), "total": ref("Money"),
                       "difference": {"allOf": [ref("Money")], "description": "total − current fare (may be negative)."},
                       "fareLines": arr(ref("FareLine")), "dropoff": ref("Place"), "stops": arr(ref("Place")),
                       "expiresAt": ref("Timestamp")},
                      ["routeQuoteId", "tripId", "total", "difference", "dropoff", "stops", "expiresAt"],
                      "Price for a route change after request; apply with PATCH /trips/{tripId}.")

S["Rider"] = obj({"riderId": ref("Id"), "firstName": s(), "phone": s(pattern=r"^\+[1-9]\d{6,14}$"), "email": s(format="email"),
                  "rating": n(minimum=0, maximum=5), "status": s(enum=["active", "suspended"]), "version": i(minimum=1)},
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
                   "firstName": s(), "rating": n(minimum=0, maximum=5), "zoneIds": arr(ref("Id")),
                   "categoryIds": arr(ref("CategoryId")), "vehicleId": ref("Id"), "documents": arr(ref("DocumentSummary")),
                   "activeTripId": ref("Id"), "version": i(minimum=1)},
                  ["driverId", "accountStatus", "onlineStatus", "firstName", "zoneIds", "categoryIds", "documents", "version"])
S["VehicleStatus"] = s(enum=["pending", "approved", "rejected", "blocked"])
S["Vehicle"] = obj({"vehicleId": ref("Id"), "make": s(), "model": s(), "year": i(minimum=1950, maximum=2100), "color": s(),
                    "plate": s(), "seats": i(minimum=1, maximum=20), "categoryIds": arr(ref("CategoryId")),
                    "status": ref("VehicleStatus"), "version": i(minimum=1)},
                   ["vehicleId", "make", "model", "year", "color", "plate", "seats", "categoryIds", "status", "version"])
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
S["Notification"] = obj({"notificationId": ref("Id"), "audience": s(enum=["rider", "driver"]),
                         "kind": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "title": s(), "body": s(), "at": ref("Timestamp"),
                         "read": b(), "tripId": ref("Id"), "deepLink": s()},
                        ["notificationId", "audience", "kind", "title", "body", "at", "read"])
S["Message"] = obj({"messageId": ref("Id"), "tripId": ref("Id"), "from": s(enum=["rider", "driver", "support"]),
                    "text": s(minLength=1, maxLength=2000), "at": ref("Timestamp")},
                   ["messageId", "tripId", "from", "text", "at"])
S["SavedPlace"] = obj({"placeId": ref("Id"), "label": s(minLength=1, maxLength=80), "kind": s(enum=["home", "work", "other"]),
                       "place": ref("Place")}, ["placeId", "label", "kind", "place"])
S["SupportTicket"] = obj({"ticketId": ref("Id"), "tripId": ref("Id"), "openedBy": ref("Actor"), "riderId": ref("Id"),
                          "driverId": ref("Id"), "category": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "subject": s(),
                          "status": s(enum=["open", "pending", "resolved", "closed"]),
                          "priority": s(enum=["low", "normal", "high", "urgent"]),
                          "createdAt": ref("Timestamp"), "updatedAt": ref("Timestamp")},
                         ["ticketId", "openedBy", "category", "subject", "status", "createdAt", "updatedAt"])
S["Incident"] = obj({"incidentId": ref("Id"), "tripId": ref("Id"), "kind": s(pattern="^[a-z][a-z0-9_]{0,63}$"),
                     "severity": s(enum=["low", "medium", "high", "critical"]),
                     "status": s(enum=["open", "investigating", "resolved", "dismissed"]),
                     "reportedBy": ref("Actor"), "openedAt": ref("Timestamp"), "updatedAt": ref("Timestamp")},
                    ["incidentId", "kind", "severity", "status", "openedAt"])
S["Payout"] = obj({"payoutId": ref("Id"), "driverId": ref("Id"), "amount": ref("Money"),
                   "status": s(enum=["pending", "pending_approval", "paid", "failed", "held"]),
                   "periodStart": ref("Timestamp"), "periodEnd": ref("Timestamp"), "createdAt": ref("Timestamp"),
                   "paidAt": ref("Timestamp")}, ["payoutId", "driverId", "amount", "status", "createdAt"])
S["EarningsPeriod"] = obj({"periodStart": ref("Timestamp"), "periodEnd": ref("Timestamp"), "tripCount": i(minimum=0),
                           "gross": ref("Money"), "commission": ref("Money"), "pickupPay": ref("Money"),
                           "tips": ref("Money"), "adjustments": ref("Money"), "cashCollected": ref("Money"),
                           "net": ref("Money")},
                          ["periodStart", "periodEnd", "tripCount", "gross", "commission", "tips", "adjustments", "net"])
S["EarningsReport"] = obj({"driverId": ref("Id"), "period": s(enum=["day", "week", "month"]), "timeZone": s(),
                           "periods": arr(ref("EarningsPeriod"))}, ["driverId", "period", "periods"])
S["DriverLocationAck"] = obj({"accepted": i(minimum=0), "serverTime": ref("Timestamp")}, ["accepted", "serverTime"])
S["PinCode"] = obj({"tripId": ref("Id"), "pin": s(pattern=r"^\d{4}$"), "expiresAt": ref("Timestamp")},
                   ["tripId", "pin", "expiresAt"], "Per-trip PIN shown to the rider when pinRequired.")
S["PinVerification"] = obj({"verifiedPinToken": s("Short-lived proof passed to `board`; the raw PIN is never stored or logged.", minLength=16),
                            "expiresAt": ref("Timestamp")}, ["verifiedPinToken", "expiresAt"])

# --- admin
S["AdminRole"] = s(enum=["viewer", "support", "dispatcher", "compliance", "finance", "safety", "content", "config", "fleet", "ops", "super"])
S["PendingApproval"] = obj({"status": s(const="pending_approval"), "approvalId": ref("Id"),
                            "action": s(examples=["trip.refund", "config.publish"]), "targetId": ref("Id"),
                            "requestedAt": ref("Timestamp")}, ["status", "approvalId", "action", "targetId", "requestedAt"],
                           "Returned with 202 when the action needs a second admin (two-person rule).")
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
S["ConfigDocName"] = s(enum=["rider_app_config", "driver_app_config"])
S["ConfigDraft"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"),
                        "version": i("Draft version (expectedVersion for PUT/publish).", minimum=1),
                        "liveVersion": i("Version of the published document the apps read.", minimum=0),
                        "document": {"oneOf": [ref("RiderAppConfig"), ref("DriverAppConfig")]},
                        "updatedAt": ref("Timestamp"), "updatedBy": ref("Id")},
                       ["doc", "zoneId", "version", "liveVersion", "document", "updatedAt"])
S["ConfigPublication"] = obj({"doc": ref("ConfigDocName"), "zoneId": ref("Id"), "version": i(minimum=1),
                              "publishedAt": ref("Timestamp")}, ["doc", "zoneId", "version", "publishedAt"])

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
S["CancelFees"] = obj({"live": ref("CancelFeeTable"), "reservation": ref("CancelFeeTable")})
S["CategoryCatalog"] = obj({"categories": arr(obj({"id": ref("CategoryId"), "label": s(), "seats": i(minimum=1), "sort": i()},
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
CONFIG_HEAD = OrderedDict([("version", i("Only increases; apps keep the last good document.", minimum=1)),
                           ("publishedAt", ref("Timestamp")), ("zoneId", ref("Id")), ("currency", ref("CurrencyCode")),
                           ("timeZone", s("IANA zone of the zone, for wall-clock rules and booking times.", pattern=r"^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)*$",
                                          examples=["Europe/Stockholm", "Europe/Paris", "Africa/Tunis"])),
                           ("country", ref("CountryCode")), ("languages", ref("Languages"))])
ZONE_PM = ("paymentMethods", arr(ref("ZonePaymentMethod"), uniqueItems=True, description="Methods offered in the zone; the wallet is separate."))
S["RiderAppConfig"] = obj(OrderedDict(list(CONFIG_HEAD.items()) + [
    ("catalog", ref("CategoryCatalog")),
    ("features", {"type": "object", "properties": {"scheduledRides": b(), "wallet": b(), "pin": b(), "shareTrip": b()},
                  "additionalProperties": {"type": "boolean"}}),
    ZONE_PM,
    ("wallet", obj({"usedFirst": b("The balance (one per currency, no conversion) pays first.")})),
    ("tips", arr(ref("AmountOption"), description="Tip options in admin order.")),
    ("raiseSteps", arr(ref("AmountOption"), description="Raise-offer quick steps while searching, in admin order.")),
    ("promoCap", {"oneOf": [ref("Money"), {"type": "null"}], "description": "Most a promotion may take off one trip in this country; null = no cap set."}),
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
                    "offerCard": {"type": "object", "description": "Which fields the offer card shows.",
                                  "properties": {"netFare": b(), "pickupAddress": b(), "dropoffAreaOnly": b(), "stops": b()},
                                  "additionalProperties": {"type": "boolean"}},
                    "exclusiveReasons": arr(obj({"id": s(pattern="^[a-z][a-z0-9_-]{0,63}$"), "text": s(), "on": b()}, ["id", "text", "on"])),
                    "autoOffline": obj({"missedExclusive": i("Missed or declined exclusive offers in a row before the driver is set offline (default 3).", minimum=0),
                                        "hiddenComesBackMin": n(minimum=0)})})),
    ("pickupPay", obj({"perKm": ref("Money"), "perMin": ref("Money"), "freeKm": n(minimum=0), "freeMin": n(minimum=0),
                       "ranges": arr({"type": "object", "description": "Distance band override (shape owned by Admin Pricing).",
                                      "properties": {"fromKm": n(minimum=0), "toKm": {"type": ["number", "null"]},
                                                     "amount": ref("Money")}}),
                       "display": s(enum=["total", "breakdown"])})),
    ("driverBonus", ref("DriverBonusLimits")),
    ("cancelFees", ref("CancelFees")),
    ("waiting", ref("DriverWaiting")),
    ("destinationMode", {"type": "object", "properties": {"perDay": i(minimum=0)}}),
    ("nextTrips", {"type": "object", "properties": {"on": b()}}),
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
                                 "description": "For offer_withdrawn, offer.status is claimed_elsewhere | expired | withdrawn."}},
                      ["eventId", "sequence", "kind", "occurredAt", "serverTime", "offer"], "Driver offer feed event.")
S["ConfigEvent"] = obj({"eventId": ref("Id"), "kind": s(const="config_published"), "doc": ref("ConfigDocName"),
                        "zoneId": ref("Id"), "version": i(minimum=1), "publishedAt": ref("Timestamp"),
                        "occurredAt": ref("Timestamp"), "serverTime": ref("Timestamp")},
                       ["eventId", "kind", "doc", "zoneId", "version", "publishedAt", "occurredAt", "serverTime"],
                       "Apps re-fetch the config document on this event.")

# --- error
S["Error"] = obj({"code": ref("ErrorCode"), "message": s(), "requestId": s(), "retryable": b(),
                  "projection": {"description": "Current authoritative resource. Always present for version_mismatch and invalid_transition "
                                                 "(TripProjection for trip commands; Offer / Driver / Rider / Vehicle / ConfigDraft for their commands).",
                                 "anyOf": [ref("TripProjection"), ref("Offer"), ref("Driver"), ref("Rider"), ref("Vehicle"), ref("ConfigDraft")]}},
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
         "SavedPlace", "SavedPaymentMethod", "RealtimeEvent", "Quote", "AdminDispatchEvent"]
for p in PAGES:
    S[f"{p}Page"] = {"allOf": [ref("Page"), {"type": "object", "properties": {"items": arr(ref(p))}}],
                     "description": f"Page<{p}>"}

# --- request bodies
EV = {"expectedVersion": i("Version the caller last saw; stale → 409 version_mismatch.", minimum=1)}
S["TripCommand"] = obj(dict(EV, location=ref("GeoFix")), ["expectedVersion"], "Body of driver trip commands.")
S["BoardCommand"] = {"allOf": [ref("TripCommand"), obj({"verifiedPinToken": s("Required when the trip has pinRequired=true.")})]}
S["CompleteCommand"] = {"allOf": [ref("TripCommand"), obj({"cashCollected": ref("Money")})]}
S["NoShowCommand"] = {"allOf": [ref("TripCommand"), obj({"reasonCode": ref("NoShowReasonCode")})]}
S["CancelCommand"] = obj(dict(EV, reasonCode=ref("CancelReasonCode"), note=s(maxLength=1000), location=ref("GeoFix")),
                         ["expectedVersion", "reasonCode"],
                         "Actor comes from the token; reasonCode must be in the actor's group (rider; driverBeforeTrip/driverDuringTrip/scheduled/driverNextTrip).")
S["EndEarlyCommand"] = obj(dict(EV, reasonCode=ref("RiderCancelReasonCode"), note=s(maxLength=1000)), ["expectedVersion"])
S["QuoteRequest"] = obj({"pickup": ref("Place"), "dropoff": ref("Place"), "stops": arr(ref("Place"), description="MUST be sent (may be empty)."),
                         "categoryIds": arr(ref("CategoryId"), description="Omit for every category in the zone."),
                         "kind": ref("TripKind"), "scheduledAt": ref("Timestamp"), "paymentMethod": ref("PaymentMethod")},
                        ["pickup", "dropoff", "stops"])
S["QuoteList"] = obj({"quotes": arr(ref("Quote")), "zoneId": ref("Id"), "serverTime": ref("Timestamp")}, ["quotes", "zoneId"])
S["CreateTripRequest"] = obj({"quoteId": ref("Id"), "categoryId": ref("CategoryId"), "pickup": ref("Place"),
                              "dropoff": ref("Place"), "stops": arr(ref("Place")), "kind": ref("TripKind"),
                              "scheduledAt": ref("Timestamp"), "paymentMethod": ref("PaymentMethod"),
                              "paymentMethodId": ref("Id"), "walletFirst": b("Use wallet balance before the method."),
                              "notes": s(maxLength=500)},
                             ["quoteId", "categoryId", "pickup", "dropoff", "stops", "kind", "paymentMethod"],
                             "Request a quoted trip. No expectedVersion: the trip does not exist yet; Idempotency-Key dedupes.")
S["UpdateTripRequest"] = obj(dict(EV, routeQuoteId=ref("Id"), dropoff=ref("Place"), stops=arr(ref("Place")),
                                  paymentMethod=ref("PaymentMethod"), paymentMethodId=ref("Id")),
                             ["expectedVersion"], "Route change (needs routeQuoteId from /route-quote) and/or payment method change.")
S["RouteQuoteRequest"] = obj(dict(EV, dropoff=ref("Place"), stops=arr(ref("Place"))), ["expectedVersion", "stops"])
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
S["NearbyDriver"] = obj({"driverId": ref("Id"), "firstName": s(), "onlineStatus": ref("DriverOnlineStatus"),
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
                              "Above refundLimit[role][country] → 202 pending_approval.")
S["AdminAdjustCommand"] = obj(dict(EV, fare=ref("Money"), waitingSeconds=i(minimum=0), waiveCancelFee=b(),
                                   reason=s(minLength=1, maxLength=1000)), ["expectedVersion", "reason"],
                              "Fare / waiting / cancel-fee correction. Over the role limit → 202 pending_approval.")
S["DriverStatusCommand"] = obj(dict(EV, accountStatus=ref("DriverAccountStatus"), note=s(minLength=1, maxLength=1000)),
                               ["expectedVersion", "accountStatus", "note"])
S["RiderStatusCommand"] = obj(dict(EV, status=s(enum=["active", "suspended"]), note=s(minLength=1, maxLength=1000)),
                              ["expectedVersion", "status", "note"])
S["VehicleReviewCommand"] = obj(dict(EV, decision=s(enum=["approved", "rejected", "blocked"]), note=s(maxLength=1000)),
                                ["expectedVersion", "decision"])
S["DocumentReviewCommand"] = obj({"decision": s(enum=["approved", "rejected"]), "expiresAt": ref("Timestamp"),
                                  "note": s(maxLength=1000)}, ["decision"],
                                 "Document has no version in CONTRACT.md §2; Idempotency-Key only.")
S["ConfigDraftUpdate"] = obj(dict(EV, zoneId=ref("Id"), document={"oneOf": [ref("RiderAppConfig"), ref("DriverAppConfig")]}),
                             ["expectedVersion", "zoneId", "document"])
S["ConfigPublishCommand"] = obj(dict(EV, zoneId=ref("Id"), note=s(maxLength=1000)), ["expectedVersion", "zoneId"])
S["ApprovalDecision"] = obj({"note": s(maxLength=1000)})

# ---------------------------------------------------------------- parameters / responses
PARAMS = OrderedDict()
def path_id(name, desc=None):
    p = {"name": name, "in": "path", "required": True, "schema": ref("Id")}
    if desc: p["description"] = desc
    return p
for nm in ["tripId", "offerId", "paymentId", "paymentMethodId", "placeId", "notificationId", "driverId", "riderId",
           "vehicleId", "documentId", "approvalId"]:
    PARAMS[nm[0].upper() + nm[1:]] = path_id(nm)
PARAMS["RideId"] = path_id("rideId", "Deprecated alias of tripId.")
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
PARAMS["ZoneIdRequired"] = {"name": "zoneId", "in": "query", "required": True, "schema": ref("Id")}
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
       body_type="application/json"):
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
    if approval: rs["202"] = rref("PendingApproval")
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
   params=TID + [pref("Cursor"), pref("Limit")], ok=(200, "MessagePage"))
op("post", "/trips/{tripId}/messages", "sendTripMessage", "Send a trip chat message (emits kind=message)", ["rider", "driver", "admin"],
   "Notifications & messages", params=TID, body="MessageRequest", ok=(201, "Message"), mutation=True)
op("get", "/support/tickets", "listOwnTickets", "Own support tickets", ["rider", "driver"], "Support",
   params=[pref("Cursor"), pref("Limit"), q("status", {"type": "string", "enum": ["open", "pending", "resolved", "closed"]})],
   ok=(200, "SupportTicketPage"))
op("post", "/support/tickets", "createTicket", "Open a support ticket", ["rider", "driver"], "Support",
   body="TicketRequest", ok=(201, "SupportTicket"), mutation=True)

# ---- Driver
op("post", "/driver/availability", "setDriverAvailability", "Go online / offline", ["driver"], "Driver · Session",
   body="AvailabilityRequest", ok=(200, "Driver"), mutation=True,
   desc="409 when on a trip, account not active, documents expired or driving limit reached (projection = Driver).")
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
   body="DriverProfileUpdate", ok=(200, "Driver"), mutation=True)
op("get", "/driver/vehicles", "listDriverVehicles", "Own vehicles", ["driver"], "Driver · Account",
   params=[pref("Cursor"), pref("Limit")], ok=(200, "VehiclePage"))
op("post", "/driver/vehicles", "addDriverVehicle", "Register a vehicle (status pending)", ["driver"], "Driver · Account",
   body="VehicleRequest", ok=(201, "Vehicle"), mutation=True)
op("get", "/driver/documents", "listDriverDocuments", "Own and vehicle documents", ["driver"], "Driver · Account",
   params=[pref("Cursor"), pref("Limit"), q("status", ref("DocumentStatus"), multi=True)], ok=(200, "DocumentPage"))
op("post", "/driver/documents", "uploadDriverDocument", "Upload a document (status in_review)", ["driver"], "Driver · Account",
   body="DocumentUpload", body_type="multipart/form-data", ok=(201, "Document"), mutation=True)

# ---- Admin
AL = [pref("Cursor"), pref("Limit")]
lists = {
    "trips": ("TripProjectionPage", "trips.read", [q("status", ref("TripStatus"), multi=True), q("kind", ref("TripKind")), pref("ZoneIdQuery"),
              q("categoryId", ref("CategoryId")), q("riderId", ref("Id")), q("driverId", ref("Id")), q("paymentStatus", ref("PaymentStatus")),
              pref("From"), pref("To"), pref("Q")]),
    "riders": ("RiderPage", "riders.read", [q("status", {"type": "string", "enum": ["active", "suspended"]}), pref("ZoneIdQuery"), pref("Q")]),
    "drivers": ("DriverPage", "drivers.read", [q("accountStatus", ref("DriverAccountStatus"), multi=True),
                q("onlineStatus", ref("DriverOnlineStatus"), multi=True), pref("ZoneIdQuery"), q("categoryId", ref("CategoryId")), pref("Q")]),
    "vehicles": ("VehiclePage", "fleet.read", [q("status", ref("VehicleStatus"), multi=True), q("driverId", ref("Id")),
                 q("categoryId", ref("CategoryId")), pref("Q")]),
    "payments": ("PaymentIntentPage", "payments.read", [q("status", ref("PaymentStatus"), multi=True), q("method", ref("PaymentMethod")),
                 q("tripId", ref("Id")), q("riderId", ref("Id")), pref("ZoneIdQuery"), pref("From"), pref("To")]),
    "refunds": ("RefundPage", "payments.read", [q("status", ref("RefundStatus"), multi=True), q("paymentId", ref("Id")), q("tripId", ref("Id")),
                pref("From"), pref("To")]),
    "payouts": ("PayoutPage", "payments.read", [q("status", {"type": "string", "enum": ["pending", "pending_approval", "paid", "failed", "held"]}, multi=True),
                q("driverId", ref("Id")), pref("From"), pref("To")]),
    "tickets": ("SupportTicketPage", "support.read", [q("status", {"type": "string", "enum": ["open", "pending", "resolved", "closed"]}, multi=True),
                q("priority", {"type": "string", "enum": ["low", "normal", "high", "urgent"]}), q("tripId", ref("Id")),
                q("riderId", ref("Id")), q("driverId", ref("Id")), pref("Q")]),
    "incidents": ("IncidentPage", "safety.read", [q("status", {"type": "string", "enum": ["open", "investigating", "resolved", "dismissed"]}, multi=True),
                  q("severity", {"type": "string", "enum": ["low", "medium", "high", "critical"]}), q("kind", {"type": "string"}),
                  q("tripId", ref("Id")), pref("ZoneIdQuery"), pref("From"), pref("To")]),
}
for name, (page, perm, filt) in lists.items():
    op("get", f"/admin/{name}", f"adminList{name.capitalize()}", f"List {name} (cursor paging)", ["admin"], "Admin · Lists",
       params=AL + filt, ok=(200, page), permission=perm,
       desc="Results are limited to the zones in the admin's token scope.")
op("get", "/admin/trips/{tripId}", "adminGetTrip", "Trip detail incl. money split", ["admin"], "Admin · Trips",
   params=TID, ok=(200, TP), permission="trips.read")
for seg, cmd, opid, body, summ, perm, appr, okc in [
        ("cancel", "cancel", "adminCancelTrip", "AdminCancelCommand", "Cancel any non-terminal trip", "trips.edit", False, (200, TP)),
        ("reassign", "reassign", "adminReassignTrip", "AdminReassignCommand", "Take the trip from its driver, back to searching", "trips.edit", False, (200, TP)),
        ("assign", "assign", "adminAssignTrip", "AdminAssignCommand", "Direct assign: exclusive offer to one driver (Assigned by Movera)", "trips.edit", False, (200, TP)),
        ("radar-group", "assign", "adminSendRadarGroup", "AdminRadarGroupCommand", "Send the trip to a radar group of up to 10 drivers", "trips.edit", False, (200, "AdminRadarGroup")),
        ("no-show", "no_show", "adminMarkNoShow", "AdminNoShowCommand", "Mark rider no-show", "trips.edit", False, (200, TP)),
        ("complete", "complete", "adminCompleteTrip", "AdminCompleteCommand", "Force-complete a stuck onboard trip", "trips.edit", False, (200, TP)),
        ("refund", None, "adminRefundTrip", "AdminRefundCommand", "Refund (full or partial)", "payments.edit", True, (201, "Refund")),
        ("adjust", None, "adminAdjustTrip", "AdminAdjustCommand", "Adjust fare / waiting / waive cancel fee", "trips.edit", True, (200, TP)),
        ("driver-bonus", None, "adminAddDriverBonus", "AdminDriverBonusCommand", "Add money to the trip for the driver (paid by Movera)", "trips.edit", False, (200, TP))]:
    op("post", f"/admin/trips/{{tripId}}/{seg}", opid, summ, ["admin"], "Admin · Trips", params=TID, body=body, ok=okc,
       mutation=True, transition=cmd, approval=appr, permission=perm,
       desc=None if cmd else "Not a lifecycle transition (status unchanged; paymentStatus/fare change and emit payment_updated / trip_projection).")
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
op("post", "/admin/drivers/{driverId}/status", "adminSetDriverStatus", "Set driver account status", ["admin"], "Admin · People",
   params=[pref("DriverId")], body="DriverStatusCommand", ok=(200, "Driver"), mutation=True, permission="drivers.edit")
op("post", "/admin/riders/{riderId}/status", "adminSetRiderStatus", "Set rider status", ["admin"], "Admin · People",
   params=[pref("RiderId")], body="RiderStatusCommand", ok=(200, "Rider"), mutation=True, permission="riders.edit")
op("post", "/admin/vehicles/{vehicleId}/review", "adminReviewVehicle", "Approve / reject / block a vehicle", ["admin"], "Admin · People",
   params=[pref("VehicleId")], body="VehicleReviewCommand", ok=(200, "Vehicle"), mutation=True, permission="fleet.edit")
op("post", "/admin/documents/{documentId}/review", "adminReviewDocument", "Approve / reject a document", ["admin"], "Admin · People",
   params=[pref("DocumentId")], body="DocumentReviewCommand", ok=(200, "Document"), mutation=True, permission="drivers.edit")
op("get", "/admin/config/{doc}", "adminGetConfigDraft", "Get the config draft for a zone", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc"), pref("ZoneIdRequired")], ok=(200, "ConfigDraft"), permission="config.read")
op("put", "/admin/config/{doc}", "adminPutConfigDraft", "Replace the config draft", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigDraftUpdate", ok=(200, "ConfigDraft"), mutation=True, permission="config.edit")
op("post", "/admin/config/{doc}/publish", "adminPublishConfig", "Publish the draft (two-person approval)", ["admin"], "Admin · Config",
   params=[pref("ConfigDoc")], body="ConfigPublishCommand", ok=(200, "ConfigPublication"), mutation=True, approval=True,
   permission="config.edit", desc="Normally 202 pending_approval; 200 when the approver publishes directly. Emits config_published.")
op("get", "/admin/audit", "adminListAudit", "Server-written audit log", ["admin"], "Admin · Governance",
   params=AL + [q("actorId", ref("Id")), q("targetType", {"type": "string"}), q("targetId", ref("Id")), q("action", {"type": "string"}),
                q("result", {"type": "string", "enum": ["committed", "rejected", "denied", "conflict", "pending_approval"]}), pref("From"), pref("To")],
   ok=(200, "AuditEntryPage"), permission="audit.read")
op("get", "/admin/approvals", "adminListApprovals", "Approval queue", ["admin"], "Admin · Governance",
   params=AL + [q("status", {"type": "string", "enum": ["pending_approval", "approved", "rejected", "expired"]}, multi=True),
                q("targetType", {"type": "string"})], ok=(200, "ApprovalPage"), permission="approval.read")
for d in ["approve", "reject"]:
    op("post", f"/admin/approvals/{{approvalId}}/{d}", f"adminApproval{d.capitalize()}", f"{d.capitalize()} a pending action (not the requester)",
       ["admin"], "Admin · Governance", params=[pref("ApprovalId")], body="ApprovalDecision", ok=(200, "Approval"), mutation=True,
       permission="approval.decide")

# ---- Deprecated aliases
o = op("get", "/rides/{rideId}", "getRideDeprecated", "Deprecated alias of GET /trips/{tripId}", ["rider"], "Deprecated",
       params=[pref("RideId")], ok=(200, TP), deprecated=True, desc="Removed after v0.3. Response is the TripProjection (tripId + rideId).")
o = op("post", "/rides/{rideId}/cancel", "cancelRideDeprecated", "Deprecated alias of POST /trips/{tripId}/cancel", ["rider"], "Deprecated",
       params=[pref("RideId")], body="CancelCommand", ok=(200, TP), mutation=True, transition="cancel", deprecated=True)

# ---------------------------------------------------------------- document
TAG_DESC = {"Trips": "Shared trip resource (rider, driver, admin)", "Realtime": "Streams: SSE (or WebSocket) + JSON replay",
            "Deprecated": "Legacy /rides aliases kept for one release"}
doc = OrderedDict()
doc["openapi"] = "3.1.0"
doc["info"] = {
    "title": "Movera API",
    "version": "0.4.0",
    "description": (
        "**Proposed contract — no backend exists yet.** One future backend serves the Rider (Flutter), Driver (Flutter) and "
        "Admin (React/TS) apps. Source of truth for names, enums, transitions, realtime and errors is `contract.json` + "
        "`CONTRACT.md` v0.4.0 in this folder; this file must agree with them.\n\n"
        "Wire rules: ids match `" + ID_PATTERN + "`; times are RFC 3339 UTC with `Z`; durations are integer seconds; money is "
        "`Money {amountMinor, currency}`; keys camelCase, enum values snake_case. Success responses are the bare resource; errors are `Error`.\n\n"
        "Every mutation needs `Idempotency-Key`. Trip, offer, driver, rider, vehicle and config commands send `expectedVersion`; a stale "
        "version is `409 version_mismatch` and a command not allowed from the current status is `409 invalid_transition`, both with the current "
        "`projection`.\n\n"
        "Extensions: `x-actor` = actors allowed (derived from the token); `x-transition` = contract.json transition command; "
        "`x-permission` = admin permission; `x-terminal` on TripStatus = terminal set.\n\n"
        "Auth: bearer JWT. Actor (rider|driver|admin), subject id, zone scope and admin role/permissions come from the token, never from the body. "
        "Token issuance (OTP/refresh) is out of scope for v0.4."),
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
header = "# Movera API v0.4.0 — generated from contract.json (+ CONTRACT.md §7). PROPOSED; no backend exists.\n"
with open(OUT, "w") as f:
    f.write(header)
    yaml.dump(to_plain(doc), f, Dumper=D, sort_keys=False, allow_unicode=True, width=120)
nops = sum(len(v) for v in PATHS.values())
print(f"paths={len(PATHS)} operations={nops} schemas={len(S)}")
