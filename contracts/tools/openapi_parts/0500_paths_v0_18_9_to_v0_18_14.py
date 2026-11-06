# Split from tools/gen_openapi.py (rule 25, no behaviour change): run by it in name order with its globals.
# ---- v0.18.9 (driver group 7: on trip; contract.json#onTrip)
OT = C["onTrip"]
_RC = OT["rideCheck"]
_RX = OT["routeChange"]
_RCD = C["configDefaults"]["rideCheck"]
_RXD = C["configDefaults"]["routeChange"]
S["RideCheck"] = obj(OrderedDict([
    ("on", {**b("v0.18.9: " + _RC["settings"]["fields"]["on"]), "default": _RCD["on"]}),
    ("stopMinutes", {**n("v0.18.9: " + _RC["settings"]["fields"]["stopMinutes"], minimum=0), "default": _RCD["stopMinutes"]}),
    ("offRouteKm", {**n("v0.18.9: " + _RC["settings"]["fields"]["offRouteKm"], minimum=0), "default": _RCD["offRouteKm"]}),
    ("endFarMeters", {**i("v0.18.9: " + _RC["settings"]["fields"]["endFarMeters"], minimum=0), "default": _RCD["endFarMeters"]}),
    ("noAnswerSeconds", {**i("v0.18.9: " + _RC["settings"]["fields"]["noAnswerSeconds"], minimum=0), "default": _RCD["noAnswerSeconds"]}),
    ("repeatMinutes", {**i("v0.18.9: " + _RC["settings"]["fields"]["repeatMinutes"], minimum=0), "default": _RCD["repeatMinutes"]}),
    ("noAnswerAlarm", {**b("v0.18.9: " + _RC["settings"]["fields"]["noAnswerAlarm"]), "default": _RCD["noAnswerAlarm"]}),
]), desc="Ride check settings (Safety). v0.18.9: " + _RC["settings"]["where"] + " " + _RC["settings"]["invalid"])
S["RouteChangeSettings"] = obj(OrderedDict([
    ("on", {**b("v0.18.9: " + _RX["settings"]["fields"]["on"]), "default": _RXD["on"]}),
    ("driverCanRefuse", {**b("v0.18.9: " + _RX["settings"]["fields"]["driverCanRefuse"]), "default": _RXD["driverCanRefuse"]}),
    ("answerSeconds", {**i("v0.18.9: " + _RX["settings"]["fields"]["answerSeconds"], minimum=15, maximum=300), "default": _RXD["answerSeconds"]}),
    ("beforePickup", {**b("v0.18.9: " + _RX["settings"]["fields"]["beforePickup"]), "default": _RXD["beforePickup"]}),
    ("fixedPriceTrips", {**s("v0.18.9: " + _RX["settings"]["fields"]["fixedPriceTrips"], enum=_RX["settings"]["values"]["fixedPriceTrips"]), "default": _RXD["fixedPriceTrips"]}),
]), desc="v0.18.9: " + _RX["settings"]["where"])
S["DriverAppConfig"]["properties"]["routeChange"] = ref("RouteChangeSettings")
S["RiderAppConfig"]["properties"]["routeChange"] = {"allOf": [ref("RouteChangeSettings")], "description": "v0.18.9: copied from the zone's driver document when served (GET /rider/config)."}
S["TripRideCheck"] = obj(OrderedDict([
    ("checkId", ref("Id")), ("trigger", ref("RideCheckTrigger")), ("askedAt", ref("Timestamp")), ("answerBy", ref("Timestamp")),
    ("answers", obj({"rider": s(enum=["ok", "need_help"]), "driver": s(enum=["ok", "need_help"])}, desc="Each side's answer so far.")),
    ("alertedAt", {"allOf": [ref("Timestamp")], "description": "A side did not answer in time: the safety team was alerted (ride_check incident)."}),
]), ["checkId", "trigger", "askedAt", "answerBy", "answers"], "v0.18.9: " + _RC["ask"]["projection"] + " " + _RC["ask"]["apps"])
S["TripRouteChange"] = obj(OrderedDict([
    ("changeId", ref("Id")), ("routeQuoteId", ref("Id")), ("status", s(enum=["pending", "accepted", "refused", "expired", "withdrawn"])),
    ("dropoff", ref("Place")), ("stops", arr(ref("Place"))), ("total", ref("Money")), ("difference", ref("Money")),
    ("askedAt", ref("Timestamp")), ("answerBy", ref("Timestamp")), ("answeredAt", ref("Timestamp")),
    ("answeredBy", s(enum=["driver", "rider", "system"])),
    ("driverEarnings", {"allOf": [ref("Money")], "description": "Driver and admin views only: the driver's earnings with the new route."}),
    ("earningsDifference", {"allOf": [ref("Money")], "description": "Driver and admin views only: new − current earnings."}),
]), ["changeId", "status", "dropoff", "stops", "total", "difference", "askedAt", "answerBy"], "v0.18.9: " + _RX["projection"] + " " + _RX["price"])
S["TripProjection"]["properties"]["rideCheck"] = ref("TripRideCheck")
S["DriverBonusOfKind"] = obj({"amountMinor": i(minimum=0), "currency": s(pattern="^[A-Z]{3}$"), "priority": b()}, ["amountMinor", "currency", "priority"], "The admin's money and Priority badge for one kind of offer.")
S["TripProjection"]["properties"]["moneySend"] = obj({"exclusiveTo": {"oneOf": [ref("Id"), {"type": "null"}]}, "radarTo": arr(ref("Id")), "skipped": obj({"expired": {"type": "integer", "minimum": 0}, "busy": {"type": "integer", "minimum": 0}, "far": {"type": "integer", "minimum": 0}}, ["expired", "busy", "far"], "Live fix 2026-11-02 (additive): free drivers left out. expired = declined or let an offer of this trip expire; busy = refused when sent; far = beyond reachKm."), "reachKm": {"oneOf": [{"type": "number", "minimum": 0}, {"type": "null"}], "description": "Live fix 2026-11-02 (additive): the widest reach used in km; null = no limit."}}, ["exclusiveTo", "radarTo"], "Answer of POST /admin/trips/{tripId}/driver-bonus with applyTo only: who got an offer with the money at once.")
S["TripProjection"]["properties"]["driverBonusByKind"] = obj({"exclusive": ref("DriverBonusOfKind"), "radar": ref("DriverBonusOfKind")}, ["exclusive", "radar"], "Admin view only (owner bug 2026-11-01): " + C["adminDispatch"]["driverBonus"]["applyTo"]["note"])
S["TripProjection"]["properties"]["routeChange"] = ref("TripRouteChange")
S["AdminTripFlag"] = obj({"flagged": b(), "reason": s(maxLength=500), "by": ref("Id"), "at": ref("Timestamp")}, ["flagged", "by", "at"], "v0.18.9: " + OT["adminTrip"]["new"]["flag"])
S["TripProjection"]["properties"]["adminFlag"] = {"allOf": [ref("AdminTripFlag")], "description": "v0.18.9: admin view only."}
S["TripTerms"]["properties"]["stopWaitPerMin"] = {"allOf": [ref("Money")], "description": "v0.18.9: " + OT["stopWaiting"]["pricePerMinute"]}
S["UpdateTripRequest"]["description"] += " v0.18.9: " + " ".join(_RX["flow"][1:2])
S["RouteQuoteRequest"]["description"] = "v0.18.9: " + _RX["flow"][0]
S["RouteChangeAnswer"] = obj(dict(EV, changeId=ref("Id")), ["expectedVersion", "changeId"], "v0.18.9: the driver's answer or the rider's withdraw of a pending route change.")
for seg, opid, summ, who in [("accept", "acceptRouteChange", "Driver accepts the rider's route change", "driver"), ("refuse", "refuseRouteChange", "Driver refuses the rider's route change (the old route stays)", "driver"),
                             ("withdraw", "withdrawRouteChange", "Rider withdraws a pending route change", "rider")]:
    op("post", f"/trips/{{tripId}}/route-change/{seg}", opid, summ, [who], "Trips", params=TID, body="RouteChangeAnswer", ok=(200, TP), mutation=True,
       desc="v0.18.9: " + " ".join(_RX["flow"]) + " " + " ".join(_RX["rules"].values()))
PATHS["/trips/{tripId}/route-quote"]["post"]["description"] = "v0.18.9: " + _RX["flow"][0] + " " + " ".join(_RX["rules"].values())
PATHS["/trips/{tripId}"]["patch"]["description"] = "v0.18.9: " + _RX["flow"][1] + " v0.18.7: { expectedVersion, pickup } moves the pickup."
for _p in ["/quotes", "/trips"]:
    PATHS[_p]["post"]["description"] = PATHS[_p]["post"].get("description", "") + " v0.18.9: " + OT["maxStops"]["enforced"]
S["RideCheckRow"] = obj(OrderedDict([
    ("tripId", ref("Id")), ("zoneId", ref("Id")), ("side", s(enum=["rider", "driver"])), ("checkId", ref("Id")), ("origin", s(enum=["server", "app"])),
    ("trigger", ref("RideCheckTrigger")), ("shownAt", ref("Timestamp")), ("answer", s(enum=["ok", "need_help"])), ("answeredAt", ref("Timestamp")),
    ("noAnswerAt", ref("Timestamp")), ("incidentId", ref("Id")), ("position", obj({"lat": n(), "lng": n(), "accuracyM": n(), "at": ref("Timestamp")})), ("createdAt", ref("Timestamp")),
]), ["tripId", "zoneId", "side", "checkId", "origin", "trigger", "createdAt"], "v0.18.9: " + _RC["adminList"]["row"])
S["RideCheckList"] = obj({"items": arr(ref("RideCheckRow")), "nextCursor": {"type": ["string", "null"]}}, ["items", "nextCursor"])
op("get", "/admin/ride-checks", "adminListRideChecks", "Every ride check (server and app), newest first", ["admin"], "Admin · Safety",
   params=[q("zoneId", ref("Id")), q("tripId", ref("Id")), q("trigger", ref("RideCheckTrigger")), q("answer", s(enum=["ok", "need_help", "no_answer", "waiting"])),
           q("origin", s(enum=["server", "app"])), q("from", ref("Timestamp")), q("to", ref("Timestamp")), q("cursor", s()), q("limit", i(minimum=1, maximum=200))],
   ok=(200, "RideCheckList"), permission="incidents.read", desc="v0.18.9: " + _RC["adminList"]["endpoint"] + " " + _RC["adminList"]["answerFilter"])
S["AdminTripFlagCommand"] = obj({"flagged": b(), "reason": s(maxLength=500)}, ["flagged"])
op("post", "/admin/trips/{tripId}/flag", "adminFlagTrip", "Flag or unflag a trip (admin only)", ["admin"], "Admin · Trips", params=TID, body="AdminTripFlagCommand",
   ok=(200, "AdminTripFlag"), mutation=True, permission="trips.annotate", desc="v0.18.9: " + OT["adminTrip"]["new"]["flag"])
S["AdminTripNote"] = obj({"noteId": ref("Id"), "tripId": ref("Id"), "text": s(minLength=1, maxLength=2000), "adminId": ref("Id"), "adminName": s(), "at": ref("Timestamp")}, ["noteId", "tripId", "text", "adminId", "at"])
S["AdminTripNoteList"] = obj({"items": arr(ref("AdminTripNote"))}, ["items"])
S["AdminTripNoteCommand"] = obj({"text": s(minLength=1, maxLength=2000)}, ["text"])
op("get", "/admin/trips/{tripId}/notes", "adminTripNotes", "The admins' notes on a trip", ["admin"], "Admin · Trips", params=TID, ok=(200, "AdminTripNoteList"), permission="trips.read", desc="v0.18.9: " + OT["adminTrip"]["new"]["notes"])
op("post", "/admin/trips/{tripId}/notes", "adminAddTripNote", "Add a note to a trip", ["admin"], "Admin · Trips", params=TID, body="AdminTripNoteCommand", ok=(201, "AdminTripNote"), mutation=True, permission="trips.annotate", desc="v0.18.9: " + OT["adminTrip"]["new"]["notes"])
S["AdminTripCaseCommand"] = obj({"about": s(enum=["rider", "driver"]), "category": s(pattern="^[a-z][a-z0-9_]{0,63}$"), "subject": s(minLength=1, maxLength=200), "text": s(minLength=1, maxLength=5000), "visibleToPerson": b("v0.18.9 (owner rule 16): true = the person sees the case in their own help list; false (default) = internal.")}, ["about", "category", "subject", "text"])
op("post", "/admin/trips/{tripId}/case", "adminOpenTripCase", "Open a support case for the trip's rider or driver", ["admin"], "Admin · Trips", params=TID, body="AdminTripCaseCommand", ok=(201, "SupportTicket"), mutation=True, permission="support.reply", desc="v0.18.9: " + OT["adminTrip"]["new"]["case"])
S["AdminRevealContactCommand"] = obj({"who": s(enum=["rider", "driver"]), "reason": s(minLength=1, maxLength=500)}, ["who", "reason"])
S["RevealedContact"] = obj({"who": s(enum=["rider", "driver"]), "phone": s(), "revealedAt": ref("Timestamp")}, ["who", "phone", "revealedAt"])
op("post", "/admin/trips/{tripId}/reveal-contact", "adminRevealTripContact", "Show the rider's or driver's phone number (reason, audited)", ["admin"], "Admin · Trips", params=TID, body="AdminRevealContactCommand", ok=(200, "RevealedContact"), mutation=True, permission="riders.viewSensitive", desc="v0.18.9: " + OT["adminTrip"]["new"]["revealContact"])
S["AdminIncidentLevelCommand"] = obj(dict(EV, severity=s(enum=["low", "medium", "high", "critical"]), note=s(maxLength=1000)), ["expectedVersion", "severity"])
op("post", "/admin/incidents/{incidentId}/level", "adminIncidentLevel", "Change an incident's level", ["admin"], "Admin · Safety", params=[pref("IncidentId")], body="AdminIncidentLevelCommand", ok=(200, "Incident"), mutation=True, permission="safety.edit", desc="v0.18.9: " + OT["adminTrip"]["new"]["incidentLevel"])
PATHS["/admin/trips"]["get"].setdefault("parameters", []).append(q("flagged", b(), "v0.18.9: only flagged trips."))
PATHS["/admin/trips/{tripId}/adjust"]["post"]["description"] = PATHS["/admin/trips/{tripId}/adjust"]["post"].get("description", "") + " v0.18.9: " + OT["adminTrip"]["existing"]["adjust"]

# ---- v0.18.10 (driver group 8: finish & cash; contract.json#finish)
FI = C["finish"]
_FP, _FT, _FE, _FR, _FM, _FD = FI["paymentMethods"], FI["tips"], FI["earlyEnd"], FI["receipt"], FI["driverMoney"], FI["debt"]
_EED = C["configDefaults"]["earlyEnd"]
S["PaymentOption"] = obj({"method": ref("ZonePaymentMethod"), "status": s(enum=["available", "coming_soon"])}, ["method", "status"], "v0.18.10: " + _FP["served"])
for _doc in ("RiderAppConfig", "DriverAppConfig"):
    S[_doc]["properties"]["paymentOptions"] = arr(ref("PaymentOption"), description="v0.18.10: written by the server when it serves the document. " + _FP["served"] + " " + _FP["serverSupport"])
S["EarlyEndSettings"] = obj(OrderedDict([
    ("repriceOverKm", {**n("v0.18.10: " + _FE["driver"], minimum=_FE["settings"]["ranges"]["repriceOverKm"][0], maximum=_FE["settings"]["ranges"]["repriceOverKm"][1]), "default": _EED["repriceOverKm"]}),
    ("repriceOverMin", {**n(minimum=_FE["settings"]["ranges"]["repriceOverMin"][0], maximum=_FE["settings"]["ranges"]["repriceOverMin"][1]), "default": _EED["repriceOverMin"]}),
]), desc="v0.18.10: " + _FE["settings"]["where"])
S["CancelFees"]["properties"]["earlyEnd"] = {"allOf": [ref("EarlyEndSettings")], "description": "DriverAppConfig only. " + C["cancelFees"]["earlyEnd"]}
S["TipRules"] = obj(OrderedDict([("cashAfterTrip", {**b(), "default": False}), ("cashInCarMinutes", {**i(minimum=0, maximum=60), "default": 5}), ("customAmount", {**b(), "default": False}), ("customMax", ref("Money"))]), desc="v0.18.10: " + _FT["settings"])
S["RiderAppConfig"]["properties"]["tipRules"] = ref("TipRules")
S["CountryRules"]["properties"]["driverPayChangeMax"] = {"allOf": [ref("Money")], "description": "v0.18.10 checker: the largest single change of a driver's pay on a trip (POST /admin/trips/{tripId}/driver-pay). Default SE 1000 kr, FR 100 €."}
S["RatingTipError"] = obj({"code": s(), "reason": s(), "message": s()}, ["code", "reason"], "v0.18.10: " + _FT["withRating"])
S["Rating"]["properties"]["tipError"] = ref("RatingTipError")
S["TipMethod"] = s("v0.18.10: " + _FT["rules"], enum=_FP["values"])
S["TripTip"] = obj({"amount": ref("Money"), "method": ref("TipMethod"), "driverShare": {"allOf": [ref("Money")], "description": _FT["driverShare"]}, "at": ref("Timestamp")}, ["amount", "method", "at"], "v0.18.10: " + _FT["projection"])
S["TipRequest"] = obj({"amount": ref("Money"), "method": ref("TipMethod")}, ["amount", "method"], "v0.18.10: " + _FT["endpoint"] + " " + _FT["rules"])
S["RatingRequest"]["properties"]["tip"] = {"allOf": [ref("Money")], "description": "v0.18.10: rider only; " + _FT["endpoint"]}
S["RatingRequest"]["properties"]["tipMethod"] = {"allOf": [ref("TipMethod")], "description": "v0.18.10: with tip; default cash."}
op("post", "/trips/{tripId}/tip", "tipTrip", "Rider tips the driver (100 % to the driver)", ["rider"], "Rider · Booking", params=TID, body="TipRequest", ok=(201, "TripTip"), mutation=True,
   desc="v0.18.10: " + " ".join([_FT["endpoint"], _FT["rules"], _FT["driverShare"]]) + " Errors (reason): " + ", ".join(_FT["errors"]) + ", payment_method_off, payment_method_coming_soon.")
S["EarningsLine"] = obj({"code": s(enum=["trip", "pickup_pay", "bonus", "tip", "adjustment"]), "amount": ref("Money")}, ["code", "amount"], "v0.18.10: one line of driverTotal. " + _FM["rule"])
S["TripFinish"] = obj(OrderedDict([
    ("endedEarly", b()), ("endedBy", s(enum=["rider", "driver"])), ("reasonCode", s()), ("repriced", b("Driver ended early: the price was worked out again (more than repriceOverKm / repriceOverMin shorter).")),
    ("total", ref("Money")), ("cashToCollect", ref("Money")), ("driverTotal", {"allOf": [ref("Money")], "description": "Driver and admin views only."}),
    ("earningsBreakdown", arr(ref("EarningsLine"), description="Driver and admin views only.")), ("ratingAllowed", b("The viewer may still rate (its rating status is pending).")),
]), ["endedEarly", "total", "cashToCollect", "ratingAllowed"], "v0.18.10: " + _FE["projection"] + " " + _FE["rider"])
S["MoneySplit"] = obj({"riderPaid": ref("Money"), "driverTotal": ref("Money"), "movera": ref("Money"), "debtCollected": ref("Money"), "tip": ref("Money"), "refunded": ref("Money")},
                      ["riderPaid", "driverTotal", "movera", "debtCollected", "refunded"], "v0.18.10: admin view only. " + _FD["moneySplit"])
_TPP = S["TripProjection"]["properties"]
_TPP["tip"] = ref("TripTip")
_TPP["finish"] = ref("TripFinish")
_TPP["driverTotal"] = {"allOf": [ref("Money")], "description": "v0.18.10: driver and admin views. " + _FM["rule"]}
_TPP["earningsBreakdown"] = arr(ref("EarningsLine"), description="v0.18.10: driver and admin views.")
_TPP["driverAdjustments"] = {"allOf": [ref("Money")], "description": "v0.18.10: driver and admin views: Movera's changes to the driver's pay on this trip (driver-pay, refunds taken from the driver)."}
_TPP["debtCollected"] = {"allOf": [ref("Money")], "description": "v0.18.10: driver and admin views. " + _FD["rule"]}
_TPP["moneySplit"] = ref("MoneySplit")
_TPP["sosAvailable"] = b("v0.18.10: " + FI["safety"]["projection"])
_CP = S["CompletePreview"]["properties"]
_CP["driverTotal"] = {"allOf": [ref("Money")], "description": "v0.18.10: " + _FM["rule"]}
_CP["earningsBreakdown"] = arr(ref("EarningsLine"))
_CP["repriced"] = b("v0.18.10: " + _FE["driver"])
_CP["shortKm"] = n("v0.18.10: booked km − km on board (early end only).")
_CP["shortMin"] = n("v0.18.10: booked minutes − minutes on board (early end only).")
S["ReceiptRefund"] = obj({"refundId": ref("Id"), "amount": ref("Money"), "at": ref("Timestamp")}, ["refundId", "amount", "at"])
S["Receipt"] = obj(OrderedDict([
    ("tripId", ref("Id")), ("issuedAt", ref("Timestamp")), ("zoneId", ref("Id")), ("country", ref("CountryCode")), ("currency", ref("CurrencyCode")), ("categoryId", ref("CategoryId")),
    ("pickup", ref("Place")), ("dropoff", ref("Place")), ("stops", arr(ref("Place"))), ("paymentMethod", ref("PaymentMethod")), ("fareLines", arr(ref("FareLine"))), ("total", ref("Money")),
    ("walletPaid", ref("Money")), ("cashPaid", ref("Money")), ("debtIncluded", ref("Money")), ("tip", obj({"amount": ref("Money"), "method": ref("TipMethod")}, ["amount", "method"])),
    ("refunds", arr(ref("ReceiptRefund"))), ("refunded", ref("Money")), ("endedEarly", b()), ("endedBy", s(enum=["rider", "driver"])), ("endedEarlyReason", s()), ("distanceMeters", i(minimum=0)),
]), ["tripId", "issuedAt", "zoneId", "country", "currency", "paymentMethod", "fareLines", "total", "refunds", "refunded", "endedEarly"], "v0.18.10: " + _FR["fields"] + " " + _FR["endedEarly"])
op("get", "/trips/{tripId}/receipt", "tripReceipt", "The receipt of the rider's ended trip", ["rider"], "Rider · Booking", params=TID, ok=(200, "Receipt"), desc="v0.18.10: " + _FR["rider"])
op("get", "/driver/trips/{tripId}/receipt", "driverTripReceipt", "The receipt of the driver's ended trip", ["driver"], "Driver · Trip", params=TID, ok=(200, "Receipt"), desc="v0.18.10: " + _FR["rider"])
op("get", "/admin/trips/{tripId}/receipt", "adminTripReceipt", "The receipt of an ended trip", ["admin"], "Admin · Trips", params=TID, ok=(200, "Receipt"), permission="trips.read", desc="v0.18.10: " + _FR["rider"])
S["ReceiptResendCommand"] = obj({"reason": s(minLength=1, maxLength=1000)}, ["reason"])
S["ReceiptResent"] = obj({"tripId": ref("Id"), "notificationId": ref("Id"), "sentAt": ref("Timestamp")}, ["tripId", "notificationId", "sentAt"])
op("post", "/admin/trips/{tripId}/receipt/resend", "adminResendReceipt", "Send the receipt to the rider again", ["admin"], "Admin · Trips", params=TID, body="ReceiptResendCommand", ok=(200, "ReceiptResent"), mutation=True, permission="trips.intervene", desc="v0.18.10: " + _FR["resend"])
S["DriverPayCommand"] = obj({"change": {"allOf": [ref("Money")], "description": "Signed, not 0: + pays the driver more, − takes back."}, "reason": s(minLength=1, maxLength=1000)}, ["change", "reason"])
op("post", "/admin/trips/{tripId}/driver-pay", "adminChangeDriverPay", "Change the driver's pay for an ended trip (audited)", ["admin"], "Admin · Trips", params=TID, body="DriverPayCommand", ok=(200, TP), mutation=True, permission="finance.edit", desc="v0.18.10: " + _FM["payChange"])
PATHS["/admin/trips/{tripId}/refund"]["post"]["description"] = PATHS["/admin/trips/{tripId}/refund"]["post"].get("description", "") + " v0.18.10: " + FI["refund"]["existing"]
PATHS["/trips"]["post"]["description"] = PATHS["/trips"]["post"].get("description", "") + " v0.18.10: " + _FP["booking"]
PATHS["/trips/{tripId}/end-early"]["post"]["description"] = PATHS["/trips/{tripId}/end-early"]["post"].get("description", "") + " v0.18.10: " + _FE["rider"]

# --- v0.18.13 (live clean-up 1, audit 2026-11-02): smart late rule, rider trip pushes, payout schedule + one currency,
# driving-time limits on the server, driver cancel reasons from the admin, refund endpoints, no fleet %, payment kill-switch.
_HC, _DL, _RTP, _PS = C["pickupWaiting"]["headingCheck"], C["drivingLimits"], C["riderTripPush"], C["payouts"]["schedule"]
_HCD, _DLD = C["configDefaults"]["headingCheck"], C["configDefaults"]["drivingLimits"]
S["HeadingCheckSettings"] = obj({
    "on": {**b("The smart late rule is used in this zone (off: after the free minutes the normal cancel fee applies)."), "default": _HCD["on"]},
    "headingPct": {**n("Heading to pickup = at least this % of the progress normal road speed allows.", minimum=50, maximum=100), "default": _HCD["headingPct"]},
    "notHeadingMinutes": {**n("Not heading for this many minutes in a row → free rider cancel (and reassign when on).", minimum=1, maximum=30), "default": _HCD["notHeadingMinutes"]},
    "reassign": {**b(_HC["reassign"]), "default": _HCD["reassign"]},
}, desc="v0.18.13: " + _HC["note"] + " " + _HC["setting"])
S["DriverAppConfig"]["properties"]["headingCheck"] = ref("HeadingCheckSettings")
S["DriverAppConfig"]["properties"]["drivingLimits"] = obj({
    "maxHoursPerDay": {**n("Counted driving hours (to the pickup + on trip) before no new offers; 0 = no limit.", minimum=0, maximum=24), "default": _DLD["maxHoursPerDay"]},
    "restMinutes": {**n(_DL["restMinutes"], minimum=0), "default": _DLD["restMinutes"]},
    "resetAfterOfflineHours": {**n("v0.18.13: hours offline in a row after which the counter starts again.", minimum=1, maximum=24), "default": _DLD["resetAfterOfflineHours"]},
}, desc="v0.18.13: " + _DL["note"] + " " + _DL["enforced"])
S["DriverAppConfig"]["properties"]["cancelReasons"]["description"] += " v0.18.13: " + C["pickupWaiting"]["cancelReasons"]
S["TripHeadingCheck"] = obj({"heading": b("The latest check: the driver is heading to the pickup."), "checkedAt": ref("Timestamp"),
                              "notHeadingSince": {"allOf": [ref("Timestamp")], "description": "Since when the checks say not heading (absent while heading)."},
                              "freeCancel": b("A rider cancel now is free because of this rule.")},
                             ["heading", "checkedAt", "freeCancel"], "v0.18.13: " + _HC["projection"] + " " + _HC["riderCancel"])
S["TripProjection"]["properties"]["headingCheck"] = ref("TripHeadingCheck")
S["DrivingTime"] = obj({"drivenMinutes": i(minimum=0), "maxMinutes": i("0 = no limit.", minimum=0), "reached": b(),
                         "resetAfterOfflineHours": n(minimum=0), "canDriveAt": ref("Timestamp")},
                        ["drivenMinutes", "maxMinutes", "reached", "resetAfterOfflineHours"], "v0.18.13: " + _DL["projection"])
S["Driver"]["properties"]["drivingTime"] = ref("DrivingTime")
PATHS["/driver/availability"]["post"]["description"] = (PATHS["/driver/availability"]["post"].get("description", "") + " v0.18.13: " + _DL["enforced"]).strip()
PATHS["/trips/{tripId}/cancel"]["post"]["description"] += " v0.18.13: " + _HC["riderCancel"] + " " + C["pickupWaiting"]["cancelReasons"]
S["PayoutSchedule"] = obj({"frequency": s(enum=["weekly", "every_2_weeks"], default=_PS["default"]["frequency"]),
                            "day": s(enum=["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], default=_PS["default"]["day"]),
                            "time": s("Local time HH:MM.", pattern=r"^([01]\d|2[0-3]):[0-5]\d$", default=_PS["default"]["time"])},
                           ["frequency", "day", "time"], "v0.18.13: " + _PS["note"])
S["CountryRules"]["properties"]["payoutSchedule"] = {"allOf": [ref("PayoutSchedule")], "description": "v0.18.13: read from the country standard only (a zone's own rules do not change it)."}
S["Payout"]["description"] = (S["Payout"].get("description", "") + " v0.18.13: " + C["payouts"]["currency"]).strip()
# Refunds the server already served (audit M4): the rider's choice and the admin's Swish / bank list.
S["RefundDestination"] = s("wallet (back to the Movera wallet at once), swish (SE only) or bank.", enum=["wallet", "swish", "bank"])
S["RiderRefund"] = obj({"refundId": ref("Id"), "tripId": ref("Id"), "amount": ref("Money"), "reason": s(), "status": ref("RefundStatus"),
                         "destination": {"oneOf": [ref("RefundDestination"), {"type": "null"}], "description": "null until the rider chooses."},
                         "payoutStatus": {"oneOf": [s(enum=["pending", "paid"]), {"type": "null"}], "description": "Swish / bank only: pending until an admin marks it paid."},
                         "payoutTo": s("Masked account, e.g. Swish ••4567, Bank ••1234."), "paidAt": ref("Timestamp"), "createdAt": ref("Timestamp"),
                         "choices": arr(ref("RefundDestination"), description="While destination is null: what the rider may choose (SE wallet, swish, bank; FR wallet, bank).")},
                        ["refundId", "tripId", "amount", "reason", "status", "destination", "payoutStatus", "createdAt"], "The rider's view of a refund done for one of his trips.")
S["RiderRefundPage"] = obj({"items": arr(ref("RiderRefund")), "nextCursor": {"oneOf": [s(), {"type": "null"}]}}, ["items", "nextCursor"], "The newest 100; nextCursor is always null.")
S["SwedishBankAccount"] = obj({"clearingNumber": s(pattern=r"^\d{4,5}$"), "accountNumber": s(pattern=r"^\d{6,12}$"), "holderName": s(minLength=2, maxLength=120)}, ["clearingNumber", "accountNumber", "holderName"])
S["IbanBankAccount"] = obj({"iban": s("Spaces allowed; stored upper case without spaces."), "bic": s(pattern=r"^[A-Z0-9]{8}([A-Z0-9]{3})?$"), "holderName": s(minLength=2, maxLength=120)}, ["iban", "holderName"])
S["RefundDestinationCommand"] = obj({"method": ref("RefundDestination"), "swish": obj({"phone": s(pattern=r"^\+46\d{7,10}$")}, ["phone"]),
                                      "bank": {"oneOf": [ref("SwedishBankAccount"), ref("IbanBankAccount")], "description": "SE: clearing + account number; other countries: IBAN."}},
                                     ["method"], "One choice per refund. wallet: credited at once. swish (+46 number, SE only) / bank: payoutStatus pending until an admin pays it. Errors: 404 refund_not_found, 409 destination_chosen, 400 method_not_available, bank_details_invalid.")
S["RefundPayoutItem"] = obj(OrderedDict(list(S["RiderRefund"]["properties"].items()) + [
    ("riderId", ref("Id")), ("riderName", s()), ("riderPhone", s()),
    ("payoutTo", {"type": "object", "description": "The full account so the admin can send the money: { swish: { phone } } or { bank: SwedishBankAccount | IbanBankAccount }."})]),
    ["refundId", "tripId", "amount", "status", "riderId"], "Admin: one Swish / bank refund to pay by hand.")
S["RefundPayoutPage"] = obj({"items": arr(ref("RefundPayoutItem")), "nextCursor": {"oneOf": [s(), {"type": "null"}]}}, ["items", "nextCursor"], "Oldest first, at most 200, only the admin's zones; nextCursor is always null.")
S["RefundPaidCommand"] = obj({"note": s(maxLength=1000)})
op("get", "/rider/refunds", "listRiderRefunds", "The rider's refunds and where each one goes", ["rider"], "Rider · Payments", ok=(200, "RiderRefundPage"),
   desc="v0.18.13 (audit M4: served since v0.18.10, now in the paths). " + C["finish"]["refund"]["existing"] if "refund" in C["finish"] else "v0.18.13 (audit M4).")
op("post", "/rider/refunds/{refundId}/destination", "chooseRefundDestination", "Choose where a refund goes (wallet, Swish, bank)", ["rider"], "Rider · Payments",
   params=[{"name": "refundId", "in": "path", "required": True, "schema": ref("Id")}], body="RefundDestinationCommand", ok=(200, "RiderRefund"), mutation=True,
   desc="v0.18.13 (audit M4: served since v0.18.10, now in the paths).")
op("get", "/admin/refunds/payouts", "adminRefundPayouts", "Swish / bank refunds to pay by hand", ["admin"], "Admin · Money",
   params=[{"name": "payoutStatus", "in": "query", "required": False, "schema": s(enum=["pending", "paid"], default="pending")}], ok=(200, "RefundPayoutPage"), permission="finance.read",
   desc="v0.18.13 (audit M4: served since v0.18.10, now in the paths).")
op("post", "/admin/refunds/{refundId}/paid", "adminMarkRefundPaid", "Mark a Swish / bank refund as paid", ["admin"], "Admin · Money",
   params=[{"name": "refundId", "in": "path", "required": True, "schema": ref("Id")}], body="RefundPaidCommand", ok=(200, "Refund"), mutation=True, permission="finance.edit",
   desc="v0.18.13 (audit M4: served since v0.18.10, now in the paths). 409 conflict reason already_paid or no_payout (the rider has not chosen Swish or bank). Written in the audit (refund.paid).")

# ---------------------------------------------------------------- v0.18.14 (deep fix round 1, fix list 2026-11-02)
_CL = C["countryLimits"]
S["CountryLimits"] = obj(OrderedDict([(k, {**i(_CL["fields"][k] + f" Range {_CL['ranges'][k][0]}–{_CL['ranges'][k][1]}.", minimum=_CL["ranges"][k][0], maximum=_CL["ranges"][k][1]), "default": _CL["defaults"][k]}) for k in _CL["defaults"]]), (), "v0.18.14: " + _CL["note"])
S["CountryRules"]["properties"]["limits"] = {"allOf": [ref("CountryLimits")], "description": "v0.18.14: read from the country standard only."}
S["DriverAppConfig"]["properties"]["offers"]["properties"]["autoOffline"]["properties"]["on"] = {**b("v0.18.14 (g1-g3 M8): false = the server never sets a driver of this zone offline for missed offers nor for no position (missedExclusive and noFixMinutes are then ignored). Default true."), "default": True}
_RCP = C["onTrip"]["routeChange"]["driverPush"]
PATHS["/trips/{tripId}"]["patch"]["description"] = (PATHS["/trips/{tripId}"]["patch"].get("description", "") + " v0.18.14: " + _RCP["note"]).strip()
_D1 = C["deepFix1"]
PATHS["/driver/earnings"]["get"]["parameters"].append(q("currency", {"type": "string", "pattern": "^[A-Z]{3}$"}, "v0.18.14: the report's currency (default the driver's first zone's)."))
S["EarningsReport"]["properties"]["currency"] = s("v0.18.14: every amount of this report is in it.", pattern="^[A-Z]{3}$")
S["EarningsReport"]["properties"]["currencies"] = arr(s(pattern="^[A-Z]{3}$"), description="v0.18.14: " + _D1["earnings"])
S["Vehicle"]["properties"]["active"] = b("v0.18.14 (GET /driver/vehicles): this is the driver's active car. " + _D1["vehicles"])
S["LegalTexts"]["properties"]["company"] = {"allOf": [ref("LegalCompany")], "description": "v0.18.14: " + _D1["legal"]}
PATHS["/notifications"]["get"]["description"] = (PATHS["/notifications"]["get"].get("description", "") + " v0.18.14: " + _D1["notifications"]).strip()
PATHS["/auth/refresh"]["post"]["description"] = (PATHS["/auth/refresh"]["post"].get("description", "") + " v0.18.14: " + _D1["signIn"]).strip()
S["AccountPhoneChange"] = obj({"phone": ref("PhoneE164")}, ["phone"])
S["AccountPhoneVerify"] = obj({"phone": ref("PhoneE164"), "sessionId": ref("Id"), "code": s(pattern=r"^[0-9]{%d}$" % AU["otp"]["codeLength"])}, ["phone", "sessionId", "code"])
S["AccountEmailChange"] = obj({"email": s(maxLength=200)}, ["email"])
S["AccountEmailChallenge"] = obj({"challengeId": ref("Id"), "expiresAt": ref("Timestamp"), "delivery": s(enum=["pending_provider", "sent"])}, ["challengeId", "expiresAt", "delivery"])
S["AccountEmailVerify"] = obj({"challengeId": ref("Id"), "code": s()}, ["challengeId", "code"])
S["SignInUnlock"] = obj({"phone": ref("PhoneE164")}, ["phone"])
op("post", "/admin/auth/sign-in-locks/unlock", "unlockSignIn", "Lift a number's wrong-code lock", ["admin"], "Admin · Auth", body="SignInUnlock", ok=(200, None), desc="v0.18.14: " + AU["otp"]["note"])
op("post", "/account/phone/change", "startPhoneChange", "Change my phone number: send a code to the new one", ["rider", "driver"], "Account", body="AccountPhoneChange", ok=(200, "OtpChallenge"), desc="v0.18.14: " + _D1["accountChange"])
op("post", "/account/phone/verify", "verifyPhoneChange", "Save the new phone number with its code", ["rider", "driver"], "Account", body="AccountPhoneVerify", ok=(200, None), desc="v0.18.14: " + _D1["accountChange"])
op("post", "/account/email/change", "startEmailChange", "Change my e-mail: send a code to the new one", ["rider", "driver"], "Account", body="AccountEmailChange", ok=(200, "AccountEmailChallenge"), desc="v0.18.14: " + _D1["accountChange"])
op("post", "/account/email/verify", "verifyEmailChange", "Save the new e-mail with its code", ["rider", "driver"], "Account", body="AccountEmailVerify", ok=(200, None), desc="v0.18.14: " + _D1["accountChange"])
